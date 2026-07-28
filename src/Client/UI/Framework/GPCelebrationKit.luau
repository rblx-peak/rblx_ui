--!strict
-- GPCelebrationKit — the CELEBRATION half of the "GP" layout language
-- (theme.LayoutKit == "GP", the pack's DialectGlaze). GPLayoutKit builds the
-- PAGE (panel, header, card, tabs, stat row); this builds the parts that only
-- the "you are being given something" screens need — daily rewards, gifts,
-- promo codes, mail attachments, the crate reveal, the prize wheel:
--
--   SoftCase     re-case a SHOUTED shared string for display (law 5)
--   Button       a petal action chip with a UIButtonComponent-SHAPED handle
--   Row          a glossy petal list row (alternating silhouette + fill)
--   RewardChip   the small icon+amount pill a reward is quoted in
--   Countdown    the butter timer pill (caption over HH:MM:SS numerals)
--   Sparkles     twinkle accents — CLAIMABLE STATES ONLY (see the law below)
--   Stamp        the sticker-stamp "Fired!" rosette a claimed thing wears
--   EmptyState   the quiet nothing-here treatment
--   Icon         an archive icon that is safe to put on a pastel page
--
-- WHY THIS EXISTS SEPARATELY FROM GPLayoutKit: the six celebration screens all
-- need the same claim vocabulary and none of it belongs in the page kit, which
-- is deliberately state-free static composition. Everything here is state — a
-- thing is claimable, claimed, expired, or locked — and the pack's rule for
-- state is that it reads in the SILHOUETTE and the SHADOW, not in a grey-out.
--
-- THE LAWS THIS KIT ENFORCES SO CALLERS CANNOT BREAK THEM:
--   * NO pure black, NO pure white. Every Frame is painted (UIStyler.Frame is
--     born pure white), every TextLabel is coloured (born pure-white text), and
--     the IconArchive GLYPH FALLBACK — which is born white-with-a-black-stroke
--     — is repainted to pack ink before it is ever parented into a page.
--   * SHADOWS ARE HUE-MATCHED. Every shadow goes through GPLayoutKit.Shadow /
--     .Glow, which derive the colour from the element's own fill. A rose claim
--     button casts rose; a matcha one casts matcha. Nothing here casts grey.
--   * BODY COPY ON PASTEL IS TextPrimary. Colors.TextOnPrimary (near-white)
--     measures 2.14:1 on rose and appears nowhere in this file — not on a
--     button label, not on a chip, not on a stamp.
--   * SPARKLES ARE A CLAIMABLE-STATE SIGNAL, NOT DECORATION. Sparkles() starts
--     hidden and SetEnabled(true) is the ONLY way to show it. If everything
--     twinkles, twinkling stops meaning "this one is ready for you".
--   * NOTHING ROTATES. The GL clipping law (ClipsDescendants is axis-aligned
--     and does NOT clip a ROTATED descendant) would bite hard here, because
--     every one of these parts lives inside a scrolling reward list. The
--     sticker stamp is therefore a ROSETTE, not a tilted rubber stamp — the
--     stamped-and-done read comes from the burst silhouette and the ink shout.
--   * ANTI-CONDESCENSION. Nothing here removes a column, a row, a timer or a
--     precision digit. Button() keeps a dimmed button LIVE (every tap answers),
--     because hiding a blocked action is how a screen ends up "simplified".
--
-- MOTION: this file composes STATICALLY and exposes Step(now) seams instead of
-- opening loops. Sparkles.Step / Glow breathing are driven by the calling
-- screen's ONE UITicker handler — no RunService connection is opened here.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local IconVisibility = require(script.Parent.Parent.Icons.IconVisibility)
local GPLayoutKit = require(script.Parent.GPLayoutKit)

local GPCelebrationKit = {}

-- ---- pack constants ----------------------------------------------------

local CHIP_H = 32
local CHIP_ICON = 20
local CHIP_GAP = 4
local COUNTDOWN_W = 168
local COUNTDOWN_H = 58
local STAMP_TEXT_INSET = 0.24

-- Sparkles sit on a RING around their host, at fixed normalized points, so a
-- claimable tile reads as "haloed" rather than "speckled". Ordered so the
-- first few (the common count) already surround the host.
local SPARKLE_POINTS: { { number } } = {
	{ 0.06, 0.12 },
	{ 0.93, 0.09 },
	{ 0.97, 0.62 },
	{ 0.10, 0.72 },
	{ 0.50, 0.02 },
	{ 0.78, 0.95 },
	{ 0.24, 0.96 },
	{ 0.02, 0.40 },
}
local SPARKLE_SIZES: { number } = { 18, 13, 16, 14, 20, 15, 12, 17 }
local SPARKLE_SPEED = 2.1
local SPARKLE_AMP = 0.42

-- Acronyms and roman numerals that must survive SoftCase. Same set the sibling
-- GPStudioKit keeps, plus the currency/product shorthand these screens quote.
local KEEP_UPPER: { [string]: boolean } = {
	RP = true, XP = true, HP = true, MP = true, KO = true, ID = true, OK = true,
	VIP = true, PVP = true, PVE = true, MVP = true, AFK = true, TNT = true,
	I = true, II = true, III = true, IV = true, V = true, VI = true,
	VII = true, VIII = true, IX = true, X = true, XI = true, XII = true,
}

-- ---- local helpers -----------------------------------------------------

-- A Frame that is ALWAYS painted: UIStyler.Frame is born pure white, which the
-- pack forbids outright, so no builder here may use it bare.
local function surface(name: string, fill: Color3, transparency: number?): Frame
	local frame = UIStyler.Frame(name)
	frame.BackgroundColor3 = fill
	frame.BackgroundTransparency = transparency or 0
	return frame
end

local function dialect(theme: Types.UITheme, name: string): { [string]: any }
	local tokens = (theme :: any).DialectTokens
	return (tokens and tokens[name]) or {}
end

-- ========================================================================
-- Copy
-- ========================================================================

-- Title-case a SHOUTED data string. This matters more here than anywhere else
-- in the pack: the claim vocabulary ("CLAIM", "CLAIMED", "EXPIRED", "REDEEMED")
-- is written by SHARED lifecycle code — a gift's expiry ticker, a redeem
-- result, a mail claim — that every kit runs, and law 5 forbids shouting under
-- this one. Re-casing for DISPLAY keeps that shared logic byte-identical.
--
-- A string already carrying a lowercase letter is the author's own casing and
-- passes through verbatim, so a player's DisplayName, "Kiln & Cobalt" and a
-- hand-written GP caption are all safe. RichText markup (anything with a "<")
-- is passed through whole rather than risking a mangled tag. Same contract as
-- the sibling GPStudioKit.SoftCase, so the two kits never disagree on a word.
function GPCelebrationKit.SoftCase(text: string): string
	if text == "" or string.find(text, "<", 1, true) or string.match(text, "%l") then
		return text
	end
	local out = string.gsub(text, "[%a']+", function(word: string): string
		if KEEP_UPPER[word] then
			return word
		end
		return string.upper(string.sub(word, 1, 1)) .. string.lower(string.sub(word, 2))
	end)
	return out
end

-- ========================================================================
-- Icons
-- ========================================================================

export type IconOptions = {
	golden: boolean?,
	tint: Color3?,
	transparency: number?,
}

-- An archive icon that is SAFE on a pastel page. IconArchive.Image's own glyph
-- fallback is a pure-white TextLabel wearing a pure-black text stroke — both
-- colours the pack bans — so the fallback is rebuilt here in ink instead.
-- Registered with IconVisibility either way, so the global icon toggle still
-- owns it.
function GPCelebrationKit.Icon(
	theme: Types.UITheme,
	parent: Instance?,
	key: string,
	sizePx: number,
	opts: IconOptions?
): GuiObject
	local options = opts or {}
	local assetId = IconArchive.Id(key, { golden = options.golden })
	if assetId then
		local image = Instance.new("ImageLabel")
		image.Name = "Icon_" .. key
		image.BackgroundTransparency = 1
		image.Image = assetId
		image.ScaleType = Enum.ScaleType.Fit
		image.Size = UDim2.fromOffset(sizePx, sizePx)
		if options.tint then
			image.ImageColor3 = options.tint
		end
		image.ImageTransparency = options.transparency or 0
		image.Parent = parent
		IconVisibility.Register(image)
		return image
	end

	local glyph = UIStyler.TextLabel("IconGlyph_" .. key)
	glyph.Text = IconArchive.Glyph(key)
	glyph.FontFace = theme.Fonts.Title
	glyph.TextScaled = true
	glyph.RichText = false
	glyph.TextColor3 = options.tint or theme.Colors.TextPrimary
	glyph.TextTransparency = options.transparency or 0
	glyph.TextStrokeTransparency = 1 -- the pack has no black halo
	glyph.Size = UDim2.fromOffset(sizePx, sizePx)
	glyph.Parent = parent
	IconVisibility.Register(glyph)
	return glyph
end

-- Repaint an icon built above (either representation) without caring which one
-- it turned out to be — the state repaints in every screen go through here.
function GPCelebrationKit.TintIcon(icon: GuiObject, tint: Color3, transparency: number?)
	local target: any = icon
	if icon:IsA("ImageLabel") or icon:IsA("ImageButton") then
		target.ImageColor3 = tint
		target.ImageTransparency = transparency or 0
	elseif icon:IsA("TextLabel") or icon:IsA("TextButton") then
		target.TextColor3 = tint
		target.TextTransparency = transparency or 0
	end
end

-- ========================================================================
-- Buttons
-- ========================================================================

export type ButtonContent = {
	text: string?,
	variant: string?,
	dimmed: boolean?,
	enabled: boolean?,
}

export type ButtonOptions = {
	text: string?,
	variant: string?,
	dimmed: boolean?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	textSize: number?,
	cornerIndex: number?,
	glaze: boolean?,
	onClick: (() -> ())?,
}

export type Button = {
	Root: TextButton,
	Chip: Frame,
	Label: TextLabel,
	Shadow: any,
	SetContent: (Button, ButtonContent) -> (),
	Destroy: (Button) -> (),
}

-- Every arcade/legacy variant NAME still resolves, re-expressed in this pack's
-- own tokens (no colour literals). "Green" is the go-ahead in every caller, so
-- it maps to the pack's matcha; "Grey" is the blocked-or-done state.
local function variantFill(theme: Types.UITheme, variant: string?): Color3
	local a = theme.Arcade
	local v = variant or "Primary"
	if v == "Green" or v == "Success" then
		return theme.Colors.Secondary
	elseif v == "Red" or v == "Danger" then
		return theme.Colors.Error
	elseif v == "Gold" or v == "Accent" then
		return theme.Colors.Accent
	elseif v == "Blue" then
		return a.Blue
	elseif v == "Magenta" or v == "Secondary" then
		return a.Magenta
	elseif v == "Orange" then
		return a.Orange
	elseif v == "Grey" then
		return theme.Colors.Disabled
	end
	return theme.Colors.Primary
end

-- A petal action chip. The BUTTON ITSELF stays transparent and the fill lives
-- on a chip child, because UIStyleEnforcer backstops any SOLID GuiButton in an
-- Arcade-family screen with a BLACK 2px stroke — which would violate pack law 1
-- on sight. A transparent button never trips it.
--
-- The returned handle is deliberately UIButtonComponent-SHAPED (.Root /
-- :SetContent / :Destroy) so a screen's existing render, ticker and teardown
-- paths can hold a GP button in the same field they held an arcade one, with
-- no branch of their own.
--
-- WHY NOT GPBouncyButton: that component is the richer CTA (squash/stretch,
-- decaying hover wobble, StateDriver tags, reduce-motion) and is the right
-- choice for a GP-NATIVE call site. It takes a `fillToken` (a Colors.* key),
-- not the legacy `variant`/`dimmed` pair — so a shared ticker calling
-- :SetContent({ text = "EXPIRED", variant = "Grey", dimmed = true }) would
-- retitle it while leaving it green. These six screens all drive their buttons
-- from exactly that shared vocabulary, so this handle speaks it instead, and
-- retints its stroke AND its hue-matched shadow with every state change.
function GPCelebrationKit.Button(theme: Types.UITheme, parent: Instance, opts: ButtonOptions, sink: { any }?): Button
	local spacing = theme.Spacing
	local zIndex = opts.zIndex or 4

	local root = Instance.new("TextButton")
	root.Name = "GPButton"
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.Size = opts.size or UDim2.fromOffset(180, 46)
	root.Position = opts.position or UDim2.fromOffset(0, 0)
	root.AnchorPoint = opts.anchorPoint or Vector2.new(0, 0)
	root.ZIndex = zIndex
	if opts.layoutOrder then
		root.LayoutOrder = opts.layoutOrder
	end
	root.Parent = parent

	local fill = opts.dimmed and theme.Colors.Disabled or variantFill(theme, opts.variant)
	local chip = surface("Chip", fill, 0)
	chip.Size = UDim2.fromScale(1, 1)
	chip.ZIndex = zIndex
	chip.Parent = root
	-- Corner FIRST, then the sheen: GlazeSheen clones the host's UICorner so the
	-- wash matches the petal silhouette exactly (the kit's ordering contract).
	GPLayoutKit.Petal(theme, chip, opts.cornerIndex or 0)
	local stroke = GPLayoutKit.SoftStroke(theme, chip, fill)
	local shadow = GPLayoutKit.Shadow(theme, chip, "sm", sink, fill)
	if opts.glaze ~= false then
		GPLayoutKit.GlazeSheen(theme, chip)
	end

	-- Ink, never TextOnPrimary: a 17px button label is body copy, and near-white
	-- body copy on any of these pastels fails contrast (2.14:1 on rose).
	local label = GPLayoutKit.Text(theme, opts.textSize or theme.TextSizes.Button, theme.Colors.TextPrimary, "Label")
	-- SoftCase, not string.upper: shared lifecycle code hands this widget
	-- arcade-cased captions ("CLAIM ALL", "EXPIRED") and this pack never shouts.
	label.Text = GPCelebrationKit.SoftCase(opts.text or "")
	label.RichText = false
	label.Size = UDim2.new(1, -spacing.S, 1, 0)
	label.Position = UDim2.fromOffset(spacing.XS, 0)
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = zIndex + 3 -- above the glaze wash (+1) and its sheen arc (+2)
	label.Parent = chip

	local handle: any = {}
	handle.Root = root
	handle.Chip = chip
	handle.Label = label
	handle.Shadow = shadow

	function handle.SetContent(_, content: ButtonContent)
		if content.text ~= nil then
			label.Text = GPCelebrationKit.SoftCase(content.text)
		end
		local blocked = content.dimmed == true or content.enabled == false
		local nextFill = blocked and theme.Colors.Disabled or variantFill(theme, content.variant or opts.variant)
		local deep = GPLayoutKit.Deepen(theme, nextFill, 1)
		chip.BackgroundColor3 = nextFill
		stroke.Color = deep
		shadow.Instance.Color = deep
		-- A blocked button DIMS but stays live (doc §11.1): every tap answers.
		label.TextColor3 = blocked and theme.Colors.TextSecondary or theme.Colors.TextPrimary
	end

	function handle.Destroy(_)
		shadow:Release()
		root:Destroy()
	end

	if opts.dimmed then
		handle:SetContent({ dimmed = true, variant = opts.variant })
	end
	if opts.onClick then
		root.Activated:Connect(opts.onClick)
	end
	-- Animate LAST, after the final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, root, chip)
	return handle :: Button
end

-- ========================================================================
-- Rows
-- ========================================================================

export type Row = {
	root: TextButton,
	body: Frame,
	stroke: UIStroke,
	shadow: any,
	SetTone: (Color3) -> (),
}

-- A glossy petal list row. The silhouette ALTERNATES by index (Petal /
-- PetalMirror) so a stack of them reads hand-arranged rather than stamped, and
-- the fill alternates with it — this pack's answer to the arcade zebra, which
-- it cannot use because both GP row fills are light.
function GPCelebrationKit.Row(theme: Types.UITheme, parent: Instance, index: number, sink: { any }?, opts: {
	heightPx: number?,
	widthPx: number?,
	glaze: boolean?,
	zIndex: number?,
}?): Row
	local o = opts or {}
	local zIndex = o.zIndex or 4
	local i = index or 0

	local root = Instance.new("TextButton")
	root.Name = "GPRow"
	root.BackgroundTransparency = 1 -- see the enforcer note in Button
	root.Text = ""
	root.AutoButtonColor = false
	root.Size = if o.widthPx
		then UDim2.fromOffset(o.widthPx, o.heightPx or 120)
		else UDim2.new(1, 0, 0, o.heightPx or 120)
	root.LayoutOrder = i
	root.ZIndex = zIndex
	root.Parent = parent

	local fill = (i % 2 == 0) and theme.Colors.SurfaceRaised or theme.Colors.Surface
	local body = surface("Body", fill, 0)
	body.Size = UDim2.fromScale(1, 1)
	body.ZIndex = zIndex
	body.Parent = root
	GPLayoutKit.Petal(theme, body, i)
	local stroke = GPLayoutKit.SoftStroke(theme, body, fill)
	local shadow = GPLayoutKit.Shadow(theme, body, "sm", sink, fill)
	if o.glaze ~= false then
		GPLayoutKit.GlazeSheen(theme, body)
	end

	-- Repaint in place (doc §11.2): a claimed/expired row deepens, it is never
	-- removed and never greyed into illegibility. The stroke and the SHADOW
	-- follow the fill, which is the hue-match rule shown in a state change.
	local function setTone(tone: Color3)
		local deep = GPLayoutKit.Deepen(theme, tone, 1)
		body.BackgroundColor3 = tone
		stroke.Color = deep
		shadow.Instance.Color = deep
	end

	return { root = root, body = body, stroke = stroke, shadow = shadow, SetTone = setTone }
end

-- ========================================================================
-- Reward chips
-- ========================================================================

export type RewardChip = {
	root: Frame,
	icon: GuiObject,
	amount: TextLabel,
}

-- The small pill a reward is quoted in: petal silhouette, blush fill, archive
-- icon then tabular numerals.
--
-- The inset comes from transparent SPACER cells, not a UIPadding: a UIPadding
-- on a frame that AutomaticSize.X's off an AutomaticSize.X label produces
-- unstable widths (the finding UIBadgeComponent records and GiftsScreen's
-- arcade chip already works around).
function GPCelebrationKit.RewardChip(theme: Types.UITheme, parent: Instance, opts: {
	iconKey: string?,
	text: string,
	index: number?,
	tone: Color3?,
	textTone: Color3?,
	zIndex: number?,
}): RewardChip
	local zIndex = opts.zIndex or 5
	local i = opts.index or 0
	local fill = opts.tone or theme.Colors.Background

	local chip = surface("RewardChip", fill, 0)
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.Size = UDim2.fromOffset(0, CHIP_H)
	chip.LayoutOrder = i
	chip.ZIndex = zIndex
	chip.Parent = parent
	GPLayoutKit.Petal(theme, chip, i)
	GPLayoutKit.SoftStroke(theme, chip, fill)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
	}).Parent = chip

	local function spacer(order: number)
		local gap = surface("Gap", fill, 1)
		gap.Size = UDim2.fromOffset(CHIP_GAP, CHIP_H)
		gap.LayoutOrder = order
		gap.ZIndex = zIndex + 1
		gap.Parent = chip
	end

	spacer(0)
	local icon = GPCelebrationKit.Icon(theme, chip, opts.iconKey or "gift", CHIP_ICON)
	icon.LayoutOrder = 1
	icon.ZIndex = zIndex + 1

	local amount = GPLayoutKit.NumberText(theme, theme.TextSizes.Body, opts.textTone or theme.Colors.TextPrimary, "Amount")
	amount.Text = opts.text
	amount.RichText = false
	amount.TextXAlignment = Enum.TextXAlignment.Left
	amount.AutomaticSize = Enum.AutomaticSize.X
	amount.Size = UDim2.fromOffset(0, CHIP_H)
	amount.LayoutOrder = 2
	amount.ZIndex = zIndex + 1
	amount.Parent = chip
	spacer(3)

	return { root = chip, icon = icon, amount = amount }
end

-- ========================================================================
-- Countdown
-- ========================================================================

export type Countdown = {
	root: Frame,
	caption: TextLabel,
	value: TextLabel,
	icon: GuiObject,
	shadow: any,
}

-- The timer pill: a butter plate carrying a quiet caption over HH:MM:SS
-- numerals in the tabular numeric face. Callers drive `.value.Text` from
-- UIChrome.FormatCountdown on their own 1Hz beat — the format is shared with
-- every other pack so a timer never reads differently under this one.
function GPCelebrationKit.Countdown(theme: Types.UITheme, parent: Instance, opts: {
	caption: string?,
	iconKey: string?,
	widthPx: number?,
	heightPx: number?,
	zIndex: number?,
}?, sink: { any }?): Countdown
	local o = opts or {}
	local zIndex = o.zIndex or 5
	local spacing = theme.Spacing
	local fill = theme.Colors.Accent
	local height = o.heightPx or COUNTDOWN_H
	-- Fractional, not fixed px: the same pill is asked for at 44 (a header
	-- ribbon slot) and at 58 (a reward row), and a hardcoded caption baseline
	-- would push the numerals out of the shorter one.
	local textX = spacing.M + 28
	local textW = -(textX + spacing.S)

	local pill = surface("Countdown", fill, 0)
	pill.Size = UDim2.fromOffset(o.widthPx or COUNTDOWN_W, height)
	pill.ZIndex = zIndex
	pill.Parent = parent
	GPLayoutKit.CornerSet(theme, pill, "Leaf")
	GPLayoutKit.SoftStroke(theme, pill, fill)
	local shadow = GPLayoutKit.Shadow(theme, pill, "sm", sink, fill)

	local icon = GPCelebrationKit.Icon(theme, pill, o.iconKey or "clock", 22)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, spacing.M, 0.5, 0)
	icon.ZIndex = zIndex + 1

	-- Ink on butter: butter is a LIGHT fill and the near-white TextOnPrimary
	-- would vanish on it (this is the same call PricePill makes).
	local caption = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Caption")
	caption.Text = o.caption or ""
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Position = UDim2.fromOffset(textX, math.floor(height * 0.12))
	caption.Size = UDim2.new(1, textW, 0, math.floor(height * 0.32))
	caption.ZIndex = zIndex + 1
	caption.Parent = pill

	local value = GPLayoutKit.NumberText(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Value")
	value.Text = ""
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Position = UDim2.fromOffset(textX, math.floor(height * 0.42))
	value.Size = UDim2.new(1, textW, 0, math.floor(height * 0.5))
	value.ZIndex = zIndex + 1
	value.Parent = pill

	return { root = pill, caption = caption, value = value, icon = icon, shadow = shadow }
end

-- ========================================================================
-- Sparkles — THE CLAIMABLE SIGNAL
-- ========================================================================

export type Sparkles = {
	root: Frame,
	SetEnabled: (boolean) -> (),
	Step: (number) -> (),
}

-- A ring of twinkling sparkles OUTSIDE the host's content, for one purpose:
-- saying "this one is ready for you". It starts HIDDEN — SetEnabled(true) is
-- the only way to show it — because a page where everything twinkles has no
-- way left to say which thing is claimable.
--
-- Nothing rotates (see the header): these live inside scrolling reward lists,
-- and a rotated descendant is NOT clipped by an ancestor's ClipsDescendants.
-- The twinkle is transparency + UIScale, driven by the caller's Step(now).
function GPCelebrationKit.Sparkles(theme: Types.UITheme, host: GuiObject, opts: {
	count: number?,
	tint: Color3?,
	inflatePx: number?,
	zIndex: number?,
}?): Sparkles
	local o = opts or {}
	local tokens = dialect(theme, "glaze")
	local count = math.clamp(o.count or tokens.sparkleCount or 6, 1, #SPARKLE_POINTS)
	local inflate = o.inflatePx or 12
	local zIndex = o.zIndex or 8
	local tint = o.tint or theme.Colors.Accent

	local root = surface("Sparkles", tint, 1)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.new(1, inflate * 2, 1, inflate * 2)
	root.ZIndex = zIndex
	root.Visible = false
	root.Parent = host

	local pips: { { image: ImageLabel, scale: UIScale, phase: number } } = {}
	for i = 1, count do
		local point = SPARKLE_POINTS[i]
		local size = SPARKLE_SIZES[i] or 16
		local pip = GPLayoutKit.Slice(theme, "sparkle", tint, "Sparkle" .. i)
		pip.AnchorPoint = Vector2.new(0.5, 0.5)
		pip.Position = UDim2.fromScale(point[1], point[2])
		pip.Size = UDim2.fromOffset(size, size)
		pip.ZIndex = zIndex
		pip.Parent = root
		local scale = Instance.new("UIScale")
		scale.Parent = pip
		-- Golden-ratio phase spread: the ring shimmers rather than blinking in
		-- unison, without storing a random per pip (a rebuild would reshuffle).
		table.insert(pips, { image = pip, scale = scale, phase = (i - 1) * 2.399 })
	end

	local function setEnabled(on: boolean)
		root.Visible = on
	end

	local function step(now: number)
		if not root.Visible then
			return
		end
		for _, pip in pips do
			local wave = 0.5 + 0.5 * math.sin(now * SPARKLE_SPEED + pip.phase)
			pip.image.ImageTransparency = (1 - SPARKLE_AMP) * (1 - wave)
			pip.scale.Scale = 0.78 + 0.34 * wave
		end
	end

	return { root = root, SetEnabled = setEnabled, Step = step }
end

-- ========================================================================
-- The claim stamp
-- ========================================================================

export type Stamp = {
	root: ImageLabel,
	label: TextLabel,
	SetVisible: (boolean) -> (),
	SetText: (string) -> (),
}

-- The sticker-stamp claim treatment: a burst rosette slapped over the thing
-- that has been claimed, carrying the pack's own word for done. It is a
-- ROSETTE and not a tilted rubber stamp because these sit inside scrolling
-- lists (see the no-rotation law in the header) — the stamped read comes from
-- the burst silhouette and the ink shout instead of from an angle.
--
-- Starts hidden; the caller flips it with the claimed state.
function GPCelebrationKit.Stamp(theme: Types.UITheme, host: GuiObject, text: string, opts: {
	sizePx: number?,
	tint: Color3?,
	artKey: string?,
	textSize: number?,
	zIndex: number?,
}?): Stamp
	local o = opts or {}
	local size = o.sizePx or 96
	local zIndex = o.zIndex or 9
	local tint = o.tint or theme.Colors.Accent

	local burst = GPLayoutKit.Slice(theme, o.artKey or "sparkleBurst", tint, "ClaimStamp")
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.5)
	burst.Size = UDim2.fromOffset(size, size)
	burst.ZIndex = zIndex
	burst.Visible = false
	burst.Parent = host

	-- Ink on butter, sentence case. The burst is a LIGHT fill, so this is the
	-- one place a claimed state could have reached for near-white and must not.
	local label = GPLayoutKit.Text(theme, o.textSize or theme.TextSizes.Body, theme.Colors.TextPrimary, "Stamped")
	label.Text = GPCelebrationKit.SoftCase(text)
	label.RichText = false
	label.TextWrapped = true
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1 - STAMP_TEXT_INSET * 2, 1 - STAMP_TEXT_INSET * 2)
	label.ZIndex = zIndex + 1
	label.Parent = burst

	local function setVisible(on: boolean)
		burst.Visible = on
	end
	local function setText(value: string)
		label.Text = GPCelebrationKit.SoftCase(value)
	end

	return { root = burst, label = label, SetVisible = setVisible, SetText = setText }
end

-- ========================================================================
-- Empty state
-- ========================================================================

export type EmptyStateOptions = {
	icon: string?,
	headline: string?,
	hint: string?,
	iconSize: number?,
	golden: boolean?,
	zIndex: number?,
}

-- The quiet nothing-here treatment: a soft archive icon over a display-face
-- headline and a body-face hint. Warm and playful, never patronizing (law 5) —
-- callers supply the copy, this supplies the shape.
function GPCelebrationKit.EmptyState(theme: Types.UITheme, parent: Instance, opts: EmptyStateOptions?): Frame
	local o = opts or {}
	local zIndex = o.zIndex or 6

	local root = surface("EmptyState", theme.Colors.Background, 1)
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = zIndex
	root.Parent = parent

	local art = GPCelebrationKit.Icon(theme, root, o.icon or "gift", o.iconSize or 104, {
		golden = o.golden ~= false,
	})
	art.AnchorPoint = Vector2.new(0.5, 1)
	art.Position = UDim2.new(0.5, 0, 0.5, -18)
	art.ZIndex = zIndex + 1

	local headline = GPLayoutKit.Text(theme, theme.TextSizes.Title, theme.Colors.TextPrimary, "Headline")
	-- Callers reach this through shared code paths that shout ("NO GIFTS RIGHT
	-- NOW"); the same string is re-cased for display rather than forked.
	headline.Text = GPCelebrationKit.SoftCase(o.headline or "Nothing on the shelf yet")
	headline.RichText = false
	headline.AnchorPoint = Vector2.new(0.5, 0)
	headline.Position = UDim2.new(0.5, 0, 0.5, -6)
	headline.Size = UDim2.fromOffset(680, 38)
	headline.ZIndex = zIndex + 1
	headline.Parent = root

	local hint = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Hint")
	hint.Text = GPCelebrationKit.SoftCase(o.hint or "Check back after the next firing.")
	hint.RichText = false
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0.5, 36)
	hint.Size = UDim2.fromOffset(680, 26)
	hint.ZIndex = zIndex + 1
	hint.Parent = root

	return root
end

-- ========================================================================
-- Scrolling
-- ========================================================================

-- A scrolling viewport with the pack's clipping and scrollbar settled once.
-- ClipsDescendants is NOT optional here: unclipped rows spilling past their
-- frame is a known past bug in this codebase, and every celebration list is a
-- scroller. Padding leaves the card shadows room so the clip edge never slices
-- one in half.
function GPCelebrationKit.Scroller(theme: Types.UITheme, parent: Instance, opts: {
	padPx: number?,
	gapPx: number?,
	list: boolean?,
	zIndex: number?,
}?): ScrollingFrame
	local o = opts or {}
	local pad = o.padPx or 6

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "GPScroller"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1)
	scroll.ClipsDescendants = true
	scroll.ZIndex = o.zIndex or 3
	scroll.Parent = parent

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, pad)
	padding.PaddingBottom = UDim.new(0, pad)
	padding.PaddingLeft = UDim.new(0, pad)
	padding.PaddingRight = UDim.new(0, pad)
	padding.Parent = scroll

	if o.list ~= false then
		UIStyler.ListLayout({
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			Padding = UDim.new(0, o.gapPx or theme.Spacing.S),
		}).Parent = scroll
	end
	return scroll
end

return GPCelebrationKit
