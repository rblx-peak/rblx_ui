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

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local NPCDialogConfig = require(script.Parent.Parent.Config.NPCDialogConfig)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)

local NPCDialogScreen = setmetatable({}, { __index = UIScreenBase })
NPCDialogScreen.__index = NPCDialogScreen

-- GPLayoutKit ships Page/Card/Tabs/StatRow/PricePill but NO button builder, and
-- UIButtonComponent frames itself through UIChrome.Stroke — which under this
-- pack's Chrome (StrokeFollowsAccent = false) returns a BLACK hairline and
-- breaks pack law 1 on sight. So the pack's button is improvised here: a
-- TRANSPARENT hit target (a solid GuiButton would also trip UIStyleEnforcer's
-- black stroke backstop) over a painted petal chip carrying its own deepened
-- stroke and hue-matched shadow, an ink label, and UIChrome.Animate's juice.
local function gpButton(theme: Types.UITheme, parent: Instance, opts: {
	text: string,
	fill: Color3,
	sizePx: Vector2,
	index: number?,
	layoutOrder: number?,
	anchorPoint: Vector2?,
	position: UDim2?,
	onClick: (() -> ())?,
}, sink: { any }?): (TextButton, TextLabel)
	local button = Instance.new("TextButton")
	button.Name = "GPAction"
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(opts.sizePx.X, opts.sizePx.Y)
	if opts.layoutOrder then
		button.LayoutOrder = opts.layoutOrder
	end
	if opts.anchorPoint then
		button.AnchorPoint = opts.anchorPoint
	end
	if opts.position then
		button.Position = opts.position
	end
	button.Parent = parent

	local chip = UIStyler.Frame("Chip")
	chip.BackgroundColor3 = opts.fill
	chip.BackgroundTransparency = 0
	chip.Size = UDim2.fromScale(1, 1)
	chip.Parent = button
	GPLayoutKit.Petal(theme, chip, opts.index or 0)
	GPLayoutKit.SoftStroke(theme, chip, opts.fill)
	GPLayoutKit.Shadow(theme, chip, "sm", sink, opts.fill)

	-- Ink, never TextOnPrimary: the near-white measures 2.14:1 on rose.
	local label = GPLayoutKit.Text(theme, theme.TextSizes.Button + 3, theme.Colors.TextPrimary, "Label")
	label.Text = opts.text -- verbatim: this pack never shouts
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 2
	label.Parent = chip

	if opts.onClick then
		button.Activated:Connect(opts.onClick)
	end
	UIChrome.Animate(theme, button, chip)
	return button, label
end

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
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
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

-- ---- GIRLY POP (theme.LayoutKit == "GP") ------------------------------
-- The same bottom-anchored dialogue box as a STUDIO SLIP: cream paper with
-- petal corners, a scalloped top lip, clay grain and a soft HUE-MATCHED shadow
-- (the plate's own fill deepened — never grey). The portrait keeps its accent
-- rim, because colour IS identity here too; the speaker's name moves onto a
-- rose nameplate instead of gold type (butter on cream is 1.6:1, ink on rose is
-- 5.15:1); the body types out in the pack's warm plum ink rather than the
-- classic pure white, which this pack forbids outright.
--
-- Same field names as classic (_panel/_portrait/_portraitStroke/
-- _portraitInitial/_speaker/_body/_clickCatcher/_continue/_choices/_close), so
-- the typewriter, _RenderLine, _ShowChoices, _Advance and _Finish all drive
-- this layout unchanged.
function NPCDialogScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	self._gpShadows = {}

	local panelFill = theme.Colors.Background
	local panel = UIStyler.Frame("Panel")
	panel.BackgroundColor3 = panelFill
	panel.BackgroundTransparency = 0
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -PANEL_BOTTOM_GAP)
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	panel.Parent = self.Root
	-- Corner FIRST, then anything that clones or hangs off the silhouette.
	GPLayoutKit.Petal(theme, panel, 0)
	GPLayoutKit.SoftStroke(theme, panel, panelFill)
	GPLayoutKit.Shadow(theme, panel, "lg", self._gpShadows, panelFill)
	self._panel = panel

	-- Matte studio dialect: a conversation is a reading surface, so no glaze.
	local studio = ((theme :: any).DialectTokens or {}).studio or {}
	local grain = GPLayoutKit.Tile(
		theme,
		studio.patternKey or "speckle",
		GPLayoutKit.Deepen(theme, panelFill, 1),
		studio.speckleTransparency or 0.94,
		"ClayGrain"
	)
	grain.ZIndex = 1
	grain.Parent = panel
	-- Free-floating page chrome, never inside a scrolling viewport, so the
	-- rotated Top strip is safe here.
	GPLayoutKit.Scallop(theme, panel, "Top", panelFill)

	-- Portrait well: blush plate taking the MIRROR petal so it nests inside the
	-- panel's silhouette instead of fighting it. The 2px accent rim is this
	-- screen's one intentional non-policy stroke (colour IS identity, doc §3.3)
	-- and _RenderLine still recolours exactly this instance per line.
	local wellFill = theme.Colors.Surface
	local portrait = UIStyler.Frame("Portrait")
	portrait.BackgroundColor3 = wellFill
	portrait.BackgroundTransparency = 0
	portrait.Position = UDim2.fromOffset(PAD, PAD + 4)
	portrait.Size = UDim2.fromOffset(PORTRAIT, PORTRAIT)
	portrait.ZIndex = 2
	GPLayoutKit.Petal(theme, portrait, 1)
	self._portraitStroke = UIStyler.Stroke(theme.Semantic.Seat1, 2, 0)
	self._portraitStroke.LineJoinMode = Enum.LineJoinMode.Round
	self._portraitStroke.Parent = portrait
	portrait.Parent = panel
	self._portrait = portrait

	local initial = GPLayoutKit.Text(theme, 44, theme.Colors.TextPrimary, "Initial")
	initial.Size = UDim2.fromScale(1, 1)
	initial.ZIndex = 3
	initial.Parent = portrait
	self._portraitInitial = initial

	-- Speaker nameplate: the LABEL is the chip, so nothing is left stranded if
	-- a caller ever hides it.
	local plateFill = theme.Colors.Primary
	local speaker = GPLayoutKit.Text(theme, 24, theme.Colors.TextPrimary, "Speaker")
	speaker.BackgroundColor3 = plateFill
	speaker.BackgroundTransparency = 0
	speaker.AutomaticSize = Enum.AutomaticSize.X
	speaker.Position = UDim2.fromOffset(TEXT_X, 16)
	speaker.Size = UDim2.fromOffset(0, 34)
	speaker.TextXAlignment = Enum.TextXAlignment.Left
	speaker.TextTruncate = Enum.TextTruncate.AtEnd
	speaker.ZIndex = 2
	speaker.Parent = panel
	UIStyler.PaddingXY(14, 0).Parent = speaker
	GPLayoutKit.CornerSet(theme, speaker, "Leaf")
	GPLayoutKit.SoftStroke(theme, speaker, plateFill)
	-- The plate can grow with the name; cap it clear of the close chip.
	local speakerCap = Instance.new("UISizeConstraint")
	speakerCap.MaxSize = Vector2.new(TEXT_W - 64, math.huge)
	speakerCap.Parent = speaker
	self._speaker = speaker

	local body = GPLayoutKit.Text(theme, 22, theme.Colors.TextPrimary, "Body")
	body.Position = UDim2.fromOffset(TEXT_X, 58)
	body.Size = UDim2.fromOffset(TEXT_W, 116)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.RichText = false
	body.TextWrapped = true
	body.ZIndex = 2
	body.Parent = panel
	self._body = body

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

	-- Continue hint. The ▶ glyph needs a real FontFace assignment, which the
	-- kit's display-text builder makes.
	local cont = GPLayoutKit.Text(theme, 16, theme.Colors.TextSecondary, "Continue")
	cont.AnchorPoint = Vector2.new(1, 1)
	cont.Position = UDim2.new(1, -PAD, 1, -14)
	cont.Size = UDim2.fromOffset(260, 20)
	cont.TextXAlignment = Enum.TextXAlignment.Right
	cont.Text = "click to continue ▶"
	cont.ZIndex = 4
	cont.Parent = panel
	self._continue = cont

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

	local close = gpButton(theme, panel, {
		text = "X",
		fill = theme.Arcade.Red,
		sizePx = Vector2.new(40, 40),
		index = 1,
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -12, 0, 12),
		onClick = function()
			self:_Finish(nil)
		end,
	}, self._gpShadows)
	close.ZIndex = 6
	self._close = close
end

-- A style rebuild destroys the Gui, but the UIShadow BUDGET only falls when a
-- handle is released — hand every GP shadow back here.
function NPCDialogScreen:_OnTeardown()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
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
	if self:LayoutKit() == "GP" then
		-- The pack's paper/ink/rose triad: a blush portrait well, the name on
		-- its rose plate, and body copy in warm plum ink. The classic line
		-- would repaint the body PURE WHITE — invisible on cream, and banned.
		self._portrait.BackgroundColor3 = theme.Colors.Surface
		self._speaker.BackgroundColor3 = theme.Colors.Primary
		self._speaker.TextColor3 = theme.Colors.TextPrimary
		self._body.TextColor3 = theme.Colors.TextPrimary
		self._continue.TextColor3 = theme.Colors.TextSecondary
	else
		self._portrait.BackgroundColor3 = theme.Arcade.NearBlack
		self._speaker.TextColor3 = theme.Arcade.Gold
		self._body.TextColor3 = WHITE
		self._continue.TextColor3 = theme.Arcade.IceBlue
	end
	self:_TypeLine(line)
end

function NPCDialogScreen:_ShowChoices(choices: any)
	for _, b in self._choiceButtons do
		b:Destroy()
	end
	table.clear(self._choiceButtons)
	self._continue.Visible = false
	self._choices.Visible = true
	if self:LayoutKit() == "GP" then
		-- Same choice set, same order, same onClick, same 200×52 footprint —
		-- pastel petal chips instead of arcade plates. The colour GRAMMAR is
		-- preserved: the first choice reads forward (matcha), the rest read
		-- secondary (sky). Raw TextButtons answer the :Destroy() the pooling
		-- loop above and NPCDialogScreen:Destroy both call.
		local theme = self:GetTheme()
		for i, choice in choices do
			local button = gpButton(theme, self._choices, {
				text = TextConfig.Resolve(choice.textKey),
				fill = if i == 1 then theme.Colors.Secondary else theme.Arcade.Blue,
				sizePx = Vector2.new(200, 52),
				index = i,
				layoutOrder = i,
				onClick = function()
					self:_Finish(choice.id)
				end,
			}, self._gpShadows)
			button.ZIndex = 5
			table.insert(self._choiceButtons, button)
		end
		return
	end
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
