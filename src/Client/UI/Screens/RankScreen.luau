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
