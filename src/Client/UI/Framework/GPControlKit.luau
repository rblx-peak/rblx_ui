--!strict
-- GPControlKit — the INTERACTIVE furniture of the "GP" layout language.
--
-- GPLayoutKit ships the STATIC composition of the pack (Page / Card / Tabs /
-- StatRow / PricePill / Glaze / Scallop / Petal / Shadow). What it does not
-- ship is the everyday control set — button, toggle, slider, text field, meter,
-- empty slot — and every GP screen needs it. This module is that set, composed
-- entirely from GPLayoutKit so there is exactly ONE implementation of the pack's
-- rules rather than one per screen.
--
-- WHY THESE CANNOT SIMPLY BE THE SHARED COMPONENTS. Two framework paths paint
-- pure black under this pack, and pack law 1 forbids pure black outright:
--   1. UIChrome.Stroke: GirlyPopTheme.Chrome sets StrokeFollowsAccent = false,
--      and the styled branch resolves that to BLACK @ 0.35 for every family and
--      every intent except "Selection". UIButtonComponent, UISliderComponent,
--      UIToggleComponent, UIProgressBarComponent and UIBadgeComponent all route
--      their rims through it.
--   2. UIStyleEnforcer: its Arcade sweep backstops any SOLID GuiButton that has
--      no UIStroke with a BLACK 2px border.
-- Both are avoided the same way GPLayoutKit.Page avoids them: the GuiButton
-- itself stays TRANSPARENT (so the enforcer never matches it) and the fill rides
-- a chip CHILD whose rim comes from GPLayoutKit.SoftStroke — a 2px rounded-join
-- stroke in a deepened tint of the fill it frames. A transparent button is also
-- why every control here is a button-plus-chip pair rather than a painted
-- TextButton.
--
-- THE LAWS THIS MODULE KEEPS SO CALLERS CANNOT BREAK THEM:
--   * No pure black, no pure white. Ink is Colors.TextPrimary; "white" is
--     Colors.Background. Every Frame is painted explicitly (UIStyler.Frame is
--     born pure white and UIStyler.TextLabel is born pure-white text).
--   * Shadows are hue-matched — GPLayoutKit.Shadow derives the colour from the
--     host's own fill — and every handle lands in a caller-owned sink so
--     GPLayoutKit.ReleaseShadows can hand the budget back on teardown.
--   * Copy passes through VERBATIM. No string.upper anywhere in this file.
--   * Body copy on a pastel fill is TextPrimary. Colors.TextOnPrimary measures
--     2.14:1 on rose and never appears here.
--   * DIMMED IS NOT DEAD (doc §11.1): a dimmed control keeps its Activated
--     wiring and its full press juice, so the tap still answers. Callers dim to
--     say "not yet", never to stop the conversation.
--
-- 0.4 BOUNDARY: static composition plus direct property assignment, exactly
-- like GPLayoutKit. The one delegated exception is hover/press juice, which
-- goes through UIChrome.Animate so there is a single implementation of it.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local GPLayoutKit = require(script.Parent.GPLayoutKit)

local GPControlKit = {}

-- ---- house geometry ----------------------------------------------------

local BUTTON_H = 44
local CHIP_H = 30
local TOGGLE_TRACK_W = 56
local TOGGLE_TRACK_H = 26
local TOGGLE_KNOB = 20
local SLIDER_TRACK_H = 10
local SLIDER_KNOB = 22
local METER_TRACK_H = 10
local FIELD_H = 44
-- A dimmed control fades toward the paper without leaving it; it must still
-- read as a control, because it is still live.
local DIM_FILL_TRANSPARENCY = 0.45

-- ---- local helpers -----------------------------------------------------

-- Always painted: UIStyler.Frame is born PURE WHITE, which this pack forbids.
local function surface(name: string, fill: Color3, transparency: number?): Frame
	local frame = UIStyler.Frame(name)
	frame.BackgroundColor3 = fill
	frame.BackgroundTransparency = transparency or 0
	return frame
end

-- The transparent hit target every control in this file is built on. See the
-- enforcer note in the header for why it may never carry a fill.
local function hitButton(name: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	return button
end

local function place(gui: GuiObject, opts: { position: UDim2?, anchorPoint: Vector2?, size: UDim2?, layoutOrder: number?, zIndex: number? })
	if opts.position then
		gui.Position = opts.position
	end
	if opts.anchorPoint then
		gui.AnchorPoint = opts.anchorPoint
	end
	if opts.size then
		gui.Size = opts.size
	end
	if opts.layoutOrder then
		gui.LayoutOrder = opts.layoutOrder
	end
	if opts.zIndex then
		gui.ZIndex = opts.zIndex
	end
end

-- ========================================================================
-- Icon
-- ========================================================================

-- The boxless archive icon, made safe for this pack.
--
-- IconArchive.Image renders an ImageLabel when the art is uploaded and an
-- outlined FredokaOne GLYPH when it is not — and that glyph is born PURE WHITE
-- with a PURE BLACK text stroke, both of which pack law 1 forbids outright. Any
-- GP surface that calls IconArchive.Image directly will therefore violate the
-- pack the moment an asset is missing, which is exactly the case a fallback
-- exists for. This wrapper repaints the fallback into pack ink, drops the black
-- outline and moves it onto the pack's display face; art-backed icons pass
-- through untouched unless a tint is asked for.
function GPControlKit.Icon(theme: Types.UITheme, parent: Instance?, key: string, sizePx: number, tint: Color3?, query: any?): GuiObject
	local icon = IconArchive.Image(parent, key, sizePx, query)
	if icon:IsA("TextLabel") then
		local label = icon :: TextLabel
		label.FontFace = theme.Fonts.Title
		label.TextColor3 = tint or theme.Colors.TextPrimary
		label.TextStrokeTransparency = 1
	elseif tint and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
		(icon :: any).ImageColor3 = tint
	end
	return icon
end

-- Recolour an icon this kit (or IconArchive) already built, whichever kind of
-- object came back. Mirrors the local `tint` helper several screens carry.
function GPControlKit.TintIcon(icon: GuiObject, color: Color3)
	if icon:IsA("ImageLabel") or icon:IsA("ImageButton") then
		(icon :: any).ImageColor3 = color
	elseif icon:IsA("TextLabel") then
		(icon :: TextLabel).TextColor3 = color
	end
end

-- ========================================================================
-- Button
-- ========================================================================

export type Button = {
	Root: TextButton,
	chip: Frame,
	label: TextLabel,
	-- An ImageLabel when the art is uploaded, a re-inked glyph TextLabel when
	-- it is not (see GPControlKit.Icon).
	icon: GuiObject?,
	SetContent: (any, { [string]: any }) -> (),
	Destroy: (any) -> (),
}

-- Petal-cornered action chip. `index` picks Petal vs PetalMirror so a row of
-- buttons reads hand-arranged; pass `pill = true` for a capsule instead.
--
-- SetContent mirrors the shared UIButtonComponent's contract closely enough for
-- a screen to swap one for the other without touching its call sites: it takes
-- { text, fill, dimmed } and repaints in place. The shadow retints with the
-- fill, which is the pack's rule shown in an interactive state.
function GPControlKit.Button(theme: Types.UITheme, parent: Instance, opts: {
	text: string,
	fill: Color3?,
	iconKey: string?,
	iconPx: number?,
	textSize: number?,
	pill: boolean?,
	index: number?,
	dimmed: boolean?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	onClick: (() -> ())?,
	sink: { any }?,
}): Button
	local spacing = theme.Spacing
	local fill = opts.fill or theme.Colors.Primary

	local root = hitButton("GPButton")
	root.Size = opts.size or UDim2.new(1, 0, 0, BUTTON_H)
	place(root, opts)
	root.Parent = parent

	local chip = surface("Chip", fill, 0)
	chip.Size = UDim2.fromScale(1, 1)
	chip.ZIndex = root.ZIndex
	chip.Parent = root
	if opts.pill then
		UIStyler.Corner(theme.Radii.Pill).Parent = chip
	else
		GPLayoutKit.Petal(theme, chip, opts.index or 0)
	end
	local stroke = GPLayoutKit.SoftStroke(theme, chip, fill)
	local shadow = GPLayoutKit.Shadow(theme, chip, "sm", opts.sink, fill)

	local textX = spacing.S
	local icon: GuiObject? = nil
	if opts.iconKey then
		local px = opts.iconPx or 24
		local art = GPControlKit.Icon(theme, chip, opts.iconKey, px)
		art.AnchorPoint = Vector2.new(0, 0.5)
		art.Position = UDim2.new(0, spacing.M, 0.5, 0)
		art.ZIndex = chip.ZIndex + 1
		icon = art
		textX = spacing.M + px + spacing.S
	end

	-- TextPrimary on every pastel fill: the near-white TextOnPrimary measures
	-- 2.14:1 on rose and is illegal for anything but large display text on a
	-- deepened tint.
	local label = GPLayoutKit.BodyText(theme, opts.textSize or theme.TextSizes.Button, theme.Colors.TextPrimary, "Label")
	label.Text = opts.text -- verbatim: this pack never shouts
	label.TextXAlignment = if icon then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Position = UDim2.fromOffset(textX, 0)
	label.Size = UDim2.new(1, -(textX + spacing.S), 1, 0)
	label.ZIndex = chip.ZIndex + 1
	label.Parent = chip

	local control: Button
	local function repaint(dimmed: boolean, nextFill: Color3)
		chip.BackgroundColor3 = nextFill
		chip.BackgroundTransparency = if dimmed then DIM_FILL_TRANSPARENCY else 0
		local deep = GPLayoutKit.Deepen(theme, nextFill, 1)
		stroke.Color = deep
		shadow.Instance.Color = deep
		-- A dimmed chip is paler, so its ink steps back with it — but never to
		-- a grey: TextSecondary is the pack's soft plum.
		label.TextColor3 = if dimmed then theme.Colors.TextSecondary else theme.Colors.TextPrimary
		if icon then
			-- The archive hands back an ImageLabel OR a glyph TextLabel; fade
			-- whichever arrived.
			local fade = if dimmed then 0.4 else 0
			if icon:IsA("ImageLabel") then
				(icon :: ImageLabel).ImageTransparency = fade
			elseif icon:IsA("TextLabel") then
				(icon :: TextLabel).TextTransparency = fade
			end
		end
	end
	repaint(opts.dimmed == true, fill)

	local currentFill = fill
	control = {
		Root = root,
		chip = chip,
		label = label,
		icon = icon,
		SetContent = function(_self: any, props: { [string]: any })
			if props.text ~= nil then
				label.Text = props.text
			end
			if props.fill ~= nil then
				currentFill = props.fill
			end
			repaint(props.dimmed == true, currentFill)
		end,
		-- The instance owns everything else; Destroy exists so a screen can hold
		-- this in the same field it used to hold a shared component and keep its
		-- teardown loop unchanged.
		Destroy = function(_self: any)
			root:Destroy()
		end,
	}

	if opts.onClick then
		-- Wired even when dimmed: doc §11.1, every tap answers.
		root.Activated:Connect(opts.onClick)
	end
	UIChrome.Animate(theme, root, chip)
	return control
end

-- ========================================================================
-- Chip — the static badge
-- ========================================================================

-- A read-only capsule (counts, states, rarity marks). Not a button: it takes no
-- input and casts a smaller shadow, so a row of them does not read as a row of
-- things to press.
function GPControlKit.Chip(theme: Types.UITheme, parent: Instance, opts: {
	text: string,
	fill: Color3?,
	textSize: number?,
	numeric: boolean?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	sink: { any }?,
}): (Frame, TextLabel)
	local fill = opts.fill or theme.Colors.Surface
	local chip = surface("GPChip", fill, 0)
	chip.Size = opts.size or UDim2.fromOffset(96, CHIP_H)
	place(chip, opts)
	chip.Parent = parent
	UIStyler.Corner(theme.Radii.Pill).Parent = chip
	GPLayoutKit.SoftStroke(theme, chip, fill)
	if opts.sink then
		GPLayoutKit.Shadow(theme, chip, "sm", opts.sink, fill)
	end

	local size = opts.textSize or theme.TextSizes.Small
	local label = if opts.numeric
		then GPLayoutKit.NumberText(theme, size, theme.Colors.TextPrimary, "Text")
		else GPLayoutKit.BodyText(theme, size, theme.Colors.TextPrimary, "Text")
	label.Text = opts.text
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = chip.ZIndex + 1
	label.Parent = chip
	return chip, label
end

-- ========================================================================
-- Toggle
-- ========================================================================

export type Toggle = {
	Root: TextButton,
	label: TextLabel,
	track: Frame,
	knob: Frame,
	Set: (any, boolean, boolean?) -> (), -- (value, notify) — notify defaults to false

	Get: (any) -> boolean,
	Destroy: (any) -> (),
}

-- Label left, capsule switch right, and the WHOLE ROW is the hit target (doc
-- §11.6: no dead zones). ON is rose with the knob thrown right; OFF is the
-- blush well with the knob at rest — a position change as well as a colour one,
-- so the state never rides on hue alone.
function GPControlKit.Toggle(theme: Types.UITheme, parent: Instance, opts: {
	label: string,
	value: boolean?,
	textSize: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	onChanged: ((boolean) -> ())?,
}): Toggle
	local spacing = theme.Spacing
	local root = hitButton("GPToggle")
	root.Size = opts.size or UDim2.new(1, 0, 0, 36)
	place(root, opts)
	root.Parent = parent

	local label = GPLayoutKit.BodyText(theme, opts.textSize or theme.TextSizes.Body, theme.Colors.TextPrimary, "Label")
	label.Text = opts.label
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Size = UDim2.new(1, -(TOGGLE_TRACK_W + spacing.S), 1, 0)
	label.ZIndex = root.ZIndex + 1
	label.Parent = root

	local trackFill = theme.Colors.Surface
	local track = surface("Track", trackFill, 0)
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.fromScale(1, 0.5)
	track.Size = UDim2.fromOffset(TOGGLE_TRACK_W, TOGGLE_TRACK_H)
	track.ZIndex = root.ZIndex + 1
	track.Parent = root
	UIStyler.Corner(theme.Radii.Pill).Parent = track
	local trackStroke = GPLayoutKit.SoftStroke(theme, track, trackFill)

	local knob = surface("Knob", theme.Colors.Background, 0)
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Size = UDim2.fromOffset(TOGGLE_KNOB, TOGGLE_KNOB)
	knob.ZIndex = track.ZIndex + 1
	knob.Parent = track
	UIStyler.Corner(theme.Radii.Pill).Parent = knob
	GPLayoutKit.SoftStroke(theme, knob, theme.Colors.Background)

	local state = opts.value ~= false
	local function paint()
		local fill = if state then theme.Colors.Primary else theme.Colors.Surface
		track.BackgroundColor3 = fill
		trackStroke.Color = GPLayoutKit.Deepen(theme, fill, 1)
		knob.Position = if state
			then UDim2.new(1, -(TOGGLE_KNOB + 3), 0.5, 0)
			else UDim2.new(0, 3, 0.5, 0)
	end
	paint()

	local control: Toggle
	control = {
		Root = root,
		label = label,
		track = track,
		knob = knob,
		-- `notify` defaults to FALSE, matching UIToggleComponent:Set exactly, so
		-- a screen can swap one for the other without re-reading its call sites.
		Set = function(_self: any, value: boolean, notify: boolean?)
			state = value
			paint()
			if notify and opts.onChanged then
				opts.onChanged(state)
			end
		end,
		Get = function(_self: any): boolean
			return state
		end,
		Destroy = function(_self: any)
			root:Destroy()
		end,
	}

	root.Activated:Connect(function()
		control:Set(not state, true)
	end)
	UIChrome.Animate(theme, root, track)
	return control
end

-- ========================================================================
-- Slider
-- ========================================================================

export type Slider = {
	Root: Frame,
	label: TextLabel,
	value: TextLabel,
	track: Frame,
	fill: Frame,
	knob: Frame,
	Set: (any, number, boolean?) -> (),
	Get: (any) -> number,
	Destroy: (any) -> (),
}

-- Caption + right-aligned numerals over a rounded track with a petal knob.
--
-- DRAG WITHOUT A GLOBAL CONNECTION: the hit target is a transparent button as
-- TALL as the whole control, and the drag is driven from that button's OWN
-- InputBegan/InputChanged/InputEnded. A UserInputService connection would
-- outlive the screen unless every caller remembered to drop it in _OnHide; an
-- instance-scoped one dies with the instance. The cost is that a pointer
-- dragged clear of the control stops updating — which is why the hit box is the
-- full control height rather than the 10px track.
function GPControlKit.Slider(theme: Types.UITheme, parent: Instance, opts: {
	label: string,
	min: number,
	max: number,
	value: number?,
	step: number?,
	decimals: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	onChanged: ((number) -> ())?,
	sink: { any }?,
}): Slider
	local minValue, maxValue = opts.min, opts.max
	local span = math.max(maxValue - minValue, 1e-6)
	local step = opts.step
	local decimals = math.max(0, math.floor(opts.decimals or 2))
	local format = "%." .. decimals .. "f"

	local root = surface("GPSlider", theme.Colors.Background, 1)
	root.Size = opts.size or UDim2.new(1, 0, 0, 44)
	place(root, opts)
	root.Parent = parent

	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Label")
	label.Text = opts.label
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(0.6, 0, 0, 20)
	label.ZIndex = root.ZIndex + 1
	label.Parent = root

	local readout = GPLayoutKit.NumberText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Value")
	readout.AnchorPoint = Vector2.new(1, 0)
	readout.Position = UDim2.fromScale(1, 0)
	readout.Size = UDim2.new(0.4, 0, 0, 20)
	readout.ZIndex = root.ZIndex + 1
	readout.Parent = root

	local trackFill = theme.Arcade.RulerTrack
	local track = surface("Track", trackFill, 0)
	track.AnchorPoint = Vector2.new(0, 1)
	track.Position = UDim2.new(0, 0, 1, -8)
	track.Size = UDim2.new(1, 0, 0, SLIDER_TRACK_H)
	track.ZIndex = root.ZIndex + 1
	track.Parent = root
	UIStyler.Corner(theme.Radii.Pill).Parent = track

	local fillBar = surface("Fill", theme.Colors.Primary, 0)
	fillBar.Size = UDim2.fromScale(0, 1)
	fillBar.ZIndex = track.ZIndex + 1
	fillBar.Parent = track
	UIStyler.Corner(theme.Radii.Pill).Parent = fillBar

	local knobFill = theme.Colors.Background
	local knob = surface("Knob", knobFill, 0)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0, 0.5)
	knob.Size = UDim2.fromOffset(SLIDER_KNOB, SLIDER_KNOB)
	knob.ZIndex = track.ZIndex + 2
	knob.Parent = track
	UIStyler.Corner(theme.Radii.Pill).Parent = knob
	GPLayoutKit.SoftStroke(theme, knob, theme.Colors.Primary)
	GPLayoutKit.Shadow(theme, knob, "sm", opts.sink, theme.Colors.Primary)

	local current = math.clamp(opts.value or minValue, minValue, maxValue)

	local function quantise(raw: number): number
		local value = math.clamp(raw, minValue, maxValue)
		if step and step > 0 then
			value = minValue + math.floor((value - minValue) / step + 0.5) * step
			value = math.clamp(value, minValue, maxValue)
		end
		return value
	end

	local function render()
		local ratio = (current - minValue) / span
		fillBar.Size = UDim2.fromScale(ratio, 1)
		knob.Position = UDim2.fromScale(ratio, 0.5)
		readout.Text = string.format(format, current)
	end
	render()

	local control: Slider
	control = {
		Root = root,
		label = label,
		value = readout,
		track = track,
		fill = fillBar,
		knob = knob,
		-- `notify` defaults to FALSE, matching UISliderComponent:Set exactly, so
		-- a screen can swap one for the other without re-reading its call sites.
		Set = function(_self: any, value: number, notify: boolean?)
			current = quantise(value)
			render()
			if notify and opts.onChanged then
				opts.onChanged(current)
			end
		end,
		Get = function(_self: any): number
			return current
		end,
		Destroy = function(_self: any)
			root:Destroy()
		end,
	}

	-- The full-height transparent grab area (see the drag note above).
	local hit = hitButton("Grab")
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = knob.ZIndex + 1
	hit.Parent = root

	local dragging = false
	local function setFromX(x: number)
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local ratio = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		control:Set(minValue + ratio * span, true)
	end

	hit.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	hit.InputChanged:Connect(function(input: InputObject)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			setFromX(input.Position.X)
		end
	end)
	local function stop(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end
	hit.InputEnded:Connect(stop)
	-- Releasing off the control must not leave it stuck in drag.
	hit.MouseLeave:Connect(function()
		dragging = false
	end)

	return control
end

-- ========================================================================
-- Meter — the read-only ruler
-- ========================================================================

export type Meter = {
	Root: Frame,
	label: TextLabel,
	value: TextLabel,
	track: Frame,
	fill: Frame,
	Set: (any, number, number?) -> (),
	Destroy: (any) -> (),
}

-- Caption, a PRINTED fraction and a bar. The fraction is printed because a bar
-- alone is a vibe, not a number, and this pack is not allowed to trade one for
-- the other. Value colour rides the FILL, never the numerals: butter gold
-- measures 1.18:1 on blush and would be unreadable as text.
function GPControlKit.Meter(theme: Types.UITheme, parent: Instance, opts: {
	label: string,
	value: number?,
	maxValue: number?,
	suffix: string?,
	accent: Color3?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
}): Meter
	local root = surface("GPMeter", theme.Colors.Background, 1)
	root.Size = opts.size or UDim2.new(1, 0, 0, 42)
	place(root, opts)
	root.Parent = parent

	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Label")
	label.Text = opts.label
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(0.5, 0, 0, 20)
	label.ZIndex = root.ZIndex + 1
	label.Parent = root

	local readout = GPLayoutKit.NumberText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Value")
	readout.AnchorPoint = Vector2.new(1, 0)
	readout.Position = UDim2.fromScale(1, 0)
	readout.Size = UDim2.new(0.5, 0, 0, 20)
	readout.ZIndex = root.ZIndex + 1
	readout.Parent = root

	local trackFill = theme.Arcade.RulerTrack
	local track = surface("Track", trackFill, 0)
	track.AnchorPoint = Vector2.new(0, 1)
	track.Position = UDim2.fromScale(0, 1)
	track.Size = UDim2.new(1, 0, 0, METER_TRACK_H)
	track.ZIndex = root.ZIndex + 1
	track.Parent = root
	UIStyler.Corner(theme.Radii.Pill).Parent = track

	local fillBar = surface("Fill", opts.accent or theme.Arcade.Gold, 0)
	fillBar.Size = UDim2.fromScale(0, 1)
	fillBar.ZIndex = track.ZIndex + 1
	fillBar.Parent = track
	UIStyler.Corner(theme.Radii.Pill).Parent = fillBar

	local maxValue = math.max(opts.maxValue or 1, 1)
	local current = opts.value or 0
	local suffix = opts.suffix or ""

	local function render()
		fillBar.Size = UDim2.fromScale(math.clamp(current / maxValue, 0, 1), 1)
		readout.Text = string.format("%d / %d%s", current, maxValue, suffix)
	end
	render()

	return {
		Root = root,
		label = label,
		value = readout,
		track = track,
		fill = fillBar,
		Set = function(_self: any, value: number, newMax: number?)
			current = value
			if newMax then
				maxValue = math.max(newMax, 1)
			end
			render()
		end,
		Destroy = function(_self: any)
			root:Destroy()
		end,
	}
end

-- ========================================================================
-- Field — the text well
-- ========================================================================

export type Field = {
	Root: Frame,
	box: TextBox,
	icon: GuiObject?,
	Destroy: (any) -> (),
}

-- A TextBox has no UIChrome builder in any pack, so the WELL carries the chrome
-- and the box is a transparent child — the nesting every family in this
-- framework uses. Placeholder ink is TextSecondary (4.5:1 on cream), never the
-- Disabled grey, which would be both illegible and off-palette.
function GPControlKit.Field(theme: Types.UITheme, parent: Instance, opts: {
	placeholder: string?,
	text: string?,
	iconKey: string?,
	textSize: number?,
	numeric: boolean?,
	index: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
}): Field
	local spacing = theme.Spacing
	local fill = theme.Colors.Surface

	local well = surface("GPField", fill, 0)
	well.Size = opts.size or UDim2.new(1, 0, 0, FIELD_H)
	place(well, opts)
	well.Parent = parent
	GPLayoutKit.Petal(theme, well, opts.index or 0)
	GPLayoutKit.SoftStroke(theme, well, fill)

	local textX = spacing.M
	local icon: GuiObject? = nil
	if opts.iconKey then
		local art = GPControlKit.Icon(theme, well, opts.iconKey, 24)
		art.AnchorPoint = Vector2.new(0, 0.5)
		art.Position = UDim2.new(0, spacing.M, 0.5, 0)
		art.ZIndex = well.ZIndex + 1
		icon = art
		textX = spacing.M + 24 + spacing.S
	end

	local box = Instance.new("TextBox")
	box.Name = "Input"
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Text = opts.text or ""
	box.PlaceholderText = opts.placeholder or ""
	box.PlaceholderColor3 = theme.Colors.TextSecondary
	box.FontFace = if opts.numeric then theme.Fonts.Numeric else theme.Fonts.Body
	box.TextSize = opts.textSize or theme.TextSizes.Body
	box.TextColor3 = theme.Colors.TextPrimary
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Position = UDim2.fromOffset(textX, 0)
	box.Size = UDim2.new(1, -(textX + spacing.S), 1, 0)
	box.ZIndex = well.ZIndex + 1
	box.Parent = well

	return {
		Root = well,
		box = box,
		icon = icon,
		Destroy = function(_self: any)
			well:Destroy()
		end,
	}
end

-- ========================================================================
-- EmptySlot — the invitation
-- ========================================================================

-- The pack's answer to a locked or unfilled cell: a SOFT OUTLINE on the bare
-- paper, not a padlock. An empty shelf here says "this one is still yours to
-- make", and the caption keeps the state explicit so nothing is lost by being
-- kind about it.
--
-- Roblox UIStroke cannot dash, so the dashed READ comes from dropping the rim
-- to half opacity while its filled neighbours keep solid ones — the outline is
-- the lightest thing in the grid, which is exactly what a dash does.
function GPControlKit.EmptySlot(theme: Types.UITheme, parent: Instance, opts: {
	caption: string?,
	markKey: string?,
	index: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
}): Frame
	local spacing = theme.Spacing
	local slot = surface("GPEmptySlot", theme.Colors.Background, 0.45)
	slot.Size = opts.size or UDim2.fromScale(1, 1)
	place(slot, opts)
	slot.Parent = parent
	GPLayoutKit.Petal(theme, slot, opts.index or 0)
	local rim = GPLayoutKit.SoftStroke(theme, slot, theme.Colors.Surface)
	rim.Transparency = 0.5

	local mark = GPLayoutKit.Slice(theme, opts.markKey or "daisy", theme.Colors.Surface, "Mark")
	mark.ImageTransparency = 0.35
	mark.ScaleType = Enum.ScaleType.Fit
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, if opts.caption then 0.4 else 0.5)
	mark.Size = UDim2.fromScale(0.34, 0.34)
	mark.ZIndex = slot.ZIndex + 1
	mark.Parent = slot

	if opts.caption then
		local caption = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Caption")
		caption.Text = opts.caption
		caption.TextTruncate = Enum.TextTruncate.AtEnd
		caption.AnchorPoint = Vector2.new(0.5, 1)
		caption.Position = UDim2.new(0.5, 0, 1, -spacing.S)
		caption.Size = UDim2.new(1, -spacing.S * 2, 0, 18)
		caption.ZIndex = slot.ZIndex + 1
		caption.Parent = slot
	end
	return slot
end

-- ========================================================================
-- Well — the recessed readout surface
-- ========================================================================

-- The blush inset every dense screen uses behind a list, a log or a readout.
-- Scrolling callers must set ClipsDescendants themselves on the SCROLL, not on
-- this: clipping here would slice the shadows of the cards riding on it.
function GPControlKit.Well(theme: Types.UITheme, parent: Instance, opts: {
	fill: Color3?,
	index: number?,
	shadow: string?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	sink: { any }?,
}): Frame
	local fill = opts.fill or theme.Colors.Surface
	local well = surface("GPWell", fill, 0)
	well.Size = opts.size or UDim2.fromScale(1, 1)
	place(well, opts)
	well.Parent = parent
	GPLayoutKit.Petal(theme, well, opts.index or 0)
	GPLayoutKit.SoftStroke(theme, well, fill)
	if opts.shadow then
		GPLayoutKit.Shadow(theme, well, opts.shadow, opts.sink, fill)
	end
	return well
end

return GPControlKit
