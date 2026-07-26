--!strict
-- Overhead chat bubbles, Pottery Clash world-space grammar (doc §9): BOXLESS —
-- no bubble surface, no frame stroke; the world is the background. The "bubble"
-- is white FredokaOne 20 text with a black TEXT stroke at 0.2 (set directly
-- here — billboards live outside the ScreenGui style enforcers), plus the
-- little ▼ speaker tail. It types its text out, holds, then fades and
-- self-destroys (a fade is allowed here: it's an overlay effect, doc §5).
-- This is the ambient over-head chatter counterpart to the anchored
-- NPCDialogScreen panel — use it for barks, emotes, player chat, mob taunts.
--
-- Usage (from a controller/handler with the theme controller):
--   local chat = UIChatBubbleController.new(themeController)
--   chat:Say(character, "Hello there!")            -- default duration
--   chat:Say(character, "...", { duration = 2, typeSpeed = 60, tail = true })
--
-- Multiple Say calls on one character stack: the newest replaces the visible
-- bubble (a real barks system rarely shows two at once over one head). Fully
-- theme-driven and re-skins live like every other piece.

local RunService = game:GetService("RunService")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)

local UIChatBubbleController = {}
UIChatBubbleController.__index = UIChatBubbleController

export type ChatBubbleController = typeof(setmetatable({} :: {
	_themeController: any,
	_active: { [Instance]: any },
}, UIChatBubbleController))

-- How high above the head the bubble floats (studs) — clear of the +3 nameplate.
local OFFSET_Y = 3.4
-- Fixed px billboard footprint (doc §9 formula) + the distance ladder: chat
-- bubbles reach 70 studs (crate-preview tier), nameplates 90.
local MAX_WIDTH = 280
local BILLBOARD_HEIGHT = 100
local MAX_DISTANCE = 70
-- World text: display font 20, text emphasis relaxed to 0.2 (doc §2 ladder).
local TEXT_SIZE = 20
local TEXT_STROKE_TRANSPARENCY = 0.2
local TAIL_HEIGHT = 14
local DEFAULT_DURATION = 3.5
local DEFAULT_TYPE_SPEED = 55

function UIChatBubbleController.new(themeController: any): ChatBubbleController
	local self = setmetatable({}, UIChatBubbleController)
	self._themeController = themeController
	self._active = {}
	-- Deferred a frame (the same pattern as UIScreenBase's deferred rebuild)
	-- so the ClientHandler handler that refreshes UIChrome's active style
	-- runs first — _StyleEntry consults that policy through TextOutline.
	if themeController and themeController.ThemeChanged then
		themeController.ThemeChanged:Connect(function()
			task.defer(function()
				self:_RestyleAll()
			end)
		end)
	end
	return self :: any
end

local function adornPart(character: Instance): BasePart?
	if character:IsA("Model") then
		return (character:FindFirstChild("Head") :: BasePart?)
			or (character :: Model).PrimaryPart
			or (character:FindFirstChildWhichIsA("BasePart") :: BasePart?)
	end
	return character:IsA("BasePart") and character or nil
end

-- Show a bubble over `character`. Replaces any bubble already on that character.
function UIChatBubbleController:Say(character: Instance, text: string, opts: { duration: number?, typeSpeed: number?, tail: boolean? }?)
	local part = adornPart(character)
	if not part then
		return
	end
	-- Clear an existing bubble on this character (newest wins).
	self:_Clear(character)

	local theme: Types.UITheme = self._themeController:GetTheme()

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ChatBubble"
	billboard.Adornee = part
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MAX_DISTANCE
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.StudsOffsetWorldSpace = Vector3.new(0, OFFSET_Y, 0)
	billboard.Size = UDim2.fromOffset(MAX_WIDTH, BILLBOARD_HEIGHT)
	billboard.SizeOffset = Vector2.new(0, 0.5)

	-- Boxless: the outlined text IS the bubble. It auto-sizes to the wrapped
	-- string and grows upward from the bottom of the billboard.
	local label = UIChrome.Text("Text", TEXT_SIZE, theme.Colors.TextPrimary)
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -TAIL_HEIGHT) -- leave room for the tail
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 0)
	label.RichText = false
	label.TextWrapped = true
	-- Cap width so long lines wrap instead of stretching off-screen.
	local sizeCap = Instance.new("UISizeConstraint")
	sizeCap.MaxSize = Vector2.new(MAX_WIDTH, math.huge)
	sizeCap.Parent = label
	label.Parent = billboard

	-- Little speaker tail pointing down at the head. FontFace MUST be assigned
	-- or ▼ renders on the symbol-incapable engine default (LegacyArial bug);
	-- the display font carries ▼ (doc §10 unicode set).
	local tail = UIStyler.TextLabel("Tail")
	tail.Size = UDim2.fromOffset(20, TAIL_HEIGHT)
	tail.AnchorPoint = Vector2.new(0.5, 0)
	tail.Position = UDim2.fromScale(0.5, 1)
	tail.FontFace = theme.Fonts.Title
	tail.Text = "▼"
	tail.TextScaled = true -- LAST wrap-related assignment (engine landmine)
	tail.Visible = not (opts and opts.tail == false)
	tail.Parent = label

	billboard.Parent = part

	local entry = {
		billboard = billboard,
		label = label,
		tail = tail,
		fullText = text,
		typeToken = {},
	}
	self._active[character] = entry
	self:_StyleEntry(entry, theme)

	-- Type it out (utf8-safe so emoji reveal cleanly), then hold + fade.
	local typeSpeed = (opts and opts.typeSpeed) or DEFAULT_TYPE_SPEED
	local duration = (opts and opts.duration) or DEFAULT_DURATION
	self:_TypeThenFade(character, entry, typeSpeed, duration)

	-- Auto-clean if the character leaves.
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			self:_Clear(character)
		end
	end)
end

function UIChatBubbleController:_TypeThenFade(character: Instance, entry: any, speed: number, duration: number)
	local token = {}
	entry.typeToken = token
	local full = entry.fullText
	entry.label.Text = ""
	task.spawn(function()
		local acc = 0
		local shown = 0
		while shown < #full and entry.typeToken == token and entry.billboard.Parent do
			local dt = RunService.Heartbeat:Wait()
			acc += dt * speed
			local target = math.min(#full, math.floor(acc))
			if target > shown then
				shown = target
				local byteEnd = (utf8.offset(full, shown + 1) or (#full + 1)) - 1
				entry.label.Text = string.sub(full, 1, byteEnd)
			end
		end
		if entry.typeToken ~= token then
			return
		end
		entry.label.Text = full
		-- Hold, then fade out and clear (the one sanctioned opacity tween:
		-- it's an overlay effect, not a panel show/hide).
		task.wait(duration)
		if entry.typeToken ~= token or not entry.billboard.Parent then
			return
		end
		local theme = self._themeController:GetTheme()
		local info = theme.Animations.Disappear
		for _, obj in { entry.label, entry.tail } do
			UIStyler.Tween(obj, info, { TextTransparency = 1, TextStrokeTransparency = 1 })
			-- Styled themes carry a TextGlow UIStroke instead of a TextStroke;
			-- fade it with the text (absent under Classic — no-op there).
			local glow = obj:FindFirstChild("TextGlow")
			if glow then
				UIStyler.Tween(glow, info, { Transparency = 1 })
			end
		end
		task.wait(info.Time)
		if self._active[character] == entry then
			self:_Clear(character)
		end
	end)
end

function UIChatBubbleController:_Clear(character: Instance)
	local entry = self._active[character]
	if not entry then
		return
	end
	entry.typeToken = {}
	entry.billboard:Destroy()
	self._active[character] = nil
end

function UIChatBubbleController:_RestyleAll()
	local theme = self._themeController:GetTheme()
	for _, entry in self._active do
		self:_StyleEntry(entry, theme)
	end
end

function UIChatBubbleController:_StyleEntry(entry: any, theme: Types.UITheme)
	-- World grammar (doc §9): white display-font text with the style's text
	-- emphasis (Classic: black TEXT stroke @ 0.2) — applied directly since no
	-- ScreenGui enforcer reaches billboards.
	local display = theme.Fonts.Title
	entry.label.FontFace = display
	entry.label.TextSize = TEXT_SIZE
	entry.label.TextColor3 = theme.Colors.TextPrimary
	UIChrome.TextOutline(entry.label, TEXT_STROKE_TRANSPARENCY)
	entry.tail.FontFace = display
	entry.tail.TextColor3 = theme.Colors.TextPrimary
	UIChrome.TextOutline(entry.tail, TEXT_STROKE_TRANSPARENCY)
	-- A swap BACK to an outline style must also drop the styled-era glow
	-- strokes: UIChrome.TextOutline leaves them in place, and no ScreenGui
	-- enforcer reaches billboards. Absent under Classic-only sessions — no-op.
	if UIChrome.ActiveChrome().TextOutline then
		for _, obj in { entry.label, entry.tail } do
			local glow = obj:FindFirstChild("TextGlow")
			if glow then
				glow:Destroy()
			end
		end
	end
end

return UIChatBubbleController
