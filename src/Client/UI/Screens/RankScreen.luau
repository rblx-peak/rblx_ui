--!strict
-- Competitive rank — Pottery Clash arcade family (doc §7.4).
-- One modal card. Centrepiece: the current tier's medal (golden treatment for
-- the upper half of the ladder) over a spinning gold sunburst (doc §10), the
-- tier name at FredokaOne 44 (the doc's screen-header scale), and the gold RP
-- ruler. During a promotion series a five-pip strip appears — won pips are
-- green checks, lost pips red X (FredokaOne has no ✕ glyph, so a literal "X"),
-- pending pips grey — under a "PROMOTION SERIES" headline that flashes gold to
-- near-white on sin(t), the §5.3 urgency grammar (colour, never opacity).
-- Below: three season-stat tiles. Right: the full tier ladder, highest first,
-- with the current tier wearing the gold selection ring (§4.3).
--
-- The promo flash and the sunburst spin are the only per-frame work; both gate
-- on UIChrome.IsOnScreen and both connections drop in _OnHide (doc §5.4).

local RunService = game:GetService("RunService")

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIAssets = require(script.Parent.Parent.Config.UIAssets)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIProgressBarComponent = require(script.Parent.Parent.Components.UIProgressBarComponent)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPStudioKit = require(script.Parent.Parent.Framework.GPStudioKit)
local UITicker = require(script.Parent.Parent.Framework.UITicker)

type Promo = { active: boolean, wins: number, losses: number, needed: number }
type RankData = {
	tier: string,
	division: number,
	rp: number,
	rpMax: number,
	promo: Promo,
	seasonWins: number,
	seasonLosses: number,
	ladder: { string },
}

local CARD_W, CARD_H = 1180, 700
local CONTENT_W = CARD_W - 28
local CONTENT_H = CARD_H - 88
local CENTRE_W = 690
local LADDER_X = CENTRE_W + 16
local LADDER_W = CONTENT_W - LADDER_X
local PIP = 44
local PROMO_SERIES = 5
local LADDER_ROW_H = 62
local SCROLLBAR = 8

local ROMAN = { "I", "II", "III", "IV", "V" }

local function demoData(): RankData
	return {
		tier = "GOLD",
		division = 2,
		rp = 62,
		rpMax = 100,
		promo = { active = true, wins = 2, losses = 1, needed = 3 },
		seasonWins = 34,
		seasonLosses = 25,
		ladder = { "BRONZE", "SILVER", "GOLD", "PLATINUM", "DIAMOND", "CHAMPION" },
	}
end

local function tintIcon(icon: GuiObject, color: Color3)
	if icon:IsA("ImageLabel") then
		icon.ImageColor3 = color
	elseif icon:IsA("TextLabel") then
		icon.TextColor3 = color
	end
end

local RankScreen = setmetatable({}, { __index = UIScreenBase })
RankScreen.__index = RankScreen

function RankScreen.new()
	local self = UIScreenBase.new("RankScreen", 6)
	self._data = demoData()
	self._burst = nil :: ImageLabel?
	self._spinConn = nil :: RBXScriptConnection?
	self._tickConn = nil :: RBXScriptConnection?
	self._phase = 0
	self._emblemIcon = nil :: GuiObject?
	return setmetatable(self, RankScreen)
end

function RankScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function RankScreen:_TierIndex(tier: string): number
	for i, name in (self._data :: RankData).ladder do
		if name == tier then
			return i
		end
	end
	return 1
end

-- Golden medal treatment for the ladder's upper half ("high tiers").
function RankScreen:_IsHighTier(tier: string): boolean
	local ladder = (self._data :: RankData).ladder
	return self:_TierIndex(tier) >= math.ceil(#ladder / 2)
end

function RankScreen:_BuildContent()
	-- GP layout language: the matte season board (see _BuildGPLayout below);
	-- the classic arcade modal build stays untouched.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "COMPETITIVE RANK",
		sizePx = Vector2.new(CARD_W, CARD_H),
		onClose = function()
			self.ScreenController:HideScreen("rank")
		end,
	})
	self._modal = modal
	local content = modal.content

	-- ---- centrepiece --------------------------------------------------
	local emblemSlot = UIStyler.Frame("EmblemSlot")
	emblemSlot.BackgroundTransparency = 1
	emblemSlot.AnchorPoint = Vector2.new(0.5, 0)
	emblemSlot.Position = UDim2.fromOffset(CENTRE_W // 2, 8)
	emblemSlot.Size = UDim2.fromOffset(210, 210)
	emblemSlot.Parent = content
	self._emblemSlot = emblemSlot
	local burst, spin = UIAssets.SunburstBehind(emblemSlot, theme.Arcade.SunburstGold, 0.5, 45)
	self._burst = burst
	self._spinConn = spin

	local tierName = UIChrome.Text("TierName", 44, theme.Arcade.Gold)
	tierName.Position = UDim2.fromOffset(0, 224)
	tierName.Size = UDim2.fromOffset(CENTRE_W, 50)
	tierName.Parent = content
	self._tierLabel = tierName

	self._rpBar = UIProgressBarComponent.new()
	self._rpBar:Create(content, {
		value = 0,
		maxValue = 1,
		showText = true,
		size = UDim2.fromOffset(420, 28),
		position = UDim2.fromOffset((CENTRE_W - 420) // 2 - 20, 288),
	})
	local rpTag = UIChrome.Text("RPTag", 20, theme.Arcade.SunburstGold)
	rpTag.Text = "RP"
	rpTag.TextXAlignment = Enum.TextXAlignment.Left
	rpTag.Position = UDim2.fromOffset((CENTRE_W - 420) // 2 - 20 + 430, 288)
	rpTag.Size = UDim2.fromOffset(50, 28)
	rpTag.Parent = content

	-- ---- promotion series strip --------------------------------------
	local promo = UIStyler.Frame("Promo")
	promo.BackgroundTransparency = 1
	promo.Position = UDim2.fromOffset((CENTRE_W - 600) // 2, 332)
	promo.Size = UDim2.fromOffset(600, 112)
	promo.Parent = content
	self._promoFrame = promo

	local promoTitle = UIChrome.Text("PromoTitle", 22, theme.Arcade.Gold)
	promoTitle.Text = "PROMOTION SERIES"
	promoTitle.Size = UDim2.new(1, 0, 0, 26)
	promoTitle.Parent = promo
	self._promoTitle = promoTitle

	local pipRow = UIStyler.Frame("Pips")
	pipRow.BackgroundTransparency = 1
	pipRow.Position = UDim2.fromOffset(0, 34)
	pipRow.Size = UDim2.new(1, 0, 0, PIP)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 14),
	}).Parent = pipRow
	pipRow.Parent = promo
	self._pipRow = pipRow

	local promoCaption = UIChrome.BodyText("PromoCaption", 14, theme.Colors.TextSecondary)
	promoCaption.Position = UDim2.fromOffset(0, 88)
	promoCaption.Size = UDim2.new(1, 0, 0, 18)
	promoCaption.Parent = promo
	self._promoCaption = promoCaption

	-- Shown instead of the strip when not in promos.
	local idle = UIChrome.BodyText("PromoIdle", 15, theme.Colors.TextSecondary)
	idle.Position = UDim2.fromOffset((CENTRE_W - 600) // 2, 372)
	idle.Size = UDim2.fromOffset(600, 22)
	idle.Parent = content
	self._promoIdle = idle

	-- ---- season stats -------------------------------------------------
	local stats = UIStyler.Frame("Stats")
	stats.BackgroundTransparency = 1
	stats.Position = UDim2.fromOffset((CENTRE_W - (200 * 3 + 32)) // 2, 462)
	stats.Size = UDim2.fromOffset(200 * 3 + 32, 92)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 16),
	}).Parent = stats
	stats.Parent = content

	self._statValues = {} :: { [string]: TextLabel }
	for order, stat in { { key = "wins", label = "WINS", color = theme.Arcade.Green },
		{ key = "losses", label = "LOSSES", color = theme.Arcade.Red },
		{ key = "winrate", label = "WINRATE", color = theme.Arcade.Gold } } do
		local tile = UIStyler.Frame("Stat_" .. stat.key)
		tile.BackgroundColor3 = theme.Arcade.NearBlack
		tile.BackgroundTransparency = 0
		tile.Size = UDim2.fromOffset(200, 92)
		tile.LayoutOrder = order
		UIChrome.Stroke(theme, "Arcade").Parent = tile
		UIChrome.GlassGradient().Parent = tile
		tile.Parent = stats

		local caption = UIChrome.Text("Caption", 16, theme.Colors.TextSecondary)
		caption.Text = stat.label
		caption.Position = UDim2.fromOffset(0, 10)
		caption.Size = UDim2.new(1, 0, 0, 20)
		caption.Parent = tile

		local value = UIChrome.Text("Value", 34, stat.color)
		value.Position = UDim2.fromOffset(0, 36)
		value.Size = UDim2.new(1, 0, 0, 42)
		value.Parent = tile
		self._statValues[stat.key] = value
	end

	-- ---- ladder -------------------------------------------------------
	local ladder = UIChrome.Panel(theme, "Arcade", "Ladder")
	ladder.Position = UDim2.fromOffset(LADDER_X, 0)
	ladder.Size = UDim2.fromOffset(LADDER_W, CONTENT_H)
	ladder.Parent = content

	local ladderTitle = UIChrome.Text("LadderTitle", 20, theme.Arcade.Gold)
	ladderTitle.Text = "SEASON LADDER"
	ladderTitle.TextXAlignment = Enum.TextXAlignment.Left
	ladderTitle.Position = UDim2.fromOffset(16, 12)
	ladderTitle.Size = UDim2.new(1, -32, 0, 24)
	ladderTitle.Parent = ladder

	local ladderList = Instance.new("ScrollingFrame")
	ladderList.Name = "LadderList"
	ladderList.BackgroundTransparency = 1
	ladderList.BorderSizePixel = 0
	ladderList.Position = UDim2.fromOffset(12, 46)
	ladderList.Size = UDim2.new(1, -24, 1, -58)
	ladderList.CanvasSize = UDim2.new()
	ladderList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	ladderList.ScrollingDirection = Enum.ScrollingDirection.Y
	ladderList.ScrollBarThickness = SCROLLBAR
	ladderList.ScrollBarImageColor3 = theme.Arcade.Gold
	ladderList.Parent = ladder
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 8),
	}).Parent = ladderList
	self._ladderList = ladderList

	self:_RenderAll()
end

function RankScreen:_RenderAll()
	if self:LayoutKit() == "GP" then
		self:_GPRenderCentre()
		self:_GPRenderPromo()
		self:_GPRenderStats()
		self:_GPRenderLadder()
		return
	end
	self:_RenderCentre()
	self:_RenderPromo()
	self:_RenderStats()
	self:_RenderLadder()
end

function RankScreen:_RenderCentre()
	local data: RankData = self._data

	if self._emblemIcon then
		self._emblemIcon:Destroy()
	end
	local emblem = IconArchive.Image(self._emblemSlot, "medal", 150, {
		golden = self:_IsHighTier(data.tier),
	})
	emblem.AnchorPoint = Vector2.new(0.5, 0.5)
	emblem.Position = UDim2.fromScale(0.5, 0.5)
	emblem.ZIndex = 3
	self._emblemIcon = emblem

	self._tierLabel.Text = string.format("%s %s", data.tier, ROMAN[data.division] or "")
	self._rpBar:Set(data.rp, math.max(data.rpMax, 1))
end

function RankScreen:_RenderPromo()
	local theme = self:GetTheme()
	local data: RankData = self._data
	local promo = data.promo

	self._promoFrame.Visible = promo.active
	self._promoIdle.Visible = not promo.active
	if not promo.active then
		self._promoIdle.Text = string.format("REACH %d RP TO START A PROMOTION SERIES", data.rpMax)
		-- The flash may have left the title mid-blend; park it back on gold.
		self._promoTitle.TextColor3 = theme.Arcade.Gold
		return
	end

	self._promoCaption.Text = string.format("WIN %d OF %d TO ADVANCE", promo.needed, PROMO_SERIES)

	for _, child in self._pipRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i = 1, PROMO_SERIES do
		local pip = UIStyler.Frame("Pip" .. i)
		pip.Size = UDim2.fromOffset(PIP, PIP)
		pip.LayoutOrder = i
		UIChrome.Corner("Arcade", "Pill").Parent = pip -- win pips are the arcade's round exception (doc §8)
		UIChrome.GlassGradient().Parent = pip

		if i <= promo.wins then
			pip.BackgroundColor3 = theme.Arcade.Green
			UIChrome.Stroke(theme, "Arcade").Parent = pip
			local check = IconArchive.Image(pip, "check", 26)
			check.AnchorPoint = Vector2.new(0.5, 0.5)
			check.Position = UDim2.fromScale(0.5, 0.5)
			tintIcon(check, Color3.new(1, 1, 1))
		elseif i <= promo.wins + promo.losses then
			pip.BackgroundColor3 = theme.Arcade.Red
			UIChrome.Stroke(theme, "Arcade").Parent = pip
			local x = UIChrome.Text("X", 24, Color3.new(1, 1, 1))
			x.Text = "X"
			x.Size = UDim2.fromScale(1, 1)
			x.Parent = pip
		else
			pip.BackgroundColor3 = theme.Arcade.NearBlack
			UIStyler.Stroke(theme.Arcade.GreyOwned, 2, 0).Parent = pip -- pending = empty grey pip (§8)
		end
		pip.Parent = self._pipRow
	end
end

function RankScreen:_RenderStats()
	local data: RankData = self._data
	local games = data.seasonWins + data.seasonLosses
	local winrate = games > 0 and math.floor(data.seasonWins / games * 100 + 0.5) or 0
	self._statValues.wins.Text = tostring(data.seasonWins)
	self._statValues.losses.Text = tostring(data.seasonLosses)
	self._statValues.winrate.Text = winrate .. "%"
end

function RankScreen:_RenderLadder()
	local theme = self:GetTheme()
	local data: RankData = self._data

	for _, child in self._ladderList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	-- Highest tier first — a ladder is read top-down.
	local currentIndex = self:_TierIndex(data.tier)
	for order = 1, #data.ladder do
		local index = #data.ladder - order + 1
		local tier = data.ladder[index]
		local isCurrent = index == currentIndex

		local root = UIStyler.Frame("Tier_" .. tier)
		root.BackgroundTransparency = 1
		root.Size = UDim2.new(1, -SCROLLBAR, 0, LADDER_ROW_H)
		root.LayoutOrder = order
		root.Parent = self._ladderList

		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 1
		hit.Parent = root

		local surface = UIStyler.Frame("Surface")
		surface.BackgroundColor3 = if isCurrent then theme.Arcade.NearBlack2 else theme.Arcade.Row
		surface.BackgroundTransparency = if isCurrent then 0 else theme.Arcade.RowTransparency
		surface.AnchorPoint = Vector2.new(0.5, 0.5)
		surface.Position = UDim2.fromScale(0.5, 0.5)
		surface.Size = UDim2.fromScale(1, 1)
		surface.ZIndex = 2
		UIChrome.Stroke(theme, "Arcade", isCurrent and "Selection" or "Panel").Parent = surface
		UIChrome.GlassGradient().Parent = surface
		surface.Parent = root

		local medal = IconArchive.Image(surface, "medal", 36, { golden = self:_IsHighTier(tier) })
		medal.AnchorPoint = Vector2.new(0, 0.5)
		medal.Position = UDim2.new(0, 12, 0.5, 0)
		if index > currentIndex then
			-- Unreached tiers dim in place (doc §11.2).
			if medal:IsA("ImageLabel") then
				medal.ImageTransparency = 0.45
			end
		end

		local name = UIChrome.Text("Name", 22, isCurrent and theme.Arcade.Gold or theme.Colors.TextPrimary)
		name.Text = tier
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(62, 0)
		name.Size = UDim2.new(1, -200, 1, 0)
		name.Parent = surface

		if isCurrent then
			local here = UIChrome.Text("Here", 13, theme.Arcade.Gold)
			here.Text = "YOU ARE HERE"
			here.TextXAlignment = Enum.TextXAlignment.Right
			here.AnchorPoint = Vector2.new(1, 0.5)
			here.Position = UDim2.new(1, -12, 0.5, 0)
			here.Size = UDim2.fromOffset(130, 20)
			here.Parent = surface
		end

		hit.Activated:Connect(function()
			if isCurrent then
				self:_Toast("You are here — " .. tier .. " " .. (ROMAN[data.division] or "") .. ".", "Info")
			elseif index < currentIndex then
				self:_Toast(tier .. " is already behind you.", "Info")
			else
				self:_Toast(string.format("Climb %d more tier%s to reach %s.",
					index - currentIndex, index - currentIndex == 1 and "" or "s", tier), "Info")
			end
		end)
		-- Animate LAST, after the final colours.
		UIChrome.Animate(theme, hit, surface)
	end
end

-- The promo headline flash: gold blending toward near-white on sin(t), the
-- §5.3 urgency treatment (colour + weight, never opacity), on-screen gated.
function RankScreen:_StartTicker()
	-- GP runs its ambient work on the ONE shared Heartbeat (UITicker); a
	-- per-screen RunService connection is a rejected pattern under this pack.
	if self:LayoutKit() == "GP" then
		self:_GPStartTicker()
		return
	end
	if self._tickConn then
		return
	end
	self._tickConn = RunService.RenderStepped:Connect(function(dt: number)
		local card = self._modal and self._modal.card
		if not card or not UIChrome.IsOnScreen(card) then
			return
		end
		local data: RankData = self._data
		if not data.promo.active then
			return
		end
		self._phase += dt
		local theme = self:GetTheme()
		local blend = 0.5 + 0.5 * math.sin(self._phase * 5)
		self._promoTitle.TextColor3 = theme.Arcade.Gold:Lerp(Color3.new(1, 1, 1), blend * 0.8)
	end)
end

function RankScreen:_StopTicker()
	if self._gpTickerStop then
		self._gpTickerStop()
		self._gpTickerStop = nil
	end
	if self._tickConn then
		self._tickConn:Disconnect()
		self._tickConn = nil
	end
end

function RankScreen:_Apply(data: any)
	local current: RankData = self._data
	self._data = {
		tier = data.tier or current.tier,
		division = data.division or current.division,
		rp = data.rp or current.rp,
		rpMax = data.rpMax or current.rpMax,
		promo = data.promo or current.promo,
		seasonWins = data.seasonWins or current.seasonWins,
		seasonLosses = data.seasonLosses or current.seasonLosses,
		ladder = data.ladder or current.ladder,
	}
end

function RankScreen:_OnShow(data: any?)
	if data then
		self:_Apply(data)
		self:_RenderAll()
	end
	if self._burst and not self._spinConn then
		self._spinConn = UIChrome.Spin(self._burst, 45)
	end
	self:_StartTicker()
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function RankScreen:_OnHide()
	self:_StopTicker()
	if self._spinConn then
		self._spinConn:Disconnect()
		self._spinConn = nil
	end
end

function RankScreen:Update(data: any)
	if not data then
		return
	end
	self:_Apply(data)
	if self._built then
		self:_RenderAll()
	end
end

-- ========================================================================
-- GP layout (theme.LayoutKit == "GP") — THE SEASON BOARD, in the pack's
-- MATTE dialect: cream paper, clay speckle, sage hairlines.
--
-- ANTI-CONDESCENSION LEDGER — every reading the arcade page carries:
--   the tier medal (golden treatment for the ladder's upper half) over its
--   slow sunburst · tier name AND division numeral · the RP ruler with its
--   value/max readout and its RP tag · the promotion strip: headline, ALL
--   FIVE pips in their three states (won / lost / pending), and the
--   "win N of 5" caption · the idle line when no series is running · all
--   THREE season tiles (wins, losses, win rate) · the FULL season ladder,
--   highest first, each row with its medal, its name, the unreached dim, the
--   "you are here" marker on the current tier and its explaining tap.
-- ADDED: the win-rate tile now also prints the raw record ("34 – 25"), and
-- the RP meter prints its percentage. Nothing was traded for either.
--
-- MOTION: the sunburst spin and the promotion flash share ONE UITicker
-- handler bound to the page, so a style rebuild unregisters it — there is no
-- RunService connection anywhere in this branch. The flash is a COLOUR
-- breathe between ink and a deepened rose, capped at half, because the pack's
-- near-white measures 2.14:1 and may never carry a headline.
-- ========================================================================

local GP_PAGE = Vector2.new(CARD_W, CARD_H + 48)
local GP_SCROLL_PAD = 10
local GP_PIP = 46
local GP_LADDER_ROW_H = 66
local GP_STAT_W = 200
local GP_STAT_H = 96
local GP_SPIN_DEGREES = 12 -- soft, not the arcade's 45°/s
local GP_FLASH_CAP = 0.5

function RankScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	local spacing = theme.Spacing

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Competitive Rank",
		subtitleText = "Where you stand this season, and what it took.",
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("rank")
		end,
	})
	self._gpShadows = page.shadows
	self._modal = { content = page.content, card = page.panel } :: any
	local content = page.content

	-- ---- centrepiece --------------------------------------------------
	local emblemSlot = UIStyler.Frame("GPEmblemSlot")
	emblemSlot.BackgroundTransparency = 1
	emblemSlot.AnchorPoint = Vector2.new(0.5, 0)
	emblemSlot.Position = UDim2.fromOffset(CENTRE_W // 2, 6)
	emblemSlot.Size = UDim2.fromOffset(210, 210)
	emblemSlot.Parent = content
	self._gpEmblemSlot = emblemSlot

	-- The pack's own soft sunburst, in butter at high transparency — a warm
	-- bloom behind the medal rather than the arcade's hard gold rays.
	local burst = GPLayoutKit.Slice(theme, "sunburstSoft", theme.Arcade.SunburstGold, "Sunburst")
	burst.ImageTransparency = 0.62
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.5)
	burst.Size = UDim2.fromScale(1.35, 1.35)
	burst.ZIndex = 2
	burst.Parent = emblemSlot
	self._gpBurst = burst

	local tierName = GPLayoutKit.Text(theme, 40, theme.Colors.TextPrimary, "TierName")
	tierName.Position = UDim2.fromOffset(0, 220)
	tierName.Size = UDim2.fromOffset(CENTRE_W, 50)
	tierName.RichText = false
	tierName.Parent = content
	self._gpTierLabel = tierName

	self._gpRpMeter = GPStudioKit.Meter(theme, content, {
		value = 0,
		maxValue = 1,
		tone = theme.Colors.Primary,
		heightPx = 28,
		sizeUDim = UDim2.fromOffset(420, 28),
		position = UDim2.fromOffset((CENTRE_W - 420) // 2 - 20, 284),
		name = "RPMeter",
	})

	local rpTag = GPLayoutKit.BodyText(theme, 20, GPLayoutKit.Deepen(theme, theme.Arcade.Gold, 1), "RPTag")
	rpTag.Text = "RP"
	rpTag.TextXAlignment = Enum.TextXAlignment.Left
	rpTag.Position = UDim2.fromOffset((CENTRE_W - 420) // 2 - 20 + 430, 284)
	rpTag.Size = UDim2.fromOffset(50, 28)
	rpTag.Parent = content

	-- ---- promotion series strip --------------------------------------
	local promo = UIStyler.Frame("GPPromo")
	promo.BackgroundTransparency = 1
	promo.Position = UDim2.fromOffset((CENTRE_W - 600) // 2, 328)
	promo.Size = UDim2.fromOffset(600, 116)
	promo.Parent = content
	self._gpPromoFrame = promo

	local promoTitle = GPLayoutKit.Text(theme, 22, theme.Colors.TextPrimary, "PromoTitle")
	promoTitle.Text = "Promotion series"
	promoTitle.Size = UDim2.new(1, 0, 0, 26)
	promoTitle.Parent = promo
	self._gpPromoTitle = promoTitle

	local pipRow = UIStyler.Frame("Pips")
	pipRow.BackgroundTransparency = 1
	pipRow.Position = UDim2.fromOffset(0, 34)
	pipRow.Size = UDim2.new(1, 0, 0, GP_PIP)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, spacing.M),
	}).Parent = pipRow
	pipRow.Parent = promo
	self._gpPipRow = pipRow

	local promoCaption = GPLayoutKit.BodyText(theme, 14, theme.Colors.TextSecondary, "PromoCaption")
	promoCaption.Position = UDim2.fromOffset(0, 90)
	promoCaption.Size = UDim2.new(1, 0, 0, 20)
	promoCaption.Parent = promo
	self._gpPromoCaption = promoCaption

	local idle = GPLayoutKit.BodyText(theme, 15, theme.Colors.TextSecondary, "PromoIdle")
	idle.Position = UDim2.fromOffset((CENTRE_W - 600) // 2, 372)
	idle.Size = UDim2.fromOffset(600, 24)
	idle.Parent = content
	self._gpPromoIdle = idle

	-- ---- season stats -------------------------------------------------
	local stats = UIStyler.Frame("GPStats")
	stats.BackgroundTransparency = 1
	stats.Position = UDim2.fromOffset((CENTRE_W - (GP_STAT_W * 3 + 32)) // 2, 458)
	stats.Size = UDim2.fromOffset(GP_STAT_W * 3 + 32, GP_STAT_H)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, spacing.M + 2),
	}).Parent = stats
	stats.Parent = content

	self._gpStatValues = {} :: { [string]: TextLabel }
	self._gpStatNotes = {} :: { [string]: TextLabel }
	local tiles = {
		{ key = "wins", label = "Wins", tone = theme.Arcade.Green },
		{ key = "losses", label = "Losses", tone = theme.Arcade.Red },
		{ key = "winrate", label = "Win rate", tone = theme.Arcade.Gold },
	}
	for order, stat in tiles do
		local tile = GPStudioKit.Paper(theme, stats, {
			name = "GPStat_" .. stat.key,
			index = order,
			fill = theme.Colors.SurfaceRaised,
			shadow = "sm",
		}, self._gpShadows)
		tile.Size = UDim2.fromOffset(GP_STAT_W, GP_STAT_H)
		tile.LayoutOrder = order

		local caption = GPLayoutKit.BodyText(theme, 15, theme.Colors.TextSecondary, "Caption")
		caption.Text = stat.label
		caption.Position = UDim2.fromOffset(0, 8)
		caption.Size = UDim2.new(1, 0, 0, 20)
		caption.ZIndex = 3
		caption.Parent = tile

		-- The tone is deepened along its own hue: matcha and butter are LIGHT
		-- fills and would not carry as 32px numerals on cream paper.
		local value = GPLayoutKit.Text(theme, 32, GPLayoutKit.Deepen(theme, stat.tone, 1), "Value")
		value.Position = UDim2.fromOffset(0, 30)
		value.Size = UDim2.new(1, 0, 0, 40)
		value.RichText = false
		value.ZIndex = 3
		value.Parent = tile
		self._gpStatValues[stat.key] = value

		local note = GPLayoutKit.BodyText(theme, 13, theme.Colors.TextSecondary, "Note")
		note.Position = UDim2.fromOffset(0, 70)
		note.Size = UDim2.new(1, 0, 0, 18)
		note.ZIndex = 3
		note.Parent = tile
		self._gpStatNotes[stat.key] = note
	end

	-- ---- ladder -------------------------------------------------------
	local ladder = GPStudioKit.Paper(theme, content, {
		name = "GPLadder",
		index = 1,
		fill = theme.Studio.Card,
		shadow = "md",
	}, self._gpShadows)
	ladder.Position = UDim2.fromOffset(LADDER_X, 0)
	ladder.Size = UDim2.fromOffset(LADDER_W, CONTENT_H)

	local ladderTitle = GPStudioKit.Heading(theme, ladder, "Season ladder", {
		sizePx = theme.TextSizes.Subtitle,
		heightPx = 26,
		name = "LadderTitle",
	})
	ladderTitle.Position = UDim2.fromOffset(spacing.M, spacing.M)
	ladderTitle.Size = UDim2.new(1, -spacing.M * 2, 0, 26)
	ladderTitle.ZIndex = 3

	GPStudioKit.Rule(theme, ladder, { inset = spacing.M }).Position = UDim2.fromOffset(spacing.M, 46)

	local ladderList = GPStudioKit.Scroller(theme, ladder, {
		name = "GPLadderList",
		padPx = GP_SCROLL_PAD,
	})
	ladderList.Position = UDim2.fromOffset(spacing.S, 54)
	ladderList.Size = UDim2.new(1, -spacing.S * 2, 1, -66)
	ladderList.ZIndex = 3
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, theme.Spacing.S),
	}).Parent = ladderList
	self._gpLadderList = ladderList

	self:_RenderAll()
end

function RankScreen:_GPRenderCentre()
	local theme = self:GetTheme()
	local data: RankData = self._data

	if self._gpEmblemIcon then
		self._gpEmblemIcon:Destroy()
	end
	local emblem = GPStudioKit.Icon(theme, self._gpEmblemSlot, "medal", 150, {
		golden = self:_IsHighTier(data.tier),
	})
	emblem.AnchorPoint = Vector2.new(0.5, 0.5)
	emblem.Position = UDim2.fromScale(0.5, 0.5)
	emblem.ZIndex = 4
	self._gpEmblemIcon = emblem

	self._gpTierLabel.Text = GPStudioKit.SoftCase(string.format("%s %s", data.tier, ROMAN[data.division] or ""))
	local rpMax = math.max(data.rpMax, 1)
	self._gpRpMeter.Set(data.rp, rpMax, string.format("%d / %d", data.rp, rpMax))
	self._gpRpMeter.name.Text = string.format("%d%%", math.floor(math.clamp(data.rp / rpMax, 0, 1) * 100 + 0.5))
	self._gpRpMeter.name.Visible = true
end

function RankScreen:_GPRenderPromo()
	local theme = self:GetTheme()
	local data: RankData = self._data
	local promo = data.promo

	self._gpPromoFrame.Visible = promo.active
	self._gpPromoIdle.Visible = not promo.active
	if not promo.active then
		self._gpPromoIdle.Text = string.format("Reach %d RP to start a promotion series.", data.rpMax)
		-- The flash may have left the headline mid-blend; park it back on ink.
		self._gpPromoTitle.TextColor3 = theme.Colors.TextPrimary
		return
	end

	self._gpPromoCaption.Text = string.format("Win %d of %d to advance.", promo.needed, PROMO_SERIES)

	for _, child in self._gpPipRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	-- All five pips, in all three states. A won pip is matcha with a check, a
	-- lost pip is the pack's soft coral with a literal "X" (FredokaOne has no
	-- ✕ glyph), a pending pip is blush behind a sage ring. Glyphs are INK —
	-- the arcade build paints them pure white, which this pack forbids.
	for i = 1, PROMO_SERIES do
		local won = i <= promo.wins
		local lost = not won and i <= promo.wins + promo.losses
		local fill = if won then theme.Arcade.Green elseif lost then theme.Arcade.Red else theme.Colors.Surface

		local pip = UIStyler.Frame("Pip" .. i)
		pip.BackgroundColor3 = fill
		pip.BackgroundTransparency = 0
		pip.Size = UDim2.fromOffset(GP_PIP, GP_PIP)
		pip.LayoutOrder = i
		pip.Parent = self._gpPipRow
		UIStyler.Corner(theme.Radii.Pill).Parent = pip
		GPLayoutKit.SoftStroke(theme, pip, fill)

		if won then
			local check = GPStudioKit.Icon(theme, pip, "check", 26, { tint = theme.Colors.TextPrimary })
			check.AnchorPoint = Vector2.new(0.5, 0.5)
			check.Position = UDim2.fromScale(0.5, 0.5)
			check.ZIndex = 3
		elseif lost then
			local mark = GPLayoutKit.Text(theme, 24, theme.Colors.TextPrimary, "X")
			mark.Text = "X"
			mark.Size = UDim2.fromScale(1, 1)
			mark.ZIndex = 3
			mark.Parent = pip
		else
			local pending = GPLayoutKit.BodyText(theme, 18, theme.Colors.TextSecondary, "Pending")
			pending.Text = tostring(i)
			pending.Size = UDim2.fromScale(1, 1)
			pending.ZIndex = 3
			pending.Parent = pip
		end
	end
end

function RankScreen:_GPRenderStats()
	local data: RankData = self._data
	local games = data.seasonWins + data.seasonLosses
	local winrate = if games > 0 then math.floor(data.seasonWins / games * 100 + 0.5) else 0
	self._gpStatValues.wins.Text = tostring(data.seasonWins)
	self._gpStatValues.losses.Text = tostring(data.seasonLosses)
	self._gpStatValues.winrate.Text = winrate .. "%"
	-- The sub-line is ADDITIVE: the arcade tiles show three numbers, these
	-- three show the same numbers plus what they were derived from.
	self._gpStatNotes.wins.Text = string.format("of %d games", games)
	self._gpStatNotes.losses.Text = string.format("of %d games", games)
	self._gpStatNotes.winrate.Text = string.format("%d – %d", data.seasonWins, data.seasonLosses)
end

function RankScreen:_GPRenderLadder()
	local theme = self:GetTheme()
	local spacing = theme.Spacing
	local data: RankData = self._data

	for _, child in self._gpLadderList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	-- Highest tier first — a ladder is read top-down.
	local currentIndex = self:_TierIndex(data.tier)
	for order = 1, #data.ladder do
		local index = #data.ladder - order + 1
		local tier = data.ladder[index]
		local isCurrent = index == currentIndex

		local root = Instance.new("TextButton")
		root.Name = "GPTier_" .. tier
		root.BackgroundTransparency = 1
		root.Text = ""
		root.AutoButtonColor = false
		root.Size = UDim2.new(1, -SCROLLBAR, 0, GP_LADDER_ROW_H)
		root.LayoutOrder = order
		root.Parent = self._gpLadderList

		local plate = GPStudioKit.Paper(theme, root, {
			name = "Plate",
			index = order,
			fill = if isCurrent then theme.Colors.SurfaceRaised else theme.Colors.Surface,
			strokeTint = if isCurrent then theme.Arcade.Gold else nil,
			strokeThickness = if isCurrent then 3 else nil,
		})
		plate.Size = UDim2.fromScale(1, 1)

		local medal = GPStudioKit.Icon(theme, plate, "medal", 38, {
			golden = self:_IsHighTier(tier),
			-- Unreached tiers dim in place (doc §11.2), never disappear.
			dim = if index > currentIndex then 0.45 else nil,
		})
		medal.AnchorPoint = Vector2.new(0, 0.5)
		medal.Position = UDim2.new(0, spacing.M, 0.5, 0)
		medal.ZIndex = 3

		local name = GPLayoutKit.Text(theme, 22,
			if isCurrent then GPLayoutKit.Deepen(theme, theme.Arcade.Gold, 1) else theme.Colors.TextPrimary, "Name")
		name.Text = GPStudioKit.SoftCase(tier)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(64, 0)
		name.Size = UDim2.new(1, -200, 1, 0)
		name.RichText = false
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.ZIndex = 3
		name.Parent = plate

		if isCurrent then
			local here = GPLayoutKit.BodyText(theme, 13, GPLayoutKit.Deepen(theme, theme.Arcade.Gold, 1), "Here")
			here.Text = "You are here"
			here.TextXAlignment = Enum.TextXAlignment.Right
			here.AnchorPoint = Vector2.new(1, 0.5)
			here.Position = UDim2.new(1, -spacing.M, 0.5, 0)
			here.Size = UDim2.fromOffset(130, 20)
			here.ZIndex = 3
			here.Parent = plate
		end

		root.Activated:Connect(function()
			if isCurrent then
				self:_Toast("You are here — " .. tier .. " " .. (ROMAN[data.division] or "") .. ".", "Info")
			elseif index < currentIndex then
				self:_Toast(tier .. " is already behind you.", "Info")
			else
				self:_Toast(string.format("Climb %d more tier%s to reach %s.",
					index - currentIndex, index - currentIndex == 1 and "" or "s", tier), "Info")
			end
		end)
		-- Animate LAST, after the final colours.
		UIChrome.Animate(theme, root, plate)
	end
end

-- ONE UITicker handler for both ambient effects, bound to the page so a style
-- rebuild unregisters it. Both gate on the card being on screen, exactly like
-- the arcade build's RunService version.
function RankScreen:_GPStartTicker()
	if self._gpTickerStop then
		return
	end
	local theme = self:GetTheme()
	local ink = theme.Colors.TextPrimary
	local flash = GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1)
	local card = self._modal and self._modal.card

	self._gpTickerStop = UITicker.Register(function(dt: number)
		if not card or not UIChrome.IsOnScreen(card) then
			return
		end
		if self._gpBurst then
			self._gpBurst.Rotation = (self._gpBurst.Rotation + GP_SPIN_DEGREES * dt) % 360
		end
		local data: RankData = self._data
		if not data.promo.active or not self._gpPromoTitle then
			return
		end
		self._phase += dt
		-- Colour, never opacity — and capped at half so the headline stays
		-- comfortably above 4.5:1 on cream at every point in the cycle.
		local blend = 0.5 + 0.5 * math.sin(self._phase * 3)
		self._gpPromoTitle.TextColor3 = ink:Lerp(flash, blend * GP_FLASH_CAP)
	end, card)
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts live in
-- StyleKit.Capabilities and only fall when a handle is released.
function RankScreen:_OnTeardown()
	self:_StopTicker()
	-- The ARCADE burst spin is a RunService connection held on the screen, not
	-- on the Gui: without this, swapping style while this screen is hidden
	-- leaves it spinning a destroyed ImageLabel forever.
	if self._spinConn then
		self._spinConn:Disconnect()
		self._spinConn = nil
	end
	self._burst = nil
	self._emblemIcon = nil
	GPStudioKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
	self._gpBurst = nil
	self._gpEmblemSlot = nil
	self._gpEmblemIcon = nil
	self._gpLadderList = nil
	self._gpPipRow = nil
	self._gpRpMeter = nil
	self._gpStatValues = nil
	self._gpStatNotes = nil
end

function RankScreen:Destroy()
	self:_StopTicker()
	if self._spinConn then
		self._spinConn:Disconnect()
		self._spinConn = nil
	end
	if self._rpBar then
		self._rpBar:Destroy()
		self._rpBar = nil
	end
	UIScreenBase.Destroy(self)
end

return RankScreen
