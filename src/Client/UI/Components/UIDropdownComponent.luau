--!strict
-- Labelled option picker (dropdown) for settings-style rows. Shows the current
-- option; clicking opens a themed list of choices below it. Emits onChanged with
-- the picked option id. Kept structurally like the toggle/slider so a settings
-- list of mixed controls stays visually consistent.
--
-- Pottery Clash arcade recipe (doc §4.1 / §4.3): the current-value box is a
-- slate Arcade.Panel plate — hard 90° corners, 3px black stroke, arcade bevel,
-- FredokaOne value text with the full black outline. The open list is an
-- Arcade.NearBlack2 well with the same black rim; option rows sit on Arcade.Row
-- fills that white-lerp on hover, and the SELECTED option is marked by the gold
-- selection ring (stroke-only — backgrounds never change on selection).
--
-- Extra props:
--   labelKey / label
--   options   : { { id: string, text: string } }
--   value     : id of the initial selection
--   onChanged : (id: string) -> ()

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local UIComponentBase = require(script.Parent.UIComponentBase)

-- Display font (doc §2): the style's display font for every control string.
-- Every label — including the arrow glyphs (▾/▴), which MUST carry an explicit
-- FontFace because the engine default (LegacyArial) has no symbol glyphs and
-- renders them invisibly — is assigned its theme font in _Style (the first
-- paint runs synchronously inside Create, so nothing renders unfonted).

local UIDropdownComponent = setmetatable({}, { __index = UIComponentBase })
UIDropdownComponent.__index = UIDropdownComponent

function UIDropdownComponent.new()
	local self = UIComponentBase.new("UIDropdown")
	self._options = {}
	self._optionButtons = {}
	self._optionCells = {}
	self._optionRings = {}
	self._open = false
	return setmetatable(self, UIDropdownComponent)
end

function UIDropdownComponent:_Build(props: Types.UIComponentProps)
	self._options = (props :: any).options or {}
	self._value = (props :: any).value or (self._options[1] and self._options[1].id)
	local root = self.Root
	root.BackgroundTransparency = 1
	if not props.size then
		root.Size = UDim2.new(1, 0, 0, 36)
		self._baseSize = root.Size
	end
	-- Overflow the open list beyond the row's own height.
	root.ClipsDescendants = false

	local label = UIStyler.TextLabel("Label")
	label.Size = UDim2.fromScale(0.55, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextScaled = true
	self._labelConstraint = UIStyler.TextSizeConstraint(16, 8)
	self._labelConstraint.Parent = label
	label.Text = TextConfig.Resolve(props.labelKey or props.label)
	label.Parent = root
	self._label = label

	-- Current-value button (right-aligned) — pure Scale fractions of Root,
	-- never a fixed pixel Offset. Arcade plate: hard corners + arcade bevel
	-- here; the 3px black stroke attaches with the theme in _Style.
	local current = Instance.new("TextButton")
	current.Name = "Current"
	current.AutoButtonColor = false
	current.Size = UDim2.fromScale(0.42, 0.78)
	current.AnchorPoint = Vector2.new(1, 0.5)
	current.Position = UDim2.new(1, 0, 0.5, 0)
	current.Text = ""
	current.ZIndex = 2
	UIChrome.Corner("Arcade").Parent = current
	self._currentBevel = UIChrome.ArcadeBevel()
	self._currentBevel.Parent = current
	UIStyler.PaddingXY(10, 0).Parent = current
	current.Parent = root
	self._current = current

	local currentText = UIStyler.TextLabel("Value")
	currentText.Size = UDim2.fromScale(0.75, 1)
	currentText.TextXAlignment = Enum.TextXAlignment.Left
	currentText.TextScaled = true
	self._currentTextConstraint = UIStyler.TextSizeConstraint(16, 8)
	self._currentTextConstraint.Parent = currentText
	currentText.ZIndex = 2
	currentText.Parent = current
	self._currentText = currentText

	-- Arrow glyph box is a perfect square (AspectRatioConstraint 1:1,
	-- DominantAxis Height) instead of a fixed pixel Offset, so it scales
	-- with `current`'s real resolved height. Starting size is non-zero on
	-- both axes (never Scale=0) — an AspectRatioConstraint driving a
	-- Scale=0 starting dimension collapses to 0x0 instead of resolving.
	local arrow = UIStyler.TextLabel("Arrow")
	arrow.Size = UDim2.fromScale(0.5, 0.5)
	arrow.AnchorPoint = Vector2.new(1, 0.5)
	arrow.Position = UDim2.new(1, 0, 0.5, 0)
	UIStyler.AspectRatio(1, Enum.DominantAxis.Height).Parent = arrow
	arrow.Text = "▾"
	arrow.TextScaled = true
	arrow.ZIndex = 2
	arrow.Parent = current
	self._arrow = arrow

	-- Option list (hidden until opened), drops below the current button.
	-- Near-black well, hard corners; its 3px black rim attaches in _Style.
	local list = UIStyler.Frame("Options")
	list.Visible = false
	list.AnchorPoint = Vector2.new(1, 0)
	list.Position = UDim2.new(1, 0, 0.5, 18)
	list.Size = UDim2.fromScale(0.42, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.ZIndex = 20
	UIChrome.Corner("Arcade").Parent = list
	UIStyler.Padding(4).Parent = list
	UIStyler.ListLayout({ Padding = UDim.new(0, 2) }).Parent = list
	list.Parent = root
	self._list = list

	-- The current box is the tap target. Its hover/press juice runs through
	-- the base §5.1 kit: a UIScale + white-lerp on the box itself (an inner
	-- surface of the fixed Root footprint), never a Size change.
	self:_UseScaleTarget(current)
	self:_SetHoverFill(current)
	self:_BindInteractions(current)
	self:_Connect(current.Activated, function()
		self:_Toggle()
	end)
	self:_RebuildOptions()
	self:_SyncCurrentText()
end

function UIDropdownComponent:_RebuildOptions()
	for _, cell in self._optionCells do
		cell:Destroy()
	end
	table.clear(self._optionCells)
	table.clear(self._optionButtons)
	table.clear(self._optionRings)
	for i, opt in self._options do
		-- Fixed-footprint cell: the layout child never moves; the button inside
		-- carries the hover UIScale so neighbouring rows never reflow.
		local cell = UIStyler.Frame("OptRow")
		cell.BackgroundTransparency = 1
		cell.Size = UDim2.new(1, 0, 0, 28)
		cell.LayoutOrder = i
		cell.ZIndex = 21
		cell.Parent = self._list

		local btn = Instance.new("TextButton")
		btn.Name = "opt_" .. opt.id
		btn.AutoButtonColor = false
		btn.Size = UDim2.fromScale(1, 1)
		btn.Text = opt.text
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.TextScaled = true
		local optConstraint = UIStyler.TextSizeConstraint(16, 8)
		optConstraint.Parent = btn
		btn.BackgroundTransparency = 1
		btn.ZIndex = 21
		UIChrome.Corner("Arcade").Parent = btn
		UIChrome.ArcadeBevel().Parent = btn
		UIStyler.PaddingXY(8, 0).Parent = btn
		btn.Parent = cell
		self:_Connect(btn.Activated, function()
			self:Set(opt.id, true)
			self:_Toggle()
		end)
		table.insert(self._optionCells, cell)
		table.insert(self._optionButtons, btn)
	end
end

function UIDropdownComponent:_Toggle()
	self._open = not self._open
	self._list.Visible = self._open
	self._arrow.Text = self._open and "▴" or "▾"
end

function UIDropdownComponent:Set(id: string, notify: boolean?)
	self._value = id
	self:_SyncCurrentText()
	if self.Theme then
		self:_Style(self.Theme)
	end
	if notify and self.Props.onChanged then
		self.Props.onChanged(id)
	end
end

function UIDropdownComponent:GetValue(): string
	return self._value
end

function UIDropdownComponent:_SyncCurrentText()
	for _, opt in self._options do
		if opt.id == self._value then
			self._currentText.Text = opt.text
			return
		end
	end
	self._currentText.Text = ""
end

function UIDropdownComponent:_Style(theme: Types.UITheme)
	local arcade = theme.Arcade
	local white = theme.Colors.TextPrimary

	-- Strokes need the theme, so they attach on first paint. The family
	-- policy (UIChrome) makes both the 3px black arcade rim.
	if not self._currentStroke then
		self._currentStroke = UIChrome.Stroke(theme, "Arcade", "Button")
		self._currentStroke.Parent = self._current
		self._listStroke = UIChrome.Stroke(theme, "Arcade", "Panel")
		self._listStroke.Parent = self._list
	end

	self._label.FontFace = theme.Fonts.Subtitle
	self._label.TextColor3 = white
	UIChrome.TextOutline(self._label)
	if self._labelConstraint then
		self._labelConstraint.MaxTextSize = theme.TextSizes.Body
	end

	self._current.BackgroundColor3 = arcade.Panel
	-- Effects toggle AND the style's bevel policy: a flat chrome
	-- (Chrome.Bevel = false) keeps the plate flat no matter what the
	-- Effects token says (same gate as UIButtonComponent's bevel).
	self._currentBevel.Enabled = theme.Effects.UseGradients and UIChrome.ActiveChrome().Bevel
	self._currentText.FontFace = theme.Fonts.Button
	self._currentText.TextColor3 = white
	UIChrome.TextOutline(self._currentText)
	if self._currentTextConstraint then
		self._currentTextConstraint.MaxTextSize = theme.TextSizes.Body
	end
	-- Same LegacyArial bug as the button icon fix: never assigning FontFace left
	-- this glyph (▾/▴) on the emoji/symbol-incapable engine default.
	self._arrow.FontFace = theme.Fonts.Button
	self._arrow.TextColor3 = white
	UIChrome.TextOutline(self._arrow)

	self._list.BackgroundColor3 = arcade.NearBlack2
	self._list.BackgroundTransparency = 0

	for _, btn in self._optionButtons do
		local optConstraint = btn:FindFirstChildOfClass("UITextSizeConstraint")
		if optConstraint then
			optConstraint.MaxTextSize = theme.TextSizes.Body
		end
		btn.FontFace = theme.Fonts.Button
		-- Every option sits on the same Row fill (hover white-lerps it); the
		-- SELECTED option is marked by the gold selection ring + gold label —
		-- selection is a ring, never a background change (doc §4.3).
		local selected = string.sub(btn.Name, 5) == self._value
		btn.BackgroundColor3 = arcade.Row
		btn.BackgroundTransparency = arcade.RowTransparency
		btn.TextColor3 = if selected then theme.Semantic.Selection else white
		-- Text emphasis AFTER the colour so a styled glow tracks the gold/white
		-- selection state (Classic: the same black outline, order-independent).
		UIChrome.TextOutline(btn)
		local ring = self._optionRings[btn]
		if not ring then
			ring = UIChrome.Stroke(theme, "Arcade", "Selection")
			ring.Parent = btn
			self._optionRings[btn] = ring
			-- First paint of this row: colours above are final, so the §5.1
			-- hover/press juice binds LAST (it re-snapshots the rest colour
			-- on every hover, so later repaints stay safe).
			UIChrome.Animate(theme, btn)
		end
		ring.Enabled = selected
	end
end

function UIDropdownComponent:Destroy()
	for _, cell in self._optionCells do
		cell:Destroy()
	end
	table.clear(self._optionCells)
	table.clear(self._optionButtons)
	table.clear(self._optionRings)
	UIComponentBase.Destroy(self)
end

return UIDropdownComponent
