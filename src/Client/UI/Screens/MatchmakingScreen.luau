--!strict
-- MATCHMAKING queue pill — Overlay layer, NOT a modal (no dim, non-exclusive):
-- a compact top-centre card tucked under the HUD's top-centre band (doc §7.2:
-- phase bar y=14, secondary widget y=62 → this sits at y=96). Left: a slate
-- well with the house sunburst spinning behind a swords icon (doc §10). Right:
-- "FINDING MATCH", a 1Hz elapsed timer, the estimated wait line and a red
-- CANCEL.
--
-- When data flips found=true the card pulses and swaps to "MATCH FOUND!" with
-- an ACCEPT (green) / DECLINE (ghost) pair and a shrinking gold accept-window
-- ruler. Letting the window expire declines automatically and drops back to
-- searching — the queue pill never just vanishes without answering (§11.1).
-- Both states share ONE RenderStepped connection gated on UIChrome.IsOnScreen,
-- dropped in _OnHide/Destroy (§5.4).
--
-- Show(data) = { estimate, found, acceptWindow, onCancel, onAccept, onDecline }.

local RunService = game:GetService("RunService")

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIAssets = require(script.Parent.Parent.Config.UIAssets)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIProgressBarComponent = require(script.Parent.Parent.Components.UIProgressBarComponent)

local WHITE = Color3.new(1, 1, 1)

-- Fixed px at the 1650×1020 baseline.
local CARD_W = 480
local CARD_H = 150
local CARD_Y = 96
local WELL = 104
local RIGHT_X = 136
local RIGHT_W = CARD_W - RIGHT_X - 16

local DEFAULT_ESTIMATE = 45
local DEFAULT_WINDOW = 10

local MatchmakingScreen = setmetatable({}, { __index = UIScreenBase })
MatchmakingScreen.__index = MatchmakingScreen

function MatchmakingScreen.new()
	local self = UIScreenBase.new("MatchmakingScreen", 18)
	self._elapsed = 0
	self._estimate = DEFAULT_ESTIMATE :: number | string
	self._found = false
	self._acceptWindow = DEFAULT_WINDOW
	self._acceptRemaining = DEFAULT_WINDOW
	self._onCancel = nil :: (() -> ())?
	self._onAccept = nil :: (() -> ())?
	self._onDecline = nil :: (() -> ())?
	-- Demo fallback: with NO Show payload at all (no backend driving found),
	-- the queue "finds" a match once the elapsed timer reaches the estimate,
	-- so the found state is reachable standalone. Any payload disables this.
	self._demoMode = true
	self._tickConn = nil :: RBXScriptConnection?
	self._spinConn = nil :: RBXScriptConnection?
	self._accum = 0
	return setmetatable(self, MatchmakingScreen)
end

function MatchmakingScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function MatchmakingScreen:_BuildContent()
	local theme = self:GetTheme()

	local card = UIChrome.Panel(theme, "Arcade", "QueueCard")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, CARD_Y)
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.Parent = self.Root
	self._card = card

	-- Left: near-black well, spinning sunburst behind the swords (doc §10).
	local well = UIStyler.Frame("Well")
	well.BackgroundColor3 = theme.Arcade.NearBlack
	well.Position = UDim2.fromOffset(16, (CARD_H - WELL) // 2)
	well.Size = UDim2.fromOffset(WELL, WELL)
	well.ClipsDescendants = true
	UIChrome.Stroke(theme, "Arcade").Parent = well
	well.Parent = card

	local _burst, spin = UIAssets.SunburstBehind(well, WHITE, 0.7, 60)
	self._spinConn = spin

	local swords = IconArchive.Image(well, "swords", 56)
	swords.AnchorPoint = Vector2.new(0.5, 0.5)
	swords.Position = UDim2.fromScale(0.5, 0.5)
	swords.ZIndex = 3

	-- ---- searching state ----------------------------------------------

	local searching = UIStyler.Frame("Searching")
	searching.BackgroundTransparency = 1
	searching.Position = UDim2.fromOffset(RIGHT_X, 10)
	searching.Size = UDim2.fromOffset(RIGHT_W, CARD_H - 20)
	searching.Parent = card
	self._searchFrame = searching

	local title = UIChrome.Text("Title", 24, WHITE)
	title.Text = "FINDING MATCH"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(0, 4)
	title.Size = UDim2.fromOffset(RIGHT_W, 28)
	title.Parent = searching

	local elapsed = UIChrome.Text("Elapsed", 20, theme.Arcade.SunburstGold)
	elapsed.TextXAlignment = Enum.TextXAlignment.Left
	elapsed.Position = UDim2.fromOffset(0, 38)
	elapsed.Size = UDim2.fromOffset(RIGHT_W, 24)
	elapsed.Parent = searching
	self._elapsedLabel = elapsed

	local estimate = UIChrome.Text("Estimate", 16, theme.Arcade.IceBlue)
	estimate.TextXAlignment = Enum.TextXAlignment.Left
	estimate.Position = UDim2.fromOffset(0, 68)
	estimate.Size = UDim2.fromOffset(RIGHT_W - 130, 22)
	estimate.TextTruncate = Enum.TextTruncate.AtEnd
	estimate.Parent = searching
	self._estimateLabel = estimate

	self._cancelButton = UIButtonComponent.new()
	self._cancelButton:Create(searching, {
		text = self:_R("CANCEL"),
		variant = "Red",
		size = UDim2.fromOffset(120, 42),
		position = UDim2.new(1, -4, 1, -4),
		anchorPoint = Vector2.new(1, 1),
		onClick = function()
			self:_Cancel()
		end,
	})

	-- ---- found state --------------------------------------------------

	local found = UIStyler.Frame("Found")
	found.BackgroundTransparency = 1
	found.Position = UDim2.fromOffset(RIGHT_X, 10)
	found.Size = UDim2.fromOffset(RIGHT_W, CARD_H - 20)
	found.Visible = false
	found.Parent = card
	self._foundFrame = found

	local foundTitle = UIChrome.Text("Title", 24, theme.Arcade.Gold)
	foundTitle.Text = "MATCH FOUND!"
	foundTitle.TextXAlignment = Enum.TextXAlignment.Left
	foundTitle.Position = UDim2.fromOffset(0, 0)
	foundTitle.Size = UDim2.fromOffset(RIGHT_W - 74, 28)
	foundTitle.Parent = found

	local window = UIChrome.Text("Window", 22, theme.Arcade.SunburstGold)
	window.TextXAlignment = Enum.TextXAlignment.Right
	window.AnchorPoint = Vector2.new(1, 0)
	window.Position = UDim2.new(1, -4, 0, 2)
	window.Size = UDim2.fromOffset(70, 26)
	window.Parent = found
	self._windowLabel = window

	-- The shrinking accept-window ruler (gold, doc §8).
	self._acceptBar = UIProgressBarComponent.new()
	self._acceptBar:Create(found, {
		value = DEFAULT_WINDOW,
		maxValue = DEFAULT_WINDOW,
		size = UDim2.fromOffset(RIGHT_W, 12),
		position = UDim2.fromOffset(0, 36),
	})

	self._acceptButton = UIButtonComponent.new()
	self._acceptButton:Create(found, {
		text = self:_R("ACCEPT"),
		variant = "Green",
		size = UDim2.fromOffset(152, 46),
		position = UDim2.fromOffset(0, 62),
		onClick = function()
			self:_Accept()
		end,
	})

	self._declineButton = UIButtonComponent.new()
	self._declineButton:Create(found, {
		text = self:_R("DECLINE"),
		variant = "Ghost",
		size = UDim2.fromOffset(152, 46),
		position = UDim2.new(1, -4, 0, 62),
		anchorPoint = Vector2.new(1, 0),
		onClick = function()
			self:_Decline(false)
		end,
	})

	self:_RenderState()
end

function MatchmakingScreen:_EstimateText(): string
	if typeof(self._estimate) == "string" then
		return "~" .. (self._estimate :: string) .. " EST."
	end
	return "~" .. UIChrome.FormatCountdown(self._estimate :: number) .. " EST."
end

function MatchmakingScreen:_RenderState()
	self._searchFrame.Visible = not self._found
	self._foundFrame.Visible = self._found
	self._elapsedLabel.Text = "IN QUEUE  " .. UIChrome.FormatCountdown(self._elapsed)
	self._estimateLabel.Text = self:_EstimateText()
	if self._found then
		self._windowLabel.Text = UIChrome.FormatCountdown(self._acceptRemaining)
		self._acceptBar:Set(self._acceptRemaining, math.max(self._acceptWindow, 1))
	end
end

function MatchmakingScreen:_SetFound(found: boolean, pulse: boolean)
	self._found = found
	if found then
		self._acceptRemaining = self._acceptWindow
	end
	self:_RenderState()
	if pulse and self._card then
		UIChrome.Pulse(self:GetTheme(), self._card)
	end
end

function MatchmakingScreen:_Cancel()
	self:_Toast("MATCHMAKING CANCELLED", "Info")
	if self._onCancel then
		self._onCancel()
	end
	self.ScreenController:HideScreen("matchmaking")
end

function MatchmakingScreen:_Accept()
	self:_Toast("MATCH ACCEPTED — LOADING…", "Success")
	if self._onAccept then
		self._onAccept()
	end
	self.ScreenController:HideScreen("matchmaking")
end

-- Declining (by tap or by letting the window expire) drops back to searching:
-- the queue keeps running rather than silently disappearing.
function MatchmakingScreen:_Decline(expired: boolean)
	if self._onDecline then
		self._onDecline()
	end
	if expired then
		self:_Toast("ACCEPT WINDOW EXPIRED — BACK IN QUEUE", "Warning")
	else
		self:_Toast("MATCH DECLINED — BACK IN QUEUE", "Info")
	end
	self:_SetFound(false, false)
end

-- ONE frugal RenderStepped connection (doc §5.4): the queue timer ticks at
-- 1Hz while searching; the accept window counts down while found.
function MatchmakingScreen:_StartTicker()
	if self._tickConn then
		return
	end
	self._accum = 0
	self._tickConn = RunService.RenderStepped:Connect(function(dt: number)
		local card = self._card
		if not card or not UIChrome.IsOnScreen(card) then
			return
		end
		self._accum += dt
		if self._accum < 1 then
			return
		end
		self._accum -= 1
		if self._found then
			self._acceptRemaining = math.max(0, self._acceptRemaining - 1)
			self._windowLabel.Text = UIChrome.FormatCountdown(self._acceptRemaining)
			self._acceptBar:Set(self._acceptRemaining, math.max(self._acceptWindow, 1))
			if self._acceptRemaining <= 0 then
				self:_Decline(true)
			end
		else
			self._elapsed += 1
			self._elapsedLabel.Text = "IN QUEUE  " .. UIChrome.FormatCountdown(self._elapsed)
			if self._demoMode and typeof(self._estimate) == "number" and self._elapsed >= (self._estimate :: number) then
				self:_SetFound(true, true)
			end
		end
	end)
end

function MatchmakingScreen:_StopTicker()
	if self._tickConn then
		self._tickConn:Disconnect()
		self._tickConn = nil
	end
end

function MatchmakingScreen:_Ingest(data: any?)
	if not data then
		return
	end
	if data.estimate ~= nil then
		self._estimate = data.estimate
	end
	if data.acceptWindow then
		self._acceptWindow = data.acceptWindow
	end
	if data.onCancel then
		self._onCancel = data.onCancel
	end
	if data.onAccept then
		self._onAccept = data.onAccept
	end
	if data.onDecline then
		self._onDecline = data.onDecline
	end
end

function MatchmakingScreen:_OnShow(data: any?)
	self._demoMode = data == nil
	self:_Ingest(data)
	-- A fresh Show is a fresh queue: the elapsed timer restarts.
	self._elapsed = 0
	self:_SetFound(data ~= nil and data.found == true, false)
	self:_StartTicker()
	if self._card then
		UIChrome.PopIn(self:GetTheme(), self._card)
	end
end

function MatchmakingScreen:_OnHide()
	self:_StopTicker()
end

function MatchmakingScreen:Update(data: any)
	if not data then
		return
	end
	self._demoMode = false -- a backend is driving the queue now
	self:_Ingest(data)
	if not self._built then
		return
	end
	if data.found ~= nil and data.found ~= self._found then
		self:_SetFound(data.found == true, data.found == true)
	else
		self:_RenderState()
	end
end

function MatchmakingScreen:Destroy()
	self:_StopTicker()
	if self._spinConn then
		self._spinConn:Disconnect()
		self._spinConn = nil
	end
	if self._acceptBar then
		self._acceptBar:Destroy()
		self._acceptBar = nil
	end
	if self._cancelButton then
		self._cancelButton:Destroy()
		self._cancelButton = nil
	end
	if self._acceptButton then
		self._acceptButton:Destroy()
		self._acceptButton = nil
	end
	if self._declineButton then
		self._declineButton:Destroy()
		self._declineButton = nil
	end
	UIScreenBase.Destroy(self)
end

return MatchmakingScreen
