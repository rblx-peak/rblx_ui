--!strict
-- DUEL RESULT — ported from Brick Game's DuelController showResults onto the
-- Pottery Clash chrome.
--
-- This is the ONE cinematic screen that dims the world (doc §11.8): VS intro
-- and the waiting lobby are boxless over a staged camera shot, but results sit
-- behind a black scrim @ 0.4 so the numbers read.
--
-- Doc §11.4 conventions, kept literally from the source:
--   * the local player sorts LEFTMOST and carries a "(you)" suffix;
--   * gold marks the winner EVERYWHERE — headline, name, percent and the glow
--     pad behind their column;
--   * a defeat headline goes Arcade.Red, a tie stays white.
--
-- Avatar headshots come from Players:GetUserThumbnailAsync inside a pcall on a
-- spawned thread (it yields and can throw), with the boxless player icon
-- standing in until — or instead of — the real headshot.

local Players = game:GetService("Players")

local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIScreenBase = require(script.Parent.UIScreenBase)
local ACLayoutKit = require(script.Parent.Parent.Framework.ACLayoutKit)

export type PlayerResult = {
	name: string,
	userId: number?,
	score: number?,
	isLocal: boolean?,
}

-- Fixed px at the 1650×1020 baseline.
local COL_W, COL_H = 420, 400
local COL_PITCH = 460
local HEAD = 200
local COLUMNS_Y = 0.56

-- AC layout (theme.LayoutKit == "AC") fixed px: the centred readout panel.
local AC_PANEL_W = 460
local AC_PANEL_H = 300

local DEMO_RESULTS: { PlayerResult } = {
	{ name = "ClayCrusher", score = 82, isLocal = true },
	{ name = "KilnKing", score = 67 },
}

local DuelResultScreen = setmetatable({}, { __index = UIScreenBase })
DuelResultScreen.__index = DuelResultScreen

function DuelResultScreen.new()
	local self = UIScreenBase.new("DuelResultScreen", 50)
	self._won = true
	self._headline = nil :: string?
	self._results = DEMO_RESULTS :: { PlayerResult }
	self._renderGen = 0
	self._columns = {} :: { Frame }
	return setmetatable(self, DuelResultScreen)
end

-- ========================================================================
-- Build
-- ========================================================================

function DuelResultScreen:_BuildContent()
	if self:LayoutKit() == "AC" then
		self:_BuildACLayout()
		return
	end

	local theme = self:GetTheme()

	-- The scrim: results are the only cinematic screen that dims (doc §11.8).
	local scrim = UIStyler.Frame("Scrim")
	scrim.BackgroundColor3 = theme.Colors.Overlay
	scrim.BackgroundTransparency = 0.4
	scrim.ZIndex = 20
	scrim.Parent = self.Root
	self._scrim = scrim

	local content = UIStyler.Frame("Content")
	content.BackgroundTransparency = 1
	content.ZIndex = 21
	content.Parent = scrim
	self._content = content

	-- YOU WIN, FredokaOne 76 (doc §2 type scale).
	local headline = UIChrome.Text("Headline", 76, theme.Arcade.Gold)
	headline.Text = ""
	headline.Position = UDim2.fromOffset(0, 42)
	headline.Size = UDim2.new(1, 0, 0, 92)
	headline.ZIndex = 22
	headline.Parent = content
	self._headlineLabel = headline

	local tally = UIChrome.Text("Tally", 44, theme.Arcade.SunburstGold)
	tally.Text = ""
	tally.Position = UDim2.fromOffset(0, 136)
	tally.Size = UDim2.new(1, 0, 0, 52)
	tally.ZIndex = 22
	tally.Parent = content
	self._tally = tally

	self._continue = UIButtonComponent.new()
	self._continue:Create(content, {
		text = "CONTINUE",
		variant = "Green",
		size = UDim2.fromOffset(260, 62),
		position = UDim2.new(0.5, 0, 1, -46),
		anchorPoint = Vector2.new(0.5, 1),
		onClick = function()
			self.ScreenController:HideScreen("duelResult")
		end,
	})
	self._continue.Root.ZIndex = 23
end

-- ========================================================================
-- AC layout (theme.LayoutKit == "AC")
-- ========================================================================

-- The AC results readout: same cinematic scrim, then a bracketed terminal
-- panel — mono verdict between hairline rules, dense name/score rows with
-- hard-square win pips, and a hairline CONTINUE action.
function DuelResultScreen:_BuildACLayout()
	local theme = self:GetTheme()

	-- Scrim at the classic 0.4 (doc §11.8) — results still dim the world.
	local scrim = UIStyler.Frame("Scrim")
	scrim.BackgroundColor3 = theme.Colors.Overlay
	scrim.BackgroundTransparency = 0.4
	scrim.ZIndex = 20
	scrim.Parent = self.Root
	self._scrim = scrim

	local content = UIStyler.Frame("Content")
	content.BackgroundTransparency = 1
	content.ZIndex = 21
	content.Parent = scrim
	self._content = content

	local panel = UIStyler.Frame("Readout")
	panel.BackgroundTransparency = 1
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.46)
	panel.Size = UDim2.fromOffset(AC_PANEL_W, AC_PANEL_H)
	panel.ZIndex = 22
	panel.Parent = content
	ACLayoutKit.Brackets(theme, panel)

	local ruleTop = ACLayoutKit.Rule(theme, panel, 0.5)
	ruleTop.Position = UDim2.fromOffset(0, 0)
	ruleTop.ZIndex = 22

	-- Verdict — text and colour mapping are applied per render (accent win /
	-- error loss / plain tie, exactly the classic mapping).
	local headline = UIChrome.Text("Headline", 18, theme.Colors.TextPrimary)
	headline.RichText = false
	headline.Text = ""
	headline.Position = UDim2.fromOffset(0, 10)
	headline.Size = UDim2.new(1, 0, 0, 24)
	headline.ZIndex = 22
	headline.Parent = panel
	self._headlineLabel = headline

	local tally = UIChrome.BodyText("Tally", 12, theme.Colors.TextSecondary)
	tally.RichText = false
	tally.Text = ""
	tally.FontFace = theme.Fonts.Numeric
	tally.Position = UDim2.fromOffset(0, 36)
	tally.Size = UDim2.new(1, 0, 0, 16)
	tally.ZIndex = 22
	tally.Parent = panel
	self._tally = tally

	local ruleMid = ACLayoutKit.Rule(theme, panel, 0.5)
	ruleMid.Position = UDim2.fromOffset(0, 60)
	ruleMid.ZIndex = 22

	-- Result rows land here per render.
	local rows = UIStyler.Frame("Rows")
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.fromOffset(0, 70)
	rows.Size = UDim2.new(1, 0, 0, 150)
	rows.ZIndex = 22
	UIStyler.ListLayout({ Padding = UDim.new(0, 2) }).Parent = rows
	rows.Parent = panel
	self._acRows = rows

	local continueButton = ACLayoutKit.ActionButton(theme, panel, "CONTINUE", function()
		self.ScreenController:HideScreen("duelResult")
	end)
	continueButton.AnchorPoint = Vector2.new(0.5, 1)
	continueButton.Position = UDim2.new(0.5, 0, 1, -14)
	continueButton.ZIndex = 23

	-- Destroy() is the only surface the lifecycle needs from _continue.
	self._continue = {
		Root = continueButton,
		Destroy = function()
			continueButton:Destroy()
		end,
	} :: any
end

-- One dense result row: hard-square pip (accent filled = won, hairline
-- empty = lost — the screen carries no per-round tally, so the pip marks
-- the match outcome per row), mono name and percent.
function DuelResultScreen:_BuildACRow(result: PlayerResult, index: number, winner: boolean): Frame
	local theme = self:GetTheme()
	local ink = if winner then theme.Colors.Accent else theme.Colors.TextPrimary

	local row = UIStyler.Frame("Result" .. index)
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 26)
	row.LayoutOrder = index
	row.ZIndex = 23
	row.Parent = self._acRows
	table.insert(self._columns, row)

	local pip = UIStyler.Frame("Pip")
	pip.AnchorPoint = Vector2.new(0, 0.5)
	pip.Position = UDim2.new(0, 4, 0.5, 0)
	pip.Size = UDim2.fromOffset(10, 10)
	pip.ZIndex = 23
	if winner then
		pip.BackgroundColor3 = theme.Colors.Accent
	else
		pip.BackgroundTransparency = 1
		UIStyler.Stroke(theme.Colors.Accent, 1, 0.4).Parent = pip
	end
	pip.Parent = row

	-- "you" always carries the suffix (doc §11.4), uppercased with the row.
	local name = UIChrome.BodyText("Name", 12, ink)
	name.RichText = false
	name.Text = string.upper(result.name .. (if result.isLocal then " (you)" else ""))
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(24, 0)
	name.Size = UDim2.new(1, -110, 1, 0)
	name.ZIndex = 23
	name.Parent = row

	local score = UIChrome.BodyText("Score", 12, ink)
	score.RichText = false
	score.Text = string.format("%d%%", math.floor(result.score or 0))
	score.FontFace = theme.Fonts.Numeric
	score.TextXAlignment = Enum.TextXAlignment.Right
	score.AnchorPoint = Vector2.new(1, 0)
	score.Position = UDim2.new(1, -4, 0, 0)
	score.Size = UDim2.fromOffset(80, 26)
	score.ZIndex = 23
	score.Parent = row

	local underline = ACLayoutKit.Rule(theme, row, 0.85)
	underline.AnchorPoint = Vector2.new(0, 1)
	underline.Position = UDim2.new(0, 0, 1, 0)

	return row
end

-- The AC render: verdict + dense rows. Same ordering, tie/winner math,
-- sound and pop flow as the classic render (doc §11.4).
function DuelResultScreen:_RenderACLayout()
	local theme = self:GetTheme()
	self._renderGen += 1

	for _, column in self._columns do
		column:Destroy()
	end
	table.clear(self._columns)

	-- Local player LEFTMOST becomes local player TOPMOST, then descending
	-- score — the same comparator as classic.
	local order = table.clone(self._results)
	table.sort(order, function(a, b)
		local ka = if a.isLocal then 0 else 1
		local kb = if b.isLocal then 0 else 1
		if ka ~= kb then
			return ka < kb
		end
		return (a.score or 0) > (b.score or 0)
	end)

	local best, bestCount = -math.huge, 0
	for _, result in order do
		local score = result.score or 0
		if score > best then
			best, bestCount = score, 1
		elseif score == best then
			bestCount += 1
		end
	end
	local tie = bestCount > 1

	if self._headline then
		self._headlineLabel.Text = self._headline
	else
		self._headlineLabel.Text = if tie then "IT'S A TIE!" elseif self._won then "YOU WIN" else "DEFEAT"
	end
	self._headlineLabel.TextColor3 = if tie
		then theme.Colors.TextPrimary
		elseif self._won then theme.Colors.Accent
		else theme.Colors.Error

	local scores = {}
	for _, result in order do
		table.insert(scores, string.format("%d", math.floor(result.score or 0)))
	end
	self._tally.Text = table.concat(scores, "   -   ")

	for index, result in order do
		local winner = not tie and (result.score or 0) == best
		self:_BuildACRow(result, index, winner)
	end

	UIChrome.PopIn(theme, self._content)
	self:_PlaySound(if self._won and not tie then "Success" else "Error")
end

-- ========================================================================
-- Result columns
-- ========================================================================

function DuelResultScreen:_LoadHeadshot(image: ImageLabel, fallback: GuiObject, userId: number?, gen: number)
	if not userId or userId <= 0 then
		return
	end
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size150x150
			)
		end)
		if not ok or type(content) ~= "string" or content == "" then
			return
		end
		if gen ~= self._renderGen or not image.Parent then
			return
		end
		image.Image = content
		image.Visible = true
		fallback.Visible = false
	end)
end

function DuelResultScreen:_BuildColumn(result: PlayerResult, index: number, count: number, winner: boolean, gen: number): Frame
	local theme = self:GetTheme()
	local accent = if winner then theme.Arcade.Gold else theme.Colors.TextPrimary

	local column = UIStyler.Frame("Result" .. index)
	column.BackgroundTransparency = 1
	column.AnchorPoint = Vector2.new(0.5, 0.5)
	column.Position = UDim2.new(0.5, (index - (count + 1) / 2) * COL_PITCH, COLUMNS_Y, 0)
	column.Size = UDim2.fromOffset(COL_W, COL_H)
	column.ZIndex = 22
	column.Parent = self._content
	table.insert(self._columns, column)

	-- Gold glow pad behind the winner (the source's buildProfileVP treatment).
	if winner then
		local glow = UIStyler.Frame("Glow")
		glow.BackgroundColor3 = theme.Arcade.Gold
		glow.BackgroundTransparency = 0.45
		glow.AnchorPoint = Vector2.new(0.5, 0)
		glow.Position = UDim2.new(0.5, 0, 0, 12)
		glow.Size = UDim2.fromOffset(HEAD + 76, HEAD + 40)
		glow.ZIndex = 22
		UIChrome.Corner("Arcade", "Wheel").Parent = glow
		glow.Parent = column
	end

	local headSlot = UIStyler.Frame("Head")
	headSlot.BackgroundColor3 = theme.Arcade.NearBlack
	headSlot.AnchorPoint = Vector2.new(0.5, 0)
	headSlot.Position = UDim2.new(0.5, 0, 0, 32)
	headSlot.Size = UDim2.fromOffset(HEAD, HEAD)
	headSlot.ClipsDescendants = true
	headSlot.ZIndex = 23
	UIChrome.Corner("Arcade", "Pill").Parent = headSlot
	-- Gold ring on the winner, plain black policy stroke on everyone else.
	if winner then
		UIStyler.Stroke(theme.Arcade.Gold, 4, 0).Parent = headSlot
	else
		UIChrome.Stroke(theme, "Arcade").Parent = headSlot
	end
	headSlot.Parent = column

	local fallback = IconArchive.Image(headSlot, "player", HEAD - 64)
	fallback.AnchorPoint = Vector2.new(0.5, 0.5)
	fallback.Position = UDim2.fromScale(0.5, 0.5)
	fallback.ZIndex = 24

	local head = Instance.new("ImageLabel")
	head.Name = "Headshot"
	head.BackgroundTransparency = 1
	head.ScaleType = Enum.ScaleType.Fit
	head.AnchorPoint = Vector2.new(0.5, 0.5)
	head.Position = UDim2.fromScale(0.5, 0.5)
	head.Size = UDim2.fromScale(1, 1)
	head.Visible = false
	head.ZIndex = 25
	head.Parent = headSlot
	self:_LoadHeadshot(head, fallback, result.userId, gen)

	if winner then
		local crown = IconArchive.Image(column, "crown", 64, { golden = true })
		crown.AnchorPoint = Vector2.new(0.5, 0.5)
		crown.Position = UDim2.new(0.5, 0, 0, 26)
		crown.ZIndex = 26
	end

	-- "you" always carries the suffix (doc §11.4).
	local name = UIChrome.Text("Name", 30, accent)
	name.Text = result.name .. (if result.isLocal then " (you)" else "")
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.new(0.5, 0, 0, HEAD + 52)
	name.Size = UDim2.fromOffset(COL_W - 20, 38)
	name.ZIndex = 24
	name.Parent = column

	-- Result percent, FredokaOne 70 (doc §2), gold on the winner.
	local percent = UIChrome.Text("Percent", 70, accent)
	percent.Text = string.format("%d%%", math.floor(result.score or 0))
	percent.AnchorPoint = Vector2.new(0.5, 0)
	percent.Position = UDim2.new(0.5, 0, 0, HEAD + 96)
	percent.Size = UDim2.fromOffset(COL_W - 20, 84)
	percent.ZIndex = 24
	percent.Parent = column

	return column
end

-- ========================================================================
-- Render
-- ========================================================================

function DuelResultScreen:_Render()
	if self:LayoutKit() == "AC" then
		self:_RenderACLayout()
		return
	end

	local theme = self:GetTheme()
	self._renderGen += 1
	local gen = self._renderGen

	for _, column in self._columns do
		column:Destroy()
	end
	table.clear(self._columns)

	-- Local player LEFTMOST, then descending score (doc §11.4).
	local order = table.clone(self._results)
	table.sort(order, function(a, b)
		local ka = if a.isLocal then 0 else 1
		local kb = if b.isLocal then 0 else 1
		if ka ~= kb then
			return ka < kb
		end
		return (a.score or 0) > (b.score or 0)
	end)

	-- The winner is the single highest score; a shared top score is a tie and
	-- nothing gets the gold treatment.
	local best, bestCount = -math.huge, 0
	for _, result in order do
		local score = result.score or 0
		if score > best then
			best, bestCount = score, 1
		elseif score == best then
			bestCount += 1
		end
	end
	local tie = bestCount > 1

	if self._headline then
		self._headlineLabel.Text = self._headline
	else
		self._headlineLabel.Text = if tie then "IT'S A TIE!" elseif self._won then "YOU WIN" else "DEFEAT"
	end
	self._headlineLabel.TextColor3 = if tie
		then theme.Colors.TextPrimary
		elseif self._won then theme.Arcade.Gold
		else theme.Arcade.Red

	local scores = {}
	for _, result in order do
		table.insert(scores, string.format("%d", math.floor(result.score or 0)))
	end
	self._tally.Text = table.concat(scores, "   -   ")

	local count = #order
	for index, result in order do
		local winner = not tie and (result.score or 0) == best
		self:_BuildColumn(result, index, count, winner, gen)
	end

	-- Open is an instant flip (base); the pop lives on the CONTENT (doc §7.4).
	UIChrome.PopIn(theme, self._content)
	self:_PlaySound(if self._won and not tie then "Success" else "Error")
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function DuelResultScreen:_OnShow(data: any?)
	if type(data) == "table" then
		if type(data.won) == "boolean" then
			self._won = data.won
		end
		-- Reset first: a payload without a headline must fall back to the
		-- derived one, not inherit the previous match's override.
		self._headline = if type(data.headline) == "string" then data.headline else nil
		if type(data.results) == "table" and #data.results > 0 then
			self._results = data.results
		end
	end
	self:_Render()
end

function DuelResultScreen:_OnHide()
	-- Orphans any in-flight headshot fetch.
	self._renderGen += 1
end

function DuelResultScreen:Update(data: any)
	if self._built and self:IsVisible() then
		self:_OnShow(data)
	end
end

function DuelResultScreen:Destroy()
	self:_OnHide()
	if self._continue then
		self._continue:Destroy()
		self._continue = nil
	end
	UIScreenBase.Destroy(self)
end

return DuelResultScreen
