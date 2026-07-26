--!strict
-- Score + multiplier (HUD widget) at the very top-right: "SCORE 12,400" in
-- gold FredokaOne with a ticker count-up — the displayed number chases the
-- target exponentially and the label only rewrites when the whole number
-- changes, so a big award animates without render-rate text churn.
--
-- Under it, the multiplier chip: "x3" in orange, pulsing when it climbs and
-- fading toward the OWNED grey as its decay timer runs out — the thin gold
-- ruler under the chip is the §8 meter for the time left. At zero the chip
-- quietly reads "x1" in grey rather than vanishing (§11.2 states change in
-- place, nothing disappears).
--
-- "+250" floaters pop by the score and drift up — pooled and reused with the
-- same take/steal discipline as DamageNumbersWidget, because score events in a
-- combo game arrive in bursts and per-event instancing is the §5.4 hitch.

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local HUDWidgetBase = require(script.Parent.HUDWidgetBase)

local ScoreWidget = setmetatable({}, { __index = HUDWidgetBase })
ScoreWidget.__index = ScoreWidget

local COUNT_RATE = 9 -- 1/s exponential chase toward the target
local FLOAT_POOL = 6
local FLOAT_LIFE = 0.8
local FLOAT_RISE = 36
local FADE_START = 0.5

function ScoreWidget.new()
	local self = HUDWidgetBase.new("score", "ScoreWidget")
	-- Demo: spawn mid-count-up so the ticker shows itself immediately.
	self._target = 12400
	self._displayed = 11900
	self._shownWhole = -1
	self._mult = 3
	self._multWindow = 8
	self._multTime = 6.5
	self._floatPool = {} :: { TextLabel }
	self._floatLive = {} :: { any }
	self._random = Random.new()
	return setmetatable(self, ScoreWidget)
end

function ScoreWidget:_Build(props: HUDWidgetBase.Props)
	local theme = self.Theme
	if props.score ~= nil then
		self._target = props.score
		self._displayed = props.score
	end

	local score = UIChrome.Text("Score", 28, theme.Arcade.Gold)
	score.TextXAlignment = Enum.TextXAlignment.Right
	score.Size = UDim2.new(1, 0, 0, 28)
	score.Parent = self.Root
	self._scoreLabel = score

	local chip = UIStyler.Frame("MultChip")
	chip.BackgroundColor3 = theme.Arcade.Row
	chip.BackgroundTransparency = theme.Arcade.RowTransparency
	chip.AnchorPoint = Vector2.new(1, 0)
	chip.Position = UDim2.new(1, 0, 0, 32)
	chip.Size = UDim2.fromOffset(56, 22)
	UIChrome.Corner("Arcade").Parent = chip
	self._chipStroke = UIChrome.Stroke(theme, "Arcade", "Panel")
	self._chipStroke.Parent = chip
	chip.Parent = self.Root
	self._chip = chip

	local multText = UIChrome.Text("Mult", 15, theme.Arcade.Orange)
	multText.Text = "x" .. tostring(self._mult)
	multText.Size = UDim2.fromScale(1, 1)
	multText.ZIndex = 2
	multText.Parent = chip
	self._multText = multText

	local track = UIStyler.Frame("MultTrack")
	track.BackgroundColor3 = theme.Arcade.RulerTrack
	track.AnchorPoint = Vector2.new(1, 0)
	track.Position = UDim2.new(1, 0, 0, 56)
	track.Size = UDim2.fromOffset(56, 4)
	track.Parent = self.Root
	self._multTrack = track

	local fill = UIStyler.Frame("MultFill")
	fill.BackgroundColor3 = theme.Arcade.Gold
	fill.Size = UDim2.new(self._multWindow > 0 and self._multTime / self._multWindow or 0, 0, 1, 0)
	fill.ZIndex = 2
	fill.Parent = track
	self._multFill = fill

	for i = 1, FLOAT_POOL do
		local label = UIChrome.Text("Floater" .. i, 20, theme.Arcade.Gold)
		label.AnchorPoint = Vector2.new(1, 0.5)
		label.Size = UDim2.fromOffset(120, 24)
		label.TextXAlignment = Enum.TextXAlignment.Right
		label.Visible = false
		label.ZIndex = 3
		label.Parent = self.Root
		table.insert(self._floatPool, label)
	end

	self:_RenderStep(function(dt: number, clock: number)
		self:_Step(dt, clock)
	end)

	self:_PopIn(score)
	self:_PushFloater(250) -- demo: one floater in flight on spawn
end

-- ---- data --------------------------------------------------------------

-- data: { score } | { delta } | { multiplier, multiplierTime, multiplierWindow }
function ScoreWidget:Update(data: any)
	if type(data) == "number" then
		data = { score = data }
	end
	if type(data) ~= "table" then
		return
	end
	if data.score ~= nil then
		local delta = data.score - self._target
		self._target = data.score
		if delta > 0 then
			self:_PushFloater(delta)
		end
	end
	if data.delta then
		self._target += data.delta
		if data.delta > 0 then
			self:_PushFloater(data.delta)
		end
	end
	if data.multiplier then
		local up = data.multiplier > self._mult
		self._mult = data.multiplier
		self._multWindow = data.multiplierWindow or self._multWindow
		self._multTime = data.multiplierTime or self._multWindow
		self._multText.Text = "x" .. tostring(self._mult)
		self._multText.TextColor3 = self.Theme.Arcade.Orange
		if up then
			self:_Pulse(self._chip)
		end
	end
end

function ScoreWidget:AddScore(amount: number)
	self:Update({ delta = amount })
end

function ScoreWidget:_PushFloater(amount: number)
	local label = table.remove(self._floatPool)
	if not label then
		-- Pool exhausted: steal the oldest live floater — never allocate.
		local oldest = table.remove(self._floatLive, 1)
		if not oldest then
			return
		end
		label = oldest.label
	end
	assert(label)
	label.Text = "+" .. HUDWidgetBase.Commas(amount)
	label.TextTransparency = 0
	UIChrome.TextOutline(label)
	label.Visible = true
	table.insert(self._floatLive, {
		label = label,
		born = os.clock(),
		drift = self._random:NextNumber(-14, 6),
	})
end

-- ---- per-frame ---------------------------------------------------------

function ScoreWidget:_Step(dt: number, clock: number)
	-- Ticker: chase the target, rewrite only on whole-number changes.
	if self._displayed ~= self._target then
		self._displayed += (self._target - self._displayed) * math.min(dt * COUNT_RATE, 1)
		if math.abs(self._target - self._displayed) < 0.6 then
			self._displayed = self._target
		end
	end
	local whole = math.floor(self._displayed + 0.5)
	if whole ~= self._shownWhole then
		self._shownWhole = whole
		self._scoreLabel.Text = "SCORE " .. HUDWidgetBase.Commas(whole)
	end

	-- Multiplier decay: the ruler drains, the chip greys out with it.
	if self._mult > 1 then
		self._multTime = math.max(self._multTime - dt, 0)
		local frac = self._multWindow > 0 and self._multTime / self._multWindow or 0
		self._multFill.Size = UDim2.new(frac, 0, 1, 0)
		self._multText.TextColor3 = self.Theme.Arcade.Orange:Lerp(self.Theme.Arcade.GreyOwned, 1 - frac)
		if self._multTime <= 0 then
			self._mult = 1
			self._multText.Text = "x1"
			self._multText.TextColor3 = self.Theme.Arcade.GreyOwned
		end
	end

	-- Floaters: ease-out rise with a late fade (the effect-overlay exception
	-- to the no-fades rule, doc §5).
	for i = #self._floatLive, 1, -1 do
		local floater = self._floatLive[i]
		local u = (clock - floater.born) / FLOAT_LIFE
		if u >= 1 then
			floater.label.Visible = false
			table.remove(self._floatLive, i)
			table.insert(self._floatPool, floater.label)
		else
			local eased = 1 - (1 - u) * (1 - u)
			floater.label.Position = UDim2.new(1, -4 + floater.drift * u, 0, 30 - FLOAT_RISE * eased)
			local fade = u <= FADE_START and 0 or (u - FADE_START) / (1 - FADE_START)
			floater.label.TextTransparency = fade
			UIChrome.TextOutline(floater.label, fade)
		end
	end
end

function ScoreWidget:_Style(theme: Types.UITheme)
	if self._scoreLabel then
		self._scoreLabel.FontFace = theme.Fonts.Numeric
		self._scoreLabel.TextColor3 = theme.Arcade.Gold
		UIChrome.TextOutline(self._scoreLabel)
	end
	if self._chip then
		self._chip.BackgroundColor3 = theme.Arcade.Row
		self._chip.BackgroundTransparency = theme.Arcade.RowTransparency
	end
	if self._chipStroke then
		self._chipStroke.Color = theme.Colors.Stroke
	end
	if self._multText then
		self._multText.FontFace = theme.Fonts.Numeric
		self._multText.TextColor3 = self._mult > 1 and theme.Arcade.Orange or theme.Arcade.GreyOwned
		UIChrome.TextOutline(self._multText)
	end
	if self._multTrack then
		self._multTrack.BackgroundColor3 = theme.Arcade.RulerTrack
	end
	if self._multFill then
		self._multFill.BackgroundColor3 = theme.Arcade.Gold
	end
	for _, label in self._floatPool do
		label.FontFace = theme.Fonts.Numeric
		label.TextColor3 = theme.Arcade.Gold
		UIChrome.TextOutline(label)
	end
	for _, floater in self._floatLive do
		floater.label.FontFace = theme.Fonts.Numeric
		floater.label.TextColor3 = theme.Arcade.Gold
	end
end

return ScoreWidget
