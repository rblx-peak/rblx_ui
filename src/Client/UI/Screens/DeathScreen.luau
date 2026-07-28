--!strict
-- Death + respawn overlay (Overlay band, hides the HUD — a focused moment,
-- doc §11.5). Boxless over the world: a black scrim at 0.55 plus a red
-- vignette built from four gradient edge strips, so the 3D scene stays
-- readable underneath and the red reads as damage rather than as chrome.
--
-- Anatomy: "YOU DIED" FredokaOne 76 in Arcade.Red with the full black outline,
-- an optional "KILLED BY <name>" row carrying the skull glyph, then the 1Hz
-- gold countdown (doc §11.3) in a FIXED 260×96 box so the per-second pulse can
-- never reflow the stack, and finally the RESPAWN button.
--
-- The button is DIMMED, never disabled, while the countdown runs: a disabled
-- UIButtonComponent withholds its onClick, and a tap that reaches nothing
-- cannot answer. Dimmed keeps the click alive, so an early tap plays the full
-- press juice and then explains itself (§11.1).
--
-- Show{ killedBy, respawnIn, onRespawn }.

local RunService = game:GetService("RunService")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local ACLayoutKit = require(script.Parent.Parent.Framework.ACLayoutKit)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPMatchFlow = require(script.Parent.Parent.Framework.GPMatchFlow)

local DeathScreen = setmetatable({}, { __index = UIScreenBase })
DeathScreen.__index = DeathScreen

-- The countdown/ready path is SHARED by all three layouts, so what differs
-- between them is the captions, not the logic. Classic keeps its exact
-- strings; AC never reassigns the table, so it keeps them too; only the GP
-- build swaps in the pack's warm voice (GP law 5: this pack never shouts).
local CLASSIC_COPY = {
	respawningIn = "RESPAWNING IN",
	ready = "READY",
	go = "GO",
	killedBy = function(name: string): string
		return "KILLED BY  " .. string.upper(name)
	end,
}

local GP_COPY = {
	respawningIn = "Back to the wheel in",
	ready = "Ready",
	go = "Go",
	killedBy = function(name: string): string
		return "Cracked by " .. name
	end,
}

-- Fixed px at the 1650×1020 baseline.
local STAGE_W = 900
local STAGE_H = 430
local VIGNETTE_V = 240 -- top/bottom strip depth
local VIGNETTE_H = 320 -- left/right strip depth
local VIGNETTE_EDGE = 0.55 -- fill transparency at the screen edge
local COUNTDOWN_BOX = Vector2.new(260, 96)
local RESPAWN_SIZE = Vector2.new(320, 68)
local DEFAULT_RESPAWN_SECONDS = 5

-- AC layout (theme.LayoutKit == "AC") fixed px: the centred mono stage and
-- the fixed countdown footprint (same no-reflow reason as COUNTDOWN_BOX).
local AC_STAGE_W = 520
local AC_STAGE_H = 200
local AC_COUNTDOWN_BOX = Vector2.new(200, 30)

-- GP layout (theme.LayoutKit == "GP") fixed px: the cream misfire plate and
-- the fixed countdown footprint (same no-reflow reason as COUNTDOWN_BOX).
local GP_STAGE_W = 760
local GP_STAGE_H = 430
local GP_BAND_H = 88
local GP_COUNTDOWN_BOX = Vector2.new(260, 92)
local GP_RESPAWN_SIZE = Vector2.new(320, 68)
-- The vignette still reads as damage under GP, but softer: Arcade.Red is a
-- muted coral in this pack, and it fades from a gentler edge value.
local GP_VIGNETTE_EDGE = 0.74

-- One vignette edge: a red strip whose UIGradient fades its fill from
-- VIGNETTE_EDGE at the screen edge to fully transparent inward. Rotation picks
-- which end of the strip is the "edge" (90 = top, -90 = bottom, 0 = left,
-- 180 = right). `edge` overrides the fill transparency at the screen edge
-- (GP asks for a gentler one); omitted, every existing caller is unchanged.
local function vignetteStrip(parent: Instance, theme: Types.UITheme, name: string, size: UDim2, anchor: Vector2, position: UDim2, rotation: number, edge: number?)
	local strip = UIStyler.Frame(name)
	strip.BackgroundColor3 = theme.Arcade.Red
	strip.BackgroundTransparency = 0
	strip.AnchorPoint = anchor
	strip.Position = position
	strip.Size = size
	strip.ZIndex = 2
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, edge or VIGNETTE_EDGE),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = strip
	strip.Parent = parent
	return strip
end

function DeathScreen.new()
	local self = UIScreenBase.new("DeathScreen", 19)
	self._remaining = 0
	self._ready = false
	self._killedBy = nil :: string?
	self._onRespawn = nil :: (() -> ())?
	self._tickConn = nil :: RBXScriptConnection?
	-- Layout-neutral captions, overridden only by the GP build.
	self._copy = CLASSIC_COPY
	self._gpShadows = nil :: { any }?
	return setmetatable(self, DeathScreen)
end

function DeathScreen:_BuildContent()
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
	if self:LayoutKit() == "AC" then
		self:_BuildACLayout()
		return
	end

	local theme = self:GetTheme()

	-- Scrim: black at 0.55 (doc §11.8 — results-style scrim, not a blackout).
	local scrim = UIStyler.Frame("Scrim")
	scrim.BackgroundColor3 = theme.Colors.Overlay
	scrim.BackgroundTransparency = 0.55
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.ZIndex = 1
	scrim.Parent = self.Root

	vignetteStrip(self.Root, theme, "VignetteTop", UDim2.new(1, 0, 0, VIGNETTE_V), Vector2.new(0, 0), UDim2.fromScale(0, 0), 90)
	vignetteStrip(self.Root, theme, "VignetteBottom", UDim2.new(1, 0, 0, VIGNETTE_V), Vector2.new(0, 1), UDim2.fromScale(0, 1), -90)
	vignetteStrip(self.Root, theme, "VignetteLeft", UDim2.new(0, VIGNETTE_H, 1, 0), Vector2.new(0, 0), UDim2.fromScale(0, 0), 0)
	vignetteStrip(self.Root, theme, "VignetteRight", UDim2.new(0, VIGNETTE_H, 1, 0), Vector2.new(1, 0), UDim2.fromScale(1, 0), 180)

	local stage = UIStyler.Frame("Stage")
	stage.BackgroundTransparency = 1
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.46)
	stage.Size = UDim2.fromOffset(STAGE_W, STAGE_H)
	stage.ZIndex = 3
	stage.Parent = self.Root
	self._stage = stage

	local headline = UIChrome.Text("Headline", 76, theme.Arcade.Red)
	headline.RichText = false
	headline.Text = "YOU DIED"
	headline.Size = UDim2.fromOffset(STAGE_W, 92)
	headline.ZIndex = 4
	headline.Parent = stage

	-- "KILLED BY <name>" — a centred icon+text row, hidden when no killer was
	-- supplied (environment deaths, falls).
	local killedRow = UIStyler.Frame("KilledBy")
	killedRow.BackgroundTransparency = 1
	killedRow.Position = UDim2.fromOffset(0, 98)
	killedRow.Size = UDim2.fromOffset(STAGE_W, 34)
	killedRow.ZIndex = 4
	killedRow.Visible = false
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = killedRow
	killedRow.Parent = stage
	self._killedRow = killedRow

	local skull = IconArchive.Image(killedRow, "skull", 30)
	skull.LayoutOrder = 1
	skull.ZIndex = 4

	local killedLabel = UIChrome.Text("KilledLabel", 24, theme.Arcade.IceBlue)
	killedLabel.RichText = false
	killedLabel.AutomaticSize = Enum.AutomaticSize.X
	killedLabel.Size = UDim2.fromOffset(0, 34)
	killedLabel.LayoutOrder = 2
	killedLabel.ZIndex = 4
	killedLabel.Parent = killedRow
	self._killedLabel = killedLabel

	-- Hairline rule under the headline block, in the damage colour.
	local rule = UIStyler.Frame("Rule")
	rule.BackgroundColor3 = theme.Arcade.Red
	rule.BackgroundTransparency = 0.35
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.Position = UDim2.new(0.5, 0, 0, 144)
	rule.Size = UDim2.fromOffset(420, 3)
	rule.ZIndex = 4
	rule.Parent = stage

	local caption = UIChrome.BodyText("Caption", 18, theme.Studio.TextMuted)
	caption.Text = "RESPAWNING IN"
	caption.Position = UDim2.fromOffset(0, 164)
	caption.Size = UDim2.fromOffset(STAGE_W, 24)
	caption.ZIndex = 4
	caption.Parent = stage
	self._caption = caption

	-- Fixed box: the 1Hz pulse scales this label, and a fixed footprint is what
	-- keeps the pulse from nudging the RESPAWN button around (doc §5.3).
	local countdown = UIChrome.Text("Countdown", 76, theme.Arcade.Gold)
	countdown.RichText = false
	countdown.AnchorPoint = Vector2.new(0.5, 0)
	countdown.Position = UDim2.new(0.5, 0, 0, 192)
	countdown.Size = UDim2.fromOffset(COUNTDOWN_BOX.X, COUNTDOWN_BOX.Y)
	countdown.ZIndex = 4
	countdown.Parent = stage
	self._countdown = countdown

	self._respawnButton = UIButtonComponent.new()
	self._respawnButton:Create(stage, {
		text = "RESPAWN",
		variant = "Green",
		iconId = IconArchive.Id("rebirth"),
		dimmed = true,
		size = UDim2.fromOffset(RESPAWN_SIZE.X, RESPAWN_SIZE.Y),
		position = UDim2.new(0.5, 0, 0, 306),
		anchorPoint = Vector2.new(0.5, 0),
		onClick = function()
			self:_TryRespawn()
		end,
	})
	self._respawnButton.Root.ZIndex = 4
end

-- The AC layout (theme.LayoutKit == "AC"): same scrim strength, but the red
-- vignette gives way to a centred mono readout — the destruction line in
-- Colors.Error between two hairline rules, the countdown beneath in accent
-- mono, and a hairline RESPAWN action. Assigns the same public fields, so
-- the classic countdown/ready path drives both layouts unchanged.
function DeathScreen:_BuildACLayout()
	local theme = self:GetTheme()

	-- Scrim: identical strength to classic (doc §11.8) — the world stays visible.
	local scrim = UIStyler.Frame("Scrim")
	scrim.BackgroundColor3 = theme.Colors.Overlay
	scrim.BackgroundTransparency = 0.55
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.ZIndex = 1
	scrim.Parent = self.Root

	local stage = UIStyler.Frame("Stage")
	stage.BackgroundTransparency = 1
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.46)
	stage.Size = UDim2.fromOffset(AC_STAGE_W, AC_STAGE_H)
	stage.ZIndex = 3
	stage.Parent = self.Root
	self._stage = stage

	local ruleTop = ACLayoutKit.Rule(theme, stage, 0.5)
	ruleTop.Position = UDim2.fromOffset(0, 0)
	ruleTop.ZIndex = 4

	local headline = UIChrome.Text("Headline", 26, theme.Colors.Error)
	headline.RichText = false
	headline.Text = "YOU DIED"
	headline.Position = UDim2.fromOffset(0, 10)
	headline.Size = UDim2.fromOffset(AC_STAGE_W, 32)
	headline.ZIndex = 4
	headline.Parent = stage

	-- "KILLED BY <name>" as a dense mono line — same fields the classic row
	-- exposes (_OnShow toggles Visible and writes the label).
	local killedRow = UIStyler.Frame("KilledBy")
	killedRow.BackgroundTransparency = 1
	killedRow.Position = UDim2.fromOffset(0, 46)
	killedRow.Size = UDim2.fromOffset(AC_STAGE_W, 18)
	killedRow.ZIndex = 4
	killedRow.Visible = false
	killedRow.Parent = stage
	self._killedRow = killedRow

	local killedLabel = UIChrome.BodyText("KilledLabel", 12, theme.Colors.TextSecondary)
	killedLabel.RichText = false
	killedLabel.Size = UDim2.fromScale(1, 1)
	killedLabel.ZIndex = 4
	killedLabel.Parent = killedRow
	self._killedLabel = killedLabel

	local ruleBottom = ACLayoutKit.Rule(theme, stage, 0.5)
	ruleBottom.Position = UDim2.fromOffset(0, 72)
	ruleBottom.ZIndex = 4

	local caption = UIChrome.BodyText("Caption", 11, theme.Colors.TextSecondary)
	caption.Text = "RESPAWNING IN"
	caption.Position = UDim2.fromOffset(0, 88)
	caption.Size = UDim2.fromOffset(AC_STAGE_W, 14)
	caption.ZIndex = 4
	caption.Parent = stage
	self._caption = caption

	-- Fixed box, same reason as classic: the 1Hz pulse must never reflow.
	local countdown = UIChrome.Text("Countdown", 18, theme.Colors.Accent)
	countdown.RichText = false
	countdown.AnchorPoint = Vector2.new(0.5, 0)
	countdown.Position = UDim2.new(0.5, 0, 0, 106)
	countdown.Size = UDim2.fromOffset(AC_COUNTDOWN_BOX.X, AC_COUNTDOWN_BOX.Y)
	countdown.ZIndex = 4
	countdown.Parent = stage
	self._countdown = countdown

	local action = ACLayoutKit.ActionButton(theme, stage, "RESPAWN", function()
		self:_TryRespawn()
	end)
	action.AnchorPoint = Vector2.new(0.5, 0)
	action.Position = UDim2.new(0.5, 0, 0, 148)
	action.ZIndex = 4
	action.TextTransparency = 0.55 -- dimmed (never disabled) until READY

	-- The classic tick path drives the button via SetContent{ text, dimmed }
	-- and pulses .Root; this adapter gives the hairline action the same
	-- surface so _SetReady/_TryRespawn run unchanged in both layouts.
	self._respawnButton = {
		Root = action,
		SetContent = function(_, props: any)
			if props.text then
				action.Text = string.upper(props.text)
			end
			action.TextTransparency = if props.dimmed then 0.55 else 0
		end,
		Destroy = function()
			action:Destroy()
		end,
	} :: any

	local hint = UIChrome.BodyText("Hint", 10, theme.Colors.TextSecondary)
	hint.Text = "[CLICK] RESPAWN"
	hint.Position = UDim2.fromOffset(0, 186)
	hint.Size = UDim2.fromOffset(AC_STAGE_W, 12)
	hint.ZIndex = 4
	hint.Parent = stage
end

-- ========================================================================
-- GP layout (theme.LayoutKit == "GP") — the MISFIRE plate.
--
-- Same beats as classic, in the pack's language: a warm plum scrim (never
-- black) at the classic 0.55, the damage vignette kept but in the pack's muted
-- coral and fading from a gentler edge, then a cream petal plate carrying a
-- coral headline band (glaze sheen + scalloped skirt), the "cracked by" line,
-- a squiggle rule, the caption, the countdown in a butter pill on a FIXED
-- footprint, and the respawn chip.
--
-- Presentation only: it assigns exactly the fields the shared countdown/ready
-- path reads (_stage, _killedRow, _killedLabel, _caption, _countdown,
-- _respawnButton) plus the pack's copy table, so _StartCountdown, _SetReady
-- and _TryRespawn run byte-identically under all three layouts.
-- ========================================================================

function DeathScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	local spacing = theme.Spacing
	local shadows: { any } = {}
	self._gpShadows = shadows
	self._copy = GP_COPY

	-- Warm plum scrim at the classic strength (doc §11.8): the world stays
	-- readable, and the pack's Overlay token is a plum-brown, not black.
	local scrim = GPMatchFlow.Fill("Scrim", theme.Colors.Overlay, 0.55)
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.ZIndex = 1
	scrim.Parent = self.Root

	vignetteStrip(self.Root, theme, "VignetteTop", UDim2.new(1, 0, 0, VIGNETTE_V), Vector2.new(0, 0), UDim2.fromScale(0, 0), 90, GP_VIGNETTE_EDGE)
	vignetteStrip(self.Root, theme, "VignetteBottom", UDim2.new(1, 0, 0, VIGNETTE_V), Vector2.new(0, 1), UDim2.fromScale(0, 1), -90, GP_VIGNETTE_EDGE)
	vignetteStrip(self.Root, theme, "VignetteLeft", UDim2.new(0, VIGNETTE_H, 1, 0), Vector2.new(0, 0), UDim2.fromScale(0, 0), 0, GP_VIGNETTE_EDGE)
	vignetteStrip(self.Root, theme, "VignetteRight", UDim2.new(0, VIGNETTE_H, 1, 0), Vector2.new(1, 0), UDim2.fromScale(1, 0), 180, GP_VIGNETTE_EDGE)

	local stage = UIStyler.Frame("Stage")
	stage.BackgroundTransparency = 1
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.46)
	stage.Size = UDim2.fromOffset(GP_STAGE_W, GP_STAGE_H)
	stage.ZIndex = 3
	stage.Parent = self.Root
	self._stage = stage

	local plateFill = theme.Colors.Background
	local plate = GPMatchFlow.Fill("Plate", plateFill)
	plate.Size = UDim2.fromScale(1, 1)
	plate.ZIndex = 3
	plate.Parent = stage
	UIStyler.Corner(theme.Radii.Large).Parent = plate
	GPLayoutKit.SoftStroke(theme, plate, plateFill)
	GPLayoutKit.Shadow(theme, plate, "lg", shadows, plateFill)

	-- Clay speckle: the studio dialect's matte grain, the same texture the kit
	-- lays under every page.
	local studioTokens = ((theme :: any).DialectTokens or {}).studio or {}
	local grain = GPLayoutKit.Tile(
		theme,
		studioTokens.patternKey or "speckle",
		GPLayoutKit.Deepen(theme, plateFill, 1),
		studioTokens.speckleTransparency or 0.94,
		"ClayGrain"
	)
	grain.ZIndex = 4
	grain.Parent = plate

	-- The headline band: coral, because this is the damage moment — but a
	-- muted coral with a glaze sheen and a doily skirt, not a warning bar.
	local bandFill = theme.Colors.Error
	local band = GPMatchFlow.Fill("Band", bandFill)
	band.Position = UDim2.fromOffset(spacing.M, spacing.M)
	band.Size = UDim2.new(1, -spacing.M * 2, 0, GP_BAND_H)
	band.ZIndex = 5
	band.Parent = plate
	GPLayoutKit.CornerSet(theme, band, "Tab")
	GPLayoutKit.SoftStroke(theme, band, bandFill)
	GPLayoutKit.Shadow(theme, band, "md", shadows, bandFill)
	GPLayoutKit.GlazeSheen(theme, band)
	GPLayoutKit.Scallop(theme, band, "Bottom", bandFill)

	-- MISFIRE is the pack's word for a pot lost in the kiln. Ink, not the
	-- near-white: 2.14:1 on an undeepened pastel is illegal here.
	local headline = GPLayoutKit.Text(theme, 58, theme.Colors.TextPrimary, "Headline")
	headline.RichText = false
	headline.Text = "Misfire"
	headline.Size = UDim2.fromScale(1, 1)
	headline.ZIndex = 7
	headline.Parent = band

	-- "Cracked by <name>" — hidden when nothing broke you (falls, kiln heat).
	local killedRow = UIStyler.Frame("KilledBy")
	killedRow.BackgroundTransparency = 1
	killedRow.Position = UDim2.fromOffset(0, spacing.M + GP_BAND_H + 24)
	killedRow.Size = UDim2.new(1, 0, 0, 34)
	killedRow.ZIndex = 6
	killedRow.Visible = false
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = killedRow
	killedRow.Parent = plate
	self._killedRow = killedRow

	-- Untinted: the archive's art is full-colour flat cartoon and an ImageColor3
	-- multiply would only muddy it. Icon() still inks the GLYPH fallback.
	local skull = GPMatchFlow.Icon(theme, killedRow, "skull", 28)
	skull.LayoutOrder = 1
	skull.ZIndex = 6

	local killedLabel = GPLayoutKit.BodyText(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "KilledLabel")
	killedLabel.RichText = false
	killedLabel.AutomaticSize = Enum.AutomaticSize.X
	killedLabel.Size = UDim2.fromOffset(0, 34)
	killedLabel.LayoutOrder = 2
	killedLabel.ZIndex = 6
	killedLabel.Parent = killedRow
	self._killedLabel = killedLabel

	local rule = GPLayoutKit.Divider(theme, plate)
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.Position = UDim2.new(0.5, 0, 0, 172)
	rule.Size = UDim2.new(0, 420, 0, rule.Size.Y.Offset)
	rule.ZIndex = 6

	local caption = GPLayoutKit.BodyText(theme, theme.TextSizes.Body + 2, theme.Colors.TextSecondary, "Caption")
	caption.Text = GP_COPY.respawningIn
	caption.Position = UDim2.fromOffset(0, 186)
	caption.Size = UDim2.new(1, 0, 0, 26)
	caption.ZIndex = 6
	caption.Parent = plate
	self._caption = caption

	-- Butter pill on a FIXED footprint: the 1Hz pulse scales the numeral, and
	-- a fixed box is what keeps it from nudging the respawn chip (doc §5.3).
	local pillFill = theme.Arcade.Gold
	local pill = GPMatchFlow.Fill("CountdownPill", pillFill)
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, 216)
	pill.Size = UDim2.fromOffset(GP_COUNTDOWN_BOX.X, GP_COUNTDOWN_BOX.Y)
	pill.ZIndex = 6
	pill.Parent = plate
	UIStyler.Corner(theme.Radii.Pill).Parent = pill
	GPLayoutKit.SoftStroke(theme, pill, pillFill)
	GPLayoutKit.Shadow(theme, pill, "sm", shadows, pillFill)

	local countdown = GPLayoutKit.Text(theme, 62, theme.Colors.TextPrimary, "Countdown")
	countdown.RichText = false
	countdown.Size = UDim2.fromScale(1, 1)
	countdown.ZIndex = 7
	countdown.Parent = pill
	self._countdown = countdown

	self._respawnButton = GPMatchFlow.Button(theme, plate, {
		text = "RESPAWN",
		fill = theme.Colors.Secondary,
		sizePx = GP_RESPAWN_SIZE,
		position = UDim2.new(0.5, 0, 0, 328),
		anchorPoint = Vector2.new(0.5, 0),
		-- The classic button carries the rebirth glyph (iconId); the chip keeps
		-- it, because a soft aesthetic does not get to drop an affordance.
		iconKey = "rebirth",
		dimmed = true,
		onClick = function()
			self:_TryRespawn()
		end,
		sink = shadows,
	})
	self._respawnButton.Root.ZIndex = 6

	local hint = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Hint")
	hint.Text = "Your clay is still warm."
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -12)
	hint.Size = UDim2.new(1, 0, 0, 18)
	hint.ZIndex = 6
	hint.Parent = plate
end

-- ---- countdown ---------------------------------------------------------

function DeathScreen:_SetReady(ready: boolean)
	if self._ready == ready then
		return
	end
	self._ready = ready
	-- Text must ride along: SetContent re-resolves the label from the props it
	-- is handed, so a bare { dimmed = ... } would blank the button's caption.
	self._respawnButton:SetContent({ text = "RESPAWN", dimmed = not ready })
	if ready then
		self._caption.Text = self._copy.ready
		self._countdown.Text = self._copy.go
		UIChrome.Pulse(self:GetTheme(), self._respawnButton.Root)
	end
end

function DeathScreen:_RenderCountdown()
	self._countdown.Text = UIChrome.FormatCountdown(self._remaining)
end

-- 1Hz gold countdown (doc §11.3). Heartbeat with an accumulator rather than a
-- loop so teardown is a single Disconnect, and gated on the overlay actually
-- being on screen (doc §5.4).
function DeathScreen:_StartCountdown(seconds: number)
	self:_StopCountdown()
	self._remaining = math.max(0, math.floor(seconds))
	self:_SetReady(false)
	self._caption.Text = self._copy.respawningIn
	self:_RenderCountdown()
	if self._remaining <= 0 then
		self:_SetReady(true)
		return
	end

	local elapsed = 0
	self._tickConn = RunService.Heartbeat:Connect(function(dt: number)
		if not UIChrome.IsOnScreen(self._countdown) then
			return
		end
		elapsed += dt
		if elapsed < 1 then
			return
		end
		elapsed -= 1
		self._remaining -= 1
		if self._remaining <= 0 then
			self._remaining = 0
			self:_StopCountdown()
			self:_SetReady(true)
			return
		end
		self:_RenderCountdown()
		UIChrome.Pulse(self:GetTheme(), self._countdown)
	end)
end

function DeathScreen:_StopCountdown()
	if self._tickConn then
		self._tickConn:Disconnect()
		self._tickConn = nil
	end
end

-- ---- respawn -----------------------------------------------------------

function DeathScreen:_TryRespawn()
	if not self._ready then
		-- Every tap answers (doc §11.1): the press juice already played, so
		-- explain — and pulse the countdown, because the HUD (and its toast
		-- stack) is hidden for this focused moment.
		UIChrome.Pulse(self:GetTheme(), self._countdown)
		local hud = self.ScreenController:GetScreen("hud")
		if hud then
			hud:PushToast({ text = "Not yet", variant = "Error" })
		end
		return
	end
	self.ScreenController:HideScreen("death")
	if self._onRespawn then
		task.spawn(self._onRespawn)
	end
end

-- ---- lifecycle ---------------------------------------------------------

function DeathScreen:_OnShow(data: any?)
	local d = data or {}
	self._onRespawn = d.onRespawn

	local killedBy = d.killedBy
	if type(killedBy) == "string" and killedBy ~= "" then
		self._killedLabel.Text = self._copy.killedBy(killedBy)
		self._killedRow.Visible = true
	else
		self._killedRow.Visible = false
	end

	UIChrome.PopIn(self:GetTheme(), self._stage)
	self:_StartCountdown(d.respawnIn or DEFAULT_RESPAWN_SECONDS)
end

function DeathScreen:_OnHide()
	self:_StopCountdown()
end

function DeathScreen:Update(data: any)
	if not data or not self._built then
		return
	end
	if data.respawnIn ~= nil then
		self:_StartCountdown(data.respawnIn)
	end
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts only fall when
-- a handle is released — hand every GP shadow back here.
function DeathScreen:_OnTeardown()
	self:_StopCountdown()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
	self._copy = CLASSIC_COPY
end

function DeathScreen:Destroy()
	self:_StopCountdown()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
	if self._respawnButton then
		self._respawnButton:Destroy()
		self._respawnButton = nil
	end
	UIScreenBase.Destroy(self)
end

return DeathScreen
