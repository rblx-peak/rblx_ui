--!strict
-- SPECTATOR chrome — HUD layer, non-exclusive. A bottom-centre strip: PREV /
-- NEXT arrow buttons flanking the spectated player card (round avatar, name,
-- a small live stat line, and a gold "2/6" position chip), then a FREE CAM
-- toggle (gold = active, doc §3.3 selection colour) and a red EXIT. A boxless
-- outlined "SPECTATING" tag floats at the top centre in ice blue — world-style
-- text, no box (doc §8 toast grammar).
--
-- Player switching calls the injected onSwitch(delta) AND cycles the local
-- index so the strip stays alive with no backend; Update(data) re-renders the
-- card from fresh data. The card is rebuilt per switch (headshot fetch runs
-- off-thread with the flat-cartoon icon as the resting art, doc §10).
--
-- Show(data) = { players, index, freecam, onSwitch, onFreecam, onExit }.

local Players = game:GetService("Players")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)

type SpectatedPlayer = { userId: number, name: string, kills: number?, deaths: number?, score: number? }

local WHITE = Color3.new(1, 1, 1)

-- Fixed px at the 1650×1020 baseline. Strip 760×96, bottom-centre.
local STRIP_W = 760
local STRIP_H = 96
local STRIP_Y = -18
local CARD_X = 76
local CARD_W = 360
local CARD_H = 72

local DEMO_PLAYERS: { SpectatedPlayer } = {
	{ userId = 1, name = "ClayCrusher", kills = 7, deaths = 2, score = 1240 },
	{ userId = 156, name = "KilnKing", kills = 5, deaths = 4, score = 980 },
	{ userId = 2, name = "GlazeGoblin", kills = 3, deaths = 1, score = 760 },
	{ userId = 3, name = "WheelWitch", kills = 9, deaths = 6, score = 1815 },
	{ userId = 1101, name = "MugMerchant", kills = 1, deaths = 5, score = 340 },
	{ userId = 55, name = "TerracottaTom", kills = 4, deaths = 4, score = 890 },
}

local function formatNumber(n: number): string
	local formatted = tostring(math.floor(n))
	while true do
		local replaced: number
		formatted, replaced = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return formatted
end

local function avatarCircle(theme: Types.UITheme, parent: Instance, userId: number, sizePx: number): Frame
	local holder = UIStyler.Frame("Avatar")
	holder.BackgroundColor3 = theme.Arcade.NearBlack
	holder.Size = UDim2.fromOffset(sizePx, sizePx)
	holder.ClipsDescendants = true
	UIChrome.Corner("Arcade", "Pill").Parent = holder
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = holder
	holder.Parent = parent

	local glyph = IconArchive.Image(holder, "player", math.floor(sizePx * 0.62))
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)

	local photo = Instance.new("ImageLabel")
	photo.Name = "Headshot"
	photo.BackgroundTransparency = 1
	photo.ScaleType = Enum.ScaleType.Crop
	photo.Size = UDim2.fromScale(1, 1)
	photo.Visible = false
	photo.Parent = holder

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and typeof(content) == "string" and content ~= "" and holder.Parent then
			photo.Image = content
			photo.Visible = true
			glyph.Visible = false
		end
	end)

	return holder
end

local SpectatorScreen = setmetatable({}, { __index = UIScreenBase })
SpectatorScreen.__index = SpectatorScreen

function SpectatorScreen.new()
	local self = UIScreenBase.new("SpectatorScreen", 3)
	self._players = DEMO_PLAYERS :: { SpectatedPlayer }
	self._index = 1
	self._freecam = false
	self._onSwitch = nil :: ((delta: number) -> ())?
	self._onFreecam = nil :: ((enabled: boolean) -> ())?
	self._onExit = nil :: (() -> ())?
	return setmetatable(self, SpectatorScreen)
end

function SpectatorScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function SpectatorScreen:_BuildContent()
	local theme = self:GetTheme()

	-- Boxless top tag (doc §8): outlined FredokaOne floating over the scene.
	local tag = UIChrome.Text("SpectatingTag", 28, theme.Arcade.IceBlue)
	tag.Text = "SPECTATING"
	tag.AnchorPoint = Vector2.new(0.5, 0)
	tag.Position = UDim2.new(0.5, 0, 0, 14)
	tag.Size = UDim2.fromOffset(360, 34)
	tag.Parent = self.Root
	self._tag = tag

	local strip = UIChrome.Panel(theme, "Arcade", "SpectatorStrip")
	strip.AnchorPoint = Vector2.new(0.5, 1)
	strip.Position = UDim2.new(0.5, 0, 1, STRIP_Y)
	strip.Size = UDim2.fromOffset(STRIP_W, STRIP_H)
	strip.Parent = self.Root
	self._strip = strip

	self._prevButton = UIButtonComponent.new()
	self._prevButton:Create(strip, {
		iconId = IconArchive.Id("arrowLeft"),
		variant = "Blue",
		size = UDim2.fromOffset(56, CARD_H),
		position = UDim2.fromOffset(12, 12),
		onClick = function()
			self:_Switch(-1)
		end,
	})

	-- The spectated player card: contents rebuilt per switch.
	local card = UIStyler.Frame("PlayerCard")
	card.BackgroundColor3 = theme.Arcade.NearBlack2
	card.BackgroundTransparency = 0
	card.Position = UDim2.fromOffset(CARD_X, 12)
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	UIChrome.Stroke(theme, "Arcade").Parent = card
	UIChrome.GlassGradient().Parent = card
	card.Parent = strip
	self._card = card

	self._nextButton = UIButtonComponent.new()
	self._nextButton:Create(strip, {
		iconId = IconArchive.Id("arrowRight"),
		variant = "Blue",
		size = UDim2.fromOffset(56, CARD_H),
		position = UDim2.fromOffset(444, 12),
		onClick = function()
			self:_Switch(1)
		end,
	})

	self._freecamButton = UIButtonComponent.new()
	self._freecamButton:Create(strip, {
		text = "FREE CAM",
		variant = "Ghost",
		size = UDim2.fromOffset(132, CARD_H),
		position = UDim2.fromOffset(512, 12),
		onClick = function()
			self:_ToggleFreecam()
		end,
	})

	self._exitButton = UIButtonComponent.new()
	self._exitButton:Create(strip, {
		text = self:_R("EXIT"),
		variant = "Red",
		size = UDim2.fromOffset(92, CARD_H),
		position = UDim2.fromOffset(656, 12),
		onClick = function()
			self:_Exit()
		end,
	})

	self:_RenderCard()
end

function SpectatorScreen:_Current(): SpectatedPlayer?
	return self._players[self._index]
end

function SpectatorScreen:_RenderCard()
	local theme = self:GetTheme()
	local card = self._card :: Frame
	for _, child in card:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local player = self:_Current()
	if not player then
		local empty = UIChrome.Text("Empty", 18, theme.Arcade.GreyOwned)
		empty.Text = "NOBODY TO SPECTATE"
		empty.Size = UDim2.fromScale(1, 1)
		empty.Parent = card
		return
	end

	local avatar = avatarCircle(theme, card, player.userId, 52)
	avatar.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Position = UDim2.new(0, 10, 0.5, 0)

	local name = UIChrome.Text("Name", 22, WHITE)
	name.RichText = false
	name.Text = player.name
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(74, 8)
	name.Size = UDim2.fromOffset(CARD_W - 74 - 66, 26)
	name.Parent = card

	-- Small live stat line, ice blue secondary note (doc §3.2).
	local stats = UIChrome.Text("Stats", 15, theme.Arcade.IceBlue)
	stats.Text = string.format(
		"K %d  •  D %d  •  %s PTS",
		player.kills or 0,
		player.deaths or 0,
		formatNumber(player.score or 0)
	)
	stats.TextXAlignment = Enum.TextXAlignment.Left
	stats.Position = UDim2.fromOffset(74, 40)
	stats.Size = UDim2.fromOffset(CARD_W - 74 - 66, 20)
	stats.Parent = card

	local position = UIChrome.Text("Index", 15, theme.Arcade.Gold)
	position.Text = string.format("%d/%d", self._index, #self._players)
	position.TextXAlignment = Enum.TextXAlignment.Right
	position.AnchorPoint = Vector2.new(1, 0)
	position.Position = UDim2.new(1, -10, 0, 8)
	position.Size = UDim2.fromOffset(52, 20)
	position.Parent = card
end

function SpectatorScreen:_Switch(delta: number)
	if #self._players == 0 then
		self:_Toast("NOBODY TO SPECTATE", "Error")
		return
	end
	self._index = ((self._index - 1 + delta) % #self._players) + 1
	self:_RenderCard()
	UIChrome.Pulse(self:GetTheme(), self._card)
	if self._onSwitch then
		self._onSwitch(delta)
	end
end

function SpectatorScreen:_ToggleFreecam()
	self._freecam = not self._freecam
	self:_SyncFreecamButton()
	if self._onFreecam then
		self._onFreecam(self._freecam)
	end
	if self._freecam then
		self:_Toast("FREE CAM ON — FLY ANYWHERE", "Info")
	else
		local player = self:_Current()
		self:_Toast(if player then "FOLLOWING " .. string.upper(player.name) else "FREE CAM OFF", "Info")
	end
end

-- Gold = active (doc §3.3 selection colour); ghost = resting toggle.
function SpectatorScreen:_SyncFreecamButton()
	self._freecamButton:SetContent({
		text = "FREE CAM",
		variant = if self._freecam then "Gold" else "Ghost",
	})
end

function SpectatorScreen:_Exit()
	if self._onExit then
		self._onExit()
	end
	self:_Toast("SPECTATOR MODE CLOSED", "Info")
	self.ScreenController:HideScreen("spectator")
end

function SpectatorScreen:_Ingest(data: any?)
	if not data then
		return
	end
	if data.players then
		self._players = data.players
	end
	if data.index then
		self._index = math.clamp(data.index, 1, math.max(1, #self._players))
	end
	if data.freecam ~= nil then
		self._freecam = data.freecam == true
	end
	if data.onSwitch then
		self._onSwitch = data.onSwitch
	end
	if data.onFreecam then
		self._onFreecam = data.onFreecam
	end
	if data.onExit then
		self._onExit = data.onExit
	end
end

function SpectatorScreen:_OnShow(data: any?)
	self:_Ingest(data)
	self:_RenderCard()
	self:_SyncFreecamButton()
	UIChrome.PopIn(self:GetTheme(), self._strip)
end

function SpectatorScreen:Update(data: any)
	self:_Ingest(data)
	if self._built then
		self:_RenderCard()
		self:_SyncFreecamButton()
	end
end

function SpectatorScreen:Destroy()
	if self._prevButton then
		self._prevButton:Destroy()
		self._prevButton = nil
	end
	if self._nextButton then
		self._nextButton:Destroy()
		self._nextButton = nil
	end
	if self._freecamButton then
		self._freecamButton:Destroy()
		self._freecamButton = nil
	end
	if self._exitButton then
		self._exitButton:Destroy()
		self._exitButton = nil
	end
	UIScreenBase.Destroy(self)
end

return SpectatorScreen
