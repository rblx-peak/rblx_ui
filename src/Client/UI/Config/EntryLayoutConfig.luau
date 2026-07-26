--!strict
-- Entry layout specs — the heart of layout-pack variety.
--
-- An "entry" is a repeated data row/card (a shop item today; inventory slots,
-- quest rows, leaderboard rows tomorrow). Every entry is built by ONE renderer
-- (UICardComponent) from a spec chosen here. That is the consistency guarantee:
-- variety comes from swapping specs, never from bespoke per-pack card code, so
-- two items in the same pack are always structurally identical and a theme
-- always paints them the same way.
--
-- A spec picks an `arrangement` (how the renderer positions image/name/price/
-- buy/tags/description) and tunes it with parameters. Add a new look by adding
-- a spec here and pointing a pack at it — no renderer or screen changes.

local EntryLayoutConfig = {}

-- arrangement:
--   "CardTop"   image on top, text stacked below (grid card; standard/image-focal)
--   "Row"       small image left · name+tags middle · price+buy right (list/compact)
--   "Split"     large image left · name+desc+price+buy right (split feel)
--   "TextFirst" name+description hero, small image top-right, price+buy footer (text-heavy)
--   "Banner"    wide hero: big image left half, text+buy right half (featured)
--   "Overlay"   full-bleed image with text overlaid on a bottom scrim (image showcase)
export type EntrySpec = {
	arrangement: "CardTop" | "Row" | "Split" | "TextFirst" | "Banner" | "Overlay",
	-- Focal sizing. Interpreted per arrangement (see renderer):
	--   CardTop  -> imageHeight (px)
	--   Row      -> imageSize (px, square)
	--   Split    -> imageWidth (0..1 fraction of the card)
	--   TextFirst-> imageSize (px, square)
	--   Banner   -> imageWidth (0..1 fraction)
	imageHeight: number?,
	imageSize: number?,
	imageWidth: number?,
	-- Focal image shape, as width:height. For CardTop the image is ALWAYS a fixed
	-- imageHeight tall, width = imageHeight * imageAspect, CENTRED in its row —
	-- 1 (or nil/0) = square, the AAA default; 0.75 = portrait; >1 = wide. Change
	-- this per spec to reshape the art slot without touching the renderer.
	imageAspect: number?,
	-- CardTop only. true = image fills the full card content width edge-to-edge
	-- (no side margin; the card is exactly as tall as it needs to be — can end up
	-- a bit long, and that's fine). false/nil = image is a centred square/rect
	-- capped to keep the whole card near a compact ~1:1.2 ratio (small even side
	-- margins). Two legitimate looks, picked per spec.
	imageFillWidth: boolean?,
	showTags: boolean,
	showDescription: boolean,
	-- CardTop only. true = render the price on the RIGHT end of the tag-badge row
	-- (name above, buy below), instead of price on its own row under the name.
	-- The badges occupy a flex area that shrinks so they never overlap the price.
	priceWithTags: boolean?,
	-- CardTop only. true = tag badges overlay the image's TOP-LEFT corner and the
	-- price overlays the image's BOTTOM-RIGHT corner (both fully INSIDE the image
	-- bounds, in a small themed chip for legibility) instead of living in the
	-- text column below the image. The text column then holds only Name + Buy.
	overlayBadgeAndPrice: boolean?,
	-- CardTop only. true = the tag badges (Sale/New/Popular/…) straddle the
	-- image's TOP edge — half overlapping onto the image, half hanging above it
	-- — instead of sitting in their own row below the image in the text column.
	-- A poster/movie-banner look for the same tags data, no renderer changes
	-- needed elsewhere: the badges are still the same _MakeTags output, just
	-- parented/positioned differently.
	tagStraddle: boolean?,
	-- "Full" wide button, "Compact" small right-aligned, "IconRight" tiny,
	-- "Pill" a smaller centred rounded button with extra breathing room BELOW the
	-- image box (still inside the same card surface), "Quantity" shows an
	-- owned-count badge INSTEAD of a buy button (inventory view — nothing to
	-- purchase, just what you have). CardTop only, and both escape the card's
	-- clipped surface entirely (built as a sibling, not clipped by it):
	-- "OutsideBelow" floats the button fully below the box, not touching it.
	-- "Straddle" centres the button ON the box's bottom edge — half overlapping
	-- inside, half hanging out below.
	buyStyle: "Full" | "Compact" | "IconRight" | "Pill" | "Quantity" | "OutsideBelow" | "Straddle",
	-- Text alignment for the name/price/tags. OPTIONAL — omit it (or nil) and the
	-- entry is LEFT-aligned, the house default (see EntryLayoutConfig.Get). Set it
	-- to Enum.TextXAlignment.Center or .Right only when a look deliberately wants
	-- centred/right-aligned text.
	nameAlign: Enum.TextXAlignment?,
	-- Split only: put the image on the RIGHT and the text column on the left.
	mirror: boolean?,
	-- Overlay only: "Scrim" (default) = dark gradient fading up from the bottom
	-- edge behind the text. "Flat" = no gradient/shadow at all — just a small
	-- rounded, semi-transparent flat-colour panel sitting directly behind the
	-- text block, so the rest of the image stays completely clean. "CenterStrip"
	-- = no scrim either — just a translucent full-width strip crossing the
	-- vertical middle of the image holding ONLY the name (poster/title-card
	-- look); price+buy get their own small translucent footer at the bottom.
	overlayBg: ("Scrim" | "Flat" | "CenterStrip")?,
}

EntryLayoutConfig.Specs = {
	StandardCard = {
		arrangement = "CardTop",
		imageAspect = 1, -- square art, the realistic default
		imageFillWidth = true, -- fills the card edge-to-edge, no side margin
		showTags = true,
		showDescription = false,
		buyStyle = "Full",
		-- Left-aligned by default (house style).
	},
	-- Standard 2.0: like StandardCard, but the tag badges overlay the image's
	-- top-left corner and the price overlays its bottom-right corner (both
	-- inside the art, in a small themed chip) — the text column below just
	-- holds the name and buy button.
	StandardCardPlus = {
		arrangement = "CardTop",
		imageAspect = 1,
		imageFillWidth = true,
		showTags = true,
		showDescription = false,
		buyStyle = "Full",
		overlayBadgeAndPrice = true,
	},
	-- Standard, but the tag badges (Sale/New/Popular/…) straddle the TOP edge of
	-- the image — half overlapping onto the art, half hanging above it — instead
	-- of sitting in the text column below the image. A poster/banner look.
	StandardCardBanner = {
		arrangement = "CardTop",
		imageAspect = 1,
		imageFillWidth = true,
		showTags = true,
		showDescription = false,
		buyStyle = "Full",
		tagStraddle = true,
	},
	-- Image showcase: full-bleed square art with name/price/tags/buy OVERLAID on a
	-- bottom scrim so the text reads over the image. The card IS the image (compact).
	ImageFocal = {
		arrangement = "Overlay",
		imageAspect = 1,
		overlayBg = "Scrim",
		showTags = true,
		showDescription = false,
		buyStyle = "Compact",
		nameAlign = Enum.TextXAlignment.Left,
	},
	-- Same showcase, but no scrim/shadow at all — a small translucent flat panel
	-- sits behind just the text so the rest of the art stays completely clean.
	ImageFocalFlat = {
		arrangement = "Overlay",
		imageAspect = 1,
		overlayBg = "Flat",
		showTags = true,
		showDescription = false,
		buyStyle = "Compact",
		nameAlign = Enum.TextXAlignment.Left,
	},
	-- Taller-than-square art (fills the card width, so a smaller aspect makes it
	-- noticeably longer) — the "not everything has to be a perfect square" pack.
	-- 0.8 reads as clearly non-square without turning into a lanky strip.
	TallCard = {
		arrangement = "CardTop",
		imageAspect = 0.8,
		imageFillWidth = true,
		showTags = true,
		showDescription = false,
		buyStyle = "Full",
		nameAlign = Enum.TextXAlignment.Left,
	},
	-- Square image in its own tidy box, then a smaller PILL buy button sitting
	-- below it with real breathing room — never flush against the image, and a
	-- distinctly different (smaller, rounder) shape than the full-width button.
	StandardPro = {
		arrangement = "CardTop",
		imageHeight = 150,
		imageAspect = 1,
		showTags = true,
		showDescription = false,
		buyStyle = "Pill",
		-- Left by default (house style). Set nameAlign = Center to re-centre.
	},
	-- Inventory view: a row with a square thumbnail and an OWNED-COUNT badge in
	-- the bottom-right instead of a buy button — for showing what you have, not
	-- what you can purchase.
	QuantityRow = {
		arrangement = "Row",
		imageSize = 56,
		imageAspect = 1,
		showTags = false,
		showDescription = false,
		buyStyle = "Quantity",
		nameAlign = Enum.TextXAlignment.Left,
	},
	-- Inventory GRID view: the card IS the square image, full-bleed, with just an
	-- owned-count badge overlaid in the bottom-right corner (and tags top-left).
	-- No name/price clutter — for browsing a grid of what you own.
	QuantityTile = {
		arrangement = "Overlay",
		imageAspect = 1,
		showTags = true,
		showDescription = false,
		buyStyle = "Quantity",
		nameAlign = Enum.TextXAlignment.Left,
	},
	-- Square image in a clean box; the buy button floats FULLY OUTSIDE/below the
	-- box (not overlapping it at all) — a bigger visual break from the image than
	-- the Pill style, which still sits inside the same rounded surface.
	OutsideCard = {
		arrangement = "CardTop",
		imageAspect = 1,
		imageFillWidth = true, -- image spans the full card width, no side gap
		showTags = true,
		showDescription = false,
		buyStyle = "OutsideBelow",
		-- Left by default (house style). Set nameAlign = Center to re-centre.
	},
	-- Square image in a clean box; the buy button straddles the box's bottom
	-- edge — half overlapping inside the box, half hanging out below it.
	StraddleCard = {
		arrangement = "CardTop",
		imageAspect = 1,
		imageFillWidth = true, -- image spans the full card width, no side gap
		showTags = true,
		showDescription = false,
		buyStyle = "Straddle",
		-- Left by default (house style). Set nameAlign = Center to re-centre.
	},
	ListRow = {
		arrangement = "Row",
		imageSize = 52,
		imageAspect = 1,
		showTags = true,
		showDescription = false,
		buyStyle = "Compact",
		nameAlign = Enum.TextXAlignment.Left,
	},
	-- The boxy base-UI shop row (reproduces Reference/RefServersShop): a nested
	-- box with a blue image box, name, gold label, green price/buy button and a
	-- sub-label. ShopScreen renders this spec with UIListRowComponent (its own
	-- self-contained renderer), NOT the shared Row card path — the arrangement/
	-- fields here are only a nominal Row so EntryLayoutConfig.Get and PackExporter
	-- treat it like any other list spec instead of silently falling back.
	ServerRow = {
		arrangement = "Row",
		imageSize = 56,
		imageAspect = 1,
		showTags = true,
		showDescription = false,
		buyStyle = "Compact",
		nameAlign = Enum.TextXAlignment.Left,
	},
	TextHeavy = {
		arrangement = "TextFirst",
		imageSize = 48,
		imageAspect = 1,
		showTags = true,
		showDescription = true,
		buyStyle = "Full",
		nameAlign = Enum.TextXAlignment.Left,
	},
	SplitLeft = {
		arrangement = "Split",
		imageWidth = 0.42,
		imageAspect = 1, -- square image column, not a tall strip
		showTags = true,
		showDescription = true,
		buyStyle = "Full",
		nameAlign = Enum.TextXAlignment.Left,
	},
	HeroBanner = {
		arrangement = "Banner",
		imageWidth = 0.42,
		imageAspect = 0, -- cinematic wide image on purpose
		showTags = true,
		showDescription = true,
		buyStyle = "Full",
		nameAlign = Enum.TextXAlignment.Left,
	},

	-- ---- New layout specs -------------------------------------------------

	-- Small square tiles, centred, minimal text — an icon grid / storefront wall.
	IconTile = {
		arrangement = "CardTop",
		imageHeight = 120,
		imageAspect = 1,
		showTags = false,
		showDescription = false,
		buyStyle = "Compact",
		-- Left by default (house style). Set nameAlign = Center to re-centre.
	},
	-- Big square hero card: large square image, centred name/price, full buy.
	SquareShowcase = {
		arrangement = "CardTop",
		imageHeight = 172,
		imageAspect = 1,
		showTags = true,
		showDescription = false,
		buyStyle = "Full",
		-- Left by default (house style). Set nameAlign = Center to re-centre.
	},
	-- Dense list row with description — inventory / quest-log feel.
	DetailRow = {
		arrangement = "Row",
		imageSize = 64,
		imageAspect = 1,
		showTags = true,
		showDescription = false,
		buyStyle = "Compact",
		nameAlign = Enum.TextXAlignment.Left,
	},
	-- Image RIGHT, text left (mirror of Split) — magazine/spotlight feel.
	SplitRight = {
		arrangement = "Split",
		imageWidth = 0.42,
		imageAspect = 1,
		showTags = true,
		showDescription = true,
		buyStyle = "Full",
		nameAlign = Enum.TextXAlignment.Left,
		mirror = true,
	},
	-- Tall portrait card: 3:4 image, gacha/character-select feel.
	Portrait = {
		arrangement = "CardTop",
		imageHeight = 176,
		imageAspect = 0.75, -- 3:4 portrait
		showTags = true,
		showDescription = false,
		buyStyle = "Full",
		-- Left by default (house style). Set nameAlign = Center to re-centre.
	},
	-- Full-bleed image, completely clean except for one translucent strip
	-- crossing the vertical middle that holds ONLY the name — a poster/title-
	-- card look. Price+buy sit in their own small translucent footer at the
	-- bottom so the rest of the art (top + most of the middle) stays untouched.
	CenterStripCard = {
		arrangement = "Overlay",
		imageAspect = 1,
		overlayBg = "CenterStrip",
		showTags = true,
		showDescription = false,
		buyStyle = "Compact",
		-- Left by default (house style). Set nameAlign = Center to re-centre.
	},
	-- Compact icon+name chip row, buy as a tiny icon — settings/menu list feel.
	MenuRow = {
		arrangement = "Row",
		imageSize = 40,
		imageAspect = 1,
		showTags = false,
		showDescription = false,
		buyStyle = "IconRight",
		nameAlign = Enum.TextXAlignment.Left,
	},
} :: { [string]: EntrySpec }

-- Fetch a spec, normalising alignment: anything is LEFT-aligned by default (the
-- house style), and a spec opts into Center/Right explicitly. A missing
-- nameAlign therefore means Left, and this is the single place that default is
-- enforced so no spec can silently ship centered. To make a spec centred/right,
-- set nameAlign = Enum.TextXAlignment.Center (or .Right).
function EntryLayoutConfig.Get(id: string): EntrySpec
	local spec = EntryLayoutConfig.Specs[id] or EntryLayoutConfig.Specs.StandardCard
	if spec.nameAlign == nil then
		-- Return a shallow copy with the default filled in, so we never mutate the
		-- shared spec table (a spec is reused across every card in a pack).
		local copy = table.clone(spec)
		copy.nameAlign = Enum.TextXAlignment.Left
		return copy
	end
	return spec
end

return EntryLayoutConfig
