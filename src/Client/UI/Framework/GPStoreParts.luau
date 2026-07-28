--!strict
-- GPStoreParts — the shared atoms of the GirlyPop SHOP SLICE (rotating shop,
-- chair skins, passes store, titles). Four screens render the same catalog
-- from different angles, so the parts they share live here rather than four
-- times over: the rarity ramp and its GLOW ladder, the butter-gold value
-- pill, the petal promo badge, the state chip, the featured-only sparkle, and
-- the clipping scroller every board needs.
--
-- COMPOSITION ONLY. Everything here is built from GPLayoutKit and painted
-- from theme tokens; nothing animates except through UIChrome.Animate (the
-- one delegated hover/press exception) — sequenced celebration motion stays
-- in the screen module that owns the ceremony.
--
-- PACK LAWS THIS FILE IS RESPONSIBLE FOR:
--   * A GuiButton is never SOLID: UIStyleEnforcer backstops a solid button
--     with a BLACK 2px stroke, which is law 1 broken on sight. Every button
--     built here is transparent with its fill on a chip CHILD.
--   * Body copy on rose/matcha/butter is TextPrimary. TextOnPrimary appears
--     exactly nowhere in this file.
--   * Petal corners alternate by index across a grid, and one UICorner per
--     instance, always (GPLayoutKit.Petal owns that guarantee).
--   * Shadows are HUE-MATCHED and BUDGETED: every handle lands in a
--     caller-owned sink so the screen's _OnTeardown can release it.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local GPLayoutKit = require(script.Parent.GPLayoutKit)
local GPChairPreview = require(script.Parent.GPChairPreview)
local Store = require(script.Parent.Parent.Config.PotteryStoreConfig)

local GPStoreParts = {}

local BADGE_H = 26
local CHIP_H = 34
local SPARKLE_POINTS = { Vector2.new(0.12, 0.16), Vector2.new(0.84, 0.22), Vector2.new(0.72, 0.78), Vector2.new(0.2, 0.8) }

-- ========================================================================
-- Rarity — one ladder, four screens
-- ========================================================================

-- The pack ships its OWN rarity ramp (DialectTokens.rarity: cream -> sage ->
-- sky -> lavender -> rose-gold). It has five stops and the game has seven
-- tiers, so the top two claim the pack's value colours: butter for Legendary
-- (value IS butter here) and the soft magenta for Exclusive.
function GPStoreParts.RarityColor(theme: Types.UITheme, rarity: string?): Color3
	local ramp = ((theme :: any).DialectTokens and (theme :: any).DialectTokens.rarity) or {}
	local rank = Store.Rank[rarity or ""] or 1
	if rank >= 7 then
		return theme.Arcade.Magenta
	elseif rank >= 6 then
		return ramp[5] or theme.Colors.Primary
	elseif rank >= 5 then
		return theme.Arcade.Gold
	end
	return ramp[rank] or theme.Colors.Surface
end

function GPStoreParts.Rank(rarity: string?): number
	return Store.Rank[rarity or ""] or 1
end

-- THE GLOW RAMP. A Common chair does not bloom — if everything auras, the
-- aura says nothing. Epic is where the well starts glowing, and the intent
-- climbs with the tier so a Mythic reads across the board.
-- Returns the budget handle, or nil when the tier does not glow.
function GPStoreParts.RarityGlow(theme: Types.UITheme, host: GuiObject, rarity: string?, sink: { any }?): any?
	local rank = GPStoreParts.Rank(rarity)
	if rank < 4 then
		return nil
	end
	local handle = GPLayoutKit.Glow(theme, host, GPStoreParts.RarityColor(theme, rarity), sink)
	local shadow = handle.Instance
	-- Bloom harder up the ladder: Epic barely haloes, Exclusive is unmissable.
	local strength = math.clamp((rank - 3) / 4, 0, 1)
	shadow.Transparency = 0.7 - 0.32 * strength
	shadow.Spread = UDim2.fromOffset(2 + math.floor(6 * strength), 2 + math.floor(6 * strength))
	return handle
end

-- The tier word, plus what it actually costs you in luck. A rarity label that
-- prints "Epic" alone is decoration; one that prints the real crate share is
-- information (pack law 6 — density only goes up).
function GPStoreParts.RarityLine(rarity: string?): string
	local name = rarity or "Common"
	local chance = Store.DropChance(name)
	if chance <= 0 then
		return name .. "  ·  never in crates"
	elseif chance < 0.01 then
		return string.format("%s  ·  1 in %d", name, math.floor(1 / chance + 0.5))
	end
	return string.format("%s  ·  %.1f%% from crates", name, chance * 100)
end

-- ========================================================================
-- Text
-- ========================================================================

function GPStoreParts.Title(theme: Types.UITheme, parent: Instance, size: number, text: string, color: Color3?): TextLabel
	local label = GPLayoutKit.Text(theme, size, color or theme.Colors.TextPrimary, "Title")
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = parent
	return label
end

function GPStoreParts.Body(theme: Types.UITheme, parent: Instance, size: number, text: string, color: Color3?): TextLabel
	local label = GPLayoutKit.BodyText(theme, size, color or theme.Colors.TextSecondary, "Body")
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = parent
	return label
end

-- ========================================================================
-- Badges — the promo shouts, de-shouted
-- ========================================================================

export type Badge = { root: Frame, label: TextLabel, shadow: any, Set: (text: string, tone: Color3) -> () }

-- A petal chip that overhangs its card's corner. `tone` is a fill, and the
-- text on it is ALWAYS TextPrimary: every tone in this pack is a light
-- pastel, and the near-white TextOnPrimary measures 2.14:1 on rose.
function GPStoreParts.Badge(theme: Types.UITheme, parent: Instance, text: string, tone: Color3?, index: number?, sink: { any }?): Badge
	local fill = tone or theme.Arcade.Gold
	local root = UIStyler.Frame("Badge")
	root.BackgroundColor3 = fill
	root.BackgroundTransparency = 0
	root.AutomaticSize = Enum.AutomaticSize.X
	root.Size = UDim2.fromOffset(0, BADGE_H)
	root.ZIndex = 9
	root.Parent = parent
	GPLayoutKit.Petal(theme, root, index or 0)
	local stroke = GPLayoutKit.SoftStroke(theme, root, fill)
	local shadow = GPLayoutKit.Shadow(theme, root, "sm", sink, fill)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, theme.Spacing.M)
	padding.PaddingRight = UDim.new(0, theme.Spacing.M)
	padding.Parent = root

	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Label")
	label.Text = text
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, BADGE_H)
	label.ZIndex = 10
	label.Parent = root

	-- Retinting a pooled badge has to move the stroke and the shadow with the
	-- fill, or a rose badge keeps casting the butter shadow it was born with.
	local function set(text: string, tone: Color3)
		label.Text = text
		root.BackgroundColor3 = tone
		local deep = GPLayoutKit.Deepen(theme, tone, 1)
		stroke.Color = deep
		shadow.Instance.Color = deep
	end
	set(text, fill)

	return { root = root, label = label, shadow = shadow, Set = set }
end

-- ========================================================================
-- Sparkle — FEATURED ONLY
-- ========================================================================

-- Four sparkles scattered inside a host, in the pack's own sparkle art. This
-- is the ONE decoration reserved for the featured slot: it means "this one,
-- right now", and it stops meaning that the moment every card wears it.
function GPStoreParts.Sparkle(theme: Types.UITheme, host: GuiObject, tint: Color3?): Frame
	local layer = UIStyler.Frame("SparkleLayer")
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = host.ZIndex + 6
	layer.Parent = host

	local def = (theme :: any).Assets and (theme :: any).Assets.sparkle
	for index, point in SPARKLE_POINTS do
		local star = Instance.new("ImageLabel")
		star.Name = "Sparkle" .. index
		star.BackgroundTransparency = 1
		if def then
			star.Image = def.image
		end
		star.ScaleType = Enum.ScaleType.Fit
		star.ImageColor3 = tint or theme.Arcade.Gold
		star.ImageTransparency = 0.15 + 0.12 * (index % 2)
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.fromScale(point.X, point.Y)
		star.Size = UDim2.fromOffset(if index % 2 == 0 then 18 else 26, if index % 2 == 0 then 18 else 26)
		star.Rotation = index * 24
		star.ZIndex = layer.ZIndex
		star.Parent = layer
	end
	return layer
end

-- ========================================================================
-- Buttons
-- ========================================================================

export type Chip = {
	root: TextButton,
	shape: Frame,
	label: TextLabel,
	icon: ImageLabel,
	shadow: any,
	SetState: (label: string, fill: Color3, interactive: boolean) -> (),
}

-- The state chip every card wears: Equip / Equipped / Owned / Locked, or a
-- price. It RECOLOURS IN PLACE and never disappears — a control that vanishes
-- when it is unavailable is a control the player cannot ask about.
--
-- The button itself stays transparent; the fill lives on the shape child, so
-- the style enforcer never staples a black stroke onto it.
function GPStoreParts.StateChip(theme: Types.UITheme, parent: Instance, opts: {
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	cornerIndex: number?,
	zIndex: number?,
	onClick: (() -> ())?,
	sink: { any }?,
}): Chip
	local zIndex = opts.zIndex or 6
	local root = Instance.new("TextButton")
	root.Name = "StateChip"
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.Size = opts.size or UDim2.new(1, 0, 0, CHIP_H)
	root.Position = opts.position or UDim2.fromScale(0, 0)
	root.AnchorPoint = opts.anchorPoint or Vector2.new(0, 0)
	root.ZIndex = zIndex
	root.Parent = parent

	local fill = theme.Colors.Secondary
	local shape = UIStyler.Frame("Shape")
	shape.BackgroundColor3 = fill
	shape.BackgroundTransparency = 0
	shape.Size = UDim2.fromScale(1, 1)
	shape.ZIndex = zIndex
	shape.Parent = root
	GPLayoutKit.Petal(theme, shape, opts.cornerIndex or 0)
	local stroke = GPLayoutKit.SoftStroke(theme, shape, fill)
	local shadow = GPLayoutKit.Shadow(theme, shape, "sm", opts.sink, fill)

	local icon = Instance.new("ImageLabel")
	icon.Name = "Glyph"
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, theme.Spacing.S, 0.5, 0)
	icon.Size = UDim2.fromOffset(20, 20)
	icon.Visible = false
	icon.ZIndex = zIndex + 1
	icon.Parent = shape

	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Button, theme.Colors.TextPrimary, "Label")
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = zIndex + 1
	label.Parent = shape

	local function setState(text: string, tone: Color3, interactive: boolean)
		label.Text = text
		shape.BackgroundColor3 = tone
		local deep = GPLayoutKit.Deepen(theme, tone, 1)
		stroke.Color = deep
		shadow.Instance.Color = deep
		-- An unavailable chip DIMS its own copy; it does not go grey and it
		-- does not stop answering (every tap still explains itself).
		label.TextColor3 = if interactive then theme.Colors.TextPrimary else theme.Colors.TextSecondary
		root.Active = true
	end

	if opts.onClick then
		root.Activated:Connect(opts.onClick)
	end
	UIChrome.Animate(theme, root, shape)
	setState("", fill, true)

	return { root = root, shape = shape, label = label, icon = icon, shadow = shadow, SetState = setState }
end

-- Butter-gold value pill with a currency glyph. Wraps the kit's PricePill so
-- every price in this slice looks like every other price.
export type Price = { root: Frame, icon: ImageLabel, amount: TextLabel, shadow: any, Set: (currency: string, amount: number) -> () }

function GPStoreParts.PricePill(theme: Types.UITheme, parent: Instance, sink: { any }?): Price
	local pill = GPLayoutKit.PricePill(theme, parent, sink)
	local function set(currency: string, amount: number)
		local id = IconArchive.Id(string.lower(currency))
		pill.icon.Image = id or ""
		pill.icon.Visible = id ~= nil
		pill.amount.Text = Store.Comma(amount)
	end
	return { root = pill.root, icon = pill.icon, amount = pill.amount, shadow = pill.shadow, Set = set }
end

-- ========================================================================
-- Counters
-- ========================================================================

export type Counter = { root: Frame, caption: TextLabel, value: TextLabel, icon: GuiObject, shadow: any }

-- A header counter: icon, quiet caption, loud numerals. This is where every
-- "%d/%d" and every "HH:MM:SS" in this slice lives, so the countdown and the
-- unlock tally are visibly the same kind of fact.
function GPStoreParts.Counter(theme: Types.UITheme, parent: Instance, opts: {
	iconKey: string,
	caption: string,
	widthPx: number?,
	fill: Color3?,
	valueSize: number?,
	layoutOrder: number?,
	sink: { any }?,
}): Counter
	local fill = opts.fill or theme.Colors.SurfaceRaised
	local root = UIStyler.Frame("Counter")
	root.BackgroundColor3 = fill
	root.BackgroundTransparency = 0
	root.Size = UDim2.fromOffset(opts.widthPx or 210, 44)
	root.LayoutOrder = opts.layoutOrder or 1
	root.ZIndex = 7
	root.Parent = parent
	GPLayoutKit.CornerSet(theme, root, "Leaf")
	GPLayoutKit.SoftStroke(theme, root, fill)
	local shadow = GPLayoutKit.Shadow(theme, root, "sm", opts.sink, fill)

	local icon = GPChairPreview.Icon(theme, root, opts.iconKey, 22)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, theme.Spacing.S + 2, 0.5, 0)
	icon.ZIndex = 8

	local caption = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Caption")
	caption.Text = opts.caption
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Position = UDim2.fromOffset(theme.Spacing.M + 22, 4)
	caption.Size = UDim2.new(1, -(theme.Spacing.M + 30), 0, 16)
	caption.ZIndex = 8
	caption.Parent = root

	local value = GPLayoutKit.NumberText(theme, opts.valueSize or theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Value")
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Position = UDim2.fromOffset(theme.Spacing.M + 22, 19)
	value.Size = UDim2.new(1, -(theme.Spacing.M + 30), 0, 22)
	value.ZIndex = 8
	value.Parent = root

	return { root = root, caption = caption, value = value, icon = icon, shadow = shadow }
end

-- ========================================================================
-- Containers
-- ========================================================================

-- A scrolling board. CLIPS — always — with padding on all four sides so the
-- soft shadows the cards cast are not sliced by the viewport edge, and a
-- rose-tinted bar rather than the default.
function GPStoreParts.Scroller(theme: Types.UITheme, parent: Instance, opts: {
	position: UDim2?,
	size: UDim2?,
	padding: number?,
	automatic: boolean?,
	name: string?,
}): ScrollingFrame
	local pad = opts.padding or theme.Spacing.M
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = opts.name or "Board"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = opts.position or UDim2.fromScale(0, 0)
	scroll.Size = opts.size or UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.new()
	if opts.automatic ~= false then
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	end
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = theme.Colors.Primary
	scroll.ScrollBarImageTransparency = 0.25
	-- Nothing in this pack rotates, so an axis-aligned clip is a complete
	-- clip. Scrolled cards must never spill onto the cream plate.
	scroll.ClipsDescendants = true
	scroll.ZIndex = 4
	scroll.Parent = parent

	local padding = Instance.new("UIPadding")
	padding.Name = "ShadowGutter"
	padding.PaddingTop = UDim.new(0, pad)
	padding.PaddingBottom = UDim.new(0, pad)
	padding.PaddingLeft = UDim.new(0, pad)
	padding.PaddingRight = UDim.new(0, pad + 6)
	padding.Parent = scroll
	return scroll
end

-- The empty state. Never a blank field and never an apology — a warm line
-- plus the thing to do next.
function GPStoreParts.Empty(theme: Types.UITheme, parent: Instance, text: string, sink: { any }?): Frame
	local fill = theme.Colors.SurfaceRaised
	local root = UIStyler.Frame("Empty")
	root.BackgroundColor3 = fill
	root.BackgroundTransparency = 0
	root.Size = UDim2.new(1, 0, 0, 132)
	root.ZIndex = 5
	root.Parent = parent
	GPLayoutKit.Petal(theme, root, 0)
	GPLayoutKit.SoftStroke(theme, root, fill)
	GPLayoutKit.Shadow(theme, root, "sm", sink, fill)

	local daisy = Instance.new("ImageLabel")
	daisy.Name = "Daisy"
	daisy.BackgroundTransparency = 1
	local def = (theme :: any).Assets and (theme :: any).Assets.daisy
	if def then
		daisy.Image = def.image
	end
	daisy.ScaleType = Enum.ScaleType.Fit
	daisy.ImageColor3 = theme.Colors.Primary
	daisy.ImageTransparency = 0.35
	daisy.AnchorPoint = Vector2.new(0.5, 0)
	daisy.Position = UDim2.new(0.5, 0, 0, 18)
	daisy.Size = UDim2.fromOffset(44, 44)
	daisy.ZIndex = 6
	daisy.Parent = root

	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Text")
	label.Text = text
	label.TextWrapped = true
	label.Position = UDim2.fromOffset(theme.Spacing.L, 70)
	label.Size = UDim2.new(1, -theme.Spacing.L * 2, 0, 46)
	label.ZIndex = 6
	label.Parent = root
	return root
end

-- Quiet section heading with the pack's squiggle rule under it.
function GPStoreParts.Section(theme: Types.UITheme, parent: Instance, text: string, layoutOrder: number?): Frame
	local root = UIStyler.Frame("Section")
	root.BackgroundTransparency = 1
	root.Size = UDim2.new(1, 0, 0, 46)
	root.LayoutOrder = layoutOrder or 1
	root.ZIndex = 5
	root.Parent = parent

	local label = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Heading")
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(1, 0, 0, 26)
	label.ZIndex = 6
	label.Parent = root

	local rule = GPLayoutKit.Divider(theme, root)
	rule.Position = UDim2.fromOffset(0, 30)
	rule.ZIndex = 5
	return root
end

return GPStoreParts
