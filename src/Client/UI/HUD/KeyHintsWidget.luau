--!strict
-- Contextual key hints (HUD widget): the bottom strip of "[KEY] Action" chips.
--
-- The whole strip REBUILDS per input mode (doc §11.7: the only per-device code
-- in this system is copy — hint strings and shortcut chips rebuild per input
-- type). Keyboard shows letters, a gamepad shows its face-button glyphs, touch
-- shows words, and swapping devices mid-session re-renders the row through
-- UserInputService.LastInputTypeChanged.

local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local HUDWidgetBase = require(script.Parent.HUDWidgetBase)
local GPHUDStyle = require(script.Parent.GPHUDStyle)

local KeyHintsWidget = setmetatable({}, { __index = HUDWidgetBase })
KeyHintsWidget.__index = KeyHintsWidget

local CHIP_H = 26
local KEY_H = 22
local KEY_TEXT = 14
local ACTION_TEXT = 15

-- Demo hints: one line per action, one label per device.
local DEMO_HINTS = {
	{ action = "Interact", keyboard = "E", gamepad = "A", touch = "TAP" },
	{ action = "Sprint", keyboard = "SHIFT", gamepad = "LS", touch = "HOLD" },
	{ action = "Inventory", keyboard = "TAB", gamepad = "Y", touch = "MENU" },
	{ action = "Map", keyboard = "M", gamepad = "X", touch = "SWIPE" },
}

function KeyHintsWidget.new()
	local self = HUDWidgetBase.new("keyHints", "KeyHintsWidget")
	self._hints = DEMO_HINTS
	self._chips = {} :: { GuiObject }
	self._mode = "keyboard"
	return setmetatable(self, KeyHintsWidget)
end

function KeyHintsWidget:_Build(props: HUDWidgetBase.Props)
	local row = UIStyler.Frame("Hints")
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 18),
	}).Parent = row
	row.Parent = self.Root
	self._row = row

	if props.hints then
		self._hints = props.hints
	end
	-- No _Rebuild here: Create calls ApplyTheme immediately after _Build, and
	-- this widget's repaint IS a rebuild — doing both would build twice.
	self._mode = self:_InputMode()

	self:_Connect(UserInputService.LastInputTypeChanged, function()
		local mode = self:_InputMode()
		if mode ~= self._mode then
			self._mode = mode
			self:_Rebuild()
		end
	end)
end

-- data: { hints = { {action, keyboard, gamepad, touch} } }
function KeyHintsWidget:Update(data: any)
	if type(data) ~= "table" then
		return
	end
	self:SetHints(data.hints or data)
end

function KeyHintsWidget:SetHints(hints: { any })
	self._hints = hints
	self:_Rebuild()
end

function KeyHintsWidget:_InputMode(): string
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "touch"
	elseif last.Name:sub(1, 7) == "Gamepad" then
		return "gamepad"
	end
	return "keyboard"
end

function KeyHintsWidget:_Rebuild()
	for _, chip in self._chips do
		chip:Destroy()
	end
	table.clear(self._chips)
	for index, hint in self._hints do
		local key = hint[self._mode]
		if key and key ~= "" then
			table.insert(self._chips, self:_BuildChip(index, tostring(key), hint.action or ""))
		end
	end
end

function KeyHintsWidget:_BuildChip(index: number, key: string, action: string): GuiObject
	local theme = self.Theme

	local chip = UIStyler.Frame("Hint" .. index)
	chip.BackgroundTransparency = 1
	chip.Size = UDim2.fromOffset(0, CHIP_H)
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.LayoutOrder = index
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
	}).Parent = chip
	chip.Parent = self._row

	-- The key cap width is COMPUTED from the glyph count rather than
	-- auto-sized: an AutomaticSize.X box wrapping an AutomaticSize.X label
	-- with padding is the unstable combination this codebase has already been
	-- bitten by (see UIBadgeComponent), and a key cap only ever holds 1–5
	-- characters, so the arithmetic is exact enough.
	local cap = UIStyler.Frame("Key")
	cap.BackgroundColor3 = theme.Arcade.NearBlack2
	cap.Size = UDim2.fromOffset(math.max(24, 12 + #key * 9), KEY_H)
	cap.LayoutOrder = 1
	UIChrome.Corner("Arcade").Parent = cap
	UIChrome.Stroke(theme, "Arcade", "Wheel").Parent = cap
	cap.Parent = chip

	local capText = UIChrome.Text("KeyText", KEY_TEXT, theme.Colors.TextPrimary)
	capText.Text = key
	capText.Size = UDim2.fromScale(1, 1)
	capText.ZIndex = 2
	capText.Parent = cap

	-- The action name sits on the world with no cap under it, so it takes the
	-- pack's light ink (see GPHUDStyle.SkyInk) — a halo can only lift a letter
	-- that is lighter than whatever is behind it.
	local label = UIChrome.Text("Action", ACTION_TEXT, GPHUDStyle.SkyInk(theme, theme.Arcade.IceBlue))
	label.Text = action
	label.Size = UDim2.fromOffset(0, CHIP_H)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.LayoutOrder = 2
	label.Parent = chip

	-- GIRLY POP: the key cap becomes a little petal-cornered clay tile, alternating
	-- along the strip by hint index. The LEGEND stays as authored — "E", "SHIFT",
	-- "TAP" are what is printed on the device, not body copy, so law 5 does not
	-- reach them — while the action beside it gets the pack's own halo so it can
	-- sit on the world with no plate under it at all.
	-- (This is the paint path: _Style rebuilds the whole strip, so the branch
	-- runs on every theme swap exactly like every other widget's _Style.)
	GPHUDStyle.Surface(theme, cap, {
		transparency = GPHUDStyle.Chip,
		petal = index,
		cornerIntent = "Panel",
		stroke = true,
		strokeIntent = "Wheel",
	})
	GPHUDStyle.Halo(theme, capText)
	GPHUDStyle.Halo(theme, label)

	return chip
end

function KeyHintsWidget:_Style(_theme: Types.UITheme)
	-- Chips are cheap and few: repainting them is a rebuild, which also keeps
	-- the computed key-cap widths correct if a theme ever changes the font.
	self:_Rebuild()
end

return KeyHintsWidget
