--!strict
-- Soft-currency vendor (id "vendor") — BUY / SELL / BUYBACK on the Pottery
-- Clash arcade family (doc §7.4 / §8 / §11).
--
--   BUY     — vendor stock rows: icon, name, stock line, price button in Cash
--             green (price-button mode, §3.3: Cash = green everywhere).
--   SELL    — the player inventory as compact rows with a muted sell-value
--             line (60% of value) and a SELL button; selling moves the item to
--             BUYBACK at its sell price.
--   BUYBACK — everything sold this visit, buyable back at the sell price.
--             Buyback clears when the player leaves (reset every Show).
--
-- A demo Cash pill (UICurrencyPillComponent) sits top-right of the content and
-- genuinely rises/falls with every transaction so the loop feels real; the
-- pill pulses on change by itself. Unaffordable / out-of-stock buys follow the
-- doc's blocked pattern: the price button dims IN PLACE (never removed, never
-- disabled) and the tap still plays full press juice, then answers with a
-- toast (§11.1 / §11.2).
--
-- Show(data) = { stock, playerItems, balance }.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UICurrencyPillComponent = require(script.Parent.Parent.Components.UICurrencyPillComponent)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)

type StockItem = { id: string, name: string, icon: string, price: number, stock: number }
type PlayerItem = { id: string, name: string, icon: string, value: number, qty: number }
type BuybackItem = { id: string, name: string, icon: string, price: number, value: number }

-- Fixed px at the 1650×1020 baseline. Content = card − (28, 88) (§7.4 insets).
local CARD_W, CARD_H = 1120, 680
local TAB_W, TAB_H = 150, 48
local NOTE_Y = 60
local LIST_Y = 96
local ROW_H = 76
local ROW_GAP = 8
local BUTTON_SIZE = UDim2.fromOffset(140, 48)
local SELL_RATE = 0.6

local TABS = {
	{ id = "buy", label = "BUY" },
	{ id = "sell", label = "SELL" },
	{ id = "buyback", label = "BUYBACK" },
}

local TAB_NOTES: { [string]: string } = {
	buy = "Stock is per visit — gone is gone.",
	sell = "Items sell for 60% of their value.",
	buyback = "Buyback offers clear when you leave the vendor.",
}

local function comma(n: number): string
	local out = tostring(math.floor(math.abs(n)))
	while true do
		local replaced: number
		out, replaced = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return if n < 0 then "-" .. out else out
end

local function sellValueOf(value: number): number
	return math.floor(value * SELL_RATE)
end

local DEMO_BALANCE = 1250

local function demoStock(): { StockItem }
	return {
		{ id = "clay_bundle", name = "CLAY BUNDLE", icon = "box", price = 120, stock = 12 },
		{ id = "glaze_kit", name = "HONEY GLAZE KIT", icon = "potion", price = 340, stock = 6 },
		{ id = "kiln_fuel", name = "KILN FUEL", icon = "fire", price = 95, stock = 20 },
		{ id = "sculpt_hammer", name = "SCULPTOR'S HAMMER", icon = "hammer", price = 780, stock = 2 },
		-- Priced above the demo wallet on purpose: shows the dim + toast gate.
		{ id = "mystery_crate", name = "MYSTERY CRATE", icon = "crate", price = 1500, stock = 1 },
	}
end

local function demoItems(): { PlayerItem }
	return {
		{ id = "old_trophy", name = "OLD TROPHY", icon = "trophy", value = 500, qty = 1 },
		{ id = "spare_key", name = "SPARE KEY", icon = "key", value = 120, qty = 3 },
		{ id = "dusty_journal", name = "DUSTY JOURNAL", icon = "book", value = 260, qty = 1 },
		{ id = "raw_crystal", name = "RAW CRYSTAL", icon = "crystal", value = 800, qty = 2 },
	}
end

local VendorScreen = setmetatable({}, { __index = UIScreenBase })
VendorScreen.__index = VendorScreen

function VendorScreen.new()
	local self = UIScreenBase.new("VendorScreen", 7)
	self._stock = demoStock()
	self._playerItems = demoItems()
	self._buyback = {} :: { BuybackItem }
	self._balance = DEMO_BALANCE
	self._tab = "buy"
	self._tabButtons = {} :: { [string]: any }
	self._rowComponents = {} :: { any }
	return setmetatable(self, VendorScreen)
end

function VendorScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function VendorScreen:_BuildContent()
	-- GP layout language: the kiln-side STALL (cream page, rose ribbon, petal
	-- rows alternating mirror, butter price pills) — see _BuildGPLayout below.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end

	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "VENDOR",
		sizePx = Vector2.new(CARD_W, CARD_H),
		onClose = function()
			self.ScreenController:HideScreen("vendor")
		end,
	})
	self._modal = modal
	local content = modal.content

	local tabRow = UIStyler.Frame("Tabs")
	tabRow.BackgroundTransparency = 1
	tabRow.Size = UDim2.fromOffset(3 * TAB_W + 2 * 10, TAB_H)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = tabRow
	tabRow.Parent = content

	for index, tab in TABS do
		local button = UIButtonComponent.new()
		button:Create(tabRow, {
			text = tab.label,
			variant = "Ghost",
			size = UDim2.fromOffset(TAB_W, TAB_H),
			layoutOrder = index,
			onClick = function()
				self:_SetTab(tab.id)
			end,
		})
		self._tabButtons[tab.id] = button
	end

	-- The demo wallet: a real currency pill that rises and falls with every
	-- buy/sell so the loop reads as live (it pulses on change by itself).
	self._pill = UICurrencyPillComponent.new()
	self._pill:Create(content, {
		currencyId = "Cash",
		value = self._balance,
		size = UDim2.fromOffset(220, 56),
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, 0, 0, 0),
	})

	local note = UIChrome.BodyText("TabNote", 15, theme.Colors.Disabled)
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.Position = UDim2.fromOffset(0, NOTE_Y)
	note.Size = UDim2.fromOffset(760, 22)
	note.Parent = content
	self._noteLabel = note

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, LIST_Y)
	list.Size = UDim2.new(1, 0, 1, -LIST_Y)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = theme.Arcade.Gold
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, ROW_GAP),
	}).Parent = list
	list.Parent = content
	self._list = list

	self:_SetTab(self._tab)
end

-- Active tab = blue (doc §3.2: blue is the tab colour), inactive = ghost.
-- SetContent re-reads text from what it is handed, so both states restate it.
function VendorScreen:_SetTab(tabId: string)
	self._tab = tabId
	for _, tab in TABS do
		local button = self._tabButtons[tab.id]
		if button then
			button:SetContent({
				text = tab.label,
				variant = if tab.id == tabId then "Blue" else "Ghost",
			})
		end
	end
	-- The GP tab bar carries its own selection paint (rose fill, butter
	-- underline, a scale step); nil under every other layout, so the classic
	-- ghost/blue flip above is untouched.
	if self._gpTabs then
		self._gpTabs.Select(tabId)
	end
	self._noteLabel.Text = TAB_NOTES[tabId] or ""
	self:_RenderList()
end

function VendorScreen:_RefreshWallet()
	-- GP wallet: the kit's butter PricePill, pulsed on change exactly like the
	-- arcade currency pill it stands in for.
	local wallet = self._gpWallet
	if wallet then
		local text = comma(self._balance)
		if wallet.amount.Text ~= text then
			wallet.amount.Text = text
			UIChrome.Pulse(self:GetTheme(), wallet.root)
		end
		return
	end
	if self._pill then
		self._pill:SetValue(self._balance)
	end
end

function VendorScreen:_ClearList()
	for _, component in self._rowComponents :: { any } do
		component:Destroy()
	end
	table.clear(self._rowComponents)
	-- Nil until the first Show builds the screen (Destroy may run earlier).
	if self._list then
		for _, child in self._list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end
end

-- Shared row shell: slate row fill + 3px black stroke + glass, 48px boxless
-- icon, name (FredokaOne 22) over a quiet sub-line. Callers add the action.
function VendorScreen:_BuildRow(order: number, icon: string, name: string, subText: string, subColor: Color3): Frame
	local theme = self:GetTheme()

	local row = UIStyler.Frame("Row" .. order)
	row.BackgroundColor3 = theme.Arcade.Row
	row.BackgroundTransparency = theme.Arcade.RowTransparency
	row.Size = UDim2.new(1, -16, 0, ROW_H)
	row.LayoutOrder = order
	UIChrome.Stroke(theme, "Arcade").Parent = row
	UIChrome.GlassGradient().Parent = row
	row.Parent = self._list

	local art = IconArchive.Image(row, icon, 48)
	art.AnchorPoint = Vector2.new(0, 0.5)
	art.Position = UDim2.new(0, 14, 0.5, 0)
	art.ZIndex = 2

	local nameLabel = UIChrome.Text("Name", 22, theme.Colors.TextPrimary)
	nameLabel.Text = name
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Position = UDim2.fromOffset(78, 10)
	nameLabel.Size = UDim2.fromOffset(700, 26)
	nameLabel.ZIndex = 2
	nameLabel.Parent = row

	local sub = UIChrome.BodyText("Sub", 15, subColor)
	sub.Text = subText
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	sub.Position = UDim2.fromOffset(78, 42)
	sub.Size = UDim2.fromOffset(700, 20)
	sub.ZIndex = 2
	sub.Parent = row

	return row
end

function VendorScreen:_EmptyLine(text: string)
	local theme = self:GetTheme()
	local label = UIChrome.BodyText("Empty", 17, theme.Colors.Disabled)
	label.Text = text
	label.Size = UDim2.new(1, -16, 0, 60)
	label.LayoutOrder = 1
	label.Parent = self._list
end

function VendorScreen:_RenderList()
	-- GP pastel stall: the same three ledgers as petal rows (see _GPRenderList).
	if self:LayoutKit() == "GP" then
		self:_GPRenderList()
		return
	end

	local theme = self:GetTheme()
	self:_ClearList()

	if self._tab == "buy" then
		for index, item in self._stock :: { StockItem } do
			local soldOut = item.stock <= 0
			local subText = if soldOut then "OUT OF STOCK" else string.format("IN STOCK: %d", item.stock)
			local subColor = if soldOut then theme.Arcade.Red else theme.Arcade.IceBlue
			local row = self:_BuildRow(index, item.icon, item.name, subText, subColor)

			local buy = UIButtonComponent.new()
			buy:Create(row, {
				priceCurrency = "Cash",
				priceAmount = comma(item.price),
				-- Blocked = dimmed IN PLACE, still tappable: the press juice
				-- plays, then _Buy answers with the reason (doc §11.1/§11.2).
				dimmed = soldOut or self._balance < item.price,
				size = BUTTON_SIZE,
				anchorPoint = Vector2.new(1, 0.5),
				position = UDim2.new(1, -14, 0.5, 0),
				onClick = function()
					self:_Buy(item)
				end,
			})
			buy.Root.ZIndex = 3
			table.insert(self._rowComponents, buy)
		end
	elseif self._tab == "sell" then
		if #self._playerItems == 0 then
			self:_EmptyLine("Nothing left to sell.")
		end
		for index, item in self._playerItems :: { PlayerItem } do
			local subText = string.format(
				"SELLS FOR $%s — 60%% OF $%s VALUE",
				comma(sellValueOf(item.value)),
				comma(item.value)
			)
			local row = self:_BuildRow(
				index,
				item.icon,
				string.format("%s  x%d", item.name, item.qty),
				subText,
				theme.Colors.Disabled
			)

			local sell = UIButtonComponent.new()
			sell:Create(row, {
				text = "SELL",
				variant = "Green",
				size = BUTTON_SIZE,
				anchorPoint = Vector2.new(1, 0.5),
				position = UDim2.new(1, -14, 0.5, 0),
				onClick = function()
					self:_Sell(item)
				end,
			})
			sell.Root.ZIndex = 3
			table.insert(self._rowComponents, sell)
		end
	else
		if #self._buyback == 0 then
			self:_EmptyLine("Nothing sold yet this visit.")
		end
		for index, entry in self._buyback :: { BuybackItem } do
			local row = self:_BuildRow(
				index,
				entry.icon,
				entry.name,
				"SOLD THIS VISIT — BUY BACK AT THE SELL PRICE",
				theme.Colors.Disabled
			)

			local back = UIButtonComponent.new()
			back:Create(row, {
				priceCurrency = "Cash",
				priceAmount = comma(entry.price),
				dimmed = self._balance < entry.price,
				size = BUTTON_SIZE,
				anchorPoint = Vector2.new(1, 0.5),
				position = UDim2.new(1, -14, 0.5, 0),
				onClick = function()
					self:_Buyback(entry)
				end,
			})
			back.Root.ZIndex = 3
			table.insert(self._rowComponents, back)
		end
	end
end

-- Return a unit to the player's inventory (stacking on id), preserving the
-- full value so it sells for the same 60% next time.
function VendorScreen:_GiveItem(id: string, name: string, icon: string, value: number)
	for _, item in self._playerItems :: { PlayerItem } do
		if item.id == id then
			item.qty += 1
			return
		end
	end
	table.insert(self._playerItems, { id = id, name = name, icon = icon, value = value, qty = 1 })
end

function VendorScreen:_Buy(item: StockItem)
	if item.stock <= 0 then
		self:_Toast("Out of stock.", "Error")
		return
	end
	if self._balance < item.price then
		self:_Toast("Not enough Cash.", "Error")
		return
	end
	self._balance -= item.price
	item.stock -= 1
	-- Bought goods land in the inventory at full value, feeding the sell loop.
	self:_GiveItem(item.id, item.name, item.icon, item.price)
	self:_Toast(string.format("Bought %s.", item.name), "Success")
	self:_RefreshWallet()
	self:_RenderList()
end

function VendorScreen:_Sell(item: PlayerItem)
	local price = sellValueOf(item.value)
	self._balance += price
	item.qty -= 1
	if item.qty <= 0 then
		local items: { PlayerItem } = self._playerItems
		local index = table.find(items, item)
		if index then
			table.remove(items, index)
		end
	end
	-- Newest sale first, so the row the player just sold tops BUYBACK.
	table.insert(self._buyback, 1, {
		id = item.id,
		name = item.name,
		icon = item.icon,
		price = price,
		value = item.value,
	})
	self:_Toast(string.format("Sold %s for $%s.", item.name, comma(price)), "Success")
	self:_RefreshWallet()
	self:_RenderList()
end

function VendorScreen:_Buyback(entry: BuybackItem)
	if self._balance < entry.price then
		self:_Toast("Not enough Cash.", "Error")
		return
	end
	self._balance -= entry.price
	local list: { BuybackItem } = self._buyback
	local index = table.find(list, entry)
	if index then
		table.remove(list, index)
	end
	self:_GiveItem(entry.id, entry.name, entry.icon, entry.value)
	self:_Toast(string.format("Bought back %s.", entry.name), "Success")
	self:_RefreshWallet()
	self:_RenderList()
end

function VendorScreen:_Apply(data: any)
	if data.stock then
		self._stock = data.stock
	end
	if data.playerItems then
		self._playerItems = data.playerItems
	end
	if data.balance ~= nil then
		self._balance = data.balance
	end
end

function VendorScreen:_OnShow(data: any?)
	if data then
		self:_Apply(data)
	end
	-- Buyback is a per-visit courtesy: it clears on leaving, so every visit
	-- starts with an empty ledger (the BUYBACK tab note says exactly this).
	table.clear(self._buyback)
	self:_RefreshWallet()
	self:_SetTab("buy")
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	elseif self._gpPage then
		-- Same POP_IN contract, on the pack's own plate (theme.Motion tokens).
		UIChrome.PopIn(self:GetTheme(), self._gpPage.panel)
	end
end

function VendorScreen:Update(data: any)
	if not data then
		return
	end
	self:_Apply(data)
	if self._built then
		self:_RefreshWallet()
		self:_RenderList()
	end
end

function VendorScreen:Destroy()
	self:_ClearList()
	for _, button in self._tabButtons :: { [string]: any } do
		button:Destroy()
	end
	table.clear(self._tabButtons)
	if self._pill then
		self._pill:Destroy()
		self._pill = nil
	end
	UIScreenBase.Destroy(self)
end

-- ======================================================================
-- GP layout (theme.LayoutKit == "GP") — the kiln-side STALL, composed from
-- GPLayoutKit: a cream Page under a rose ribbon, the kit's Tab bar for
-- BUY / SELL / BUYBACK, a butter wallet pill in the ribbon's right slot, and
-- each ledger as petal rows whose corners ALTERNATE mirror down the list
-- (pack law 4 — a shelf reads hand-arranged, never stamped). Every plate
-- casts a shadow deepened from its OWN fill (pack law 2).
--
-- Presentation only: the same stock, the same 60% sell rate, the same
-- buy/sell/buyback handlers, the same per-visit buyback reset. Blocked
-- controls are DIMMED IN PLACE and still tappable (doc §11.1/§11.2) — the
-- price pill goes quiet, the tap still plays its juice, and _Buy / _Buyback
-- still answer with the toast that names the reason.
--
-- DENSITY (pack law 6): every field the arcade build shows is here — the
-- item icon, name, quantity, the stock / sell-value / buyback sub-line with
-- its 60%-of-value arithmetic, the price in Cash, the tab note and the live
-- wallet. Each row GAINS a state chip carrying the action word or the stock
-- state, so meaning never rides on a dimmed fill alone.
-- ======================================================================

local GP_PAGE = Vector2.new(1120, 700)
local GP_TABS_H = 52
local GP_NOTE_Y = 62
local GP_LIST_Y = 92
local GP_ROW_H = 84
local GP_ROW_GAP = 10
local GP_CHIP_W, GP_CHIP_H = 118, 30
local GP_PRICE_W, GP_PRICE_H = 172, 44

-- The icon archive's GLYPH FALLBACK is born pure-white with a black text
-- stroke — both banned outright by pack law 1. Every archive placement in
-- this branch goes through here so a pending upload cannot punch a hole in
-- the palette.
local function gpArt(theme: Types.UITheme, parent: Instance, key: string, sizePx: number, query: any?): GuiObject
	local art = IconArchive.Image(parent, key, sizePx, query)
	if art:IsA("TextLabel") then
		art.TextColor3 = theme.Colors.TextPrimary
		art.TextStrokeTransparency = 1
	end
	return art
end

-- GP never shouts (pack law 5). The stock, inventory and buyback tables are
-- authored in arcade caps ("CLAY BUNDLE"), so the SAME strings are retitled
-- for DISPLAY only — the data, the ids and every other branch are untouched,
-- and the toasts keep quoting the caller's own spelling.
local function gpTitleCase(text: string): string
	if string.find(text, "<", 1, true) then
		return text
	end
	-- Only SHOUTED copy is retitled: a string already carrying a lowercase
	-- letter was cased deliberately and flattening it would do real damage.
	if string.find(text, "%l") then
		return text
	end
	local retitled = string.gsub(string.lower(text), "[%a][%w']*", function(word: string): string
		return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
	end)
	return retitled
end

-- A painted petal plate. UIStyler.Frame is born PURE WHITE, so nothing in
-- this branch is ever left unpainted. Shadow is opt-in: one per chip across a
-- full ledger would spend a quarter of the engine's ~100-shadow budget on
-- furniture, so only the ROWS take one.
local function gpPlate(theme: Types.UITheme, parent: Instance, fill: Color3, index: number, sink: { any }?): Frame
	local plate = UIStyler.Frame("Plate")
	plate.BackgroundColor3 = fill
	plate.Parent = parent
	GPLayoutKit.Petal(theme, plate, index)
	GPLayoutKit.SoftStroke(theme, plate, fill)
	if sink then
		GPLayoutKit.Shadow(theme, plate, "sm", sink, fill)
	end
	return plate
end

-- A state chip: pastel plate, INK copy. Colors.TextOnPrimary (near-white)
-- measures 2.14:1 on these tints and is legal only for LARGE display text on
-- a deepened one, so nothing small in this branch ever uses it.
local function gpChip(theme: Types.UITheme, parent: Instance, fill: Color3, text: string, index: number): Frame
	local root = gpPlate(theme, parent, fill, index)
	root.Name = "Chip"
	root.AnchorPoint = Vector2.new(1, 0.5)
	root.Position = UDim2.new(1, -(GP_PRICE_W + 26), 0.5, 0)
	root.Size = UDim2.fromOffset(GP_CHIP_W, GP_CHIP_H)
	root.ZIndex = 4

	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "ChipText")
	label.Text = text
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 5
	label.Parent = root
	return root
end

type GPPriceButton = { root: TextButton, pill: any }

-- The value CONTROL: a butter-gold PricePill wearing a transparent button.
-- The button itself stays transparent because UIStyleEnforcer backstops any
-- SOLID GuiButton with a BLACK 2px stroke, which would break pack law 1 on
-- sight; the pill child carries the fill, the stroke and the hue shadow.
local function gpPriceButton(theme: Types.UITheme, parent: Instance, sink: { any }?, onClick: () -> ()): GPPriceButton
	local root = Instance.new("TextButton")
	root.Name = "GPPrice"
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.AnchorPoint = Vector2.new(1, 0.5)
	root.Position = UDim2.new(1, -16, 0.5, 0)
	root.Size = UDim2.fromOffset(GP_PRICE_W, GP_PRICE_H)
	root.ZIndex = 5
	root.Parent = parent

	local pill = GPLayoutKit.PricePill(theme, root, sink)
	pill.root.Size = UDim2.fromScale(1, 1)
	pill.root.ZIndex = 5
	pill.icon.ZIndex = 6
	pill.amount.ZIndex = 6

	root.Activated:Connect(onClick)
	UIChrome.Animate(theme, root, pill.root)
	return { root = root, pill = pill }
end

function VendorScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	-- Arcade leftovers must not leak into the pastel page: _OnShow pops
	-- self._modal if present and _RefreshWallet drives self._pill.
	self._modal = nil
	self._pill = nil
	self._tabButtons = {}
	self._gpShadows = {} :: { any }
	-- TWO sinks by design. Page chrome is built once and released at teardown;
	-- ROW content is destroyed and rebuilt by _ClearList on every render, so
	-- its handles are released at the TOP of each render or the budget counter
	-- climbs forever behind instances that no longer exist.
	self._gpRowShadows = {} :: { any }

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Vendor",
		subtitleText = "The kiln-side stall",
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("vendor")
		end,
	})
	for _, handle in page.shadows do
		table.insert(self._gpShadows, handle)
	end
	self._gpPage = page

	-- The live wallet, in the ribbon's right slot. Butter fill, ink numerals:
	-- butter is a LIGHT fill and the near-white TextOnPrimary would vanish.
	local wallet = GPLayoutKit.PricePill(theme, page.topRight, self._gpShadows)
	wallet.root.Name = "Wallet"
	wallet.root.Size = UDim2.fromOffset(196, 44)
	wallet.icon.Image = IconArchive.Id("cash") or ""
	wallet.amount.Text = comma(self._balance)
	self._gpWallet = wallet

	local tabs = GPLayoutKit.Tabs(theme, page.content, {
		widthPx = 172,
		heightPx = GP_TABS_H,
	}, self._gpShadows)
	self._gpTabs = tabs
	for _, tab in TABS do
		local tabId = tab.id
		-- Title Case, verbatim: this pack never shouts (pack law 5). The tab
		-- IDS and the handler are the classic build's, untouched.
		local label = string.upper(string.sub(tab.label, 1, 1)) .. string.lower(string.sub(tab.label, 2))
		tabs.Add(label, tabId, function()
			if self._tab == tabId then
				return
			end
			self:_SetTab(tabId)
		end)
	end

	local note = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "TabNote")
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.Position = UDim2.fromOffset(0, GP_NOTE_Y)
	note.Size = UDim2.new(1, -220, 0, 24)
	note.Parent = page.content
	self._noteLabel = note

	local list = Instance.new("ScrollingFrame")
	list.Name = "Ledger"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, GP_LIST_Y)
	list.Size = UDim2.new(1, 0, 1, -GP_LIST_Y)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = theme.Colors.Primary
	-- MUST clip: unclipped rows spilling past the frame is a known past bug
	-- here. The padding keeps a row's SOFT shadow off the clip edge so a plate
	-- is never sliced flat on the boundary.
	list.ClipsDescendants = true
	local pad = Instance.new("UIPadding")
	pad.Name = "gpLedgerPad"
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 18)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = list
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, GP_ROW_GAP),
	}).Parent = list
	list.Parent = page.content
	self._list = list

	self:_SetTab(self._tab)
end

-- The shared GP row shell: a petal plate (mirrored by list position), 48px
-- boxless icon, the display-face name over the quiet sub-line every ledger
-- already prints. Callers add the state chip and the value control.
function VendorScreen:_GPRow(order: number, icon: string, name: string, subText: string): Frame
	local theme = self:GetTheme()

	local row = gpPlate(theme, self._list, theme.Colors.SurfaceRaised, order, self._gpRowShadows)
	row.Name = "Row" .. order
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -20, 0, GP_ROW_H)

	local art = gpArt(theme, row, icon, 48)
	art.AnchorPoint = Vector2.new(0, 0.5)
	art.Position = UDim2.new(0, 16, 0.5, 0)
	art.ZIndex = 3

	local nameLabel = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Name")
	nameLabel.Text = name
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Position = UDim2.fromOffset(80, 10)
	nameLabel.Size = UDim2.new(1, -(80 + GP_PRICE_W + GP_CHIP_W + 60), 0, 28)
	nameLabel.ZIndex = 3
	nameLabel.Parent = row

	local sub = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Sub")
	sub.Text = subText
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	sub.Position = UDim2.fromOffset(80, 44)
	sub.Size = UDim2.new(1, -(80 + GP_PRICE_W + GP_CHIP_W + 60), 0, 22)
	sub.ZIndex = 3
	sub.Parent = row

	return row
end

function VendorScreen:_GPEmptyLine(text: string)
	local theme = self:GetTheme()
	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Empty")
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(1, -20, 0, 60)
	label.LayoutOrder = 1
	label.Parent = self._list
end

-- Quieten a value control IN PLACE (doc §11.2). The SHADOW retints with the
-- fill: a disabled pill still casting amber would be the grey-shadow bug
-- inverted, which is the one thing this pack cannot do.
function VendorScreen:_GPQuiet(price: GPPriceButton, blocked: boolean)
	local theme = self:GetTheme()
	local fill = if blocked then theme.Colors.Disabled else theme.Arcade.Gold
	price.pill.root.BackgroundColor3 = fill
	price.pill.shadow.Instance.Color = GPLayoutKit.Deepen(theme, fill, 1)
end

function VendorScreen:_GPRenderList()
	-- _gpPage is the definitive "was this tree built under GP" test. A style
	-- change flips LayoutKit() one frame BEFORE the deferred rebuild lands, so
	-- a render can arrive against the previous layout's instances.
	if not self._gpPage or not self._list then
		return
	end
	local theme = self:GetTheme()
	-- Release BEFORE the clear: _ClearList destroys the instances, and a
	-- destroyed UIShadow still owes the budget until its handle is released.
	GPLayoutKit.ReleaseShadows(self._gpRowShadows)
	self:_ClearList()

	local cashId = IconArchive.Id("cash") or ""

	if self._tab == "buy" then
		for index, item in self._stock :: { StockItem } do
			local soldOut = item.stock <= 0
			local blocked = soldOut or self._balance < item.price
			local subText = if soldOut
				then "Out of stock until the next firing"
				else string.format("In stock: %d", item.stock)
			local row = self:_GPRow(index, item.icon, gpTitleCase(item.name), subText)

			-- The chip says the stock state in WORDS; the pill says the price.
			-- Neither meaning rides on a tint alone.
			gpChip(
				theme,
				row,
				if soldOut then theme.Colors.Disabled else theme.Colors.Secondary,
				if soldOut then "Sold out" else string.format("%d left", item.stock),
				index + 1
			)

			local price = gpPriceButton(theme, row, self._gpRowShadows, function()
				self:_Buy(item)
			end)
			price.pill.icon.Image = cashId
			price.pill.amount.Text = comma(item.price)
			-- Blocked = dimmed IN PLACE, still tappable: the press juice plays,
			-- then _Buy answers with the reason (doc §11.1/§11.2).
			self:_GPQuiet(price, blocked)
		end
	elseif self._tab == "sell" then
		if #self._playerItems == 0 then
			self:_GPEmptyLine("Nothing left to sell.")
		end
		for index, item in self._playerItems :: { PlayerItem } do
			-- The full 60%-of-value arithmetic the arcade row prints, kept.
			local subText = string.format(
				"Sells for $%s — 60%% of its $%s value",
				comma(sellValueOf(item.value)),
				comma(item.value)
			)
			local row = self:_GPRow(
				index,
				item.icon,
				-- Retitled BEFORE the quantity is joined on, so the "x3" suffix
				-- is never capitalised along with the name.
				string.format("%s  x%d", gpTitleCase(item.name), item.qty),
				subText
			)

			gpChip(theme, row, theme.Colors.Secondary, "Sell", index + 1)

			local price = gpPriceButton(theme, row, self._gpRowShadows, function()
				self:_Sell(item)
			end)
			price.pill.icon.Image = cashId
			price.pill.amount.Text = comma(sellValueOf(item.value))
			self:_GPQuiet(price, false)
		end
	else
		if #self._buyback == 0 then
			self:_GPEmptyLine("Nothing sold yet this visit.")
		end
		for index, entry in self._buyback :: { BuybackItem } do
			local row = self:_GPRow(
				index,
				entry.icon,
				gpTitleCase(entry.name),
				string.format("Sold this visit — buy it back for $%s", comma(entry.price))
			)

			gpChip(theme, row, theme.Colors.Surface, "Buy back", index + 1)

			local price = gpPriceButton(theme, row, self._gpRowShadows, function()
				self:_Buyback(entry)
			end)
			price.pill.icon.Image = cashId
			price.pill.amount.Text = comma(entry.price)
			self:_GPQuiet(price, self._balance < entry.price)
		end
	end
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts live in
-- StyleKit.Capabilities and only fall when a handle is released — so every
-- GP shadow handle is handed back here.
function VendorScreen:_OnTeardown()
	GPLayoutKit.ReleaseShadows(self._gpRowShadows)
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpPage = nil
	self._gpTabs = nil
	self._gpWallet = nil
end

return VendorScreen
