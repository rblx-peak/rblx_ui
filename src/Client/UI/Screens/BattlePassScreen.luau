--!strict
-- Battle pass / season track — Pottery Clash arcade family (doc §7.4).
-- One modal card: a header (season name, current tier, XP ruler to the next
-- tier, the 1Hz season countdown, UNLOCK PREMIUM and CLAIM ALL) over a
-- horizontally scrolling tier rail.
--
-- Rail anatomy: a fixed left gutter carries the two lane labels (FREE /
-- PREMIUM) so they never scroll away; each tier is a COLUMN inside the scroll
-- with the free reward on top, the premium reward below, and a labelled
-- divider between them carrying the tier number. Node states follow the doc's
-- language: CLAIMED recolours grey in place with a check where the reward was
-- (§11.2), CLAIMABLE wears a pulsing gold ring (§4.3 selection-is-a-ring),
-- LOCKED dims in place and still answers every tap with a toast (§11.1).
--
-- The ring pulse and the countdown share ONE RenderStepped connection that
-- gates on UIChrome.IsOnScreen and is dropped in _OnHide/Destroy (§5.4).

local RunService = game:GetService("RunService")

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIProgressBarComponent = require(script.Parent.Parent.Components.UIProgressBarComponent)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPStudioKit = require(script.Parent.Parent.Framework.GPStudioKit)
local UITicker = require(script.Parent.Parent.Framework.UITicker)

type Reward = { icon: string?, label: string?, amount: number? }
type Tier = {
	level: number,
	free: Reward?,
	premium: Reward?,
	claimedFree: boolean?,
	claimedPremium: boolean?,
}
type SeasonData = {
	season: string,
	tier: number,
	xp: number,
	xpPerTier: number,
	endsIn: number,
	premium: boolean,
	tiers: { Tier },
}

local CARD_W, CARD_H = 1440, 700
local CONTENT_W = CARD_W - 28
local CONTENT_H = CARD_H - 88
local RAIL_Y = 150
local RAIL_H = CONTENT_H - RAIL_Y
local GUTTER_W = 96
local COL_W = 132
local COL_GAP = 12
local LANE_H = 186
local FREE_Y = 6
local DIVIDER_Y = 200
local DIVIDER_H = 34
local PREMIUM_Y = 242
local COL_H = PREMIUM_Y + LANE_H
local PREMIUM_PRICE = 899

-- Reward pools the demo season cycles through, so the rail reads like a real
-- track (cash beats, a crate every fifth tier, a crown at the top).
local FREE_POOL: { Reward } = {
	{ icon = "cash", amount = 250 },
	{ icon = "star", amount = 150, label = "XP" },
	{ icon = "cash", amount = 400 },
	{ icon = "ticket", amount = 2 },
	{ icon = "crate", amount = 1, label = "CRATE" },
}
local PREMIUM_POOL: { Reward } = {
	{ icon = "bux", amount = 25 },
	{ icon = "chest", amount = 1, label = "CHEST" },
	{ icon = "sparkle", amount = 1, label = "GLAZE" },
	{ icon = "cash", amount = 1500 },
	{ icon = "crown", amount = 1, label = "TITLE" },
}

local function demoData(): SeasonData
	local tiers: { Tier } = {}
	for level = 1, 30 do
		table.insert(tiers, {
			level = level,
			free = FREE_POOL[((level - 1) % #FREE_POOL) + 1],
			premium = PREMIUM_POOL[((level - 1) % #PREMIUM_POOL) + 1],
			claimedFree = level <= 9,
			claimedPremium = false,
		})
	end
	return {
		season = "SEASON 3 — KILN & COBALT",
		tier = 12,
		xp = 640,
		xpPerTier = 1000,
		endsIn = 2 * 86400 + 6 * 3600 + 21 * 60,
		premium = false,
		tiers = tiers,
	}
end

local function rewardText(reward: Reward): string
	if reward.label and reward.amount and reward.amount > 1 then
		return string.format("%d %s", reward.amount, reward.label)
	elseif reward.label then
		return reward.label
	elseif reward.amount then
		if reward.amount >= 1000 then
			return string.format("%.1fK", reward.amount / 1000)
		end
		return tostring(reward.amount)
	end
	return "?"
end

local function tintIcon(icon: GuiObject, color: Color3)
	if icon:IsA("ImageLabel") then
		icon.ImageColor3 = color
	elseif icon:IsA("TextLabel") then
		icon.TextColor3 = color
	end
end

local function dimIcon(icon: GuiObject, transparency: number)
	if icon:IsA("ImageLabel") then
		icon.ImageTransparency = transparency
	elseif icon:IsA("TextLabel") then
		icon.TextTransparency = transparency
	end
end

local BattlePassScreen = setmetatable({}, { __index = UIScreenBase })
BattlePassScreen.__index = BattlePassScreen

function BattlePassScreen.new()
	local self = UIScreenBase.new("BattlePassScreen", 6)
	self._data = demoData()
	self._pulseRings = {} :: { UIStroke }
	self._tickConn = nil :: RBXScriptConnection?
	self._phase = 0
	self._accum = 0
	return setmetatable(self, BattlePassScreen)
end

function BattlePassScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function BattlePassScreen:_BuildContent()
	-- GP layout language: the matte season shelf (see _BuildGPLayout below);
	-- the classic arcade modal build stays untouched.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "BATTLE PASS",
		sizePx = Vector2.new(CARD_W, CARD_H),
		onClose = function()
			self.ScreenController:HideScreen("battlePass")
		end,
	})
	self._modal = modal
	local content = modal.content

	local season = UIChrome.Text("Season", 30, theme.Arcade.Gold)
	season.TextXAlignment = Enum.TextXAlignment.Left
	season.Size = UDim2.fromOffset(760, 36)
	season.RichText = false
	season.TextTruncate = Enum.TextTruncate.AtEnd
	season.Parent = content
	self._seasonLabel = season

	local tier = UIChrome.Text("Tier", 22, theme.Colors.TextPrimary)
	tier.TextXAlignment = Enum.TextXAlignment.Left
	tier.Position = UDim2.fromOffset(0, 40)
	tier.Size = UDim2.fromOffset(300, 26)
	tier.Parent = content
	self._tierLabel = tier

	self._xpBar = UIProgressBarComponent.new()
	self._xpBar:Create(content, {
		value = 0,
		maxValue = 1,
		label = "XP",
		size = UDim2.fromOffset(460, 26),
		position = UDim2.fromOffset(0, 74),
	})

	-- Countdown surface (doc §11.3): 1Hz, gold FredokaOne, HH:MM:SS.
	local countdown = UIChrome.Text("Countdown", 20, theme.Arcade.SunburstGold)
	countdown.TextXAlignment = Enum.TextXAlignment.Left
	countdown.Position = UDim2.fromOffset(480, 74)
	countdown.Size = UDim2.fromOffset(420, 26)
	countdown.Parent = content
	self._countdownLabel = countdown

	local actions = UIStyler.Frame("Actions")
	actions.BackgroundTransparency = 1
	actions.AnchorPoint = Vector2.new(1, 0)
	actions.Position = UDim2.new(1, 0, 0, 12)
	actions.Size = UDim2.fromOffset(540, 52)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12),
	}).Parent = actions
	actions.Parent = content

	self._claimAll = UIButtonComponent.new()
	self._claimAll:Create(actions, {
		text = "CLAIM ALL",
		variant = "Green",
		size = UDim2.fromOffset(200, 52),
		layoutOrder = 1,
		onClick = function()
			self:_ClaimAll()
		end,
	})

	-- Robux is ALWAYS magenta (doc §3.3), icon leading the amount (§8).
	self._premiumButton = UIButtonComponent.new()
	self._premiumButton:Create(actions, {
		text = string.format("UNLOCK PREMIUM  %d", PREMIUM_PRICE),
		variant = "Magenta",
		iconId = IconArchive.Id("robux"),
		size = UDim2.fromOffset(320, 52),
		layoutOrder = 2,
		onClick = function()
			self:_UnlockPremium()
		end,
	})

	local rule = UIStyler.Frame("Rule")
	rule.BackgroundColor3 = theme.Arcade.RulerTick
	rule.BackgroundTransparency = 0.65
	rule.Position = UDim2.fromOffset(0, 128)
	rule.Size = UDim2.new(1, 0, 0, 2)
	rule.Parent = content

	-- Fixed lane gutter: labels stay put while the rail scrolls under them.
	local gutter = UIStyler.Frame("Gutter")
	gutter.BackgroundTransparency = 1
	gutter.Position = UDim2.fromOffset(0, RAIL_Y)
	gutter.Size = UDim2.fromOffset(GUTTER_W, COL_H)
	gutter.Parent = content

	-- 18px, not the 20–24 label tier: "PREMIUM" in FredokaOne has to fit the
	-- 96px gutter, and an overflowing label would run under the rail.
	local freeLabel = UIChrome.Text("FreeLane", 18, theme.Colors.TextPrimary)
	freeLabel.Text = "FREE"
	freeLabel.Position = UDim2.fromOffset(0, FREE_Y + LANE_H // 2 - 14)
	freeLabel.Size = UDim2.fromOffset(GUTTER_W, 28)
	freeLabel.Parent = gutter

	local premiumLabel = UIChrome.Text("PremiumLane", 18, theme.Arcade.Magenta)
	premiumLabel.Text = "PREMIUM"
	premiumLabel.Position = UDim2.fromOffset(0, PREMIUM_Y + LANE_H // 2 - 14)
	premiumLabel.Size = UDim2.fromOffset(GUTTER_W, 28)
	premiumLabel.Parent = gutter

	local rail = Instance.new("ScrollingFrame")
	rail.Name = "Rail"
	rail.BackgroundTransparency = 1
	rail.BorderSizePixel = 0
	rail.Position = UDim2.fromOffset(GUTTER_W + 8, RAIL_Y)
	rail.Size = UDim2.new(1, -(GUTTER_W + 8), 0, RAIL_H)
	rail.CanvasSize = UDim2.new()
	rail.AutomaticCanvasSize = Enum.AutomaticSize.X
	rail.ScrollingDirection = Enum.ScrollingDirection.X
	rail.ScrollBarThickness = 8
	rail.ScrollBarImageColor3 = theme.Arcade.Gold
	rail.Parent = content
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, COL_GAP),
	}).Parent = rail
	self._rail = rail

	self:_RenderHeader()
	self:_RenderRail()
end

function BattlePassScreen:_RenderHeader()
	if self:LayoutKit() == "GP" then
		self:_GPRenderHeader()
		return
	end
	local data: SeasonData = self._data
	self._seasonLabel.Text = data.season
	self._tierLabel.Text = string.format("TIER %d", data.tier)
	self._xpBar:Set(data.xp, math.max(data.xpPerTier, 1))
	self._countdownLabel.Text = "SEASON ENDS  " .. UIChrome.FormatCountdown(data.endsIn)

	-- SetContent always re-reads the label from the props it is HANDED (it is
	-- not a partial merge for text/icon), so every call restates both.
	if data.premium then
		self._premiumButton:SetContent({ text = "PREMIUM ACTIVE", variant = "Grey" })
		self._premiumButton:SetEnabled(false)
	else
		self._premiumButton:SetContent({
			text = string.format("UNLOCK PREMIUM  %d", PREMIUM_PRICE),
			variant = "Magenta",
			iconId = IconArchive.Id("robux"),
		})
		self._premiumButton:SetEnabled(true)
	end
	-- CLAIM ALL dims in place when there is nothing to claim; the tap still
	-- plays its juice and then explains (doc §11.1).
	self._claimAll:SetContent({ text = "CLAIM ALL", dimmed = self:_ClaimableCount() == 0 })
end

function BattlePassScreen:_ClaimableCount(): number
	local data: SeasonData = self._data
	local n = 0
	for _, tier in data.tiers do
		if tier.level <= data.tier then
			if tier.free and not tier.claimedFree then
				n += 1
			end
			if data.premium and tier.premium and not tier.claimedPremium then
				n += 1
			end
		end
	end
	return n
end

function BattlePassScreen:_LaneState(tier: Tier, lane: string): string
	local data: SeasonData = self._data
	local claimed = if lane == "free" then tier.claimedFree else tier.claimedPremium
	if claimed then
		return "claimed"
	end
	if tier.level > data.tier then
		return "locked"
	end
	if lane == "premium" and not data.premium then
		return "locked"
	end
	return "claimable"
end

function BattlePassScreen:_RenderRail()
	local data: SeasonData = self._data
	local isGP = self:LayoutKit() == "GP"
	-- Explicitly `any`: the two layouts hold their rail in different fields and
	-- narrowing the union buys nothing here.
	local rail: any = if isGP then self._gpRail else self._rail
	local keepPosition = rail.CanvasPosition

	table.clear(self._pulseRings)
	for _, child in rail:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for index, tier in data.tiers do
		if isGP then
			self:_GPBuildColumn(tier, index)
		else
			self:_BuildColumn(tier, index)
		end
	end
	-- AutomaticCanvasSize only catches up after the layout pass, so the
	-- immediate restore would clamp against a stale (smaller) canvas: re-apply
	-- once the new columns have been measured, or a claim would jump the rail
	-- back to tier 1.
	rail.CanvasPosition = keepPosition
	task.defer(function()
		if rail and rail.Parent then
			rail.CanvasPosition = keepPosition
		end
	end)
end

function BattlePassScreen:_BuildColumn(tier: Tier, index: number)
	local theme = self:GetTheme()
	local data: SeasonData = self._data

	local column = UIStyler.Frame("Tier" .. tier.level)
	column.BackgroundTransparency = 1
	column.Size = UDim2.fromOffset(COL_W, COL_H)
	column.LayoutOrder = index
	column.Parent = self._rail

	self:_BuildNode(column, tier, "free", FREE_Y)

	-- The labelled divider between the lanes: a hairline rule carrying the tier
	-- number, gold once the tier is reached.
	local reached = tier.level <= data.tier
	local divider = UIStyler.Frame("Divider")
	divider.BackgroundTransparency = 1
	divider.Position = UDim2.fromOffset(0, DIVIDER_Y)
	divider.Size = UDim2.fromOffset(COL_W, DIVIDER_H)
	divider.Parent = column

	local rule = UIStyler.Frame("Rule")
	rule.BackgroundColor3 = reached and theme.Arcade.SunburstGold or theme.Arcade.RulerTick
	rule.BackgroundTransparency = reached and 0.2 or 0.7
	rule.AnchorPoint = Vector2.new(0, 0.5)
	rule.Position = UDim2.new(0, 0, 0.5, 0)
	rule.Size = UDim2.new(1, 0, 0, 2)
	rule.Parent = divider

	local chip = UIStyler.Frame("LevelChip")
	chip.BackgroundColor3 = reached and theme.Arcade.Gold or theme.Arcade.NearBlack
	chip.BackgroundTransparency = 0
	chip.AnchorPoint = Vector2.new(0.5, 0.5)
	chip.Position = UDim2.fromScale(0.5, 0.5)
	chip.Size = UDim2.fromOffset(62, 28)
	UIChrome.Stroke(theme, "Arcade").Parent = chip
	UIChrome.GlassGradient().Parent = chip
	chip.Parent = divider

	local level = UIChrome.Text("Level", 17, reached and theme.Arcade.NearBlack or theme.Colors.TextPrimary)
	level.Text = tostring(tier.level)
	level.Size = UDim2.fromScale(1, 1)
	level.Parent = chip

	self:_BuildNode(column, tier, "premium", PREMIUM_Y)
end

function BattlePassScreen:_BuildNode(column: Frame, tier: Tier, lane: string, y: number)
	local theme = self:GetTheme()
	local reward: Reward? = if lane == "free" then tier.free else tier.premium
	local state = self:_LaneState(tier, lane)

	local root = UIStyler.Frame(lane == "free" and "Free" or "Premium")
	root.BackgroundTransparency = 1
	root.Position = UDim2.fromOffset(0, y)
	root.Size = UDim2.fromOffset(COL_W, LANE_H)
	root.Parent = column

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 1
	hit.Parent = root

	local surface = UIStyler.Frame("Surface")
	surface.BackgroundColor3 = if state == "claimed" then theme.Arcade.GreyClaimed else theme.Arcade.NearBlack
	surface.BackgroundTransparency = if state == "locked" then 0.45 else 0
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 2
	local stroke = UIChrome.Stroke(theme, "Arcade", state == "claimable" and "Selection" or "Panel")
	stroke.Parent = surface
	UIChrome.GlassGradient().Parent = surface
	surface.Parent = root
	if state == "claimable" then
		table.insert(self._pulseRings, stroke)
	end

	if not reward then
		local none = UIChrome.Text("None", 16, theme.Arcade.GreyOwned)
		none.Text = "—"
		none.Size = UDim2.fromScale(1, 1)
		none.Parent = surface
		return
	end

	if state == "claimed" then
		-- CLAIMED recolours grey IN PLACE: the check takes the reward's slot.
		local check = IconArchive.Image(surface, "check", 64)
		check.AnchorPoint = Vector2.new(0.5, 0)
		check.Position = UDim2.new(0.5, 0, 0, 26)
		tintIcon(check, theme.Arcade.GreyOwned)
	else
		local icon = IconArchive.Image(surface, reward.icon or "gift", 64, { golden = lane == "premium" })
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 26)
		if state == "locked" then
			dimIcon(icon, 0.5)
		end
	end

	local amount = UIChrome.Text("Amount", 18, if state == "claimed"
		then theme.Arcade.GreyOwned
		elseif state == "locked" then theme.Arcade.GreyOwned
		else theme.Arcade.SunburstGold)
	amount.Text = rewardText(reward)
	amount.Position = UDim2.fromOffset(4, 100)
	amount.Size = UDim2.new(1, -8, 0, 24)
	amount.RichText = false
	amount.TextTruncate = Enum.TextTruncate.AtEnd
	amount.Parent = surface

	local footer = UIChrome.Text("Footer", 14, theme.Colors.TextPrimary)
	if state == "claimed" then
		footer.Text = "CLAIMED"
		footer.TextColor3 = theme.Arcade.GreyOwned
	elseif state == "claimable" then
		footer.Text = "CLAIM"
		footer.TextColor3 = theme.Arcade.Green
	else
		footer.Text = "LOCKED"
		footer.TextColor3 = theme.Arcade.GreyOwned
	end
	footer.Position = UDim2.fromOffset(4, 132)
	footer.Size = UDim2.new(1, -8, 0, 20)
	footer.Parent = surface

	if state == "locked" then
		local lock = IconArchive.Image(surface, "lock", 22)
		lock.AnchorPoint = Vector2.new(1, 1)
		lock.Position = UDim2.new(1, -6, 1, -6)
	end

	hit.Activated:Connect(function()
		self:_ClaimNode(tier, lane)
	end)
	-- Animate LAST, after the final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, hit, surface)
end

function BattlePassScreen:_ClaimNode(tier: Tier, lane: string)
	local data: SeasonData = self._data
	local state = self:_LaneState(tier, lane)
	if state == "claimed" then
		self:_Toast("Already claimed.", "Info")
		return
	end
	if state == "locked" then
		if lane == "premium" and not data.premium then
			self:_Toast("Unlock Premium to claim this reward.", "Error")
		else
			self:_Toast(string.format("Reach tier %d to claim this.", tier.level), "Error")
		end
		return
	end
	if lane == "free" then
		tier.claimedFree = true
	else
		tier.claimedPremium = true
	end
	self:_Toast(string.format("Tier %d reward claimed.", tier.level), "Success")
	self:_RenderHeader()
	self:_RenderRail()
end

function BattlePassScreen:_ClaimAll()
	local data: SeasonData = self._data
	local claimed = self:_ClaimableCount()
	if claimed == 0 then
		self:_Toast("Nothing to claim yet.", "Error")
		return
	end
	for _, tier in data.tiers do
		if tier.level <= data.tier then
			if tier.free then
				tier.claimedFree = true
			end
			if data.premium and tier.premium then
				tier.claimedPremium = true
			end
		end
	end
	self:_Toast(string.format("Claimed %d rewards.", claimed), "Success")
	self:_RenderHeader()
	self:_RenderRail()
end

function BattlePassScreen:_UnlockPremium()
	local data: SeasonData = self._data
	if data.premium then
		self:_Toast("Premium is already active this season.", "Info")
		return
	end
	self.ScreenController:ShowModal({
		kind = "Confirm",
		title = "UNLOCK PREMIUM",
		body = string.format("Unlock the premium lane for the whole season for %d Robux?", PREMIUM_PRICE),
		confirmKey = "UNLOCK",
		cancelKey = "NOT NOW",
		onConfirm = function()
			data.premium = true
			self:_Toast("Premium unlocked — every premium tier is yours.", "Success")
			self:_RenderHeader()
			self:_RenderRail()
		end,
	})
end

-- ONE frugal RenderStepped connection drives both ambient effects (doc §5.4):
-- the claimable rings breathe on sin(t), the countdown ticks at 1Hz.
function BattlePassScreen:_StartTicker()
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
		self._phase += dt
		local breathe = 0.5 + 0.5 * math.sin(self._phase * 3)
		for index = #self._pulseRings, 1, -1 do
			local ring = self._pulseRings[index]
			if ring.Parent then
				ring.Thickness = 3 + 2 * breathe
				ring.Transparency = 0.25 * (1 - breathe)
			else
				table.remove(self._pulseRings, index)
			end
		end

		self._accum += dt
		if self._accum >= 1 then
			self._accum -= 1
			local data: SeasonData = self._data
			data.endsIn = math.max(0, data.endsIn - 1)
			self._countdownLabel.Text = "SEASON ENDS  " .. UIChrome.FormatCountdown(data.endsIn)
		end
	end)
end

function BattlePassScreen:_StopTicker()
	if self._gpTickerStop then
		self._gpTickerStop()
		self._gpTickerStop = nil
	end
	if self._tickConn then
		self._tickConn:Disconnect()
		self._tickConn = nil
	end
end

function BattlePassScreen:_Apply(data: any)
	local current: SeasonData = self._data
	self._data = {
		season = data.season or current.season,
		tier = data.tier or current.tier,
		xp = data.xp or current.xp,
		xpPerTier = data.xpPerTier or current.xpPerTier,
		endsIn = data.endsIn or current.endsIn,
		premium = if data.premium ~= nil then data.premium else current.premium,
		tiers = data.tiers or current.tiers,
	}
end

-- _EnsureBuilt has already rendered with the data the screen was holding, so
-- only a fresh payload re-renders here.
function BattlePassScreen:_OnShow(data: any?)
	if data then
		self:_Apply(data)
		self:_RenderHeader()
		self:_RenderRail()
	end
	self:_StartTicker()
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function BattlePassScreen:_OnHide()
	self:_StopTicker()
end

function BattlePassScreen:Update(data: any)
	if not data then
		return
	end
	self:_Apply(data)
	if self._built then
		self:_RenderHeader()
		self:_RenderRail()
	end
end

-- ========================================================================
-- GP layout (theme.LayoutKit == "GP") — THE SEASON SHELF, in the pack's
-- MATTE dialect: cream paper, clay speckle, sage hairlines. A season track is
-- a shelf of finished pieces waiting to be taken home.
--
-- ANTI-CONDESCENSION LEDGER — every reading the arcade page carries:
--   season name · current tier · XP ruler to the next tier · the live 1Hz
--   season countdown · CLAIM ALL (dimmed in place when there is nothing) ·
--   UNLOCK PREMIUM with its Robux price and icon, becoming the inert
--   PREMIUM ACTIVE state · the fixed FREE / PREMIUM lane gutter · EVERY tier
--   column in the data (thirty in the demo, not a sample) · both lanes per
--   column · per node: reward icon, reward amount text, footer state, the
--   claimed check, the locked lock, the claimable ring · the labelled
--   divider carrying the tier number and going gold once reached.
-- ADDED: the XP ruler prints its percentage alongside its counts.
--
-- BUDGET NOTE: nodes are SHADOWLESS — thirty tiers is sixty nodes, and sixty
-- UIShadows would be more than half the engine's whole on-screen budget for
-- one screen. Claimable reads as a BREATHING RING, which is the state's
-- grammar in this codebase anyway.
-- ========================================================================

local GP_PAGE = Vector2.new(CARD_W, CARD_H + 48)
local GP_SCROLL_PAD = 10
local GP_COL_W = 138
local GP_LANE_H = 182
local GP_FREE_Y = 4
local GP_DIVIDER_Y = 196
local GP_DIVIDER_H = 36
local GP_PREMIUM_Y = 240
local GP_COL_H = GP_PREMIUM_Y + GP_LANE_H
local GP_ACTION_H = 52

function BattlePassScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	local spacing = theme.Spacing

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Battle Pass",
		subtitleText = "This season's shelf — what is yours already, and what is next.",
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("battlePass")
		end,
	})
	self._gpShadows = page.shadows
	self._modal = { content = page.content, card = page.panel } :: any
	local content = page.content

	local season = GPLayoutKit.Text(theme, 30, theme.Colors.TextPrimary, "Season")
	season.TextXAlignment = Enum.TextXAlignment.Left
	season.Size = UDim2.fromOffset(760, 38)
	season.RichText = false
	season.TextTruncate = Enum.TextTruncate.AtEnd
	season.Parent = content
	self._gpSeasonLabel = season

	local tier = GPLayoutKit.BodyText(theme, 22, theme.Colors.TextPrimary, "Tier")
	tier.TextXAlignment = Enum.TextXAlignment.Left
	tier.Position = UDim2.fromOffset(0, 42)
	tier.Size = UDim2.fromOffset(300, 26)
	tier.Parent = content
	self._gpTierLabel = tier

	self._gpXpMeter = GPStudioKit.Meter(theme, content, {
		value = 0,
		maxValue = 1,
		label = "XP",
		tone = theme.Colors.Primary,
		heightPx = 26,
		sizeUDim = UDim2.fromOffset(460, 26),
		position = UDim2.fromOffset(0, 76),
		name = "XPMeter",
	})

	local countdown = GPLayoutKit.BodyText(theme, 20, GPLayoutKit.Deepen(theme, theme.Arcade.Gold, 1), "Countdown")
	countdown.TextXAlignment = Enum.TextXAlignment.Left
	countdown.Position = UDim2.fromOffset(480, 76)
	countdown.Size = UDim2.fromOffset(440, 26)
	countdown.Parent = content
	self._gpCountdownLabel = countdown

	local actions = UIStyler.Frame("GPActions")
	actions.BackgroundTransparency = 1
	actions.AnchorPoint = Vector2.new(1, 0)
	actions.Position = UDim2.new(1, 0, 0, 12)
	actions.Size = UDim2.fromOffset(560, GP_ACTION_H)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, spacing.M),
	}).Parent = actions
	actions.Parent = content

	self._gpClaimAll = GPStudioKit.Button(theme, actions, {
		text = "Claim all",
		tone = theme.Colors.Secondary,
		index = 0,
		sizeUDim = UDim2.fromOffset(200, GP_ACTION_H),
		layoutOrder = 1,
		onClick = function()
			self:_ClaimAll()
		end,
	}, self._gpShadows)

	-- Robux keeps its magenta coding (doc §3.3) with the icon leading the
	-- amount (§8) — the pack re-tints the token, it does not re-assign it.
	self._gpPremiumButton = GPStudioKit.Button(theme, actions, {
		text = string.format("Unlock premium  %d", PREMIUM_PRICE),
		tone = theme.Arcade.Magenta,
		index = 1,
		iconId = IconArchive.Id("robux"),
		sizeUDim = UDim2.fromOffset(330, GP_ACTION_H),
		layoutOrder = 2,
		onClick = function()
			self:_UnlockPremium()
		end,
	}, self._gpShadows)

	GPStudioKit.Rule(theme, content, { transparency = 0.2 }).Position = UDim2.fromOffset(0, 130)

	-- Fixed lane gutter: labels stay put while the rail scrolls under them.
	local gutter = UIStyler.Frame("GPGutter")
	gutter.BackgroundTransparency = 1
	gutter.Position = UDim2.fromOffset(0, RAIL_Y)
	gutter.Size = UDim2.fromOffset(GUTTER_W, GP_COL_H)
	gutter.Parent = content

	local freeLabel = GPLayoutKit.BodyText(theme, 18, theme.Colors.TextPrimary, "FreeLane")
	freeLabel.Text = "Free"
	freeLabel.Position = UDim2.fromOffset(0, GP_FREE_Y + GP_LANE_H // 2 - 14)
	freeLabel.Size = UDim2.fromOffset(GUTTER_W, 28)
	freeLabel.Parent = gutter

	local premiumLabel = GPLayoutKit.BodyText(theme, 18, GPLayoutKit.Deepen(theme, theme.Arcade.Magenta, 1), "PremiumLane")
	premiumLabel.Text = "Premium"
	premiumLabel.Position = UDim2.fromOffset(0, GP_PREMIUM_Y + GP_LANE_H // 2 - 14)
	premiumLabel.Size = UDim2.fromOffset(GUTTER_W, 28)
	premiumLabel.Parent = gutter

	local rail = GPStudioKit.Scroller(theme, content, {
		name = "GPRail",
		direction = Enum.ScrollingDirection.X,
		padPx = GP_SCROLL_PAD,
		padTopPx = 0,
	})
	rail.Position = UDim2.fromOffset(GUTTER_W + 8, RAIL_Y)
	rail.Size = UDim2.new(1, -(GUTTER_W + 8), 0, CONTENT_H - RAIL_Y)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, COL_GAP),
	}).Parent = rail
	self._gpRail = rail

	self:_GPRenderHeader()
	self:_RenderRail()
end

function BattlePassScreen:_GPRenderHeader()
	local theme = self:GetTheme()
	local data: SeasonData = self._data
	self._gpSeasonLabel.Text = GPStudioKit.SoftCase(data.season)
	self._gpTierLabel.Text = string.format("Tier %d", data.tier)

	local perTier = math.max(data.xpPerTier, 1)
	self._gpXpMeter.Set(data.xp, perTier, string.format("%d / %d", data.xp, perTier))
	-- The lane label doubles as the percentage readout: "XP" alone is a name,
	-- "XP · 64%" is a name and a reading.
	self._gpXpMeter.name.Text = string.format("XP · %d%%", math.floor(math.clamp(data.xp / perTier, 0, 1) * 100 + 0.5))
	self._gpCountdownLabel.Text = "Season ends  " .. UIChrome.FormatCountdown(data.endsIn)

	if data.premium then
		self._gpPremiumButton.SetText("Premium active")
		self._gpPremiumButton.SetIcon(nil)
		self._gpPremiumButton.SetTone(theme.Colors.Disabled)
		self._gpPremiumButton.SetDimmed(true)
	else
		self._gpPremiumButton.SetText(string.format("Unlock premium  %d", PREMIUM_PRICE))
		self._gpPremiumButton.SetIcon(IconArchive.Id("robux"))
		self._gpPremiumButton.SetTone(theme.Arcade.Magenta)
		self._gpPremiumButton.SetDimmed(false)
	end
	-- CLAIM ALL dims in place when there is nothing to claim; the tap still
	-- plays its juice and then explains (doc §11.1).
	self._gpClaimAll.SetDimmed(self:_ClaimableCount() == 0)
end

function BattlePassScreen:_GPBuildColumn(tier: Tier, index: number)
	local theme = self:GetTheme()
	local data: SeasonData = self._data

	local column = UIStyler.Frame("GPTier" .. tier.level)
	column.BackgroundTransparency = 1
	column.Size = UDim2.fromOffset(GP_COL_W, GP_COL_H)
	column.LayoutOrder = index
	column.Parent = self._gpRail

	self:_GPBuildNode(column, tier, "free", GP_FREE_Y, index)

	-- The labelled divider between the lanes: a hairline carrying the tier
	-- number, gold once the tier is reached.
	local reached = tier.level <= data.tier
	local divider = UIStyler.Frame("Divider")
	divider.BackgroundTransparency = 1
	divider.Position = UDim2.fromOffset(0, GP_DIVIDER_Y)
	divider.Size = UDim2.fromOffset(GP_COL_W, GP_DIVIDER_H)
	divider.Parent = column

	local rule = GPStudioKit.Rule(theme, divider, {
		thickness = 2,
		transparency = if reached then 0 else 0.4,
	})
	if reached then
		-- Reached goes gold; unreached keeps the studio dialect's sage hairline.
		rule.BackgroundColor3 = GPLayoutKit.Deepen(theme, theme.Arcade.Gold, 1)
	end
	rule.AnchorPoint = Vector2.new(0, 0.5)
	rule.Position = UDim2.new(0, 0, 0.5, 0)

	local chip = GPStudioKit.Chip(theme, divider, {
		name = "LevelChip",
		text = tostring(tier.level),
		tone = if reached then theme.Arcade.Gold else theme.Colors.Surface,
		textColor = theme.Colors.TextPrimary,
		index = index,
		pill = true,
		sizeUDim = UDim2.fromOffset(66, 30),
		position = UDim2.fromScale(0.5, 0.5),
		anchorPoint = Vector2.new(0.5, 0.5),
		textSize = theme.TextSizes.Body,
	})
	chip.root.ZIndex = 3
	chip.label.ZIndex = 4

	self:_GPBuildNode(column, tier, "premium", GP_PREMIUM_Y, index + 1)
end

function BattlePassScreen:_GPBuildNode(column: Frame, tier: Tier, lane: string, y: number, cornerIndex: number)
	local theme = self:GetTheme()
	local reward: Reward? = if lane == "free" then tier.free else tier.premium
	local state = self:_LaneState(tier, lane)

	local root = Instance.new("TextButton")
	root.Name = if lane == "free" then "Free" else "Premium"
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.Position = UDim2.fromOffset(0, y)
	root.Size = UDim2.fromOffset(GP_COL_W, GP_LANE_H)
	root.Parent = column

	local claimable = state == "claimable"
	local plate = GPStudioKit.Paper(theme, root, {
		name = "Plate",
		index = cornerIndex,
		fill = if state == "claimed"
			then theme.Arcade.GreyClaimed
			elseif state == "locked" then theme.Colors.Surface
			else theme.Colors.SurfaceRaised,
		strokeTint = if claimable then theme.Colors.Primary else nil,
		strokeThickness = if claimable then 3 else nil,
	})
	plate.Size = UDim2.fromScale(1, 1)
	local stroke = plate:FindFirstChildOfClass("UIStroke") :: UIStroke
	if claimable then
		table.insert(self._pulseRings, stroke)
	end

	if not reward then
		local none = GPLayoutKit.BodyText(theme, 16, theme.Colors.TextSecondary, "None")
		none.Text = "—"
		none.Size = UDim2.fromScale(1, 1)
		none.ZIndex = 3
		none.Parent = plate
		return
	end

	if state == "claimed" then
		-- CLAIMED recolours in place: the check takes the reward's own slot.
		local check = GPStudioKit.Icon(theme, plate, "check", 64, { tint = theme.Colors.TextSecondary })
		check.AnchorPoint = Vector2.new(0.5, 0)
		check.Position = UDim2.new(0.5, 0, 0, 26)
		check.ZIndex = 3
	else
		local icon = GPStudioKit.Icon(theme, plate, reward.icon or "gift", 64, {
			golden = lane == "premium",
			dim = if state == "locked" then 0.5 else nil,
		})
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 26)
		icon.ZIndex = 3
	end

	local amount = GPLayoutKit.Text(theme, 18, if state == "claimable"
		then GPLayoutKit.Deepen(theme, theme.Arcade.Gold, 1)
		else theme.Colors.TextSecondary, "Amount")
	amount.Text = GPStudioKit.SoftCase(rewardText(reward))
	amount.Position = UDim2.fromOffset(4, 100)
	amount.Size = UDim2.new(1, -8, 0, 24)
	amount.RichText = false
	amount.TextTruncate = Enum.TextTruncate.AtEnd
	amount.ZIndex = 3
	amount.Parent = plate

	local footer = GPLayoutKit.BodyText(theme, 14, theme.Colors.TextSecondary, "Footer")
	if state == "claimed" then
		footer.Text = "Claimed"
	elseif state == "claimable" then
		footer.Text = "Claim"
		footer.TextColor3 = GPLayoutKit.Deepen(theme, theme.Colors.Secondary, 1)
	else
		footer.Text = "Locked"
	end
	footer.Position = UDim2.fromOffset(4, 130)
	footer.Size = UDim2.new(1, -8, 0, 20)
	footer.ZIndex = 3
	footer.Parent = plate

	if state == "locked" then
		local lock = GPStudioKit.Icon(theme, plate, "lock", 22, { tint = theme.Colors.TextSecondary })
		lock.AnchorPoint = Vector2.new(1, 1)
		lock.Position = UDim2.new(1, -6, 1, -6)
		lock.ZIndex = 4
	end

	root.Activated:Connect(function()
		self:_ClaimNode(tier, lane)
	end)
	-- Animate LAST, after the final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, root, plate)
end

-- ONE UITicker handler drives both ambient effects, bound to the page so a
-- style rebuild unregisters it: the claimable rings breathe on sin(t) and the
-- countdown ticks at 1Hz. Both gate on the card being on screen.
function BattlePassScreen:_GPStartTicker()
	if self._gpTickerStop then
		return
	end
	local card = self._modal and self._modal.card
	self._gpTickerStop = UITicker.Register(function(dt: number)
		if not card or not UIChrome.IsOnScreen(card) then
			return
		end
		self._phase += dt
		local breathe = 0.5 + 0.5 * math.sin(self._phase * 2.4)
		for index = #self._pulseRings, 1, -1 do
			local ring = self._pulseRings[index]
			if ring.Parent then
				ring.Thickness = 2.5 + 1.8 * breathe
				ring.Transparency = 0.2 * (1 - breathe)
			else
				table.remove(self._pulseRings, index)
			end
		end

		self._accum += dt
		if self._accum >= 1 then
			self._accum -= 1
			local data: SeasonData = self._data
			data.endsIn = math.max(0, data.endsIn - 1)
			if self._gpCountdownLabel then
				self._gpCountdownLabel.Text = "Season ends  " .. UIChrome.FormatCountdown(data.endsIn)
			end
		end
	end, card)
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts live in
-- StyleKit.Capabilities and only fall when a handle is released.
function BattlePassScreen:_OnTeardown()
	self:_StopTicker()
	GPStudioKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
	self._gpRail = nil
	self._gpClaimAll = nil
	self._gpPremiumButton = nil
	self._gpXpMeter = nil
	self._gpCountdownLabel = nil
	table.clear(self._pulseRings)
end

function BattlePassScreen:Destroy()
	self:_StopTicker()
	if self._xpBar then
		self._xpBar:Destroy()
		self._xpBar = nil
	end
	if self._claimAll then
		self._claimAll:Destroy()
		self._claimAll = nil
	end
	if self._premiumButton then
		self._premiumButton:Destroy()
		self._premiumButton = nil
	end
	UIScreenBase.Destroy(self)
end

return BattlePassScreen
