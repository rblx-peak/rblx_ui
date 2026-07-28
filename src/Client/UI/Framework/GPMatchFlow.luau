--!strict
-- GPMatchFlow — the small set of GP builders the MATCH FLOW screens need and
-- GPLayoutKit does not (yet) ship: an action chip, a circular avatar disc,
-- pack-safe iconography, a painted plate and the pack's soft casing.
--
-- WHY THIS FILE EXISTS. The six match-flow screens (match summary, duel intro,
-- duel result, lobby, matchmaking, death) all branch on theme.LayoutKit == "GP"
-- and all need the same four things. GPLayoutKit is the shared kit and the
-- right long-term home for them, but it is being written against several
-- screens at once; growing it from a screen branch invites a collision. So
-- these live here — additive, self-contained, composed FROM GPLayoutKit rather
-- than duplicating it — and fold into the kit the moment it takes them.
--
-- THE LAWS THESE BUILDERS EXIST TO KEEP:
--   * NO pure black and NO pure white. UIStyler.Frame is born pure white and
--     IconArchive's GLYPH fallback is born pure white with a BLACK text stroke;
--     Fill() and Icon() are the two places that gets corrected, so no screen
--     has to remember.
--   * SOLID GuiButtons are a trap: UIStyleEnforcer backstops any solid button
--     with a black 2px stroke. Button() therefore keeps the TextButton itself
--     transparent and puts the fill on a chip child — the same dodge
--     GPLayoutKit.Page uses for its close button.
--   * SHADOWS ARE HUE-MATCHED. Every shadow here goes through
--     GPLayoutKit.Shadow with an explicit tint and lands in a caller-owned
--     sink, so the budget counter comes back down on teardown.
--   * NO all-caps. SoftCase() re-cases the arcade captions that shared
--     lifecycle code hands these widgets ("READY UP" -> "Ready up") for
--     DISPLAY only — no caller, config, remote or data is touched.
--   * DIMMED, NEVER DISABLED (§11.1). Button():SetContent{dimmed=true} washes
--     the fill toward cream and softens the ink; the click still lands and the
--     screen still answers it.
--
-- 0.4 BOUNDARY: static composition only. Nothing here animates on its own; the
-- one delegated exception is hover/press juice, which UIChrome.Animate owns so
-- it stays one implementation.

local Players = game:GetService("Players")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local GPLayoutKit = require(script.Parent.GPLayoutKit)

local GPMatchFlow = {}

-- How far a dimmed chip's fill washes toward the cream page.
local DIM_LERP = 0.55

-- ========================================================================
-- Painted primitives
-- ========================================================================

-- A Frame that is ALWAYS painted. UIStyler.Frame is born pure white, which the
-- pack forbids outright, so no GP builder may use it bare.
function GPMatchFlow.Fill(name: string, color: Color3, transparency: number?): Frame
	local frame = UIStyler.Frame(name)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	return frame
end

-- A petal-cornered plate with the pack's deepened-tint hairline and (when an
-- intent is given) a hue-matched shadow. `index` alternates Petal/PetalMirror
-- so a stack or grid of these reads hand-arranged rather than stamped.
function GPMatchFlow.Plate(theme: Types.UITheme, parent: Instance, opts: {
	name: string?,
	fill: Color3,
	index: number?,
	shadow: string?,
	sink: { any }?,
	corner: string?,
}): Frame
	local plate = GPMatchFlow.Fill(opts.name or "GPPlate", opts.fill)
	plate.Parent = parent
	if opts.corner then
		GPLayoutKit.CornerSet(theme, plate, opts.corner)
	else
		GPLayoutKit.Petal(theme, plate, opts.index or 0)
	end
	GPLayoutKit.SoftStroke(theme, plate, opts.fill)
	if opts.shadow then
		GPLayoutKit.Shadow(theme, plate, opts.shadow, opts.sink, opts.fill)
	end
	return plate
end

-- The studio dialect's clay speckle, keyed off the surface it grains.
function GPMatchFlow.Grain(theme: Types.UITheme, host: GuiObject, fill: Color3, zIndex: number?): ImageLabel
	local tokens = ((theme :: any).DialectTokens or {}).studio or {}
	local grain = GPLayoutKit.Tile(
		theme,
		tokens.patternKey or "speckle",
		GPLayoutKit.Deepen(theme, fill, 1),
		tokens.speckleTransparency or 0.94,
		"ClayGrain"
	)
	grain.ZIndex = zIndex or (host.ZIndex + 1)
	grain.Parent = host
	return grain
end

-- ========================================================================
-- Iconography
-- ========================================================================

-- IconArchive.Image, made safe for this pack. Its GLYPH fallback (drawn when
-- an icon has no uploaded art) is born pure white with a black text stroke —
-- both banned here, and a missing upload must not be the one thing on screen
-- that breaks the palette. Full-colour archive ART is left alone unless a
-- STATE tint is explicitly asked for (ready green, muted grey…).
function GPMatchFlow.Icon(theme: Types.UITheme, parent: Instance, key: string, sizePx: number, tint: Color3?, query: any?): GuiObject
	local icon = IconArchive.Image(parent, key, sizePx, query)
	if icon:IsA("TextLabel") then
		icon.TextColor3 = tint or theme.Colors.TextPrimary
		icon.TextStrokeTransparency = 1
	elseif tint and icon:IsA("ImageLabel") then
		icon.ImageColor3 = tint
	end
	return icon
end

-- ========================================================================
-- Copy
-- ========================================================================

-- Initialisms a lowercasing pass would mangle, as {what the pass produces ->
-- what it should say}. "BASE XP" must not become "Base xp"; the pack is
-- soft-spoken, not illiterate.
local ACRONYMS: { [string]: string } = {
	Xp = "XP",
	Exp = "EXP",
	Mvp = "MVP",
	Hp = "HP",
	Ko = "KO",
	Pvp = "PVP",
	Vip = "VIP",
	Kd = "KD",
}

-- Shared lifecycle code hands these widgets arcade-cased captions
-- ("READY UP", "START MATCH") and screens hand them arcade-cased DATA labels
-- ("BASE XP"). This pack never shouts, so the SAME string is re-cased for
-- DISPLAY only — no caller, config, remote or data is touched. RichText markup
-- is passed through untouched rather than half-lowercased.
function GPMatchFlow.SoftCase(text: string): string
	if text == "" or string.find(text, "<", 1, true) then
		return text
	end
	local soft = string.upper(string.sub(text, 1, 1)) .. string.lower(string.sub(text, 2))
	for mangled, acronym in ACRONYMS do
		-- %f[%a]/%f[%A] are the frontier (word-boundary) patterns, so the "Xp"
		-- inside a word like "Xpress" is left alone.
		soft = string.gsub(soft, "%f[%a]" .. mangled .. "%f[%A]", acronym)
	end
	return soft
end

-- ========================================================================
-- The action chip
-- ========================================================================

export type Button = {
	Root: TextButton,
	chip: Frame,
	label: TextLabel,
	SetContent: (any, any) -> (),
	SetEnabled: (any, boolean) -> (),
	Destroy: (any) -> (),
}

-- UIButtonComponent's variant names, re-expressed in this pack's palette, so a
-- screen that flips "Green" -> "Grey" to mean "you are ready, tap to undo"
-- still reads as a STATE CHANGE here. Legacy names (Primary/Secondary/Accent)
-- resolve too, exactly as the component's own recipe map does — an unknown
-- variant keeps the chip's current fill rather than inventing one.
local function variantFill(theme: Types.UITheme, variant: string?): Color3?
	if variant == nil then
		return nil
	end
	local map: { [string]: Color3 } = {
		Primary = theme.Colors.Primary,
		Secondary = theme.Arcade.Magenta,
		Accent = theme.Arcade.Gold,
		Gold = theme.Arcade.Gold,
		Green = theme.Colors.Secondary,
		Red = theme.Colors.Error,
		Blue = theme.Arcade.Blue,
		Magenta = theme.Arcade.Magenta,
		Grey = theme.Arcade.GreyOwned,
		Ghost = theme.Colors.Surface,
	}
	return map[variant]
end

-- The pack's button, with the same Root / SetContent / SetEnabled / Destroy
-- surface UIButtonComponent exposes — so a screen's existing lifecycle code
-- ("dim START until enough players are ready", "flip READY UP to UNREADY")
-- drives it with no changes at all.
--
-- The TextButton stays transparent and the fill rides a chip child; see the
-- enforcer note in the file header.
function GPMatchFlow.Button(theme: Types.UITheme, parent: Instance, opts: {
	text: string,
	fill: Color3,
	sizePx: Vector2,
	position: UDim2?,
	anchorPoint: Vector2?,
	index: number?,
	textSize: number?,
	dimmed: boolean?,
	layoutOrder: number?,
	iconKey: string?,
	onClick: (() -> ())?,
	sink: { any }?,
}): Button
	local button = Instance.new("TextButton")
	button.Name = "GPAction"
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(opts.sizePx.X, opts.sizePx.Y)
	if opts.position then
		button.Position = opts.position
	end
	if opts.anchorPoint then
		button.AnchorPoint = opts.anchorPoint
	end
	if opts.layoutOrder then
		button.LayoutOrder = opts.layoutOrder
	end
	button.Parent = parent

	local base = opts.fill
	local chip = GPMatchFlow.Fill("Chip", base)
	chip.Size = UDim2.fromScale(1, 1)
	chip.Parent = button
	GPLayoutKit.Petal(theme, chip, opts.index or 0)
	local stroke = GPLayoutKit.SoftStroke(theme, chip, base)
	local shadow = GPLayoutKit.Shadow(theme, chip, "sm", opts.sink, base)

	local icon: GuiObject? = nil
	local textInset = 0
	if opts.iconKey then
		local glyph = GPMatchFlow.Icon(theme, chip, opts.iconKey, math.min(opts.sizePx.Y - 22, 30))
		glyph.AnchorPoint = Vector2.new(0, 0.5)
		glyph.Position = UDim2.new(0, theme.Spacing.M, 0.5, 0)
		glyph.ZIndex = 3
		icon = glyph
		textInset = theme.Spacing.M + math.min(opts.sizePx.Y - 22, 30)
	end

	-- Ink on every pastel: TextOnPrimary (near-white) measures 2.14:1 on rose
	-- and is legal only for LARGE display text on a deepened tint.
	local label = GPLayoutKit.Text(theme, opts.textSize or (theme.TextSizes.Button + 5), theme.Colors.TextPrimary, "Label")
	label.Text = GPMatchFlow.SoftCase(opts.text)
	label.Position = UDim2.fromOffset(textInset, 0)
	label.Size = UDim2.new(1, -textInset, 1, 0)
	label.ZIndex = 2
	label.Parent = chip

	local function paint(dimmed: boolean)
		local fill = if dimmed then base:Lerp(theme.Colors.Background, DIM_LERP) else base
		local deep = GPLayoutKit.Deepen(theme, fill, 1)
		chip.BackgroundColor3 = fill
		stroke.Color = deep
		shadow.Instance.Color = deep
		label.TextColor3 = if dimmed then theme.Colors.TextSecondary else theme.Colors.TextPrimary
		if icon then
			if icon:IsA("ImageLabel") then
				icon.ImageTransparency = if dimmed then 0.45 else 0
			elseif icon:IsA("TextLabel") then
				icon.TextTransparency = if dimmed then 0.45 else 0
			end
		end
	end
	paint(opts.dimmed == true)

	if opts.onClick then
		button.Activated:Connect(opts.onClick)
	end
	UIChrome.Animate(theme, button, chip)

	return {
		Root = button,
		chip = chip,
		label = label,
		-- Matches UIButtonComponent: text rides along with every call, because
		-- SetContent re-resolves the caption from the props it is handed.
		SetContent = function(_, props: any)
			if props.text then
				label.Text = GPMatchFlow.SoftCase(props.text)
			end
			base = props.fill or variantFill(theme, props.variant) or base
			paint(props.dimmed == true)
		end,
		SetEnabled = function(_, enabled: boolean)
			paint(not enabled)
		end,
		Destroy = function()
			button:Destroy()
		end,
	}
end

-- ========================================================================
-- Avatars
-- ========================================================================

export type Avatar = {
	root: Frame,
	photo: ImageLabel,
	fallback: GuiObject,
}

-- The circular head. Circles are the one round exception this framework
-- sanctions (doc §4.2) and they survive the pack change unchanged — what
-- changes is the ring, which is a deepened tint of the disc's own fill (or the
-- seat colour a caller passes) rather than a black policy stroke.
function GPMatchFlow.AvatarDisc(theme: Types.UITheme, parent: Instance, sizePx: number, ring: Color3?, ringPx: number?): Avatar
	local wellFill = theme.Colors.Surface
	local holder = GPMatchFlow.Fill("Avatar", wellFill)
	holder.Size = UDim2.fromOffset(sizePx, sizePx)
	holder.ClipsDescendants = true
	holder.Parent = parent
	UIStyler.Corner(theme.Radii.Pill).Parent = holder
	if ring then
		UIStyler.Stroke(ring, ringPx or 3, 0).Parent = holder
	else
		GPLayoutKit.SoftStroke(theme, holder, wellFill)
	end

	local fallback = GPMatchFlow.Icon(theme, holder, "player", math.floor(sizePx * 0.62), theme.Colors.TextSecondary)
	fallback.AnchorPoint = Vector2.new(0.5, 0.5)
	fallback.Position = UDim2.fromScale(0.5, 0.5)
	fallback.ZIndex = 2

	local photo = Instance.new("ImageLabel")
	photo.Name = "Headshot"
	photo.BackgroundTransparency = 1
	photo.ScaleType = Enum.ScaleType.Crop
	photo.Size = UDim2.fromScale(1, 1)
	photo.Visible = false
	photo.ZIndex = 3
	photo.Parent = holder

	return { root = holder, photo = photo, fallback = fallback }
end

-- Fire-and-forget headshot fetch for the screens that have no render
-- generation of their own. GetUserThumbnailAsync YIELDS and can THROW for a
-- brand-new or blocked user, so it runs on its own thread inside a pcall and
-- only lands if the disc is still parented. Screens that DO keep a generation
-- counter (the duel pair) drive their own loader against the same two fields.
function GPMatchFlow.LoadHeadshot(avatar: Avatar, userId: number?)
	if not userId or userId <= 0 then
		return
	end
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if not ok or typeof(content) ~= "string" or content == "" then
			return
		end
		if not avatar.root.Parent then
			return
		end
		avatar.photo.Image = content
		avatar.photo.Visible = true
		avatar.fallback.Visible = false
	end)
end

return GPMatchFlow
