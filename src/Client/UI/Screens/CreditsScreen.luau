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
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)

type CreditGroup = { role: string, names: { string } }

-- GP never shouts (pack law 5). The credit ROLES, the wordmark and the thanks
-- line arrive here as arcade all-caps from data; the SAME strings are retitled
-- for DISPLAY only — no caller, config or data is touched. The rule itself
-- lives in the KIT so this pack has exactly ONE of them: "UI DESIGN" reads
-- "UI Design" here and everywhere else (GPLayoutKit.TitleCase).
local gpTitleCase = GPLayoutKit.TitleCase

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
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
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

-- ---- GIRLY POP (theme.LayoutKit == "GP") ------------------------------
-- The roll on the pack's own paper: a full-bleed warm cream sheet with clay
-- speckle instead of the near-black sheet, and the calm STUDIO dialect (no
-- glaze, no sparkle) because this is 90 seconds of reading. Role headings
-- become petal chips alternating rose/matcha by index — the pack's twin colour
-- masses, hand-arranged rather than stamped — over ink names on cream.
--
-- Same field names as classic (_backdrop/_column/_skip), same scroll ticker,
-- same end-of-roll test, same _Finish paths.
function CreditsScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	self._gpShadows = {}

	local paper = theme.Colors.Background
	local backdrop = UIStyler.Frame("Backdrop")
	backdrop.BackgroundColor3 = paper
	backdrop.BackgroundTransparency = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 1
	backdrop.Parent = self.Root
	self._backdrop = backdrop

	local studio = ((theme :: any).DialectTokens or {}).studio or {}
	local grain = GPLayoutKit.Tile(
		theme,
		studio.patternKey or "speckle",
		GPLayoutKit.Deepen(theme, paper, 1),
		studio.speckleTransparency or 0.94,
		"ClayGrain"
	)
	grain.ZIndex = 1
	grain.Parent = backdrop

	local clipper = UIStyler.Frame("Clipper")
	clipper.BackgroundTransparency = 1
	clipper.ClipsDescendants = true
	clipper.Size = UDim2.fromScale(1, 1)
	clipper.ZIndex = 2
	clipper.Parent = self.Root

	local column = UIStyler.Frame("Column")
	column.BackgroundTransparency = 1
	column.AnchorPoint = Vector2.new(0.5, 0)
	column.Position = UDim2.new(0.5, 0, 1, 0)
	column.Size = UDim2.fromOffset(COLUMN_W, 100)
	column.ZIndex = 3
	column.Parent = clipper
	self._column = column

	-- SKIP is a shim answering the two members the screen uses on it (.Root for
	-- the pop-in, :Destroy() in Destroy) — the pack has no button builder and
	-- UIButtonComponent would frame this in a BLACK stroke under GP.
	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.BackgroundTransparency = 1
	skip.Text = ""
	skip.AutoButtonColor = false
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -24, 1, -24)
	skip.Size = UDim2.fromOffset(140, 52)
	skip.ZIndex = 5
	skip.Parent = self.Root

	local skipFill = theme.Colors.Surface
	local skipChip = UIStyler.Frame("Chip")
	skipChip.BackgroundColor3 = skipFill
	skipChip.BackgroundTransparency = 0
	skipChip.Size = UDim2.fromScale(1, 1)
	skipChip.ZIndex = 5
	skipChip.Parent = skip
	GPLayoutKit.Petal(theme, skipChip, 0)
	GPLayoutKit.SoftStroke(theme, skipChip, skipFill)
	GPLayoutKit.Shadow(theme, skipChip, "sm", self._gpShadows, skipFill)

	local skipLabel = GPLayoutKit.Text(theme, 20, theme.Colors.TextPrimary, "Label")
	skipLabel.Text = "Skip"
	skipLabel.Size = UDim2.fromScale(1, 1)
	skipLabel.ZIndex = 6
	skipLabel.Parent = skipChip
	skip.Activated:Connect(function()
		self:_Finish()
	end)
	UIChrome.Animate(theme, skip, skipChip)
	self._skip = {
		Root = skip,
		Destroy = function(_self: any)
			skip:Destroy()
		end,
	} :: any

	self:_RenderColumn()
end

-- The GP roll, group for group and name for name — nothing is dropped or
-- summarised (pack law 6). Role chips alternate petal/mirror AND rose/matcha by
-- index; a sage squiggle rules off each group.
function CreditsScreen:_GPRenderColumn()
	local theme = self:GetTheme()
	local column: Frame = self._column
	for _, child in column:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local y = 0
	for index, group in self._groups :: { CreditGroup } do
		local chipFill = if index % 2 == 1 then theme.Colors.Primary else theme.Colors.Secondary
		-- The label IS the chip: auto-sized on X and centred in the column.
		local role = GPLayoutKit.Text(theme, 22, theme.Colors.TextPrimary, "Role")
		role.BackgroundColor3 = chipFill
		role.BackgroundTransparency = 0
		role.Text = gpTitleCase(group.role)
		role.AutomaticSize = Enum.AutomaticSize.X
		role.AnchorPoint = Vector2.new(0.5, 0)
		role.Position = UDim2.new(0.5, 0, 0, y)
		role.Size = UDim2.fromOffset(0, ROLE_H + 6)
		role.Parent = column
		UIStyler.PaddingXY(18, 0).Parent = role
		GPLayoutKit.Petal(theme, role, index)
		GPLayoutKit.SoftStroke(theme, role, chipFill)
		y += ROLE_H + 6 + ROLE_GAP

		for _, name in group.names do
			local nameLabel = GPLayoutKit.Text(theme, 26, theme.Colors.TextPrimary, "Name")
			nameLabel.Text = name
			nameLabel.Position = UDim2.fromOffset(0, y)
			nameLabel.Size = UDim2.fromOffset(COLUMN_W, NAME_H)
			nameLabel.Parent = column
			y += NAME_H
		end

		-- A sage squiggle rules off the group. Fixed 16px: the kit sizes the
		-- strip full-width off the art's own tile height, and AbsoluteSize is
		-- still zero this frame, so the height is written explicitly.
		local rule = GPLayoutKit.Divider(theme, column)
		rule.AnchorPoint = Vector2.new(0.5, 0)
		rule.Position = UDim2.new(0.5, 0, 0, y + 12)
		rule.Size = UDim2.fromOffset(320, 16)
		y += GROUP_GAP
	end

	y += 40
	local wordmark = GPLayoutKit.Text(theme, 54, theme.Colors.TextPrimary, "Wordmark")
	wordmark.Text = gpTitleCase(WORDMARK)
	wordmark.Position = UDim2.fromOffset(0, y)
	wordmark.Size = UDim2.fromOffset(COLUMN_W, 70)
	wordmark.Parent = column
	y += 84

	local thanks = GPLayoutKit.Text(theme, 26, theme.Colors.TextPrimary, "Thanks")
	thanks.Text = gpTitleCase(THANKS)
	thanks.Position = UDim2.fromOffset(0, y)
	thanks.Size = UDim2.fromOffset(COLUMN_W, NAME_H)
	thanks.Parent = column
	y += NAME_H + 60

	column.Size = UDim2.fromOffset(COLUMN_W, y)
end

-- A style rebuild destroys the Gui, but the UIShadow BUDGET only falls when a
-- handle is released — hand the GP skip chip's shadow back here.
function CreditsScreen:_OnTeardown()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
end

function CreditsScreen:_RenderColumn()
	if self:LayoutKit() == "GP" then
		self:_GPRenderColumn()
		return
	end
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
