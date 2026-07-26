--!strict
-- CRATE REVEAL — the crate-opening celebration, ported from Brick Game's
-- LobbyHud reveal overlay (+ CrateFx / CrateConfig) onto the Pottery Clash
-- chrome. The source choreography is preserved exactly (doc §5.3):
--
--   * first page  — the card drops from y −0.3 with 0.55s Bounce Out, its
--     scale pops to 1.28 in 0.16s Quad, then settles to 1 in 0.4s Back Out;
--   * later pages — no drop, just 0.75 → 1 in 0.35s Back Out;
--   * every page  — 36 confetti squares (8–14px, 6 theme colours) tween
--     1.6–2.4s LINEAR from above the top edge to below the bottom, with ±60px
--     horizontal drift and ±360° spin.
--
-- A multi-open (5×/10×) arrives as a queue and PAGES THROUGH THIS ONE CARD —
-- the CONTINUE button reads "NEXT (i/n)" until the last item. Page dots under
-- the card show where you are. Every confetti square, tween and RenderStepped
-- connection is torn down in _OnHide, so a closed reveal costs nothing.

local TweenService = game:GetService("TweenService")

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIAssets = require(script.Parent.Parent.Config.UIAssets)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIScreenBase = require(script.Parent.UIScreenBase)

export type RevealItem = {
	name: string,
	icon: string?,
	rarity: string?,
	note: string?,
}

-- Fixed px at the 1650×1020 baseline.
local CARD_W, CARD_H = 400, 470
local DOT = 12

local CARD_OFF = UDim2.new(0.5, 0, -0.3, 0)
local CARD_HOME = UDim2.fromScale(0.5, 0.5)
local DROP = TweenInfo.new(0.55, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SETTLE = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local REPOP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FIRST_FROM_SCALE = 0.55
local PAGE_FROM_SCALE = 0.75

local CONFETTI_COUNT = 36
local CONFETTI_MIN, CONFETTI_MAX = 8, 14
local CONFETTI_DRIFT = 60

-- Rarity ramp (doc §3.3: rarity colours tint stroke + label). The shop accent
-- rotation carries the low/mid tiers; the top two claim gold and magenta.
local RARITY_RANK: { [string]: number } = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
	Exclusive = 6,
}

local function rarityAccent(theme: Types.UITheme, rarity: string?): Color3
	local a = theme.Arcade
	local rank = RARITY_RANK[rarity or ""]
	if not rank then
		return a.Gold
	elseif rank >= 6 then
		return a.Magenta
	elseif rank == 5 then
		return a.Gold
	elseif rank == 4 then
		return a.ShopAccents[1]
	elseif rank == 3 then
		return a.ShopAccents[4]
	elseif rank == 2 then
		return a.Green
	end
	return a.ShopAccents[3]
end

-- Legendary and up get the golden icon variant and the gold sunburst.
local function isHighRarity(rarity: string?): boolean
	return (RARITY_RANK[rarity or ""] or 0) >= 5
end

local DEMO_ITEMS: { RevealItem } = {
	{ name = "Golden Kiln Throne", icon = "crown", rarity = "Legendary" },
	{ name = "Neon Gamer Chair", icon = "bolt", rarity = "Rare" },
	{ name = "Clay Throne", icon = "potion", rarity = "Uncommon", note = "Duplicate  +12 shards" },
}

local CrateRevealScreen = setmetatable({}, { __index = UIScreenBase })
CrateRevealScreen.__index = CrateRevealScreen

function CrateRevealScreen.new()
	local self = UIScreenBase.new("CrateRevealScreen", 62)
	self._items = DEMO_ITEMS :: { RevealItem }
	self._crateName = "GOLDEN CRATE"
	self._page = 1
	self._tweens = {} :: { Tween }
	self._confetti = {} :: { Frame }
	self._confettiTweens = {} :: { Tween }
	self._dots = {} :: { Frame }
	self._spinConn = nil :: RBXScriptConnection?
	return setmetatable(self, CrateRevealScreen)
end

-- ========================================================================
-- Build
-- ========================================================================

function CrateRevealScreen:_BuildContent()
	local theme = self:GetTheme()

	-- The §7.4 modal dim. Confetti is parented HERE (not to the card) so it
	-- rains across the whole screen, exactly like the source overlay.
	local dim = UIStyler.Frame("Dim")
	dim.BackgroundColor3 = theme.Colors.Overlay
	dim.BackgroundTransparency = 0.45
	dim.ZIndex = 60
	dim.Parent = self.Root
	self._dim = dim

	local card = UIStyler.Frame("Card")
	card.BackgroundColor3 = theme.Arcade.Panel
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = CARD_HOME
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.ZIndex = 61
	UIChrome.GlassGradient().Parent = card
	card.Parent = dim
	self._card = card

	-- The rarity ring: the ONE stroke this screen re-colours at runtime, because
	-- rarity IS the card's identity (doc §3.3). Policy thickness/mode still come
	-- from UIChrome — only the colour is swapped per item, in _RenderPage.
	local ring = UIChrome.Stroke(theme, "Arcade", "Selection")
	ring.Parent = card
	self._ring = ring

	local scale = Instance.new("UIScale")
	scale.Parent = card
	self._scale = scale

	local crate = UIChrome.Text("Crate", 22, theme.Arcade.IceBlue)
	crate.Text = ""
	crate.TextTruncate = Enum.TextTruncate.AtEnd
	crate.Position = UDim2.fromOffset(12, 14)
	crate.Size = UDim2.new(1, -24, 0, 26)
	crate.ZIndex = 62
	crate.Parent = card
	self._crateLabel = crate

	-- Art well: gold sunburst (doc §10, 45°/s, visibility-gated) behind the
	-- item icon.
	local art = UIStyler.Frame("Art")
	art.BackgroundColor3 = theme.Arcade.NearBlack
	art.AnchorPoint = Vector2.new(0.5, 0)
	art.Position = UDim2.new(0.5, 0, 0, 48)
	art.Size = UDim2.fromOffset(CARD_W - 48, 200)
	art.ZIndex = 62
	UIChrome.Stroke(theme, "Arcade").Parent = art
	art.Parent = card
	self._art = art

	local iconSlot = UIStyler.Frame("IconSlot")
	iconSlot.BackgroundTransparency = 1
	iconSlot.AnchorPoint = Vector2.new(0.5, 0.5)
	iconSlot.Position = UDim2.fromScale(0.5, 0.5)
	iconSlot.Size = UDim2.fromOffset(170, 170)
	iconSlot.ZIndex = 64
	iconSlot.Parent = art
	self._iconSlot = iconSlot

	local name = UIChrome.Text("Name", 26, theme.Colors.TextPrimary)
	name.Text = ""
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(12, 258)
	name.Size = UDim2.new(1, -24, 0, 34)
	name.ZIndex = 63
	name.Parent = card
	self._name = name

	local rarity = UIChrome.Text("Rarity", 20, theme.Arcade.Gold)
	rarity.Text = ""
	rarity.Position = UDim2.fromOffset(12, 294)
	rarity.Size = UDim2.new(1, -24, 0, 26)
	rarity.ZIndex = 63
	rarity.Parent = card
	self._rarity = rarity

	local note = UIChrome.Text("Note", 18, theme.Arcade.IceBlue)
	note.Text = ""
	note.Position = UDim2.fromOffset(12, 322)
	note.Size = UDim2.new(1, -24, 0, 24)
	note.ZIndex = 63
	note.Parent = card
	self._note = note

	local dots = UIStyler.Frame("Dots")
	dots.BackgroundTransparency = 1
	dots.AnchorPoint = Vector2.new(0.5, 0)
	dots.Position = UDim2.new(0.5, 0, 0, 354)
	dots.Size = UDim2.new(1, -24, 0, DOT + 4)
	dots.ZIndex = 63
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}).Parent = dots
	dots.Parent = card
	self._dotRow = dots

	self._continue = UIButtonComponent.new()
	self._continue:Create(card, {
		text = "CONTINUE",
		variant = "Green",
		size = UDim2.fromOffset(200, 52),
		position = UDim2.new(0.5, 0, 1, -18),
		anchorPoint = Vector2.new(0.5, 1),
		onClick = function()
			self:_Advance()
		end,
	})
	self._continue.Root.ZIndex = 63
end

-- ========================================================================
-- Confetti (doc §5.3) — fire-and-forget, but every square is tracked so hide
-- can destroy it mid-flight.
-- ========================================================================

function CrateRevealScreen:_ConfettiColors(): { Color3 }
	local theme = self:GetTheme()
	local colors = table.clone(theme.Arcade.Rainbow)
	table.insert(colors, theme.Arcade.Magenta) -- the source's sixth colour
	return colors
end

function CrateRevealScreen:_ClearConfetti()
	for _, tween in self._confettiTweens do
		tween:Cancel()
	end
	table.clear(self._confettiTweens)
	for _, square in self._confetti do
		square:Destroy()
	end
	table.clear(self._confetti)
end

function CrateRevealScreen:_BurstConfetti()
	local colors = self:_ConfettiColors()
	for _ = 1, CONFETTI_COUNT do
		local size = math.random(CONFETTI_MIN, CONFETTI_MAX)
		local square = UIStyler.Frame("Confetti")
		square.BackgroundColor3 = colors[math.random(#colors)]
		square.Position = UDim2.new(math.random(), 0, 0, -20)
		square.Size = UDim2.fromOffset(size, size)
		square.Rotation = math.random(0, 360)
		square.ZIndex = 65
		square.Parent = self._dim
		table.insert(self._confetti, square)

		local tween = TweenService:Create(
			square,
			TweenInfo.new(math.random(160, 240) / 100, Enum.EasingStyle.Linear),
			{
				Position = UDim2.new(
					square.Position.X.Scale,
					math.random(-CONFETTI_DRIFT, CONFETTI_DRIFT),
					1,
					40
				),
				Rotation = square.Rotation + math.random(-360, 360),
			}
		)
		table.insert(self._confettiTweens, tween)
		tween.Completed:Once(function()
			local index = table.find(self._confetti, square)
			if index then
				table.remove(self._confetti, index)
			end
			square:Destroy()
		end)
		tween:Play()
	end
end

-- ========================================================================
-- Paging
-- ========================================================================

function CrateRevealScreen:_CancelTweens()
	for _, tween in self._tweens do
		tween:Cancel()
	end
	table.clear(self._tweens)
end

-- The entrance beats. firstPage plays the full drop → pop → settle; later
-- queue pages get the quick re-pop only.
function CrateRevealScreen:_Animate(firstPage: boolean)
	self:_CancelTweens()
	local card, scale = self._card, self._scale
	if firstPage then
		card.Position = CARD_OFF
		scale.Scale = FIRST_FROM_SCALE
		local drop = TweenService:Create(card, DROP, { Position = CARD_HOME })
		table.insert(self._tweens, drop)
		drop.Completed:Once(function()
			if not self:IsVisible() then
				return
			end
			local pop = TweenService:Create(scale, POP, { Scale = 1.28 })
			table.insert(self._tweens, pop)
			pop.Completed:Once(function()
				if not self:IsVisible() then
					return
				end
				local settle = TweenService:Create(scale, SETTLE, { Scale = 1 })
				table.insert(self._tweens, settle)
				settle:Play()
			end)
			pop:Play()
		end)
		drop:Play()
	else
		card.Position = CARD_HOME
		scale.Scale = PAGE_FROM_SCALE
		local repop = TweenService:Create(scale, REPOP, { Scale = 1 })
		table.insert(self._tweens, repop)
		repop:Play()
	end
end

function CrateRevealScreen:_RenderDots()
	for _, dot in self._dots do
		dot:Destroy()
	end
	table.clear(self._dots)
	local count = #self._items
	self._dotRow.Visible = count > 1
	if count <= 1 then
		return
	end
	local theme = self:GetTheme()
	for i = 1, count do
		local dot = UIStyler.Frame("Dot" .. i)
		dot.BackgroundColor3 = if i == self._page then theme.Arcade.Gold else theme.Arcade.GreyOwned
		dot.Size = UDim2.fromOffset(DOT, DOT)
		dot.LayoutOrder = i
		dot.ZIndex = 64
		UIChrome.Corner("Arcade", "Pill").Parent = dot
		dot.Parent = self._dotRow
		table.insert(self._dots, dot)
	end
end

function CrateRevealScreen:_RenderPage(page: number, firstPage: boolean)
	local theme = self:GetTheme()
	local item = self._items[page]
	if not item then
		return
	end
	self._page = page

	local accent = rarityAccent(theme, item.rarity)
	local golden = isHighRarity(item.rarity)
	self._ring.Color = accent

	-- Text FIRST: even if art hiccups, the card still announces the prize.
	self._crateLabel.Text = self._crateName
	self._name.Text = item.name
	self._rarity.Text = string.upper(item.rarity or "")
	self._rarity.TextColor3 = accent
	self._note.Text = item.note or "NEW!"
	self._note.TextColor3 = if item.note then theme.Arcade.IceBlue else theme.Arcade.MoneyGreen

	if self._spinConn then
		self._spinConn:Disconnect()
		self._spinConn = nil
	end
	self._iconSlot:ClearAllChildren()
	if golden then
		-- Parented INTO the square icon slot so the sunburst stays round (the
		-- well itself is a wide rectangle) and the next page's ClearAllChildren
		-- takes it with the icon.
		local _, spin = UIAssets.SunburstBehind(self._iconSlot, theme.Arcade.SunburstGold, 0.55, 45)
		self._spinConn = spin
	end
	local icon = IconArchive.Image(self._iconSlot, item.icon or "chest", 140, { golden = golden })
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 65

	local last = page >= #self._items
	self._continue:SetContent({
		text = if last then "CONTINUE" else string.format("NEXT  (%d/%d)", page, #self._items),
		variant = if last then "Green" else "Blue",
	})

	self:_RenderDots()
	self:_Animate(firstPage)
	self:_BurstConfetti()
	self:_PlaySound("Success")
end

function CrateRevealScreen:_Advance()
	if self._page < #self._items then
		self:_RenderPage(self._page + 1, false)
	else
		self.ScreenController:HideScreen("crateReveal")
	end
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function CrateRevealScreen:_OnShow(data: any?)
	if type(data) == "table" then
		if type(data.items) == "table" and #data.items > 0 then
			self._items = data.items
		end
		if type(data.crateName) == "string" then
			self._crateName = data.crateName
		end
	end
	self:_ClearConfetti()
	self:_RenderPage(1, true)
end

function CrateRevealScreen:_OnHide()
	self:_CancelTweens()
	self:_ClearConfetti()
	if self._spinConn then
		self._spinConn:Disconnect()
		self._spinConn = nil
	end
	if self._card then
		self._card.Position = CARD_HOME
		self._scale.Scale = 1
	end
end

function CrateRevealScreen:Update(data: any)
	if self._built and self:IsVisible() then
		self:_OnShow(data)
	end
end

function CrateRevealScreen:Destroy()
	self:_OnHide()
	if self._continue then
		self._continue:Destroy()
		self._continue = nil
	end
	UIScreenBase.Destroy(self)
end

return CrateRevealScreen
