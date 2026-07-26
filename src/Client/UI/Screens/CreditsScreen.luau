--!strict
-- Scrolling credits (id "credits", hidesHUD — a focused moment, doc §11.5).
-- Full-bleed near-black backdrop, a centred column of credit groups (role
-- heading in gold FredokaOne 22, names in white 26) driven up the screen at
-- ~40 px/s by one RenderStepped connection, gated on UIChrome.IsOnScreen and
-- dropped in _OnHide/Destroy (§5.4). The roll ends with the game wordmark and
-- a thanks line, then closes itself.
--
-- SKIP is a ghost button bottom-right, and ANY input (key, click, tap, gamepad
-- button) skips too — the UserInputService connection lives only while shown.
-- Both paths funnel through _Finish, which fires once: onDone, then hide.
--
-- The end-of-roll test uses AbsolutePosition/AbsoluteSize (viewport px), not
-- the baseline offset, so it is correct at any UIScale/viewport.
--
-- Show(data) = { groups = { { role, names } }, onDone }.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)

type CreditGroup = { role: string, names: { string } }

-- Fixed px at the 1650×1020 baseline.
local SCROLL_SPEED = 40 -- px/s upward
local COLUMN_W = 900
local ROLE_H = 30
local ROLE_GAP = 8
local NAME_H = 34
local GROUP_GAP = 46
local WORDMARK = "POTTERY CLASH"
local THANKS = "THANKS FOR PLAYING"

local function demoGroups(): { CreditGroup }
	return {
		{ role = "GAME DIRECTION", names = { "M. Ashford" } },
		{ role = "PROGRAMMING", names = { "T. Okafor", "J. Reyes", "sable_dev" } },
		{ role = "UI DESIGN", names = { "The Pottery Clash UI Team" } },
		{ role = "ART & ICONS", names = { "Gvesster - Icon Pack v6" } },
		{ role = "MUSIC & SOUND", names = { "K. Lindqvist", "echo.wav" } },
		{ role = "QA & PLAYTESTING", names = { "The Kiln Crew", "Beta potters everywhere" } },
		{ role = "SPECIAL THANKS", names = { "Every player who spun the wheel", "You" } },
	}
end

local CreditsScreen = setmetatable({}, { __index = UIScreenBase })
CreditsScreen.__index = CreditsScreen

function CreditsScreen.new()
	local self = UIScreenBase.new("CreditsScreen", 23)
	self._groups = demoGroups()
	self._onDone = nil :: (() -> ())?
	self._offset = 0
	self._finished = false
	self._scrollConn = nil :: RBXScriptConnection?
	self._inputConn = nil :: RBXScriptConnection?
	return setmetatable(self, CreditsScreen)
end

function CreditsScreen:_BuildContent()
	local theme = self:GetTheme()

	-- Full-bleed near-black backdrop: the credits own the whole screen.
	local backdrop = UIStyler.Frame("Backdrop")
	backdrop.BackgroundColor3 = theme.Arcade.NearBlack
	backdrop.BackgroundTransparency = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 1
	backdrop.Parent = self.Root
	self._backdrop = backdrop

	local clipper = UIStyler.Frame("Clipper")
	clipper.BackgroundTransparency = 1
	clipper.ClipsDescendants = true
	clipper.Size = UDim2.fromScale(1, 1)
	clipper.ZIndex = 2
	clipper.Parent = self.Root

	-- The rolling column: anchored to the TRUE bottom edge via Position scale
	-- (doc §7.1 — scale-anchored positions stay glued to screen edges); the
	-- ticker drives the pixel offset negative to roll it upward.
	local column = UIStyler.Frame("Column")
	column.BackgroundTransparency = 1
	column.AnchorPoint = Vector2.new(0.5, 0)
	column.Position = UDim2.new(0.5, 0, 1, 0)
	column.Size = UDim2.fromOffset(COLUMN_W, 100)
	column.ZIndex = 3
	column.Parent = clipper
	self._column = column

	self._skip = UIButtonComponent.new()
	self._skip:Create(self.Root, {
		text = "SKIP",
		variant = "Ghost",
		size = UDim2.fromOffset(140, 52),
		anchorPoint = Vector2.new(1, 1),
		position = UDim2.new(1, -24, 1, -24),
		onClick = function()
			self:_Finish()
		end,
	})
	self._skip.Root.ZIndex = 5

	self:_RenderColumn()
end

function CreditsScreen:_RenderColumn()
	local theme = self:GetTheme()
	local column: Frame = self._column
	for _, child in column:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local y = 0
	for _, group in self._groups :: { CreditGroup } do
		local role = UIChrome.Text("Role", 22, theme.Arcade.Gold)
		role.Text = group.role
		role.Position = UDim2.fromOffset(0, y)
		role.Size = UDim2.fromOffset(COLUMN_W, ROLE_H)
		role.Parent = column
		y += ROLE_H + ROLE_GAP

		for _, name in group.names do
			local nameLabel = UIChrome.Text("Name", 26, theme.Colors.TextPrimary)
			nameLabel.Text = name
			nameLabel.Position = UDim2.fromOffset(0, y)
			nameLabel.Size = UDim2.fromOffset(COLUMN_W, NAME_H)
			nameLabel.Parent = column
			y += NAME_H
		end
		y += GROUP_GAP
	end

	y += 40
	local wordmark = UIChrome.Text("Wordmark", 54, theme.Arcade.Gold)
	wordmark.Text = WORDMARK
	wordmark.Position = UDim2.fromOffset(0, y)
	wordmark.Size = UDim2.fromOffset(COLUMN_W, 70)
	wordmark.Parent = column
	y += 84

	local thanks = UIChrome.Text("Thanks", 26, theme.Colors.TextPrimary)
	thanks.Text = THANKS
	thanks.Position = UDim2.fromOffset(0, y)
	thanks.Size = UDim2.fromOffset(COLUMN_W, NAME_H)
	thanks.Parent = column
	y += NAME_H + 60

	column.Size = UDim2.fromOffset(COLUMN_W, y)
end

function CreditsScreen:_StartScroll()
	if self._scrollConn then
		return
	end
	self._scrollConn = RunService.RenderStepped:Connect(function(dt: number)
		local backdrop = self._backdrop
		if not backdrop or not UIChrome.IsOnScreen(backdrop) then
			return
		end
		self._offset -= SCROLL_SPEED * dt
		local column: Frame = self._column
		column.Position = UDim2.new(0.5, 0, 1, self._offset)
		-- Done when the column's bottom clears the top of the viewport.
		if column.AbsolutePosition.Y + column.AbsoluteSize.Y < 0 then
			self:_Finish()
		end
	end)
end

function CreditsScreen:_StopScroll()
	if self._scrollConn then
		self._scrollConn:Disconnect()
		self._scrollConn = nil
	end
end

-- One exit for all three paths (SKIP, any input, roll completed): fires
-- onDone exactly once, then hides. The SKIP click also raises InputBegan, so
-- the guard is what keeps that from double-firing.
function CreditsScreen:_Finish()
	if self._finished then
		return
	end
	self._finished = true
	local onDone = self._onDone
	self.ScreenController:HideScreen("credits")
	if onDone then
		task.spawn(onDone)
	end
end

function CreditsScreen:_OnShow(data: any?)
	if data then
		if data.groups then
			self._groups = data.groups
		end
		if data.onDone then
			self._onDone = data.onDone
		end
	end
	self._finished = false
	self._offset = 0
	self:_RenderColumn()
	self._column.Position = UDim2.new(0.5, 0, 1, 0)
	self:_StartScroll()

	-- Any input skips. InputBegan covers keys, clicks, taps and gamepad
	-- buttons (never mouse movement); connected only while shown.
	if self._inputConn then
		self._inputConn:Disconnect()
	end
	self._inputConn = UserInputService.InputBegan:Connect(function()
		self:_Finish()
	end)

	UIChrome.PopIn(self:GetTheme(), self._skip.Root)
end

function CreditsScreen:_OnHide()
	self:_StopScroll()
	if self._inputConn then
		self._inputConn:Disconnect()
		self._inputConn = nil
	end
end

function CreditsScreen:Update(data: any)
	if not data then
		return
	end
	if data.groups then
		self._groups = data.groups
		if self._built then
			self:_RenderColumn()
		end
	end
	if data.onDone then
		self._onDone = data.onDone
	end
end

function CreditsScreen:Destroy()
	self:_OnHide()
	if self._skip then
		self._skip:Destroy()
		self._skip = nil
	end
	UIScreenBase.Destroy(self)
end

return CreditsScreen
