--!strict
-- Style/Capabilities — feature detection for Roblox native UI Styling, probed
-- against the RUNNING engine, never assumed from documentation or training
-- data. Verified in this place (2026-07-26, live probes):
--
--   * StyleSheet / StyleRule / StyleLink / StyleDerive: classes EXIST, full
--     method surface present (SetProperties / SetPropertyTransitions /
--     Priority / Selector all accept writes) — but runtime APPLICATION is
--     INERT here: a linked ".Tag { BackgroundColor3 }" rule left a frame at
--     its authored color on screen (visual proof), pseudo-instance rules
--     created no modifier children, and property reads never reflect rules.
--   * The Selector property accepts ANY string unvalidated (":Pressed" — a
--     GuiState that does not exist — round-trips fine), so acceptance is NOT
--     support. Only render-time evidence counts, hence the probe below.
--   * Enum.GuiState = Idle | Hover | Press | NonInteractable. There is no
--     :Focus pseudo-state; gamepad focus styling stays a Luau concern.
--   * UIShadow RENDERS today (hard offset drop shadows + zero-offset glows,
--     both visually confirmed). Spread is a UDim2 in this build, not the
--     number some specs claim. ZIndex defaults to -1 (below parent).
--   * UICorner per-corner radii (TopLeftRadius et al) RENDER today.
--
-- Because "classes exist" and "styling applies" are different facts, the
-- ACTIVE flag resolves asynchronously from a live rig: a rule styles a probe
-- frame's Size, and AbsoluteSize — which reflects the RENDERED layout even
-- though property reads do not — is the witness. Transitions are probed the
-- same way (mid-flight AbsoluteSize sample on a tag flip).
--
-- Everything downstream treats styling as progressive enhancement: the
-- imperative UIChrome/ApplyTheme path is authoritative until StylingActive
-- resolves true in some future engine build — at which point sheets built by
-- SheetBuilder begin to matter without a code change here.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local UISignal = require(script.Parent.Parent:WaitForChild("UISignal"))

local Capabilities = {}

-- ---- synchronous facts (class existence) -------------------------------

local function classExists(className: string): boolean
	local ok, inst = pcall(Instance.new, className)
	if ok and inst then
		(inst :: Instance):Destroy()
		return true
	end
	return false
end

Capabilities.SheetClassesAvailable = classExists("StyleSheet")
	and classExists("StyleRule")
	and classExists("StyleLink")
	and classExists("StyleDerive")

Capabilities.ShadowAvailable = classExists("UIShadow")

Capabilities.PerCornerRadii = (function(): boolean
	local ok = pcall(function()
		local corner = Instance.new("UICorner")
		;(corner :: any).TopLeftRadius = UDim.new(0, 1)
		corner:Destroy()
	end)
	return ok
end)()

-- ---- asynchronous facts (does styling APPLY?) --------------------------

-- false until proven; consumers must tolerate a late flip to true.
Capabilities.StylingActive = false
Capabilities.TransitionsActive = false
Capabilities.Resolved = false
Capabilities.OnResolved = UISignal.new()

local PROBE_TAG = "StyleCapProbe"
local PROBE_SLOW_TAG = "StyleCapProbeSlow"

-- One hidden rig answers both questions. Runs once; ~0.6s wall clock.
function Capabilities.Detect()
	if Capabilities.Resolved then
		return
	end
	if not Capabilities.SheetClassesAvailable then
		Capabilities.Resolved = true
		Capabilities.OnResolved:Fire(false, false)
		return
	end
	task.spawn(function()
		local player = Players.LocalPlayer
		local pg = player and player:FindFirstChildOfClass("PlayerGui")
		if not pg then
			Capabilities.Resolved = true
			Capabilities.OnResolved:Fire(false, false)
			return
		end

		local gui = Instance.new("ScreenGui")
		gui.Name = "StyleCapabilityProbe"
		gui.DisplayOrder = -1000
		gui.Enabled = true

		local sheet = Instance.new("StyleSheet")
		sheet.Parent = gui
		local link = Instance.new("StyleLink")
		link.StyleSheet = sheet
		link.Parent = gui

		local sized = Instance.new("StyleRule")
		sized.Selector = "." .. PROBE_TAG
		sized:SetProperties({ Size = UDim2.fromOffset(7, 7) })
		sized.Parent = sheet

		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.fromOffset(1, 1)
		frame.Position = UDim2.fromOffset(-50, -50)
		CollectionService:AddTag(frame, PROBE_TAG)
		frame.Parent = gui
		gui.Parent = pg

		task.wait(0.2)
		-- AbsoluteSize reflects the rendered layout; property reads do not.
		local active = math.abs(frame.AbsoluteSize.X - 7) < 0.5

		local transitions = false
		if active then
			local slow = Instance.new("StyleRule")
			slow.Selector = "." .. PROBE_SLOW_TAG
			slow.Priority = 10
			slow:SetProperties({ Size = UDim2.fromOffset(100, 100) })
			pcall(function()
				slow:SetPropertyTransitions({ Size = TweenInfo.new(0.4, Enum.EasingStyle.Linear) })
			end)
			slow.Parent = sheet
			CollectionService:AddTag(frame, PROBE_SLOW_TAG)
			task.wait(0.15)
			local mid = frame.AbsoluteSize.X
			-- Mid-flight between 7 and 100 = the tween is really animating.
			transitions = mid > 12 and mid < 95
			task.wait(0.4)
		end

		gui:Destroy()
		Capabilities.StylingActive = active
		Capabilities.TransitionsActive = transitions
		Capabilities.Resolved = true
		Capabilities.OnResolved:Fire(active, transitions)
	end)
end

-- ---- UIShadow budget ---------------------------------------------------
-- Engine guidance: keep on-screen UIShadows at or below ~100. We warn at 80.
-- Pooled elements carrying glows must DISABLE on release, not destroy — a
-- disabled shadow keeps its budget slot but costs no render; the counter
-- tracks *live enabled* shadows via the handle contract below.

local WARN_THRESHOLD = 80
local liveShadows = 0
local warned = false

export type ShadowHandle = {
	SetEnabled: (self: ShadowHandle, enabled: boolean) -> (),
	Release: (self: ShadowHandle) -> (),
	Instance: UIShadow,
}

-- Every UIShadow the framework creates passes through here so the budget is
-- one number, not a guess. `Release` is for actual destruction; pooled users
-- call SetEnabled(false) and keep the handle.
function Capabilities.RegisterShadow(shadow: UIShadow): ShadowHandle
	local enabled = shadow.Enabled
	if enabled then
		liveShadows += 1
	end
	if liveShadows > WARN_THRESHOLD and not warned then
		warned = true
		warn(("[StyleCapabilities] live UIShadow count crossed %d (engine guidance <=100). Audit glow usage."):format(WARN_THRESHOLD))
	end
	local handle = {} :: any
	handle.Instance = shadow
	function handle.SetEnabled(_, on: boolean)
		if on == enabled then
			return
		end
		enabled = on
		shadow.Enabled = on
		liveShadows += on and 1 or -1
	end
	function handle.Release(_)
		if enabled then
			liveShadows -= 1
			enabled = false
		end
		shadow:Destroy()
	end
	return handle :: ShadowHandle
end

function Capabilities.LiveShadowCount(): number
	return liveShadows
end

return Capabilities
