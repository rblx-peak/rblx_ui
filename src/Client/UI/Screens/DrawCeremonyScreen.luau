--!strict
-- DRAW CEREMONY (E4) — the Gurren Lagann gacha moment. A five-stage,
-- fully skippable celebration of a SERVER-AUTHORITATIVE pull:
--
--   1. insert     — a drill-ticket chip slams center (scale slam + capped shake)
--   2. spin-up    — a dial's pointer spins up with a rising gold anticipation glow
--   3. slash-wipe — two full-screen angular panels close on a slash line, then open
--   4. reveals    — per-item card flip-ins escalating by rarity (common pop /
--                   rare flip + gold glow + small cut-in / giga cut-in first,
--                   then the card with lg glow + breathing pulse). A pull at or
--                   over the batch threshold reveals its commons as one grid
--                   beat; only the best pull gets the full ceremony.
--   5. summary    — every card face-up + CONTINUE.
--
-- THE 0.4 BOUNDARY: Styling owns static appearance and state looks — each
-- result card is a tagged UIChip (+DialectComic) whose rare/giga states are
-- UIFeatured/UIMaxed modifier tags flipped ONLY through StateDriver; those
-- StyleRules are inert until the engine activates styling application, and
-- the imperative theme path (budget-registered UIChrome glow handles) renders
-- the identical look meanwhile. Luau + UITicker own everything sequenced,
-- continuous or non-styling-triggered: stage clock + beat scheduling, dial
-- rotation, slam shake, glow breathing, cut-in choreography. No behavior is
-- implemented on both sides.
--
-- SERVER-AUTHORITATIVE: Show(data) renders ONLY the confirmed results the
-- caller hands in — this screen never rolls, weights or invents a pull.
--
-- NO SKEW EXISTS IN ROBLOX — techniques used here, per element:
--   * ticket chip / result cards: whole-element Rotation on the ART child
--     (the layout footprint frame never rotates, so grids never reflow);
--   * slash-wipe: two OVERSIZED frames rotated by ceremony.slashDeg sliding
--     inside a full-screen ClipsDescendants frame — the rotated-clipped
--     frame trick; their slanted bodies sweep the viewport edge-to-edge;
--   * cut-in bands: full-width rotated strips tweened across the same clipper.
--
-- Skippable (never blocks input): any click / key / gamepad A advances the
-- current stage to its final state; SKIP ALL, Escape or gamepad B jumps
-- straight to the summary grid. ReduceMotion (boolean attribute on the screen
-- Gui or Root) collapses the whole ceremony to the confirmed summary.
--
-- Pooling + budget: result cards come from a pool; each pooled card owns ONE
-- sticker UIShadow + ONE glow UIShadow, both registered with the Capabilities
-- budget via UIChrome and DISABLED (never destroyed) on release. Worst case
-- on a 10-pull this screen registers 22 UIShadow instances (10 card shadows +
-- 10 card glows + ticket shadow + dial glow) with at most 20 ENABLED at once
-- (summary grid of ten all-rare/giga cards); the prelude pair is disabled
-- before the first card enables. Handles Release only at teardown.
--
-- Caps honoured: shake ≤ 6 px decaying under 0.4 s; the slash-line flash is
-- a single flash and the giga glow breathes at ceremony.pulseHz (≤ 3/s).

local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local Tags = require(script.Parent.Parent.StyleKit.Tags)
local StateDriver = require(script.Parent.Parent.StyleKit.StateDriver)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIScreenBase = require(script.Parent.UIScreenBase)

export type DrawResult = {
	name: string,
	rarity: string, -- "common" | "rare" | "giga" (anything else clamps to common)
	icon: string?, -- IconArchive semantic role
}

export type DrawCeremonyData = {
	results: { DrawResult },
	onClose: (() -> ())?,
}

type Beat = { at: number, fn: () -> (), fired: boolean }

type Card = {
	root: Frame, -- fixed grid footprint (never rotates, never scales)
	art: Frame, -- the visual: rotation/scale/flip land HERE (tags live here)
	scale: UIScale,
	iconSlot: Frame,
	icon: GuiObject?,
	nameLabel: TextLabel,
	strip: Frame,
	stripLabel: TextLabel,
	shadowHandle: any, -- Capabilities.ShadowHandle (sticker shadow)
	glow: UIShadow,
	glowHandle: any, -- Capabilities.ShadowHandle (rarity glow)
	glowBase: number, -- resting transparency the giga breath oscillates from
	revealed: boolean,
	pulsing: boolean,
}

-- Layout px at the 1650×1020 authoring baseline (structure, not style).
local CARD_W, CARD_H = 210, 280
local GRID_PAD = 18
local GRID_COLS = 5

-- Choreography fallbacks for packs without a DialectTokens.ceremony
-- namespace (GL overrides every one of these from the theme file).
local FALLBACK: { [string]: number } = {
	slamFromScale = 2.4,
	insertTime = 0.6,
	spinUpTime = 1.05,
	spinMaxDegPerSec = 1080,
	slashDeg = 12,
	slashCloseTime = 0.22,
	slashHoldTime = 0.12,
	slashOpenTime = 0.28,
	revealBeat = 0.55,
	quickBeat = 0.3,
	batchBeat = 0.45,
	cutInSmallTime = 0.5,
	cutInGigaTime = 0.85,
	slamShakePx = 6,
	slamShakeDecay = 0.35,
	pulseHz = 1.2,
	pulseDepth = 0.25,
	batchThreshold = 6,
}

local RARITY_RANK: { [string]: number } = { common = 1, rare = 2, giga = 3 }

local DrawCeremonyScreen = setmetatable({}, { __index = UIScreenBase })
DrawCeremonyScreen.__index = DrawCeremonyScreen

-- ------------------------------------------------------------------------
-- Token helpers — every visual value flows from the ACTIVE theme; the GL
-- numbers live in GurrenLagannTheme.DialectTokens.ceremony (additive).
-- ------------------------------------------------------------------------

local function ceremonyNamespace(theme: Types.UITheme): { [string]: any }?
	local dialects = theme.DialectTokens
	return dialects and dialects.ceremony
end

local function num(theme: Types.UITheme, key: string): number
	local ns = ceremonyNamespace(theme)
	local v = ns and ns[key]
	return if type(v) == "number" then v else FALLBACK[key]
end

local function comicSlantDeg(theme: Types.UITheme): number
	local dialects = theme.DialectTokens
	local comic = dialects and dialects.comic
	local v = comic and comic.slantDeg
	return if type(v) == "number" then v else 0
end

local function rarityRank(rarity: string?): number
	return RARITY_RANK[rarity or ""] or 1
end

local function rarityAccent(theme: Types.UITheme, rarity: string?): Color3
	local ns = ceremonyNamespace(theme)
	local rank = rarityRank(rarity)
	if rank >= 3 then
		local c = ns and ns.rarityGiga
		return if typeof(c) == "Color3" then c else theme.Colors.Primary
	elseif rank == 2 then
		local c = ns and ns.rarityRare
		return if typeof(c) == "Color3" then c else theme.Arcade.Gold
	end
	local c = ns and ns.rarityCommon
	return if typeof(c) == "Color3" then c else theme.Studio.Tan
end

-- Optional sibling components (built by parallel Life Pass work). Resolved at
-- runtime so this module loads cleanly whether or not they exist yet.
local function optionalComponentClass(name: string): any
	local components = script.Parent.Parent:FindFirstChild("Components")
	local module = components and components:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, class = pcall(require :: any, module)
		if ok and type(class) == "table" and type((class :: any).new) == "function" then
			return class
		end
	end
	return nil
end

-- CONTINUE prefers GLAngularButtonComponent (same UIComponentBase contract);
-- any construction hiccup falls back to the stock arcade button.
local function makeButton(parent: Instance, props: { [string]: any }): any
	local angular = optionalComponentClass("GLAngularButtonComponent")
	if angular then
		local ok, button = pcall(function()
			local b = (angular :: any).new()
			b:Create(nil, props)
			return b
		end)
		if ok and button and (button :: any).Root then
			(button :: any).Root.Parent = parent
			return button
		end
	end
	local b = UIButtonComponent.new()
	b:Create(parent, props)
	return b
end

-- ------------------------------------------------------------------------
-- Construction
-- ------------------------------------------------------------------------

function DrawCeremonyScreen.new()
	local self = UIScreenBase.new("DrawCeremonyScreen", 63)
	self._results = {} :: { DrawResult }
	self._onClose = nil :: (() -> ())?
	self._stage = "idle"
	self._stageClock = 0
	self._stageDuration = 0
	self._beats = {} :: { Beat }
	self._tweens = {} :: { Tween }
	self._cards = {} :: { Card }
	self._cardPool = {} :: { Card }
	self._inputConn = nil :: RBXScriptConnection?
	self._stopTicker = nil :: (() -> ())?
	self._closing = false
	-- shake state (Luau/ticker side; caps enforced by the ceremony tokens)
	self._shakeTarget = nil :: GuiObject?
	self._shakeBase = UDim2.new()
	self._shakeAmp = 0
	self._shakeAge = 0
	self._shakeDecay = 0.35
	-- dial state
	self._dialSpeed = 0
	self._rng = Random.new()
	return setmetatable(self, DrawCeremonyScreen)
end

function DrawCeremonyScreen:_BuildContent()
	local theme = self:GetTheme()
	local slant = comicSlantDeg(theme)
	-- The Comic DIALECT tag keys on the pack actually declaring the comic
	-- namespace — ceremony tokens alone must not opt a pack into comic rules.
	local comicPack = (theme.DialectTokens and theme.DialectTokens.comic) ~= nil

	-- Fresh build (first show OR style rebuild after _ResetShell): every pool
	-- and handle from a previous shell was released in _OnTeardown.
	self._cards = {}
	self._cardPool = {}
	self._closing = false
	self._comicPack = comicPack

	-- ---- layers (sibling ZIndex bands under Root) ----------------------
	local dim = UIStyler.Frame("Dim")
	dim.BackgroundColor3 = theme.Colors.Overlay
	dim.BackgroundTransparency = 0.4
	dim.ZIndex = 60
	dim.Parent = self.Root
	self._dim = dim

	-- Cards + summary chrome live BELOW the slash panels so the wipe covers
	-- and then reveals them.
	local cardLayer = UIStyler.Frame("CardLayer")
	cardLayer.BackgroundTransparency = 1
	cardLayer.ZIndex = 61
	cardLayer.Parent = self.Root
	self._cardLayer = cardLayer

	-- Prelude (ticket + dial) sits above the cards, below the slash.
	local prelude = UIStyler.Frame("Prelude")
	prelude.BackgroundTransparency = 1
	prelude.ZIndex = 63
	prelude.Visible = false
	prelude.Parent = self.Root
	self._prelude = prelude

	-- The rotated-clipped container: slash panels + cut-in bands are rotated
	-- children of THIS full-screen clipper, so their oversized slanted bodies
	-- never spill outside the viewport (the no-skew technique).
	local clipper = UIStyler.Frame("SlashClipper")
	clipper.BackgroundTransparency = 1
	clipper.ClipsDescendants = true
	clipper.ZIndex = 65
	clipper.Parent = self.Root
	self._clipper = clipper

	-- ---- prelude: drill ticket -----------------------------------------
	local ticket = UIStyler.Frame("DrillTicket")
	ticket.BackgroundColor3 = theme.Studio.Card
	ticket.AnchorPoint = Vector2.new(0.5, 0.5)
	ticket.Position = UDim2.fromScale(0.5, 0.45)
	ticket.Size = UDim2.fromOffset(340, 120)
	-- Whole-element Rotation sells the comic slant (no skew exists).
	ticket.Rotation = slant
	UIChrome.Stroke(theme, "Arcade").Parent = ticket
	ticket.Visible = false
	ticket.Parent = prelude
	self._ticket = ticket
	self._ticketBasePos = ticket.Position
	StateDriver.Structural(ticket, Tags.Structural.Chip)
	if comicPack then
		StateDriver.SetDialect(ticket, Tags.Dialect.Comic)
	end

	local ticketScale = Instance.new("UIScale")
	ticketScale.Parent = ticket
	self._ticketScale = ticketScale

	-- "sm" matches the GL sheet's .UIChip.DialectComic::UIShadow recipe, so
	-- the styling and imperative expressions stay ONE look (bridge parity).
	local _, ticketShadowHandle = UIChrome.Shadow(theme, "sm", ticket)
	ticketShadowHandle:SetEnabled(false) -- enabled on slam impact
	self._ticketShadowHandle = ticketShadowHandle

	local ticketAccent = UIStyler.Frame("HeatBar")
	ticketAccent.BackgroundColor3 = theme.Colors.Primary
	ticketAccent.Size = UDim2.new(1, 0, 0, 14)
	ticketAccent.ZIndex = 2
	ticketAccent.Parent = ticket

	local ticketLabel = UIChrome.Text("Label", 44, theme.Studio.TextDark)
	ticketLabel.Text = "DRILL TICKET"
	ticketLabel.Position = UDim2.new(0, 0, 0, 14)
	ticketLabel.Size = UDim2.new(1, 0, 1, -14)
	ticketLabel.ZIndex = 2
	ticketLabel.Parent = ticket

	-- ---- prelude: spin-up dial -----------------------------------------
	local dial = UIStyler.Frame("Dial")
	dial.BackgroundColor3 = theme.Arcade.NearBlack
	dial.AnchorPoint = Vector2.new(0.5, 0.5)
	dial.Position = UDim2.fromScale(0.5, 0.45)
	dial.Size = UDim2.fromOffset(240, 240)
	UIChrome.Corner("Arcade", "Pill").Parent = dial
	UIChrome.Stroke(theme, "Arcade").Parent = dial
	dial.Visible = false
	dial.Parent = prelude
	self._dial = dial

	local dialScale = Instance.new("UIScale")
	dialScale.Parent = dial
	self._dialScale = dialScale

	local dialGlow, dialGlowHandle = UIChrome.Glow(theme, "md", dial)
	dialGlowHandle:SetEnabled(false) -- ramps in during spin-up
	self._dialGlow = dialGlow
	self._dialGlowHandle = dialGlowHandle
	-- The anticipation ramp lands on the theme glow's own resting value.
	self._dialGlowRest = dialGlow.Transparency

	-- Pointer pivot: the ticker rotates this ART child; the dial itself
	-- (and the layout) never moves.
	local pivot = UIStyler.Frame("PointerPivot")
	pivot.BackgroundTransparency = 1
	pivot.AnchorPoint = Vector2.new(0.5, 0.5)
	pivot.Position = UDim2.fromScale(0.5, 0.5)
	pivot.Size = UDim2.fromScale(1, 1)
	pivot.ZIndex = 2
	pivot.Parent = dial
	self._dialPivot = pivot

	local pointer = UIStyler.Frame("Pointer")
	pointer.BackgroundColor3 = theme.Colors.Primary
	pointer.AnchorPoint = Vector2.new(0.5, 1)
	pointer.Position = UDim2.fromScale(0.5, 0.5)
	pointer.Size = UDim2.fromOffset(10, 96)
	pointer.Parent = pivot

	local hub = UIStyler.Frame("Hub")
	hub.BackgroundColor3 = theme.Studio.Card
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(28, 28)
	hub.ZIndex = 3
	UIChrome.Corner("Arcade", "Pill").Parent = hub
	UIChrome.Stroke(theme, "Arcade").Parent = hub
	hub.Parent = dial

	-- ---- slash-wipe panels (rotated-clipped frames) --------------------
	-- Oversized so the rotated body covers its half of the screen with no
	-- exposed corner at any point of the sweep.
	local function slashPanel(name: string): Frame
		local panel = UIStyler.Frame(name)
		panel.BackgroundColor3 = theme.Arcade.NearBlack2
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Size = UDim2.fromOffset(2600, 1700)
		panel.Rotation = num(theme, "slashDeg")
		UIChrome.Stroke(theme, "Arcade").Parent = panel
		panel.Visible = false
		panel.Parent = clipper
		return panel
	end
	self._slashLeft = slashPanel("SlashLeft")
	self._slashRight = slashPanel("SlashRight")

	-- The slash line: one heat-colored slanted strip flashed ONCE at the
	-- moment the panels meet (single flash — well under the 3/s cap).
	local slashLine = UIStyler.Frame("SlashLine")
	slashLine.BackgroundColor3 = theme.Colors.Primary
	slashLine.AnchorPoint = Vector2.new(0.5, 0.5)
	slashLine.Position = UDim2.fromScale(0.5, 0.5)
	slashLine.Size = UDim2.fromOffset(12, 2200)
	slashLine.Rotation = num(theme, "slashDeg")
	slashLine.ZIndex = 4
	slashLine.Visible = false
	slashLine.Parent = clipper
	self._slashLine = slashLine

	-- ---- cut-in band (pooled: ONE band, re-dressed per use) ------------
	local band = UIStyler.Frame("CutInBand")
	band.BackgroundColor3 = theme.Arcade.Gold
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Size = UDim2.fromOffset(1900, 140)
	band.Rotation = slant -- rotated strip inside the clipper (no skew)
	UIChrome.Stroke(theme, "Arcade").Parent = band
	band.ZIndex = 6
	band.Visible = false
	band.Parent = clipper
	self._band = band

	local bandLabel = UIChrome.Text("BandLabel", 64, theme.Colors.TextOnPrimary)
	bandLabel.Size = UDim2.fromScale(1, 1)
	bandLabel.ZIndex = 7
	bandLabel.Parent = band
	self._bandLabel = bandLabel

	-- ---- summary grid + CONTINUE ---------------------------------------
	local gridHolder = UIStyler.Frame("Grid")
	gridHolder.BackgroundTransparency = 1
	gridHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	gridHolder.Position = UDim2.fromScale(0.5, 0.46)
	gridHolder.Size = UDim2.fromOffset(CARD_W, CARD_H)
	UIStyler.GridLayout(UDim2.fromOffset(CARD_W, CARD_H), UDim2.fromOffset(GRID_PAD, GRID_PAD)).Parent = gridHolder
	gridHolder.Parent = cardLayer
	self._gridHolder = gridHolder

	self._continue = makeButton(cardLayer, {
		text = "CONTINUE",
		variant = "Gold",
		size = UDim2.fromOffset(260, 64),
		position = UDim2.new(0.5, 0, 1, -60),
		anchorPoint = Vector2.new(0.5, 1),
		onClick = function()
			self:_Close()
		end,
	})
	self._continue.Root.Visible = false

	-- ---- input: full-screen skip catcher + SKIP ALL --------------------
	-- The catcher renders above the slash clipper; SKIP ALL sits above the
	-- catcher (sibling ZIndex) so it stays clickable. In summary the catcher
	-- hides entirely, which is what lets CONTINUE receive clicks.
	local catcher = Instance.new("TextButton")
	catcher.Name = "SkipCatcher"
	catcher.Text = ""
	catcher.BackgroundTransparency = 1
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.ZIndex = 71
	catcher.Visible = false
	catcher.Parent = self.Root
	catcher.Activated:Connect(function()
		self:_Advance()
	end)
	self._catcher = catcher

	self._skip = makeButton(self.Root, {
		text = "SKIP >>",
		variant = "Ghost",
		size = UDim2.fromOffset(150, 44),
		position = UDim2.new(1, -24, 0, 24),
		anchorPoint = Vector2.new(1, 0),
		onClick = function()
			self:_JumpToSummary()
		end,
	})
	self._skip.Root.ZIndex = 72

	-- THE one UITicker registration for this module: stage clock + beats,
	-- dial spin, shake decay, giga glow breath. Bound to the Gui so a style
	-- rebuild (which destroys the shell) unregisters it automatically.
	self._stopTicker = UITicker.Register(function(dt: number, now: number)
		self:_Step(dt, now)
	end, self.Gui)
end

-- ------------------------------------------------------------------------
-- Result cards (pooled)
-- ------------------------------------------------------------------------

function DrawCeremonyScreen:_AcquireCard(): Card
	local pooled: Card? = table.remove(self._cardPool)
	if pooled then
		return pooled
	end
	local theme = self:GetTheme()

	local root = UIStyler.Frame("CardCell")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(CARD_W, CARD_H)

	-- ART child: rotation, scale and the flip all land here so the grid
	-- footprint never reflows (the no-skew / no-reflow rule).
	local art = UIStyler.Frame("CardArt")
	art.BackgroundColor3 = theme.Studio.Card
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.Size = UDim2.fromScale(1, 1)
	art.Visible = false
	UIChrome.Stroke(theme, "Arcade").Parent = art
	art.Parent = root
	StateDriver.Structural(art, Tags.Structural.Chip)
	if self._comicPack then
		StateDriver.SetDialect(art, Tags.Dialect.Comic)
	end

	local scale = Instance.new("UIScale")
	scale.Parent = art

	local _, shadowHandle = UIChrome.Shadow(theme, "sm", art)
	shadowHandle:SetEnabled(false)

	local glow, glowHandle = UIChrome.Glow(theme, "md", art)
	glowHandle:SetEnabled(false)

	local iconSlot = UIStyler.Frame("IconSlot")
	iconSlot.BackgroundTransparency = 1
	iconSlot.AnchorPoint = Vector2.new(0.5, 0)
	iconSlot.Position = UDim2.new(0.5, 0, 0, 22)
	iconSlot.Size = UDim2.fromOffset(120, 120)
	iconSlot.ZIndex = 2
	iconSlot.Parent = art

	local nameLabel = UIChrome.Text("Name", 20, theme.Studio.TextDark)
	nameLabel.TextWrapped = true
	nameLabel.Position = UDim2.new(0, 10, 0, 150)
	nameLabel.Size = UDim2.new(1, -20, 0, 84)
	nameLabel.ZIndex = 2
	nameLabel.Parent = art

	local strip = UIStyler.Frame("RarityStrip")
	strip.BackgroundColor3 = theme.Arcade.Gold
	strip.AnchorPoint = Vector2.new(0, 1)
	strip.Position = UDim2.fromScale(0, 1)
	strip.Size = UDim2.new(1, 0, 0, 38)
	strip.ZIndex = 2
	strip.Parent = art

	local stripLabel = UIChrome.Text("Rarity", 22, theme.Colors.TextOnPrimary)
	stripLabel.Size = UDim2.fromScale(1, 1)
	stripLabel.ZIndex = 3
	stripLabel.Parent = strip

	return {
		root = root,
		art = art,
		scale = scale,
		iconSlot = iconSlot,
		icon = nil,
		nameLabel = nameLabel,
		strip = strip,
		stripLabel = stripLabel,
		shadowHandle = shadowHandle,
		glow = glow,
		glowHandle = glowHandle,
		glowBase = glow.Transparency,
		revealed = false,
		pulsing = false,
	}
end

-- Release every active card back to the pool: glows/shadows DISABLE (budget
-- slots kept, zero render cost), modifier tags clear through StateDriver.
function DrawCeremonyScreen:_ReleaseCards()
	for _, card in self._cards :: { Card } do
		card.shadowHandle:SetEnabled(false)
		card.glowHandle:SetEnabled(false)
		card.pulsing = false
		card.revealed = false
		StateDriver.Set(card.art, Tags.Modifier.Featured, false)
		StateDriver.Set(card.art, Tags.Modifier.Maxed, false)
		card.art.Visible = false
		if card.icon then
			card.icon:Destroy()
			card.icon = nil
		end
		card.root.Parent = nil
		table.insert(self._cardPool, card)
	end
	table.clear(self._cards)
end

function DrawCeremonyScreen:_BuildGrid()
	local theme = self:GetTheme()
	local slant = comicSlantDeg(theme)
	self:_ReleaseCards()

	local n = #self._results
	local cols = math.max(1, math.min(n, GRID_COLS))
	local rows = math.max(1, math.ceil(n / cols))
	self._gridHolder.Size = UDim2.fromOffset(
		cols * CARD_W + (cols - 1) * GRID_PAD,
		rows * CARD_H + (rows - 1) * GRID_PAD
	)

	for i, result in self._results :: { DrawResult } do
		local card = self:_AcquireCard()
		local accent = rarityAccent(theme, result.rarity)
		card.root.LayoutOrder = i
		-- Alternating sticker tilt (whole-element Rotation on the ART child).
		card.art.Rotation = if i % 2 == 0 then -slant else slant
		card.art.Size = UDim2.fromScale(1, 1)
		card.art.Visible = false
		card.scale.Scale = 1
		card.nameLabel.Text = result.name
		card.strip.BackgroundColor3 = accent
		card.stripLabel.Text = string.upper(result.rarity)
		local icon = IconArchive.Image(card.iconSlot, result.icon or "chest", 120, { golden = rarityRank(result.rarity) >= 3 })
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = 3
		card.icon = icon
		card.root.Parent = self._gridHolder
		table.insert(self._cards, card)
	end
end

-- Retarget a pooled glow at a theme glow intent without recreating it.
function DrawCeremonyScreen:_ApplyGlowIntent(card: Card, intent: string)
	local theme = self:GetTheme()
	local glows = theme.EffectGlows
	local def = glows and (glows :: any)[intent]
	if not def then
		return
	end
	local color = def.Color
	if def.ColorToken then
		color = (theme.Colors :: any)[def.ColorToken] or color
	end
	local glow = card.glow
	glow.BlurRadius = def.Blur
	glow.Offset = def.Offset
	glow.Spread = def.Spread
	glow.Color = color or theme.Arcade.Gold
	glow.Transparency = def.Transparency
	card.glowBase = def.Transparency
end

-- mode: "pop" (common) | "quick" (lesser rare/giga on a batch pull) |
--       "flip" (full ceremony) | "instant" (skip / reduce-motion final state)
function DrawCeremonyScreen:_RevealCard(index: number, mode: string)
	local card: Card? = (self._cards :: { Card })[index]
	local result: DrawResult? = (self._results :: { DrawResult })[index]
	if not card or not result or card.revealed then
		return
	end
	local theme = self:GetTheme()
	local rank = rarityRank(result.rarity)
	card.revealed = true
	card.art.Visible = true
	card.shadowHandle:SetEnabled(true)

	-- Styling side: rarity STATE rides modifier tags through StateDriver —
	-- .UIChip.UIFeatured::UIShadow (gold glow) is authored in the GL sheet,
	-- inert until the engine applies styling.
	if rank >= 2 then
		StateDriver.Set(card.art, Tags.Modifier.Featured, true)
	end
	if rank >= 3 then
		StateDriver.Set(card.art, Tags.Modifier.Maxed, true)
	end
	-- Imperative bridge-era fallback: the SAME look from the pooled glow
	-- handle (md for rare, lg for giga), enabled — never recreated.
	if rank >= 2 then
		self:_ApplyGlowIntent(card, if rank >= 3 then "lg" else "md")
		card.glowHandle:SetEnabled(true)
	end
	card.pulsing = rank >= 3 -- the ticker breathes this glow (Luau side)

	if mode == "instant" then
		card.scale.Scale = 1
		card.art.Size = UDim2.fromScale(1, 1)
		return
	end
	if mode == "flip" then
		-- Fake flip (no 3D transforms in Roblox): X-squash on the ART child
		-- reads as a card turning face-up; the grid cell never moves.
		card.art.Size = UDim2.fromScale(0.06, 1)
		card.scale.Scale = 1
		table.insert(self._tweens, UIStyler.Tween(card.art, theme.Motion.PopIn, { Size = UDim2.fromScale(1, 1) }))
	elseif mode == "quick" then
		card.art.Size = UDim2.fromScale(1, 1)
		card.scale.Scale = 0.8
		table.insert(self._tweens, UIStyler.Tween(card.scale, theme.Motion.PulseSettle, { Scale = 1 }))
	else -- "pop"
		card.art.Size = UDim2.fromScale(1, 1)
		card.scale.Scale = theme.Motion.PopFromScale
		table.insert(self._tweens, UIStyler.Tween(card.scale, theme.Motion.PopIn, { Scale = 1 }))
	end
end

-- ------------------------------------------------------------------------
-- Cut-in band. One pooled band, re-dressed per use; the real GLCutIn module
-- can replace this single function body once its API lands.
-- ------------------------------------------------------------------------

function DrawCeremonyScreen:_PlayCutIn(tier: string, result: DrawResult)
	local theme = self:GetTheme()
	local giga = tier == "giga"
	local band = self._band :: Frame
	local accent = rarityAccent(theme, result.rarity)
	band.BackgroundColor3 = accent
	band.Size = UDim2.fromOffset(1900, if giga then 170 else 100)
	self._bandLabel.TextSize = if giga then 72 else 44
	self._bandLabel.Text = if giga then "G I G A !!" else "RARE!"
	band.Position = UDim2.fromScale(-0.8, 0.42)
	band.Visible = true
	local duration = num(theme, if giga then "cutInGigaTime" else "cutInSmallTime")
	table.insert(self._tweens, UIStyler.Tween(
		band,
		TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut),
		{ Position = UDim2.fromScale(1.8, 0.42) }
	))
end

-- ------------------------------------------------------------------------
-- Stage machine. Natural progression comes from the ticker clock; a skip
-- enters the next stage with `instant = true` so the previous stage's
-- leftovers resolve to their final states with no animation.
-- ------------------------------------------------------------------------

function DrawCeremonyScreen:_CancelTweens()
	for _, tween in self._tweens :: { Tween } do
		tween:Cancel()
	end
	table.clear(self._tweens)
end

function DrawCeremonyScreen:_Beat(at: number, fn: () -> ())
	table.insert(self._beats, { at = at, fn = fn, fired = false })
end

function DrawCeremonyScreen:_EnterStage(stage: string, instant: boolean)
	self:_CancelTweens()
	table.clear(self._beats)
	self._stageClock = 0
	-- A skip mid-shake must not freeze the target off its base position.
	local shakeTarget = self._shakeTarget :: GuiObject?
	if shakeTarget and self._shakeAmp > 0 then
		shakeTarget.Position = self._shakeBase
	end
	self._shakeAmp = 0
	self._stage = stage
	if stage == "insert" then
		self:_EnterInsert()
	elseif stage == "spinup" then
		self:_EnterSpinup(instant)
	elseif stage == "slash" then
		self:_EnterSlash()
	elseif stage == "reveals" then
		self:_EnterReveals(instant)
	elseif stage == "summary" then
		self:_EnterSummary()
	end
end

function DrawCeremonyScreen:_EnterInsert()
	local theme = self:GetTheme()
	-- Defensive reset: a re-entrant Show/Update can arrive mid-slash or
	-- mid-cut-in (its tweens were cancelled, which freezes properties), so
	-- every transient layer is squared away before the ceremony restarts.
	self._slashLeft.Visible = false
	self._slashRight.Visible = false
	self._slashLine.Visible = false
	self._band.Visible = false
	self._dialGlowHandle:SetEnabled(false)
	self._prelude.Visible = true
	self._dial.Visible = false
	local ticket = self._ticket :: Frame
	ticket.Position = self._ticketBasePos
	ticket.Visible = true
	local scale = self._ticketScale :: UIScale
	scale.Scale = num(theme, "slamFromScale")
	table.insert(self._tweens, UIStyler.Tween(scale, theme.Motion.PopIn, { Scale = 1 }))
	-- Impact: shadow lands + capped shake (≤6 px, decays under 0.4 s).
	self:_Beat(0.14, function()
		self._ticketShadowHandle:SetEnabled(true)
		self._shakeTarget = ticket
		self._shakeBase = self._ticketBasePos
		self._shakeAmp = math.min(num(theme, "slamShakePx"), 6)
		self._shakeDecay = math.min(num(theme, "slamShakeDecay"), 0.4)
		self._shakeAge = 0
		self:_PlaySound("Open")
	end)
	self._stageDuration = num(theme, "insertTime")
end

function DrawCeremonyScreen:_EnterSpinup(instant: boolean)
	local theme = self:GetTheme()
	self._prelude.Visible = true
	local ticket = self._ticket :: Frame
	local ticketScale = self._ticketScale :: UIScale
	if instant then
		ticket.Visible = false
		self._ticketShadowHandle:SetEnabled(false)
	else
		-- The ticket gets sucked into the dial.
		table.insert(self._tweens, UIStyler.Tween(ticketScale, theme.Animations.Disappear, { Scale = 0.1 }))
		self:_Beat(0.12, function()
			ticket.Visible = false
			ticketScale.Scale = 1
			self._ticketShadowHandle:SetEnabled(false)
		end)
	end
	local dial = self._dial :: Frame
	dial.Visible = true
	local dialScale = self._dialScale :: UIScale
	dialScale.Scale = theme.Motion.PopFromScale
	table.insert(self._tweens, UIStyler.Tween(dialScale, theme.Motion.PopIn, { Scale = 1 }))
	self._dialSpeed = 0
	self._dialGlow.Transparency = 0.9 -- from nearly invisible...
	self._dialGlowHandle:SetEnabled(true)
	self._stageDuration = num(theme, "spinUpTime")
end

function DrawCeremonyScreen:_EnterSlash()
	local theme = self:GetTheme()
	-- Prelude resolves instantly regardless of how we got here.
	self._prelude.Visible = false
	self._ticket.Visible = false
	self._ticketShadowHandle:SetEnabled(false)
	self._dial.Visible = false
	self._dialGlowHandle:SetEnabled(false)

	local closeTime = num(theme, "slashCloseTime")
	local holdTime = num(theme, "slashHoldTime")
	local left = self._slashLeft :: Frame
	local right = self._slashRight :: Frame
	left.Position = UDim2.fromScale(-0.85, 0.5)
	right.Position = UDim2.fromScale(1.85, 0.5)
	left.Visible = true
	right.Visible = true
	local closeInfo = TweenInfo.new(closeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	table.insert(self._tweens, UIStyler.Tween(left, closeInfo, { Position = UDim2.fromScale(0.18, 0.5) }))
	table.insert(self._tweens, UIStyler.Tween(right, closeInfo, { Position = UDim2.fromScale(0.82, 0.5) }))
	-- The meet: ONE slash-line flash along the slanted seam.
	self:_Beat(closeTime, function()
		local line = self._slashLine :: Frame
		line.BackgroundTransparency = 0
		line.Visible = true
		table.insert(self._tweens, UIStyler.Tween(
			line,
			TweenInfo.new(closeTime + holdTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		))
	end)
	self._stageDuration = closeTime + holdTime
end

function DrawCeremonyScreen:_EnterReveals(instant: boolean)
	local theme = self:GetTheme()
	local left = self._slashLeft :: Frame
	local right = self._slashRight :: Frame
	local line = self._slashLine :: Frame
	if instant then
		left.Visible = false
		right.Visible = false
		line.Visible = false
	else
		-- The wipe opens onto the (still face-down) grid.
		local openTime = num(theme, "slashOpenTime")
		local openInfo = TweenInfo.new(openTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		table.insert(self._tweens, UIStyler.Tween(left, openInfo, { Position = UDim2.fromScale(-0.85, 0.5) }))
		table.insert(self._tweens, UIStyler.Tween(right, openInfo, { Position = UDim2.fromScale(1.85, 0.5) }))
		self:_Beat(openTime, function()
			left.Visible = false
			right.Visible = false
			line.Visible = false
		end)
	end
	self._stageDuration = self:_PlanReveals()
end

-- Schedule the reveal beats; returns the stage duration. Escalation:
-- common = pop; rare = flip + gold glow + small cut-in; giga = giga cut-in
-- FIRST, then the card with lg glow (+ the ticker's breathing pulse). At or
-- over the batch threshold, commons share ONE beat and lesser rare/giga get
-- quick pops — only the best pull gets the full ceremony, last.
function DrawCeremonyScreen:_PlanReveals(): number
	local theme = self:GetTheme()
	local results = self._results :: { DrawResult }
	local n = #results
	if n == 0 then
		return 0.1
	end
	local t = 0.15 -- let the wipe start opening first

	local bestIndex = 1
	for i, result in results do
		if rarityRank(result.rarity) > rarityRank(results[bestIndex].rarity) then
			bestIndex = i
		end
	end

	if n >= num(theme, "batchThreshold") then
		-- Batch grid: every common lands on the same beat.
		local commons: { number } = {}
		for i, result in results do
			if i ~= bestIndex and rarityRank(result.rarity) <= 1 then
				table.insert(commons, i)
			end
		end
		if #commons > 0 then
			self:_Beat(t, function()
				for _, index in commons do
					self:_RevealCard(index, "pop")
				end
			end)
			t += num(theme, "batchBeat")
		end
		-- Lesser rare/giga: quick pops with their glow, no cut-in.
		for i, result in results do
			if i ~= bestIndex and rarityRank(result.rarity) >= 2 then
				local index = i
				self:_Beat(t, function()
					self:_RevealCard(index, "quick")
				end)
				t += num(theme, "quickBeat")
			end
		end
		t = self:_PlanFullReveal(bestIndex, t)
	else
		-- Small pulls: every item gets its rarity's full escalation, in the
		-- server-confirmed order.
		for i in results do
			t = self:_PlanFullReveal(i, t)
		end
	end
	return t + 0.35
end

function DrawCeremonyScreen:_PlanFullReveal(index: number, t: number): number
	local theme = self:GetTheme()
	local result = (self._results :: { DrawResult })[index]
	local rank = rarityRank(result.rarity)
	if rank >= 3 then
		self:_Beat(t, function()
			self:_PlayCutIn("giga", result)
		end)
		t += num(theme, "cutInGigaTime") * 0.7
		self:_Beat(t, function()
			self:_RevealCard(index, "flip")
			self:_PlaySound("Success")
		end)
		t += num(theme, "revealBeat") + 0.15
	elseif rank == 2 then
		self:_Beat(t, function()
			self:_PlayCutIn("small", result)
			self:_RevealCard(index, "flip")
			self:_PlaySound("Success")
		end)
		t += num(theme, "revealBeat")
	else
		self:_Beat(t, function()
			self:_RevealCard(index, "pop")
		end)
		t += num(theme, "revealBeat") * 0.7
	end
	return t
end

function DrawCeremonyScreen:_EnterSummary()
	-- Final confirmed state, unconditionally: every card face-up, all
	-- transient chrome gone. This is also the reduce-motion landing.
	self._prelude.Visible = false
	self._ticket.Visible = false
	self._ticketShadowHandle:SetEnabled(false)
	self._dial.Visible = false
	self._dialGlowHandle:SetEnabled(false)
	self._slashLeft.Visible = false
	self._slashRight.Visible = false
	self._slashLine.Visible = false
	self._band.Visible = false
	for i in self._results :: { DrawResult } do
		self:_RevealCard(i, "instant")
	end
	self._catcher.Visible = false
	self._skip.Root.Visible = false
	local continueButton = self._continue
	continueButton.Root.Visible = true
	pcall(function()
		continueButton:PlayAnimation("Appear")
	end)
	self._stageDuration = math.huge
end

-- ------------------------------------------------------------------------
-- The ticker step: beats, continuous motion, natural stage advancement.
-- ------------------------------------------------------------------------

function DrawCeremonyScreen:_Step(dt: number, now: number)
	if not self._visible or self._stage == "idle" then
		return
	end
	local theme = self:GetTheme()
	local stageAtEntry = self._stage
	self._stageClock += dt
	local clock = self._stageClock

	for _, beat in self._beats :: { Beat } do
		if not beat.fired and clock >= beat.at then
			beat.fired = true
			beat.fn()
		end
	end

	-- Slam shake: capped amplitude, linear decay, restores the base position.
	local shakeTarget = self._shakeTarget
	if self._shakeAmp > 0 and shakeTarget then
		self._shakeAge += dt
		local life = 1 - self._shakeAge / self._shakeDecay
		if life <= 0 then
			self._shakeAmp = 0
			shakeTarget.Position = self._shakeBase
		else
			local amp = self._shakeAmp * life
			shakeTarget.Position = self._shakeBase + UDim2.fromOffset(
				math.round(self._rng:NextNumber(-amp, amp)),
				math.round(self._rng:NextNumber(-amp, amp))
			)
		end
	end

	-- Spin-up: pointer accelerates toward terminal velocity while the
	-- anticipation glow tightens (both continuous → Luau ticker side).
	if self._stage == "spinup" then
		local maxSpeed = num(theme, "spinMaxDegPerSec")
		local duration = num(theme, "spinUpTime")
		self._dialSpeed = math.min(maxSpeed, self._dialSpeed + maxSpeed * dt / math.max(duration * 0.8, 0.05))
		local pivot = self._dialPivot :: Frame
		pivot.Rotation = (pivot.Rotation + self._dialSpeed * dt) % 360
		local glow = self._dialGlow :: UIShadow
		local from = 0.9
		local target = self._dialGlowRest :: number
		glow.Transparency = from + (target - from) * math.clamp(clock / duration, 0, 1)
	end

	-- Giga breath: glow transparency oscillates around its resting value at
	-- pulseHz (≤ 3 flashes/s cap), only on visible pulsing cards.
	local pulseDepth = num(theme, "pulseDepth")
	local omega = num(theme, "pulseHz") * 2 * math.pi
	for _, card in self._cards :: { Card } do
		if card.pulsing and card.art.Visible then
			card.glow.Transparency = math.clamp(
				card.glowBase + pulseDepth * (0.5 + 0.5 * math.sin(now * omega)),
				0,
				1
			)
		end
	end

	-- Natural stage advancement (a beat above may have already moved us on).
	if self._stage ~= stageAtEntry then
		return
	end
	if clock >= self._stageDuration then
		local stage = self._stage
		if stage == "insert" then
			self:_EnterStage("spinup", false)
		elseif stage == "spinup" then
			self:_EnterStage("slash", false)
		elseif stage == "slash" then
			self:_EnterStage("reveals", false)
		elseif stage == "reveals" then
			self:_EnterStage("summary", false)
		end
	end
end

-- ------------------------------------------------------------------------
-- Skipping / closing — input always answers instantly (rule 4).
-- ------------------------------------------------------------------------

function DrawCeremonyScreen:_Advance()
	local stage = self._stage
	if stage == "insert" then
		self:_EnterStage("spinup", true)
	elseif stage == "spinup" then
		self:_EnterStage("slash", true)
	elseif stage == "slash" then
		self:_EnterStage("reveals", true)
	elseif stage == "reveals" then
		self:_EnterStage("summary", true)
	elseif stage == "summary" then
		self:_Close()
	end
end

function DrawCeremonyScreen:_JumpToSummary()
	if self._stage ~= "summary" and self._stage ~= "idle" then
		self:_EnterStage("summary", true)
	end
end

function DrawCeremonyScreen:_Close()
	if self._closing then
		return
	end
	self._closing = true
	local onClose = self._onClose
	if onClose then
		task.spawn(onClose)
	end
	-- Prefer controller bookkeeping when the manifest id is wired (a no-op
	-- for unknown ids), then guarantee the hide either way.
	if self.ScreenController then
		pcall(function()
			self.ScreenController:HideScreen("drawCeremony")
		end)
	end
	if self._visible then
		self:Hide()
	end
end

-- ------------------------------------------------------------------------
-- Lifecycle
-- ------------------------------------------------------------------------

function DrawCeremonyScreen:_OnShow(data: any?)
	-- Sanitize: render ONLY what the server confirmed; clamp junk rarities.
	local results: { DrawResult } = {}
	if type(data) == "table" and type(data.results) == "table" then
		for _, entry in ipairs(data.results) do
			if type(entry) == "table" and type(entry.name) == "string" then
				local rarity = if RARITY_RANK[entry.rarity] then entry.rarity else "common"
				table.insert(results, {
					name = entry.name,
					rarity = rarity,
					icon = if type(entry.icon) == "string" then entry.icon else nil,
				})
			end
		end
	end
	self._results = results
	self._onClose = if type(data) == "table" and type(data.onClose) == "function" then data.onClose else nil
	self._closing = false

	self:_BuildGrid()
	self._catcher.Visible = true
	self._skip.Root.Visible = true
	self._continue.Root.Visible = false

	-- One InputBegan connection per show, dropped on hide (zero growth).
	if self._inputConn then
		self._inputConn:Disconnect()
	end
	self._inputConn = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not self._visible then
			return
		end
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.Keyboard then
			if input.KeyCode == Enum.KeyCode.Escape then
				self:_JumpToSummary()
			else
				self:_Advance()
			end
		elseif inputType == Enum.UserInputType.Gamepad1 then
			if input.KeyCode == Enum.KeyCode.ButtonB then
				self:_JumpToSummary()
			elseif input.KeyCode == Enum.KeyCode.ButtonA then
				self:_Advance()
			end
		end
	end)

	local reduceMotion = self.Gui:GetAttribute("ReduceMotion") == true
		or self.Root:GetAttribute("ReduceMotion") == true
	if reduceMotion or #results == 0 then
		-- Rule 4: sequenced choreography collapses to the instant final state.
		self:_EnterStage("summary", true)
	else
		self:_EnterStage("insert", false)
	end
end

function DrawCeremonyScreen:_OnHide()
	self:_CancelTweens()
	table.clear(self._beats)
	self._stage = "idle"
	self._shakeAmp = 0
	self._shakeTarget = nil
	if self._inputConn then
		self._inputConn:Disconnect()
		self._inputConn = nil
	end
	if self._ticketShadowHandle then
		self._ticketShadowHandle:SetEnabled(false)
	end
	if self._dialGlowHandle then
		self._dialGlowHandle:SetEnabled(false)
	end
	if self._band then
		self._band.Visible = false
	end
	if self._cards then
		self:_ReleaseCards()
	end
end

-- Style-rebuild / final teardown: pools cleared, every budget handle
-- Released (the counter drops), the one ticker handler stopped. The base
-- destroys the Gui right after this hook.
function DrawCeremonyScreen:_OnTeardown()
	if self._stopTicker then
		self._stopTicker()
		self._stopTicker = nil
	end
	if self._inputConn then
		self._inputConn:Disconnect()
		self._inputConn = nil
	end
	self:_CancelTweens()
	table.clear(self._beats)
	if self._cards then
		self:_ReleaseCards()
	end
	if self._cardPool then
		for _, card in self._cardPool :: { Card } do
			card.shadowHandle:Release()
			card.glowHandle:Release()
			card.root:Destroy()
		end
		table.clear(self._cardPool)
	end
	if self._ticketShadowHandle then
		self._ticketShadowHandle:Release()
		self._ticketShadowHandle = nil
	end
	if self._dialGlowHandle then
		self._dialGlowHandle:Release()
		self._dialGlowHandle = nil
	end
	if self._continue then
		pcall(function()
			self._continue:Destroy()
		end)
		self._continue = nil
	end
	if self._skip then
		pcall(function()
			self._skip:Destroy()
		end)
		self._skip = nil
	end
end

function DrawCeremonyScreen:Update(data: any)
	if self._built and self:IsVisible() then
		self:_OnShow(data)
	end
end

function DrawCeremonyScreen:Destroy()
	self:_OnHide()
	if self._built then
		self:_OnTeardown()
	end
	UIScreenBase.Destroy(self)
end

return DrawCeremonyScreen
