--!strict
-- SlashTransition (E8) — the between-screens diagonal wipe: two angular
-- panels SLAM shut over the whole screen, the router swaps screens behind
-- the cover (`during` runs in that window — the load-hiding trick), manga
-- action-line stripes streak across the covered frame, then the panels
-- fling open and clear. Budget: 0.12s close + 0.15s covered + 0.14s open
-- = 0.41s, under the 0.45s cap.
--
-- THE 0.4 BOUNDARY: Styling owns static appearance and state looks (tags
-- flipped through StateDriver; inert until the engine activates styling
-- application — the imperative theme path renders meanwhile). Luau +
-- UITicker own everything sequenced, continuous, or non-styling-triggered:
-- word timing, rotation, particles, choreography, shake. This module lives
-- ENTIRELY on the Luau side — a sequenced full-screen choreography (close →
-- covered → open) with a stripe scroll driven by the ONE shared ticker. It
-- flips no style tags and owns no static look; every colour it paints is
-- read from the theme handed to Play.
--
-- NO SKEW EXISTS IN ROBLOX — technique used here: each panel is an
-- OVERSIZED frame (1.5×3 screens) carrying whole-element Rotation; the
-- rotated leading edge IS the diagonal seam. Overhang past the viewport
-- simply isn't rendered, so no clipping is needed (rotated GuiObjects
-- ignore ClipsDescendants anyway — which is exactly why the root doesn't
-- try to clip). The stripe layer is the same trick: an oversized rotated
-- container whose plain horizontal children render as slanted speed lines.
-- Nothing here reflows layout — panels and stripes are absolute-positioned
-- decoration in their own layer.
--
-- POOLED (zero garbage per transition): the whole rig — panels, strokes,
-- the stripe pool, the four Tweens, the one ticker handler, the input
-- listener — is built ONCE at first Play and reused forever. A repeat Play
-- creates zero instances and zero connections; Destroy() releases all of
-- it (and a destroyed Cursor layer self-cleans via root.Destroying +
-- UITicker's bindTo).
--
-- RE-ENTRANCY: Play while the wipe is active COALESCES into the one live
-- ceremony — while closing, the new `during` joins the covered window
-- already in flight; while covered, it runs immediately; while opening,
-- the same panels fold back shut first. Two panel sets never exist.
--
-- REDUCE-MOTION (opts.reduceMotion, or a ReduceMotion boolean attribute on
-- the module root frame "SlashTransition" in the Cursor layer): during() +
-- onDone() run immediately, no visuals. SKIPPABLE: any press mid-wipe
-- (after a ~30ms arm window, so the very press whose handler STARTED the
-- wipe can't self-skip it in the same input dispatch) jumps straight to
-- the final confirmed state — pending `during`s run, panels clear, onDones
-- fire. The overlay is never Active, so input is never blocked.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local Layers = require(script.Parent.Layers)
local UITicker = require(script.Parent.UITicker)

local SlashTransition = {}

export type PlayOpts = {
	during: (() -> ())?,
	onDone: (() -> ())?,
	reduceMotion: boolean?,
}

-- Choreography contract (the E8 budget) — pack-agnostic on purpose: packs
-- tune the LOOK via theme tokens, never the timing.
local CLOSE_TIME = 0.12 -- panels slam shut (Quad In)
local COVER_TIME = 0.15 -- stripe window while the router swaps behind cover
local OPEN_TIME = 0.14 -- panels fling open (Quad Out)

local CLOSE_INFO = TweenInfo.new(CLOSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local OPEN_INFO = TweenInfo.new(OPEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Panel geometry, in scale of the full-screen root. Oversized so the
-- rotated seam crosses the whole viewport with margin at every angle a
-- pack plausibly asks for; positions are fixed, so the four tweens can be
-- prebuilt once and replayed.
local PANEL_W = 1.5
local PANEL_H = 3
local SEAM_OVERLAP = 0.03 -- closed panels overlap 3% so the seam can't hairline
local DEFAULT_SLASH_DEG = 14 -- override: theme.DialectTokens.comic.slashAngleDeg

local CLOSED_A = UDim2.fromScale(0.5 - PANEL_W / 2 + SEAM_OVERLAP, 0.5)
local CLOSED_B = UDim2.fromScale(0.5 + PANEL_W / 2 - SEAM_OVERLAP, 0.5)
local OPEN_A = UDim2.fromScale(-1.35, 0.5) -- fully clear of the viewport
local OPEN_B = UDim2.fromScale(2.35, 0.5)

-- Speed-line pool: thin frames inside an oversized rotated container (2×2
-- screens, centred — the viewport occupies its central band, 0.25..0.75).
local STRIPE_COUNT = 9
local STRIPE_MIN_X = -0.3 -- wrap bounds, container scale
local STRIPE_MAX_X = 1.05
local STRIPE_MIN_Y = 0.25 -- keep lanes inside the visible band
local STRIPE_MAX_Y = 0.75
local STRIPE_MIN_SPEED = 2.6 -- container-scale/s: a streak crosses in ~0.1-0.2s
local STRIPE_MAX_SPEED = 5
local STRIPE_MIN_HEIGHT = 2 -- px
local STRIPE_MAX_HEIGHT = 6
local STRIPE_MIN_WIDTH = 0.18 -- container scale (2 screens = 0.36+ screens long)
local STRIPE_MAX_WIDTH = 0.45
local STRIPE_MIN_TRANSPARENCY = 0.55 -- "paper at low alpha"
local STRIPE_MAX_TRANSPARENCY = 0.8

-- Inputs that skip: presses, not pointer drift (mouse movement / stick
-- wander must not eat the wipe).
local SKIP_INPUTS: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.Keyboard] = true,
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
	[Enum.UserInputType.Touch] = true,
	[Enum.UserInputType.Gamepad1] = true,
}
-- The skip listener ignores input younger than this: the InputBegan whose
-- handler issued the Play (keyboard nav bound to InputBegan is common) is
-- redelivered to OUR listener in the same dispatch and must not instantly
-- self-skip the wipe it just started. Deliberate presses a frame+ later skip.
local SKIP_ARM_TIME = 0.03

type Phase = "Idle" | "Closing" | "Covered" | "Opening"

type Rig = {
	root: Frame,
	panelA: Frame,
	panelB: Frame,
	strokeA: UIStroke,
	strokeB: UIStroke,
	stripeLayer: Frame,
	stripes: { Frame },
	closeA: Tween,
	closeB: Tween,
	openA: Tween,
	openB: Tween,
	stopTicker: () -> (),
	connections: { RBXScriptConnection },
}

local rig: Rig? = nil
local phase: Phase = "Idle"
local coveredElapsed = 0
local rng = Random.new()

-- Coalesced callback queues (module-level, reused across transitions).
local pendingDuring: { () -> () } = {}
local pendingDone: { () -> () } = {}
local stripeSpeeds: { number } = table.create(STRIPE_COUNT, 0)
-- os.clock() stamp of the Play that engaged the ceremony — see SKIP_ARM_TIME.
local wipeStartedAt = 0

local function callSafe(fn: (() -> ())?, label: string)
	if not fn then
		return
	end
	local ok, err = pcall(fn)
	if not ok then
		warn("[SlashTransition] " .. label .. " error: " .. tostring(err))
	end
end

-- Snapshot the queued batch before running: a callback may start the NEXT
-- transition, and that transition's queue entries must not run inside this
-- one. The batch is a fresh (tiny, usually 1-entry) table per non-empty
-- flush rather than a shared scratch: flushes can reenter — a callback may
-- call Destroy(), whose teardown flushes these same queues — and a shared
-- scratch would let the inner flush clobber entries the outer flush hasn't
-- run yet, silently losing promised callbacks.
local function flush(queue: { () -> () }, label: string)
	local n = #queue
	if n == 0 then
		return
	end
	local batch: { () -> () } = table.create(n)
	table.move(queue, 1, n, 1, batch)
	table.clear(queue)
	for i = 1, n do
		callSafe(batch[i], label)
	end
end

-- Re-deal the speed-line lanes so every wipe reads freshly hand-drawn.
local function scatterStripes(r: Rig)
	for i, stripe in r.stripes do
		stripeSpeeds[i] = rng:NextNumber(STRIPE_MIN_SPEED, STRIPE_MAX_SPEED)
		stripe.Size = UDim2.new(
			rng:NextNumber(STRIPE_MIN_WIDTH, STRIPE_MAX_WIDTH),
			0,
			0,
			rng:NextInteger(STRIPE_MIN_HEIGHT, STRIPE_MAX_HEIGHT)
		)
		stripe.Position = UDim2.fromScale(
			rng:NextNumber(STRIPE_MIN_X, STRIPE_MAX_X),
			rng:NextNumber(STRIPE_MIN_Y, STRIPE_MAX_Y)
		)
		stripe.BackgroundTransparency = rng:NextNumber(STRIPE_MIN_TRANSPARENCY, STRIPE_MAX_TRANSPARENCY)
	end
end

local function beginOpen()
	local r = rig
	if not r then
		return
	end
	phase = "Opening"
	r.stripeLayer.Visible = false
	r.openA:Play()
	r.openB:Play()
end

local function enterCovered()
	local r = rig
	if not r then
		return
	end
	phase = "Covered"
	coveredElapsed = 0
	-- The load-hiding window: the router swaps screens NOW, fully covered.
	-- Phase is already "Covered", so a Play issued from inside a `during`
	-- coalesces correctly (its own during runs inline).
	flush(pendingDuring, "during")
	if rig ~= r then
		return -- a during() tore the rig down
	end
	scatterStripes(r)
	r.stripeLayer.Visible = true
end

local function finishOpen()
	local r = rig
	phase = "Idle"
	if r then
		r.root.Visible = false
	end
	-- Phase is "Idle" first, so an onDone that Plays again starts fresh.
	flush(pendingDone, "onDone")
end

-- HARD LAW: any user input mid-ceremony jumps to the final confirmed state
-- instantly. The promised covered-window work still happens (a lost during
-- would strand the router mid-swap) — it just happens NOW.
local function skipToEnd()
	local r = rig
	if not r or phase == "Idle" then
		return
	end
	r.closeA:Cancel()
	r.closeB:Cancel()
	r.openA:Cancel()
	r.openB:Cancel()
	phase = "Covered" -- so a Play inside a flushed during coalesces inline
	flush(pendingDuring, "during")
	if rig ~= r then
		return
	end
	r.stripeLayer.Visible = false
	r.panelA.Position = OPEN_A
	r.panelB.Position = OPEN_B
	finishOpen()
end

-- THE one ticker handler for this module: covered-phase timing + the
-- stripe scroll. Early-outs to a single compare in every other phase.
local function step(dt: number, _now: number)
	local r = rig
	if not r or phase ~= "Covered" then
		return
	end
	for i, stripe in r.stripes do
		local pos = stripe.Position
		local x = pos.X.Scale + stripeSpeeds[i] * dt
		if x > STRIPE_MAX_X then
			-- Wrap with a fresh lane so the loop never reads as a loop.
			stripe.Position = UDim2.fromScale(STRIPE_MIN_X, rng:NextNumber(STRIPE_MIN_Y, STRIPE_MAX_Y))
		else
			stripe.Position = UDim2.fromScale(x, pos.Y.Scale)
		end
	end
	coveredElapsed += dt
	if coveredElapsed >= COVER_TIME then
		beginOpen()
	end
end

-- Release EVERYTHING (pooling law: 100 transitions = zero connection
-- growth, and teardown leaves nothing behind). Promised callbacks still
-- run — never lost, merely instant.
local function teardown(r: Rig, destroyRoot: boolean)
	if rig == r then
		rig = nil
	end
	phase = "Idle"
	r.stopTicker()
	for _, connection in r.connections do
		connection:Disconnect()
	end
	table.clear(r.connections)
	r.closeA:Cancel()
	r.closeB:Cancel()
	r.openA:Cancel()
	r.openB:Cancel()
	if destroyRoot then
		r.root:Destroy()
	end
	flush(pendingDuring, "during")
	flush(pendingDone, "onDone")
end

-- Build the rig ONCE (module-level pool); rebuild only if the Cursor layer
-- was externally destroyed. Colours passed in are provisional — applyTheme
-- repaints on every Play.
local function ensureRig(theme: Types.UITheme): Rig
	local existing = rig
	if existing and existing.root.Parent then
		return existing
	end
	if existing then
		teardown(existing, true)
	end

	local root = UIStyler.Frame("SlashTransition")
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Active = false -- never blocks input (hard law)
	root.Parent = Layers.Get("Cursor")

	local strokeThickness = theme.Effects.StrokeThickness
	local function buildPanel(name: string, openPos: UDim2): (Frame, UIStroke)
		local panel = UIStyler.Frame(name)
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Size = UDim2.fromScale(PANEL_W, PANEL_H)
		panel.Position = openPos
		panel.BackgroundColor3 = theme.Colors.Background
		panel.ZIndex = 2
		local stroke = UIStyler.Stroke(theme.Colors.Stroke, strokeThickness, 0)
		stroke.Parent = panel
		panel.Parent = root
		return panel, stroke
	end
	local panelA, strokeA = buildPanel("SlashPanelA", OPEN_A)
	local panelB, strokeB = buildPanel("SlashPanelB", OPEN_B)

	local stripeLayer = UIStyler.Frame("Stripes")
	stripeLayer.BackgroundTransparency = 1
	stripeLayer.AnchorPoint = Vector2.new(0.5, 0.5)
	stripeLayer.Position = UDim2.fromScale(0.5, 0.5)
	stripeLayer.Size = UDim2.fromScale(2, 2)
	stripeLayer.ZIndex = 3
	stripeLayer.Visible = false
	stripeLayer.Parent = root

	local stripes: { Frame } = table.create(STRIPE_COUNT)
	for _ = 1, STRIPE_COUNT do
		local stripe = UIStyler.Frame("Stripe")
		stripe.AnchorPoint = Vector2.new(0, 0.5)
		stripe.Size = UDim2.new(STRIPE_MIN_WIDTH, 0, 0, STRIPE_MIN_HEIGHT)
		stripe.Parent = stripeLayer
		table.insert(stripes, stripe)
	end

	local connections: { RBXScriptConnection } = {}
	local closeA = TweenService:Create(panelA, CLOSE_INFO, { Position = CLOSED_A })
	local closeB = TweenService:Create(panelB, CLOSE_INFO, { Position = CLOSED_B })
	local openA = TweenService:Create(panelA, OPEN_INFO, { Position = OPEN_A })
	local openB = TweenService:Create(panelB, OPEN_INFO, { Position = OPEN_B })

	local newRig: Rig = {
		root = root,
		panelA = panelA,
		panelB = panelB,
		strokeA = strokeA,
		strokeB = strokeB,
		stripeLayer = stripeLayer,
		stripes = stripes,
		closeA = closeA,
		closeB = closeB,
		openA = openA,
		openB = openB,
		-- THE one UITicker.Register for this module, bound to the root for
		-- auto-cleanup if the layer dies.
		stopTicker = UITicker.Register(step, root),
		connections = connections,
	}
	rig = newRig

	-- Panel A drives phase changes (both tweens share one TweenInfo). The
	-- PlaybackState guard ignores Cancel-fired Completed events.
	table.insert(connections, closeA.Completed:Connect(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and phase == "Closing" and rig == newRig then
			enterCovered()
		end
	end))
	table.insert(connections, openA.Completed:Connect(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and phase == "Opening" and rig == newRig then
			finishOpen()
		end
	end))
	-- One persistent listener (guarded to a single compare while idle), so
	-- repeat transitions create zero connections.
	table.insert(connections, UserInputService.InputBegan:Connect(function(input: InputObject, _processed: boolean)
		if
			phase ~= "Idle"
			and SKIP_INPUTS[input.UserInputType]
			and os.clock() - wipeStartedAt >= SKIP_ARM_TIME
		then
			skipToEnd()
		end
	end))
	table.insert(connections, root.Destroying:Connect(function()
		if rig == newRig then
			teardown(newRig, false)
		end
	end))

	return newRig
end

-- Repainted on EVERY Play (cheap property writes, no instance churn): the
-- rig outlives theme swaps, so the look always follows the theme handed in.
-- Panels = Colors.Background framed in the pack's ink (Colors.Stroke);
-- stripes = DialectTokens.comic.paper when the pack speaks comic, else
-- Colors.Surface — so every pack wipes in its own voice.
local function applyTheme(r: Rig, theme: Types.UITheme)
	local chrome = theme.Chrome
	local inkThickness = if chrome then chrome.StrokeThickness else theme.Effects.StrokeThickness

	local slashDeg = DEFAULT_SLASH_DEG
	local stripeColor = theme.Colors.Surface
	local dialects = theme.DialectTokens
	local comic = if dialects then dialects.comic else nil
	if comic then
		local angle = comic.slashAngleDeg
		if typeof(angle) == "number" then
			slashDeg = angle :: number
		end
		local paper = comic.paper
		if typeof(paper) == "Color3" then
			stripeColor = paper :: Color3
		end
	end

	r.panelA.BackgroundColor3 = theme.Colors.Background
	r.panelB.BackgroundColor3 = theme.Colors.Background
	r.panelA.Rotation = slashDeg
	r.panelB.Rotation = slashDeg
	r.strokeA.Color = theme.Colors.Stroke
	r.strokeB.Color = theme.Colors.Stroke
	r.strokeA.Thickness = inkThickness
	r.strokeB.Thickness = inkThickness
	r.stripeLayer.Rotation = slashDeg
	for _, stripe in r.stripes do
		stripe.BackgroundColor3 = stripeColor
	end
end

-- Play the wipe. `during` runs while the screen is fully covered (the
-- router swaps screens there); `onDone` fires after the panels clear. See
-- the header for re-entrancy / reduce-motion / skip semantics.
function SlashTransition.Play(theme: Types.UITheme, opts: PlayOpts?)
	local during: (() -> ())? = nil
	local onDone: (() -> ())? = nil
	local reduce = false
	if opts then
		during = opts.during
		onDone = opts.onDone
		reduce = opts.reduceMotion == true
	end

	if reduce then
		callSafe(during, "during")
		callSafe(onDone, "onDone")
		return
	end

	local r = ensureRig(theme)
	if r.root:GetAttribute("ReduceMotion") == true then
		callSafe(during, "during")
		callSafe(onDone, "onDone")
		return
	end

	applyTheme(r, theme)

	-- Re-arm the skip guard: the press whose handler issued THIS Play (same
	-- InputBegan dispatch — our listener fires after theirs) must not
	-- immediately self-skip the ceremony it just engaged.
	wipeStartedAt = os.clock()

	if onDone then
		table.insert(pendingDone, onDone)
	end

	if phase == "Covered" then
		-- Coalesce: already covered — the swap window is NOW.
		callSafe(during, "during")
		return
	end

	if during then
		table.insert(pendingDuring, during)
	end

	if phase == "Idle" then
		phase = "Closing"
		r.root.Visible = true
		r.closeA:Play()
		r.closeB:Play()
	elseif phase == "Opening" then
		-- Coalesce: fold the reveal back into a fresh close — the same
		-- panels, from wherever they are. A second rig never exists.
		r.openA:Cancel()
		r.openB:Cancel()
		phase = "Closing"
		r.closeA:Play()
		r.closeB:Play()
	end
	-- phase == "Closing": nothing to start — the queued during joins the
	-- covered window already in flight.
end

-- Full release: connections, ticker handler, tweens, instances. The next
-- Play rebuilds from scratch. Pending callbacks flush (instantly), never
-- silently dropped.
function SlashTransition.Destroy()
	local r = rig
	if r then
		teardown(r, true)
	end
end

return SlashTransition
