--!strict
-- GPScallopPanel — a surface with a scalloped doily lip on any subset of its
-- four sides, petal corners, a soft HUE-MATCHED shadow and an opt-in glaze
-- sheen. This is the pack's panel atom as a live, restylable COMPONENT (the
-- GPLayoutKit builders are static composition; a screen that wants a panel to
-- survive live theme swaps and carry its own teardown wants this instead).
--
-- Generic and theme-agnostic by construction. Every colour, radius, pattern,
-- transparency and stroke weight is a token read off the active theme, and each
-- decoration degrades on its own: no Assets.scallopEdge gives a soft rounded
-- lip in the same tint, no Corners table gives the uniform radius ladder, no
-- DialectTokens gives house fallbacks. Nothing pink is written down here.
--
-- THE 0.4 BOUNDARY: this component is ENTIRELY static composition on the Luau
-- side plus a structural tag for the styling side (UIPanel via StateDriver, the
-- sole tag mutator). NOTHING HERE ANIMATES — no tween, no UITicker handler, no
-- RunService connection; the panel is a surface, and surfaces do not move.
-- Sequenced motion that happens to be hosted ON a panel (a kiln ceremony, a
-- glaze pour) belongs to the screen module that owns the sequence, not here. A
-- behaviour implemented on BOTH sides is a bug, so there is deliberately no
-- state look in this file for a pack's StyleRules to fight over.
--
-- DIALECT (props.dialect): the pack's two sub-languages, tokenized rather than
-- branched on a pack id.
--   "glaze"  — glossy: the specular wash + sheen arc, and the glaze dialect's
--              pattern (polka dots) at its own transparency. Celebration
--              surfaces, reward cards, storefront plates.
--   "studio" — matte: clay speckle grain, no sheen. THIS is what data-dense
--              screens use, because a shimmering surface under twenty stat rows
--              is unreadable — and the matte dialect is not a lesser one: it
--              carries the same density as the Armored Core assembly panel.
--   A pack that declares neither namespace still renders: the dialect lookup
--   returns an empty table and every read falls to a house value.
--
-- EDGES (props.edges): { Top = true, Bottom = true, Left = ..., Right = ... }.
-- The lip hangs fully OUTSIDE the side it decorates, so the panel's own content
-- box is never eaten by decoration (the pack's hardest law: nothing gets
-- smaller for being cute).
--
-- CLIPPING CAVEAT, and why this component does NOT set ClipsDescendants:
-- Roblox clipping is axis-aligned and does not clip ROTATED descendants. The
-- Top/Left/Right lips are rotated to point their art outward, and they are
-- meant to hang past the panel — so a self-clipping panel would erase the very
-- decoration it was built for. Callers who need clipped content should parent
-- that content into `panel.Content` and set ClipsDescendants on THEIR OWN inner
-- frame, or use only the (unrotated, safe-anywhere) Bottom edge. A panel
-- wearing rotated edges must never be placed inside a scrolling viewport.
--
-- ORDERING CONTRACT (inherited from GPLayoutKit.GlazeSheen): the sheen clones
-- the host's UICorner so the wash can never square off a petal corner. _Style
-- therefore emits the corner FIRST and rebuilds the sheen after it — which is
-- also why the sheen is rebuilt rather than recoloured on a theme swap: its
-- corner clone would otherwise carry the previous pack's radii.
--
-- BUDGETS: at most ONE UIShadow per instance, budget-counted through
-- Capabilities.RegisterShadow and Released on every restyle and on Destroy.
-- Zero ticker handlers, zero RunService connections. 100x Create/Destroy = zero
-- connection, instance or budget growth.
--
-- Props (plus the shared layout props from UIComponentBase):
--   dialect    : "glaze" | "studio"  (default "studio" — matte is the safe
--                default; a caller opts INTO shimmer, never out of it)
--   edges      : { Top/Bottom/Left/Right = boolean }  (default Bottom only)
--   fillToken  : Colors.* key for the panel fill (default "SurfaceRaised")
--   cornerKey  : Corners.* key ("Petal" | "PetalMirror" | "Leaf" | "Tab").
--                Omitted, the panel alternates Petal/PetalMirror by layoutOrder
--                so a grid of panels reads hand-arranged rather than stamped.
--   sheen      : force the glaze wash on/off, overriding the dialect default
--   contentPad : px inset for the Content frame (default Spacing.M)

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local StateDriver = require(script.Parent.Parent.StyleKit.StateDriver)
local Tags = require(script.Parent.Parent.StyleKit.Tags)
local UIComponentBase = require(script.Parent.UIComponentBase)

local GPScallopPanel = setmetatable({}, { __index = UIComponentBase })
GPScallopPanel.__index = GPScallopPanel

local EDGE_ORDER: { GPLayoutKit.ScallopEdge } = { "Top", "Bottom", "Left", "Right" }
-- House fallbacks for packs that declare no dialect namespace. Chosen so the
-- decoration reads as "barely there texture" rather than disappearing.
local HOUSE_PATTERN_TRANSPARENCY = 0.93

local function dialectTokens(theme: Types.UITheme, name: string): { [string]: any }
	local tokens = theme.DialectTokens
	return (tokens and tokens[name]) or {}
end

function GPScallopPanel.new()
	local self = UIComponentBase.new("GPScallopPanel")
	self._edges = {}
	self._edgeInstances = {}
	return setmetatable(self, GPScallopPanel)
end

function GPScallopPanel:_Build(props: Types.UIComponentProps)
	local root = self.Root
	-- The ROOT IS the surface (not a transparent wrapper): a panel that painted
	-- its fill on a child would cast its shadow from the child and leave the
	-- root's rect showing through at the corners.
	--
	-- Born TRANSPARENT, never painted here: UIStyler.Frame's BackgroundColor3
	-- default is PURE WHITE, which this pack forbids outright, and _Build has no
	-- theme to paint from (it runs before the first ApplyTheme). A transparent
	-- frame renders nothing, so no white can ever reach a screen; _Style is the
	-- only place in this file that assigns a fill or clears the transparency.
	root.BackgroundTransparency = 1
	-- NOT ClipsDescendants — see the clipping caveat in the header.

	-- Structural identity for the styling side (build-time, never removed).
	StateDriver.Structural(root, Tags.Structural.Panel)

	-- Pattern layer: the dialect's own grain (clay speckle / polka dots), under
	-- everything. Built once as a bare ImageLabel and re-pointed in _Style,
	-- because the KEY itself is a dialect token and can change with the theme.
	-- Deliberately NOT registered with IconVisibility: this is pack CHROME, not
	-- iconography, and toggling icons off must not strip a surface's texture.
	local pattern = Instance.new("ImageLabel")
	pattern.Name = "Pattern"
	pattern.BackgroundTransparency = 1
	pattern.ScaleType = Enum.ScaleType.Tile
	pattern.Size = UDim2.fromScale(1, 1)
	pattern.ZIndex = 2
	pattern.Parent = root
	self._pattern = pattern

	-- Content well: where callers parent their children, above the pattern and
	-- above the sheen so decoration can never wash out copy.
	local content = UIStyler.Frame("Content")
	content.BackgroundTransparency = 1
	content.ZIndex = 6
	content.Parent = root
	self.Content = content

	-- Edge strips are STRUCTURE (which sides exist), so they are built here and
	-- only tinted/retiled in _Style. Default: the Bottom lip alone — the one
	-- unrotated edge, safe in any container.
	local edges = props.edges
	for _, side in EDGE_ORDER do
		local wanted = if edges then (edges :: any)[side] == true else side == "Bottom"
		if wanted then
			table.insert(self._edges, side)
		end
	end
end

-- Rebuild the decoration that cannot simply be recoloured. Two things qualify:
-- the scallop strips (a pack may swap the art's tile geometry, or drop the
-- asset entirely and need the rounded-lip fallback instead) and the glaze sheen
-- (it CLONES the host's UICorner, so a corner change invalidates it).
function GPScallopPanel:_RebuildDecoration(theme: Types.UITheme, fill: Color3)
	local root = self.Root

	for _, instance in self._edgeInstances do
		instance:Destroy()
	end
	table.clear(self._edgeInstances)
	for _, side in self._edges do
		local strip = GPLayoutKit.Scallop(theme, root, side, fill)
		-- Left/Right do NOT return a direct child of the panel: the kit wraps
		-- them in a "ScallopRail" square (the only way to span a vertical edge
		-- with horizontally-tiled art, since no UDim expresses "parent height as
		-- my width"). The thing this component owns — and must destroy on the
		-- next restyle — is that outermost child, not the strip inside it.
		-- Tracking the strip alone would leave an orphaned rail per theme swap.
		local owned: GuiObject = if strip.Parent == root then strip else (strip.Parent :: GuiObject)
		-- Under the content well and the sheen, over the flat fill: the lip is
		-- the surface dripping past its own edge, not a sticker on top of it.
		owned.ZIndex = 1
		strip.ZIndex = 1
		table.insert(self._edgeInstances, owned)
	end

	if self._sheen then
		self._sheen:Destroy()
		self._sheen = nil
	end
	local dialect = self.Props.dialect or "studio"
	local wantsSheen = self.Props.sheen
	if wantsSheen == nil then
		wantsSheen = dialect == "glaze"
	end
	if wantsSheen then
		-- Corner first, sheen second — the ordering contract (see header).
		local sheen = GPLayoutKit.GlazeSheen(theme, root)
		sheen.ZIndex = 3
		self._sheen = sheen
	end
end

function GPScallopPanel:_Style(theme: Types.UITheme)
	local root = self.Root
	local spacing = theme.Spacing
	local dialect = self.Props.dialect or "studio"
	local tokens = dialectTokens(theme, dialect)

	local fillToken = self.Props.fillToken
	local fill = (fillToken and (theme.Colors :: any)[fillToken]) or theme.Colors.SurfaceRaised
	root.BackgroundTransparency = 0
	self:_SetColor(root, "BackgroundColor3", fill)

	-- PETAL CORNERS. A named cornerKey wins; otherwise alternate Petal /
	-- PetalMirror by layout order so a GRID of panels reads hand-arranged
	-- rather than stamped. CornerSet destroys any stale UICorner before
	-- parenting, so an instance never carries CornerRadius alongside per-corner
	-- radii (documented-undefined engine behaviour) and never grows a second
	-- UICorner across restyles.
	local cornerKey = self.Props.cornerKey
	if cornerKey then
		GPLayoutKit.CornerSet(theme, root, cornerKey)
	else
		GPLayoutKit.Petal(theme, root, self.Props.layoutOrder or 0)
	end

	-- Soft rounded-join stroke in a DEEPENED TINT OF THE FILL — never black,
	-- never grey. Rebuilt rather than recoloured because the pack's stroke
	-- weight and transparency are Chrome policy and may move with the theme.
	if self._stroke then
		self._stroke:Destroy()
	end
	self._stroke = GPLayoutKit.SoftStroke(theme, root, fill)

	-- THE HUE-MATCHED SHADOW: derived from this panel's OWN fill, so a cream
	-- panel casts warm and a matcha panel casts sage. Only packs declaring
	-- native shadow tokens pay; budget-counted, and the old handle is RELEASED,
	-- never leaked, on every restyle.
	if self._shadowHandle then
		self._shadowHandle:Release()
		self._shadowHandle = nil
	end
	if theme.EffectShadows then
		self._shadowHandle = GPLayoutKit.Shadow(theme, root, "md", nil, fill)
	end

	-- Dialect grain. The pattern KEY is itself a token (glaze -> polkadot,
	-- studio -> speckle), tinted with the fill's own deepened hue so the
	-- texture belongs to the surface instead of sitting on it as grey noise.
	local pattern = self._pattern :: ImageLabel
	local assets = theme.Assets
	local patternDef = assets and assets[tokens.patternKey or ""]
	if patternDef then
		pattern.Visible = true
		pattern.Image = patternDef.image
		pattern.TileSize = UDim2.fromOffset(
			patternDef.tile or patternDef.tileX or 128,
			patternDef.tile or patternDef.height or 128
		)
		pattern.ImageColor3 = GPLayoutKit.Deepen(theme, fill, 1)
		pattern.ImageTransparency = tokens.patternTransparency
			or tokens.speckleTransparency
			or HOUSE_PATTERN_TRANSPARENCY
	else
		-- TODO: asset missing — the panel simply reads flat. A decorative
		-- overlay with no art must NOT fall back to a solid box: it would sit
		-- on top of the content it was meant to flatter.
		pattern.Visible = false
	end

	self:_RebuildDecoration(theme, fill)

	local pad = self.Props.contentPad or spacing.M
	local content = self.Content :: Frame
	content.Position = UDim2.fromOffset(pad, pad)
	content.Size = UDim2.new(1, -pad * 2, 1, -pad * 2)
end

function GPScallopPanel:Destroy()
	if self._shadowHandle then
		self._shadowHandle:Release()
		self._shadowHandle = nil
	end
	UIComponentBase.Destroy(self)
end

return GPScallopPanel
