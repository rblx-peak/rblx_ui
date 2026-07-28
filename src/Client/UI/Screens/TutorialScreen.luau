--!strict
-- Step-based onboarding. Walks TutorialConfig steps, showing a bottom-centre
-- arcade hint card per step and a spotlight (dimmed overlay with a gold
-- cut-out ring) over the step's highlight target when one is registered with
-- UIScreenController. Advancing is driven by the card's Next button or the
-- AdvanceTutorial input action.
--
-- Chrome (doc §4.1 / §7.4-adjacent): the hint card is a hand-built arcade
-- panel — pure black @ 0.4, 3px black stroke, glass sheen, hard 90° corners,
-- deliberately headerless (it's a floating hint, not a modal). Authored in
-- fixed px at the 1650×1020 baseline; UIScreenBase attaches the UIScale.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local TutorialConfig = require(script.Parent.Parent.Config.TutorialConfig)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIHighlightComponent = require(script.Parent.Parent.Components.UIHighlightComponent)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)

local TutorialScreen = setmetatable({}, { __index = UIScreenBase })
TutorialScreen.__index = TutorialScreen

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

function TutorialScreen.new()
	-- DisplayOrder 15: the input-aids band, above lobby chrome (doc §7.3).
	local self = UIScreenBase.new("TutorialScreen", 15)
	self._steps = TutorialConfig.Steps
	self._index = 1
	self._onComplete = nil :: ((boolean) -> ())?
	return setmetatable(self, TutorialScreen)
end

function TutorialScreen:_BuildContent()
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
	local theme = self:GetTheme()

	-- No Root-level AspectRatioConstraint: the dim overlay below must cover
	-- the TRUE viewport, not a design-locked box — Root has AnchorPoint (0,0),
	-- so constraining it would shrink it flush to the top-left and leave part
	-- of the real screen undimmed.

	-- Full-screen dim, black @ 0.45 (the one modal-dim recipe, doc §7.4).
	local dim = UIStyler.Frame("Dim")
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.Parent = self.Root
	self._dim = dim

	-- Highlight that tracks the current step's target — see
	-- UIHighlightComponent for why this replaced a one-off ring built inline
	-- here (that version snapshotted the target's position once per step and
	-- never updated again, so it visibly drifted off target on any viewport
	-- resize or target reflow).
	local highlight = UIHighlightComponent.new()
	highlight:Create(self.Root, { shape = "RoundedSquare" })
	self._highlight = highlight

	-- Hint card: hand-built arcade panel, bottom-centre, headerless. Pure
	-- black @ 0.4 (the world stays visible through it), 3px black stroke,
	-- glass sheen, hard corners (no UICorner = the arcade's 90° default).
	local card = UIStyler.Frame("HintCard")
	card.BackgroundColor3 = Color3.new(0, 0, 0)
	card.BackgroundTransparency = 0.4
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -60)
	card.Size = UDim2.fromOffset(700, 250)
	UIChrome.Stroke(theme, "Arcade").Parent = card
	UIChrome.GlassGradient().Parent = card
	card.Parent = self.Root
	self._card = card

	-- Step title: gold FredokaOne 26 with the black outline (doc §2). Width
	-- stops short of the close X in the top-right corner.
	local title = UIChrome.Text("Title", 26, theme.Arcade.Gold)
	title.Position = UDim2.fromOffset(18, 12)
	title.Size = UDim2.new(1, -84, 0, 30)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = card
	self._title = title

	-- Step body: white FredokaOne 20 outlined, RichText for the italic hints.
	local body = UIChrome.Text("Text", 20, theme.Colors.TextPrimary)
	body.RichText = true
	body.Position = UDim2.fromOffset(18, 50)
	body.Size = UDim2.new(1, -36, 0, 122)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	-- Long-text safety (doc §2): shrink-to-fit capped at the authored 20px.
	self._textConstraint = UIStyler.TextSizeConstraint(20, 10)
	self._textConstraint.Parent = body
	body.TextWrapped = true
	-- TextScaled must be the LAST wrap-related assignment (engine landmine:
	-- a later TextWrapped write silently reverts it).
	body.TextScaled = true
	body.Parent = card
	self._text = body

	-- Progress "%d / %d": ice-blue FredokaOne 16 (secondary note colour,
	-- doc §3.2), bottom-left, centred against the Next button row.
	local progress = UIChrome.Text("Progress", 16, theme.Arcade.IceBlue)
	progress.AnchorPoint = Vector2.new(0, 1)
	progress.Position = UDim2.new(0, 18, 1, -28)
	progress.Size = UDim2.fromOffset(220, 24)
	progress.TextXAlignment = Enum.TextXAlignment.Left
	progress.Parent = card
	self._progress = progress

	-- Next: arcade Green (advance/confirm in the HUD, doc §3.3), bottom-right.
	self._nextButton = UIButtonComponent.new()
	self._nextButton:Create(card, {
		text = "Next →",
		variant = "Green",
		size = UDim2.fromOffset(170, 52),
		anchorPoint = Vector2.new(1, 1),
		position = UDim2.new(1, -14, 1, -14),
		onClick = function()
			self:Advance()
		end,
	})

	-- 48×48 red close X (UIChrome policy — plain "X": FredokaOne has no ✕
	-- glyph), top-right of the card; closing counts as not-completed.
	local close = UIChrome.CloseButton(theme, card, function()
		self:_Finish(false)
	end)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -8, 0, 8)
	self._close = close
end

-- ---- GIRLY POP (theme.LayoutKit == "GP") ------------------------------
-- The same floating hint card, rebuilt as a STUDIO NOTE: warm plum scrim,
-- a cream paper plate with petal corners, clay grain, a scalloped bottom lip
-- and a soft hue-matched shadow. Deliberately headerless, exactly like the
-- classic card — a hint is not a modal.
--
-- Every field the update path touches is assigned under the same name
-- (_dim/_highlight/_card/_title/_text/_progress/_textConstraint/_nextButton/
-- _close), so _ShowStep, _UpdateHighlight, Advance and _OnShow are unchanged.
-- _nextButton is a SHIM answering the one method _ShowStep calls (:SetContent)
-- — the same trick LoadingScreen's AC ruler uses for its progress contract.
function TutorialScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	local spacing = theme.Spacing
	self._gpShadows = {}

	-- Warm plum scrim: no pure black anywhere in this pack. Full-bleed over the
	-- TRUE viewport, same as classic (no aspect lock on Root).
	local dim = UIStyler.Frame("Dim")
	dim.BackgroundColor3 = theme.Colors.Overlay
	dim.BackgroundTransparency = 0.45
	dim.Parent = self.Root
	self._dim = dim

	local highlight = UIHighlightComponent.new()
	highlight:Create(self.Root, { shape = "RoundedSquare" })
	self._highlight = highlight

	local cardFill = theme.Colors.Background
	local card = UIStyler.Frame("HintCard")
	card.BackgroundColor3 = cardFill
	card.BackgroundTransparency = 0
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -60)
	card.Size = UDim2.fromOffset(700, 250)
	card.Parent = self.Root
	GPLayoutKit.Petal(theme, card, 0)
	GPLayoutKit.SoftStroke(theme, card, cardFill)
	GPLayoutKit.Shadow(theme, card, "lg", self._gpShadows, cardFill)
	self._card = card

	local studio = ((theme :: any).DialectTokens or {}).studio or {}
	local grain = GPLayoutKit.Tile(
		theme,
		studio.patternKey or "speckle",
		GPLayoutKit.Deepen(theme, cardFill, 1),
		studio.speckleTransparency or 0.94,
		"ClayGrain"
	)
	grain.ZIndex = 1
	grain.Parent = card
	-- Unrotated bottom lip: safe anywhere (the rotated Top/Left/Right strips are
	-- the ones that ignore an ancestor's ClipsDescendants).
	GPLayoutKit.Scallop(theme, card, "Bottom", cardFill)

	-- Step title in the display face, INK. The classic gold would be a 1.6:1
	-- headline on cream; _ShowStep repaints this per step (see its GP branch).
	local title = GPLayoutKit.Text(theme, 26, theme.Colors.TextPrimary, "Title")
	title.Position = UDim2.fromOffset(spacing.L, spacing.M)
	title.Size = UDim2.new(1, -(spacing.L + 84), 0, 30)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 3
	title.Parent = card
	self._title = title

	local body = GPLayoutKit.Text(theme, 20, theme.Colors.TextPrimary, "Text")
	body.RichText = true
	body.Position = UDim2.fromOffset(spacing.L, 50)
	body.Size = UDim2.new(1, -spacing.L * 2, 0, 122)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	-- Same long-text safety as classic, same cap: shrink-to-fit to 10px.
	self._textConstraint = UIStyler.TextSizeConstraint(20, 10)
	self._textConstraint.Parent = body
	body.TextWrapped = true
	-- TextScaled must be the LAST wrap-related assignment (engine landmine:
	-- a later TextWrapped write silently reverts it).
	body.TextScaled = true
	body.ZIndex = 3
	body.Parent = card
	self._text = body

	local progress = GPLayoutKit.BodyText(theme, 16, theme.Colors.TextSecondary, "Progress")
	progress.AnchorPoint = Vector2.new(0, 1)
	progress.Position = UDim2.new(0, spacing.L, 1, -28)
	progress.Size = UDim2.fromOffset(220, 24)
	progress.TextXAlignment = Enum.TextXAlignment.Left
	progress.ZIndex = 3
	progress.Parent = card
	self._progress = progress

	-- Advance stays MATCHA (the pack's forward/confirm mass), 170×52 as authored.
	local _next, nextLabel = gpButton(theme, card, {
		text = "Next →",
		fill = theme.Colors.Secondary,
		sizePx = Vector2.new(170, 52),
		index = 1,
		anchorPoint = Vector2.new(1, 1),
		position = UDim2.new(1, -14, 1, -14),
		onClick = function()
			self:Advance()
		end,
	}, self._gpShadows)
	_next.ZIndex = 4
	self._nextButton = {
		Root = _next,
		SetContent = function(_self: any, content: any)
			if content and content.text then
				nextLabel.Text = content.text
			end
		end,
		Destroy = function(_self: any)
			_next:Destroy()
		end,
	} :: any

	-- Close chip: soft coral, leaf-cornered — closing still counts as
	-- not-completed. A display-face "X" (no ✕ glyph in this family).
	local close, _closeLabel = gpButton(theme, card, {
		text = "X",
		fill = theme.Arcade.Red,
		sizePx = Vector2.new(44, 44),
		index = 1,
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -12, 0, 12),
		onClick = function()
			self:_Finish(false)
		end,
	}, self._gpShadows)
	close.ZIndex = 4
	self._close = close
end

function TutorialScreen:_ShowStep()
	local step = self._steps[self._index]
	if not step then
		self:_Finish(true)
		return
	end
	local theme = self:GetTheme()
	self._title.Text = TextConfig.Resolve(step.titleKey)
	-- GP repaints the step title in INK: butter gold on the pack's cream paper
	-- is a 1.6:1 headline, and the colour mass is carried by the card chrome.
	self._title.TextColor3 = if self:LayoutKit() == "GP" then theme.Colors.TextPrimary else theme.Arcade.Gold
	local body = TextConfig.Resolve(step.textKey)
	if step.hintKeys then
		-- Pack law 5 forbids ITALICS outright, so under GP a hint separates
		-- itself as its own quiet paragraph instead of slanting. Same hints,
		-- same order, same text — only the emphasis mark differs, and every
		-- other kit still gets the <i> wrapper byte-identical.
		local gp = self:LayoutKit() == "GP"
		for _, hintKey in step.hintKeys do
			local hint = TextConfig.Resolve(hintKey)
			body ..= if gp then "\n\n" .. hint else "\n\n<i>" .. hint .. "</i>"
		end
	end
	self._text.Text = body
	self._text.TextColor3 = theme.Colors.TextPrimary
	self._progress.Text = string.format("%d / %d", self._index, #self._steps)
	self._progress.TextColor3 = theme.Arcade.IceBlue

	local isLast = self._index >= #self._steps
	self._nextButton:SetContent({ text = isLast and TextConfig.Resolve("modal.ok") or "Next →" })

	self:_UpdateHighlight(step)
end

-- Restyle the highlight for this step (shape/arrow, per-step overrides — see
-- TutorialConfig) and point it at the step's registered target, if any
-- (e.g. "hud.topRight", "nav.shop", "nav.theme").
-- UIHighlightComponent:Track keeps itself correctly positioned from here on,
-- including across viewport resizes — no per-step position math needed.
function TutorialScreen:_UpdateHighlight(step: any)
	self._highlight:SetContent({
		shape = step.highlightShape or "RoundedSquare",
		showArrow = step.highlightArrowDirection ~= nil,
		arrowDirection = step.highlightArrowDirection,
	})
	local target = step.highlightTargetId and self.ScreenController:GetHighlightTarget(step.highlightTargetId)
	self._highlight:Track(target)
end

function TutorialScreen:Advance()
	self._index += 1
	if self._index > #self._steps then
		self:_Finish(true)
	else
		self:_ShowStep()
	end
end

function TutorialScreen:_Finish(completed: boolean)
	self.ScreenController:HideScreen("tutorial")
	if self._onComplete then
		self._onComplete(completed)
	end
end

-- A style rebuild destroys the Gui, but the UIShadow BUDGET only falls when a
-- handle is released — hand every GP shadow back here.
function TutorialScreen:_OnTeardown()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
end

function TutorialScreen:_OnShow(data: any?)
	if data and data.steps then
		self._steps = data.steps
	end
	if data and data.onComplete then
		self._onComplete = data.onComplete
	end
	self._index = 1
	self:_ShowStep()
	-- Open is an instant Visible flip (UIScreenBase); the pop-in juice lives
	-- on the contents — the hint card — never the container (doc §5 / §7.4).
	UIChrome.PopIn(self:GetTheme(), self._card)
end

return TutorialScreen
