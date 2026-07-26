--!strict
-- Animated on/off switch in the phase-pill language (UI_DESIGN_DOCUMENT.md
-- §8): the track is a true 88x28 pill that reads exactly like a booth phase
-- pill — OFF = recessed chocolate (panelDeep) with a muted knob/label, ON =
-- honey fill with a cream knob — and plays the "phase lands" pulse when it
-- switches on. Emits changes via onChanged.
--
-- Extra props:
--   labelKey / label
--   value     : boolean initial state
--   onChanged : (value: boolean) -> ()

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local UIComponentBase = require(script.Parent.UIComponentBase)

local UIToggleComponent = setmetatable({}, { __index = UIComponentBase })
UIToggleComponent.__index = UIToggleComponent

-- Phase-pill geometry (doc §8), fixed px at the 1650x1020 baseline.
local TRACK_WIDTH = 88
local TRACK_HEIGHT = 28
local KNOB_SIZE = 22
local KNOB_MARGIN = 3
-- ON hangs off the right edge (Scale 1 minus knob+margin) so the endpoints
-- stay correct even if a caller ever resizes the track.
local ON_POS = UDim2.new(1, -(KNOB_SIZE + KNOB_MARGIN), 0.5, 0)
local OFF_POS = UDim2.new(0, KNOB_MARGIN, 0.5, 0)

function UIToggleComponent.new()
	local self = UIComponentBase.new("UIToggle")
	self._value = false
	return setmetatable(self, UIToggleComponent)
end

function UIToggleComponent:_Build(props: Types.UIComponentProps)
	self._value = props.value == true
	local root = self.Root
	root.BackgroundTransparency = 1
	if not props.size then
		root.Size = UDim2.new(1, 0, 0, 36)
		self._baseSize = root.Size
	end

	local label = UIStyler.TextLabel("Label")
	label.Size = UDim2.new(1, -(TRACK_WIDTH + 12), 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextScaled = true
	self._labelConstraint = UIStyler.TextSizeConstraint(16, 8)
	self._labelConstraint.Parent = label
	label.Text = TextConfig.Resolve(props.labelKey or props.label)
	label.Parent = root
	self._label = label

	-- The track IS the phase pill: fixed 88x28, corner policy from UIChrome
	-- (full pill), explicitly chromed — glass sheen here, the policy stroke
	-- in _Style — so the look never depends on the arcade style-enforcer
	-- backstop (which would slap a black stroke + bevel onto any solid
	-- button it finds bare).
	local track = Instance.new("TextButton")
	track.Name = "Track"
	track.Text = ""
	track.AutoButtonColor = false
	track.Size = UDim2.fromOffset(TRACK_WIDTH, TRACK_HEIGHT)
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, 0, 0.5, 0)
	track.BorderSizePixel = 0
	UIChrome.Corner("Arcade", "Pill").Parent = track
	UIChrome.GlassGradient().Parent = track
	track.Parent = root
	self._track = track

	-- Cream circle knob sliding between the pill's ends.
	local knob = UIStyler.Frame("Knob")
	knob.Size = UDim2.fromOffset(KNOB_SIZE, KNOB_SIZE)
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Position = self._value and ON_POS or OFF_POS
	UIChrome.Corner("Arcade", "Pill").Parent = knob
	knob.Parent = track
	self._knob = knob

	-- Hover/press juice animates a UIScale on the pill surface, never the
	-- Root footprint, so rows/lists around the toggle never reflow. The base
	-- interaction wiring also keeps the press squash playing when disabled —
	-- every tap answers (doc §11.1) — while the actual flip stays gated.
	self:_UseScaleTarget(track)
	self:_SetHoverFill(track)
	self:_BindInteractions(track)
	self:_Connect(track.Activated, function()
		if self.Props.enabled ~= false then
			self:Set(not self._value, true)
		end
	end)
end

function UIToggleComponent:Set(value: boolean, notify: boolean?)
	local changed = self._value ~= value
	self._value = value
	local theme = self.Theme
	if theme then
		local anims = theme.Animations
		local a = theme.Arcade
		local trackColor = value and a.Green or a.RulerTrack
		self:_Tween(self._knob, anims.Emphasis, { Position = value and ON_POS or OFF_POS })
		self:_Tween(self._track, anims.Emphasis, { BackgroundColor3 = trackColor })
		self:_Tween(self._knob, anims.Emphasis, {
			BackgroundColor3 = value and theme.Colors.TextPrimary or theme.Colors.Disabled,
		})
		self:_Tween(self._label, anims.Emphasis, {
			TextColor3 = value and theme.Colors.TextPrimary or theme.Colors.Disabled,
		})
		-- If we're mid-hover the base class restores its captured rest colour
		-- on HoverOff — retarget it so it restores the NEW state fill instead
		-- of snapping back to the pre-toggle colour.
		if self._hoverRestColor then
			self._hoverRestColor = trackColor
		end
		if changed and value then
			-- The "phase lands" pulse (doc §8) — spikes the pill, not the row.
			self:PlayAnimation("Pulse")
		end
	end
	if notify and self.Props.onChanged then
		self.Props.onChanged(value)
	end
end

function UIToggleComponent:GetValue(): boolean
	return self._value
end

function UIToggleComponent:_Style(theme: Types.UITheme)
	local a = theme.Arcade
	self._label.FontFace = theme.Fonts.Body
	if self._labelConstraint then
		self._labelConstraint.MaxTextSize = theme.TextSizes.Body
	end

	-- Stroke policy belongs to UIChrome (Classic: 3px black; styled chrome:
	-- the style hairline) — rebuild it from the live theme instead of
	-- hand-rolling colour/thickness.
	if self._trackStroke then
		self._trackStroke:Destroy()
	end
	self._trackStroke = UIChrome.Stroke(theme, "Arcade")
	self._trackStroke.Parent = self._track

	-- Phase-pill states (doc §8): OFF = panelDeep + muted knob/label, ON =
	-- honey + cream knob. Snap on (re)theme; Set() tweens the live flips.
	local on = self._value
	self._track.BackgroundColor3 = on and a.Green or a.RulerTrack
	self._knob.BackgroundColor3 = on and theme.Colors.TextPrimary or theme.Colors.Disabled
	self._label.TextColor3 = on and theme.Colors.TextPrimary or theme.Colors.Disabled
	self._knob.Position = on and ON_POS or OFF_POS
end

return UIToggleComponent
