--!strict
-- UIChrome — the Pottery Clash policy helpers (UI_DESIGN_DOCUMENT.md §12).
-- Callers pass INTENT ("Panel", "Button", tan stroke); these helpers decide
-- POLICY (hard 0px corners + 3px black strokes for Arcade, the 16px soft
-- ladder + tan hairlines for Studio). A full re-theme — or a translation to
-- another game — is a one-file change: swap the palette (DefaultTheme) and
-- the two policy functions here, and every surface follows.
--
-- Sits above UIStyler (raw Instance builders) and below components/screens.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Types = require(script.Parent.Types)
local UIStyler = require(script.Parent.UIStyler)

local UIChrome = {}

-- The authoring baseline (doc §7.1): all layout is fixed px at 1650×1020.
UIChrome.BASE_WIDTH = 1650
UIChrome.BASE_HEIGHT = 1020

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

-- The ACTIVE style's chrome policy (Types.UIThemeChrome). Classic defaults
-- when the theme carries none. ClientHandler refreshes this on every theme
-- change; helpers below consult it so a style swap moves the whole chrome
-- language without touching call sites.
local CLASSIC_CHROME: Types.UIThemeChrome = {
	StrokeThickness = 3,
	StrokeFollowsAccent = false,
	StrokeTransparency = 0,
	TextOutline = true,
	TextGlowTransparency = 0.75,
	Bevel = true,
	Glass = true,
}
local activeChrome: Types.UIThemeChrome = CLASSIC_CHROME
local activeAccent: Color3 = Color3.fromRGB(245, 190, 55)
-- The active style's font kit: Text()/BodyText() and the close X follow the
-- STYLE, not a hardcoded family — that is what turns every screen mono when
-- Armored Core is active. Classic's kit IS Fredoka/Gotham, so under the
-- default style these resolve to the exact fonts that were hardcoded before.
local activeDisplayFont: Font = Font.fromEnum(Enum.Font.FredokaOne)
local activeBodyFont: Font = Font.fromEnum(Enum.Font.GothamMedium)

function UIChrome.SetActiveTheme(theme: Types.UITheme)
	activeChrome = theme.Chrome or CLASSIC_CHROME
	activeAccent = theme.Colors.Accent
	activeDisplayFont = theme.Fonts.Title
	activeBodyFont = theme.Fonts.Body
end

function UIChrome.ActiveChrome(): Types.UIThemeChrome
	return activeChrome
end

-- ========================================================================
-- Corner policy
-- ========================================================================

-- Studio corner-radius ladder (doc §4.2): panels 16 → buttons 12 →
-- tools/swatches 10 → sub-options 6 → full pill. Wheel chrome clamps to 5.
local STUDIO_RADII = {
	Panel = 16,
	Button = 12,
	Tool = 10,
	Sub = 6,
	Pill = 1000,
}

export type CornerIntent = "Panel" | "Button" | "Tool" | "Sub" | "Pill" | "Wheel"

function UIChrome.Radius(family: Types.UIFamily, intent: CornerIntent?): number
	-- A style that declares HardCorners flattens EVERYTHING — including the
	-- Studio soft ladder. Pills stay round (knobs, pips: circles are geometry,
	-- not decoration).
	if activeChrome.HardCorners then
		return intent == "Pill" and 1000 or 0
	end
	if family == "Studio" then
		return STUDIO_RADII[intent or "Panel"] or STUDIO_RADII.Panel
	end
	if intent == "Wheel" then
		return 5
	end
	if intent == "Pill" then
		-- Circles/pills are the arcade's only round exception (win pips,
		-- avatar heads) — the 3px-black-box language keeps 90° corners.
		return 1000
	end
	-- HARD ARCADE: zero rounded corners, no caller can deviate (doc §4.1.1).
	return 0
end

function UIChrome.Corner(family: Types.UIFamily, intent: CornerIntent?): UICorner
	return UIStyler.Corner(UIChrome.Radius(family, intent))
end

-- ========================================================================
-- Stroke policy
-- ========================================================================

export type StrokeIntent = "Panel" | "Button" | "Selection" | "Swatch" | "Wheel"

-- Doc §4.1.2 / §4.2 / §4.3: Arcade = ALWAYS a 3px black Border stroke
-- (caller colour/thickness ignored). Studio = tan hairlines: panels
-- tan @ 0.75, buttons tan 1.5px @ 0.7; selection = solid honey 3px;
-- glaze swatches = cream ring 3px. Wheel chrome = thin 1.2px black.
function UIChrome.Stroke(theme: Types.UITheme, family: Types.UIFamily, intent: StrokeIntent?): UIStroke
	-- Per-STYLE chrome (Types.UIThemeChrome) overrides BOTH families: a style
	-- may replace the black 3px arcade language AND the tan Studio hairlines
	-- with e.g. hairline accent framing. Selection stays fully opaque in
	-- every style — it must always read.
	local chrome = theme.Chrome
	if chrome then
		local color = chrome.StrokeFollowsAccent and theme.Colors.Accent or BLACK
		if intent == "Selection" then
			return UIStyler.Stroke(theme.Semantic.Selection, math.max(chrome.StrokeThickness, 1), 0)
		end
		return UIStyler.Stroke(color, chrome.StrokeThickness, chrome.StrokeTransparency)
	end
	if family == "Studio" then
		if intent == "Selection" then
			return UIStyler.Stroke(theme.Studio.Accent, 3, 0)
		elseif intent == "Swatch" then
			return UIStyler.Stroke(theme.Studio.Card, 3, 0.8)
		elseif intent == "Button" then
			return UIStyler.Stroke(theme.Studio.Tan, 1.5, 0.7)
		end
		return UIStyler.Stroke(theme.Studio.Tan, 1, 0.75)
	end
	if intent == "Selection" then
		return UIStyler.Stroke(theme.Semantic.Selection, 3, 0)
	elseif intent == "Wheel" then
		return UIStyler.Stroke(BLACK, 1.2, 0)
	end
	return UIStyler.Stroke(BLACK, 3, 0)
end

-- ========================================================================
-- Gradients (the two house bevels)
-- ========================================================================

-- The glass bevel for panels/cards (doc §4.1.4): vertical transparency fade
-- 0.05 → 0.35 top-to-bottom — a cheap top-lit sheen on every filled surface.
function UIChrome.GlassGradient(): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	-- Styles that reject decorative sheen (Chrome.Glass = false) get the
	-- instance disabled — call sites don't branch, the policy does.
	gradient.Enabled = activeChrome.Glass
	return gradient
end

-- The arcade button bevel (doc §4.1.3): vertical UIGradient multiplying the
-- fill from white at top to RGB(140,140,140) at bottom.
function UIChrome.ArcadeBevel(): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 140, 140)),
	})
	gradient.Enabled = activeChrome.Bevel
	return gradient
end

-- Rainbow gradient (doc §3.2), for STARTER-PACK-style headlines. Pair with
-- UIChrome.ScrollGradient(gradient, 0.45) for the offset scroll.
function UIChrome.RainbowGradient(theme: Types.UITheme): UIGradient
	local stops = theme.Arcade.Rainbow
	local keypoints = {}
	for i, color in stops do
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / (#stops - 1), color))
	end
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(keypoints)
	return gradient
end

-- ========================================================================
-- Frugal RenderStepped effects (doc §5.4): every ambient effect gates on
-- the element being visible AND on-screen before doing any work.
-- ========================================================================

local function isOnScreen(gui: GuiObject): boolean
	if not gui.Visible then
		return false
	end
	local screenGui = gui:FindFirstAncestorOfClass("ScreenGui")
	if screenGui and not screenGui.Enabled then
		return false
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	local viewport = camera.ViewportSize
	local pos, size = gui.AbsolutePosition, gui.AbsoluteSize
	return pos.X + size.X > 0 and pos.Y + size.Y > 0 and pos.X < viewport.X and pos.Y < viewport.Y
end
UIChrome.IsOnScreen = isOnScreen

-- Spin an element (sunbursts 45–60°/s) only while it's actually on screen.
function UIChrome.Spin(gui: GuiObject, degreesPerSecond: number): RBXScriptConnection
	return RunService.RenderStepped:Connect(function(dt: number)
		if isOnScreen(gui) then
			gui.Rotation = (gui.Rotation + degreesPerSecond * dt) % 360
		end
	end)
end

-- Offset-scroll a gradient (rainbow: 0.45 cycles/sec), visibility-gated.
function UIChrome.ScrollGradient(gradient: UIGradient, cyclesPerSecond: number): RBXScriptConnection
	local t = 0
	return RunService.RenderStepped:Connect(function(dt: number)
		local host = gradient.Parent
		if host and host:IsA("GuiObject") and isOnScreen(host) then
			t = (t + cyclesPerSecond * dt) % 1
			gradient.Offset = Vector2.new(t, 0)
		end
	end)
end

-- ========================================================================
-- Surfaces
-- ========================================================================

-- panel(): surface + rim + glass gradient in one call (doc §12). Arcade =
-- slate panel, 3px black stroke, glass sheen; Studio = chocolate at 6%
-- transparency, tan hairline, corner 16.
function UIChrome.Panel(theme: Types.UITheme, family: Types.UIFamily, name: string): Frame
	local panel = UIStyler.Frame(name)
	panel.BackgroundTransparency = 0
	if family == "Studio" then
		panel.BackgroundColor3 = theme.Studio.Panel
		panel.BackgroundTransparency = theme.Studio.PanelTransparency
	else
		panel.BackgroundColor3 = theme.Arcade.Panel
	end
	UIChrome.Corner(family, "Panel").Parent = panel
	UIChrome.Stroke(theme, family, "Panel").Parent = panel
	UIChrome.GlassGradient().Parent = panel
	return panel
end

-- Text emphasis, per the ACTIVE style: Classic = the black outline rule
-- (doc §2 — TextStrokeColor3 black @ 0; world billboards relax via the
-- optional transparency). A style with Chrome.TextOutline = false gets a
-- GLOW instead: a Contextual UIStroke matched to the text colour at high
-- transparency — never the muddy TextStroke halo.
function UIChrome.TextOutline(label: Instance, transparency: number?)
	local textObject = label :: any
	if activeChrome.TextOutline then
		textObject.TextStrokeColor3 = BLACK
		textObject.TextStrokeTransparency = transparency or 0
		-- A glow left over from a styled era must not survive a swap back to
		-- an outline style (persistent surfaces never rebuild — billboards,
		-- nav rail — so the cleanup lives here, in the policy).
		local staleGlow = label:FindFirstChild("TextGlow")
		if staleGlow then
			staleGlow:Destroy()
		end
		return
	end
	textObject.TextStrokeTransparency = 1
	local glow = label:FindFirstChild("TextGlow") :: UIStroke?
	if not glow then
		glow = Instance.new("UIStroke")
		glow.Name = "TextGlow"
		glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		glow.Thickness = 1
		glow.Parent = label
	end
	glow.Color = textObject.TextColor3
	glow.Transparency = activeChrome.TextGlowTransparency
end

-- Display-font label: the active style's Title font (Classic: FredokaOne) at
-- a fixed px size, with the style's text emphasis (outline or glow).
function UIChrome.Text(name: string, size: number, color: Color3): TextLabel
	local label = UIStyler.TextLabel(name)
	label.FontFace = activeDisplayFont
	label.TextSize = size
	label.TextColor3 = color
	UIChrome.TextOutline(label)
	return label
end

-- Quiet body label: the active style's Body font (Classic: GothamMedium), no
-- outline (hint labels, captions).
function UIChrome.BodyText(name: string, size: number, color: Color3): TextLabel
	local label = UIStyler.TextLabel(name)
	label.FontFace = activeBodyFont
	label.TextSize = size
	label.TextColor3 = color
	return label
end

-- ========================================================================
-- animate() — the core button juice (doc §5.1), for RAW GuiButtons built by
-- screens. Components get the identical behaviour from UIComponentBase.
-- Contract: apply LAST, after final colours (it snapshots the rest colour —
-- and re-captures it on every hover, because buttons recolour at runtime).
-- AutoButtonColor is always off: colour+scale is the only feedback story.
-- ========================================================================

function UIChrome.Animate(theme: Types.UITheme, button: GuiButton, scaleTarget: GuiObject?)
	local motion = theme.Motion
	button.AutoButtonColor = false
	local target = scaleTarget or button
	local scale = target:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = target

	local restColor = button.BackgroundColor3
	local solid = button.BackgroundTransparency < 1

	button.MouseEnter:Connect(function()
		restColor = button.BackgroundColor3 -- re-capture: runtime recolours
		TweenService:Create(scale, motion.HoverIn, { Scale = motion.HoverScale }):Play()
		if solid then
			TweenService:Create(button, motion.HoverIn, {
				BackgroundColor3 = restColor:Lerp(WHITE, motion.HoverFillLerp),
			}):Play()
		end
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, motion.HoverOut, { Scale = 1 }):Play()
		if solid then
			TweenService:Create(button, motion.HoverOut, { BackgroundColor3 = restColor }):Play()
		end
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, motion.PressIn, { Scale = motion.PressScale }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, motion.HoverIn, { Scale = motion.HoverScale }):Play()
	end)
end

-- Big-button juice (doc §5.2) for rail buttons / feature cells: hover =
-- 1.12× + 30° tilt; click = squash to 0.82, wait 0.08s, Elastic overshoot
-- back. Applied to the ART child so list layout never reflows.
function UIChrome.AnimateBig(theme: Types.UITheme, button: GuiButton, art: GuiObject)
	local motion = theme.Motion
	button.AutoButtonColor = false
	local scale = art:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = art

	button.MouseEnter:Connect(function()
		TweenService:Create(scale, motion.BigHover, { Scale = motion.BigHoverScale }):Play()
		TweenService:Create(art, motion.BigHover, { Rotation = motion.BigHoverTilt }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, motion.HoverOut, { Scale = 1 }):Play()
		TweenService:Create(art, motion.HoverOut, { Rotation = 0 }):Play()
	end)
	button.Activated:Connect(function()
		TweenService:Create(scale, motion.PressIn, { Scale = motion.BigPressScale }):Play()
		task.delay(0.08, function()
			if scale.Parent then
				TweenService:Create(scale, motion.BigRelease, { Scale = 1 }):Play()
			end
		end)
	end)
end

-- popIn(): entrance pop — scale 0.82 → 1 overshoot ("pop", not slide).
function UIChrome.PopIn(theme: Types.UITheme, gui: GuiObject)
	local motion = theme.Motion
	local scale = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = gui
	scale.Scale = motion.PopFromScale
	TweenService:Create(scale, motion.PopIn, { Scale = 1 }):Play()
end

-- pulse(): "chosen!" feedback on swatches/pills — 1.14 spike then settle.
function UIChrome.Pulse(theme: Types.UITheme, gui: GuiObject)
	local motion = theme.Motion
	local scale = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = gui
	local up = TweenService:Create(scale, motion.PulseUp, { Scale = motion.PulseScale })
	up.Completed:Once(function()
		if scale.Parent then
			TweenService:Create(scale, motion.PulseSettle, { Scale = 1 }):Play()
		end
	end)
	up:Play()
end

-- ========================================================================
-- Modal anatomy (doc §7.4) — ONE recipe for every menu.
-- ========================================================================

export type ModalCard = {
	dim: Frame,
	card: Frame,
	header: Frame,
	title: TextLabel,
	close: TextButton,
	content: Frame,
}

-- The 48×48 red close X (doc §7.4). FredokaOne has no ✕ glyph, so the
-- label is a plain "X".
-- Headers/closes built by ModalCard are raw instances painted once; these
-- tags let a ThemeChanged sweep (wired in ClientHandler) retint every live
-- one when a colour preset moves the red family.
UIChrome.HEADER_TAG = "UIHeaderBar"
UIChrome.CLOSE_TAG = "UICloseButton"

local function makeCloseButton(theme: Types.UITheme): TextButton
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Size = UDim2.fromOffset(48, 48)
	close.BackgroundColor3 = theme.Arcade.Red
	CollectionService:AddTag(close, UIChrome.CLOSE_TAG)
	close.BorderSizePixel = 0
	close.Text = "X"
	close.FontFace = activeDisplayFont
	close.TextSize = 28
	close.TextColor3 = theme.Colors.TextPrimary
	UIChrome.TextOutline(close)
	if theme.Chrome then
		-- Styled chrome: the X frames like every other surface (hairline).
		UIChrome.Stroke(theme, "Arcade", "Button").Parent = close
	else
		UIStyler.Stroke(BLACK, 2, 0).Parent = close
	end
	UIChrome.ArcadeBevel().Parent = close
	return close
end

-- The four corner L-brackets of an AC terminal frame: eight thin accent
-- frames (two per corner). Purely decorative, ZIndex-matched to the host.
local function terminalBrackets(host: GuiObject, theme: Types.UITheme, zIndex: number)
	local accent = theme.Colors.Accent
	local LEN, THICK, PAD = 14, 2, 0
	for _, corner in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		local ax, ay = corner[1], corner[2]
		local h = UIStyler.Frame("BracketH")
		h.BackgroundColor3 = accent
		h.BorderSizePixel = 0
		h.AnchorPoint = Vector2.new(ax, ay)
		h.Position = UDim2.new(ax, ax == 0 and PAD or -PAD, ay, ay == 0 and PAD or -PAD)
		h.Size = UDim2.fromOffset(LEN, THICK)
		h.ZIndex = zIndex
		h.Parent = host
		local v = UIStyler.Frame("BracketV")
		v.BackgroundColor3 = accent
		v.BorderSizePixel = 0
		v.AnchorPoint = Vector2.new(ax, ay)
		v.Position = UDim2.new(ax, ax == 0 and PAD or -PAD, ay, ay == 0 and PAD or -PAD)
		v.Size = UDim2.fromOffset(THICK, LEN)
		v.ZIndex = zIndex
		v.Parent = host
	end
end

-- The AC terminal anatomy behind ModalCard: same return contract, entirely
-- different page. Big cards go FULL-BLEED (48px margin) regardless of the
-- caller's arcade sizePx; small dialogs (< 400px tall) stay centred alerts.
-- Thin 40px top bar (accent tick + mono title + hairline underline), corner
-- brackets, 24px footer hint strip, quiet 32px close X.
local function terminalCard(theme: Types.UITheme, parent: Instance, opts: {
	title: string?,
	sizePx: Vector2?,
	onClose: (() -> ())?,
	showClose: boolean?,
}): ModalCard
	local dim = UIStyler.Frame("Dim")
	dim.BackgroundColor3 = BLACK
	dim.BackgroundTransparency = 0.25
	dim.ZIndex = 40
	dim.Parent = parent

	local size = opts.sizePx or Vector2.new(820, 560)
	local fullBleed = size.Y >= 400

	local card = UIStyler.Frame("Card")
	card.BackgroundColor3 = theme.Colors.Background
	card.BackgroundTransparency = 0.05
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	if fullBleed then
		card.Size = UDim2.new(1, -96, 1, -96)
	else
		card.Size = UDim2.fromOffset(size.X, size.Y)
	end
	card.ZIndex = 41
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = card
	card.Parent = parent
	terminalBrackets(card, theme, 44)

	local header = UIStyler.Frame("Header")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 40)
	header.ZIndex = 42
	CollectionService:AddTag(header, UIChrome.HEADER_TAG)
	header.Parent = card

	-- Hairline underline separating the top bar from the well.
	local rule = UIStyler.Frame("Rule")
	rule.BackgroundColor3 = theme.Colors.Accent
	rule.BackgroundTransparency = 0.5
	rule.BorderSizePixel = 0
	rule.AnchorPoint = Vector2.new(0, 1)
	rule.Position = UDim2.new(0, 0, 1, 0)
	rule.Size = UDim2.new(1, 0, 0, 1)
	rule.ZIndex = 42
	rule.Parent = header

	-- Accent tick block ahead of the title (the AC "section live" marker).
	local tick = UIStyler.Frame("Tick")
	tick.BackgroundColor3 = theme.Colors.Accent
	tick.BorderSizePixel = 0
	tick.AnchorPoint = Vector2.new(0, 0.5)
	tick.Position = UDim2.new(0, 14, 0.5, 0)
	tick.Size = UDim2.fromOffset(4, 16)
	tick.ZIndex = 43
	tick.Parent = header

	local title = UIChrome.Text("Title", 18, theme.Colors.TextPrimary)
	title.Text = opts.title or ""
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(28, 0)
	title.Size = UDim2.new(1, -110, 1, 0)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 43
	title.Parent = header

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Size = UDim2.fromOffset(32, 32)
	close.BackgroundColor3 = theme.Colors.Surface
	close.BackgroundTransparency = 0.2
	CollectionService:AddTag(close, UIChrome.CLOSE_TAG)
	close.BorderSizePixel = 0
	close.Text = "X"
	close.FontFace = activeDisplayFont
	close.TextSize = 16
	close.TextColor3 = theme.Colors.TextSecondary
	UIChrome.TextOutline(close)
	UIChrome.Stroke(theme, "Arcade", "Button").Parent = close
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -10, 0.5, 0)
	close.ZIndex = 43
	close.Visible = opts.showClose ~= false
	close.Parent = header
	if opts.onClose then
		close.Activated:Connect(opts.onClose)
	end
	UIChrome.Animate(theme, close)

	-- Footer hint strip: dim mono, right-aligned, hairline overline.
	local footer = UIStyler.Frame("Footer")
	footer.BackgroundTransparency = 1
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 0, 1, 0)
	footer.Size = UDim2.new(1, 0, 0, 24)
	footer.ZIndex = 42
	footer.Parent = card
	local overline = UIStyler.Frame("Rule")
	overline.BackgroundColor3 = theme.Colors.Accent
	overline.BackgroundTransparency = 0.75
	overline.BorderSizePixel = 0
	overline.Size = UDim2.new(1, 0, 0, 1)
	overline.ZIndex = 42
	overline.Parent = footer
	local hint = UIChrome.BodyText("Hint", 11, theme.Colors.TextSecondary)
	hint.Text = opts.showClose ~= false and "[ESC] CLOSE" or ""
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.Position = UDim2.new(0, 14, 0, 0)
	hint.Size = UDim2.new(1, -28, 1, 0)
	hint.ZIndex = 43
	hint.Parent = footer

	local content = UIStyler.Frame("Content")
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(16, 48)
	content.Size = UDim2.new(1, -32, 1, -80)
	content.ZIndex = 42
	content.Parent = card

	return {
		dim = dim,
		card = card,
		header = header,
		title = title,
		close = close,
		content = content,
	}
end

-- Full-screen black dim @ 0.45 → centred fixed-size card (pure black @ 0.4,
-- 3px black stroke, glass sheen) → red 64px header (FredokaOne 34 white
-- title left, 48×48 red close X at the right end) → transparent content
-- frame inset (14, 74, −28, −88). Open/close is an instant Visible flip —
-- the pop/juice lives on the CONTENTS, not the container.
--
-- Under the AC layout kit the SAME call yields the terminal anatomy above —
-- the modal contract is where a whole-library layout swap happens for free.
function UIChrome.ModalCard(theme: Types.UITheme, parent: Instance, opts: {
	title: string?,
	sizePx: Vector2?,
	onClose: (() -> ())?,
	showClose: boolean?,
}): ModalCard
	if theme.LayoutKit == "AC" then
		return terminalCard(theme, parent, opts)
	end
	local dim = UIStyler.Frame("Dim")
	dim.BackgroundColor3 = BLACK
	dim.BackgroundTransparency = 0.45
	dim.ZIndex = 40
	dim.Parent = parent

	local size = opts.sizePx or Vector2.new(820, 560)
	local card = UIStyler.Frame("Card")
	card.BackgroundColor3 = BLACK
	card.BackgroundTransparency = 0.4 -- the world stays visible through menus
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(size.X, size.Y)
	card.ZIndex = 41
	UIChrome.Stroke(theme, "Arcade").Parent = card
	card.Parent = parent

	local header = UIStyler.Frame("Header")
	header.BackgroundColor3 = theme.Arcade.HeaderRed
	header.Size = UDim2.new(1, 0, 0, 64)
	header.ZIndex = 42
	CollectionService:AddTag(header, UIChrome.HEADER_TAG)
	UIChrome.GlassGradient().Parent = header
	header.Parent = card

	local title = UIChrome.Text("Title", 34, WHITE)
	title.Text = opts.title or ""
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(18, 0)
	title.Size = UDim2.new(1, -84, 1, 0)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 43
	title.Parent = header

	local close = makeCloseButton(theme)
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -8, 0.5, 0)
	close.ZIndex = 43
	close.Visible = opts.showClose ~= false
	close.Parent = header
	if opts.onClose then
		close.Activated:Connect(opts.onClose)
	end
	UIChrome.Animate(theme, close)

	local content = UIStyler.Frame("Content")
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(14, 74)
	content.Size = UDim2.new(1, -28, 1, -88)
	content.ZIndex = 42
	content.Parent = card

	return {
		dim = dim,
		card = card,
		header = header,
		title = title,
		close = close,
		content = content,
	}
end

-- closeButton(): standalone 48×48 red X wired to a callback (doc §12).
function UIChrome.CloseButton(theme: Types.UITheme, parent: Instance, onClose: () -> ()): TextButton
	local close = makeCloseButton(theme)
	close.Parent = parent
	close.Activated:Connect(onClose)
	UIChrome.Animate(theme, close)
	return close
end

-- ========================================================================
-- Semantic lookups
-- ========================================================================

-- Currency colour (doc §3.3: Cash = green, Bux = blue, Robux = magenta,
-- no exceptions). Unknown currencies read as gold/valuable.
function UIChrome.CurrencyColor(theme: Types.UITheme, currencyId: string): Color3
	return theme.Semantic.Currency[currencyId] or theme.Arcade.Gold
end

-- Countdown format (doc §11.3): 1Hz gold FredokaOne, HH:MM:SS / M:SS.
function UIChrome.FormatCountdown(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%02d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

return UIChrome
