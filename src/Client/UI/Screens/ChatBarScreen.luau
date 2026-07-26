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
	self._bar.BackgroundColor3 = theme.Arcade.Panel
	self._speaker.TextColor3 = theme.Arcade.Gold
	self._body.TextColor3 = theme.Colors.TextPrimary
end

function ChatBarScreen:_OnHide()
	self._typing = false
	self._typeToken = {}
end

return ChatBarScreen
