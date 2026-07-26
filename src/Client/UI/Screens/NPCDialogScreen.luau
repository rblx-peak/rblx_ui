--!strict
-- NPC dialogue box with a typewriter reveal, restyled to the Pottery Clash
-- arcade language (UI_DESIGN_DOCUMENT.md): a bottom-anchored pure-black @0.4
-- panel with a 3px black stroke and the glass sheen (NO red header — this is
-- a dialog, not a menu), a near-black portrait well rimmed in the speaker's
-- accent colour, gold speaker name, white FredokaOne body that types out at
-- the line's speed, and arcade choice buttons on the final line.
--
-- Click while typing reveals the whole line instantly; click a finished line
-- to advance. Drive it with Show({ sequenceId = "welcome_merchant" }) or a raw
-- sequence table; choices fire onChoice(id).

local RunService = game:GetService("RunService")

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local NPCDialogConfig = require(script.Parent.Parent.Config.NPCDialogConfig)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)

local NPCDialogScreen = setmetatable({}, { __index = UIScreenBase })
NPCDialogScreen.__index = NPCDialogScreen

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

-- Fixed px at the 1650×1020 baseline (doc §7.1) — UIScreenBase attaches the
-- shared UIScale, so these offsets shrink/grow with the viewport.
local PANEL_W = 860
local PANEL_H = 250
local PANEL_BOTTOM_GAP = 40
local PORTRAIT = 120
local PAD = 20
local TEXT_X = PAD + PORTRAIT + 20 -- content column right of the portrait
local TEXT_W = PANEL_W - TEXT_X - PAD

function NPCDialogScreen.new()
	local self = UIScreenBase.new("NPCDialogScreen", 16)
	self._lines = {}
	self._index = 1
	self._typing = false
	self._choiceButtons = {}
	self._onChoice = nil :: ((string) -> ())?
	self._defaultSpeed = 45
	return setmetatable(self, NPCDialogScreen)
end

function NPCDialogScreen:_BuildContent()
	local theme = self:GetTheme()

	-- The dialog panel: bottom-centre, pure black @ 0.4 (the world stays
	-- visible through it), 3px black stroke + glass sheen via UIChrome.
	local panel = UIStyler.Frame("Panel")
	panel.BackgroundColor3 = BLACK
	panel.BackgroundTransparency = 0.4
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -PANEL_BOTTOM_GAP)
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	UIChrome.Stroke(theme, "Arcade").Parent = panel
	UIChrome.GlassGradient().Parent = panel
	panel.Parent = self.Root
	self._panel = panel

	-- Portrait well: 120px square near-black box (hard arcade corners) with a
	-- 2px accent rim in the speaker's colour. The accent stroke is this
	-- screen's one intentional non-policy stroke (colour IS identity, doc
	-- §3.3) — recoloured per line in _RenderLine.
	local portrait = UIStyler.Frame("Portrait")
	portrait.BackgroundColor3 = theme.Arcade.NearBlack
	portrait.Position = UDim2.fromOffset(PAD, PAD)
	portrait.Size = UDim2.fromOffset(PORTRAIT, PORTRAIT)
	self._portraitStroke = UIStyler.Stroke(theme.Semantic.Seat1, 2, 0)
	self._portraitStroke.Parent = portrait
	portrait.Parent = panel
	self._portrait = portrait

	-- Speaker initial in the well (placeholder until real portraits).
	-- UIChrome.Text = FredokaOne + the non-negotiable black outline.
	local initial = UIChrome.Text("Initial", 44, WHITE)
	initial.Size = UDim2.fromScale(1, 1)
	initial.Parent = portrait
	self._portraitInitial = initial

	-- Speaker name: gold display text.
	local speaker = UIChrome.Text("Speaker", 24, theme.Arcade.Gold)
	speaker.Position = UDim2.fromOffset(TEXT_X, 18)
	speaker.Size = UDim2.fromOffset(TEXT_W - 56, 30) -- clear of the close X
	speaker.TextXAlignment = Enum.TextXAlignment.Left
	speaker.TextTruncate = Enum.TextTruncate.AtEnd
	speaker.Parent = panel
	self._speaker = speaker

	-- Body text (typewriter target): white FredokaOne 22, wrapped.
	local body = UIChrome.Text("Body", 22, WHITE)
	body.Position = UDim2.fromOffset(TEXT_X, 56)
	body.Size = UDim2.fromOffset(TEXT_W, 118)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.RichText = false
	body.TextWrapped = true
	body.Parent = panel
	self._body = body

	-- Full-panel click catcher: reveal while typing, advance when done.
	local clickCatcher = Instance.new("TextButton")
	clickCatcher.Name = "Advance"
	clickCatcher.Text = ""
	clickCatcher.BackgroundTransparency = 1
	clickCatcher.AutoButtonColor = false
	clickCatcher.Size = UDim2.fromScale(1, 1)
	clickCatcher.ZIndex = 3
	clickCatcher.Parent = panel
	clickCatcher.Activated:Connect(function()
		self:_OnClick()
	end)
	self._clickCatcher = clickCatcher

	-- Continue hint (bottom-right): ice-blue FredokaOne 16. UIChrome.Text
	-- assigns FontFace — mandatory for the ▶ glyph (the engine-default
	-- LegacyArial has no symbol coverage at all).
	local cont = UIChrome.Text("Continue", 16, theme.Arcade.IceBlue)
	cont.AnchorPoint = Vector2.new(1, 1)
	cont.Position = UDim2.new(1, -PAD, 1, -12)
	cont.Size = UDim2.fromOffset(260, 20)
	cont.TextXAlignment = Enum.TextXAlignment.Right
	cont.Text = "click to continue ▶"
	cont.ZIndex = 4
	cont.Parent = panel
	self._continue = cont

	-- Choice row (hidden until the final line offers choices). Sits above the
	-- click catcher so choosing never falls through to advance.
	local choices = UIStyler.Frame("Choices")
	choices.BackgroundTransparency = 1
	choices.AnchorPoint = Vector2.new(0, 1)
	choices.Position = UDim2.new(0, TEXT_X, 1, -16)
	choices.Size = UDim2.fromOffset(TEXT_W, 52)
	choices.Visible = false
	choices.ZIndex = 5
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12),
	}).Parent = choices
	choices.Parent = panel
	self._choices = choices

	-- Red arcade close X, top-right of the panel → same as choosing nothing.
	local close = UIChrome.CloseButton(theme, panel, function()
		self:_Finish(nil)
	end)
	close.Size = UDim2.fromOffset(40, 40)
	close.TextSize = 24
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 10)
	close.ZIndex = 6
	self._close = close
end

-- ---- typewriter -------------------------------------------------------

function NPCDialogScreen:_TypeLine(line: any)
	local fullText = TextConfig.Resolve(line.textKey)
	self._fullText = fullText
	self._typing = true
	self._body.Text = ""
	self._continue.Visible = false
	self._choices.Visible = false

	local speed = line.typeSpeed or self._defaultSpeed
	task.spawn(function()
		local shown = 0
		local acc = 0
		local token = {}
		self._typeToken = token
		while shown < #fullText and self._typing and self._typeToken == token do
			local dt = RunService.Heartbeat:Wait()
			acc += dt * speed
			local target = math.min(#fullText, math.floor(acc))
			if target > shown then
				shown = target
				-- utf8.offset keeps multi-byte glyphs (emoji) intact while typing.
				local byteEnd = (utf8.offset(fullText, shown + 1) or (#fullText + 1)) - 1
				self._body.Text = string.sub(fullText, 1, byteEnd)
			end
		end
		if self._typeToken == token then
			self:_FinishTyping()
		end
	end)
end

function NPCDialogScreen:_FinishTyping()
	self._typing = false
	self._body.Text = self._fullText
	local line = self._lines[self._index]
	if line and line.choices then
		self:_ShowChoices(line.choices)
	else
		self._continue.Visible = true
	end
end

function NPCDialogScreen:_OnClick()
	if self._typing then
		-- Skip to the full line.
		self._typeToken = {}
		self:_FinishTyping()
	elseif not self._choices.Visible then
		self:_Advance()
	end
end

function NPCDialogScreen:_Advance()
	self._index += 1
	local line = self._lines[self._index]
	if line then
		self:_RenderLine(line)
	else
		self:_Finish(nil)
	end
end

-- ---- rendering --------------------------------------------------------

function NPCDialogScreen:_RenderLine(line: any)
	local theme = self:GetTheme()
	local speakerName = TextConfig.Resolve(line.speakerKey)
	self._speaker.Text = speakerName
	self._portraitInitial.Text = string.upper(string.sub(speakerName, 1, 1))
	-- Colour = identity (doc §3.3): the portrait rim takes the line's accent.
	self._portraitStroke.Color = line.portraitColor or theme.Semantic.Seat1
	-- Re-assert the themed colours each render so a live theme swap mid-
	-- conversation repaints the next line correctly.
	self._portrait.BackgroundColor3 = theme.Arcade.NearBlack
	self._speaker.TextColor3 = theme.Arcade.Gold
	self._body.TextColor3 = WHITE
	self._continue.TextColor3 = theme.Arcade.IceBlue
	self:_TypeLine(line)
end

function NPCDialogScreen:_ShowChoices(choices: any)
	for _, b in self._choiceButtons do
		b:Destroy()
	end
	table.clear(self._choiceButtons)
	self._continue.Visible = false
	self._choices.Visible = true
	for i, choice in choices do
		local button = UIButtonComponent.new()
		button:Create(self._choices, {
			textKey = choice.textKey,
			-- Doc §3.3: green = confirm/primary, blue = secondary actions.
			variant = i == 1 and "Green" or "Blue",
			size = UDim2.fromOffset(200, 52),
			layoutOrder = i,
			onClick = function()
				self:_Finish(choice.id)
			end,
		})
		table.insert(self._choiceButtons, button)
	end
end

function NPCDialogScreen:_Finish(choiceId: string?)
	self._typing = false
	self._typeToken = {}
	self.ScreenController:HideScreen("npcDialog")
	if self._onChoice then
		self._onChoice(choiceId or "closed")
	end
end

function NPCDialogScreen:_OnShow(data: any?)
	local sequence
	if data and data.lines then
		sequence = data
	elseif data and data.sequenceId then
		sequence = NPCDialogConfig.Get(data.sequenceId)
	else
		sequence = NPCDialogConfig.Get("welcome_merchant")
	end
	self._lines = sequence.lines
	self._defaultSpeed = sequence.defaultTypeSpeed or 45
	self._onChoice = data and data.onChoice or nil
	self._index = 1
	-- Show/hide is an instant flip (doc §7.4); the juice lives on the content:
	-- the panel pops 0.82 → 1 while the first line starts typing.
	UIChrome.PopIn(self:GetTheme(), self._panel)
	self:_RenderLine(self._lines[1])
end

function NPCDialogScreen:_OnHide()
	self._typing = false
	self._typeToken = {}
end

function NPCDialogScreen:Destroy()
	for _, b in self._choiceButtons do
		b:Destroy()
	end
	table.clear(self._choiceButtons)
	UIScreenBase.Destroy(self)
end

return NPCDialogScreen
