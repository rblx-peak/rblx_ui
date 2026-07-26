--!strict
-- GLSpiralGauge — the SPIRAL POWER meter (Gurren Lagann pack / Life Pass
-- juice layer): a circular Pill-cornered dial well, a drill-spiral pointer
-- spinning on THE shared ticker at a speed proportional to charge, a
-- Fonts.Numeric % readout, and the COMBINATION READY chip that arms at full
-- charge.
--
-- THE 0.4 BOUNDARY: this module is the Luau + UITicker side. Styling owns
-- static appearance and the MAXED state LOOK — UIMaxed flips through
-- StateDriver (the sole tag mutator) so the pack's StyleRules can dress the
-- chip and pulse its glow (inert until the engine activates styling
-- application; the imperative theme path painted below renders meanwhile,
-- including the budget-safe UIChrome.Glow "pulse" fallback held enabled
-- while maxed and disabled otherwise). Luau + UITicker own everything
-- sequenced or continuous: the ticker-lerped display ratio, pointer
-- rotation, the brief overcharge overspin. Neither side implements the
-- other's half.
--
-- METER LAW: display updates are TICKER work. The readout and pointer are
-- never tweened — transitions are forbidden on meter fills — and the spiral
-- ART frame carries the UIMeterFill structural tag so SheetBuilder's
-- transition refusal covers this meter too.
--
-- NO-SKEW ANNOTATION: Roblox has no skew transform. The drill pointer is
-- whole-element Rotation on the ART child ("SpiralArt") — the dial root
-- keeps its unrotated square footprint, so layout never reflows. The chip's
-- comic slant is whole-element Rotation on the chip sticker itself (an
-- absolutely positioned leaf; nothing reflows). The spokes are sized to the
-- art frame's inscribed circle, so no clipping is needed (and none would
-- survive rotation anyway).
--
-- REDUCE-MOTION: a ReduceMotion boolean attribute on the returned Root
-- snaps the display chase, parks the pointer, and skips the overspin burst.
-- Nothing here is a blocking ceremony — the gauge never captures input.
--
-- BUDGETS: exactly ONE UITicker.Register per gauge (bound to the Root for
-- auto-cleanup; Destroy also stops it explicitly, idempotently) and at most
-- ONE glow UIShadow, budget-counted through UIChrome.Glow → Capabilities
-- .RegisterShadow: SetEnabled(false) below max (disable-not-destroy),
-- Release()d only in Destroy. 100x new/Destroy = zero connection or budget
-- growth.
--
-- Not a UIComponentBase subclass on purpose (same reasoning as GLSlamText):
-- the gauge takes a theme SNAPSHOT at construction — a Life Pass ceremony
-- element is rebuilt by its host on pack swaps, so the base's live-restyle
-- registration lifecycle is the wrong shape for it.
--
--   local gauge = GLSpiralGauge.new(parent, theme, { sizePx = 140 })
--   gauge:SetRatio(0.62) -- discrete; the display chases it on the ticker
--   gauge:SetRatio(1)    -- overcharge: overspin + UIMaxed + the chip arms
--   gauge:Destroy()

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local StateDriver = require(script.Parent.Parent.StyleKit.StateDriver)
local Tags = require(script.Parent.Parent.StyleKit.Tags)
local Capabilities = require(script.Parent.Parent.StyleKit.Capabilities)

local GLSpiralGauge = {}

export type GLSpiralGaugeOptions = {
	sizePx: number?,
}

export type GLSpiralGauge = {
	Root: Frame,
	SetRatio: (self: GLSpiralGauge, ratio: number) -> (),
	Destroy: (self: GLSpiralGauge) -> (),
}

-- Framework hard cap (a law, not a style token): the pointer never exceeds
-- 360°/s — not at full charge, not during the overcharge burst.
local POINTER_DPS_CAP = 360

local DEFAULT_SIZE_PX = 120

-- Drill cross-section: one long heat hand plus three gold flutes at
-- IRREGULAR angles — the irregularity is what reads as a drill (not a fan)
-- once spinning. Lengths are fractions of the ART frame; widths fractions of
-- the dial diameter. Colors resolve from the theme in the builder.
local SPOKES = {
	{ angle = 0, length = 0.5, width = 0.075, heat = true },
	{ angle = 105, length = 0.42, width = 0.055, heat = false },
	{ angle = 195, length = 0.32, width = 0.045, heat = false },
	{ angle = 285, length = 0.42, width = 0.055, heat = false },
}

-- ---- GL comic token access ----------------------------------------------
-- GurrenLagannTheme.DialectTokens.comic is the authority for every
-- GL-specific number/string; the fallbacks keep the gauge safe (and square,
-- and modest) under packs that carry no DialectTokens.

local function comicTokens(theme: Types.UITheme): { [string]: any }?
	local dialects = theme.DialectTokens
	return if dialects then dialects.comic else nil
end

local function comicNumber(theme: Types.UITheme, key: string, fallback: number): number
	local comic = comicTokens(theme)
	local value = if comic then comic[key] else nil
	return if type(value) == "number" then value else fallback
end

local function comicString(theme: Types.UITheme, key: string, fallback: string): string
	local comic = comicTokens(theme)
	local value = if comic then comic[key] else nil
	return if type(value) == "string" then value else fallback
end

local function comicColor(theme: Types.UITheme, key: string, fallback: Color3): Color3
	local comic = comicTokens(theme)
	local value = if comic then comic[key] else nil
	return if typeof(value) == "Color3" then value else fallback
end

-- ---- API ----------------------------------------------------------------

function GLSpiralGauge.new(parent: Instance, theme: Types.UITheme, opts: GLSpiralGaugeOptions?): GLSpiralGauge
	local options: GLSpiralGaugeOptions = opts or {}
	local sizePx = math.max(48, math.floor(options.sizePx or DEFAULT_SIZE_PX))

	local chipHeight = math.max(22, math.floor(sizePx * 0.2))
	local chipGap = math.max(4, math.floor(sizePx * 0.05))
	local rootWidth = math.floor(sizePx * 1.12) -- the chip sticker overhangs the dial

	-- GL feel numbers (theme-authored; see GurrenLagannTheme.DialectTokens).
	local pointerBaseDps = math.min(comicNumber(theme, "spiralPointerBaseDps", 240), POINTER_DPS_CAP)
	local overspinSeconds = math.max(0.05, comicNumber(theme, "spiralOverspinSeconds", 0.45))
	local lerpRate = math.max(1, comicNumber(theme, "spiralLerpRate", 9))

	local root = UIStyler.Frame("GLSpiralGauge")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(rootWidth, sizePx + chipGap + chipHeight)
	StateDriver.Structural(root, Tags.Structural.Surface)

	-- Dial well: geometric circle (Pill corner policy — circles are geometry,
	-- not decoration, so they survive HardCorners), panel-cel fill, ink frame.
	local well = UIStyler.Frame("Well")
	well.BackgroundColor3 = theme.Arcade.NearBlack
	well.AnchorPoint = Vector2.new(0.5, 0)
	well.Position = UDim2.new(0.5, 0, 0, 0)
	well.Size = UDim2.fromOffset(sizePx, sizePx)
	well.ZIndex = 1
	UIChrome.Corner("Arcade", "Pill").Parent = well
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = well
	well.Parent = root

	-- ART child: carries every spinning visual; the ticker drives Rotation on
	-- THIS frame only (whole-element rotation — see header). Sized to the
	-- inscribed circle so centered spokes can never poke past the round rim.
	local art = UIStyler.Frame("SpiralArt")
	art.BackgroundTransparency = 1
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	local artPx = math.floor(sizePx * 0.8)
	art.Size = UDim2.fromOffset(artPx, artPx)
	art.ZIndex = 2
	StateDriver.Structural(art, Tags.Structural.MeterFill)
	art.Parent = well

	for index, spec in SPOKES do
		-- Spoke wrapper: full-size and rotated about the art center; the bar
		-- inside is anchored bottom-center AT that center, so it sweeps like
		-- a clock hand as the art spins. (Child rotation about the child's
		-- own center cannot orbit a bar — the wrapper trick can.)
		local spoke = UIStyler.Frame("Spoke" .. index)
		spoke.BackgroundTransparency = 1
		spoke.Rotation = spec.angle
		spoke.ZIndex = 2
		spoke.Parent = art

		local bar = UIStyler.Frame("Bar")
		bar.BackgroundColor3 = if spec.heat then theme.Colors.Primary else theme.Arcade.Gold
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.new(0, math.max(3, math.floor(sizePx * spec.width)), spec.length, 0)
		bar.ZIndex = 2
		bar.Parent = spoke
	end

	-- Hub cap over the spoke bases (gold, ink-ringed).
	local hub = UIStyler.Frame("Hub")
	hub.BackgroundColor3 = theme.Arcade.Gold
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	local hubPx = math.max(10, math.floor(sizePx * 0.16))
	hub.Size = UDim2.fromOffset(hubPx, hubPx)
	hub.ZIndex = 3
	UIChrome.Corner("Arcade", "Pill").Parent = hub
	UIChrome.Stroke(theme, "Arcade", "Button").Parent = hub
	hub.Parent = well

	-- Numeric % readout: the meter's value face (ticker-set, never tweened).
	local readout = UIStyler.TextLabel("Readout")
	readout.FontFace = theme.Fonts.Numeric
	readout.TextSize = math.max(14, math.floor(sizePx * 0.2))
	readout.TextColor3 = theme.Colors.TextPrimary
	readout.Size = UDim2.fromScale(1, 1)
	readout.ZIndex = 4
	readout.Text = "0%"
	UIChrome.TextOutline(readout)
	StateDriver.Structural(readout, Tags.Structural.Value)
	readout.Parent = well

	-- COMBINATION READY chip: built once, ARMED by the UIMaxed flip. Its
	-- LOOK belongs to the styling side (".UIChip.UIMaxed" once live); its
	-- presence (Visible) and the fallback glow are the imperative bridge.
	local chip = UIStyler.Frame("ReadyChip")
	chip.BackgroundColor3 = theme.Arcade.Gold
	chip.AnchorPoint = Vector2.new(0.5, 1)
	chip.Position = UDim2.new(0.5, 0, 1, 0)
	chip.Size = UDim2.fromOffset(rootWidth, chipHeight)
	chip.ZIndex = 5
	chip.Visible = false
	-- Comic sticker slant: whole-element Rotation on the chip leaf.
	chip.Rotation = comicNumber(theme, "slantDeg", 0)
	UIChrome.Corner("Arcade").Parent = chip
	UIChrome.Stroke(theme, "Arcade", "Button").Parent = chip
	StateDriver.Structural(chip, Tags.Structural.Chip)
	chip.Parent = root

	local chipLabel = UIStyler.TextLabel("Text")
	chipLabel.FontFace = theme.Fonts.Button
	chipLabel.TextSize = math.max(12, math.floor(chipHeight * 0.58))
	chipLabel.TextColor3 = comicColor(theme, "ink", theme.Colors.Stroke)
	chipLabel.Size = UDim2.fromScale(1, 1)
	chipLabel.ZIndex = 5
	chipLabel.Text = comicString(theme, "spiralMaxedText", "MAX!")
	StateDriver.Structural(chipLabel, Tags.Structural.Label)
	chipLabel.Parent = chip

	-- The comic dialect scopes this subtree's pack rules; packs without the
	-- dialect never wear the tag and pay nothing.
	if comicTokens(theme) then
		StateDriver.SetDialect(root, Tags.Dialect.Comic)
	end

	-- ---- state -----------------------------------------------------------

	local displayed = 0 -- what the dial currently SHOWS (chases target)
	local target = 0 -- last discrete SetRatio, clamped for display
	local lastPercent = -1
	local overspinLeft = 0 -- seconds of overcharge burst remaining
	local isMaxed = false
	local destroyed = false
	local glowHandle: Capabilities.ShadowHandle? = nil

	local reduceMotion = root:GetAttribute("ReduceMotion") == true
	local attrConn = root:GetAttributeChangedSignal("ReduceMotion"):Connect(function()
		reduceMotion = root:GetAttribute("ReduceMotion") == true
	end)

	-- THE one UITicker handler of this gauge: display chase + pointer spin.
	-- Bound to the Root so destruction auto-unregisters (Destroy also stops
	-- it explicitly, idempotently).
	local stopTicker = UITicker.Register(function(dt: number, _now: number)
		-- Display chase (TICKER work — meters are never tweened).
		if reduceMotion then
			displayed = target
		else
			displayed += (target - displayed) * math.min(1, dt * lerpRate)
			if math.abs(target - displayed) < 0.0005 then
				displayed = target
			end
		end
		local percent = math.floor(displayed * 100 + 0.5)
		if percent ~= lastPercent then
			lastPercent = percent
			readout.Text = string.format("%d%%", percent)
		end

		-- Pointer spin: proportional to displayed charge; the overcharge
		-- burst decays linearly; EVERYTHING sits under the 360°/s cap.
		-- Frugal (doc §5.4): zero work off-screen; reduce-motion parks it.
		if reduceMotion or not UIChrome.IsOnScreen(well) then
			return
		end
		local speed = math.min(displayed, 1) * pointerBaseDps
		if overspinLeft > 0 then
			overspinLeft = math.max(0, overspinLeft - dt)
			speed += (overspinLeft / overspinSeconds) * POINTER_DPS_CAP
		end
		speed = math.min(speed, POINTER_DPS_CAP)
		if speed > 0 then
			art.Rotation = (art.Rotation + speed * dt) % 360
		end
	end, root)

	local gauge = {} :: GLSpiralGauge
	gauge.Root = root

	-- Discrete ratio in; the ticker chases it. ratio >= 1 arms overcharge:
	-- UIMaxed flips through StateDriver on the ROOT (the meter contract) and
	-- on the CHIP (so ".UIChip.UIMaxed" rules dress the sticker directly),
	-- the pointer overspins briefly, and the imperative pulse-glow fallback
	-- arms. Dropping below 1 clears all of it.
	function gauge.SetRatio(_, ratio: number)
		if destroyed then
			return
		end
		target = math.clamp(ratio, 0, 1)
		local maxed = ratio >= 1
		if maxed == isMaxed then
			return
		end
		isMaxed = maxed
		StateDriver.Set(root, Tags.Modifier.Maxed, maxed)
		StateDriver.Set(chip, Tags.Modifier.Maxed, maxed)
		chip.Visible = maxed -- presence is Luau state; the LOOK is styling's
		if maxed then
			if not reduceMotion then
				overspinLeft = overspinSeconds
			end
			-- Imperative fallback glow (the styling side pulses it once
			-- live): built lazily ONCE, then disable-not-destroy so 100
			-- max/unmax cycles cost one budget slot and zero churn.
			local handle = glowHandle
			if handle == nil then
				local _glowInstance, fresh = UIChrome.Glow(theme, "pulse", chip)
				glowHandle = fresh :: Capabilities.ShadowHandle
			else
				handle:SetEnabled(true)
			end
		else
			overspinLeft = 0
			local handle = glowHandle
			if handle then
				handle:SetEnabled(false)
			end
		end
	end

	function gauge.Destroy(_)
		if destroyed then
			return
		end
		destroyed = true
		stopTicker()
		attrConn:Disconnect()
		local handle = glowHandle
		if handle then
			handle:Release() -- actual teardown: the budget slot is returned
			glowHandle = nil
		end
		root:Destroy()
	end

	root.Parent = parent
	return gauge
end

return GLSpiralGauge
