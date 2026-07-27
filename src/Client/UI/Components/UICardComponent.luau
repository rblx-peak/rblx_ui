--!strict
-- Spec-driven shop entry renderer. ONE renderer builds every card; the active
-- pack's EntrySpec decides the arrangement (image-focal, list row, split,
-- text-heavy, banner). Consistency is structural: the individual elements
-- (image well, name, description, price, tag pills, buy button) are built by
-- shared _Make* helpers and themed in one _Style, so every entry in a pack is
-- identical in construction and a theme always paints them the same. Only
-- placement changes between packs — never the elements themselves.
--
-- Restyled to the Pottery Clash ARCADE card (UI_DESIGN_DOCUMENT.md §3.2/§8):
--   * surface = slate row colour at 8% transparency, hard 90° corners, 3px
--     black stroke, glass sheen (all via UIChrome — policy, not per-call style)
--   * accent rotation red→yellow→blue→purple by layoutOrder: tints the item
--     NAME and a 2px accent ring around the image well (doc §3.2)
--   * image well = near-black box with a white sunburst spinning 45°/s behind
--     the art at 0.7 transparency (doc §10; visibility-gated, disconnected in
--     Destroy)
--   * buy button = UIButtonComponent price-button mode: currency icon left of
--     the amount, fill colour = currency colour (Cash green / Bux blue /
--     Robux magenta), OWNED flips grey in place (doc §3.3/§8/§11.2)
--
-- Props:
--   item         : Shared.Types.ShopItem (required)
--   spec         : EntryLayoutConfig.EntrySpec (defaults to StandardCard)
--   currencyIcon : emoji fallback glyph for plain price text rows
--   affordable, owned : booleans
--   onBuy        : (item) -> ()
--   quantity     : number? (inventory views)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedTypes = require(ReplicatedStorage.Shared.Types)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local UIAssets = require(script.Parent.Parent.Config.UIAssets)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local IconVisibility = require(script.Parent.Parent.Icons.IconVisibility)
local IconVisibility = require(script.Parent.Parent.Icons.IconVisibility)
local EntryLayoutConfig = require(script.Parent.Parent.Config.EntryLayoutConfig)
local CardSpacing = require(script.Parent.Parent.Config.CardSpacingConfig)
local TextScaleConfig = require(script.Parent.Parent.Config.TextScaleConfig)
-- SAFE: GLLayoutKit requires only Types/UIStyler/UIChrome (verified), none of
-- which require a component, so this closes no cycle. The kit is CONSULTED as
-- the active pack's policy — the same branch UIChrome.ModalCard already makes.
local GLLayoutKit = require(script.Parent.Parent.Framework.GLLayoutKit)
local UIComponentBase = require(script.Parent.UIComponentBase)
local UIButtonComponent = require(script.Parent.UIButtonComponent)
local UIBadgeComponent = require(script.Parent.UIBadgeComponent)

local UICardComponent = setmetatable({}, { __index = UIComponentBase })
UICardComponent.__index = UICardComponent

local WHITE = Color3.new(1, 1, 1)

function UICardComponent.new()
	local self = UIComponentBase.new("UICard")
	self._badges = {}
	-- Every GL sticker-shadow BUDGET HANDLE this card takes out, released in
	-- Destroy (law 9). Stays empty on every non-GL pack.
	self._glShadows = {}
	return setmetatable(self, UICardComponent)
end

-- Deterministic pastel from the item id — a stable, distinct placeholder swatch
-- per item until real icon art (item.iconId) replaces it.
local function monogramColor(id: string): Color3
	local hash = 0
	for i = 1, #id do
		hash = (hash * 31 + string.byte(id, i)) % 360
	end
	return Color3.fromHSV(hash / 360, 0.5, 0.85)
end

function UICardComponent:_Build(props: Types.UIComponentProps)
	local item = props.item :: SharedTypes.ShopItem
	local spec = (props.spec :: EntryLayoutConfig.EntrySpec?) or EntryLayoutConfig.Get("StandardCard")
	self._spec = spec
	self._item = item

	local root = self.Root
	root.BackgroundTransparency = 1

	-- Accent rotation (doc §3.2): shop card accents cycle red → yellow → blue →
	-- purple by grid position. Resolved against theme.Arcade.ShopAccents in
	-- _Style; only the 1..4 index is fixed at build time.
	self._accentIndex = ((props.layoutOrder or 1) - 1) % 4 + 1

	-- "OutsideBelow"/"Straddle" buy styles put the button OUTSIDE the card's
	-- clipped surface — floating fully or partly below its rounded bottom edge.
	-- For those, shrink the surface to leave room at the bottom of Root and
	-- top-anchor it there; the real button is built as a Root-level sibling
	-- AFTER the arrangement runs (see the bottom of this function), so it is
	-- never clipped by the surface's ClipsDescendants.
	local externalBuy = spec.arrangement == "CardTop"
		and (spec.buyStyle == "OutsideBelow" or spec.buyStyle == "Straddle")
	-- OutsideBelow reserves a full button + gap; Straddle only reserves HALF a
	-- button's height (the other half overlaps the surface on top of it). Both
	-- are SCALE fractions of Root's own height (Root = the full card cell) —
	-- CardSpacing.ExternalBuy.* values are col-relative fractions (see
	-- CardSpacingConfig's module doc), so they're converted to card-relative
	-- here by multiplying by colFactor (col's own fraction of the card).
	local colFactorForExternal = 1 - CardSpacing.SurfacePadding * 2
	local externalHeightOfCard = CardSpacing.ExternalBuy.Height * colFactorForExternal
	local externalGapOfCard = CardSpacing.ExternalBuy.BelowGap * colFactorForExternal
	local straddleGapOfCard = CardSpacing.ExternalBuy.StraddleBelowGap * colFactorForExternal
	-- Straddle reserves half a button's height (the other half overlaps the
	-- surface on top of it) PLUS a small StraddleBelowGap, so the button's
	-- own bottom edge sits a little above Root's true bottom edge instead of
	-- flush against it — otherwise it visually crowds the next row's card
	-- directly underneath (confirmed, real complaint).
	local externalReserve = externalBuy
		and (spec.buyStyle == "Straddle" and (externalHeightOfCard / 2 + straddleGapOfCard)
			or (externalHeightOfCard + externalGapOfCard))
		or 0
	self._externalReserve = externalReserve

	-- Surface = fixed footprint's visual layer; hover/press scale this, not the
	-- Root, so cards never spill into neighbours or reflow the grid/list.
	local surface = UIStyler.Frame("Surface")
	surface.BackgroundTransparency = 0
	if externalBuy then
		surface.Size = UDim2.new(1, 0, 1 - externalReserve, 0)
		surface.AnchorPoint = Vector2.new(0.5, 0)
		surface.Position = UDim2.new(0.5, 0, 0, 0)
	else
		surface.Size = UDim2.fromScale(1, 1)
		surface.AnchorPoint = Vector2.new(0.5, 0.5)
		surface.Position = UDim2.fromScale(0.5, 0.5)
	end
	surface.ClipsDescendants = true
	surface.ZIndex = 2
	surface.Parent = root
	self._surface = surface
	self:_UseScaleTarget(surface)

	-- Whole-cell hit target (doc §11.6): the ENTIRE cell is one invisible
	-- button — art/name/price are non-interactive children, so there are no
	-- dead zones inside a card. It sits at ZIndex 1 BELOW Surface: a plain
	-- Frame never blocks input, so this still receives every tap that the
	-- buy button (whose own Hit renders above, inside the Surface subtree)
	-- doesn't claim first. A cell tap routes to the same purchase prompt as
	-- the buy button; the screen gates affordability and answers with a
	-- toast (doc §11.1). No hover juice here — the buy button already pops,
	-- and doubling the spring on one cell reads as jitter.
	local cellHit = Instance.new("TextButton")
	cellHit.Name = "CellHit"
	cellHit.BackgroundTransparency = 1
	cellHit.Text = ""
	cellHit.Size = UDim2.fromScale(1, 1)
	cellHit.AutoButtonColor = false
	cellHit.Selectable = false -- gamepad focus goes to the buy button itself
	cellHit.ZIndex = 1
	cellHit.Parent = root
	self:_Connect(cellHit.MouseButton1Down, function()
		self:PlayAnimation("Press")
	end)
	self:_Connect(cellHit.MouseButton1Up, function()
		-- "HoverOff", not "Release": Release settles at the HOVER scale, but
		-- the cell has no hover state, so it must come back to rest (1.0).
		self:PlayAnimation("HoverOff")
	end)
	self:_Connect(cellHit.Activated, function()
		self:PlayAnimation("Pulse")
		local onBuy = self.Props.onBuy
		if onBuy and spec.buyStyle ~= "Quantity" then
			onBuy(self._item)
		end
	end)

	-- CardTop's own width:height shape — the same trick as the reference
	-- MainGui's item cards (a UIAspectRatioConstraint on the card itself), so
	-- the whole cell always keeps its authored proportions no matter what Scale
	-- CellSize the grid gives it. Every internal element below is then just a
	-- Scale fraction of THIS card's own resolved height — never a pixel Offset.
	-- Computed PER-SPEC from imageAspect (not one flat constant) — a spec with
	-- a taller/shorter focal image needs a taller/shorter card, or the image
	-- overflows the card and spills into the next grid row (a real, confirmed
	-- bug on TallCard's 0.8 imageAspect before this fix).
	if spec.arrangement == "CardTop" then
		-- AspectRatioForSpec computes the card's shape from ONLY the rows
		-- THIS spec's text column actually renders (see its own comment) —
		-- specs that skip Tags/Price rows, use Pill buyStyle, or use an
		-- external buy button all need their own shorter/differently-shaped
		-- card, not the one-size-fits-all full-layout ratio.
		local ratio = CardSpacing.CardTop.AspectRatioForSpec(spec)
		local cardAspect = UIStyler.AspectRatio(ratio, Enum.DominantAxis.Width)
		cardAspect.Parent = root
	elseif spec.arrangement == "Overlay" then
		-- Overlay's card IS the image (no text block below it), so the card's
		-- own shape is simply the image's own declared aspect ratio.
		local imgAspect = spec.imageAspect and spec.imageAspect > 0 and spec.imageAspect or 1
		local cardAspect = UIStyler.AspectRatio(imgAspect, Enum.DominantAxis.Width)
		cardAspect.Parent = root
	end

	-- HARD ARCADE chrome (doc §4.1), all through UIChrome so policy is central:
	-- zero rounded corners; the 3px black stroke is created in _Style (the
	-- stroke helper is theme-driven); the glass sheen sits on every filled
	-- surface (doc §4.1.4).
	UIChrome.Corner("Arcade").Parent = surface
	-- Held only so the GL branch of _Style can switch the sheen off (cel
	-- shading has none); inert under every other pack.
	self._glass = UIChrome.GlassGradient()
	self._glass.Parent = surface

	-- Studs texture over the card fill (theme-gated; configured/hidden in _Style
	-- — the Pottery base has no Texture token, so this stays hidden by default).
	-- Its ZIndex (1, set by UIStyler.Texture) keeps it above the fill but below
	-- the arrangement content, which is parented afterward at the default ZIndex.
	self._texture = UIStyler.Texture("", 48, Color3.new(1, 1, 1), 1)
	self._texture.Parent = surface

	-- Dispatch to the arrangement. Each lays out shared elements differently.
	local arrangement = spec.arrangement
	if arrangement == "Row" then
		self:_BuildRow(surface, spec)
	elseif arrangement == "Split" then
		self:_BuildSplit(surface, spec, 0.5)
	elseif arrangement == "Banner" then
		self:_BuildSplit(surface, spec, 0.6)
	elseif arrangement == "TextFirst" then
		self:_BuildTextFirst(surface, spec)
	elseif arrangement == "Overlay" then
		self:_BuildOverlay(surface, spec)
	else
		self:_BuildCardTop(surface, spec)
	end

	if externalBuy then
		self:_BuildExternalBuy(root, spec)
	end
end

-- Builds the real buy button as a Root-level SIBLING of the (clipped) surface,
-- so it is never cut off by ClipsDescendants — used by "OutsideBelow" (fully
-- below the box, not touching it) and "Straddle" (centred ON the box's bottom
-- edge, half overlapping inside, half hanging out below).
function UICardComponent:_BuildExternalBuy(root: Frame, spec: EntryLayoutConfig.EntrySpec)
	local props = self.Props
	local buy = UIButtonComponent.new()
	self._buy = buy
	local straddle = spec.buyStyle == "Straddle"
	-- Default: as wide as the box itself (matches the card, edge to edge) — a
	-- per-spec buttonSize can override this later if a narrower/fixed width is
	-- ever wanted, but the out-of-the-box default spans the full card width.
	-- Height is a Scale fraction of Root (the full card cell), like everything
	-- else — never a pixel Offset. CardSpacing.ExternalBuy.Height is a
	-- col-relative fraction (see CardSpacingConfig's module doc); converted to
	-- card-relative here the same way _Build's externalReserve is.
	local colFactorForExternal = 1 - CardSpacing.SurfacePadding * 2
	local buttonH = CardSpacing.ExternalBuy.Height * colFactorForExternal
	local size = UDim2.new(1, 0, buttonH, 0)
	-- Price-button mode (doc §3.3/§8): currency icon left of the amount, fill
	-- colour decided by the currency, OWNED flips grey in place. Unaffordable
	-- stays currency-coloured but DIMMED in place, still tappable — every tap
	-- answers (doc §11.1); the screen explains via its can't-afford toast.
	buy:Create(root, {
		priceCurrency = self._item.currencyType,
		priceAmount = ShopConfig.FormatPrice(self._item.price),
		owned = props.owned or false,
		enabled = not props.owned,
		dimmed = props.affordable == false,
		size = size,
		anchorPoint = Vector2.new(0.5, straddle and 0.5 or 1),
		-- Straddle: centred exactly on the surface's bottom edge (root height
		-- minus the half-button reserve). OutsideBelow: flush with Root's own
		-- bottom edge, safely inside the full-button-plus-gap reserve.
		position = straddle and UDim2.new(0.5, 0, 1 - self._externalReserve, 0) or UDim2.new(0.5, 0, 1, 0),
		onClick = function()
			if props.onBuy then
				props.onBuy(self._item)
			end
			self:PlayAnimation("Pulse")
		end,
	})
	-- Sits above the surface so the overlapping half of a Straddle button reads
	-- as "on top of" the box, not tucked behind it.
	buy.Root.ZIndex = 6
end

-- ========================================================================
-- Shared element builders — used by every arrangement (this is what keeps
-- entries consistent no matter the pack).
-- ========================================================================

function UICardComponent:_MakeImage(parent: Instance, size: UDim2, fillWidth: boolean?): Frame
	local item = self._item
	-- The image WELL (doc §3.2/§10): a near-black box (painted in _Style), hard
	-- corners, ringed by a 2px stroke in this card's rotation accent, with the
	-- white house sunburst spinning behind the art. Clips its children so the
	-- oversized spinning burst never spills past the well.
	local holder = UIStyler.Frame("Image")
	holder.Size = size
	holder.ClipsDescendants = true
	self._imageHolder = holder
	-- 2px accent ring (bespoke per doc §3.2 — deliberately NOT the family's 3px
	-- black policy stroke; the accent colour lands in _Style).
	self._imageStroke = UIStyler.Stroke(Color3.new(), 2, 0)
	self._imageStroke.Parent = holder

	-- Aspect ratio, applied ONLY where the image has a square-ish footprint we
	-- must protect from stretching — the Row/TextFirst offset thumbnails and the
	-- Split image column. CardTop images deliberately FILL the full card width
	-- (a hero banner) and are sized by height alone, so they never leave the ugly
	-- empty gap beside a shrunken square. `fillWidth` opts a caller out entirely.
	local aspect = (self._spec :: any).imageAspect
	if not fillWidth and aspect and aspect > 0 then
		-- The concrete axis stays authoritative; the free axis is computed to hold
		-- the ratio. Width concrete (scaled or offset) -> Width dominant; otherwise
		-- height is concrete (a fixed-height slot) -> Height dominant.
		local widthConcrete = size.X.Scale ~= 0 or size.X.Offset ~= 0
		local dominant = widthConcrete and Enum.DominantAxis.Width or Enum.DominantAxis.Height
		UIStyler.AspectRatio(aspect, dominant).Parent = holder
	end

	-- The house glow motif (doc §10): a white sunburst @ 0.7 spinning 45°/s
	-- behind the item art. Added BEFORE the art so it renders underneath (same
	-- ZIndex, earlier sibling). The spin is already visibility-gated inside
	-- UIChrome.Spin (doc §5.4); the connection is stored and disconnected in
	-- Destroy so a destroyed card never leaves a RenderStepped ticking.
	local _burst, spin = UIAssets.SunburstBehind(holder, WHITE, 0.7, 45)
	self._sunburstSpin = spin

	-- Art, in order of preference: an archive KEY on the item (the normal case
	-- — content names a semantic role and the archive picks the variant), then
	-- a literal iconId, and only then the monogram.
	local archiveId = (item :: any).iconKey and IconArchive.Id((item :: any).iconKey, {
		golden = (item :: any).iconGolden == true,
	}) or nil
	if archiveId or item.iconId ~= "" then
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.ScaleType = Enum.ScaleType.Fit
		image.Image = archiveId or item.iconId
		image.Parent = holder
		IconVisibility.Register(image)
	else
		-- Monogram fallback: the first letter of the name, tinted with the
		-- item's stable pastel (the well itself is now near-black, so the
		-- per-item identity colour moves onto the glyph), outlined black.
		local mono = UIStyler.TextLabel("Mono")
		mono.Size = UDim2.fromScale(1, 1)
		-- FontFace is ALWAYS assigned on glyph labels (the engine default
		-- LegacyArial lacks coverage and renders nothing) — the style's display
		-- font lands in _Style (the first paint runs synchronously in Create).
		mono.TextColor3 = monogramColor(item.id)
		UIChrome.TextOutline(mono)
		-- TextScaled stays the LAST wrap-related assignment on this label.
		mono.TextScaled = true
		mono.Text = string.upper(string.sub(TextConfig.Resolve(item.nameKey), 1, 1))
		-- Scale padding (a fraction of the label's own resolved size) instead of a
		-- pixel value derived from Size.Y.Offset — that Offset read is always 0 now
		-- that image holders are Scale-sized, so a fixed px fallback would never
		-- actually scale with the tile at different viewport sizes.
		UIStyler.PaddingScale(0.18).Parent = mono
		mono.Parent = holder
		self._mono = mono
	end
	holder.Parent = parent
	return holder
end

-- Names NEVER wrap to a 2nd line — TextScaled shrinks the text to fit the
-- fixed box width/height instead (a size constraint caps how far it can
-- shrink so it never goes illegibly small). `height` is a UDim (Scale
-- fraction of the card OR a pixel Offset, caller's choice during the
-- pure-Scale conversion) for the row the caller reserves; `oneLine` only
-- affects the text-size cap (grid-card rows cap smaller) — wrapping is off
-- either way.
function UICardComponent:_MakeName(parent: Instance, height: UDim, oneLine: boolean?): TextLabel
	local name = UIStyler.TextLabel("Name")
	name.Size = UDim2.new(UDim.new(1, 0), height)
	name.TextXAlignment = self._spec.nameAlign
	name.TextYAlignment = Enum.TextYAlignment.Center
	name.TextTruncate = Enum.TextTruncate.None
	-- NOT setting TextWrapped at all: assigning it explicitly (even to false)
	-- AFTER TextScaled = true silently reverts TextScaled back to false —
	-- confirmed via a live Studio test, an unconditional engine coupling, not
	-- a timing issue (no reordering avoids it; only never touching the
	-- property does). TextScaled forces TextWrapped to true as its own side
	-- effect, but on a box this short (~1 line tall), the engine shrinks text
	-- to fit ONE line rather than wrapping into a 2nd, since wrapping would
	-- need more vertical space than the box has — confirmed empirically at
	-- these exact proportions, never actually wraps in practice.
	name.TextScaled = true
	name.Text = TextConfig.Resolve(self._item.nameKey)
	self._nameConstraint = UIStyler.TextSizeConstraint(oneLine and 16 or 20, 9)
	self._nameConstraint.Parent = name
	name.Parent = parent
	self._name = name
	self._nameOneLine = oneLine or false
	return name
end

function UICardComponent:_MakeDescription(parent: Instance): TextLabel?
	if not self._spec.showDescription then
		return nil
	end
	local desc = UIStyler.TextLabel("Description")
	desc.Size = UDim2.new(1, 0, 1, 0)
	desc.AutomaticSize = Enum.AutomaticSize.None
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	-- TextWrapped is set BEFORE TextScaled (never after — see _MakeName's
	-- comment on why the reverse order silently reverts TextScaled back to
	-- false). Description is the one label that actually needs wrapping (a
	-- multi-line paragraph, unlike the one-line Name/Price/Tags), and
	-- TextScaled+TextWrapped together shrink-to-fit while still wrapping.
	desc.TextWrapped = true
	desc.TextScaled = true
	self._descConstraint = UIStyler.TextSizeConstraint(14, 7)
	self._descConstraint.Parent = desc
	desc.Text = self._item.descriptionKey and TextConfig.Resolve(self._item.descriptionKey) or ""
	desc.Parent = parent
	self._desc = desc
	return desc
end

-- Un-converted arrangements (Row/Split/TextFirst/Overlay) still pass no
-- `height` override and get this legacy pixel row height, matching the
-- pre-conversion look until their own conversion stage.
local LEGACY_PRICE_HEIGHT_PX = 16
local LEGACY_TAGROW_HEIGHT_PX = 15

-- `height` overrides the default Offset-based row height with a caller-chosen
-- UDim (CardTop passes a SCALE fraction of the card's own height; other
-- arrangements — not yet converted — omit it and keep the old pixel default).
function UICardComponent:_MakePrice(parent: Instance, height: UDim?): TextLabel
	local price = UIStyler.TextLabel("Price")
	price.Size = UDim2.new(UDim.new(1, 0), height or UDim.new(0, LEGACY_PRICE_HEIGHT_PX))
	price.TextXAlignment = self._spec.nameAlign
	-- Currency semantics (doc §3.3): icon leads, amount is comma-formatted; the
	-- currency COLOUR lands in _Style via UIChrome.CurrencyColor.
	price.Text = string.format("%s %s", self.Props.currencyIcon or "", ShopConfig.FormatPrice(self._item.price))
	-- A caller-supplied SCALE height (CardTop) means the row shrinks/grows with
	-- the card at any viewport, so the text must shrink/grow with it too —
	-- TextScaled instead of a theme-fixed pixel TextSize, same as _MakeName.
	-- NOT touching TextWrapped (see _MakeName's comment on why: it silently
	-- reverts TextScaled back to false) — this box is short enough that
	-- TextScaled never actually wraps in practice.
	if height then
		price.TextTruncate = Enum.TextTruncate.None
		price.TextScaled = true
		self._priceConstraint = UIStyler.TextSizeConstraint(16, 7)
		self._priceConstraint.Parent = price
	end
	price.Parent = parent
	self._price = price
	self._priceScaled = height ~= nil
	return price
end

-- Always returns a fixed-height row when the spec shows tags — even for an item
-- with no tags — so the slot is reserved and every card in a pack keeps the
-- same vertical rhythm (an item missing tags must not shift name/price/buy).
-- Returns nil only when the pack doesn't use tags at all. `height` overrides
-- the default Offset-based row height (see _MakePrice's note above).
function UICardComponent:_MakeTags(parent: Instance, height: UDim?): Frame?
	if not self._spec.showTags then
		return nil
	end
	local item = self._item
	local tagRow = UIStyler.Frame("Tags")
	tagRow.BackgroundTransparency = 1
	tagRow.Size = UDim2.new(UDim.new(1, 0), height or UDim.new(0, LEGACY_TAGROW_HEIGHT_PX))
	-- (Matches the badge's own height exactly — no slack above/below it.)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = self._spec.nameAlign == Enum.TextXAlignment.Center
			and Enum.HorizontalAlignment.Center
			or Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 4),
	}).Parent = tagRow
	tagRow.Parent = parent
	if item.tags then
		for i, tag in item.tags do
			local badge = UIBadgeComponent.new()
			badge:Create(tagRow, { text = tag, variant = tag, layoutOrder = i })
			table.insert(self._badges, badge)
		end
	end
	return tagRow
end

-- A single row holding the tag badges on the LEFT and the price pinned to the
-- RIGHT (Standard 2.0). The badges live in a clipped flex frame that fills the
-- space left of the price, so no matter how many/long the badges are they get
-- clipped at the price's edge and never overlap it. The price is measured and
-- reserves exactly its own width on the right.
function UICardComponent:_MakeTagPriceRow(parent: Instance): Frame
	local row = UIStyler.Frame("TagPriceRow")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, CardSpacing.Height.TagPriceRow)
	row.Parent = parent

	-- Price pinned to the right; AutomaticSize.X so it's exactly as wide as it
	-- needs, and the badge area fills everything to its left.
	local price = UIStyler.TextLabel("Price")
	price.AnchorPoint = Vector2.new(1, 0.5)
	price.Position = UDim2.fromScale(1, 0.5)
	price.Size = UDim2.fromScale(0, 1)
	price.AutomaticSize = Enum.AutomaticSize.X
	price.TextXAlignment = Enum.TextXAlignment.Right
	price.Text = string.format("%s %s", self.Props.currencyIcon or "", ShopConfig.FormatPrice(self._item.price))
	price.Parent = row
	self._price = price

	-- Badge flex area: everything left of the price, minus a small gap. Clipped so
	-- a long stack of badges is cut off at the price instead of running into it.
	local badgeArea = UIStyler.Frame("Badges")
	badgeArea.BackgroundTransparency = 1
	badgeArea.ClipsDescendants = true
	badgeArea.AnchorPoint = Vector2.new(0, 0.5)
	badgeArea.Position = UDim2.fromScale(0, 0.5)
	-- Width is resolved after the price width is known (deferred a frame); until
	-- then it fills the row and clips, which is already safe.
	badgeArea.Size = UDim2.new(1, 0, 1, 0)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 4),
	}).Parent = badgeArea
	badgeArea.Parent = row

	if self._item.tags then
		for i, tag in self._item.tags do
			local badge = UIBadgeComponent.new()
			badge:Create(badgeArea, { text = tag, variant = tag, layoutOrder = i })
			table.insert(self._badges, badge)
		end
	end

	-- Once sizes resolve, shrink the badge area so it ends a gap before the price
	-- (keeps a clean margin between the last badge and the money).
	task.defer(function()
		if not row.Parent then
			return
		end
		local priceW = price.AbsoluteSize.X
		if priceW > 0 then
			badgeArea.Size = UDim2.new(1, -(priceW + 8), 1, 0)
		end
	end)

	return row
end

-- Un-converted arrangements (Row/Split/TextFirst) still pass useCardScale =
-- false and get these legacy pixel heights, matching the pre-conversion look.
local LEGACY_BUY_HEIGHT_PX = { Compact = 26, IconRight = 26, Pill = 24, Full = 26 }

-- `useCardScale`: true when `parent`'s own height IS (a fraction of) the
-- card's own AbsoluteSize (CardTop's `col`), so CardSpacing.Height.Buy* (now
-- Scale fractions of the card) can be used directly. Un-converted arrangements
-- pass false/omit it and get the legacy pixel heights instead.
function UICardComponent:_MakeBuy(parent: Instance, useCardScale: boolean?): GuiObject
	local props = self.Props
	local spec = self._spec
	-- Quantity: an inventory view has nothing to purchase — show an owned-count
	-- badge in the same slot instead of a buy button.
	if spec.buyStyle == "Quantity" then
		return self:_MakeQuantityBadge(parent)
	end
	local buy = UIButtonComponent.new()
	self._buy = buy
	local size
	local function h(cardScaleFraction: number, legacyKey: string): UDim
		return useCardScale and UDim.new(cardScaleFraction, 0) or UDim.new(0, LEGACY_BUY_HEIGHT_PX[legacyKey])
	end
	if spec.buyStyle == "Compact" then
		-- A pure SCALE fraction of the parent's width, not a flat 92px cap or
		-- a synchronously-read AbsoluteSize pixel snapshot — reading
		-- parent.AbsoluteSize.X here at construction time is unreliable
		-- (Roblox hasn't resolved the parent's own just-assigned Scale size
		-- yet within the same frame, confirmed via measurement: it read ~6px
		-- on a parent that settles to ~173px moments later, producing a
		-- near-invisible button). A Scale value resolves against the real
		-- AbsoluteSize once layout actually settles, with no timing risk, and
		-- also keeps the button from staying squeezed into a narrow slice on
		-- a wide Row list card that has real width to spare (the price above
		-- it already uses the full column width; Buy should too). On a
		-- narrow CardTop grid column this looks the same as before.
		size = UDim2.new(UDim.new(0.92, 0), h(CardSpacing.Height.BuyCompact, "Compact"))
	elseif spec.buyStyle == "IconRight" then
		size = UDim2.new(UDim.new(0, 34), h(CardSpacing.Height.BuyIconRight, "IconRight"))
	elseif spec.buyStyle == "Pill" then
		-- Smaller, rounder, centred — deliberately NOT flush with the image box
		-- above it (the caller adds real spacing before this).
		size = UDim2.new(UDim.new(0, 110), h(CardSpacing.Height.BuyPill, "Pill"))
	else
		size = UDim2.new(UDim.new(1, 0), h(CardSpacing.Height.BuyFull, "Full"))
	end
	-- Price-button mode (doc §3.3/§8): currency icon left of the amount, fill
	-- colour decided by the currency (Cash green / Bux blue / Robux magenta),
	-- OWNED flips grey in place with children hidden. Unaffordable stays
	-- currency-coloured but DIMMED in place, still tappable — every tap
	-- answers (doc §11.1); the screen explains via its can't-afford toast.
	buy:Create(parent, {
		priceCurrency = self._item.currencyType,
		priceAmount = ShopConfig.FormatPrice(self._item.price),
		owned = props.owned or false,
		enabled = not props.owned,
		dimmed = props.affordable == false,
		size = size,
		onClick = function()
			if props.onBuy then
				props.onBuy(self._item)
			end
			self:PlayAnimation("Pulse")
		end,
	})
	if spec.buyStyle == "Pill" then
		-- Pill buttons are always fully round regardless of the theme's
		-- roundness — pills are the one round exception in EVERY style, so the
		-- radius comes from the UIChrome policy (which keeps pills round even
		-- under a HardCorners chrome).
		local corner = buy.Root:FindFirstChild("Surface") and buy.Root.Surface:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0, UIChrome.Radius("Arcade", "Pill"))
		end
	end
	return buy.Root
end

-- Themed "×N owned" chip for inventory-style rows (QuantityRow / buyStyle
-- "Quantity"). Not a button — nothing to purchase here, just what's owned.
-- Quantity is deterministic per item (stable across re-renders) unless the game
-- supplies a real one via props.quantity.
-- `useCardScale`: true when `parent`'s own height IS (a fraction of) the
-- card's own AbsoluteSize (Overlay's surface), so the chip height is a Scale
-- fraction instead of a fixed pixel Offset (matches _MakeBuy's pattern).
function UICardComponent:_MakeQuantityBadge(parent: Instance, useCardScale: boolean?): Frame
	local chip = UIStyler.Frame("Quantity")
	chip.Size = useCardScale and UDim2.fromScale(0, 0.125) or UDim2.fromOffset(0, 30)
	chip.AutomaticSize = Enum.AutomaticSize.X
	-- Arcade micro-badge chrome: hard corners (UIChrome policy); the thin chip
	-- stroke attaches in _Style (a styled chrome needs the live theme), where
	-- the slate fill + ice-blue count land too.
	UIChrome.Corner("Arcade").Parent = chip
	if useCardScale then
		UIStyler.PaddingScale(0.2).Parent = chip
	else
		UIStyler.PaddingXY(12, 4).Parent = chip
	end
	local label = UIStyler.TextLabel("Count")
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.TextScaled = true
	self._qtyLabelConstraint = UIStyler.TextSizeConstraint(16, 6)
	self._qtyLabelConstraint.Parent = label
	label.Parent = chip
	self._qtyLabel = label
	chip.Parent = parent

	local quantity = (self.Props :: any).quantity
	if not quantity then
		-- Stable per-item fallback so the same item always shows the same count.
		local hash = 0
		for i = 1, #self._item.id do
			hash = (hash * 31 + string.byte(self._item.id, i)) % 12
		end
		quantity = hash + 1
	end
	-- Leading/trailing space around the "×N" text itself, in addition to the
	-- chip's own UIPadding, for a bit more breathing room around the glyph.
	label.Text = " ×" .. tostring(quantity) .. " "
	return chip
end

-- Themed pill chip showing the price, for overlaying DIRECTLY ON the image
-- (overlayBadgeAndPrice spec flag) — a solid themed background so the price
-- stays legible over any art, unlike the plain _MakePrice text used when price
-- sits in the (already-dark) text column below the image. `useCardScale`
-- (matching _MakeQuantityBadge/_MakeBuy's pattern): true when parent's height
-- IS a fraction of the card's own AbsoluteSize, so the chip height is a Scale
-- fraction instead of a fixed pixel Offset.
function UICardComponent:_MakePriceChip(parent: Instance, useCardScale: boolean?): Frame
	local chip = UIStyler.Frame("PriceChip")
	chip.Size = useCardScale and UDim2.fromScale(0, 0.1) or UDim2.fromOffset(0, 24)
	chip.AutomaticSize = Enum.AutomaticSize.X
	-- Arcade chrome: hard corners; the thin stroke attaches in _Style (a styled
	-- chrome needs the live theme), where the fill is painted with the item's
	-- CURRENCY colour (doc §3.3 — colour is meaning), so the chip reads like a
	-- miniature price button riding on the art.
	UIChrome.Corner("Arcade").Parent = chip
	-- NO UIPadding here: chip is AutomaticSize.X off the label, and the label
	-- is ALSO AutomaticSize.X — a UIPadding fighting that combination produced
	-- unstable/incorrect sizing (same fix already applied to UIBadgeComponent).
	local label = UIStyler.TextLabel("Value")
	label.AutomaticSize = Enum.AutomaticSize.X
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.fromScale(0, 0.5)
	label.Size = UDim2.fromScale(0, 0.8)
	-- Leading/trailing space: no UIPadding on this chip (see the comment
	-- above), so the padded string itself keeps text off the chip's edge.
	label.Text = string.format(" %s %s ", self.Props.currencyIcon or "", ShopConfig.FormatPrice(self._item.price))
	-- TextScaled must be the LAST text-wrap-related assignment — setting
	-- TextWrapped afterward (even to false) silently reverts TextScaled back
	-- to false (confirmed via a live Studio test, same as every other label
	-- in this file).
	label.TextScaled = true
	self._priceChipLabelConstraint = UIStyler.TextSizeConstraint(16, 6)
	self._priceChipLabelConstraint.Parent = label
	label.Parent = chip
	self._priceChipLabel = label
	chip.Parent = parent
	return chip
end

-- Small helper: a transparent vertical stack container.
local function stack(name: string, padding: number, align: Enum.HorizontalAlignment?): Frame
	local frame = UIStyler.Frame(name)
	frame.BackgroundTransparency = 1
	UIStyler.ListLayout({
		Padding = UDim.new(0, padding),
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
	}).Parent = frame
	return frame
end

-- ========================================================================
-- Arrangements
-- ========================================================================

-- Image on top, text stacked below. Standard grid card / image-focal.
--
-- Gaps between elements are EXPLICIT spacer frames sized from CardSpacingConfig
-- (the column's own UIListLayout gap is 0) instead of one uniform padding value
-- — that's what lets "make X touch Y" be a single-line config edit instead of a
-- renderer-code hunt, and lets each pair (image->tags, tags->name, name->price,
-- price->buy) have its own independently-tunable gap.
function UICardComponent:_BuildCardTop(surface: Frame, spec: EntryLayoutConfig.EntrySpec)
	-- Uniform inset on all 4 sides — the slight bottom margin matches
	-- top/left/right and was never the source of the "extra space" bug
	-- (that was Gap.BuyToBottom double-accounting for tagStraddle/other
	-- branches, fixed separately). Keep this small and even everywhere.
	UIStyler.PaddingScale(CardSpacing.SurfacePadding).Parent = surface
	local col = stack("Content", 0, spec.nameAlign == Enum.TextXAlignment.Center and Enum.HorizontalAlignment.Center or Enum.HorizontalAlignment.Left)
	col.Size = UDim2.fromScale(1, 1)
	col.Parent = surface

	local order = 0
	local function next_(o: GuiObject)
		order += 1
		o.LayoutOrder = order
	end
	-- A zero-height frame just for spacing — its Size.Y (a SCALE fraction of the
	-- card's own height) IS the gap.
	local function gap(scale: number)
		if scale <= 0 then
			return
		end
		local spacer = UIStyler.Frame("Gap")
		spacer.BackgroundTransparency = 1
		spacer.Size = UDim2.new(1, 0, scale, 0)
		spacer.Parent = col
		next_(spacer)
	end

	-- Image fills the card's content width edge-to-edge (imageFillWidth) or is a
	-- centred square/rect — either way its HEIGHT is a Scale fraction of the
	-- card's own height, computed from the image's aspect against the known
	-- content width fraction (1 - 2*SurfacePadding), so the whole row scales
	-- perfectly with the card's own UIAspectRatioConstraint-driven size, with no
	-- pixel measurement needed at all.
	local aspect = (spec :: any).imageAspect
	if not aspect or aspect <= 0 then
		aspect = 1 -- square default
	end
	local contentW = 1 - CardSpacing.SurfacePadding * 2 -- fraction of card WIDTH
	-- MUST match whatever AspectRatioForSpec computed for Root's own
	-- UIAspectRatioConstraint in _Build, or this math computes the image
	-- height for a DIFFERENT card shape than the one actually rendering.
	local cardAspect = CardSpacing.CardTop.AspectRatioForSpec(spec) -- card WIDTH / card HEIGHT
	-- imgH as a fraction of the CARD's own height first (imgW(px) = contentW *
	-- cardWidth(px); cardHeight(px) = cardWidth(px) / cardAspect; imgH_frac =
	-- imgW(px)/aspect / cardHeight(px) = contentW * cardAspect / aspect) — then
	-- converted to a fraction of `col` (what `wrap` is actually parented in,
	-- and what Scale resolves against) by dividing by colFactor, the same
	-- correction CardSpacingConfig's OWN fractions already bake in. Getting
	-- this wrong is what caused the confirmed "extra space under the buy
	-- button" bug — col's content undersized itself relative to its real
	-- available space.
	local imgHFracOfCard = (contentW * cardAspect) / aspect
	local colFactor = 1 - CardSpacing.SurfacePadding * 2
	local imgHFrac = imgHFracOfCard / colFactor
	-- The default (non-external) buy styles append a BuyToBottom spacer after
	-- the button (see the tail of this function) — that spacer's height must
	-- come FROM somewhere so col's content still sums to exactly 1.0 (it
	-- doesn't add a new fraction on top, which previously overflowed col's own
	-- bounds and got silently clipped by surface.ClipsDescendants). The image
	-- row is what shrinks to make room, since it's the biggest/most forgiving
	-- element to trim slightly.
	local hasBuyToBottom = spec.buyStyle ~= "OutsideBelow" and spec.buyStyle ~= "Straddle"
	if hasBuyToBottom then
		imgHFrac -= CardSpacing.Gap.BuyToBottom
	end
	local wrap = UIStyler.Frame("ImageWrap")
	wrap.BackgroundTransparency = 1
	wrap.Size = UDim2.new(1, 0, imgHFrac, 0)
	wrap.Parent = col
	next_(wrap)
	local img = self:_MakeImage(wrap, UDim2.fromScale(1, 1), true)
	img.AnchorPoint = Vector2.new(0.5, 0)
	img.Position = UDim2.fromScale(0.5, 0)
	-- These two overlays are sized relative to `wrap` (the image wrap), whose OWN
	-- height is imgHFrac (a fraction of the CARD, not of itself) — Scale always
	-- resolves against the immediate parent, so a card-relative fraction like
	-- CardSpacing.Height.TagRow must be re-expressed as a fraction of `wrap`
	-- itself: divide by imgHFrac to convert "fraction of card" to "fraction of
	-- wrap".
	local tagRowFracOfWrap = CardSpacing.Height.TagRow / imgHFrac
	-- Banner look: the tag badges straddle the image's TOP edge — a later
	-- sibling of the image inside the same wrap, so it renders on top of it
	-- without needing any ZIndex bump — half overlapping onto the art, half
	-- hanging above it, instead of taking a row in the text column below.
	if spec.tagStraddle and spec.showTags then
		local straddleTags = self:_MakeTags(wrap)
		if straddleTags then
			straddleTags.AnchorPoint = Vector2.new(0, 0)
			straddleTags.Position = UDim2.new(0.04, 0, CardSpacing.BannerStraddleOffset / imgHFrac, 0)
			straddleTags.Size = UDim2.new(0.92, 0, tagRowFracOfWrap, 0)
		end
	end
	-- Standard 2.0: badges overlay the image's top-left corner, price overlays
	-- its bottom-right corner (both fully inside the art) — both later siblings
	-- of the image inside the same wrap, so they render on top with no ZIndex
	-- bump needed. Text column below only gets Name + Buy.
	if spec.overlayBadgeAndPrice then
		if spec.showTags then
			local overlayTags = self:_MakeTags(wrap)
			if overlayTags then
				overlayTags.AnchorPoint = Vector2.new(0, 0)
				overlayTags.Position = UDim2.new(0.04, 0, 0.04, 0)
				overlayTags.Size = UDim2.new(0.92, 0, tagRowFracOfWrap, 0)
			end
		end
		-- _MakePriceChip's own useCardScale sizing assumes its parent's height
		-- IS the card's height — but it's parented in `wrap` here (the image
		-- wrap, whose own height is imgHFrac of the card), so its Size gets
		-- overridden right after with the same wrap-relative conversion
		-- tagRowFracOfWrap already uses (divide the card-relative fraction by
		-- imgHFrac to convert "fraction of card" into "fraction of wrap").
		local priceChip = self:_MakePriceChip(wrap, true)
		priceChip.Size = UDim2.new(priceChip.Size.X.Scale, priceChip.Size.X.Offset, 0.1 / imgHFrac, 0)
		priceChip.AnchorPoint = Vector2.new(1, 1)
		priceChip.Position = UDim2.new(0.96, 0, 0.96, 0)
	end
	-- Standard 2.0: price rides on the RIGHT of the tag row (name above it, buy
	-- below). Otherwise: tags row, then name, then price on its own row.
	if spec.priceWithTags then
		gap(CardSpacing.Gap.ImageToName)
		local name = self:_MakeName(col, UDim.new(CardSpacing.Height.Name, 0), true)
		next_(name)
		gap(CardSpacing.Gap.NameToPrice)
		next_(self:_MakeTagPriceRow(col))
	elseif spec.overlayBadgeAndPrice then
		-- Badges + price already placed on the image — text column is just
		-- Name + Buy, tight against each other with only their normal small
		-- gaps. The card ITSELF uses AspectRatioForSpec (see _Build) — its
		-- own shorter shape derived from ONLY the rows this layout actually
		-- has — so col naturally sums to exactly 1.0 here with no padding
		-- needed. (Padding this with blank Tags/Price-sized spacers instead
		-- of shortening the card was tried and reverted — it just moved the
		-- dead space into the middle of the layout instead of removing it.)
		gap(CardSpacing.Gap.ImageToName)
		local name = self:_MakeName(col, UDim.new(CardSpacing.Height.Name, 0), true)
		next_(name)
	else
		-- tagStraddle (badges on the image) and showTags=false both skip the
		-- Tags row here — either way the card ITSELF already uses
		-- AspectRatioForSpec's shorter shape for a spec with no Tags row (see
		-- _Build), so col sums to exactly 1.0 with just the normal small gap,
		-- no blank spacer needed (same fix as overlayBadgeAndPrice above —
		-- padding this instead of shortening the card was tried and reverted).
		local tags = not spec.tagStraddle and self:_MakeTags(col, UDim.new(CardSpacing.Height.TagRow, 0)) or nil
		if tags then
			-- The missing gap: this was never inserted before, so the badge
			-- always sat flush against the image regardless of the config value.
			gap(CardSpacing.Gap.ImageToTags)
			next_(tags)
			gap(CardSpacing.Gap.TagsToName)
		else
			gap(CardSpacing.Gap.ImageToName)
		end
		local name = self:_MakeName(col, UDim.new(CardSpacing.Height.Name, 0), true)
		next_(name)
		gap(CardSpacing.Gap.NameToPrice)
		local price = self:_MakePrice(col, UDim.new(CardSpacing.Height.Price, 0))
		next_(price)
	end
	-- "OutsideBelow"/"Straddle": the real button is built externally (see
	-- _Build/_BuildExternalBuy) as a sibling of the surface, so it's never
	-- clipped — just close out the column with a little bottom padding here so
	-- price doesn't touch the surface's clipped edge.
	if spec.buyStyle == "OutsideBelow" or spec.buyStyle == "Straddle" then
		local pad = UIStyler.Frame("BottomPad")
		pad.BackgroundTransparency = 1
		-- Straddle needs real reserved space here (the button's overlapping
		-- half would otherwise cover the price row right above it);
		-- OutsideBelow's button never touches the surface, so it stays flush.
		local padScale = spec.buyStyle == "Straddle" and CardSpacing.ExternalBuy.StraddleBottomPad
			or CardSpacing.ExternalBuy.BottomPad
		pad.Size = UDim2.new(1, 0, padScale, 0)
		pad.LayoutOrder = 900
		pad.Parent = col
		return
	end
	-- Pill buttons get real breathing room so they read as a separate element
	-- below the image box, not flush against the price row like a normal buy.
	gap(spec.buyStyle == "Pill" and CardSpacing.Gap.BuyToPill or CardSpacing.Gap.PriceToBuy)
	local buy = self:_MakeBuy(col, true)
	buy.LayoutOrder = 999
	-- (Pill buttons are meant for a CENTRED spec — nameAlign = Center — so the
	-- column's own HorizontalAlignment already centres a narrower button like this.)
	-- A visible bottom margin so the button doesn't sit flush against the
	-- surface's own clipped bottom edge.
	local bottomPad = UIStyler.Frame("BottomPad")
	bottomPad.BackgroundTransparency = 1
	bottomPad.Size = UDim2.new(1, 0, CardSpacing.Gap.BuyToBottom, 0)
	bottomPad.LayoutOrder = 1000
	bottomPad.Parent = col
end

-- Full-bleed image with the text OVERLAID on it (name/price/tags/buy). Three
-- readability treatments, picked by spec.overlayBg:
--   "Scrim"       (default) — a dark gradient fading up from the bottom edge,
--                  behind the whole text band.
--   "Flat"        — no gradient/shadow at all: a small rounded, translucent
--                  flat-colour panel sits directly behind JUST the text, so
--                  the rest of the image stays completely clean.
--   "CenterStrip" — no scrim either: a translucent strip crosses the vertical
--                  MIDDLE of the image holding ONLY the name (poster/title-card
--                  look); price+buy get their own small translucent footer.
-- Either way the card IS the image (no text block below) — compact and premium.
function UICardComponent:_BuildOverlay(surface: Frame, spec: EntryLayoutConfig.EntrySpec)
	-- Image fills the entire card.
	local img = self:_MakeImage(surface, UDim2.fromScale(1, 1), true)
	img.ZIndex = 2

	-- Inventory tile: buyStyle "Quantity" means there's nothing to sell, so skip
	-- the whole price/scrim treatment entirely — just the square image with an
	-- owned-count badge overlaid in the bottom-right corner (and tags top-left,
	-- if the spec wants them). "The image AS the square, stuff inside of it."
	if spec.buyStyle == "Quantity" then
		if spec.showTags then
			local tags = self:_MakeTags(surface, UDim.new(0.083, 0))
			if tags then
				tags.AnchorPoint = Vector2.new(0, 0)
				tags.Position = UDim2.fromScale(0.033, 0.033)
				tags.Size = UDim2.new(0.933, 0, 0.083, 0)
				tags.ZIndex = 5
				for _, d in tags:GetDescendants() do
					if d:IsA("GuiObject") then
						d.ZIndex = 5
					end
				end
			end
		end
		local qty = self:_MakeQuantityBadge(surface, true)
		qty.AnchorPoint = Vector2.new(1, 1)
		qty.Position = UDim2.new(0.967, 0, 0.967, 0)
		qty.ZIndex = 5
		return
	end

	local useFlat = spec.overlayBg == "Flat"
	local useCenterStrip = spec.overlayBg == "CenterStrip"

	if useCenterStrip then
		-- No scrim/darkening at all — the image stays fully clean except for one
		-- translucent strip crossing the vertical middle, holding ONLY the name.
		local strip = UIStyler.Frame("NameStrip")
		strip.AnchorPoint = Vector2.new(0, 0.5)
		strip.Position = UDim2.fromScale(0, 0.5)
		strip.Size = UDim2.new(1, 0, 0.142, 0)
		strip.ZIndex = 4
		strip.Parent = surface
		self._nameStrip = strip
		local name = self:_MakeName(strip, UDim.new(1, 0))
		name.AnchorPoint = Vector2.new(0, 0)
		name.Position = UDim2.fromScale(0.033, 0)
		name.Size = UDim2.new(0.933, 0, 1, 0)
		name.ZIndex = 5
	elseif not useFlat then
		-- Bottom scrim: a dark gradient fading from transparent (top) to opaque
		-- (bottom) so overlaid text reads over bright art without hiding the image.
		-- The frame spans the FULL card (not just the bottom fraction) so its
		-- rounded corners align EXACTLY with the card's own corners — sizing it
		-- smaller (with its own separate rounding) was what caused a visible seam/
		-- cutoff where the scrim's own top corners curved against the image at an
		-- arbitrary point partway down. Only the gradient decides where it darkens.
		local scrim = UIStyler.Frame("Scrim")
		scrim.BackgroundColor3 = Color3.new(0, 0, 0)
		scrim.BackgroundTransparency = 0
		scrim.Size = UDim2.fromScale(1, 1)
		scrim.ZIndex = 3
		local scrimGrad = Instance.new("UIGradient")
		scrimGrad.Rotation = 90
		scrimGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.45, 1),
			NumberSequenceKeypoint.new(0.7, 0.45),
			NumberSequenceKeypoint.new(1, 0.1),
		})
		scrimGrad.Parent = scrim
		scrim.Parent = surface
		self._scrim = scrim
		-- Hard arcade corners: the scrim spans the full card, and both are
		-- square (radius 0), so no corner-matching is needed anymore.
	else
		-- Flat: a small rounded panel sized to just the text block (not the whole
		-- card width), a few px larger than the Info frame it sits behind so there's
		-- a clean margin. Coloured + made translucent in _Style.
		local flatBg = UIStyler.Frame("FlatBg")
		flatBg.AnchorPoint = Vector2.new(0, 1)
		flatBg.Position = UDim2.new(0.017, 0, 0.983, 0)
		flatBg.Size = UDim2.new(0.967, 0, 0.233, 0)
		flatBg.ZIndex = 4
		flatBg.Parent = surface
		self._flatBg = flatBg
		UIChrome.Corner("Arcade").Parent = flatBg
	end

	-- Tags top-left over the image.
	if spec.showTags then
		local tags = self:_MakeTags(surface, UDim.new(0.092, 0))
		if tags then
			tags.AnchorPoint = Vector2.new(0, 0)
			tags.Position = UDim2.fromScale(0.042, 0.042)
			tags.Size = UDim2.new(0.917, 0, 0.092, 0)
			tags.ZIndex = 6
			for _, d in tags:GetDescendants() do
				if d:IsA("GuiObject") then
					d.ZIndex = 6
				end
			end
		end
	end

	-- Text column pinned to the bottom over the scrim. Name + price stack (or,
	-- for CenterStrip, just price — the name already lives in the strip above),
	-- and a compact Buy sits to the right so nothing overflows the card's edge.
	-- All Scale fractions of the (now fixed-aspect) card itself.
	local infoBottomInset = 0.042
	local infoH = useCenterStrip and 0.142 or 0.196

	-- CenterStrip already showed the name up in the middle strip, so the bottom
	-- footer here only needs price+buy — and since it has no scrim behind it,
	-- it gets its own small translucent panel (reusing the Flat styling path).
	-- Sized to hug `info` (below) with a small uniform margin — it used to be a
	-- fixed height taller than info's actual content, leaving a dead strip of
	-- translucent panel below the buy button with nothing in it.
	if useCenterStrip then
		local margin = 0.017
		local footerBg = UIStyler.Frame("FooterBg")
		footerBg.AnchorPoint = Vector2.new(0, 1)
		footerBg.Position = UDim2.new(0.017, 0, 1 - (infoBottomInset - margin), 0)
		footerBg.Size = UDim2.new(0.967, 0, infoH + margin * 2, 0)
		footerBg.ZIndex = 4
		footerBg.Parent = surface
		self._flatBg = footerBg
		UIChrome.Corner("Arcade").Parent = footerBg
	end

	local info = UIStyler.Frame("Info")
	info.BackgroundTransparency = 1
	info.AnchorPoint = Vector2.new(0, 1)
	info.Position = UDim2.new(0.042, 0, 1 - infoBottomInset, 0)
	info.Size = UDim2.new(0.917, 0, infoH, 0)
	info.ZIndex = 5
	info.Parent = surface

	-- Every Y-fraction below is card-relative (matching the module's usual
	-- convention), but name/price/buy are parented in `info` (NOT surface), so
	-- Scale resolves against info's OWN AbsoluteSize — dividing by infoH here
	-- converts each "fraction of the card" into "fraction of info," or the
	-- values render far too small (confirmed via measurement: the buy button
	-- rendered at ~2px tall before this fix, a real bug).
	local function ofInfo(cardFrac: number): number
		return infoH > 0 and (cardFrac / infoH) or cardFrac
	end

	if not useCenterStrip then
		-- Title takes the FULL width on its own row, above price+buy — not
		-- squeezed to leave room for the buy button beside it.
		local name = self:_MakeName(info, UDim.new(ofInfo(0.083), 0), true)
		name.Size = UDim2.new(1, 0, ofInfo(0.083), 0)
		name.Position = UDim2.fromScale(0, 0)
		name.ZIndex = 5
	end
	local price = self:_MakePrice(info, useCenterStrip and UDim.new(1, 0) or UDim.new(ofInfo(0.071), 0))
	if useCenterStrip then
		price.Size = UDim2.new(0.708, 0, 1, 0)
		price.Position = UDim2.fromScale(0, 0)
	else
		-- Second row, left side: price on the left, buy on the right (below).
		price.Size = UDim2.new(0.55, 0, ofInfo(0.071), 0)
		price.Position = UDim2.fromScale(0, ofInfo(0.108))
		price.TextYAlignment = Enum.TextYAlignment.Center
	end
	price.ZIndex = 5
	-- Buy button: thinner (was 28px tall) and pinned to the BOTTOM-RIGHT corner
	-- of the info block — same row as price, not vertically centred across both
	-- text rows anymore, now that the name has its own row above.
	local buy = self:_MakeBuy(info)
	if useCenterStrip then
		buy.AnchorPoint = Vector2.new(1, 0.5)
		buy.Position = UDim2.new(1, 0, 0.5, 0)
		buy.Size = UDim2.new(0.233, 0, ofInfo(0.117), 0)
	else
		buy.AnchorPoint = Vector2.new(1, 1)
		buy.Position = UDim2.new(1, 0, 1, 0)
		buy.Size = UDim2.new(0.233, 0, ofInfo(0.092), 0)
	end
	for _, d in buy:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = math.max(d.ZIndex, 5)
		end
	end
	buy.ZIndex = 5
end

-- Small image left · name+tags middle · price+buy right. List / compact row.
function UICardComponent:_BuildRow(surface: Frame, spec: EntryLayoutConfig.EntrySpec)
	UIStyler.PaddingXY(10, 8).Parent = surface
	local row = UIStyler.Frame("Content")
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = row
	row.Parent = surface

	local imageSize = spec.imageSize or 52
	local img = self:_MakeImage(row, UDim2.fromOffset(imageSize, imageSize))
	img.LayoutOrder = 1

	-- Right column is a SCALE fraction of the row (never a fixed pixel width)
	-- so it grows with the card on wide list packs — a fixed 130px column
	-- both (a) capped how far the right-aligned price/quantity number could
	-- grow leftward as digits increase, and (b) forced the buy button to stay
	-- squeezed into a narrow slice even on a card with plenty of real width
	-- to spare.
	local rightWidthFrac = 0.34
	local right = stack("Right", 4, Enum.HorizontalAlignment.Right)
	right.Size = UDim2.new(rightWidthFrac, 0, 1, 0)
	right.LayoutOrder = 3
	right.Parent = row

	local middle = stack("Middle", 3)
	middle.Size = UDim2.new(1 - rightWidthFrac, -(imageSize + 20), 1, 0)
	middle.LayoutOrder = 2
	middle.Parent = row
	-- Name/price text scale with the ROW's own real height instead of a fixed
	-- pixel row (matching the TextScaled pattern used everywhere else), so a
	-- pack with a taller/shorter CardHeight still gets proportional text.
	self:_MakeName(middle, UDim.new(0.55, 0)).LayoutOrder = 1
	local tags = self:_MakeTags(middle, UDim.new(0.3, 0))
	if tags then
		tags.LayoutOrder = 2
	end

	local price = self:_MakePrice(right, UDim.new(0.3, 0))
	price.Size = UDim2.new(1, 0, 0.3, 0)
	price.TextXAlignment = Enum.TextXAlignment.Right
	price.LayoutOrder = 1
	local buy = self:_MakeBuy(right)
	buy.LayoutOrder = 2
end

-- Large image left, text column right (name, desc, tags, price, buy). Split.
function UICardComponent:_BuildSplit(surface: Frame, spec: EntryLayoutConfig.EntrySpec, _variant: number)
	UIStyler.Padding(10).Parent = surface
	local row = UIStyler.Frame("Content")
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, 12),
	}).Parent = row
	row.Parent = surface

	local imageW = spec.imageWidth or 0.4
	local img = self:_MakeImage(row, UDim2.new(imageW, -6, 1, 0))
	-- mirror = image on the right, text on the left (SplitRight spec).
	img.LayoutOrder = spec.mirror and 2 or 1

	local right = UIStyler.Frame("Right")
	right.BackgroundTransparency = 1
	right.Size = UDim2.new(1 - imageW, -6, 1, 0)
	right.LayoutOrder = spec.mirror and 1 or 2
	right.Parent = row

	-- Buy is a Scale-height bar ANCHORED to the very bottom of `right` — a
	-- sibling of the text stack below, not one of ITS list-managed children —
	-- so it is ALWAYS flush against the bottom edge with zero dead space,
	-- regardless of how much of the remaining space the variable-length
	-- name/tags/description content above actually fills. Budgeting the list
	-- content to sum to exactly 1.0 (like CardTop's config-derived fractions)
	-- isn't reliably possible here since description length varies per item;
	-- reserving the button's own space structurally, instead of hoping the
	-- content above exactly fills up to it, is what guarantees no gap below it.
	local buyHFrac = CardSpacing.Height.BuyFull
	local buy = self:_MakeBuy(right, true)
	buy.AnchorPoint = Vector2.new(0, 1)
	buy.Position = UDim2.new(0, 0, 1, 0)
	buy.Size = UDim2.new(1, 0, buyHFrac, 0)

	local textGap = 0.02
	local textStack = stack("TextStack", 6)
	textStack.Size = UDim2.new(1, 0, 1 - buyHFrac - textGap, 0)
	textStack.Parent = right

	local o = 0
	local function next_(g: GuiObject) o += 1; g.LayoutOrder = o end
	-- Name/tags/desc/price scale via TextScaled fractions of textStack's own
	-- real height (matching _BuildRow's pattern) instead of a fixed pixel row.
	next_(self:_MakeName(textStack, UDim.new(0.2, 0)))
	local tags = self:_MakeTags(textStack, UDim.new(0.1, 0))
	if tags then next_(tags) end
	-- Reduced from 0.55 -> 0.4: _MakeDescription caps its font at 14px
	-- (MaxTextSize), so a box much taller than what ~2-3 lines at that capped
	-- size actually needs just leaves real, visible blank space below the
	-- text (the same fix applied to _BuildTextFirst).
	local desc = self:_MakeDescription(textStack)
	if desc then
		desc.Size = UDim2.new(1, 0, 0.4, 0)
		next_(desc)
	end
	next_(self:_MakePrice(textStack, UDim.new(0.12, 0)))
end

-- Name + description hero, small image top-right, price+buy footer. Text-heavy.
-- Row heights are SCALE fractions of `col` (col's own real AbsoluteSize IS a
-- fraction of the card, matching CardTop/Row/Split's convention) — never a
-- pixel Offset — so every text element inside (name/price via TextScaled)
-- shrinks/grows with the card at any viewport instead of staying a fixed size.
function UICardComponent:_BuildTextFirst(surface: Frame, spec: EntryLayoutConfig.EntrySpec)
	UIStyler.Padding(12).Parent = surface

	-- Footer (price + buy) is a Scale-height bar ANCHORED to the very bottom
	-- of `surface` — a sibling of `col` below, not one of ITS list-managed
	-- children — so the buy button is ALWAYS flush against the card's bottom
	-- edge with zero dead space, regardless of how much of the remaining
	-- space the variable-length name/tags/description content above actually
	-- fills. Buy is right-aligned within the footer (not centered), matching
	-- the house rule: only images/art get centered, everything else is left
	-- or right aligned.
	local footerHFrac = 0.16
	local footer = UIStyler.Frame("Footer")
	footer.BackgroundTransparency = 1
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 0, 1, 0)
	footer.Size = UDim2.new(1, 0, footerHFrac, 0)
	footer.Parent = surface
	local price = self:_MakePrice(footer, UDim.new(1, 0))
	price.Size = UDim2.new(0.5, 0, 1, 0)
	price.TextYAlignment = Enum.TextYAlignment.Center
	local buy = self:_MakeBuy(footer)
	buy.AnchorPoint = Vector2.new(1, 0.5)
	buy.Position = UDim2.new(1, 0, 0.5, 0)
	buy.Size = UDim2.new(0.42, 0, 1, 0)

	local colGap = 0.02
	local col = stack("Content", 6)
	col.Size = UDim2.new(1, 0, 1 - footerHFrac - colGap, 0)
	col.Parent = surface

	-- Header: name (left, fills) + small square image (right). The thumbnail
	-- stays a fixed pixel square (matching Row's own small-thumbnail precedent
	-- — imageSize is a deliberate fixed icon size, not something that needs to
	-- scale with the card), but the row's own height is a Scale fraction so
	-- the name text next to it can TextScale against a real, card-proportional
	-- box.
	local header = UIStyler.Frame("Header")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0.26, 0)
	header.LayoutOrder = 1
	header.Parent = col
	local imgSize = spec.imageSize or 44
	local img = self:_MakeImage(header, UDim2.fromOffset(imgSize, imgSize))
	img.AnchorPoint = Vector2.new(1, 0)
	img.Position = UDim2.fromScale(1, 0)
	local name = self:_MakeName(header, UDim.new(1, 0))
	name.Size = UDim2.new(1, -(imgSize + 10), 1, 0)
	name.TextYAlignment = Enum.TextYAlignment.Center

	local tags = self:_MakeTags(col, UDim.new(0.09, 0))
	if tags then tags.LayoutOrder = 2 end
	-- Reduced from 0.55 -> 0.36: _MakeDescription caps its font at 14px
	-- (MaxTextSize), so a box much taller than what ~2-3 lines at that capped
	-- size actually needs just leaves real, visible blank space below the
	-- text — confirmed via screenshot. Sized to realistically fit capped-font
	-- text instead of reserving a box bigger than TextScaled will ever fill.
	local desc = self:_MakeDescription(col)
	if desc then
		desc.Size = UDim2.new(1, 0, 0.36, 0)
		desc.LayoutOrder = 3
	end
end

-- ========================================================================
-- Theming (one place → consistent across all arrangements)
-- ========================================================================

-- ========================================================================
-- GL PACK BRANCH — the active pack's policy, not a fork. Everything below
-- RE-DRESSES the structure the arrangements already built (nothing is rebuilt,
-- moved or removed), so the public API, props, Update() and the onBuy flow are
-- untouched. Built lazily on the first GL style pass, then only re-tinted and
-- toggled; a live swap back off GL runs _StyleGLRelease, which puts every GL
-- part away (disable-not-destroy) instead of tearing it down.
-- ========================================================================

function UICardComponent:_StyleGL(theme: Types.UITheme)
	local arcade = theme.Arcade
	local ink = theme.Colors.Stroke
	local surface = self._surface :: Frame

	-- ---- card surface: cut silhouette + halftone + sticker shadow -------
	-- (laws 1/4/8: no rounded corner anywhere, every plate carries the hard
	-- offset shadow, halftone rides the major surface.) Plates ride LIGHTER
	-- than the page on purpose — the black sticker shadow only reads against a
	-- lighter card.
	local plate = self._glPlate
	if not plate then
		plate = GLLayoutKit.Slice(theme, "cardCut", arcade.Row, "GLPlate")
		plate.Size = UDim2.fromScale(1, 1)
		plate.ZIndex = 0 -- beneath the texture layer (1) and all arrangement content
		plate.Parent = surface
		self._glPlateShadow = GLLayoutKit.Shadow(theme, plate, "sm", self._glShadows)
		GLLayoutKit.Tile(theme, "halftone", ink, 0.88, "GLTone").Parent = plate
		self._glPlate = plate
	end
	plate.ImageColor3 = arcade.Row
	plate.BackgroundColor3 = arcade.Row -- the kit's missing-asset fallback path
	plate.Visible = true
	if self._glPlateShadow then
		self._glPlateShadow:SetEnabled(true)
	end
	surface.BackgroundTransparency = 1
	-- Law 6 needs something to BREAK the container, and a clipped surface eats
	-- both the overhanging badge and the shadow offset.
	surface.ClipsDescendants = false
	if self._stroke then
		self._stroke.Enabled = false -- the 9-slice draws the ink itself
	end
	if self._glass then
		self._glass.Enabled = false -- cel shading: flat fills, no sheen
	end

	-- ---- image well -> ART SLOT (law 7) ---------------------------------
	-- Item art is content this pack cannot generate, and the glossy 3D icon set
	-- is explicitly banned as the visual language — so the well ships as a
	-- correctly-shaped, hatched, visibly-intentional reserved slot. Whatever
	-- the arrangement put in the well (art image, sunburst, monogram) is only
	-- HIDDEN, so a swap back off GL restores it exactly.
	local holder = self._imageHolder :: Frame?
	if holder then
		local slot = self._glArtSlot
		if not slot then
			local hidden = {}
			for _, child in holder:GetChildren() do
				if child:IsA("GuiObject") and child.Visible then
					child.Visible = false
					table.insert(hidden, child)
				end
			end
			self._glHiddenArt = hidden
			slot = GLLayoutKit.Slice(theme, "artSlot", theme.Colors.Disabled, "GLArtSlot")
			slot.Size = UDim2.fromScale(1, 1)
			slot.ZIndex = 2
			slot.Parent = holder
			GLLayoutKit.Tile(theme, "halftone", ink, 0.8, "GLArtTone").Parent = slot
			local label = GLLayoutKit.Text(theme, 13, theme.Colors.TextSecondary, "GLArtLabel")
			label.Text = "ART SLOT"
			label.AnchorPoint = Vector2.new(0.5, 0.5)
			label.Position = UDim2.fromScale(0.5, 0.5)
			label.Size = UDim2.fromScale(1, 0.3)
			label.Rotation = GLLayoutKit.TILT * 2
			label.ZIndex = 3
			label.Parent = slot
			local torn = GLLayoutKit.Slice(theme, "edgeTorn", ink, "GLArtTorn")
			torn.AnchorPoint = Vector2.new(0, 1)
			torn.Position = UDim2.new(0, 0, 1, 6)
			torn.Size = UDim2.new(1, 0, 0, 10)
			torn.Rotation = 180
			torn.ZIndex = 3
			torn.Parent = slot
			self._glArtSlot = slot
			self._glArtLabel = label
		end
		slot.ImageColor3 = theme.Colors.Disabled
		slot.BackgroundColor3 = theme.Colors.Disabled
		slot.Visible = true
		if self._glArtLabel then
			self._glArtLabel.TextColor3 = theme.Colors.TextSecondary
		end
		holder.BackgroundTransparency = 1
		holder.ClipsDescendants = false -- let the torn lower edge overhang
		if self._imageStroke then
			self._imageStroke.Enabled = false -- no accent ring on a hatched well
		end
	end

	-- ---- type: cream display, gold value (laws 2/3) ---------------------
	if self._name then
		self._name.TextColor3 = theme.Colors.TextPrimary
		UIChrome.TextOutline(self._name)
	end
	if self._desc then
		self._desc.TextColor3 = theme.Colors.TextSecondary
	end
	if self._price then
		-- The value reads as GOLD NUMERALS, never a currency-candy colour and
		-- never black; the black stays where the pack allows it — the outline.
		self._price.FontFace = theme.Fonts.Numeric
		self._price.TextColor3 = arcade.Gold
		UIChrome.TextOutline(self._price)
	end

	-- ---- tag chips -> tilted paper stickers (laws 4/5/6) ----------------
	-- The badge components keep their own text, variant colour and lifecycle;
	-- only the SURFACE under them changes, to the kit's cut paper chip.
	local chips = self._glBadgeChips
	if not chips then
		chips = {}
		self._glBadgeChips = chips
		for _, badge in self._badges do
			local root = badge.Root :: Frame
			-- The chip is tinted from the badge's OWN resolved variant token
			-- (colour is meaning, doc §3.3) — read off the instance, so no
			-- variant map is duplicated here and no literal is introduced.
			local chip = GLLayoutKit.Slice(theme, "chipPaper", root.BackgroundColor3, "GLChip")
			chip.Size = UDim2.fromScale(1, 1)
			chip.ZIndex = 0
			chip.Parent = root
			local shadow = GLLayoutKit.Shadow(theme, chip, "sm", self._glShadows)
			table.insert(chips, { root = root, chip = chip, shadow = shadow })
		end
	end
	for _, entry in chips do
		entry.chip.ImageColor3 = entry.root.BackgroundColor3
		entry.chip.BackgroundColor3 = entry.root.BackgroundColor3
		entry.chip.Visible = true
		entry.shadow:SetEnabled(true)
		entry.root.BackgroundTransparency = 1
		entry.root.Rotation = GLLayoutKit.TILT * 1.6
		local stroke = entry.root:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = false
		end
	end

	-- ---- overlay price chip -> ink plate + gold numerals (law 3) --------
	if self._priceChipLabel then
		local host = self._priceChipLabel.Parent :: Frame
		local back = self._glPriceChip
		if not back then
			back = GLLayoutKit.Slice(theme, "chipPaper", arcade.NearBlack, "GLPriceChip")
			back.Size = UDim2.fromScale(1, 1)
			back.Rotation = -GLLayoutKit.TILT
			back.ZIndex = 0
			back.Parent = host
			self._glPriceChipShadow = GLLayoutKit.Shadow(theme, back, "sm", self._glShadows)
			self._glPriceChip = back
		end
		back.ImageColor3 = arcade.NearBlack
		back.BackgroundColor3 = arcade.NearBlack
		back.Visible = true
		if self._glPriceChipShadow then
			self._glPriceChipShadow:SetEnabled(true)
		end
		host.BackgroundTransparency = 1
		if self._priceChipStroke then
			self._priceChipStroke.Enabled = false
		end
		self._priceChipLabel.TextColor3 = arcade.Gold
		UIChrome.TextOutline(self._priceChipLabel)
	end

	-- ---- quantity chip -> the same ink plate + gold count ---------------
	if self._qtyLabel then
		local host = self._qtyLabel.Parent :: Frame
		local back = self._glQtyChip
		if not back then
			back = GLLayoutKit.Slice(theme, "chipPaper", arcade.NearBlack, "GLQtyChip")
			back.Size = UDim2.fromScale(1, 1)
			back.Rotation = -GLLayoutKit.TILT
			back.ZIndex = 0
			back.Parent = host
			self._glQtyChipShadow = GLLayoutKit.Shadow(theme, back, "sm", self._glShadows)
			self._glQtyChip = back
		end
		back.ImageColor3 = arcade.NearBlack
		back.BackgroundColor3 = arcade.NearBlack
		back.Visible = true
		if self._glQtyChipShadow then
			self._glQtyChipShadow:SetEnabled(true)
		end
		host.BackgroundTransparency = 1
		if self._qtyStroke then
			self._qtyStroke.Enabled = false
		end
		self._qtyLabel.TextColor3 = arcade.Gold
		UIChrome.TextOutline(self._qtyLabel)
	end
end

-- Live swap OFF the GL pack: put every GL part away and hand the classic
-- chrome back the properties the classic pass does not itself reassign.
-- Early-outs to nothing on a card that was never dressed.
function UICardComponent:_StyleGLRelease()
	if not self._glPlate then
		return
	end
	self._glPlate.Visible = false
	if self._glPlateShadow then
		self._glPlateShadow:SetEnabled(false)
	end
	(self._surface :: Frame).ClipsDescendants = true
	if self._stroke then
		self._stroke.Enabled = true
	end
	if self._glass then
		self._glass.Enabled = true
	end
	if self._glArtSlot then
		self._glArtSlot.Visible = false
	end
	for _, child in self._glHiddenArt or {} do
		child.Visible = true
	end
	local holder = self._imageHolder :: Frame?
	if holder then
		holder.BackgroundTransparency = 0
		holder.ClipsDescendants = true
	end
	if self._imageStroke then
		self._imageStroke.Enabled = true
	end
	for _, entry in self._glBadgeChips or {} do
		entry.chip.Visible = false
		entry.shadow:SetEnabled(false)
		entry.root.BackgroundTransparency = 0
		entry.root.Rotation = 0
		local stroke = entry.root:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = true
		end
	end
	if self._glPriceChip then
		self._glPriceChip.Visible = false
		if self._glPriceChipShadow then
			self._glPriceChipShadow:SetEnabled(false)
		end
		if self._priceChipLabel then
			(self._priceChipLabel.Parent :: Frame).BackgroundTransparency = 0
		end
		if self._priceChipStroke then
			self._priceChipStroke.Enabled = true
		end
	end
	if self._glQtyChip then
		self._glQtyChip.Visible = false
		if self._glQtyChipShadow then
			self._glQtyChipShadow:SetEnabled(false)
		end
		if self._qtyLabel then
			(self._qtyLabel.Parent :: Frame).BackgroundTransparency = 0
		end
		if self._qtyStroke then
			self._qtyStroke.Enabled = true
		end
	end
end

function UICardComponent:_Style(theme: Types.UITheme)
	local arcade = theme.Arcade
	local accent = arcade.ShopAccents[self._accentIndex] or arcade.Gold

	-- Card surface: slate row colour at the row transparency (doc §3.2), plus
	-- the 3px black policy stroke. The stroke is created lazily HERE (not in
	-- _Build) because UIChrome.Stroke is theme-driven and the first theme only
	-- lands after _Build; the arcade policy ignores the caller anyway (always
	-- 3px black), so no repaint on later theme swaps is needed.
	self:_SetColor(self._surface, "BackgroundColor3", arcade.Row)
	self._surface.BackgroundTransparency = arcade.RowTransparency
	if not self._stroke then
		self._stroke = UIChrome.Stroke(theme, "Arcade")
		self._stroke.Parent = self._surface
	end
	-- Studs texture over the card fill (theme-gated; hidden when theme.Texture
	-- is nil — the Pottery base has none).
	UIStyler.ConfigureTexture(self._texture, theme.Texture)

	-- Image well: near-black box (doc §3.2) ringed by this card's rotation
	-- accent (2px stroke built in _MakeImage; only the colour is themed).
	if self._imageHolder then
		self:_SetColor(self._imageHolder, "BackgroundColor3", arcade.NearBlack)
	end
	if self._imageStroke then
		self:_SetColor(self._imageStroke, "Color", accent)
	end
	-- Monogram fallback glyph (only when the item has no art): the style's
	-- display font — glyph labels are never left on the engine default
	-- (LegacyArial lacks coverage and renders nothing).
	if self._mono then
		self._mono.FontFace = theme.Fonts.Title
	end

	-- Item name: display font tinted with the rotation accent (doc §3.2 —
	-- accent tints stroke + label), with the non-negotiable black outline
	-- (doc §2) so it reads over anything, including Overlay art and scrims.
	if self._name then
		self._name.FontFace = theme.Fonts.Subtitle
		self._name.TextColor3 = accent
		UIChrome.TextOutline(self._name)
	end
	if self._nameConstraint then
		-- Grid names cap out at the smaller Body size (never grow past a
		-- typical 1-line name's size); other slots cap at Subtitle. Actual
		-- rendered size still shrinks below the cap via TextScaled to fit.
		self._nameConstraint.MaxTextSize = self._nameOneLine and theme.TextSizes.Body or theme.TextSizes.Subtitle
	end
	if self._nameStrip then
		self._nameStrip.BackgroundColor3 = arcade.NearBlack
		self._nameStrip.BackgroundTransparency = 0.32
	end

	-- Price text: ALWAYS the currency's colour (doc §3.3 — Cash green, Bux
	-- blue, Robux magenta, no exceptions), display font, black outline.
	if self._price then
		self._price.FontFace = theme.Fonts.Numeric
		-- Scale-height rows (CardTop) use TextScaled + a constraint (set below)
		-- instead of a fixed pixel TextSize, so the price shrinks/grows with the
		-- card at any viewport instead of overflowing a small Scale-sized row.
		if not self._priceScaled then
			self._price.TextSize = theme.TextSizes.Body
		end
		self._price.TextColor3 = UIChrome.CurrencyColor(theme, self._item.currencyType)
		UIChrome.TextOutline(self._price)
	end
	if self._priceConstraint then
		self._priceConstraint.MaxTextSize = theme.TextSizes.Body
	end

	-- Description: the quiet body font in the secondary ice blue (doc §3.2).
	if self._desc then
		self._desc.FontFace = theme.Fonts.Body
		self._desc.TextColor3 = arcade.IceBlue
	end
	if self._descConstraint then
		self._descConstraint.MaxTextSize = theme.TextSizes.Small
	end

	-- Overlay Flat panel / CenterStrip footer: a translucent near-black box
	-- behind just the text — reads cleanly over any art without darkening it.
	if self._flatBg then
		self._flatBg.BackgroundColor3 = arcade.NearBlack
		self._flatBg.BackgroundTransparency = 0.32
	end

	-- Quantity badge (inventory rows): slate chip with an ice-blue count
	-- (doc §3.2 — ice blue is the "counts / secondary notes" colour). It's
	-- informational, not an action, so it doesn't compete with name/price.
	if self._qtyLabel then
		local qtyChip = self._qtyLabel.Parent :: Frame
		self:_SetColor(qtyChip, "BackgroundColor3", arcade.Panel)
		-- Thin chip border: Classic keeps the bespoke 2px black micro stroke;
		-- a styled chrome frames the chip through the UIChrome policy instead.
		if not self._qtyStroke then
			self._qtyStroke = if theme.Chrome ~= nil
				then UIChrome.Stroke(theme, "Arcade", "Button")
				else UIStyler.Stroke(Color3.new(), 2, 0)
			self._qtyStroke.Parent = qtyChip
		end
		self._qtyLabel.FontFace = theme.Fonts.Numeric
		self._qtyLabel.TextColor3 = arcade.IceBlue
		UIChrome.TextOutline(self._qtyLabel)
		if self._qtyLabelConstraint then
			self._qtyLabelConstraint.MaxTextSize = TextScaleConfig.ScaledCap(theme.TextSizes.Small)
		end
	end

	-- Price chip (overlayBadgeAndPrice): a miniature price button riding on
	-- the art — currency-coloured fill (doc §3.3), white amount, black outline.
	if self._priceChipLabel then
		local priceChip = self._priceChipLabel.Parent :: Frame
		self:_SetColor(priceChip, "BackgroundColor3", UIChrome.CurrencyColor(theme, self._item.currencyType))
		-- Thin chip border: same Classic-vs-styled gate as the quantity chip.
		if not self._priceChipStroke then
			self._priceChipStroke = if theme.Chrome ~= nil
				then UIChrome.Stroke(theme, "Arcade", "Button")
				else UIStyler.Stroke(Color3.new(), 2, 0)
			self._priceChipStroke.Parent = priceChip
		end
		self._priceChipLabel.FontFace = theme.Fonts.Numeric
		self._priceChipLabel.TextColor3 = WHITE
		UIChrome.TextOutline(self._priceChipLabel)
		if self._priceChipLabelConstraint then
			self._priceChipLabelConstraint.MaxTextSize = TextScaleConfig.ScaledCap(theme.TextSizes.Small)
		end
	end

	-- ACTIVE-PACK POLICY, detected once per style application (the same switch
	-- UIChrome.ModalCard makes). Everything above is the untouched classic
	-- paint — it still runs, so every token stays live and a swap back off GL
	-- lands on a fully-repainted card; the GL pass then re-dresses the surface,
	-- the art well, the chips and the value type in the comic language.
	if theme.LayoutKit == "GL" then
		self:_StyleGL(theme)
	else
		self:_StyleGLRelease()
	end
end

-- Patch the parts of a card that change without a purchase (affordability,
-- owned state, live balance-driven price re-renders) WITHOUT destroying and
-- rebuilding the whole card. This is what lets the shop update in place instead
-- of flickering/rebuilding every entry whenever currency changes — the same
-- kind of reload a real game would visibly suffer from on every value tick.
function UICardComponent:Update(props: { affordable: boolean?, owned: boolean? })
	if props.affordable ~= nil then
		self.Props.affordable = props.affordable
	end
	if props.owned ~= nil then
		self.Props.owned = props.owned
	end
	if not self._buy then
		return
	end
	local owned = self.Props.owned
	local affordable = self.Props.affordable
	-- Price-button mode: `owned` recolours grey OWNED in place with children
	-- hidden (doc §11.2); unaffordable stays currency-coloured, DIMMED in
	-- place (55% fill transparency + grey text) and still fully tappable so
	-- every tap answers — the screen explains via its can't-afford toast
	-- (doc §11.1); only ownership disables the buy.
	self._buy:SetContent({
		owned = owned or false,
		dimmed = affordable == false,
	})
	self._buy:SetEnabled(not owned)
end

function UICardComponent:Destroy()
	-- Stop the sunburst spin first — RenderStepped effects must never outlive
	-- their card (doc §5.4).
	if self._sunburstSpin then
		self._sunburstSpin:Disconnect()
		self._sunburstSpin = nil
	end
	-- GL sticker shadows are BUDGET HANDLES (StyleKit.Capabilities counts them)
	-- — release them, don't just let the Gui die under them (law 9). No-op on
	-- any pack that never took the GL branch.
	GLLayoutKit.ReleaseShadows(self._glShadows)
	self._glBadgeChips = nil
	for _, badge in self._badges do
		badge:Destroy()
	end
	if self._buy then
		self._buy:Destroy()
	end
	UIComponentBase.Destroy(self)
end

return UICardComponent
