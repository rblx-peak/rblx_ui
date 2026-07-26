--!strict
-- "What's new" modal. One §7.4 card holding a version/date line, a scrolling
-- body of TAGGED groups, and a footer carrying the DON'T SHOW AGAIN toggle and
-- CLOSE.
--
-- A group is a coloured tag chip (NEW green / IMPROVED blue / FIXED gold /
-- REMOVED red — the arcade palette's own semantics, doc §3.2) over a list of
-- bullet lines. Bullets are drawn as real dots, not glyphs, so no font has to
-- own a bullet character; the line text is white FredokaOne 20 with RichText
-- LEFT ON, which is what lets patch copy bold a feature name mid-sentence.
--
-- The body rebuilds from data on every Show (groups are pure input), so the
-- screen is a function of Show{ version, date, groups, onDismiss } and renders
-- a real changelog standalone from the demo set below.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIToggleComponent = require(script.Parent.Parent.Components.UIToggleComponent)

local PatchNotesScreen = setmetatable({}, { __index = UIScreenBase })
PatchNotesScreen.__index = PatchNotesScreen

-- Fixed px at the 1650×1020 baseline. Content = card − the §7.4 insets.
local CARD = Vector2.new(880, 660)
local HEAD_H = 36
local FOOTER_H = 56
local TAG_W = 128
local TAG_H = 30
local BULLET_INDENT = 26
local BULLET_SIZE = 9
local LINE_SIZE = 20

local TAG_ORDER = { "NEW", "IMPROVED", "FIXED", "REMOVED" }

local function tagColor(theme: Types.UITheme, tag: string): Color3
	local arcade = theme.Arcade
	local map: { [string]: Color3 } = {
		NEW = arcade.Green,
		IMPROVED = arcade.Blue,
		FIXED = arcade.Gold,
		REMOVED = arcade.Red,
	}
	return map[string.upper(tag)] or arcade.Panel
end

local DEMO_VERSION = "v1.4.0"
local DEMO_DATE = "24 JUL 2026"
local DEMO_GROUPS = {
	{
		tag = "NEW",
		lines = {
			"The <b>Spin Wheel</b> is live in the lobby — one free spin every 6 hours.",
			"Twelve new chair skins in the gallery, including two <b>Golden</b> variants.",
			"Trades now show both players' confirm state live, so nobody guesses.",
		},
	},
	{
		tag = "IMPROVED",
		lines = {
			"Shop cards open noticeably faster: viewport models stream 3 per frame.",
			"Blocked buttons now explain themselves instead of going quiet.",
			"Leaderboards remember where you were scrolled between openings.",
		},
	},
	{
		tag = "FIXED",
		lines = {
			"Daily rewards no longer claim the wrong day when you play past midnight.",
			"Nameplates stop bleeding through walls at long range.",
			"The pause menu no longer swallows the first click after a respawn.",
		},
	},
	{
		tag = "REMOVED",
		lines = {
			"Retired the legacy Rustic and Sci-Fi theme packs.",
		},
	},
}

function PatchNotesScreen.new()
	local self = UIScreenBase.new("PatchNotesScreen", 12)
	self._dontShow = false
	self._onDismiss = nil :: ((dontShowAgain: boolean) -> ())?
	return setmetatable(self, PatchNotesScreen)
end

function PatchNotesScreen:_Close()
	local dismiss = self._onDismiss
	self.ScreenController:HideScreen("patchNotes")
	if dismiss then
		task.spawn(dismiss, self._dontShow)
	end
end

-- One bullet line: a real dot plus a wrapped RichText line. The row auto-sizes
-- on Y off its tallest child, so a three-line entry pushes the list down
-- instead of clipping.
local function buildLine(theme: Types.UITheme, parent: Instance, order: number, text: string)
	local row = UIStyler.Frame("Line")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.LayoutOrder = order
	row.ZIndex = 44
	row.Parent = parent

	-- Dots are one of the arcade's sanctioned round shapes (doc §4.2).
	local dot = UIStyler.Frame("Dot")
	dot.BackgroundColor3 = theme.Arcade.SunburstGold
	dot.BackgroundTransparency = 0
	dot.Position = UDim2.fromOffset(6, 9)
	dot.Size = UDim2.fromOffset(BULLET_SIZE, BULLET_SIZE)
	dot.ZIndex = 45
	UIChrome.Corner("Arcade", "Pill").Parent = dot
	dot.Parent = row

	local label = UIChrome.Text("Text", LINE_SIZE, theme.Colors.TextPrimary)
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Position = UDim2.fromOffset(BULLET_INDENT, 0)
	label.Size = UDim2.new(1, -BULLET_INDENT, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.ZIndex = 45
	label.Parent = row
end

-- One tagged group: the chip, then its lines.
local function buildGroup(theme: Types.UITheme, parent: Instance, order: number, tag: string, lines: { string })
	local group = UIStyler.Frame("Group_" .. tag)
	group.BackgroundTransparency = 1
	group.Size = UDim2.new(1, 0, 0, 0)
	group.AutomaticSize = Enum.AutomaticSize.Y
	group.LayoutOrder = order
	group.ZIndex = 43
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, 8),
	}).Parent = group
	group.Parent = parent

	local chip = UIStyler.Frame("Tag")
	chip.BackgroundColor3 = tagColor(theme, tag)
	chip.BackgroundTransparency = 0
	chip.Size = UDim2.fromOffset(TAG_W, TAG_H)
	chip.LayoutOrder = 0
	chip.ZIndex = 44
	UIChrome.Stroke(theme, "Arcade").Parent = chip
	UIChrome.ArcadeBevel().Parent = chip
	chip.Parent = group

	local chipLabel = UIChrome.Text("Label", 18, theme.Colors.TextPrimary)
	chipLabel.RichText = false
	chipLabel.Text = string.upper(tag)
	chipLabel.Size = UDim2.fromScale(1, 1)
	chipLabel.ZIndex = 45
	chipLabel.Parent = chip

	for index, line in lines do
		buildLine(theme, group, index, line)
	end
end

function PatchNotesScreen:_Render(version: string, date: string, groups: { any })
	local theme = self:GetTheme()
	-- Groups are pure input: wipe and rebuild rather than diffing.
	for _, child in self._body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	self._version.Text = version
	self._date.Text = string.upper(date)

	local order = 0
	for _, group in groups do
		local lines = group.lines
		if type(lines) == "table" and #lines > 0 then
			order += 1
			buildGroup(theme, self._body, order, tostring(group.tag or "NEW"), lines)
		end
	end
	if order == 0 then
		local empty = UIChrome.Text("Empty", 22, theme.Studio.TextMuted)
		empty.Text = "Nothing new this time."
		empty.TextXAlignment = Enum.TextXAlignment.Left
		empty.Size = UDim2.new(1, 0, 0, 40)
		empty.ZIndex = 44
		empty.Parent = self._body
	end
end

function PatchNotesScreen:_BuildContent()
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "WHAT'S NEW",
		sizePx = CARD,
		onClose = function()
			self:_Close()
		end,
	})
	self._modal = modal
	local content = modal.content

	-- Version/date head line: gold version left, quiet date right.
	local version = UIChrome.Text("Version", 26, theme.Arcade.Gold)
	version.RichText = false
	version.Text = DEMO_VERSION
	version.TextXAlignment = Enum.TextXAlignment.Left
	version.Size = UDim2.new(0.5, 0, 0, HEAD_H)
	version.ZIndex = 43
	version.Parent = content
	self._version = version

	local date = UIChrome.BodyText("Date", 16, theme.Arcade.IceBlue)
	date.Text = DEMO_DATE
	date.TextXAlignment = Enum.TextXAlignment.Right
	date.AnchorPoint = Vector2.new(1, 0)
	date.Position = UDim2.fromScale(1, 0)
	date.Size = UDim2.new(0.5, 0, 0, HEAD_H)
	date.ZIndex = 43
	date.Parent = content
	self._date = date

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Notes"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, HEAD_H + 10)
	scroll.Size = UDim2.new(1, 0, 1, -(HEAD_H + 10 + FOOTER_H + 10))
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Arcade.Gold
	scroll.ZIndex = 43
	scroll.Parent = content
	self._scroll = scroll

	-- Inner body keeps the list layout off the ScrollingFrame itself, so the
	-- 10px right gutter for the scrollbar is a padding, not a per-row inset.
	local body = UIStyler.Frame("Body")
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, -12, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.ZIndex = 43
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, 20),
	}).Parent = body
	body.Parent = scroll
	self._body = body

	local footer = UIStyler.Frame("Footer")
	footer.BackgroundTransparency = 1
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.fromScale(0, 1)
	footer.Size = UDim2.new(1, 0, 0, FOOTER_H)
	footer.ZIndex = 43
	footer.Parent = content

	self._toggle = UIToggleComponent.new()
	self._toggle:Create(footer, {
		label = "DON'T SHOW AGAIN",
		value = false,
		size = UDim2.fromOffset(320, 36),
		position = UDim2.fromScale(0, 0.5),
		anchorPoint = Vector2.new(0, 0.5),
		onChanged = function(value: boolean)
			self._dontShow = value
		end,
	})
	self._toggle.Root.ZIndex = 44

	self._closeButton = UIButtonComponent.new()
	self._closeButton:Create(footer, {
		text = "CLOSE",
		variant = "Green",
		size = UDim2.fromOffset(180, 48),
		position = UDim2.fromScale(1, 0.5),
		anchorPoint = Vector2.new(1, 0.5),
		onClick = function()
			self:_Close()
		end,
	})
	self._closeButton.Root.ZIndex = 44

	self:_Render(DEMO_VERSION, DEMO_DATE, DEMO_GROUPS)
end

-- Show{ version, date, groups = { { tag, lines } }, onDismiss }. Groups arrive
-- in caller order; a caller that hands us an unordered map of tag -> lines gets
-- the canonical NEW/IMPROVED/FIXED/REMOVED order instead.
function PatchNotesScreen:_OnShow(data: any?)
	local d = data or {}
	self._onDismiss = d.onDismiss

	local groups = d.groups
	if type(groups) ~= "table" then
		groups = DEMO_GROUPS
	elseif groups[1] == nil then
		local ordered = {}
		for _, tag in TAG_ORDER do
			local lines = (groups :: any)[tag]
			if type(lines) == "table" then
				table.insert(ordered, { tag = tag, lines = lines })
			end
		end
		groups = ordered
	end

	self._dontShow = false
	self._toggle:Set(false)
	self:_Render(d.version or DEMO_VERSION, d.date or DEMO_DATE, groups)
	self._scroll.CanvasPosition = Vector2.new(0, 0)
	UIChrome.PopIn(self:GetTheme(), self._modal.content)
end

function PatchNotesScreen:Destroy()
	if self._toggle then
		self._toggle:Destroy()
		self._toggle = nil
	end
	if self._closeButton then
		self._closeButton:Destroy()
		self._closeButton = nil
	end
	UIScreenBase.Destroy(self)
end

return PatchNotesScreen
