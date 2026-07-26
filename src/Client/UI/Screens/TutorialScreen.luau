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

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local TutorialConfig = require(script.Parent.Parent.Config.TutorialConfig)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIHighlightComponent = require(script.Parent.Parent.Components.UIHighlightComponent)

local TutorialScreen = setmetatable({}, { __index = UIScreenBase })
TutorialScreen.__index = TutorialScreen

function TutorialScreen.new()
	-- DisplayOrder 15: the input-aids band, above lobby chrome (doc §7.3).
	local self = UIScreenBase.new("TutorialScreen", 15)
	self._steps = TutorialConfig.Steps
	self._index = 1
	self._onComplete = nil :: ((boolean) -> ())?
	return setmetatable(self, TutorialScreen)
end

function TutorialScreen:_BuildContent()
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

function TutorialScreen:_ShowStep()
	local step = self._steps[self._index]
	if not step then
		self:_Finish(true)
		return
	end
	local theme = self:GetTheme()
	self._title.Text = TextConfig.Resolve(step.titleKey)
	self._title.TextColor3 = theme.Arcade.Gold
	local body = TextConfig.Resolve(step.textKey)
	if step.hintKeys then
		for _, hintKey in step.hintKeys do
			body ..= "\n\n<i>" .. TextConfig.Resolve(hintKey) .. "</i>"
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
