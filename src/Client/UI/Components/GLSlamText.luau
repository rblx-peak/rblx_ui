--!strict
-- GLSlamText — the Gurren Lagann comic word-slam text engine. Text lands
-- WORD BY WORD: MaxVisibleGraphemes jumps straight to the next word-end each
-- beat (whole words slam in, never letters), and every landed word pops the
-- whole label (UIScale spike settling Back Out per Motion tokens) with a tiny
-- decaying shake tick.
--
-- THE 0.4 BOUNDARY: this module is ENTIRELY on the Luau + UITicker side.
-- Word timing, grapheme stepping, pop/shake choreography are sequenced
-- behavior, so they live here; styling owns only the static tokens consumed
-- (fonts, colors, DialectTokens numbers) and flips no state tags for any of
-- this. No StyleRule mirrors any part of the slam — a behavior implemented on
-- both sides would be a bug.
--
-- SLANT TECHNIQUE (no skew exists in Roblox): the comic tilt is a
-- whole-element Rotation on the label itself (DialectTokens.comic.slantDeg).
-- Rotation never reflows layout — neighbours keep their cells.
--
-- Not a UIComponentBase subclass on purpose: this is a fire-and-forget
-- ceremony element with a Play() handle contract. It takes a theme SNAPSHOT
-- per play (a ceremony never restyles mid-slam), so the base's theme
-- re-registration lifecycle is the wrong shape; UIScreenBase is for screens.
--
-- Contracts honored:
--   * Reduce motion: opts.reduceMotion, else a ReduceMotion boolean attribute
--     on `parent` — collapses to instant full text with one soft pop.
--   * Skippable: handle.Skip() at any point jumps to the full confirmed text
--     with zero residual tweens and fires onDone. The label is inert
--     (Active = false by default) so a running slam never blocks input;
--     ceremony hosts bind their skip input to the handle.
--   * Pooling: labels come from a module pool (release on Destroy); 100x
--     Play/Destroy grows nothing. No UIShadow is created (text glow is the
--     UIStroke path via UIChrome.TextOutline), so no shadow budget is spent.
--   * ONE UITicker.Register for the whole module: a single multiplexed
--     handler serves every concurrent play and unregisters when the last one
--     finishes. Auto-cleanup is per-play (a play whose label lost its parent
--     aborts itself), so the shared handler can never outlive its work.
--   * Shake caps: amplitude hard-capped at 6px, decay hard-capped at 0.4s
--     (GL tokens sit well inside: 2px / 0.15s). No flashes are used.
--
-- CJK fallback: a boundary-less run longer than slamCjkRunGraphemes slams
-- every slamCjkStepGraphemes graphemes instead, so utf8 text without spaces
-- still lands rhythmically.

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local StateDriver = require(script.Parent.Parent.StyleKit.StateDriver)
local Tags = require(script.Parent.Parent.StyleKit.Tags)

local GLSlamText = {}

export type SlamOptions = {
	sizePx: number?,
	perWordSeconds: number?,
	onDone: (() -> ())?,
	reduceMotion: boolean?,
}

export type SlamHandle = {
	Skip: () -> (),
	Destroy: () -> (),
}

type PlayState = {
	label: TextLabel,
	scale: UIScale,
	steps: { number }, -- cumulative grapheme counts to jump to, in order
	stepIndex: number,
	elapsed: number,
	nextAt: number,
	perWord: number,
	popScale: number,
	popInfo: TweenInfo,
	popTween: Tween?,
	shakePx: number,
	shakeSeconds: number,
	shakeAge: number, -- >= shakeSeconds means the shake is idle
	basePosition: UDim2,
	doneAt: number?, -- elapsed time at which the play finalizes naturally
	onDone: (() -> ())?,
	finished: boolean,
	destroyed: boolean,
}

-- Framework hard caps (laws, not style): shake <= 6px, decay <= 0.4s.
local SHAKE_PX_CAP = 6
local SHAKE_SECONDS_CAP = 0.4

-- Label pool (perf plumbing, not styling). Enough for stacked ceremonies.
local POOL_CAP = 8
local BASE_POSITION = UDim2.fromScale(0.5, 0.5)
local pool: { TextLabel } = {}

-- GL token fallbacks, mirroring GurrenLagannTheme.DialectTokens.comic — the
-- same pattern as UIChrome's DEFAULT_SHADOWS: the GL theme is the authority,
-- these keep the engine safe under themes that carry no DialectTokens.
local TOKEN_FALLBACKS: { [string]: number } = {
	slamPerWordSeconds = 0.12,
	slamPopScale = 1.15,
	slamShakePx = 2,
	slamShakeSeconds = 0.15,
	slamCjkRunGraphemes = 6,
	slamCjkStepGraphemes = 2,
	slantDeg = 0, -- only the comic dialect tilts; others render square
}

local function comicToken(theme: Types.UITheme, key: string): number
	local dialects = theme.DialectTokens
	local comic = if dialects then dialects.comic else nil
	local value = if comic then comic[key] else nil
	if type(value) == "number" then
		return value
	end
	local fallback = TOKEN_FALLBACKS[key]
	assert(fallback ~= nil, "GLSlamText: unknown comic token " .. key)
	return fallback
end

-- ---- word-boundary precompute ------------------------------------------

-- Walk utf8.graphemes once and produce the cumulative grapheme counts the
-- reveal jumps to: one step per word (run of non-whitespace graphemes), and
-- for boundary-less runs longer than `runMax` (CJK), a step every `runStep`
-- graphemes so the rhythm survives. MaxVisibleGraphemes counts every
-- grapheme including spaces, so cumulative indices line up exactly.
local function computeSteps(text: string, runMax: number, runStep: number): { number }
	runMax = math.max(1, math.floor(runMax))
	runStep = math.max(1, math.floor(runStep))

	local runs: { { first: number, last: number } } = {}
	local total = 0
	local runFirst = 0
	local inRun = false
	local ok = pcall(function()
		for startByte, endByte in utf8.graphemes(text) do
			total += 1
			local grapheme = string.sub(text, startByte, endByte)
			if string.match(grapheme, "%s") then
				if inRun then
					table.insert(runs, { first = runFirst, last = total - 1 })
					inRun = false
				end
			elseif not inRun then
				runFirst = total
				inRun = true
			end
		end
	end)
	if not ok then
		-- Invalid utf8: one slam of everything. MaxVisibleGraphemes saturates
		-- safely past the true count (see Framework/BootSequence), so byte
		-- length is a safe overshoot.
		return { #text }
	end
	if inRun then
		table.insert(runs, { first = runFirst, last = total })
	end

	local steps: { number } = {}
	for _, run in runs do
		local length = run.last - run.first + 1
		if length <= runMax then
			table.insert(steps, run.last)
		else
			-- CJK fallback: no word boundaries — land every `runStep`
			-- graphemes, folding any short remainder into the final step.
			local cursor = run.first - 1
			while cursor + runStep < run.last do
				cursor += runStep
				table.insert(steps, cursor)
			end
			table.insert(steps, run.last)
		end
	end
	return steps
end

-- ---- label pool ---------------------------------------------------------

local function acquire(): (TextLabel, UIScale)
	local label = table.remove(pool)
	if label == nil then
		local fresh = UIStyler.TextLabel("GLSlamText")
		fresh.RichText = false -- MaxVisibleGraphemes is silently ignored on RichText labels
		fresh.TextWrapped = true
		StateDriver.Structural(fresh, Tags.Structural.Label)
		local freshScale = Instance.new("UIScale")
		freshScale.Parent = fresh
		label = fresh
	end
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = BASE_POSITION
	label.Size = UDim2.fromScale(1, 1)
	label.Visible = true
	local scale = label:FindFirstChildOfClass("UIScale")
	if scale == nil then
		scale = Instance.new("UIScale")
		scale.Parent = label
	end
	scale.Scale = 1
	return label, scale
end

local function release(label: TextLabel)
	local ok = pcall(function()
		label.Parent = nil
	end)
	if not ok then
		return -- label died with its host; nothing left to pool
	end
	label.Text = ""
	label.MaxVisibleGraphemes = -1
	label.Rotation = 0
	label.Position = BASE_POSITION
	if #pool < POOL_CAP then
		table.insert(pool, label)
	else
		label:Destroy()
	end
end

-- ---- the shared ticker (ONE Register for the whole module) --------------

local activePlays: { [PlayState]: boolean } = {}
local activeCount = 0
local tickerStop: (() -> ())? = nil

local function deactivate(state: PlayState)
	if not activePlays[state] then
		return
	end
	activePlays[state] = nil
	activeCount -= 1
	if activeCount <= 0 and tickerStop then
		tickerStop()
		tickerStop = nil
	end
end

-- Complete to the final confirmed text with zero residual tweens, fire
-- onDone. Serves natural completion AND Skip — the end state is identical.
local function finishPlay(state: PlayState)
	if state.finished then
		return
	end
	state.finished = true
	deactivate(state)
	if state.popTween then
		state.popTween:Cancel()
		state.popTween = nil
	end
	state.label.MaxVisibleGraphemes = -1
	state.scale.Scale = 1
	state.label.Position = state.basePosition
	local callback = state.onDone
	state.onDone = nil
	if callback then
		-- DEFERRED on purpose: natural completion reaches here from inside
		-- stepAll's iteration over activePlays (itself inside UITicker's
		-- handler dispatch). An onDone that chains a new Play would otherwise
		-- insert keys into both tables MID-TRAVERSAL — undefined `next`
		-- behavior. Deferring runs the chain after the frame's dispatch.
		task.defer(callback)
	end
end

local function landStep(state: PlayState)
	local target = state.steps[state.stepIndex]
	state.label.MaxVisibleGraphemes = target
	-- Stamp pop on the WHOLE label: spike then settle Back Out (Motion token).
	if state.popTween then
		state.popTween:Cancel()
	end
	state.scale.Scale = state.popScale
	state.popTween = UIStyler.Tween(state.scale, state.popInfo, { Scale = 1 })
	state.shakeAge = 0 -- restart the landing shake tick
	if state.stepIndex >= #state.steps then
		state.doneAt = state.elapsed + math.max(state.shakeSeconds, state.popInfo.Time)
	end
end

local function stepPlay(state: PlayState, dt: number)
	local label = state.label
	if label.Parent == nil then
		-- Host tore down mid-ceremony: abort silently (Destroy semantics — no
		-- onDone); the label died with its host so it is not pooled.
		state.finished = true
		state.destroyed = true
		state.onDone = nil
		if state.popTween then
			state.popTween:Cancel()
			state.popTween = nil
		end
		deactivate(state)
		return
	end

	state.elapsed += dt
	while state.stepIndex < #state.steps and state.elapsed >= state.nextAt do
		state.stepIndex += 1
		landStep(state)
		state.nextAt += state.perWord
	end

	-- Landing shake: a few px of jitter decaying linearly to rest.
	if state.shakeAge < state.shakeSeconds then
		state.shakeAge += dt
		local progress = math.min(state.shakeAge / state.shakeSeconds, 1)
		if progress >= 1 then
			label.Position = state.basePosition
		else
			local magnitude = state.shakePx * (1 - progress)
			local base = state.basePosition
			label.Position = UDim2.new(
				base.X.Scale,
				base.X.Offset + (math.random() * 2 - 1) * magnitude,
				base.Y.Scale,
				base.Y.Offset + (math.random() * 2 - 1) * magnitude
			)
		end
	end

	if state.doneAt and state.elapsed >= state.doneAt then
		finishPlay(state)
	end
end

local function stepAll(dt: number, _now: number)
	-- Removing the CURRENT key during iteration is defined behavior (next
	-- semantics); plays only ever remove themselves.
	for state in activePlays do
		stepPlay(state, dt)
	end
end

local function activate(state: PlayState)
	if activePlays[state] then
		return
	end
	activePlays[state] = true
	activeCount += 1
	if not tickerStop then
		tickerStop = UITicker.Register(stepAll)
	end
end

-- ---- teardown -----------------------------------------------------------

local function destroyPlay(state: PlayState)
	if state.destroyed then
		return
	end
	state.destroyed = true
	state.onDone = nil -- Destroy is abort: never fires onDone
	state.finished = true
	deactivate(state)
	if state.popTween then
		state.popTween:Cancel()
		state.popTween = nil
	end
	release(state.label)
end

local function skipPlay(state: PlayState)
	if state.destroyed then
		return
	end
	if state.finished then
		-- Already at the final text (reduce-motion soft pop may still be
		-- settling): Skip still means zero residual tweens.
		if state.popTween then
			state.popTween:Cancel()
			state.popTween = nil
			state.scale.Scale = 1
		end
		return
	end
	finishPlay(state)
end

-- ---- API ----------------------------------------------------------------

-- Slams `text` into a pooled label filling `parent`, word by word. The label
-- persists showing the full text after completion — the ceremony owns removal
-- via handle.Destroy(). All visuals resolve from `theme` (fonts, colors) and
-- its DialectTokens.comic numbers; nothing here is hardcoded style.
function GLSlamText.Play(parent: Instance, theme: Types.UITheme, text: string, opts: SlamOptions?): SlamHandle
	local options: SlamOptions = opts or {}
	local reduceMotion = options.reduceMotion
	if reduceMotion == nil then
		reduceMotion = parent:GetAttribute("ReduceMotion") == true
	end

	local label, scale = acquire()
	label.FontFace = theme.Fonts.Title
	label.TextSize = options.sizePx or theme.TextSizes.Title
	label.TextColor3 = theme.Colors.TextPrimary
	UIChrome.TextOutline(label)
	-- Comic slant: whole-element Rotation (no skew exists in Roblox; rotation
	-- never reflows layout). Non-comic themes token-fall-back to 0.
	label.Rotation = comicToken(theme, "slantDeg")
	label.Text = text
	label.MaxVisibleGraphemes = 0
	label.Parent = parent

	local steps = computeSteps(
		text,
		comicToken(theme, "slamCjkRunGraphemes"),
		comicToken(theme, "slamCjkStepGraphemes")
	)
	local popScale = comicToken(theme, "slamPopScale")
	local popInfo = theme.Motion.PulseSettle

	local state: PlayState = {
		label = label,
		scale = scale,
		steps = steps,
		stepIndex = 0,
		elapsed = 0,
		nextAt = 0,
		perWord = math.max(options.perWordSeconds or comicToken(theme, "slamPerWordSeconds"), 0.02),
		popScale = popScale,
		popInfo = popInfo,
		popTween = nil,
		shakePx = math.clamp(comicToken(theme, "slamShakePx"), 0, SHAKE_PX_CAP),
		shakeSeconds = math.clamp(comicToken(theme, "slamShakeSeconds"), 0.01, SHAKE_SECONDS_CAP),
		shakeAge = math.huge, -- idle until the first landing
		basePosition = BASE_POSITION,
		doneAt = nil,
		onDone = options.onDone,
		finished = false,
		destroyed = false,
	}

	if reduceMotion or #steps == 0 then
		-- Instant final state with ONE soft pop: half the comic spike,
		-- settling on the same Motion token. No ticker, no shake.
		state.finished = true
		label.MaxVisibleGraphemes = -1
		scale.Scale = 1 + (popScale - 1) * 0.5
		state.popTween = UIStyler.Tween(scale, popInfo, { Scale = 1 })
		task.defer(function()
			local callback = state.onDone
			state.onDone = nil
			if callback then
				callback()
			end
		end)
	else
		activate(state)
		-- The first word lands NOW — a slam never waits a beat to start.
		state.stepIndex = 1
		landStep(state)
		state.nextAt = state.perWord
	end

	return {
		Skip = function()
			skipPlay(state)
		end,
		Destroy = function()
			destroyPlay(state)
		end,
	}
end

return GLSlamText
