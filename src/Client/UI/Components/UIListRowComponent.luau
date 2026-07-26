--!strict
-- Shop LIST ROW — the leaderboard/zebra row grammar (doc §9) fused with the
-- shop row. Zebra background by LayoutOrder parity (Arcade.NearBlack2 odd /
-- Arcade.Row even, both @ 0.15 transparency), hard 90° corners + the 3px
-- black arcade stroke; a 92×92 near-black icon box on the left (item art, or
-- a FredokaOne monogram on a pastel hashed from the item id); white outlined
-- name over a gold tag/category line; and a price button at the row's right
-- end (UIButtonComponent price mode — the currency icon always leads the
-- number, doc §3.3). Normally themed: base ApplyTheme runs and _Style paints
-- theme.Arcade / theme.Colors tokens on every repaint.
--
-- Props: item, currencyIcon (accepted for protocol compatibility; the price
-- button derives its icon from priceCurrency instead), affordable, owned?,
-- onBuy

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local SharedTypes = require(ReplicatedStorage.Shared.Types)
local Types = require(script.Parent.Parent.Types)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
-- SAFE: GLLayoutKit requires only Types/UIStyler/UIChrome (verified), none of
-- which require a component, so this closes no cycle. The kit is CONSULTED as
-- the active pack's policy — the same branch UIChrome.ModalCard already makes.
local GLLayoutKit = require(script.Parent.Parent.Framework.GLLayoutKit)
local UIComponentBase = require(script.Parent.UIComponentBase)
local UIButtonComponent = require(script.Parent.UIButtonComponent)

local UIListRowComponent = setmetatable({}, { __index = UIComponentBase })
UIListRowComponent.__index = UIListRowComponent

-- Fixed px at the 1650×1020 authoring baseline (doc §7.1).
local ROW_HEIGHT = 124
local ICON_BOX = 92
local BUY_WIDTH = 150
local BUY_HEIGHT = 48
local EDGE_PAD = 16
-- Doc §2 type scale: 20–24 = labels/rows.
local NAME_TEXT_SIZE = 24
local SUB_TEXT_SIZE = 20
-- Left edge of the text column: icon box + its margins.
local TEXT_X = EDGE_PAD + ICON_BOX + EDGE_PAD
-- Room reserved on the right for the price button (+ a small gap).
local TEXT_RIGHT_RESERVE = TEXT_X + BUY_WIDTH + EDGE_PAD + 12
-- Zebra rows sit at 0.15 transparency (doc §9 leaderboard grammar).
local ZEBRA_TRANSPARENCY = 0.15

local WHITE = Color3.new(1, 1, 1)

function UIListRowComponent.new()
	local self = UIComponentBase.new("UIListRow")
	-- Every GL sticker-shadow BUDGET HANDLE this row takes out, released in
	-- Destroy (law 9). Stays empty on every non-GL pack.
	self._glShadows = {}
	return setmetatable(self, UIListRowComponent)
end

-- Deterministic pastel from the item id — the same stable placeholder-swatch
-- hash the card renderer uses, so an item keeps one identity colour whether it
-- renders as a card or a row. Hash-derived, deliberately not a theme token.
local function monogramColor(id: string): Color3
	local hash = 0
	for i = 1, #id do
		hash = (hash * 31 + string.byte(id, i)) % 360
	end
	return Color3.fromHSV(hash / 360, 0.5, 0.85)
end

-- The gold line under the name: the item's tags joined, else its category.
local function subText(item: SharedTypes.ShopItem): string
	if item.tags and #item.tags > 0 then
		-- "•" is in FredokaOne's stated glyph set (doc §10 booth iconography).
		return table.concat(item.tags, " • ")
	end
	if item.category and item.category ~= "" then
		return TextConfig.Resolve("shop.category." .. item.category)
	end
	return ""
end

function UIListRowComponent:_Build(props: Types.UIComponentProps)
	local item = props.item :: SharedTypes.ShopItem
	self._item = item
	if not props.size then
		self.Root.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		self._baseSize = self.Root.Size
	end
	self.Root.BackgroundTransparency = 1

	-- Surface carries the zebra fill and everything visible; the Root stays a
	-- fixed transparent footprint so the Appear pop (a UIScale on the surface)
	-- never reflows the list.
	local surface = UIStyler.Frame("Surface")
	surface.BackgroundTransparency = ZEBRA_TRANSPARENCY
	surface.Size = UDim2.fromScale(1, 1)
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Parent = self.Root
	self._surface = surface
	self:_UseScaleTarget(surface)
	-- HARD ARCADE: 0px corners; the border stroke attaches on first _Style —
	-- Classic keeps the 3px stroke painted from theme.Colors.Stroke, a styled
	-- chrome frames the row through the UIChrome policy instead.
	UIChrome.Corner("Arcade").Parent = surface

	-- Zebra parity comes from LayoutOrder, which ShopScreen's sync loop mutates
	-- externally on reorder — repaint whenever it moves.
	self:_Connect(self.Root:GetPropertyChangedSignal("LayoutOrder"), function()
		local theme = self.Theme
		if theme then
			self:_ApplyZebra(theme)
		end
	end)

	-- Left icon box: 92×92 near-black (doc §3.2 "icon boxes"), hard corners;
	-- its border stroke attaches on first _Style, same gate as the surface.
	local iconBox = UIStyler.Frame("IconBox")
	iconBox.Size = UDim2.fromOffset(ICON_BOX, ICON_BOX)
	iconBox.AnchorPoint = Vector2.new(0, 0.5)
	iconBox.Position = UDim2.new(0, EDGE_PAD, 0.5, 0)
	iconBox.Parent = surface
	self._iconBox = iconBox
	UIChrome.Corner("Arcade").Parent = iconBox

	if item.iconId ~= "" then
		-- Real art fits inside the box with a small margin, keeping its own
		-- aspect (ScaleType.Fit).
		local art = Instance.new("ImageLabel")
		art.Name = "Art"
		art.BackgroundTransparency = 1
		art.Image = item.iconId
		art.ScaleType = Enum.ScaleType.Fit
		art.Size = UDim2.fromOffset(ICON_BOX - 8, ICON_BOX - 8)
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.Position = UDim2.fromScale(0.5, 0.5)
		art.Parent = iconBox
	else
		-- Monogram fallback: the item name's first letter in FredokaOne over a
		-- pastel hashed from the item id.
		local swatch = UIStyler.Frame("Monogram")
		swatch.BackgroundColor3 = monogramColor(item.id)
		swatch.Size = UDim2.fromScale(1, 1)
		swatch.Parent = iconBox
		local name = TextConfig.Resolve(item.nameKey)
		local letter = UIChrome.Text("Letter", 44, WHITE)
		letter.Text = string.upper(string.sub(name ~= "" and name or item.id, 1, 1))
		letter.Size = UDim2.fromScale(1, 1)
		letter.Parent = swatch
	end

	-- Name: white FredokaOne 24 with the black outline, truncating at the end
	-- (doc §2 long-text safety for names).
	local nameLabel = UIChrome.Text("ItemName", NAME_TEXT_SIZE, WHITE)
	nameLabel.Text = TextConfig.Resolve(item.nameKey)
	-- RichText off: TextTruncate is unreliable on RichText labels, and a plain
	-- item name never needs markup.
	nameLabel.RichText = false
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Position = UDim2.new(0, TEXT_X, 0.5, -28)
	nameLabel.Size = UDim2.new(1, -TEXT_RIGHT_RESERVE, 0, 28)
	nameLabel.Parent = surface
	self._name = nameLabel

	-- Gold label line under the name: tags joined, else category (doc §3.3:
	-- gold = "this is valuable / worth noticing").
	local sub = UIChrome.Text("SubLabel", SUB_TEXT_SIZE, WHITE)
	sub.Text = subText(item)
	sub.RichText = false
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	sub.Position = UDim2.new(0, TEXT_X, 0.5, 2)
	sub.Size = UDim2.new(1, -TEXT_RIGHT_RESERVE, 0, 24)
	sub.Parent = surface
	self._sub = sub

	self:_BuildBuy()
end

-- The price button at the row's right end. Price mode: the currency icon
-- always leads the amount, colour by currency (Cash green / Bux blue / Robux
-- magenta), OWNED = grey with children hidden — all owned by UIButtonComponent.
function UIListRowComponent:_BuildBuy()
	local item = self._item :: SharedTypes.ShopItem
	local owned = self.Props.owned == true
	self._buyOwned = owned
	local buy = UIButtonComponent.new()
	self._buy = buy
	buy:Create(self._surface, {
		size = UDim2.fromOffset(BUY_WIDTH, BUY_HEIGHT),
		position = UDim2.new(1, -EDGE_PAD, 0.5, 0),
		anchorPoint = Vector2.new(1, 0.5),
		priceCurrency = item.currencyType,
		priceAmount = ShopConfig.FormatPrice(item.price),
		owned = owned,
		-- Unaffordable = currency-coloured but DIMMED in place, still fully
		-- tappable — every tap answers (doc §11.1) and the screen explains
		-- via its can't-afford toast. Only ownership disables the buy.
		enabled = not owned,
		dimmed = self.Props.affordable == false,
		onClick = function()
			if self.Props.onBuy then
				self.Props.onBuy(self._item)
			end
		end,
	})
end

-- OWNED/CLAIMED recolours IN PLACE (doc §11.2): SetContent flips the live
-- price button grey "OWNED" with its children hidden — the control is never
-- destroyed or rebuilt. Affordability is the in-place dim.
function UIListRowComponent:_RefreshBuy()
	local owned = self.Props.owned == true
	self._buyOwned = owned
	if self._buy then
		self._buy:SetContent({
			owned = owned,
			dimmed = self.Props.affordable == false,
		})
		self._buy:SetEnabled(not owned)
	end
end

-- Zebra by LayoutOrder parity (doc §9): NearBlack2 odd / Row even, @ 0.15.
-- Painted directly (no theme-swap tween) so a reorder recolours instantly.
function UIListRowComponent:_ApplyZebra(theme: Types.UITheme)
	local odd = self.Root.LayoutOrder % 2 == 1
	if theme.LayoutKit == "GL" then
		-- GL has no zebra: the cut plate IS the row surface, and parity drives
		-- the SLIGHT ALTERNATING TILT instead (the kit's ListRow grammar), so
		-- reorders keep re-deciding the slant exactly the way they used to
		-- re-decide the stripe. Both slants are multiples of the one axis.
		self._surface.BackgroundTransparency = 1
		if self._glPlate then
			self._glPlate.Rotation = if odd then -GLLayoutKit.TILT * 0.3 else GLLayoutKit.TILT * 0.35
		end
		return
	end
	self._surface.BackgroundColor3 = odd and theme.Arcade.NearBlack2 or theme.Arcade.Row
	self._surface.BackgroundTransparency = ZEBRA_TRANSPARENCY
end

-- ========================================================================
-- GL PACK BRANCH — the active pack's policy, not a fork. It RE-DRESSES the
-- row the classic pass just painted: nothing is rebuilt, moved or removed, so
-- props, Update(), the price-button flow and onBuy are untouched. Built lazily
-- on the first GL pass, then only re-tinted/toggled; a swap back off GL runs
-- _StyleGLRelease (disable-not-destroy).
-- ========================================================================

function UIListRowComponent:_StyleGL(theme: Types.UITheme)
	local ink = theme.Colors.Stroke
	local surface = self._surface :: Frame

	-- ---- row surface: cut plate + halftone + sticker shadow (laws 1/4/8) --
	local plate = self._glPlate
	if not plate then
		plate = GLLayoutKit.Slice(theme, "cardCut", theme.Arcade.Row, "GLPlate")
		plate.Size = UDim2.fromScale(1, 1)
		plate.ZIndex = 0 -- under the icon box / name / sub / buy button
		plate.Parent = surface
		self._glPlateShadow = GLLayoutKit.Shadow(theme, plate, "sm", self._glShadows)
		GLLayoutKit.Tile(theme, "halftone", ink, 0.9, "GLTone").Parent = plate
		self._glPlate = plate
	end
	plate.ImageColor3 = theme.Arcade.Row
	plate.BackgroundColor3 = theme.Arcade.Row -- the kit's missing-asset fallback
	plate.Visible = true
	if self._glPlateShadow then
		self._glPlateShadow:SetEnabled(true)
	end
	-- Only the PLATE tilts. The Root and the buy button stay rectangular so
	-- gamepad/touch bounds never sit on a slant (the pack's a11y rule).
	self:_ApplyZebra(theme)
	if self._stroke then
		self._stroke.Enabled = false -- the 9-slice draws the ink itself
	end

	-- ---- icon box -> ART SLOT (law 7) -----------------------------------
	-- Item art cannot be generated and the glossy 3D icon set is banned as the
	-- visual language, so the box becomes the hatched reserved slot. The real
	-- art / monogram is only HIDDEN, so a swap back off GL restores it.
	local box = self._iconBox :: Frame
	local slot = self._glArtSlot
	if not slot then
		local hidden = {}
		for _, child in box:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				child.Visible = false
				table.insert(hidden, child)
			end
		end
		self._glHiddenArt = hidden
		slot = GLLayoutKit.Slice(theme, "artSlot", theme.Colors.Disabled, "GLArtSlot")
		slot.Size = UDim2.fromScale(1, 1)
		slot.ZIndex = 2
		slot.Parent = box
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
	box.BackgroundTransparency = 1
	if self._iconStroke then
		self._iconStroke.Enabled = false
	end

	-- ---- type: name cream, the sub/value line gold (laws 2/3) -----------
	-- (The price itself is the buy button, which the shared UIButtonComponent
	-- already turns into the pack's ink plate with gold numerals under GL —
	-- never a coloured pill.)
	self._name.TextColor3 = theme.Colors.TextPrimary
	UIChrome.TextOutline(self._name)
	self._sub.TextColor3 = theme.Arcade.Gold
	UIChrome.TextOutline(self._sub)
end

function UIListRowComponent:_StyleGLRelease(theme: Types.UITheme)
	if not self._glPlate then
		return
	end
	self._glPlate.Visible = false
	if self._glPlateShadow then
		self._glPlateShadow:SetEnabled(false)
	end
	if self._glArtSlot then
		self._glArtSlot.Visible = false
	end
	for _, child in self._glHiddenArt or {} do
		child.Visible = true
	end
	(self._iconBox :: Frame).BackgroundTransparency = 0
	if self._stroke then
		self._stroke.Enabled = true
	end
	if self._iconStroke then
		self._iconStroke.Enabled = true
	end
	self:_ApplyZebra(theme)
end

function UIListRowComponent:_Style(theme: Types.UITheme)
	self:_ApplyZebra(theme)
	-- Row + icon-box borders: Classic keeps the legacy 3px stroke painted from
	-- theme.Colors.Stroke; a styled chrome (theme.Chrome) frames both through
	-- the UIChrome policy instead (e.g. hairline accent framing).
	local styled = theme.Chrome ~= nil
	if not self._stroke then
		self._stroke = if styled
			then UIChrome.Stroke(theme, "Arcade", "Panel")
			else UIStyler.Stroke(Color3.new(0, 0, 0), 3, 0)
		self._stroke.Parent = self._surface
		self._iconStroke = if styled
			then UIChrome.Stroke(theme, "Arcade", "Panel")
			else UIStyler.Stroke(Color3.new(0, 0, 0), 3, 0)
		self._iconStroke.Parent = self._iconBox
	end
	if not styled then
		self._stroke.Color = theme.Colors.Stroke
		self._iconStroke.Color = theme.Colors.Stroke
	end
	self:_SetColor(self._iconBox, "BackgroundColor3", theme.Arcade.NearBlack)
	-- Fixed doc type-scale sizes (24/20) stay; fonts/colours re-read the theme
	-- so a live swap repaints the row like any other component. The text
	-- emphasis is re-asserted AFTER each colour so a styled glow tracks it.
	self._name.FontFace = theme.Fonts.Subtitle
	self._name.TextColor3 = theme.Colors.TextPrimary
	UIChrome.TextOutline(self._name)
	self._sub.FontFace = theme.Fonts.Subtitle
	self._sub.TextColor3 = theme.Arcade.Gold
	UIChrome.TextOutline(self._sub)

	-- ACTIVE-PACK POLICY, detected once per style application (the same switch
	-- UIChrome.ModalCard makes). Everything above is the untouched classic
	-- paint — it still runs, so every token stays live and a swap back off GL
	-- lands on a fully-repainted row; the GL pass then re-dresses the surface,
	-- the icon box and the type in the comic language.
	if theme.LayoutKit == "GL" then
		self:_StyleGL(theme)
	else
		self:_StyleGLRelease(theme)
	end
end

-- Patch affordability / owned in place without rebuilding the row.
function UIListRowComponent:Update(props: { affordable: boolean?, owned: boolean? })
	if props.affordable ~= nil then
		self.Props.affordable = props.affordable
	end
	if props.owned ~= nil then
		self.Props.owned = props.owned
	end
	self:_RefreshBuy()
end

function UIListRowComponent:Destroy()
	if self._buy then
		self._buy:Destroy()
		self._buy = nil
	end
	UIComponentBase.Destroy(self)
end

return UIListRowComponent
