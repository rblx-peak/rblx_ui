--!strict
-- Shared data schemas used by both the server (validation) and the client
-- (rendering). Pure types — no runtime logic. Add new fields freely; remove
-- or rename only deliberately, since both domains compile against these.

-- Currency is colour-coded everywhere, no exceptions (design doc §3.3):
-- Cash = green, Bux = blue (Robux = magenta appears only on direct-Robux
-- price buttons, never as a wallet balance).
export type CurrencyId = "Cash" | "Bux"

export type CurrencyDef = {
	id: CurrencyId,
	nameKey: string,
	-- Emoji fallback glyph (used when the image fails to fetch).
	icon: string,
	-- Uploaded flat-cartoon icon ("rbxassetid://..."), shown boxless.
	iconId: string,
	-- Key into theme.Semantic.Currency, resolved client-side.
	colorToken: string,
	order: number,
}

export type ShopItemTag = "New" | "Sale" | "Rare" | "Limited" | "Popular"

export type ShopItem = {
	id: string,
	nameKey: string,
	descriptionKey: string?,
	-- "" means "no icon yet" — the client renders a monogram swatch placeholder.
	iconId: string,
	-- Preferred: a SEMANTIC key into the client's icon archive ("crate",
	-- "crown"). Content names a role and the archive picks the variant, so art
	-- can be re-skinned without touching item data. Wins over iconId.
	iconKey: string?,
	-- Ask the archive for this item's premium treatment (gold/rainbow/etc).
	iconGolden: boolean?,
	price: number,
	currencyType: CurrencyId,
	category: string,
	tags: { ShopItemTag }?,
}

export type ShopCategory = {
	id: string,
	nameKey: string,
	order: number,
}

export type CurrencyBalances = { [string]: number }

export type PurchaseResult = {
	success: boolean,
	messageKey: string,
	balances: CurrencyBalances?,
}

local Types = {}

return Types
