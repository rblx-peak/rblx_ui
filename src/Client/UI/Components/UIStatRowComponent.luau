--!strict
-- UIStatRowComponent — the ARMORED CORE assembly stat row:
--
--   LABEL                        +12 [   1240 ] kg
--   ────────────────────────────────────▒▒▒▒░░░░░
--
-- One text line (uppercase mono label left; numeric value right-aligned in a
-- fixed-width column framed by SEPARATE "[" / "]" labels; unit as its own
-- dimmer label after the value so numerals stay flush across a stacked list)
-- over a 4px magnitude bar scaled value/maxValue.
--
-- SetPreview(v) is the part-swap DELTA GHOST: a second bar segment overlays
-- the difference — painted Success when the change is GOOD, Error when BAD —
-- and a signed delta numeral appears left of the brackets. `invertGoodness`
-- flips the mapping for WEIGHT / EN LOAD style stats where lower is better;
-- the sign prefix is ALWAYS present so meaning never rides on hue alone.
--
-- SetOverLimit(on) flips the value + brackets to Error and shows a small
-- "OVER LIMIT" chip pulsing on ONE UITicker handler owned by the row. The
-- chip overlays the right end of the bar line (anchored bottom-right) so the
-- fixed text columns above never move.
--
-- Extra props (beyond Types.UIComponentProps):
--   label          : string   already-resolved text (uppercased here)
--   unit           : string?  e.g. "kg" — the column is reserved either way
--   maxValue       : number   bar scale (default 100)
--   invertGoodness : boolean? lower-is-better stats
--   value          : number?  initial value
--
-- API: :SetValue(v)   :SetPreview(v | nil)   :SetOverLimit(on)

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIComponentBase = require(script.Parent.UIComponentBase)
local UITicker = require(script.Parent.Parent.Framework.UITicker)

local UIStatRowComponent = setmetatable({}, { __index = UIComponentBase })
UIStatRowComponent.__index = UIStatRowComponent

local DEFAULT_H = 34
local TEXT_H = 20
local BAR_H = 4
-- The fixed column ladder, measured from the RIGHT edge: every row in a
-- stack keeps its numerals flush regardless of label length.
local UNIT_W = 44
local BRACKET_W = 12
local VALUE_W = 76
local DELTA_W = 64
local COL_GAP = 4 -- between "]" and the unit
local LABEL_GAP = 8 -- between the label and the delta column
local CHIP_W = 78
local CHIP_H = 14
local TRACK_TRANSPARENCY = 0.5
local CHIP_PULSE_RATE = 6 -- rad/s
local CHIP_PULSE_DEPTH = 0.4

function UIStatRowComponent.new()
	local self = UIComponentBase.new("UIStatRow")
	self._value = 0
	self._maxValue = 100
	self._invertGoodness = false
	self._preview = nil :: number?
	self._overLimit = false
	self._stopTicker = nil :: (() -> ())?
	return setmetatable(self, UIStatRowComponent)
end

function UIStatRowComponent:_Build(props: Types.UIComponentProps)
	self._maxValue = (props.maxValue :: number?) or 100
	self._invertGoodness = props.invertGoodness == true

	local root = self.Root
	if not props.size then
		root.Size = UDim2.new(1, 0, 0, DEFAULT_H)
		self._baseSize = root.Size
	end

	local x = UNIT_W
	local unit = UIStyler.TextLabel("Unit")
	unit.Size = UDim2.new(0, UNIT_W, 0, TEXT_H)
	unit.Position = UDim2.new(1, -x, 0, 0)
	unit.TextXAlignment = Enum.TextXAlignment.Left
	unit.Text = (props.unit :: string?) or ""
	unit.Parent = root
	self._unitLabel = unit

	x += COL_GAP + BRACKET_W
	local closeBracket = UIStyler.TextLabel("CloseBracket")
	closeBracket.Size = UDim2.new(0, BRACKET_W, 0, TEXT_H)
	closeBracket.Position = UDim2.new(1, -x, 0, 0)
	closeBracket.Text = "]"
	closeBracket.Parent = root
	self._closeBracket = closeBracket

	x += VALUE_W
	local value = UIStyler.TextLabel("Value")
	value.Size = UDim2.new(0, VALUE_W, 0, TEXT_H)
	value.Position = UDim2.new(1, -x, 0, 0)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Parent = root
	self._valueLabel = value

	x += BRACKET_W
	local openBracket = UIStyler.TextLabel("OpenBracket")
	openBracket.Size = UDim2.new(0, BRACKET_W, 0, TEXT_H)
	openBracket.Position = UDim2.new(1, -x, 0, 0)
	openBracket.Text = "["
	openBracket.Parent = root
	self._openBracket = openBracket

	x += DELTA_W
	local delta = UIStyler.TextLabel("Delta")
	delta.Size = UDim2.new(0, DELTA_W, 0, TEXT_H)
	delta.Position = UDim2.new(1, -x, 0, 0)
	delta.TextXAlignment = Enum.TextXAlignment.Right
	delta.Text = ""
	delta.Parent = root
	self._deltaLabel = delta

	local label = UIStyler.TextLabel("Label")
	label.Size = UDim2.new(1, -(x + LABEL_GAP), 0, TEXT_H)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = string.upper((props.label :: string?) or "")
	label.Parent = root
	self._label = label

	local track = UIStyler.Frame("Track")
	track.Position = UDim2.new(0, 0, 1, -BAR_H)
	track.Size = UDim2.new(1, 0, 0, BAR_H)
	track.Parent = root
	self._track = track

	local fill = UIStyler.Frame("Fill")
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 2
	fill.Parent = track
	self._fill = fill

	-- The preview ghost overlays [min, max] of (value, preview) as a scale
	-- span INSIDE the track, above the fill: an extension reads as gained
	-- range, a covered run of the fill reads as lost range.
	local ghost = UIStyler.Frame("PreviewGhost")
	ghost.Size = UDim2.fromScale(0, 1)
	ghost.ZIndex = 3
	ghost.Visible = false
	ghost.Parent = track
	self._ghost = ghost

	local chip = UIStyler.Frame("OverLimitChip")
	chip.AnchorPoint = Vector2.new(1, 1)
	chip.Position = UDim2.new(1, 0, 1, 0)
	chip.Size = UDim2.fromOffset(CHIP_W, CHIP_H)
	chip.ZIndex = 4
	chip.Visible = false
	chip.Parent = root
	self._chip = chip

	local chipText = UIStyler.TextLabel("ChipText")
	chipText.Size = UDim2.fromScale(1, 1)
	chipText.Text = "OVER LIMIT"
	chipText.ZIndex = 5
	chipText.Parent = chip
	self._chipText = chipText

	-- THE one ticker handler for this row: the over-limit chip pulse. bindTo
	-- the Root so any teardown auto-unregisters; Destroy stops it too.
	self._stopTicker = UITicker.Register(function(dt: number, now: number)
		self:_Tick(dt, now)
	end, root)

	self:SetValue((props.value :: number?) or 0)
end

function UIStatRowComponent:SetValue(v: number)
	self._value = v
	self._valueLabel.Text = tostring(math.round(v))
	local ratio = if self._maxValue > 0 then math.clamp(v / self._maxValue, 0, 1) else 0
	if self.Theme then
		self:_Tween(self._fill, self.Theme.Animations.Emphasis, { Size = UDim2.fromScale(ratio, 1) })
	else
		self._fill.Size = UDim2.fromScale(ratio, 1)
	end
	self:_RenderPreview()
end

function UIStatRowComponent:SetPreview(v: number?)
	self._preview = v
	self:_RenderPreview()
end

function UIStatRowComponent:SetOverLimit(on: boolean)
	if self._overLimit == on then
		return
	end
	self._overLimit = on
	self._chip.Visible = on
	if not on then
		self._chip.BackgroundTransparency = 0
	end
	self:_PaintValueColumn()
end

-- Ghost + delta numeral from the current preview. GOOD = the stat moves the
-- way this stat wants (up normally, down under invertGoodness); the delta
-- keeps its +/- prefix in every state so the sign, not the hue, carries the
-- meaning. A change that rounds to zero shows a neutral "+0" and no ghost.
function UIStatRowComponent:_RenderPreview()
	local theme = self.Theme
	local ghost = self._ghost :: Frame
	local delta = self._deltaLabel :: TextLabel
	local preview = self._preview

	if preview == nil then
		ghost.Visible = false
		delta.Text = ""
		return
	end

	local diff = preview - self._value
	if math.round(diff) == 0 then
		ghost.Visible = false
		delta.Text = "+0"
		if theme then
			delta.TextColor3 = theme.Colors.TextSecondary
		end
		return
	end

	local maxV = self._maxValue
	local vRatio = if maxV > 0 then math.clamp(self._value / maxV, 0, 1) else 0
	local pRatio = if maxV > 0 then math.clamp(preview / maxV, 0, 1) else 0
	local lo = math.min(vRatio, pRatio)
	local hi = math.max(vRatio, pRatio)

	local good = (diff > 0) ~= self._invertGoodness
	ghost.Visible = true
	ghost.Position = UDim2.fromScale(lo, 0)
	ghost.Size = UDim2.fromScale(hi - lo, 1)
	delta.Text = string.format("%+d", math.round(diff))
	if theme then
		local color = if good then theme.Colors.Success else theme.Colors.Error
		ghost.BackgroundColor3 = color
		delta.TextColor3 = color
	end
end

-- Value + bracket ink, Error while over limit. Instant sets — no tween ever
-- leaves the row half-recoloured. The style-policy glow is re-applied after
-- every recolour so it tracks the value's current colour.
function UIStatRowComponent:_PaintValueColumn()
	local theme = self.Theme
	if not theme then
		return
	end
	local colors = theme.Colors
	local valueColor = if self._overLimit then colors.Error else colors.TextPrimary
	local bracketColor = if self._overLimit then colors.Error else colors.TextSecondary
	self._valueLabel.TextColor3 = valueColor
	self._openBracket.TextColor3 = bracketColor
	self._closeBracket.TextColor3 = bracketColor
	UIChrome.TextOutline(self._valueLabel)
end

function UIStatRowComponent:_Tick(_dt: number, now: number)
	if not self._overLimit then
		return
	end
	if not UIChrome.IsOnScreen(self.Root) then
		return
	end
	local wave = 0.5 + 0.5 * math.sin(now * CHIP_PULSE_RATE)
	self._chip.BackgroundTransparency = wave * CHIP_PULSE_DEPTH
end

function UIStatRowComponent:_Style(theme: Types.UITheme)
	local colors = theme.Colors

	local label = self._label :: TextLabel
	label.FontFace = theme.Fonts.Body
	label.TextSize = theme.TextSizes.Body
	label.TextColor3 = colors.TextSecondary

	-- FontFace is ALWAYS assigned on the symbol-bearing labels (brackets,
	-- signed deltas) — the engine landmine rule.
	local value = self._valueLabel :: TextLabel
	value.FontFace = theme.Fonts.Numeric
	value.TextSize = theme.TextSizes.Body

	for _, bracket in { self._openBracket :: TextLabel, self._closeBracket :: TextLabel } do
		bracket.FontFace = theme.Fonts.Numeric
		bracket.TextSize = theme.TextSizes.Body
	end

	local unit = self._unitLabel :: TextLabel
	unit.FontFace = theme.Fonts.Body
	unit.TextSize = theme.TextSizes.Small
	unit.TextColor3 = colors.TextSecondary

	local delta = self._deltaLabel :: TextLabel
	delta.FontFace = theme.Fonts.Numeric
	delta.TextSize = theme.TextSizes.Body

	local track = self._track :: Frame
	track.BackgroundColor3 = colors.SurfaceRaised
	track.BackgroundTransparency = TRACK_TRANSPARENCY

	local fill = self._fill :: Frame
	fill.BackgroundColor3 = colors.Accent

	local chip = self._chip :: Frame
	chip.BackgroundColor3 = colors.Error
	local chipText = self._chipText :: TextLabel
	chipText.FontFace = theme.Fonts.Numeric
	chipText.TextSize = theme.TextSizes.Small
	chipText.TextColor3 = colors.TextOnPrimary

	self:_PaintValueColumn()
	self:_RenderPreview()
end

function UIStatRowComponent:Destroy()
	if self._stopTicker then
		self._stopTicker()
		self._stopTicker = nil
	end
	UIComponentBase.Destroy(self)
end

return UIStatRowComponent
