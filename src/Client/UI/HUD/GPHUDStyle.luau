--!strict
-- GPHUDStyle — the GIRLY POP pass for the HUD (theme.LayoutKit == "GP").
--
-- HUD widgets are COMPONENTS, not screens: they must never fork _Build. Every
-- widget here keeps its structure and its classic paint exactly as authored and
-- appends ONE call per surface to its _Style — the widget's own declared repaint
-- path (HUDWidgetBase:ApplyTheme -> _Style, re-run on every live theme swap).
-- This module is that call. Nothing in it builds a widget; it only repaints one.
--
-- WHY THE HUD NEEDS A PASS AT ALL WHEN theme.Arcade IS ALREADY PASTEL:
-- GirlyPop remaps the arcade colour block (NearBlack reads LIGHT, RulerTrack is
-- pale rose, Gold is butter), so the widgets' existing token reads already land
-- on the right hues. What the token reads CANNOT reach are the three things the
-- arcade grammar hard-codes in shape rather than colour:
--   * SQUARE corners — UIChrome.Radius returns 0 for the Arcade family at every
--     intent but Pill, so a pastel HUD would still be a row of hard boxes;
--   * OPAQUE fills — UIStyler.Frame is born at BackgroundTransparency 0, which
--     over live gameplay cuts holes in the world. This pack's HUD must stay
--     LIGHT: every plate here sits translucent so the scene reads through it;
--   * NO DEPTH — the pack's signature is the soft HUE-MATCHED shadow, and the
--     arcade language has none (its depth is the 3px black border).
--
-- REVERSIBILITY IS A HARD REQUIREMENT. Widgets never rebuild on a style swap,
-- so every mutation this module makes must undo itself the moment the theme is
-- not GP: corners go back through UIChrome.Radius (the same policy call _Build
-- used), fills go back to the caller's declared rest transparency, strokes are
-- restored from a fresh policy reference, shadows are RELEASED (not merely
-- destroyed — the budget counter only falls on Release) and the glaze/scallop
-- chrome is deleted. Classic therefore stays pixel-identical after any number
-- of swaps in either direction.
--
-- SHADOW BUDGET (engine guidance <=100 live UIShadows): the HUD is PERSISTENT,
-- so it is the one surface that can quietly hold the budget hostage. Shadows
-- are spent only on the plates that carry the pack — meters, chips, slots,
-- plates — and never on pooled high-churn rows (killfeed, damage floaters,
-- score floaters), which would multiply by their pool size for no read. Every
-- handle lands in the owning widget's HUDWidgetBase sink and is released in
-- Destroy as well as on a swap away from GP.
--
-- LAW 1 (no pure black / no pure white) is why the halo below exists. GP's
-- Chrome sets TextOutline = false and TextGlowTransparency = 1, i.e. boxless
-- HUD text (zone banner, damage numbers, waypoint labels, the objective ticker)
-- would carry NO emphasis at all and vanish over a bright scene. The pack's own
-- answer is used instead of the banned black outline: a Contextual stroke in a
-- DEEPENED TINT OF THE LETTER'S OWN COLOUR — gold digits get a caramel halo,
-- ink copy gets a plum one. It reuses the "TextGlow" instance UIChrome.TextOutline
-- already manages, so no label ever carries two UIStrokes.

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)

local GPHUDStyle = {}

-- ---- the HUD's transparency ladder -------------------------------------

-- Chrome plates (minimap, compass tape, timer box, ammo block): the world must
-- read through them. Lower than this and the HUD becomes a wall; higher and ink
-- copy stops clearing its 4.5:1 over a bright scene.
GPHUDStyle.Plate = 0.16
-- Meters must read at a glance in peripheral vision, so they sit denser.
GPHUDStyle.Meter = 0.1
-- Interactive chips (ability slots, buff chips, key caps, the score chip).
GPHUDStyle.Chip = 0.1
-- Feed rows are the lightest thing on screen: they stack, and a stack of plates
-- is a panel by another name.
GPHUDStyle.Row = 0.26

local HALO_TRANSPARENCY = 0.12
local HALO_THICKNESS = 2
local HALO_DEEPEN = 0.55

local SHADOW_NAME = "GPHUDShadow"
local PETAL_NAME = "GPPetal"
local GLAZE_NAME = "GlazeSheen"
local SCALLOP_NAME = "ScallopBottom"

-- Weak keys: a destroyed host must never keep its handle (or this table) alive.
local shadowHandles: { [GuiObject]: any } = (setmetatable({}, { __mode = "k" }) :: any)

-- ---- helpers -----------------------------------------------------------

function GPHUDStyle.Active(theme: Types.UITheme): boolean
	return theme.LayoutKit == "GP"
end

-- The fill a hue-matched effect keys off. Mirrors GPLayoutKit's own rule: a
-- transparent plate has no BackgroundColor3 worth deepening, and a tinted image
-- carries its colour on ImageColor3 instead.
local function hostFill(theme: Types.UITheme, host: GuiObject): Color3
	if host.BackgroundTransparency < 1 then
		return host.BackgroundColor3
	end
	if host:IsA("ImageLabel") or host:IsA("ImageButton") then
		return (host :: any).ImageColor3
	end
	return theme.Colors.Surface
end

-- One UICorner per instance, ever. A petal set writes the four per-corner radii
-- and MUST NOT also carry CornerRadius (documented-undefined engine behaviour),
-- so switching between the two shapes replaces the instance rather than editing
-- it. Named so the swap back can recognise what it is looking at.
local function clearPetal(host: GuiObject)
	local petal = host:FindFirstChild(PETAL_NAME)
	if petal then
		petal:Destroy()
	end
end

local function uniformCorner(host: GuiObject): UICorner
	local corner = host:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		;(corner :: UICorner).Parent = host
	end
	return corner :: UICorner
end

-- ---- text --------------------------------------------------------------

-- The pack's answer to a black outline: a soft halo in a DEEPENED TINT of the
-- label's own colour. A DROP-IN for UIChrome.TextOutline — same arguments, same
-- meaning (`transparency` is the emphasis strength a dimmed or fading label
-- passes), and it delegates first, so on every non-GP pack this call is exactly
-- the outline the widget asked for. Under GP it then repaints the glow stroke
-- UIChrome.TextOutline already owns, so a label never ends up carrying two
-- UIStrokes (only the first would render).
function GPHUDStyle.Halo(theme: Types.UITheme, label: Instance?, transparency: number?)
	if not label then
		return
	end
	local dim = transparency or 0
	UIChrome.TextOutline(label, dim)
	if not GPHUDStyle.Active(theme) then
		return
	end
	local glow = label:FindFirstChild("TextGlow") :: UIStroke?
	if not glow then
		return
	end
	local ink = (label :: any).TextColor3 :: Color3
	glow.Color = ink:Lerp(theme.Colors.TextPrimary, HALO_DEEPEN):Lerp(theme.Colors.Stroke, 0.15)
	glow.Thickness = HALO_THICKNESS
	-- A dimmed label's halo dims with it, or a "completed, greyed in place" row
	-- would keep a crisp rim and read as still active.
	glow.Transparency = HALO_TRANSPARENCY + (1 - HALO_TRANSPARENCY) * dim
end

-- THE RULE FOR BOXLESS COPY. The halo deepens a label's own colour, which lifts
-- a LIGHT letter off a bright sky and off a dark alley alike — and only doubles
-- a DARK letter's problem, since a dark rim on dark ink over a night scene is
-- nothing at all. So anywhere the HUD puts copy straight onto the world with no
-- tile under it, this pack's warm plum ink is swapped for its warm cream. Copy
-- that sits ON a tile keeps the ink: there it is the most legible thing there is.
function GPHUDStyle.SkyInk(theme: Types.UITheme, classic: Color3): Color3
	return if GPHUDStyle.Active(theme) then theme.Colors.Background else classic
end

-- A label that drives its OWN Contextual UIStroke — the round timer's panic
-- glow is the only one on the HUD — must not also carry the emphasis glow. The
-- engine renders ONE UIStroke per object, and the emphasis one is created first
-- (inside UIChrome.Text), so it would win and the §5.3 panic would silently
-- stop showing. GP-only on purpose: the same collision exists on the other glow
-- styles today, and quietly changing what they render is not this pass's call.
function GPHUDStyle.YieldGlow(theme: Types.UITheme, label: Instance?)
	if not label or not GPHUDStyle.Active(theme) then
		return
	end
	local glow = label:FindFirstChild("TextGlow")
	if glow then
		glow:Destroy()
	end
end

-- Copy swap for the ONE case where a caption is a fixed string the paint path
-- owns. GP never shouts (law 5), every other pack does — so the widget hands
-- both spellings in and the theme picks. No data, config or callback is touched.
function GPHUDStyle.Copy(theme: Types.UITheme, girly: string, classic: string): string
	return if GPHUDStyle.Active(theme) then girly else classic
end

-- ---- shadows -----------------------------------------------------------

-- Ensure-or-release, idempotent across any number of _Style runs. Under GP the
-- shadow is created once and only ever RETINTED afterwards; off GP the handle
-- is Released so the budget counter actually falls (destroying the instance
-- alone would leave the count high forever).
function GPHUDStyle.Shadow(theme: Types.UITheme, host: GuiObject, intent: string?, tint: Color3?, sink: { any }?)
	local handle = shadowHandles[host]
	if not GPHUDStyle.Active(theme) then
		if handle then
			shadowHandles[host] = nil
			if sink then
				local index = table.find(sink, handle)
				if index then
					table.remove(sink, index)
				end
			end
			handle:Release()
		end
		return
	end
	local fill = tint or hostFill(theme, host)
	if handle and handle.Instance and handle.Instance.Parent == host then
		handle.Instance.Color = GPLayoutKit.Deepen(theme, fill, 1)
		return
	end
	local fresh = GPLayoutKit.Shadow(theme, host, intent or "sm", sink, fill)
	fresh.Instance.Name = SHADOW_NAME
	shadowHandles[host] = fresh
end

-- Hand a host's shadow back BEFORE destroying it. Widgets whose surfaces churn
-- at runtime (a buff expiring, a loadout swap rebuilding the ability row) would
-- otherwise hold budget for instances that no longer exist — the counter falls
-- on Release, never on Destroy.
function GPHUDStyle.Drop(host: GuiObject?, sink: { any }?)
	if not host then
		return
	end
	local handle = shadowHandles[host]
	if not handle then
		return
	end
	shadowHandles[host] = nil
	if sink then
		local index = table.find(sink, handle)
		if index then
			table.remove(sink, index)
		end
	end
	handle:Release()
end

-- ---- the one surface call ----------------------------------------------

export type SurfaceOpts = {
	-- fill
	fill: Color3?, -- GP background colour; omit to keep the widget's own
	restFill: Color3?, -- what non-GP restores to (required alongside `fill`)
	transparency: number?, -- GP background transparency
	restTransparency: number?, -- what non-GP restores to (default 0)
	keepTransparency: boolean?, -- never touch the fill's transparency
	-- shape
	radius: number?, -- GP uniform corner radius
	petal: number?, -- GP petal index; alternates by parity, wins over radius
	cornerIntent: UIChrome.CornerIntent?, -- the intent _Build used, for the restore
	keepCorner: boolean?, -- never touch corners
	-- rim
	stroke: boolean?, -- manage the host's UIStroke
	strokeIntent: UIChrome.StrokeIntent?, -- the intent _Build used, for the restore
	strokeTint: Color3?, -- GP hue source (defaults to the host's own fill)
	strokeKeepColor: boolean?, -- the widget repaints the colour itself
	strokeThickness: number?, -- GP override; the pack's 2px eats a 2px-wide mark
	-- depth + gloss
	shadow: string?, -- "sm" | "md" | "lg" | "glow"
	shadowTint: Color3?,
	sink: { any }?,
	glaze: boolean?,
	scallop: boolean?,
}

-- Repaint ONE surface into (or out of) the pack. Every branch is symmetrical:
-- whatever the GP side sets, the classic side puts back.
function GPHUDStyle.Surface(theme: Types.UITheme, host: GuiObject?, opts: SurfaceOpts)
	if not host then
		return
	end
	local on = GPHUDStyle.Active(theme)

	-- The arcade colour block is already remapped to pastels by the pack, so a
	-- fill override is the exception, not the rule: it exists for the surfaces
	-- whose CONTRAST PAIRING has to change (butter-on-value carrying ink digits
	-- where the arcade carried gold digits on slate).
	if opts.fill then
		host.BackgroundColor3 = if on then opts.fill else (opts.restFill or opts.fill)
	end

	if not opts.keepTransparency then
		host.BackgroundTransparency = if on then (opts.transparency or GPHUDStyle.Plate) else (opts.restTransparency or 0)
	end

	if not opts.keepCorner then
		if on and opts.petal then
			local corner = GPLayoutKit.Petal(theme, host, opts.petal)
			corner.Name = PETAL_NAME
		else
			clearPetal(host)
			local radius = if on then (opts.radius or theme.Radii.Medium) else UIChrome.Radius("Arcade", opts.cornerIntent)
			uniformCorner(host).CornerRadius = UDim.new(0, radius)
		end
	end

	if opts.stroke then
		local stroke = host:FindFirstChildOfClass("UIStroke")
		if on then
			if not stroke then
				-- Named so the swap back can tell "a rim this pass invented"
				-- from "the rim _Build made": the first must be DELETED (classic
				-- never had one, and restoring a 3px black policy stroke onto a
				-- 2px crosshair bar would draw a black box), the second restored.
				stroke = UIStyler.Stroke(theme.Colors.Stroke, 2, 0.35)
				;(stroke :: UIStroke).Name = "GPRim"
				;(stroke :: UIStroke).Parent = host
			end
			local chrome = theme.Chrome
			local rim = stroke :: UIStroke
			-- Hue-matched: a matcha meter gets a matcha rim, not the pack's one
			-- rose default. THIS is the rule that keeps the HUD from reading as
			-- a pink wash (pack law 2, applied to the rim as well as the shade).
			-- strokeKeepColor opts a rim out in BOTH directions — a semantic ring
			-- (buff green/debuff red, the XP selection rose) means something, and
			-- deepening it to match its plate would erase that meaning.
			if not opts.strokeKeepColor then
				rim.Color = GPLayoutKit.Deepen(theme, opts.strokeTint or hostFill(theme, host), 1)
			end
			rim.Thickness = opts.strokeThickness or (chrome and chrome.StrokeThickness) or 2
			rim.Transparency = (chrome and chrome.StrokeTransparency) or 0.35
			rim.LineJoinMode = Enum.LineJoinMode.Round
		elseif stroke and stroke.Name == "GPRim" then
			stroke:Destroy()
		elseif stroke then
			-- Restore from a fresh POLICY reference rather than a remembered
			-- snapshot: that is the same call _Build made, so it resolves to
			-- whatever the now-active style would have built in the first place.
			local reference = UIChrome.Stroke(theme, "Arcade", opts.strokeIntent)
			if not opts.strokeKeepColor then
				stroke.Color = reference.Color
			end
			stroke.Thickness = reference.Thickness
			stroke.Transparency = reference.Transparency
			stroke.LineJoinMode = Enum.LineJoinMode.Round
			reference:Destroy()
		end
	end

	-- Glaze goes on AFTER the corner (the wash clones the host's UICorner to
	-- match the silhouette — reversed, it would square off a petal).
	local glaze = host:FindFirstChild(GLAZE_NAME)
	if opts.glaze and on then
		if not glaze then
			local wash = GPLayoutKit.GlazeSheen(theme, host)
			-- Below the host's content, which every HUD widget authors at
			-- ZIndex >= 2. GlazeSheen defaults to host + 1, which would put the
			-- sheen ON the digits it is meant to flatter. Sibling ZIndex ordering
			-- is hierarchical, so lowering the wash carries its arc down with it.
			wash.ZIndex = host.ZIndex
		end
	elseif glaze then
		glaze:Destroy()
	end

	local scallop = host:FindFirstChild(SCALLOP_NAME)
	if opts.scallop and on then
		if not scallop then
			GPLayoutKit.Scallop(theme, host, "Bottom", hostFill(theme, host))
		elseif scallop:IsA("ImageLabel") then
			scallop.ImageColor3 = hostFill(theme, host)
		end
	elseif scallop then
		scallop:Destroy()
	end

	if opts.shadow then
		GPHUDStyle.Shadow(theme, host, opts.shadow, opts.shadowTint, opts.sink)
	end
end

return GPHUDStyle
