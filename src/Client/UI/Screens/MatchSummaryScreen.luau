--!strict
-- MATCH SUMMARY screen — the end-of-match card, Pottery Clash arcade family.
-- Three bands inside one §7.4 modal card:
--
--   * the headline banner — VICTORY in gold / DEFEAT in arcade red, FredokaOne
--     76 (doc §2 result tier, §11.4 "gold marks winners everywhere");
--   * the scoreboard: a gold column-header row over zebra rows 48px carrying
--     rank / player / score / K / D / MVP, with the local player's row ringed
--     in gold and suffixed "(you)" (doc §11.4 "local player first");
--   * the reward breakdown strip: base XP, performance bonus, streak bonus and
--     the gold TOTAL, revealed one at a time on a 0.12s stagger with the §5.1
--     pop, the total counting up as it lands.
--
-- Show(data) = { won, rows = { {rank,name,userId,score,kills,deaths,mvp,
-- isLocal} }, rewards = { {label, amount, icon} } }. A rewards entry labelled
-- "total" becomes the gold total cell; with none, the total is summed here.
-- The reveal replays on every show, and its stagger/count-up are epoch-guarded
-- so hiding the screen mid-sequence cancels the pending work.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local ACLayoutKit = require(script.Parent.Parent.Framework.ACLayoutKit)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPMatchFlow = require(script.Parent.Parent.Framework.GPMatchFlow)
local UITicker = require(script.Parent.Parent.Framework.UITicker)

type ScoreRow = {
	rank: number,
	name: string,
	userId: number,
	score: number,
	kills: number,
	deaths: number,
	mvp: boolean?,
	isLocal: boolean?,
}
type Reward = { label: string, amount: number, icon: string? }

local MatchSummaryScreen = setmetatable({}, { __index = UIScreenBase })
MatchSummaryScreen.__index = MatchSummaryScreen

-- Fixed px at the 1650×1020 baseline. Card 1200×760 → content 1172×672.
local CARD = Vector2.new(1200, 760)
local CONTENT_W = 1172
local BANNER_H = 118
local TABLE_Y = 132
local HEADER_H = 34
local ROWS_Y = 170
local ROWS_H = 296
local ROW_H = 48
local REWARDS_Y = 478
local REWARDS_H = 122
local REWARD_GAP = 14
local BUTTONS_Y = 612
local BUTTON_H = 56
local SCROLLBAR_RESERVE = 10
local ZEBRA_TRANSPARENCY = 0.15 -- doc §9
local STAGGER = 0.12
local COUNT_UP_SECONDS = 0.7

-- Scoreboard column geometry (x, width). Numeric columns are right-aligned on
-- their own edge so the digits line up down the table.
local COL_RANK_X, COL_RANK_W = 16, 64
local COL_PLAYER_X = 92
local COL_PLAYER_W = 538
local COL_SCORE_R, COL_SCORE_W = 760, 140
local COL_K_R, COL_KD_W = 880, 80
local COL_D_R = 980
local COL_MVP_X, COL_MVP_W = 1010, 130

-- GP layout (theme.LayoutKit == "GP") fixed px. The page is 80px TALLER than
-- the arcade card and not one pixel narrower: GPLayoutKit.Page's content well
-- comes out 1172 wide — exactly CONTENT_W — so the scoreboard reuses the
-- COL_* ladder above verbatim, and the extra height pays for the pack's own
-- chrome (petal corners, hue shadows, the header's scalloped lip) instead of
-- coming out of the table. Rows are 4px taller and the strip 6px taller than
-- classic; nothing shrinks.
local GP_CARD = Vector2.new(1200, 840)
local GP_BANNER_H = 124
local GP_TABLE_Y = 140
local GP_HEADER_H = 34
local GP_ROWS_Y = 182
local GP_ROWS_H = 300
local GP_ROW_H = 52
local GP_ROW_GAP = 4
local GP_REWARDS_Y = 490
local GP_REWARDS_H = 128
-- The action row stops 10px short of the field's bottom edge on purpose: the
-- page's content frame clips, and a chip flush to that edge would have its
-- soft shadow shaved off square.
local GP_BUTTONS_Y = 632
local GP_BUTTON_H = 56
-- A scrolling viewport clips axis-aligned, so a row's own shadow would be
-- sliced at the top and bottom edge. Rows are deliberately shadow-free (the
-- same call GPLayoutKit.StatRow makes) and the well is inset instead.
local GP_SCROLL_PAD = 6
-- GPLayoutKit.Page CLIPS its content field. Anything that casts a hue-matched
-- shadow therefore sits inside an inset field, or its soft edge is sliced dead
-- straight at the clip boundary — the one way this pack looks broken.
local GP_FIELD_INSET = 6
local GP_FIELD_W = CONTENT_W - GP_FIELD_INSET * 2

local WHITE = Color3.new(1, 1, 1)

local DEMO_ROWS: { ScoreRow } = {
	{ rank = 1, name = "ClayCrusher", userId = 1, score = 4820, kills = 19, deaths = 4, mvp = true },
	{ rank = 2, name = "KilnKing", userId = 156, score = 4110, kills = 15, deaths = 7 },
	{ rank = 3, name = "You", userId = 0, score = 3760, kills = 13, deaths = 6, isLocal = true },
	{ rank = 4, name = "GlazeGoblin", userId = 2, score = 3040, kills = 11, deaths = 9 },
	{ rank = 5, name = "WheelWitch", userId = 3, score = 2680, kills = 9, deaths = 10 },
	{ rank = 6, name = "PorcelainPete", userId = 261, score = 2210, kills = 7, deaths = 11 },
	{ rank = 7, name = "MugMerchant", userId = 1101, score = 1740, kills = 5, deaths = 12 },
	{ rank = 8, name = "SlipCasterX", userId = 8, score = 980, kills = 2, deaths = 14 },
}

local DEMO_REWARDS: { Reward } = {
	{ label = "BASE XP", amount = 250, icon = "star" },
	{ label = "PERFORMANCE BONUS", amount = 180, icon = "bolt" },
	{ label = "STREAK BONUS x3", amount = 120, icon = "fire" },
	{ label = "TOTAL", amount = 550, icon = "trophy" },
}

local function isTotal(reward: Reward): boolean
	return string.find(string.lower(reward.label), "total", 1, true) ~= nil
end

-- A circular headshot well (doc §4.2: circles are the arcade's round
-- exception); the flat-cartoon player icon holds the slot until the thumbnail
-- resolves, and stays put if it never does (doc §10 fallback chain).
local function avatarCircle(theme: Types.UITheme, parent: Instance, userId: number, sizePx: number): Frame
	local holder = UIStyler.Frame("Avatar")
	holder.BackgroundColor3 = theme.Arcade.NearBlack
	holder.Size = UDim2.fromOffset(sizePx, sizePx)
	holder.ClipsDescendants = true
	UIChrome.Corner("Arcade", "Pill").Parent = holder
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = holder
	holder.Parent = parent

	local glyph = IconArchive.Image(holder, "player", math.floor(sizePx * 0.62))
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)

	local photo = Instance.new("ImageLabel")
	photo.Name = "Headshot"
	photo.BackgroundTransparency = 1
	photo.ScaleType = Enum.ScaleType.Crop
	photo.Size = UDim2.fromScale(1, 1)
	photo.Visible = false
	photo.Parent = holder

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and typeof(content) == "string" and content ~= "" and holder.Parent then
			photo.Image = content
			photo.Visible = true
			glyph.Visible = false
		end
	end)

	return holder
end

function MatchSummaryScreen.new()
	local self = UIScreenBase.new("MatchSummaryScreen", 19)
	self._won = true
	self._rows = DEMO_ROWS
	self._rewards = DEMO_REWARDS
	-- Bumped on every (re)show and on hide, so a pending stagger/count-up from
	-- an earlier reveal can never paint over a newer one.
	self._epoch = 0
	self._rewardCells = {} :: { { frame: Frame, amount: TextLabel, value: number, total: boolean } }
	-- Two GP shadow sinks, because they have different lifetimes: the page and
	-- its furniture are built ONCE, while the reward cells are torn down and
	-- rebuilt on every render and must hand their budget back each time.
	self._gpShadows = nil :: { any }?
	self._gpCellShadows = nil :: { any }?
	return setmetatable(self, MatchSummaryScreen)
end

function MatchSummaryScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function MatchSummaryScreen:_BuildContent()
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
	if self:LayoutKit() == "AC" then
		self:_BuildACLayout()
		return
	end
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = self:_R("MATCH SUMMARY"),
		sizePx = CARD,
		onClose = function()
			self.ScreenController:HideScreen("matchSummary")
		end,
	})
	self._modal = modal
	local content = modal.content

	-- Headline banner.
	local banner = UIStyler.Frame("Banner")
	banner.BackgroundColor3 = theme.Arcade.NearBlack
	banner.Size = UDim2.new(1, 0, 0, BANNER_H)
	UIChrome.Stroke(theme, "Arcade").Parent = banner
	UIChrome.GlassGradient().Parent = banner
	banner.Parent = content

	local headline = UIChrome.Text("Headline", 76, theme.Arcade.Gold)
	headline.Position = UDim2.fromOffset(0, 4)
	headline.Size = UDim2.new(1, 0, 0, 84)
	headline.Parent = banner
	self._headline = headline

	local subline = UIChrome.Text("Subline", 19, theme.Arcade.IceBlue)
	subline.Position = UDim2.fromOffset(0, 86)
	subline.Size = UDim2.new(1, 0, 0, 26)
	subline.Parent = banner
	self._subline = subline

	-- Column headers.
	local header = UIStyler.Frame("ColumnHeader")
	header.BackgroundColor3 = theme.Arcade.Panel
	header.Position = UDim2.fromOffset(0, TABLE_Y)
	header.Size = UDim2.new(1, -SCROLLBAR_RESERVE, 0, HEADER_H)
	UIChrome.Stroke(theme, "Arcade").Parent = header
	UIChrome.GlassGradient().Parent = header
	header.Parent = content

	local function headerCell(text: string, x: number, width: number, alignment: Enum.TextXAlignment)
		local label = UIChrome.Text("H_" .. text, 16, theme.Arcade.Gold)
		label.Text = text
		label.TextXAlignment = alignment
		label.Position = UDim2.fromOffset(x, 0)
		label.Size = UDim2.fromOffset(width, HEADER_H)
		label.Parent = header
	end
	headerCell("RANK", COL_RANK_X, COL_RANK_W, Enum.TextXAlignment.Left)
	headerCell("PLAYER", COL_PLAYER_X, COL_PLAYER_W, Enum.TextXAlignment.Left)
	headerCell("SCORE", COL_SCORE_R - COL_SCORE_W, COL_SCORE_W, Enum.TextXAlignment.Right)
	headerCell("K", COL_K_R - COL_KD_W, COL_KD_W, Enum.TextXAlignment.Right)
	headerCell("D", COL_D_R - COL_KD_W, COL_KD_W, Enum.TextXAlignment.Right)
	headerCell("MVP", COL_MVP_X, COL_MVP_W, Enum.TextXAlignment.Center)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scoreboard"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, ROWS_Y)
	scroll.Size = UDim2.new(1, 0, 0, ROWS_H)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Arcade.Gold
	scroll.Parent = content
	UIStyler.ListLayout({
		Padding = UDim.new(0, 0), -- true zebra: rows meet edge to edge
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = scroll
	self._scroll = scroll

	local rewards = UIStyler.Frame("Rewards")
	rewards.BackgroundTransparency = 1
	rewards.Position = UDim2.fromOffset(0, REWARDS_Y)
	rewards.Size = UDim2.new(1, 0, 0, REWARDS_H)
	rewards.Parent = content
	self._rewardStrip = rewards

	-- Action row: PLAY AGAIN leads (green = confirm/positive, doc §3.3), LEAVE
	-- is the quiet ghost beside it.
	local buttons = UIStyler.Frame("Buttons")
	buttons.BackgroundTransparency = 1
	buttons.Position = UDim2.fromOffset(0, BUTTONS_Y)
	buttons.Size = UDim2.new(1, 0, 0, BUTTON_H)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 16),
	}).Parent = buttons
	buttons.Parent = content

	local again = UIButtonComponent.new()
	again:Create(buttons, {
		text = self:_R("PLAY AGAIN"),
		variant = "Green",
		size = UDim2.fromOffset(300, BUTTON_H),
		layoutOrder = 1,
		onClick = function()
			self:_Toast("SEARCHING FOR A NEW MATCH", "Success")
			self.ScreenController:HideScreen("matchSummary")
		end,
	})
	self._againButton = again

	local leave = UIButtonComponent.new()
	leave:Create(buttons, {
		text = self:_R("LEAVE"),
		variant = "Ghost",
		size = UDim2.fromOffset(220, BUTTON_H),
		layoutOrder = 2,
		onClick = function()
			self:_Toast("RETURNING TO THE LOBBY", "Info")
			self.ScreenController:HideScreen("matchSummary")
		end,
	})
	self._leaveButton = leave

	self:_Render()
end

function MatchSummaryScreen:_BuildScoreRow(row: ScoreRow, index: number)
	local theme = self:GetTheme()
	local local_ = row.isLocal == true

	local frame = UIStyler.Frame("Row" .. index)
	if local_ then
		-- Local player first (doc §11.4): a gold ring and a solid near-black
		-- fill lift "you" out of the zebra without breaking the row rhythm.
		frame.BackgroundColor3 = theme.Arcade.NearBlack
		frame.BackgroundTransparency = 0
		UIChrome.Stroke(theme, "Arcade", "Selection").Parent = frame
	else
		frame.BackgroundColor3 = if index % 2 == 1 then theme.Arcade.NearBlack2 else theme.Arcade.Row
		frame.BackgroundTransparency = ZEBRA_TRANSPARENCY
	end
	frame.Size = UDim2.new(1, -SCROLLBAR_RESERVE, 0, ROW_H)
	frame.LayoutOrder = index
	frame.Parent = self._scroll

	local rank = UIChrome.Text("Rank", 22, theme.Arcade.Gold)
	rank.Text = "#" .. tostring(row.rank)
	rank.TextXAlignment = Enum.TextXAlignment.Left
	rank.Position = UDim2.fromOffset(COL_RANK_X, 0)
	rank.Size = UDim2.fromOffset(COL_RANK_W, ROW_H)
	rank.Parent = frame

	local avatar = avatarCircle(theme, frame, row.userId, 34)
	avatar.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Position = UDim2.new(0, COL_PLAYER_X, 0.5, 0)

	local name = UIChrome.Text("Name", 20, if local_ then theme.Arcade.Gold else WHITE)
	name.Text = if local_ then row.name .. " (you)" else row.name
	name.RichText = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(COL_PLAYER_X + 44, 0)
	name.Size = UDim2.fromOffset(COL_PLAYER_W - 44, ROW_H)
	name.Parent = frame

	local function numeric(text: string, rightEdge: number, width: number, color: Color3, size: number)
		local label = UIChrome.Text("N", size, color)
		label.Text = text
		label.TextXAlignment = Enum.TextXAlignment.Right
		label.Position = UDim2.fromOffset(rightEdge - width, 0)
		label.Size = UDim2.fromOffset(width, ROW_H)
		label.Parent = frame
	end
	numeric(tostring(row.score), COL_SCORE_R, COL_SCORE_W, theme.Arcade.SunburstGold, 22)
	numeric(tostring(row.kills), COL_K_R, COL_KD_W, WHITE, 20)
	numeric(tostring(row.deaths), COL_D_R, COL_KD_W, theme.Arcade.GreyOwned, 20)

	if row.mvp then
		local star = IconArchive.Image(frame, "star", 28, { golden = true })
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.new(0, COL_MVP_X + COL_MVP_W / 2, 0.5, 0)
	end
end

-- One reward cell. Built hidden: the reveal makes it visible on its stagger
-- beat and pops it in (doc §5.1) — no fades, springs only.
function MatchSummaryScreen:_BuildRewardCell(reward: Reward, x: number, width: number, total: boolean)
	local theme = self:GetTheme()

	local cell = UIStyler.Frame("Reward_" .. reward.label)
	cell.BackgroundColor3 = if total then theme.Arcade.NearBlack else theme.Arcade.NearBlack2
	cell.BackgroundTransparency = 0
	cell.Position = UDim2.fromOffset(x, 0)
	cell.Size = UDim2.fromOffset(width, REWARDS_H)
	cell.Visible = false
	-- The total wears the gold selection ring; the breakdown cells keep the
	-- standard black arcade stroke.
	UIChrome.Stroke(theme, "Arcade", if total then "Selection" else "Panel").Parent = cell
	UIChrome.GlassGradient().Parent = cell
	cell.Parent = self._rewardStrip

	local icon = IconArchive.Image(cell, reward.icon or "star", 44, { golden = total })
	icon.AnchorPoint = Vector2.new(0, 0)
	icon.Position = UDim2.fromOffset(14, 14)

	local label = UIChrome.Text("Label", 17, if total then theme.Arcade.Gold else theme.Arcade.IceBlue)
	label.Text = reward.label
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Position = UDim2.fromOffset(68, 18)
	label.Size = UDim2.fromOffset(width - 82, 24)
	label.Parent = cell

	local amount = UIChrome.Text("Amount", if total then 40 else 32, if total then theme.Arcade.Gold else WHITE)
	amount.Text = "+" .. tostring(math.floor(reward.amount))
	amount.TextXAlignment = Enum.TextXAlignment.Left
	amount.Position = UDim2.fromOffset(14, REWARDS_H - 58)
	amount.Size = UDim2.fromOffset(width - 28, 48)
	amount.Parent = cell

	table.insert(self._rewardCells, {
		frame = cell,
		amount = amount,
		value = math.floor(reward.amount),
		total = total,
	})
end

function MatchSummaryScreen:_Render()
	if self:LayoutKit() == "GP" then
		self:_GPRender()
		return
	end
	if self:LayoutKit() == "AC" then
		self:_ACRender()
		return
	end
	local theme = self:GetTheme()

	self._headline.Text = if self._won then "VICTORY" else "DEFEAT"
	self._headline.TextColor3 = if self._won then theme.Arcade.Gold else theme.Arcade.Red
	local localRow: ScoreRow? = nil
	for _, row in self._rows do
		if row.isLocal then
			localRow = row
		end
	end
	self._subline.Text = if localRow
		then string.format("YOU PLACED #%d • %d SCORE • %d / %d K/D", localRow.rank, localRow.score, localRow.kills, localRow.deaths)
		else string.format("%d PLAYERS • MATCH COMPLETE", #self._rows)

	for _, child in self._scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, row in self._rows do
		self:_BuildScoreRow(row, index)
	end

	for _, child in self._rewardStrip:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(self._rewardCells)

	-- Split the breakdown from the total, then lay the strip out: equal-width
	-- breakdown cells and a wider gold total at the right end.
	local breakdown: { Reward } = {}
	local total: Reward? = nil
	local sum = 0
	for _, reward in self._rewards do
		if isTotal(reward) then
			total = reward
		else
			table.insert(breakdown, reward)
			sum += reward.amount
		end
	end
	total = total or { label = "TOTAL", amount = sum, icon = "trophy" }

	local totalWidth = 272
	local count = math.max(1, #breakdown)
	local cellWidth = math.floor((CONTENT_W - totalWidth - REWARD_GAP * count) / count)
	for index, reward in breakdown do
		self:_BuildRewardCell(reward, (index - 1) * (cellWidth + REWARD_GAP), cellWidth, false)
	end
	self:_BuildRewardCell(total, CONTENT_W - totalWidth, totalWidth, true)
end

-- The staggered reveal: each cell lands 0.12s after the last with the §5.1 pop,
-- and the total counts up as it arrives. Every delayed step re-checks the epoch
-- so hiding the screen (or a re-show) cancels the sequence cleanly.
function MatchSummaryScreen:_PlayReveal()
	local theme = self:GetTheme()
	self._epoch += 1
	local epoch = self._epoch

	for _, cell in self._rewardCells do
		cell.frame.Visible = false
		if cell.total then
			cell.amount.Text = "+0"
		end
	end

	for index, cell in self._rewardCells do
		task.delay(STAGGER * (index - 1), function()
			if self._epoch ~= epoch or not cell.frame.Parent then
				return
			end
			cell.frame.Visible = true
			UIChrome.PopIn(theme, cell.frame)
			if cell.total then
				self:_CountUp(cell.amount, cell.value, epoch)
			end
		end)
	end
end

function MatchSummaryScreen:_CountUp(label: TextLabel, target: number, epoch: number)
	local start = os.clock()
	task.spawn(function()
		while true do
			if self._epoch ~= epoch or not label.Parent then
				return
			end
			local alpha = math.clamp((os.clock() - start) / COUNT_UP_SECONDS, 0, 1)
			label.Text = "+" .. tostring(math.floor(target * alpha + 0.5))
			if alpha >= 1 then
				return
			end
			task.wait()
		end
	end)
end

function MatchSummaryScreen:_Ingest(data: any?)
	if not data then
		return
	end
	if data.won ~= nil then
		self._won = data.won == true
	end
	if data.rows and #data.rows > 0 then
		self._rows = data.rows
	end
	if data.rewards and #data.rewards > 0 then
		self._rewards = data.rewards
	end
end

function MatchSummaryScreen:_OnShow(data: any?)
	self:_Ingest(data)
	self:_Render()
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
	self:_PlayReveal()
	self:_PlaySound(if self._won then "Success" else "Error")
end

-- Cancels any in-flight stagger / count-up.
function MatchSummaryScreen:_OnHide()
	self._epoch += 1
end

function MatchSummaryScreen:Update(data: any)
	self:_Ingest(data)
	if self._built then
		self:_Render()
		self:_PlayReveal()
	end
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts only fall when
-- a handle is released — hand both GP sinks back here.
function MatchSummaryScreen:_OnTeardown()
	self._epoch += 1
	GPLayoutKit.ReleaseShadows(self._gpCellShadows)
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpCellShadows = nil
	self._gpShadows = nil
	self._gpBanner = nil
	table.clear(self._rewardCells)
end

function MatchSummaryScreen:Destroy()
	self._epoch += 1
	GPLayoutKit.ReleaseShadows(self._gpCellShadows)
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpCellShadows = nil
	self._gpShadows = nil
	if self._againButton then
		self._againButton:Destroy()
		self._againButton = nil
	end
	if self._leaveButton then
		self._leaveButton:Destroy()
		self._leaveButton = nil
	end
	UIScreenBase.Destroy(self)
end

-- ========================================================================
-- AC layout — the "SORTIE REPORT" terminal page (theme.LayoutKit == "AC").
-- Centre-left: the big mono outcome line (VICTORY in accent / DEFEAT in
-- the error token, from the same `won` data as classic), a hairline, the
-- local pilot's stats as a dense two-column ladder, then the requisition
-- rows — which the classic reveal machinery (_PlayReveal / _CountUp)
-- drives unchanged through self._rewardCells: rows print in on the
-- stagger, the total counts up. Right: the full standings table from the
-- same rows feed, the local player behind the accent notch. Footer:
-- [ESC] CONTINUE wired to the classic close action.
-- ========================================================================

local AC_STAT_ROW_H = 24
local AC_TABLE_ROW_H = 24

function MatchSummaryScreen:_BuildACLayout()
	local theme = self:GetTheme()

	local shell = ACLayoutKit.Shell(theme, self.Root, self:_R("SORTIE REPORT"))
	-- _OnShow pops self._modal.content in both layouts; under AC that is the
	-- shell's content region.
	self._modal = { content = shell.content } :: any
	ACLayoutKit.SetHints(shell, { { key = "ESC", action = "CONTINUE" } })

	-- THE one UITicker handler for this screen: [ESC] CONTINUE is the classic
	-- close action. Bound to the page so a style rebuild unregisters it.
	local escDown = false
	UITicker.Register(function()
		local pressed = UserInputService:IsKeyDown(Enum.KeyCode.Escape)
		if pressed and not escDown and self._visible then
			self.ScreenController:HideScreen("matchSummary")
		end
		escDown = pressed
	end, shell.page)

	-- Centre-left report column: fully data-driven, _ACRender reprints it.
	local report = UIStyler.Frame("Report")
	report.BackgroundTransparency = 1
	report.Size = UDim2.new(0.44, -14, 1, 0)
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 8),
	}).Parent = report
	report.Parent = shell.content
	self._acReport = report

	local divider = ACLayoutKit.Rule(theme, shell.content, 0.75)
	divider.Size = UDim2.new(0, 1, 1, 0)
	divider.Position = UDim2.new(0.44, 0, 0, 0)

	-- Right: the full standings, dim header over hairline rows.
	local standings = UIStyler.Frame("Standings")
	standings.BackgroundTransparency = 1
	standings.Position = UDim2.new(0.44, 14, 0, 0)
	standings.Size = UDim2.new(0.56, -14, 1, 0)
	standings.Parent = shell.content

	ACLayoutKit.SectionLabel(theme, standings, "STANDINGS")

	local header = ACLayoutKit.ListRow(theme, standings, {
		{ text = "RANK", widthScale = 0.1, align = Enum.TextXAlignment.Right, dim = true },
		{ text = "CALLSIGN", widthScale = 0.4, dim = true },
		{ text = "SCORE", widthScale = 0.2, align = Enum.TextXAlignment.Right, dim = true },
		{ text = "K", widthScale = 0.1, align = Enum.TextXAlignment.Right, dim = true },
		{ text = "D", widthScale = 0.1, align = Enum.TextXAlignment.Right, dim = true },
		{ text = "MVP", widthScale = 0.1, align = Enum.TextXAlignment.Right, dim = true },
	}, { heightPx = 22 })
	header.Position = UDim2.fromOffset(0, 22)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Table"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 48)
	scroll.Size = UDim2.new(1, 0, 1, -48)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = theme.Colors.Accent
	scroll.Parent = standings
	UIStyler.ListLayout({
		Padding = UDim.new(0, 0),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = scroll
	self._acStandings = scroll

	self:_ACRender()
end

function MatchSummaryScreen:_ACRender()
	local theme = self:GetTheme()

	for _, child in self._acReport:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, child in self._acStandings:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(self._rewardCells)

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local outcome = UIChrome.Text("Outcome", 18, if self._won then theme.Colors.Accent else theme.Colors.Error)
	outcome.Text = if self._won then "VICTORY" else "DEFEAT"
	outcome.TextXAlignment = Enum.TextXAlignment.Left
	outcome.Size = UDim2.new(1, 0, 0, 26)
	outcome.LayoutOrder = nextOrder()
	outcome.Parent = self._acReport

	local localRow: ScoreRow? = nil
	for _, row in self._rows do
		if row.isLocal then
			localRow = row
		end
	end

	local subline = UIChrome.BodyText("Subline", 11, theme.Colors.TextSecondary)
	subline.Text = if localRow
		then string.format("YOU PLACED #%d // %d SCORE // %d / %d K/D", localRow.rank, localRow.score, localRow.kills, localRow.deaths)
		else string.format("%d PLAYERS // MATCH COMPLETE", #self._rows)
	subline.TextXAlignment = Enum.TextXAlignment.Left
	subline.Size = UDim2.new(1, 0, 0, 14)
	subline.LayoutOrder = nextOrder()
	subline.Parent = self._acReport

	local rule = ACLayoutKit.Rule(theme, self._acReport)
	rule.LayoutOrder = nextOrder()

	ACLayoutKit.SectionLabel(theme, self._acReport, "COMBAT RECORD", nextOrder())

	local function ladderRow(label: string, value: string)
		ACLayoutKit.ListRow(theme, self._acReport, {
			{ text = label, widthScale = 0.55, dim = true },
			{ text = value, widthScale = 0.45, align = Enum.TextXAlignment.Right },
		}, { heightPx = AC_STAT_ROW_H, layoutOrder = nextOrder() })
	end
	if localRow then
		ladderRow("PLACEMENT", "#" .. tostring(localRow.rank))
		ladderRow("SCORE", tostring(localRow.score))
		ladderRow("KILLS", tostring(localRow.kills))
		ladderRow("DEATHS", tostring(localRow.deaths))
	else
		ladderRow("PLAYERS", tostring(#self._rows))
	end

	local rewardsRule = ACLayoutKit.Rule(theme, self._acReport)
	rewardsRule.LayoutOrder = nextOrder()

	ACLayoutKit.SectionLabel(theme, self._acReport, "REQUISITION", nextOrder())

	-- Same breakdown/total split as classic; _PlayReveal / _CountUp drive
	-- these rows through self._rewardCells unchanged.
	local breakdown: { Reward } = {}
	local total: Reward? = nil
	local sum = 0
	for _, reward in self._rewards do
		if isTotal(reward) then
			total = reward
		else
			table.insert(breakdown, reward)
			sum += reward.amount
		end
	end
	total = total or { label = "TOTAL", amount = sum, icon = "trophy" }

	local function rewardRow(reward: Reward, totalRow: boolean)
		local row, labels = ACLayoutKit.ListRow(theme, self._acReport, {
			{ text = reward.label, widthScale = 0.62, dim = not totalRow, color = if totalRow then theme.Colors.Accent else nil },
			{ text = "+" .. tostring(math.floor(reward.amount)), widthScale = 0.38, align = Enum.TextXAlignment.Right, color = if totalRow then theme.Colors.Accent else theme.Colors.TextPrimary },
		}, { heightPx = AC_STAT_ROW_H, layoutOrder = nextOrder() })
		-- Built hidden: the reveal prints it on its stagger beat.
		row.Visible = false
		table.insert(self._rewardCells, {
			frame = row :: Frame,
			amount = labels[2],
			value = math.floor(reward.amount),
			total = totalRow,
		})
	end
	for _, reward in breakdown do
		rewardRow(reward, false)
	end
	rewardRow(total, true)

	-- Action line: the same callbacks as classic's PLAY AGAIN / LEAVE.
	local actions = UIStyler.Frame("Actions")
	actions.BackgroundTransparency = 1
	actions.Size = UDim2.new(1, 0, 0, 34)
	actions.LayoutOrder = nextOrder()
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = actions
	actions.Parent = self._acReport

	ACLayoutKit.ActionButton(theme, actions, self:_R("PLAY AGAIN"), function()
		self:_Toast("SEARCHING FOR A NEW MATCH", "Success")
		self.ScreenController:HideScreen("matchSummary")
	end)
	ACLayoutKit.ActionButton(theme, actions, self:_R("LEAVE"), function()
		self:_Toast("RETURNING TO THE LOBBY", "Info")
		self.ScreenController:HideScreen("matchSummary")
	end)

	for index, row in self._rows do
		local local_ = row.isLocal == true
		local built = ACLayoutKit.ListRow(theme, self._acStandings, {
			{ text = "#" .. tostring(row.rank), widthScale = 0.1, align = Enum.TextXAlignment.Right, dim = true },
			{ text = if local_ then row.name .. " (YOU)" else row.name, widthScale = 0.4, color = if local_ then theme.Colors.Accent else nil },
			{ text = tostring(row.score), widthScale = 0.2, align = Enum.TextXAlignment.Right },
			{ text = tostring(row.kills), widthScale = 0.1, align = Enum.TextXAlignment.Right, dim = true },
			{ text = tostring(row.deaths), widthScale = 0.1, align = Enum.TextXAlignment.Right, dim = true },
			{ text = if row.mvp then "MVP" else "", widthScale = 0.1, align = Enum.TextXAlignment.Right, color = theme.Colors.Accent },
		}, { heightPx = AC_TABLE_ROW_H, layoutOrder = index })
		if local_ then
			built.BackgroundTransparency = 0.85
			local notch = UIStyler.Frame("Notch")
			notch.BackgroundColor3 = theme.Colors.Accent
			notch.BorderSizePixel = 0
			notch.Size = UDim2.new(0, 3, 1, -8)
			notch.Position = UDim2.new(0, 0, 0, 4)
			notch.Parent = built
		end
	end
	self._acStandings.CanvasPosition = Vector2.new(0, 0)
end

-- ========================================================================
-- GP layout — the "Firing Report" (theme.LayoutKit == "GP").
--
-- The same three bands, in the pack's language and at the SAME density:
--
--   * the verdict banner — "Fired!" in butter gold when the kiln was kind,
--     "Misfire" in the pack's soft coral when it wasn't, over the identical
--     placement / score / K / D subline;
--   * the scoreboard — the SAME six columns (rank, potter, score, K, D, MVP)
--     on the SAME COL_* ladder as classic, because GPLayoutKit.Page's content
--     well is 1172 wide exactly like the arcade card's. Rows alternate
--     Petal/PetalMirror so the table reads hand-arranged rather than stamped,
--     and the local potter's row is rose with a butter notch;
--   * the reward breakdown — one petal cell per line plus the gold total,
--     which GLOWS rather than shouting, driven by the UNCHANGED classic
--     reveal machinery (_PlayReveal / _CountUp read self._rewardCells).
--
-- Presentation only: same _rows / _rewards feeds, same callbacks, same toasts,
-- same epoch-guarded reveal. Nothing here is a data change.
-- ========================================================================

function MatchSummaryScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	local spacing = theme.Spacing

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Firing Report",
		sizePx = GP_CARD,
		onClose = function()
			self.ScreenController:HideScreen("matchSummary")
		end,
	})
	-- The page owns a sink already; adopt it as THE sink so teardown releases
	-- one list. Cells keep their own (they churn on every render).
	local shadows = page.shadows
	self._gpShadows = shadows
	self._gpCellShadows = {}
	-- _OnShow pops self._modal.content in every layout; under GP that is the
	-- page's content field, and _StartTicker-style callers read .card.
	self._modal = { content = page.content, card = page.panel } :: any

	-- Everything below rides an inset field, not the clipped content frame
	-- itself; see GP_FIELD_INSET.
	local content = UIStyler.Frame("Field")
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(GP_FIELD_INSET, GP_FIELD_INSET)
	content.Size = UDim2.new(1, -GP_FIELD_INSET * 2, 1, -GP_FIELD_INSET)
	content.ZIndex = 3
	content.Parent = page.content

	-- ---- verdict banner ----------------------------------------------
	-- Built once and REPAINTED per render (a rebuild per show would mint a new
	-- shadow every time and quietly eat the budget).
	local bannerFill = theme.Arcade.Gold
	local banner = GPMatchFlow.Fill("Banner", bannerFill)
	banner.Size = UDim2.new(1, 0, 0, GP_BANNER_H)
	banner.ZIndex = 4
	banner.Parent = content
	GPLayoutKit.Petal(theme, banner, 0)
	local bannerStroke = GPLayoutKit.SoftStroke(theme, banner, bannerFill)
	local bannerShadow = GPLayoutKit.Shadow(theme, banner, "md", shadows, bannerFill)
	-- Corner FIRST, then the sheen: GlazeSheen clones the host's UICorner so
	-- the wash can never square off a petal.
	GPLayoutKit.GlazeSheen(theme, banner)
	self._gpBanner = { plate = banner, stroke = bannerStroke, shadow = bannerShadow }

	-- Ink, not the near-white: TextOnPrimary measures 2.14:1 on these pastels.
	local headline = GPLayoutKit.Text(theme, 64, theme.Colors.TextPrimary, "Headline")
	headline.RichText = false
	headline.Position = UDim2.fromOffset(0, 8)
	headline.Size = UDim2.new(1, 0, 0, 74)
	headline.ZIndex = 6
	headline.Parent = banner
	self._headline = headline

	local subline = GPLayoutKit.BodyText(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Subline")
	subline.RichText = false
	subline.Position = UDim2.fromOffset(0, 84)
	subline.Size = UDim2.new(1, 0, 0, 30)
	subline.ZIndex = 6
	subline.Parent = banner
	self._subline = subline

	-- ---- column headers ----------------------------------------------
	-- All six columns, on the arcade ladder. Dropping one "because it looks
	-- cleaner in pastel" is exactly the bug this pack's §0.3 law exists to stop.
	local headerFill = theme.Colors.Surface
	local header = GPMatchFlow.Fill("ColumnHeader", headerFill)
	header.Position = UDim2.fromOffset(0, GP_TABLE_Y)
	header.Size = UDim2.new(1, -SCROLLBAR_RESERVE, 0, GP_HEADER_H)
	header.ZIndex = 4
	header.Parent = content
	GPLayoutKit.CornerSet(theme, header, "Tab")
	GPLayoutKit.SoftStroke(theme, header, headerFill)

	local function headerCell(text: string, x: number, width: number, alignment: Enum.TextXAlignment)
		local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "H_" .. text)
		label.Text = text
		label.TextXAlignment = alignment
		label.Position = UDim2.fromOffset(x, 0)
		label.Size = UDim2.fromOffset(width, GP_HEADER_H)
		label.ZIndex = 5
		label.Parent = header
	end
	headerCell("Rank", COL_RANK_X, COL_RANK_W, Enum.TextXAlignment.Left)
	headerCell("Potter", COL_PLAYER_X, COL_PLAYER_W, Enum.TextXAlignment.Left)
	headerCell("Score", COL_SCORE_R - COL_SCORE_W, COL_SCORE_W, Enum.TextXAlignment.Right)
	headerCell("K", COL_K_R - COL_KD_W, COL_KD_W, Enum.TextXAlignment.Right)
	headerCell("D", COL_D_R - COL_KD_W, COL_KD_W, Enum.TextXAlignment.Right)
	headerCell("MVP", COL_MVP_X, COL_MVP_W, Enum.TextXAlignment.Center)

	-- ---- the standings well -------------------------------------------
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scoreboard"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, GP_ROWS_Y)
	scroll.Size = UDim2.new(1, 0, 0, GP_ROWS_H)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = GPLayoutKit.Deepen(theme, theme.Colors.Surface, 1)
	-- MANDATORY: a scrolled row that escapes its viewport is a known past bug
	-- in this codebase. Clip, and inset so a row's rounded lip is not shaved.
	scroll.ClipsDescendants = true
	scroll.ZIndex = 4
	scroll.Parent = content
	UIStyler.ListLayout({
		Padding = UDim.new(0, GP_ROW_GAP), -- petal corners need air to read
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = scroll
	UIStyler.PaddingXY(0, GP_SCROLL_PAD).Parent = scroll
	self._scroll = scroll

	-- ---- rewards + actions ---------------------------------------------
	local rewards = UIStyler.Frame("Rewards")
	rewards.BackgroundTransparency = 1
	rewards.Position = UDim2.fromOffset(0, GP_REWARDS_Y)
	rewards.Size = UDim2.new(1, 0, 0, GP_REWARDS_H)
	rewards.ZIndex = 4
	rewards.Parent = content
	self._rewardStrip = rewards

	local buttons = UIStyler.Frame("Buttons")
	buttons.BackgroundTransparency = 1
	buttons.Position = UDim2.fromOffset(0, GP_BUTTONS_Y)
	buttons.Size = UDim2.new(1, 0, 0, GP_BUTTON_H)
	buttons.ZIndex = 4
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, spacing.M),
	}).Parent = buttons
	buttons.Parent = content

	-- THROW is the pack's word for going again; the callbacks and toasts are
	-- the classic ones, untouched.
	self._againButton = GPMatchFlow.Button(theme, buttons, {
		text = "Throw again",
		fill = theme.Colors.Secondary,
		sizePx = Vector2.new(320, GP_BUTTON_H),
		index = 0,
		layoutOrder = 1,
		onClick = function()
			self:_Toast("SEARCHING FOR A NEW MATCH", "Success")
			self.ScreenController:HideScreen("matchSummary")
		end,
		sink = shadows,
	})
	self._againButton.Root.ZIndex = 5

	self._leaveButton = GPMatchFlow.Button(theme, buttons, {
		text = "Leave",
		fill = theme.Colors.Surface,
		sizePx = Vector2.new(220, GP_BUTTON_H),
		index = 1,
		layoutOrder = 2,
		onClick = function()
			self:_Toast("RETURNING TO THE LOBBY", "Info")
			self.ScreenController:HideScreen("matchSummary")
		end,
		sink = shadows,
	})
	self._leaveButton.Root.ZIndex = 5

	self:_Render()
end

-- One standings row: the arcade ladder, softened. Deliberately shadow-free —
-- eight hue shadows inside a clipping viewport would both eat the budget and
-- get shaved at the scroll edge; depth comes from the petal and the stroke.
function MatchSummaryScreen:_BuildGPScoreRow(row: ScoreRow, index: number)
	local theme = self:GetTheme()
	local local_ = row.isLocal == true

	-- Local potter first (doc §11.4): a rose row, a butter notch and the
	-- "(you)" suffix lift you out of the zebra without breaking its rhythm.
	local fill = if local_
		then theme.Colors.Primary
		elseif index % 2 == 1 then theme.Colors.SurfaceRaised
		else theme.Colors.Surface
	local frame = GPMatchFlow.Fill("Row" .. index, fill)
	frame.Size = UDim2.new(1, -SCROLLBAR_RESERVE, 0, GP_ROW_H)
	frame.LayoutOrder = index
	frame.ZIndex = 4
	frame.Parent = self._scroll
	-- Alternating by index: the table reads hand-arranged, not stamped.
	GPLayoutKit.Petal(theme, frame, index)
	GPLayoutKit.SoftStroke(theme, frame, fill)

	if local_ then
		local notch = GPMatchFlow.Fill("Notch", theme.Arcade.Gold)
		notch.Position = UDim2.fromOffset(6, 8)
		notch.Size = UDim2.new(0, 5, 1, -16)
		notch.ZIndex = 6
		notch.Parent = frame
		UIStyler.Corner(theme.Radii.Pill).Parent = notch
	end

	-- Body copy on rose is TextPrimary (5.15:1); the near-white is illegal.
	local rank = GPLayoutKit.NumberText(theme, 22, theme.Colors.TextPrimary, "Rank")
	rank.Text = "#" .. tostring(row.rank)
	rank.TextXAlignment = Enum.TextXAlignment.Left
	rank.Position = UDim2.fromOffset(COL_RANK_X + 10, 0)
	rank.Size = UDim2.fromOffset(COL_RANK_W, GP_ROW_H)
	rank.ZIndex = 5
	rank.Parent = frame

	local avatar = GPMatchFlow.AvatarDisc(theme, frame, 38, if local_ then GPLayoutKit.Deepen(theme, fill, 1) else nil)
	avatar.root.AnchorPoint = Vector2.new(0, 0.5)
	avatar.root.Position = UDim2.new(0, COL_PLAYER_X, 0.5, 0)
	avatar.root.ZIndex = 5
	GPMatchFlow.LoadHeadshot(avatar, row.userId)

	local name = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Name")
	name.Text = if local_ then row.name .. " (you)" else row.name
	name.RichText = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(COL_PLAYER_X + 48, 0)
	name.Size = UDim2.fromOffset(COL_PLAYER_W - 48, GP_ROW_H)
	name.ZIndex = 5
	name.Parent = frame

	-- Tabular numerals, right-aligned on their own column edge: this is a
	-- stats game and the digits line up down the table.
	local function numeric(text: string, rightEdge: number, width: number, color: Color3, size: number)
		local label = GPLayoutKit.NumberText(theme, size, color, "N")
		label.Text = text
		label.Position = UDim2.fromOffset(rightEdge - width, 0)
		label.Size = UDim2.fromOffset(width, GP_ROW_H)
		label.ZIndex = 5
		label.Parent = frame
	end
	-- Deaths ride the quiet tone on the zebra plates, but NEVER on the local
	-- potter's ROSE row: TextSecondary measures 2.20:1 there. Law 3 — body copy
	-- on any of this pack's pastels is the plum-brown ink.
	local muted = if local_ then theme.Colors.TextPrimary else theme.Colors.TextSecondary
	numeric(tostring(row.score), COL_SCORE_R, COL_SCORE_W, theme.Colors.TextPrimary, 22)
	numeric(tostring(row.kills), COL_K_R, COL_KD_W, theme.Colors.TextPrimary, 20)
	numeric(tostring(row.deaths), COL_D_R, COL_KD_W, muted, 20)

	if row.mvp then
		local star = GPMatchFlow.Icon(theme, frame, "star", 28, nil, { golden = true })
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.new(0, COL_MVP_X + COL_MVP_W / 2, 0.5, 0)
		star.ZIndex = 5
	end
end

-- One reward cell, built HIDDEN: the classic reveal makes it visible on its
-- stagger beat and pops it in. The total wears butter gold, a glaze sheen and
-- a zero-offset GLOW — this pack blooms where the arcade would shout.
function MatchSummaryScreen:_BuildGPRewardCell(reward: Reward, x: number, width: number, total: boolean, index: number)
	local theme = self:GetTheme()
	local fill = if total then theme.Arcade.Gold else theme.Colors.SurfaceRaised

	local cell = GPMatchFlow.Plate(theme, self._rewardStrip, {
		name = "Reward_" .. reward.label,
		fill = fill,
		index = index,
		shadow = "sm",
		sink = self._gpCellShadows,
	})
	cell.Position = UDim2.fromOffset(x, 0)
	cell.Size = UDim2.fromOffset(width, GP_REWARDS_H)
	cell.ZIndex = 4
	cell.Visible = false
	if total then
		GPLayoutKit.GlazeSheen(theme, cell)
		GPLayoutKit.Glow(theme, cell, fill, self._gpCellShadows)
	end

	local icon = GPMatchFlow.Icon(theme, cell, reward.icon or "star", 44, nil, { golden = total })
	icon.Position = UDim2.fromOffset(theme.Spacing.M, theme.Spacing.M)
	icon.ZIndex = 6

	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Label")
	label.Text = GPMatchFlow.SoftCase(reward.label)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Position = UDim2.fromOffset(68, 20)
	label.Size = UDim2.fromOffset(width - 82, 24)
	label.ZIndex = 6
	label.Parent = cell

	local amount = GPLayoutKit.Text(theme, if total then 40 else 32, theme.Colors.TextPrimary, "Amount")
	amount.Text = "+" .. tostring(math.floor(reward.amount))
	amount.TextXAlignment = Enum.TextXAlignment.Left
	amount.Position = UDim2.fromOffset(theme.Spacing.M, GP_REWARDS_H - 60)
	amount.Size = UDim2.fromOffset(width - theme.Spacing.M * 2, 48)
	amount.ZIndex = 6
	amount.Parent = cell

	table.insert(self._rewardCells, {
		frame = cell,
		amount = amount,
		value = math.floor(reward.amount),
		total = total,
	})
end

function MatchSummaryScreen:_GPRender()
	local theme = self:GetTheme()

	-- Gold marks the winner everywhere (doc §11.4); a misfire wears the pack's
	-- soft coral, never a fire-engine red. The banner is repainted, not rebuilt.
	local verdictFill = if self._won then theme.Arcade.Gold else theme.Colors.Error
	local deep = GPLayoutKit.Deepen(theme, verdictFill, 1)
	local bannerParts = self._gpBanner
	bannerParts.plate.BackgroundColor3 = verdictFill
	bannerParts.stroke.Color = deep
	bannerParts.shadow.Instance.Color = deep

	self._headline.Text = if self._won then "Fired!" else "Misfire"

	local localRow: ScoreRow? = nil
	for _, row in self._rows do
		if row.isLocal then
			localRow = row
		end
	end
	-- Identical numbers to classic, in the pack's voice: placement, score and
	-- the full K/D pair. Nothing is rounded away for looking softer.
	self._subline.Text = if localRow
		then string.format("You placed #%d  ·  %d score  ·  %d / %d K/D", localRow.rank, localRow.score, localRow.kills, localRow.deaths)
		else string.format("%d potters  ·  match complete", #self._rows)

	for _, child in self._scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, row in self._rows do
		self:_BuildGPScoreRow(row, index)
	end

	-- The cells churn on every render, so their shadow budget comes back
	-- BEFORE the rebuild — otherwise a few re-shows quietly exhaust it.
	GPLayoutKit.ReleaseShadows(self._gpCellShadows)
	for _, child in self._rewardStrip:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(self._rewardCells)

	-- Same split and same geometry as classic: equal-width breakdown cells and
	-- a wider gold total at the right end.
	local breakdown: { Reward } = {}
	local total: Reward? = nil
	local sum = 0
	for _, reward in self._rewards do
		if isTotal(reward) then
			total = reward
		else
			table.insert(breakdown, reward)
			sum += reward.amount
		end
	end
	total = total or { label = "TOTAL", amount = sum, icon = "trophy" }

	local totalWidth = 272
	local count = math.max(1, #breakdown)
	local cellWidth = math.floor((GP_FIELD_W - totalWidth - REWARD_GAP * count) / count)
	for index, reward in breakdown do
		self:_BuildGPRewardCell(reward, (index - 1) * (cellWidth + REWARD_GAP), cellWidth, false, index)
	end
	self:_BuildGPRewardCell(total, GP_FIELD_W - totalWidth, totalWidth, true, count + 1)
end

return MatchSummaryScreen
