--!strict
-- BootSequence — reusable "system power-on" for any screen or panel: a
-- flicker on the container, a staggered reveal of its direct children, and a
-- glyph-scramble type-on for tagged labels. Deliberately theme-agnostic —
-- the ARMORED CORE flavour comes from the theme (mono fonts, accent chrome),
-- not from this module, so any style can boot.
--
-- PREFER A CanvasGroup ROOT: when `root` IS a CanvasGroup the flicker drives
-- one GroupTransparency sequence (1 -> on -> 0.7 -> on -> 0.4 -> on, with
-- jittered holds) so the whole subtree flickers as a single composited
-- surface. Any other GuiObject falls back to Visible toggling — the caller's
-- tree is never reparented or wrapped to force a CanvasGroup in.
--
-- The sequence is COSMETIC ONLY and never gates input: nothing is disabled
-- and no overlay is added — every control is interactive the moment it is
-- visible.
--
-- Scramble opt-in: tag a TextLabel with SetAttribute("BootScramble", true).
-- Its text is captured ONCE, churned as random glyphs from `charset`, then
-- resolved by typing the TRUE string back on via MaxVisibleGraphemes — so
-- RichText tags and multibyte text are never byte-chopped — and restored
-- exactly.
--
-- Reduce-motion: root:GetAttribute("ReduceMotion") == true skips the whole
-- sequence — final state instantly, onComplete on the next frame.
--
-- All animation for one play() runs in ONE UITicker handler (bound to root,
-- so a root destroyed mid-sequence cleans itself up). cancel() snaps
-- everything to the final state, restores every label, and unregisters; it
-- does NOT fire onComplete. Calling play() again on the same root cancels
-- the first sequence.
--
-- Usage (screen _OnShow):
--   function GarageScreen:_OnShow()
--       self._bootCancel = BootSequence.play(self._panel, {
--           stagger = 0.04,
--           onComplete = function() self:_StartReadouts() end,
--       })
--   end
--   function GarageScreen:_OnHide()
--       if self._bootCancel then
--           self._bootCancel()
--           self._bootCancel = nil
--       end
--   end

local UITicker = require(script.Parent.UITicker)

local BootSequence = {}

export type BootConfig = {
	stagger: number?,
	scramble: boolean?,
	charset: string?,
	onComplete: (() -> ())?,
}

local DEFAULT_STAGGER = 0.05
local DEFAULT_CHARSET = "01<>[]#$%&/|"
local FLICKER_HOLD_MIN = 0.03 -- each keyframe holds 0.03..0.08s (jittered)
local FLICKER_HOLD_JITTER = 0.05
local SCRAMBLE_START_JITTER = 0.08 -- labels don't all churn in lockstep
local SCRAMBLE_HOLD = 0.22
local SCRAMBLE_HOLD_JITTER = 0.12
local SCRAMBLE_INTERVAL = 1 / 30 -- glyph churn throttle; per-frame would burn time on long labels
local SCRAMBLE_MAX_LEN = 40 -- bounds churn cost on very long strings
local RESOLVE_RATE = 60 -- graphemes/sec floor for the type-on
local RESOLVE_MAX_TIME = 0.35 -- long strings type faster instead of dragging

type ScrambleState = "wait" | "scramble" | "resolve" | "done"

type ScrambleEntry = {
	label: TextLabel,
	text: string, -- captured once, restored exactly
	richText: boolean,
	originalMax: number,
	total: number,
	scrambleLen: number,
	buffer: { string }, -- reused: char array + table.concat, no `..` in the hot loop
	scrambleStart: number,
	resolveStart: number,
	rate: number,
	accum: number,
	state: ScrambleState,
}

type ChildEntry = {
	gui: GuiObject,
	order: number,
	index: number,
}

type FlickerStep = {
	at: number,
	value: number,
}

-- Active sequence per root, so a second play() supersedes the first.
local active: { [GuiObject]: () -> () } = {}

-- Codepoint count approximates the grapheme count; the type-on only uses it
-- as a stop condition, and MaxVisibleGraphemes saturates safely if it
-- overcounts (RichText tags, combining marks).
local function countUnits(s: string): number
	local n = utf8.len(s)
	if n == nil then
		return #s
	end
	return n
end

local function splitGlyphs(charset: string): { string }
	local glyphs: { string } = {}
	local ok = pcall(function()
		for _, code in utf8.codes(charset) do
			table.insert(glyphs, utf8.char(code))
		end
	end)
	if not ok or #glyphs == 0 then
		table.clear(glyphs)
		for i = 1, #charset do
			table.insert(glyphs, string.sub(charset, i, i))
		end
	end
	return glyphs
end

function BootSequence.play(root: GuiObject, config: BootConfig?): () -> ()
	local cfg: BootConfig = config or {}
	local onComplete = cfg.onComplete

	local prior = active[root]
	if prior then
		prior()
	end

	if root:GetAttribute("ReduceMotion") == true then
		-- Nothing was touched, so the tree already IS the final state.
		if onComplete then
			task.defer(onComplete)
		end
		return function() end
	end

	local rng = Random.new()

	-- ---- flicker ---------------------------------------------------------
	local canvasGroup: CanvasGroup? = nil
	if root:IsA("CanvasGroup") then
		canvasGroup = root :: CanvasGroup
	end
	local onValue = if canvasGroup then canvasGroup.GroupTransparency else 0
	local originalVisible = root.Visible

	local flickerSteps: { FlickerStep } = {}
	do
		local pattern = { 1, onValue, 0.7, onValue, 0.4, onValue }
		local t = 0
		for i, value in pattern do
			flickerSteps[i] = { at = t, value = value }
			t += FLICKER_HOLD_MIN + rng:NextNumber() * FLICKER_HOLD_JITTER
		end
	end
	-- Children start revealing at the first "power on" keyframe.
	local revealStart = flickerSteps[2].at

	local function applyFlicker(value: number)
		if canvasGroup then
			canvasGroup.GroupTransparency = value
		else
			root.Visible = value < 0.5
		end
	end

	-- ---- staggered child reveal -------------------------------------------
	local stagger = cfg.stagger or DEFAULT_STAGGER
	local children: { ChildEntry } = {}
	for index, child in root:GetChildren() do
		-- Only children that were showing take part; a child the caller keeps
		-- hidden stays hidden through and after the boot.
		if child:IsA("GuiObject") and child.Visible then
			table.insert(children, { gui = child, order = child.LayoutOrder, index = index })
			child.Visible = false
		end
	end
	table.sort(children, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.index < b.index -- GetChildren order breaks ties (table.sort is unstable)
	end)

	-- ---- scramble entries ---------------------------------------------------
	local glyphs = splitGlyphs(cfg.charset or DEFAULT_CHARSET)
	if #glyphs == 0 then
		glyphs = splitGlyphs(DEFAULT_CHARSET)
	end
	local entries: { ScrambleEntry } = {}
	if cfg.scramble ~= false then
		for _, descendant in root:GetDescendants() do
			if descendant:IsA("TextLabel") and descendant:GetAttribute("BootScramble") == true then
				local text = descendant.Text
				local total = countUnits(text)
				if total > 0 then
					local scrambleLen = math.min(total, SCRAMBLE_MAX_LEN)
					local scrambleStart = revealStart + rng:NextNumber() * SCRAMBLE_START_JITTER
					table.insert(entries, {
						label = descendant,
						text = text,
						richText = descendant.RichText,
						originalMax = descendant.MaxVisibleGraphemes,
						total = total,
						scrambleLen = scrambleLen,
						buffer = table.create(scrambleLen) :: { string },
						scrambleStart = scrambleStart,
						resolveStart = scrambleStart + SCRAMBLE_HOLD + rng:NextNumber() * SCRAMBLE_HOLD_JITTER,
						rate = math.max(RESOLVE_RATE, total / RESOLVE_MAX_TIME),
						accum = math.huge, -- first churn tick fills immediately
						state = "wait" :: ScrambleState,
					})
					-- Blank until the churn starts so the true string never
					-- flashes ahead of its own type-on. RichText goes off for
					-- the churn phase: random glyphs (the charset carries "<"
					-- and ">") must never be parsed as markup. Both restored
					-- for the resolve — and exactly, on cancel.
					descendant.RichText = false
					descendant.Text = ""
					descendant.MaxVisibleGraphemes = -1
				end
			end
		end
	end
	local labelsPending = #entries

	-- ---- lifecycle -----------------------------------------------------------
	local finished = false
	local stopTicker: (() -> ())? = nil
	local destroyingConn: RBXScriptConnection? = nil
	local cancel: () -> ()

	local function snapFinal()
		if canvasGroup then
			canvasGroup.GroupTransparency = onValue
		else
			root.Visible = originalVisible
		end
		for _, entry in children do
			entry.gui.Visible = true
		end
		for _, e in entries do
			e.label.RichText = e.richText
			e.label.Text = e.text
			e.label.MaxVisibleGraphemes = e.originalMax
			e.state = "done"
		end
	end

	local function finish(completed: boolean)
		if finished then
			return
		end
		finished = true
		snapFinal()
		if stopTicker then
			stopTicker()
		end
		if destroyingConn then
			destroyingConn:Disconnect()
			destroyingConn = nil
		end
		if active[root] == cancel then
			active[root] = nil
		end
		if completed and onComplete then
			task.spawn(onComplete)
		end
	end

	cancel = function()
		finish(false)
	end
	active[root] = cancel
	-- Belt to UITicker's bindTo braces: the ticker handler dies with the root,
	-- but the active-map entry and label state must be released too.
	destroyingConn = root.Destroying:Connect(cancel)

	-- ---- THE one per-frame driver (UITicker; frame-rate independent) --------
	local elapsed = 0
	local flickerIndex = 1
	local childIndex = 1

	stopTicker = UITicker.Register(function(dt: number, _now: number)
		if finished then
			return
		end
		elapsed += dt

		-- Flicker: apply every keyframe we've reached; a slow frame lands on
		-- the newest one rather than stretching the sequence.
		while flickerIndex <= #flickerSteps and elapsed >= flickerSteps[flickerIndex].at do
			applyFlicker(flickerSteps[flickerIndex].value)
			flickerIndex += 1
		end

		-- Staggered reveal, LayoutOrder sequence.
		while childIndex <= #children and elapsed >= revealStart + (childIndex - 1) * stagger do
			children[childIndex].gui.Visible = true
			childIndex += 1
		end

		-- Scramble churn, then MaxVisibleGraphemes type-on of the true string.
		for _, e in entries do
			if e.state == "wait" and elapsed >= e.scrambleStart then
				e.state = "scramble"
			end
			if e.state == "scramble" then
				if elapsed >= e.resolveStart then
					e.state = "resolve"
					e.label.RichText = e.richText
					e.label.Text = e.text
					e.label.MaxVisibleGraphemes = 0
				else
					e.accum += dt
					if e.accum >= SCRAMBLE_INTERVAL then
						e.accum = 0
						local buffer = e.buffer
						for i = 1, e.scrambleLen do
							buffer[i] = glyphs[rng:NextInteger(1, #glyphs)]
						end
						e.label.Text = table.concat(buffer, "", 1, e.scrambleLen)
					end
				end
			end
			if e.state == "resolve" then
				local shown = math.floor((elapsed - e.resolveStart) * e.rate)
				if shown >= e.total then
					e.label.MaxVisibleGraphemes = e.originalMax
					e.state = "done"
					labelsPending -= 1
				else
					e.label.MaxVisibleGraphemes = shown
				end
			end
		end

		if flickerIndex > #flickerSteps and childIndex > #children and labelsPending == 0 then
			finish(true)
		end
	end, root)

	-- Power starts OFF this frame, not next Heartbeat — no one-frame flash of
	-- the assembled tree before the flicker begins.
	applyFlicker(flickerSteps[1].value)

	return cancel
end

return BootSequence
