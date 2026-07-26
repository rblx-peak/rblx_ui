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
	self._surface.BackgroundColor3 = odd and theme.Arcade.NearBlack2 or theme.Arcade.Row
	self._surface.BackgroundTransparency = ZEBRA_TRANSPARENCY
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
