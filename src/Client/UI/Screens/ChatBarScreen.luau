--!strict
-- Bottom-of-screen speech bar — the on-screen (UI) counterpart to the overhead
-- chat bubble. An arcade slate bar pinned to the bottom that types out a line
-- with an optional speaker name, then auto-hides. Use it for narration,
-- subtitles, radio chatter, quest voice-over — anything that reads as "someone
-- is talking" without the full NPCDialogScreen panel or an above-head bubble.
--
-- Show({ speaker = "Radio", text = "...", duration = 4, typeSpeed = 50 }) or feed
-- a queue of lines; each types, holds, then the next plays.
--
-- Arcade family (doc §1): slate panel, 3px black stroke, hard 90° corners,
-- glass sheen; FredokaOne with full black outlines. Authored in fixed px at
-- the 1650×1020 baseline (UIScreenBase attaches the UIScale).

local RunService = game:GetService("RunService")

local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIScreenBase = require(script.Parent.UIScreenBase)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)

local ChatBarScreen = setmetatable({}, { __index = UIScreenBase })
ChatBarScreen.__index = ChatBarScreen

function ChatBarScreen.new()
	local self = UIScreenBase.new("ChatBarScreen", 15)
	self._queue = {}
	self._typing = false
	self._typeToken = {}
	return setmetatable(self, ChatBarScreen)
end

function ChatBarScreen:_BuildContent()
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
	local theme = self:GetTheme()

	-- The bar: arcade slate panel (UIChrome.Panel = hard corners + 3px black
	-- stroke + glass gradient) at 10% transparency, pinned bottom-centre.
	local bar = UIChrome.Panel(theme, "Arcade", "Bar")
	bar.BackgroundTransparency = 0.1
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -60)
	bar.Size = UDim2.fromOffset(880, 130)
	bar.Parent = self.Root
	self._bar = bar
	UIStyler.PaddingXY(18, 12).Parent = bar

	-- Speaker line (top, hidden when no speaker): gold display text.
	local speaker = UIChrome.Text("Speaker", 20, theme.Arcade.Gold)
	speaker.Size = UDim2.new(1, 0, 0, 24)
	speaker.TextXAlignment = Enum.TextXAlignment.Left
	speaker.RichText = false
	speaker.TextTruncate = Enum.TextTruncate.AtEnd
	speaker.ZIndex = 2
	speaker.Parent = bar
	self._speaker = speaker

	-- Body (typewriter target): white display text, wrapped, fixed 24px.
	local body = UIChrome.Text("Body", 24, theme.Colors.TextPrimary)
	body.Position = UDim2.fromOffset(0, 28)
	body.Size = UDim2.new(1, 0, 1, -28)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.RichText = false
	body.TextWrapped = true
	body.ZIndex = 2
	body.Parent = bar
	self._body = body

	-- Click anywhere on the bar skips the type / advances (every tap answers).
	local hit = Instance.new("TextButton")
	hit.Name = "Advance"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 3
	hit.Parent = bar
	hit.Activated:Connect(function()
		self:_OnClick()
	end)
end

-- ---- GIRLY POP (theme.LayoutKit == "GP") ------------------------------
-- The same bottom speech bar as a STUDIO SLIP: a cream paper plate with petal
-- corners, a scalloped top lip, clay-speckle grain and a soft HUE-MATCHED
-- shadow (the plate's own fill deepened — never grey). The speaker's name is a
-- rose nameplate rather than gold type, because butter gold on cream is a
-- 1.6:1 caption; ink on rose is 5.15:1. Body copy stays the pack's warm plum
-- ink — the classic bar types in pure white, which this pack forbids outright.
--
-- Same instances under the same field names (_bar/_speaker/_body), so
-- _Next, _TypeLine, _OnClick and _Repaint drive this layout unchanged.
function ChatBarScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	local spacing = theme.Spacing
	self._gpShadows = {}

	local barFill = theme.Colors.Background
	local bar = UIStyler.Frame("Bar")
	bar.BackgroundColor3 = barFill
	bar.BackgroundTransparency = 0
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -60)
	bar.Size = UDim2.fromOffset(880, 130)
	bar.Parent = self.Root
	-- Petal FIRST: GlazeSheen and the scallop both read the host's corner, and
	-- CornerSet clears any stale UICorner so only one ever exists.
	GPLayoutKit.Petal(theme, bar, 0)
	GPLayoutKit.SoftStroke(theme, bar)
	GPLayoutKit.Shadow(theme, bar, "md", self._gpShadows, barFill)
	self._bar = bar

	-- Matte studio grain: this is a reading surface, so it stays flat (the
	-- glossy glaze dialect is for celebration screens).
	local studio = ((theme :: any).DialectTokens or {}).studio or {}
	local grain = GPLayoutKit.Tile(
		theme,
		studio.patternKey or "speckle",
		GPLayoutKit.Deepen(theme, barFill, 1),
		studio.speckleTransparency or 0.94,
		"ClayGrain"
	)
	grain.ZIndex = 1
	grain.Parent = bar

	-- The doily lip on top. Safe here: the bar is free-floating page chrome,
	-- never inside a scrolling viewport (the rotated-descendant clip caveat).
	GPLayoutKit.Scallop(theme, bar, "Top", barFill)

	-- Speaker nameplate: the LABEL itself is the chip, so _Next's
	-- `self._speaker.Visible = false` hides the plate with it.
	local speakerFill = theme.Colors.Primary
	local speaker = GPLayoutKit.Text(theme, 20, theme.Colors.TextPrimary, "Speaker")
	speaker.BackgroundColor3 = speakerFill
	speaker.BackgroundTransparency = 0
	speaker.AutomaticSize = Enum.AutomaticSize.X
	speaker.Position = UDim2.fromOffset(spacing.L, spacing.M)
	speaker.Size = UDim2.fromOffset(0, 30)
	speaker.TextXAlignment = Enum.TextXAlignment.Left
	speaker.RichText = false
	speaker.TextTruncate = Enum.TextTruncate.AtEnd
	speaker.ZIndex = 3
	speaker.Parent = bar
	UIStyler.PaddingXY(12, 0).Parent = speaker
	GPLayoutKit.CornerSet(theme, speaker, "Leaf")
	GPLayoutKit.SoftStroke(theme, speaker, speakerFill)
	self._speaker = speaker

	local body = GPLayoutKit.Text(theme, 24, theme.Colors.TextPrimary, "Body")
	body.Position = UDim2.fromOffset(spacing.L, spacing.M + 34)
	body.Size = UDim2.new(1, -spacing.L * 2, 1, -(spacing.M * 2 + 34))
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.RichText = false
	body.TextWrapped = true
	body.ZIndex = 3
	body.Parent = bar
	self._body = body

	local hit = Instance.new("TextButton")
	hit.Name = "Advance"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 4
	hit.Parent = bar
	hit.Activated:Connect(function()
		self:_OnClick()
	end)
end

-- Public: show a single line or queue several. `data.lines` = { {speaker,text,...} }.
function ChatBarScreen:Show(data: any?)
	UIScreenBase.Show(self, data)
end

function ChatBarScreen:_OnShow(data: any?)
	self._queue = {}
	if data and data.lines then
		for _, l in data.lines do
			table.insert(self._queue, l)
		end
	elseif data then
		table.insert(self._queue, data)
	end
	self:_Repaint()
	self:_Next()
end

function ChatBarScreen:_Next()
	local line = table.remove(self._queue, 1)
	if not line then
		self.ScreenController:HideScreen("chatBar")
		return
	end
	self._current = line
	self._speaker.Text = line.speaker or ""
	self._speaker.Visible = (line.speaker ~= nil and line.speaker ~= "")
	self:_TypeLine(line)
end

function ChatBarScreen:_TypeLine(line: any)
	local full = line.text or ""
	self._fullText = full
	self._typing = true
	self._body.Text = ""
	local token = {}
	self._typeToken = token
	local speed = line.typeSpeed or 50
	local duration = line.duration or 3.5
	task.spawn(function()
		local acc, shown = 0, 0
		while shown < #full and self._typing and self._typeToken == token do
			local dt = RunService.Heartbeat:Wait()
			acc += dt * speed
			local target = math.min(#full, math.floor(acc))
			if target > shown then
				shown = target
				local byteEnd = (utf8.offset(full, shown + 1) or (#full + 1)) - 1
				self._body.Text = string.sub(full, 1, byteEnd)
			end
		end
		if self._typeToken ~= token then
			return
		end
		self._typing = false
		self._body.Text = full
		-- Auto-advance after holding, unless another click already advanced.
		task.wait(duration)
		if self._typeToken == token then
			self:_Next()
		end
	end)
end

function ChatBarScreen:_OnClick()
	if self._typing then
		-- Reveal the whole line instantly, then RE-ARM the auto-advance with
		-- the line's own hold duration — one click skips the type, and the bar
		-- still moves on by itself (no second click ever required).
		local token = {}
		self._typeToken = token
		self._typing = false
		self._body.Text = self._fullText
		local duration = (self._current and self._current.duration) or 3.5
		task.delay(duration, function()
			if self._typeToken == token then
				self:_Next()
			end
		end)
	else
		self._typeToken = {}
		self:_Next()
	end
end

function ChatBarScreen:_Repaint()
	-- Colours re-read from the active theme on each show (chrome — the 3px
	-- black stroke, hard corners and glass sheen — is policy, never repainted).
	local theme = self:GetTheme()
	if self:LayoutKit() == "GP" then
		-- The pack's paper/ink/rose triad. The classic line would repaint the
		-- plate slate, the name butter-gold on cream (1.6:1) and leave the body
		-- ink — this keeps the nameplate legible and the paper warm.
		self._bar.BackgroundColor3 = theme.Colors.Background
		self._speaker.BackgroundColor3 = theme.Colors.Primary
		self._speaker.TextColor3 = theme.Colors.TextPrimary
		self._body.TextColor3 = theme.Colors.TextPrimary
		return
	end
	self._bar.BackgroundColor3 = theme.Arcade.Panel
	self._speaker.TextColor3 = theme.Arcade.Gold
	self._body.TextColor3 = theme.Colors.TextPrimary
end

function ChatBarScreen:_OnHide()
	self._typing = false
	self._typeToken = {}
end

-- A style rebuild destroys the Gui, but the UIShadow BUDGET only falls when a
-- handle is released — hand the GP plate's shadow back here.
function ChatBarScreen:_OnTeardown()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
end

return ChatBarScreen
