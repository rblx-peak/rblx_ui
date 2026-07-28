--!strict
-- Settings / options menu — the Pottery Clash arcade modal (doc §7.4 anatomy):
-- a UIPanelComponent modal card whose body is a scroll of SettingsConfig-driven
-- option rows. The row engine is unchanged — ONE functional row per
-- SettingsConfig row, so adding a setting is a data edit, never a UI edit:
--   * Toggle   -> the §8 phase-pill recipe (88×28 pill track: OFF = the
--                 near-black ruler track + disabled text, ON = arcade green +
--                 white text, white knob slide, pulse when it lands ON)
--   * Slider   -> the §8 slider geometry (12px recessed rail corner 6, 6px
--                 fill, 26px knob swelling 1.15× while held, GothamMedium 12
--                 value readout)
--   * Dropdown -> an arcade slate cycle-box (Arcade.Panel + 2px black stroke +
--                 hard corners + FredokaOne + "▸" affordance) that cycles its
--                 option list on click — no overlay list to clip
-- Every control change funnels through self:_ApplyChange(id, value), which
-- updates state + fires the injected onChange (SetChangeHandler).
--
-- The §8 control GEOMETRY is the booth's, but the colours here are Arcade:
-- doc §1 assigns menus/HUD to the arcade family, and the chocolate-and-honey
-- studio palette belongs to the crafting booth. Row art comes from the icon
-- archive keyed by what each setting IS (a speaker for volume), not by control
-- type. All layout is fixed px at the 1650×1020 baseline (UIScreenBase
-- attaches the UIScale).

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local SettingsConfig = require(script.Parent.Parent.Config.SettingsConfig)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIPanelComponent = require(script.Parent.Parent.Components.UIPanelComponent)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local ACLayoutKit = require(script.Parent.Parent.Framework.ACLayoutKit)
local GLLayoutKit = require(script.Parent.Parent.Framework.GLLayoutKit)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

-- GP never shouts (pack law 5). "SETTINGS" arrives from TextConfig in arcade
-- all-caps; the SAME string is retitled for DISPLAY under that layout kit only.
-- The rule lives in the KIT, not here — one casing rule per pack, or a title
-- reads one way in this screen and another in the next (GPLayoutKit.TitleCase).
local gpTitleCase = GPLayoutKit.TitleCase

-- Fixed pixel geometry (1650×1020 baseline).
local ROW_H = 60
local HEADER_H = 30
local LIST_PAD = 8
local CONTROL_INSET = 16 -- controls' right inset inside a row
local LABEL_X = 58 -- row label start (after the 36px kind icon at x=14)

-- Toggle: the phase-pill track (doc §8 — true pill, 88×28, FredokaOne 13).
local TOGGLE_W = 88
local TOGGLE_H = 28
local TOGGLE_KNOB = 22

-- Slider: the studio slider (doc §8 — 12px recessed rail, 6px honey fill,
-- 26px cream knob that swells to 1.15× while held).
local SLIDER_W = 310
local RAIL_W = 230
local RAIL_H = 12
local FILL_H = 6
local SLIDER_KNOB = 26
local KNOB_HELD_SCALE = 1.15

-- Dropdown: arcade slate cycle-box.
local DROP_W = 220
local DROP_H = 36

-- Row art comes from the icon archive, keyed by WHAT THE SETTING IS rather
-- than by the control type — a speaker for volume reads instantly where a
-- generic "slider" glyph reads as noise. ROW_ICON is looked up first; KIND_ICON
-- is the fallback for settings a game adds without registering art.
local ROW_ICON = {
	master_volume = "soundOn",
	music_volume = "musicOn",
	sfx_enabled = "bell",
	ui_scale = "expand",
	reduced_motion = "bolt",
	quality = "sparkle",
	show_damage = "target",
	show_overheads = "player",
	camera_side = "compass",
	language = "book",
	notifications = "bell",
}

local KIND_ICON = {
	Toggle = "checkButton",
	Slider = "sort",
	Dropdown = "arrowDown",
}

local SettingsScreen = setmetatable({}, { __index = UIScreenBase })
SettingsScreen.__index = SettingsScreen

function SettingsScreen.new()
	local self = UIScreenBase.new("SettingsScreen", 17)
	self._state = SettingsConfig.Defaults()
	self._rows = {}
	-- Global input connections (slider drag) tracked so a rebuild / teardown can
	-- disconnect them — UserInputService connections are not tied to any Instance.
	self._conns = {} :: { RBXScriptConnection }
	-- Optional injected callback: (id, value) -> () when a setting changes.
	self._onChange = nil :: ((string, any) -> ())?
	return setmetatable(self, SettingsScreen)
end

function SettingsScreen:SetChangeHandler(fn: (string, any) -> ())
	self._onChange = fn
end

function SettingsScreen:_Track(conn: RBXScriptConnection)
	table.insert(self._conns, conn)
end

function SettingsScreen:_BuildContent()
	-- GP layout language: the pastel studio page (see _BuildGPLayout below).
	-- Every control, every section and every value survives the re-skin.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
	-- AC layout language: the whole screen is a bespoke terminal page (see
	-- _BuildACLayout below); the classic arcade modal build stays untouched.
	if self:LayoutKit() == "AC" then
		self:_BuildACLayout()
		return
	end

	local theme = self:GetTheme()

	-- The one modal recipe (doc §7.4): dim → black card → red header with the
	-- title + 48×48 red X. The panel owns that anatomy; close hides this screen.
	local panel = UIPanelComponent.new()
	panel:Create(self.Root, {
		titleKey = "settings.title",
		showClose = true,
		size = UDim2.fromOffset(780, 640),
		onClose = function()
			self.ScreenController:HideScreen("settings")
		end,
	})
	self._panel = panel
	-- Open/close is an instant flip; the pop lives on the panel CONTENT.
	self:_SetAnimatedPanel(panel)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Arcade.Gold
	scroll.Parent = panel.Body
	self._scroll = scroll

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = scroll

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, LIST_PAD)
	layout.Parent = scroll

	self:_BuildRows()
end

function SettingsScreen:_BuildRows()
	for _, inst in self._rows do
		inst:Destroy()
	end
	table.clear(self._rows)
	for _, conn in self._conns do
		conn:Disconnect()
	end
	table.clear(self._conns)

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	for _, section in SettingsConfig.Sections do
		self:_SectionHeader(self:_R(section.titleKey), nextOrder())
		for _, row in section.rows do
			self:_BuildRow(row, nextOrder())
		end
	end
end

-- Gold FredokaOne 22 with the black outline — the arcade section voice.
function SettingsScreen:_SectionHeader(text: string, order: number)
	local theme = self:GetTheme()
	local holder = UIStyler.Frame("SectionHeader")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, HEADER_H)
	holder.LayoutOrder = order
	holder.Parent = self._scroll

	local label = UIChrome.Text("Title", 22, theme.Arcade.Gold)
	label.Size = UDim2.new(1, -8, 1, 0)
	label.Position = UDim2.fromOffset(4, 0)
	label.TextXAlignment = Enum.TextXAlignment.Left
	-- Section headings shout, like every other display-font heading in the
	-- system; the config keeps its sentence-case source string.
	label.Text = string.upper(text)
	label.Parent = holder

	table.insert(self._rows, holder)
end

function SettingsScreen:_ApplyChange(id: string, value: any)
	self._state[id] = value
	if self._onChange then
		self._onChange(id, value)
	end
end

-- ---- row shell ---------------------------------------------------------
-- A 60px arcade row: Arcade.Row fill @ 8% transparency, 2px black stroke,
-- hard 90° corners (no UICorner at all), kind-icon glyph + white FredokaOne 20
-- label. Controls parent into the returned frame, anchored to its right edge.
function SettingsScreen:_SettingRow(icon: string, text: string, order: number): Frame
	local theme = self:GetTheme()

	local row = UIStyler.Frame("SettingRow")
	row.BackgroundTransparency = theme.Arcade.RowTransparency
	row.BackgroundColor3 = theme.Arcade.Row
	row.Size = UDim2.new(1, 0, 0, ROW_H)
	row.LayoutOrder = order
	-- Classic recipe: 2px black frame; styled chrome brings its own stroke.
	if theme.Chrome then
		UIChrome.Stroke(theme, "Arcade").Parent = row
	else
		UIStyler.Stroke(BLACK, 2, 0).Parent = row
	end

	-- Boxless pack art, 32px, vertically centred at x=14. IconArchive hands
	-- back an ImageLabel (or a glyph label if the art is missing) — either way
	-- it occupies the same slot, so the row never shifts.
	local iconImage = IconArchive.Image(row, icon, 32)
	iconImage.AnchorPoint = Vector2.new(0, 0.5)
	iconImage.Position = UDim2.new(0, 14, 0.5, 0)
	iconImage.ZIndex = 2

	local label = UIChrome.Text("RowLabel", 20, WHITE)
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, LABEL_X, 0.5, 0)
	-- Leave the right ~360px for the widest control (slider + inset).
	label.Size = UDim2.new(1, -(LABEL_X + SLIDER_W + CONTROL_INSET * 2), 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = text
	label.ZIndex = 2
	label.Parent = row

	row.Parent = self._scroll
	return row
end

function SettingsScreen:_BuildRow(row: any, order: number)
	local value = self._state[row.id]
	local icon = ROW_ICON[row.id] or KIND_ICON[row.kind] or "star"
	if row.kind == "Toggle" then
		local shell = self:_SettingRow(icon, self:_R(row.labelKey), order)
		self:_ToggleControl(shell, value == true, function(v: boolean)
			self:_ApplyChange(row.id, v)
		end)
		table.insert(self._rows, shell)
	elseif row.kind == "Slider" then
		local shell = self:_SettingRow(icon, self:_R(row.labelKey), order)
		self:_SliderControl(shell, row, tonumber(value) or row.min or 0, function(v: number)
			self:_ApplyChange(row.id, v)
		end)
		table.insert(self._rows, shell)
	elseif row.kind == "Dropdown" then
		local shell = self:_SettingRow(icon, self:_R(row.labelKey), order)
		local options = {}
		for _, opt in row.options do
			table.insert(options, { id = opt.id, text = self:_R(opt.textKey) })
		end
		self:_DropdownControl(shell, options, value, function(id: string)
			self:_ApplyChange(row.id, id)
		end)
		table.insert(self._rows, shell)
	end
end

-- ---- Toggle: the phase-pill recipe (doc §8) ----------------------------
-- 88×28 true-pill track: OFF = the near-black ruler track + disabled text,
-- ON = arcade green + white text; a white knob slides between the ends and the
-- pill pulses when it lands ON.
function SettingsScreen:_ToggleControl(row: Frame, initial: boolean, onChanged: (boolean) -> ())
	local theme = self:GetTheme()
	local motion = theme.Motion

	local offKnobPos = UDim2.new(0, 3, 0.5, 0)
	local onKnobPos = UDim2.new(0, TOGGLE_W - TOGGLE_KNOB - 3, 0.5, 0)
	-- The state word sits on the side the knob is NOT on.
	local offTextPos = UDim2.fromOffset(TOGGLE_KNOB + 6, 0)
	local onTextPos = UDim2.fromOffset(6, 0)

	local track = Instance.new("TextButton")
	track.Name = "ToggleTrack"
	track.Text = ""
	track.AutoButtonColor = false
	track.BorderSizePixel = 0
	track.Size = UDim2.fromOffset(TOGGLE_W, TOGGLE_H)
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, -CONTROL_INSET, 0.5, 0)
	track.BackgroundColor3 = initial and theme.Arcade.Green or theme.Arcade.RulerTrack
	track.ZIndex = 2
	UIChrome.Corner("Arcade", "Pill").Parent = track
	-- Classic recipe: 2px black frame; styled chrome brings its own stroke.
	if theme.Chrome then
		UIChrome.Stroke(theme, "Arcade", "Button").Parent = track
	else
		UIStyler.Stroke(BLACK, 2, 0).Parent = track
	end
	-- Explicit glass sheen: keeps the recipe colours exact AND satisfies the
	-- style enforcer's "solid button carries a gradient", so the arcade bevel
	-- backstop never multiplies the honey fill.
	UIChrome.GlassGradient().Parent = track

	local stateLabel = UIChrome.Text("State", 13, initial and theme.Colors.TextPrimary or theme.Colors.Disabled)
	stateLabel.Size = UDim2.new(1, -(TOGGLE_KNOB + 12), 1, 0)
	stateLabel.Position = initial and onTextPos or offTextPos
	stateLabel.Text = initial and "ON" or "OFF"
	stateLabel.ZIndex = 3
	stateLabel.Parent = track

	local knob = UIStyler.Frame("Knob")
	knob.BackgroundTransparency = 0
	knob.BackgroundColor3 = theme.Colors.TextPrimary
	knob.Size = UDim2.fromOffset(TOGGLE_KNOB, TOGGLE_KNOB)
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Position = initial and onKnobPos or offKnobPos
	knob.ZIndex = 4
	UIChrome.Corner("Arcade", "Pill").Parent = knob
	knob.Parent = track

	-- Hover/press juice on a UIScale (never a Size change). Deliberately NOT
	-- UIChrome.Animate: its hover fill-lerp snapshots the rest colour on enter,
	-- and a click-while-hovered recolour (OFF→ON) would be reverted on leave.
	local scale = Instance.new("UIScale")
	scale.Parent = track
	self:_Track(track.MouseEnter:Connect(function()
		TweenService:Create(scale, motion.HoverIn, { Scale = motion.HoverScale }):Play()
	end))
	self:_Track(track.MouseLeave:Connect(function()
		TweenService:Create(scale, motion.HoverOut, { Scale = 1 }):Play()
	end))
	self:_Track(track.MouseButton1Down:Connect(function()
		TweenService:Create(scale, motion.PressIn, { Scale = motion.PressScale }):Play()
	end))
	self:_Track(track.MouseButton1Up:Connect(function()
		TweenService:Create(scale, motion.HoverIn, { Scale = motion.HoverScale }):Play()
	end))

	local on = initial
	self:_Track(track.Activated:Connect(function()
		on = not on
		TweenService:Create(knob, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = on and onKnobPos or offKnobPos,
		}):Play()
		TweenService:Create(track, motion.HoverOut, {
			BackgroundColor3 = on and theme.Arcade.Green or theme.Arcade.RulerTrack,
		}):Play()
		stateLabel.Text = on and "ON" or "OFF"
		stateLabel.TextColor3 = on and theme.Colors.TextPrimary or theme.Colors.Disabled
		stateLabel.Position = on and onTextPos or offTextPos
		if on then
			-- "Chosen!" spike when the phase lands ON (doc §8 phase pills).
			UIChrome.Pulse(theme, track)
		end
		onChanged(on)
	end))

	track.Parent = row
end

-- ---- Slider: the studio slider recipe (doc §8) -------------------------
-- 12px recessed rail (the near-black ruler track, corner 6) with a 6px gold fill and a
-- 26px cream knob that swells to 1.15× while held; GothamMedium 12 muted
-- value readout (the recipe's quiet caption voice) at the far right.
function SettingsScreen:_SliderControl(row: Frame, spec: any, initial: number, onChanged: (number) -> ())
	local theme = self:GetTheme()
	local motion = theme.Motion
	local min = spec.min or 0
	local max = spec.max or 100
	local step = spec.step or 1
	local decimals = spec.decimals or 0
	local span = max - min
	if span == 0 then
		span = 1
	end
	local fmt = "%." .. tostring(decimals) .. "f"

	local holder = UIStyler.Frame("SliderControl")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(0, SLIDER_W, 1, 0)
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, -CONTROL_INSET, 0.5, 0)
	holder.ZIndex = 2
	holder.Parent = row

	local readout = UIChrome.BodyText("Value", 12, theme.Arcade.IceBlue)
	readout.Size = UDim2.fromOffset(64, 20)
	readout.AnchorPoint = Vector2.new(1, 0.5)
	readout.Position = UDim2.new(1, 0, 0.5, 0)
	readout.TextXAlignment = Enum.TextXAlignment.Right
	readout.ZIndex = 3
	readout.Parent = holder

	local rail = UIStyler.Frame("Rail")
	rail.BackgroundTransparency = 0
	rail.BackgroundColor3 = theme.Arcade.RulerTrack
	rail.Size = UDim2.fromOffset(RAIL_W, RAIL_H)
	rail.AnchorPoint = Vector2.new(0, 0.5)
	rail.Position = UDim2.new(0, 0, 0.5, 0)
	rail.ZIndex = 3
	UIChrome.Corner("Studio", "Sub").Parent = rail
	rail.Parent = holder

	local fill = UIStyler.Frame("Fill")
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = theme.Arcade.Gold
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.new(0, 0, 0.5, 0)
	fill.Size = UDim2.new(0, 0, 0, FILL_H)
	fill.ZIndex = 4
	UIChrome.Corner("Studio", "Sub").Parent = fill
	fill.Parent = rail

	local knob = UIStyler.Frame("Knob")
	knob.BackgroundTransparency = 0
	knob.BackgroundColor3 = theme.Colors.TextPrimary
	knob.Size = UDim2.fromOffset(SLIDER_KNOB, SLIDER_KNOB)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.new(0, 0, 0.5, 0)
	knob.ZIndex = 5
	UIChrome.Corner("Arcade", "Pill").Parent = knob
	knob.Parent = rail
	local knobScale = Instance.new("UIScale")
	knobScale.Parent = knob

	-- Whole-strip invisible hit target (doc §11.6): the rail zone at full row
	-- height, so there are no dead zones around the thin rail.
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.BorderSizePixel = 0
	hit.Size = UDim2.new(0, RAIL_W + SLIDER_KNOB, 1, 0)
	hit.Position = UDim2.new(0, -SLIDER_KNOB // 2, 0, 0)
	hit.ZIndex = 6
	hit.Parent = holder

	local function quantize(raw: number): number
		local snapped = min + math.floor((raw - min) / step + 0.5) * step
		return math.clamp(snapped, min, max)
	end

	-- Scale-positioned fill/knob: immune to the baseline UIScale.
	local function render(value: number)
		local frac = (value - min) / span
		fill.Size = UDim2.new(frac, 0, 0, FILL_H)
		knob.Position = UDim2.new(frac, 0, 0.5, 0)
		readout.Text = string.format(fmt, value)
	end
	render(quantize(initial))

	local function setHeld(held: boolean)
		TweenService:Create(knobScale, held and motion.HoverIn or motion.HoverOut, {
			Scale = held and KNOB_HELD_SCALE or 1,
		}):Play()
	end

	local dragging = false
	local function applyFromX(x: number)
		local absPos = rail.AbsolutePosition.X
		local absW = rail.AbsoluteSize.X
		if absW <= 0 then
			return
		end
		local frac = math.clamp((x - absPos) / absW, 0, 1)
		local value = quantize(min + frac * span)
		render(value)
		onChanged(value)
	end

	self:_Track(hit.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setHeld(true)
			applyFromX(input.Position.X)
		end
	end))
	self:_Track(UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			applyFromX(input.Position.X)
		end
	end))
	self:_Track(UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if dragging then
				dragging = false
				setHeld(false)
			end
		end
	end))
end

-- ---- Dropdown: arcade slate cycle-box ----------------------------------
-- Arcade.Panel fill, 2px black stroke, hard corners, FredokaOne, "▸"
-- affordance. Cycles the option list on click (the modal body clips its
-- descendants, so an expanding overlay list would be cut off). The press
-- juice always plays — every tap answers (doc §11.1).
function SettingsScreen:_DropdownControl(row: Frame, options: { { id: string, text: string } }, initialId: any, onChanged: (string) -> ())
	local theme = self:GetTheme()

	local idx = 1
	for i, opt in options do
		if opt.id == initialId then
			idx = i
			break
		end
	end

	local btn = Instance.new("TextButton")
	btn.Name = "DropdownControl"
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.BorderSizePixel = 0
	btn.Size = UDim2.fromOffset(DROP_W, DROP_H)
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -CONTROL_INSET, 0.5, 0)
	btn.BackgroundColor3 = theme.Arcade.Panel
	btn.ZIndex = 2
	-- Hard 90° corners (no UICorner), 2px black stroke, explicit arcade bevel.
	-- Styled chrome swaps in its own framing stroke; the bevel self-disables.
	if theme.Chrome then
		UIChrome.Stroke(theme, "Arcade", "Button").Parent = btn
	else
		UIStyler.Stroke(BLACK, 2, 0).Parent = btn
	end
	UIChrome.ArcadeBevel().Parent = btn

	local lbl = UIChrome.Text("Current", 20, WHITE)
	lbl.AnchorPoint = Vector2.new(0, 0.5)
	lbl.Position = UDim2.new(0, 12, 0.5, 0)
	lbl.Size = UDim2.new(1, -44, 1, 0)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.Text = options[idx] and options[idx].text or ""
	lbl.ZIndex = 3
	lbl.Parent = btn

	-- Cycle affordance — a symbol glyph, so FontFace matters (UIChrome.Text
	-- assigns FredokaOne, which carries this Unicode arrow).
	local arrow = UIChrome.Text("Cycle", 20, WHITE)
	arrow.Size = UDim2.fromOffset(24, DROP_H)
	arrow.AnchorPoint = Vector2.new(1, 0.5)
	arrow.Position = UDim2.new(1, -6, 0.5, 0)
	arrow.Text = "▸"
	arrow.ZIndex = 3
	arrow.Parent = btn

	self:_Track(btn.Activated:Connect(function()
		if #options == 0 then
			return
		end
		idx = (idx % #options) + 1
		lbl.Text = options[idx].text
		onChanged(options[idx].id)
	end))

	btn.Parent = row
	-- Hover/press springs — applied LAST, after final colours (UIChrome.Animate
	-- snapshots the rest colour). The fill never recolours at runtime here, so
	-- the hover white-lerp is safe.
	UIChrome.Animate(theme, btn)
end

-- ========================================================================
-- GIRLY POP layout (theme.LayoutKit == "GP")
-- ========================================================================
-- The options menu as the STUDIO's own worksheet: the kit's cream Page (rose
-- header ribbon with its glaze sheen and scalloped lip, clay-speckle paper, a
-- petal close chip) over a scroll of petal-cornered option rows.
--
-- ANTI-CONDESCENSION (pack law 6) is the whole brief here: EVERY SettingsConfig
-- section, EVERY row, EVERY control kind and EVERY current value survives the
-- re-skin. Nothing is merged, hidden behind a sub-page or rounded off — the
-- sliders keep their exact `decimals` readout, the dropdowns keep their full
-- option list, the toggles keep their state word. The row engine is untouched:
-- one functional row per config row, all changes funnelling through
-- self:_ApplyChange(id, value) exactly as they always did.
--
-- The CONTROLS are rebuilt rather than reused because the classic recipes frame
-- themselves with UIChrome.Stroke, which under this pack's Chrome
-- (StrokeFollowsAccent = false) returns a BLACK hairline that pack law 1
-- forbids outright — and because hard 90° arcade corners on a pastel worksheet
-- would read as a rendering error. Geometry, callbacks and quantisation are
-- carried over verbatim.
function SettingsScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = gpTitleCase(self:_R("settings.title")),
		subtitleText = "Tune the studio to your liking.",
		-- WIDER than the classic 780 card, never narrower: the row's label
		-- column is whatever is left after the widest control, so growing the
		-- page can only give a long setting name MORE room.
		sizePx = Vector2.new(900, 700),
		onClose = function()
			self.ScreenController:HideScreen("settings")
		end,
	})
	self._gpPage = page
	-- The page's own sink owns the header/close/panel shadows; every row and
	-- control shadow joins it, and _OnTeardown hands the lot back.
	self._gpShadows = page.shadows
	-- No UIPanelComponent on this page. The base drives the intro through the
	-- registered panel, so a two-method shim gives the GP page the house POP
	-- without touching the shared Show/Hide path.
	self._panel = nil
	self:_SetAnimatedPanel({
		AnimateIn = function(_self: any)
			UIChrome.PopIn(self:GetTheme(), page.panel)
		end,
		AnimateOut = function(_self: any)
			return nil
		end,
	} :: any)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	-- Explicit: content leaking past a scrolling frame is a known past bug here.
	scroll.ClipsDescendants = true
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Colors.Primary
	scroll.Parent = page.content
	self._scroll = scroll

	-- The padding is what keeps a row's soft shadow off the clip edge: 10px on
	-- the left and 14px on the right (the extra is the scrollbar gutter).
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 16)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = scroll

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, LIST_PAD)
	layout.Parent = scroll

	self:_GPBuildRows()
end

-- Same cleanup contract as _BuildRows: old rows die and the tracked GLOBAL
-- input connections (slider drags on UserInputService, which are bound to no
-- Instance) disconnect before any new ones are made.
function SettingsScreen:_GPBuildRows()
	for _, inst in self._rows do
		inst:Destroy()
	end
	table.clear(self._rows)
	for _, conn in self._conns do
		conn:Disconnect()
	end
	table.clear(self._conns)

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local rowIndex = 0
	for _, section in SettingsConfig.Sections do
		self:_GPSectionHeader(self:_R(section.titleKey), nextOrder())
		for _, row in section.rows do
			rowIndex += 1
			self:_GPBuildRow(row, nextOrder(), rowIndex)
		end
	end
end

-- Section voice: the display face in INK over a sage squiggle. Copy passes
-- through VERBATIM — the classic header shouts it, this pack never does.
function SettingsScreen:_GPSectionHeader(text: string, order: number)
	local theme = self:GetTheme()
	local holder = UIStyler.Frame("SectionHeader")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, HEADER_H + 18)
	holder.LayoutOrder = order
	holder.Parent = self._scroll

	local label = GPLayoutKit.Text(theme, 22, theme.Colors.TextPrimary, "Title")
	label.Size = UDim2.new(1, -8, 0, HEADER_H)
	label.Position = UDim2.fromOffset(4, 0)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = holder

	local rule = GPLayoutKit.Divider(theme, holder)
	rule.Position = UDim2.fromOffset(4, HEADER_H)
	rule.Size = UDim2.new(1, -12, 0, 16)

	table.insert(self._rows, holder)
end

-- The 60px option row: a petal plate (mirrored by index so the stack reads
-- hand-arranged), a 2px stroke in a DEEPENED tint of its own fill, a soft
-- hue-matched shadow, the archive icon in its authored slot and an ink label.
-- Same height, same icon slot, same label column as the classic row.
function SettingsScreen:_GPSettingRow(icon: string, text: string, order: number, index: number): Frame
	local theme = self:GetTheme()
	local fill = theme.Colors.SurfaceRaised

	local row = UIStyler.Frame("SettingRow")
	row.BackgroundColor3 = fill
	row.BackgroundTransparency = 0
	row.Size = UDim2.new(1, 0, 0, ROW_H)
	row.LayoutOrder = order
	GPLayoutKit.Petal(theme, row, index)
	GPLayoutKit.SoftStroke(theme, row, fill)
	GPLayoutKit.Shadow(theme, row, "sm", self._gpShadows, fill)

	-- Through the KIT, not the archive directly: the archive's glyph FALLBACK
	-- (which stands in when a role has no uploaded art) is born pure white on a
	-- pure black text stroke, and both are banned here.
	local iconImage = GPLayoutKit.Icon(theme, row, icon, 32)
	iconImage.AnchorPoint = Vector2.new(0, 0.5)
	iconImage.Position = UDim2.new(0, 14, 0.5, 0)
	iconImage.ZIndex = 2

	local label = GPLayoutKit.Text(theme, 20, theme.Colors.TextPrimary, "RowLabel")
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, LABEL_X, 0.5, 0)
	-- Leave the right ~360px for the widest control (slider + inset), exactly
	-- as classic does — the wider page hands the surplus to the label.
	label.Size = UDim2.new(1, -(LABEL_X + SLIDER_W + CONTROL_INSET * 2), 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = text
	label.ZIndex = 2
	label.Parent = row

	row.Parent = self._scroll
	return row
end

-- One functional row per config row — the same dispatch, the same initial
-- values read from self._state, the same _ApplyChange callbacks as classic.
function SettingsScreen:_GPBuildRow(row: any, order: number, index: number)
	local value = self._state[row.id]
	local icon = ROW_ICON[row.id] or KIND_ICON[row.kind] or "star"
	if row.kind == "Toggle" then
		local shell = self:_GPSettingRow(icon, self:_R(row.labelKey), order, index)
		self:_GPToggleControl(shell, value == true, function(v: boolean)
			self:_ApplyChange(row.id, v)
		end)
		table.insert(self._rows, shell)
	elseif row.kind == "Slider" then
		local shell = self:_GPSettingRow(icon, self:_R(row.labelKey), order, index)
		self:_GPSliderControl(shell, row, tonumber(value) or row.min or 0, function(v: number)
			self:_ApplyChange(row.id, v)
		end)
		table.insert(self._rows, shell)
	elseif row.kind == "Dropdown" then
		local shell = self:_GPSettingRow(icon, self:_R(row.labelKey), order, index)
		local options = {}
		for _, opt in row.options do
			table.insert(options, { id = opt.id, text = self:_R(opt.textKey) })
		end
		self:_GPDropdownControl(shell, options, value, function(id: string)
			self:_ApplyChange(row.id, id)
		end)
		table.insert(self._rows, shell)
	end
end

-- The phase pill in the pack's language: the SAME 88×28 track, the SAME knob
-- travel and the SAME "chosen!" pulse when it lands ON — matcha when on, the
-- pale ruler track when off, with the state word in ink beside the knob.
-- The pill's stroke retints with its fill, which is the hue-match rule shown in
-- an interactive state. Copy is sentence case: this pack does not shout "ON".
function SettingsScreen:_GPToggleControl(row: Frame, initial: boolean, onChanged: (boolean) -> ())
	local theme = self:GetTheme()
	local motion = theme.Motion

	local offKnobPos = UDim2.new(0, 3, 0.5, 0)
	local onKnobPos = UDim2.new(0, TOGGLE_W - TOGGLE_KNOB - 3, 0.5, 0)
	-- The state word sits on the side the knob is NOT on.
	local offTextPos = UDim2.fromOffset(TOGGLE_KNOB + 6, 0)
	local onTextPos = UDim2.fromOffset(6, 0)
	local onFill = theme.Colors.Secondary
	local offFill = theme.Arcade.RulerTrack

	-- Transparent hit target: a SOLID GuiButton trips UIStyleEnforcer's black
	-- stroke backstop, which this pack forbids on sight.
	local hit = Instance.new("TextButton")
	hit.Name = "ToggleTrack"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromOffset(TOGGLE_W, TOGGLE_H)
	hit.AnchorPoint = Vector2.new(1, 0.5)
	hit.Position = UDim2.new(1, -CONTROL_INSET, 0.5, 0)
	hit.ZIndex = 3
	hit.Parent = row

	local track = UIStyler.Frame("Pill")
	track.BackgroundColor3 = if initial then onFill else offFill
	track.BackgroundTransparency = 0
	track.Size = UDim2.fromScale(1, 1)
	track.ZIndex = 3
	track.Parent = hit
	UIStyler.Corner(theme.Radii.Pill).Parent = track
	local trackStroke = GPLayoutKit.SoftStroke(theme, track, if initial then onFill else offFill)

	local stateLabel = GPLayoutKit.BodyText(
		theme,
		13,
		if initial then theme.Colors.TextPrimary else theme.Colors.TextSecondary,
		"State"
	)
	stateLabel.Size = UDim2.new(1, -(TOGGLE_KNOB + 12), 1, 0)
	stateLabel.Position = if initial then onTextPos else offTextPos
	stateLabel.Text = if initial then "On" else "Off"
	stateLabel.ZIndex = 4
	stateLabel.Parent = track

	local knob = UIStyler.Frame("Knob")
	knob.BackgroundTransparency = 0
	knob.BackgroundColor3 = theme.Colors.Background
	knob.Size = UDim2.fromOffset(TOGGLE_KNOB, TOGGLE_KNOB)
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Position = if initial then onKnobPos else offKnobPos
	knob.ZIndex = 5
	UIStyler.Corner(theme.Radii.Pill).Parent = knob
	GPLayoutKit.SoftStroke(theme, knob, theme.Colors.Background)
	knob.Parent = track

	-- Hover/press juice on a UIScale (never a Size change). Deliberately NOT
	-- UIChrome.Animate: its hover fill-lerp snapshots the rest colour on enter,
	-- and a click-while-hovered recolour (OFF→ON) would be reverted on leave.
	local scale = Instance.new("UIScale")
	scale.Parent = track
	self:_Track(hit.MouseEnter:Connect(function()
		TweenService:Create(scale, motion.HoverIn, { Scale = motion.HoverScale }):Play()
	end))
	self:_Track(hit.MouseLeave:Connect(function()
		TweenService:Create(scale, motion.HoverOut, { Scale = 1 }):Play()
	end))
	self:_Track(hit.MouseButton1Down:Connect(function()
		TweenService:Create(scale, motion.PressIn, { Scale = motion.PressScale }):Play()
	end))
	self:_Track(hit.MouseButton1Up:Connect(function()
		TweenService:Create(scale, motion.HoverIn, { Scale = motion.HoverScale }):Play()
	end))

	local on = initial
	self:_Track(hit.Activated:Connect(function()
		on = not on
		local fill = if on then onFill else offFill
		TweenService:Create(knob, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = if on then onKnobPos else offKnobPos,
		}):Play()
		TweenService:Create(track, motion.HoverOut, { BackgroundColor3 = fill }):Play()
		trackStroke.Color = GPLayoutKit.Deepen(theme, fill, 1)
		stateLabel.Text = if on then "On" else "Off"
		stateLabel.TextColor3 = if on then theme.Colors.TextPrimary else theme.Colors.TextSecondary
		stateLabel.Position = if on then onTextPos else offTextPos
		if on then
			-- "Chosen!" spike when the phase lands ON (capped by Motion.PulseScale).
			UIChrome.Pulse(theme, track)
		end
		onChanged(on)
	end))
end

-- The slider, geometry for geometry: the same 310px holder, 230px rail, 6px
-- fill, 26px knob swelling 1.15× while held, the same quantisation, the same
-- whole-strip hit target and the SAME `decimals` readout — a soft pack does not
-- get to round a value off. Pastel: a pale pill rail, a butter-gold fill
-- (gold means value here too) and a cream knob rimmed in deepened rose.
function SettingsScreen:_GPSliderControl(row: Frame, spec: any, initial: number, onChanged: (number) -> ())
	local theme = self:GetTheme()
	local motion = theme.Motion
	local min = spec.min or 0
	local max = spec.max or 100
	local step = spec.step or 1
	local decimals = spec.decimals or 0
	local span = max - min
	if span == 0 then
		span = 1
	end
	local fmt = "%." .. tostring(decimals) .. "f"

	local holder = UIStyler.Frame("SliderControl")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(0, SLIDER_W, 1, 0)
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, -CONTROL_INSET, 0.5, 0)
	holder.ZIndex = 3
	holder.Parent = row

	-- Tabular numerals so the readout does not jitter as it counts.
	local readout = GPLayoutKit.NumberText(theme, 14, theme.Colors.TextPrimary, "Value")
	readout.Size = UDim2.fromOffset(64, 20)
	readout.AnchorPoint = Vector2.new(1, 0.5)
	readout.Position = UDim2.new(1, 0, 0.5, 0)
	readout.ZIndex = 4
	readout.Parent = holder

	local railFill = theme.Arcade.RulerTrack
	local rail = UIStyler.Frame("Rail")
	rail.BackgroundTransparency = 0
	rail.BackgroundColor3 = railFill
	rail.Size = UDim2.fromOffset(RAIL_W, RAIL_H)
	rail.AnchorPoint = Vector2.new(0, 0.5)
	rail.Position = UDim2.new(0, 0, 0.5, 0)
	rail.ZIndex = 4
	UIStyler.Corner(theme.Radii.Pill).Parent = rail
	GPLayoutKit.SoftStroke(theme, rail, railFill)
	rail.Parent = holder

	local fill = UIStyler.Frame("Fill")
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = theme.Colors.Accent
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.new(0, 0, 0.5, 0)
	fill.Size = UDim2.new(0, 0, 0, FILL_H)
	fill.ZIndex = 5
	UIStyler.Corner(theme.Radii.Pill).Parent = fill
	fill.Parent = rail

	local knob = UIStyler.Frame("Knob")
	knob.BackgroundTransparency = 0
	knob.BackgroundColor3 = theme.Colors.Background
	knob.Size = UDim2.fromOffset(SLIDER_KNOB, SLIDER_KNOB)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.new(0, 0, 0.5, 0)
	knob.ZIndex = 6
	UIStyler.Corner(theme.Radii.Pill).Parent = knob
	GPLayoutKit.SoftStroke(theme, knob, theme.Colors.Primary)
	knob.Parent = rail
	local knobScale = Instance.new("UIScale")
	knobScale.Parent = knob

	-- Whole-strip invisible hit target (doc §11.6): the rail zone at full row
	-- height, so there are no dead zones around the thin rail.
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.BorderSizePixel = 0
	hit.Size = UDim2.new(0, RAIL_W + SLIDER_KNOB, 1, 0)
	hit.Position = UDim2.new(0, -SLIDER_KNOB // 2, 0, 0)
	hit.ZIndex = 7
	hit.Parent = holder

	local function quantize(raw: number): number
		local snapped = min + math.floor((raw - min) / step + 0.5) * step
		return math.clamp(snapped, min, max)
	end

	-- Scale-positioned fill/knob: immune to the baseline UIScale.
	local function render(value: number)
		local frac = (value - min) / span
		fill.Size = UDim2.new(frac, 0, 0, FILL_H)
		knob.Position = UDim2.new(frac, 0, 0.5, 0)
		readout.Text = string.format(fmt, value)
	end
	render(quantize(initial))

	local function setHeld(held: boolean)
		TweenService:Create(knobScale, if held then motion.HoverIn else motion.HoverOut, {
			Scale = if held then KNOB_HELD_SCALE else 1,
		}):Play()
	end

	local dragging = false
	local function applyFromX(x: number)
		local absPos = rail.AbsolutePosition.X
		local absW = rail.AbsoluteSize.X
		if absW <= 0 then
			return
		end
		local frac = math.clamp((x - absPos) / absW, 0, 1)
		local value = quantize(min + frac * span)
		render(value)
		onChanged(value)
	end

	self:_Track(hit.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setHeld(true)
			applyFromX(input.Position.X)
		end
	end))
	self:_Track(UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			applyFromX(input.Position.X)
		end
	end))
	self:_Track(UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if dragging then
				dragging = false
				setHeld(false)
			end
		end
	end))
end

-- The cycle-box, same 220×36 footprint and the same full option list (no
-- overlay list: the page clips its descendants, so an expanding list would be
-- cut off). A blush petal chip with an ink label and a rose "▸" affordance.
-- The press juice always plays — every tap answers (doc §11.1).
function SettingsScreen:_GPDropdownControl(row: Frame, options: { { id: string, text: string } }, initialId: any, onChanged: (string) -> ())
	local theme = self:GetTheme()

	local idx = 1
	for i, opt in options do
		if opt.id == initialId then
			idx = i
			break
		end
	end

	local btn = Instance.new("TextButton")
	btn.Name = "DropdownControl"
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.BackgroundTransparency = 1 -- solid buttons trip the enforcer's black stroke
	btn.Size = UDim2.fromOffset(DROP_W, DROP_H)
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -CONTROL_INSET, 0.5, 0)
	btn.ZIndex = 3
	btn.Parent = row

	local chipFill = theme.Colors.Surface
	local chip = UIStyler.Frame("Chip")
	chip.BackgroundColor3 = chipFill
	chip.BackgroundTransparency = 0
	chip.Size = UDim2.fromScale(1, 1)
	chip.ZIndex = 3
	chip.Parent = btn
	GPLayoutKit.CornerSet(theme, chip, "Leaf")
	GPLayoutKit.SoftStroke(theme, chip, chipFill)
	GPLayoutKit.Shadow(theme, chip, "sm", self._gpShadows, chipFill)

	local lbl = GPLayoutKit.Text(theme, 20, theme.Colors.TextPrimary, "Current")
	lbl.AnchorPoint = Vector2.new(0, 0.5)
	lbl.Position = UDim2.new(0, 14, 0.5, 0)
	lbl.Size = UDim2.new(1, -46, 1, 0)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.Text = if options[idx] then options[idx].text else ""
	lbl.ZIndex = 4
	lbl.Parent = chip

	-- Cycle affordance — a symbol glyph, so FontFace matters (the kit's display
	-- text builder assigns it; the engine default has no symbol coverage).
	local arrow = GPLayoutKit.Text(theme, 20, theme.Colors.Primary, "Cycle")
	arrow.Size = UDim2.fromOffset(24, DROP_H)
	arrow.AnchorPoint = Vector2.new(1, 0.5)
	arrow.Position = UDim2.new(1, -8, 0.5, 0)
	arrow.Text = "▸"
	arrow.ZIndex = 4
	arrow.Parent = chip

	self:_Track(btn.Activated:Connect(function()
		if #options == 0 then
			return
		end
		idx = (idx % #options) + 1
		lbl.Text = options[idx].text
		onChanged(options[idx].id)
	end))

	UIChrome.Animate(theme, btn, chip)
end

-- A style rebuild destroys the Gui, but the UIShadow BUDGET only falls when a
-- handle is released — and the slider drags live on UserInputService, which is
-- bound to no Instance at all, so both are handed back here.
function SettingsScreen:_OnTeardown()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
	self._gpPage = nil
	for _, conn in self._conns do
		conn:Disconnect()
	end
	table.clear(self._conns)
	table.clear(self._rows)
end

-- ---- AC layout (theme.LayoutKit == "AC") -------------------------------
-- Full-bleed terminal page: left category rail (one entry per SettingsConfig
-- section), right a dense scrolling column of 34px option rows. The CONTROLS
-- are the exact classic recipes (_ToggleControl/_SliderControl/
-- _DropdownControl) with the exact same _ApplyChange callbacks — only the row
-- shell around them speaks the AC language (dim mono label, hairline rule).
function SettingsScreen:_BuildACLayout()
	local theme = self:GetTheme()
	local shell = ACLayoutKit.Shell(theme, self.Root, self:_R("settings.title"))
	ACLayoutKit.SetHints(shell, { { key = "ESC", action = "CLOSE" } })
	-- No modal panel on the terminal page; the base skips panel intros when
	-- none is registered (snap open, the AC fantasy).
	self._panel = nil

	local rail = ACLayoutKit.Rail(theme, shell.content, 200)

	local pane = UIStyler.Frame("Pane")
	pane.BackgroundTransparency = 1
	pane.Position = UDim2.fromOffset(216, 0)
	pane.Size = UDim2.new(1, -216, 1, 0)
	pane.Parent = shell.content

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = theme.Colors.Accent
	scroll.Parent = pane
	self._scroll = scroll

	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 0),
	}).Parent = scroll

	for index, section in SettingsConfig.Sections do
		rail.AddEntry(self:_R(section.titleKey), function()
			self:_ACBuildSection(index)
		end)
	end
	rail.Select(1)
	self:_ACBuildSection(1)
end

-- Swap the right-hand column to one SettingsConfig section. Same cleanup
-- contract as _BuildRows: old rows die, tracked global input connections
-- (slider drags) disconnect before new ones are made.
function SettingsScreen:_ACBuildSection(sectionIndex: number)
	local theme = self:GetTheme()
	local section = SettingsConfig.Sections[sectionIndex]
	if not section then
		return
	end

	for _, inst in self._rows do
		inst:Destroy()
	end
	table.clear(self._rows)
	for _, conn in self._conns do
		conn:Disconnect()
	end
	table.clear(self._conns)

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local sectionLabel = ACLayoutKit.SectionLabel(theme, self._scroll, self:_R(section.titleKey), nextOrder())
	table.insert(self._rows, sectionLabel)
	for _, row in section.rows do
		self:_ACBuildRow(row, nextOrder())
	end
end

-- One dense 34px option row: dim mono uppercase label left, hairline rule
-- underneath, and the SAME control component as classic mounted at the right
-- edge (the control builders anchor themselves to the row's right).
function SettingsScreen:_ACBuildRow(row: any, order: number)
	local theme = self:GetTheme()
	local value = self._state[row.id]

	local shell = UIStyler.Frame("SettingRow")
	shell.BackgroundTransparency = 1
	shell.Size = UDim2.new(1, 0, 0, 34)
	shell.LayoutOrder = order
	shell.Parent = self._scroll

	local label = UIChrome.BodyText("RowLabel", 12, theme.Colors.TextSecondary)
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, 4, 0.5, 0)
	-- Leave the right ~340px free for the widest control (slider + inset).
	label.Size = UDim2.new(1, -(SLIDER_W + CONTROL_INSET * 2 + 4), 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = string.upper(self:_R(row.labelKey))
	label.Parent = shell

	local rule = ACLayoutKit.Rule(theme, shell, 0.85)
	rule.AnchorPoint = Vector2.new(0, 1)
	rule.Position = UDim2.new(0, 0, 1, 0)

	if row.kind == "Toggle" then
		self:_ToggleControl(shell, value == true, function(v: boolean)
			self:_ApplyChange(row.id, v)
		end)
	elseif row.kind == "Slider" then
		self:_SliderControl(shell, row, tonumber(value) or row.min or 0, function(v: number)
			self:_ApplyChange(row.id, v)
		end)
	elseif row.kind == "Dropdown" then
		local options = {}
		for _, opt in row.options do
			table.insert(options, { id = opt.id, text = self:_R(opt.textKey) })
		end
		self:_DropdownControl(shell, options, value, function(id: string)
			self:_ApplyChange(row.id, id)
		end)
	end

	table.insert(self._rows, shell)
end

function SettingsScreen:GetState(): { [string]: any }
	return self._state
end

function SettingsScreen:Destroy()
	for _, conn in self._conns do
		conn:Disconnect()
	end
	table.clear(self._conns)
	UIScreenBase.Destroy(self)
end

return SettingsScreen
