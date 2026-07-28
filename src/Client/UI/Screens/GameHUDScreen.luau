--!strict
-- Pottery Clash arcade HUD (UI_DESIGN_DOCUMENT.md §7.2), authored in fixed px
-- at the 1650×1020 baseline (UIScreenBase attaches the baseline UIScale):
--
--   * LEFT EDGE   — rail of 116×116 invisible icon buttons at x=16, 126px
--                   pitch (Store / Index / Settings), each captioned by a
--                   bottom text strip; the whole cell is one invisible button
--                   (doc §11.6 whole-cell hit targets) with big-button juice
--                   on the ART child (doc §5.2 — layout never reflows).
--   * TOP CENTRE  — gold status line at y=14 ("WAVE %d") and the FIXED
--                   220×60 round-timer box at y=118. Final 10s = the §5.3
--                   panic: TextSize oscillates 52→66 on sin(t·10), the colour
--                   flashes red toward near-white, the glow stroke thickens
--                   4→7 — the box itself NEVER resizes (pulsing never reflows).
--   * TOP RIGHT   — 190×52 action buttons at 202px pitch (SHOP green, DAILY
--                   orange), plus the "hud.topRight" / "nav.shop" highlight
--                   anchors the tutorial points at.
--   * BOTTOM LEFT — Cash 220×56 + Bux 180×56 currency pills at y=−14
--                   (doc §8 recipe via UICurrencyPillComponent), with the
--                   objectives list (arcade slate rows) stacked above them.
--
-- Toasts + the banner live in a SECOND ScreenGui ("GameHUDOverlays") at
-- DisplayOrder 60: doc §7.3 puts toasts/reveals at 60–65 so they render above
-- every panel — and stay visible even when lobby chrome is hidden.
--
-- Public API preserved: new / Rebuild / PushBanner / PushToast / Update /
-- SetElementRegion (no-op) / ApplyLayout ({scaleOverride}).

local RunService = game:GetService("RunService")

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScaleHelper = require(script.Parent.Parent.UIScaleHelper)
local UIStyleEnforcer = require(script.Parent.Parent.UIStyleEnforcer)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local HUDConfig = require(script.Parent.Parent.Config.HUDConfig)
local UIAssets = require(script.Parent.Parent.Config.UIAssets)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UICurrencyPillComponent = require(script.Parent.Parent.Components.UICurrencyPillComponent)
local UIToastComponent = require(script.Parent.Parent.Components.UIToastComponent)
local UINotificationComponent = require(script.Parent.Parent.Components.UINotificationComponent)
local ACLayoutKit = require(script.Parent.Parent.Framework.ACLayoutKit)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- Left rail geometry (doc §7.2: 116×116 cells at x=16, 126px pitch).
local RAIL_X = 16
local RAIL_CELL = 116
local RAIL_PITCH = 126
local RAIL_Y0 = 200
local RAIL_CAPTION_H = 22

-- Top-right action row (doc §7.2: 190×52 buttons at 202px pitch).
local ACTION_W, ACTION_H = 190, 52
local ACTION_PITCH = 202

-- Round timer (doc §5.3): fixed box, FredokaOne 48 gold; panic numbers.
local TIMER_TEXT_SIZE = 48
local PANIC_WINDOW = 10
local PANIC_RED = Color3.fromRGB(255, 70, 55)
local PANIC_WHITE = Color3.fromRGB(255, 245, 240)

local GameHUDScreen = setmetatable({}, { __index = UIScreenBase })
GameHUDScreen.__index = GameHUDScreen

-- ---- lifecycle --------------------------------------------------------

function GameHUDScreen.new()
	local self = UIScreenBase.new("GameHUDScreen", 2)
	self._values = table.clone(HUDConfig.DefaultValues)
	self._objectives = {} :: { GuiObject }
	self._toasts = {} :: { any }
	self._components = {} :: { any } -- buttons + pills, destroyed on Rebuild
	self._pills = {} :: { [string]: any } -- Update lands on ids "Cash"/"Bux"
	self._banner = nil :: any
	self._statusLabel = nil :: TextLabel? -- Update lands on id "wave"
	self._timerLabel = nil :: TextLabel? -- Update lands on id "timer"
	self._timerGlow = nil :: UIStroke?
	self._timerBox = nil :: Frame?
	self._timerFx = nil :: RBXScriptConnection?
	self._overlayGui = nil :: ScreenGui?
	self._overlayScaleCleanup = nil :: (() -> ())?
	-- GP shadow sink. A destroyed GuiObject does NOT decrement the live-UIShadow
	-- budget — only a released handle does — so every soft shadow the pastel HUD
	-- casts is handed back here on rebuild and on teardown.
	self._gpShadows = {} :: { any }
	-- Round-timer colour pairing, resolved per pack in _BuildGPLayout. nil on
	-- every other layout kit, where _StartTimerFx falls back to the constants.
	self._restInk = nil :: Color3?
	self._restGlow = nil :: Color3?
	self._panicHot = nil :: Color3?
	self._panicCool = nil :: Color3?
	-- Persisted so ApplyLayout can keep tuning the HUD scale across rebuilds.
	self._scaleOverride = nil :: number?
	return setmetatable(self, GameHUDScreen)
end

-- Tear down and rebuild HUD content (used on a pack change at runtime).
function GameHUDScreen:Rebuild()
	if not self._built then
		return
	end
	self:_StopTimerFx()
	for _, toast in self._toasts do
		toast:Destroy()
	end
	self._toasts = {}
	if self._banner then
		self._banner:Destroy()
		self._banner = nil
	end
	for _, component in self._components do
		component:Destroy()
	end
	self._components = {}
	self._pills = {}
	self._objectives = {}
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	if self._overlayScaleCleanup then
		self._overlayScaleCleanup()
		self._overlayScaleCleanup = nil
	end
	if self._overlayGui then
		self._overlayGui:Destroy()
		self._overlayGui = nil
	end
	-- Only the content wrapper is destroyed — the baseline UIScale that
	-- UIScreenBase attached to Root must survive a rebuild.
	if self._content then
		self._content:Destroy()
		self._content = nil
	end
	self:_BuildContent()
	self:_RefreshValues()
	if self._visible then
		self:_StartTimerFx()
	end
end

-- ---- build ------------------------------------------------------------

-- One 116×116 rail cell: a full-size INVISIBLE button (whole-cell hit target,
-- doc §11.6) over a non-interactive art frame + bottom caption strip. The
-- §5.2 big-button juice (1.12× + 30° tilt hover, squash/elastic click) is
-- applied to the ART child so the rail never reflows.
function GameHUDScreen:_RailCell(parent: Instance, index: number, caption: string, onClick: () -> ()): (TextButton, Frame)
	local theme = self:GetTheme()

	local cell = Instance.new("TextButton")
	cell.Name = caption .. "Cell"
	cell.BackgroundTransparency = 1
	cell.BorderSizePixel = 0
	cell.Text = ""
	cell.AutoButtonColor = false
	cell.Size = UDim2.fromOffset(RAIL_CELL, RAIL_CELL)
	cell.Position = UDim2.fromOffset(RAIL_X, RAIL_Y0 + (index - 1) * RAIL_PITCH)
	cell.Parent = parent

	local art = UIStyler.Frame("Art")
	art.BackgroundTransparency = 1
	art.Size = UDim2.new(1, 0, 0, RAIL_CELL - RAIL_CAPTION_H - 4)
	art.Parent = cell

	local strip = UIChrome.Text("Caption", 15, WHITE)
	strip.Text = string.upper(caption)
	strip.Size = UDim2.new(1, 0, 0, RAIL_CAPTION_H)
	strip.Position = UDim2.new(0, 0, 1, -RAIL_CAPTION_H)
	strip.Parent = cell

	cell.Activated:Connect(onClick)
	UIChrome.AnimateBig(theme, cell, art)
	return cell, art
end

function GameHUDScreen:_BuildContent()
	-- The round-timer colour pairing is a GP-only override (_BuildGPLayout sets
	-- all four; _StartTimerFx falls back to the doc §5.3 constants when they are
	-- nil). Clearing them HERE, ahead of every branch, is what stops a swap AWAY
	-- from GP leaving the classic/AC timer breathing in this pack's plum ink and
	-- flashing plum-coral instead of red: Rebuild does not go through
	-- _OnTeardown, so nothing else on that path would ever put them back.
	self._restInk = nil
	self._restGlow = nil
	self._panicHot = nil
	self._panicCool = nil
	-- GP layout language: the pastel studio HUD — everything floats over the
	-- world on translucent glazed tiles with hue-matched shadows, nothing
	-- opaque. See _BuildGPLayout below.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
	if self:LayoutKit() == "AC" then
		self:_BuildACLayout()
		return
	end
	local theme = self:GetTheme()

	-- All HUD chrome lives in this wrapper so (a) Rebuild can drop it without
	-- touching the baseline UIScale on Root, and (b) the pack/preset scale is
	-- an EXTRA UIScale on the wrapper, composed multiplicatively with the
	-- baseline scale instead of fighting it.
	local content = UIStyler.Frame("Content")
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = self.Root
	self._content = content

	local packScale = Instance.new("UIScale")
	packScale.Name = "PackScale"
	packScale.Parent = content
	self._packScale = packScale

	-- ---- LEFT EDGE: icon rail (Store / Index / Settings) --------------

	local _, storeArt = self:_RailCell(content, 1, "Store", function()
		self.ScreenController:ShowScreen("store")
	end)
	local cart = UIAssets.Icon(storeArt, "Cart", 76)
	cart.AnchorPoint = Vector2.new(0.5, 0.5)
	cart.Position = UDim2.fromScale(0.5, 0.5)

	local _, indexArt = self:_RailCell(content, 2, "Index", function()
		self.ScreenController:ShowScreen("index")
	end)
	local star = UIAssets.Icon(indexArt, "Star", 76)
	star.AnchorPoint = Vector2.new(0.5, 0.5)
	star.Position = UDim2.fromScale(0.5, 0.5)

	local settingsCell, settingsArt = self:_RailCell(content, 3, "Settings", function()
		self.ScreenController:ShowScreen("settings")
	end)
	local gear = UIAssets.Icon(settingsArt, "Settings", 76)
	gear.AnchorPoint = Vector2.new(0.5, 0.5)
	gear.Position = UDim2.fromScale(0.5, 0.5)

	-- The tutorial's theme step points at the Settings rail button.
	self.ScreenController:RegisterHighlightTarget("nav.theme", settingsCell)

	-- ---- TOP CENTRE: status line + round timer ------------------------

	-- Amber status line (doc §3.2: sunburst gold = amber status lines).
	local status = UIChrome.Text("Status", 24, theme.Arcade.SunburstGold)
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.new(0.5, 0, 0, 14)
	status.Size = UDim2.fromOffset(500, 30)
	status.Parent = content
	self._statusLabel = status

	-- Round timer: FIXED 220×60 arcade panel (slate + 3px black stroke +
	-- glass sheen). The pulsing lives on TextSize/colour/glow only.
	local timerBox = UIChrome.Panel(theme, "Arcade", "RoundTimer")
	timerBox.AnchorPoint = Vector2.new(0.5, 0)
	timerBox.Position = UDim2.new(0.5, 0, 0, 118)
	timerBox.Size = UDim2.fromOffset(220, 60)
	timerBox.Parent = content
	self._timerBox = timerBox

	local timerValue = UIChrome.Text("Value", TIMER_TEXT_SIZE, theme.Arcade.Gold)
	timerValue.Size = UDim2.fromScale(1, 1)
	timerValue.Parent = timerBox
	self._timerLabel = timerValue

	-- The breathing/panic glow: a Contextual stroke around the digits, on
	-- top of the enforced black TextStroke outline.
	local glow = Instance.new("UIStroke")
	glow.Name = "Glow"
	glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	glow.LineJoinMode = Enum.LineJoinMode.Round
	glow.Color = theme.Arcade.Gold
	glow.Thickness = 3
	glow.Transparency = 0.45
	glow.Parent = timerValue
	self._timerGlow = glow

	-- ---- TOP RIGHT: action row (SHOP / DAILY) -------------------------

	local actions = UIStyler.Frame("TopRightActions")
	actions.BackgroundTransparency = 1
	actions.AnchorPoint = Vector2.new(1, 0)
	actions.Position = UDim2.new(1, -16, 0, 14)
	actions.Size = UDim2.fromOffset(ACTION_PITCH + ACTION_W, ACTION_H)
	actions.Parent = content

	local shopButton = UIButtonComponent.new()
	shopButton:Create(actions, {
		text = "SHOP",
		variant = "Green",
		size = UDim2.fromOffset(ACTION_W, ACTION_H),
		position = UDim2.fromOffset(ACTION_PITCH, 0),
		onClick = function()
			local shopScreen = self.ScreenController:GetScreen("shop")
			self.ScreenController:ToggleScreen("shop", { balances = shopScreen and shopScreen._balances })
		end,
	})
	table.insert(self._components, shopButton)

	local dailyButton = UIButtonComponent.new()
	dailyButton:Create(actions, {
		text = "DAILY",
		variant = "Orange",
		size = UDim2.fromOffset(ACTION_W, ACTION_H),
		position = UDim2.fromOffset(0, 0),
		onClick = function()
			self:PushBanner({
				title = "DAILY REWARD",
				body = "Come back tomorrow for more!",
				variant = "Info",
			})
		end,
	})
	table.insert(self._components, dailyButton)

	-- Highlight anchors: the tutorial's welcome step points at the action
	-- row, its shop step at the SHOP button itself.
	self.ScreenController:RegisterHighlightTarget("hud.topRight", actions)
	self.ScreenController:RegisterHighlightTarget("nav.shop", shopButton.Root)

	-- ---- BOTTOM LEFT: currency pills + objectives ---------------------

	local pillRow = UIStyler.Frame("CurrencyPills")
	pillRow.BackgroundTransparency = 1
	pillRow.AnchorPoint = Vector2.new(0, 1)
	pillRow.Position = UDim2.new(0, 16, 1, -14)
	pillRow.Size = UDim2.fromOffset(220 + 10 + 180, 56)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = pillRow
	pillRow.Parent = content

	local cashPill = UICurrencyPillComponent.new()
	cashPill:Create(pillRow, {
		currencyId = "Cash",
		value = self._values.Cash,
		size = UDim2.fromOffset(220, 56),
		layoutOrder = 1,
	})
	self._pills.Cash = cashPill
	table.insert(self._components, cashPill)

	local buxPill = UICurrencyPillComponent.new()
	buxPill:Create(pillRow, {
		currencyId = "Bux",
		value = self._values.Bux,
		size = UDim2.fromOffset(180, 56),
		layoutOrder = 2,
	})
	self._pills.Bux = buxPill
	table.insert(self._components, buxPill)

	-- Objectives stack directly above the pills, growing upward.
	local objectives = UIStyler.Frame("Objectives")
	objectives.BackgroundTransparency = 1
	objectives.AnchorPoint = Vector2.new(0, 1)
	objectives.Position = UDim2.new(0, 16, 1, -(14 + 56 + 14))
	objectives.Size = UDim2.fromOffset(320, 0)
	objectives.AutomaticSize = Enum.AutomaticSize.Y
	UIStyler.ListLayout({
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = objectives
	objectives.Parent = content
	self._objectivesHolder = objectives

	-- ---- overlays (second ScreenGui) ----------------------------------
	self:_BuildOverlays()

	self:_ApplyPackScale()
end

-- AC mission HUD (theme.LayoutKit == "AC"): the machine overlay. No opaque
-- Shell page — data floats over the live world with hairlines only. A thin
-- transparent status strip along the top edge carries objectives (far left,
-- dim mono rows), the round timer (centre — the same fields _StartTimerFx
-- drives, so the panic flash keeps working), and the currency pills (right,
-- same component keys so Update lands unchanged). Corner L-brackets frame
-- the whole screen; the classic rail/action shortcuts collapse into a quiet
-- mono cluster at the bottom right. Toast/banner overlays are shared with
-- classic via _BuildOverlays.
function GameHUDScreen:_BuildACLayout()
	local theme = self:GetTheme()

	-- Same wrapper contract as classic: Rebuild drops this, the baseline
	-- UIScale on Root survives, and the pack scale composes on top.
	local content = UIStyler.Frame("Content")
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = self.Root
	self._content = content

	local packScale = Instance.new("UIScale")
	packScale.Name = "PackScale"
	packScale.Parent = content
	self._packScale = packScale

	-- ---- machine framing: corner L-brackets on the whole screen -------

	local machineFrame = UIStyler.Frame("MachineFrame")
	machineFrame.BackgroundTransparency = 1
	machineFrame.Position = UDim2.fromOffset(10, 10)
	machineFrame.Size = UDim2.new(1, -20, 1, -20)
	machineFrame.Parent = content
	ACLayoutKit.Brackets(theme, machineFrame)

	-- ---- TOP EDGE: transparent status strip + hairline ----------------

	local strip = UIStyler.Frame("StatusStrip")
	strip.BackgroundTransparency = 1
	strip.Size = UDim2.new(1, 0, 0, 34)
	strip.Parent = content

	local stripRule = ACLayoutKit.Rule(theme, strip, 0.8)
	stripRule.AnchorPoint = Vector2.new(0, 1)
	stripRule.Position = UDim2.new(0, 0, 1, 0)

	-- Far left: objectives as small dim mono rows (rendered on the same
	-- Update path as classic — see _RenderACObjectives), growing downward.
	local objectives = UIStyler.Frame("Objectives")
	objectives.BackgroundTransparency = 1
	objectives.Position = UDim2.fromOffset(16, 8)
	objectives.Size = UDim2.fromOffset(300, 0)
	objectives.AutomaticSize = Enum.AutomaticSize.Y
	UIStyler.ListLayout({
		Padding = UDim.new(0, 2),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = objectives
	objectives.Parent = content
	self._objectivesHolder = objectives

	-- Left of centre: the wave readout as a dim mono status line.
	local status = UIChrome.BodyText("Status", 11, theme.Colors.TextSecondary)
	status.AnchorPoint = Vector2.new(1, 0)
	status.Position = UDim2.new(0.5, -130, 0, 11)
	status.Size = UDim2.fromOffset(150, 12)
	status.TextXAlignment = Enum.TextXAlignment.Right
	status.Parent = content
	self._statusLabel = status

	-- Centre: the round timer in its own bracket-marked terminal region.
	-- The box stays a FIXED transparent footprint; _StartTimerFx drives the
	-- label's TextSize/colour and this glow stroke exactly as in classic
	-- (theme.Arcade.Gold rides the accent under this style).
	local timerBox = UIStyler.Frame("RoundTimer")
	timerBox.BackgroundTransparency = 1
	timerBox.AnchorPoint = Vector2.new(0.5, 0)
	timerBox.Position = UDim2.new(0.5, 0, 0, 0)
	timerBox.Size = UDim2.fromOffset(220, 56)
	timerBox.Parent = content
	ACLayoutKit.Brackets(theme, timerBox)
	self._timerBox = timerBox

	local timerValue = UIChrome.Text("Value", 16, theme.Arcade.Gold)
	timerValue.Size = UDim2.fromScale(1, 1)
	timerValue.Parent = timerBox
	self._timerLabel = timerValue

	local glow = Instance.new("UIStroke")
	glow.Name = "Glow"
	glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	glow.LineJoinMode = Enum.LineJoinMode.Round
	glow.Color = theme.Arcade.Gold
	glow.Thickness = 3
	glow.Transparency = 0.45
	glow.Parent = timerValue
	self._timerGlow = glow

	-- Right: the same currency pill components/keys as classic, compacted
	-- into a horizontal instrument row hanging from the top edge.
	local pillRow = UIStyler.Frame("CurrencyPills")
	pillRow.BackgroundTransparency = 1
	pillRow.AnchorPoint = Vector2.new(1, 0)
	pillRow.Position = UDim2.new(1, -16, 0, 0)
	pillRow.Size = UDim2.fromOffset(190 + 8 + 160, 48)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}).Parent = pillRow
	pillRow.Parent = content

	local cashPill = UICurrencyPillComponent.new()
	cashPill:Create(pillRow, {
		currencyId = "Cash",
		value = self._values.Cash,
		size = UDim2.fromOffset(190, 48),
		layoutOrder = 1,
	})
	self._pills.Cash = cashPill
	table.insert(self._components, cashPill)

	local buxPill = UICurrencyPillComponent.new()
	buxPill:Create(pillRow, {
		currencyId = "Bux",
		value = self._values.Bux,
		size = UDim2.fromOffset(160, 48),
		layoutOrder = 2,
	})
	self._pills.Bux = buxPill
	table.insert(self._components, buxPill)

	-- ---- BOTTOM RIGHT: shortcut cluster (rail + action row, collapsed) --

	local cluster = UIStyler.Frame("ShortcutCluster")
	cluster.BackgroundTransparency = 1
	cluster.AnchorPoint = Vector2.new(1, 1)
	cluster.Position = UDim2.new(1, -16, 1, -14)
	cluster.Size = UDim2.fromOffset(5 * 104 + 4 * 6, 24)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
	}).Parent = cluster
	cluster.Parent = content

	local shortcutCount = 0
	local function shortcut(text: string, onClick: () -> ()): TextButton
		shortcutCount += 1
		local button = ACLayoutKit.ActionButton(theme, cluster, text, onClick)
		button.Size = UDim2.fromOffset(104, 24)
		button.TextSize = 11
		button.LayoutOrder = shortcutCount
		return button
	end

	shortcut("STORE", function()
		self.ScreenController:ShowScreen("store")
	end)
	shortcut("INDEX", function()
		self.ScreenController:ShowScreen("index")
	end)
	local settingsButton = shortcut("SETTINGS", function()
		self.ScreenController:ShowScreen("settings")
	end)
	local shopButton = shortcut("SHOP", function()
		local shopScreen = self.ScreenController:GetScreen("shop")
		self.ScreenController:ToggleScreen("shop", { balances = shopScreen and shopScreen._balances })
	end)
	shortcut("DAILY", function()
		self:PushBanner({
			title = "DAILY REWARD",
			body = "Come back tomorrow for more!",
			variant = "Info",
		})
	end)

	-- Same tutorial anchors as classic, pointed at the AC equivalents.
	self.ScreenController:RegisterHighlightTarget("nav.theme", settingsButton)
	self.ScreenController:RegisterHighlightTarget("hud.topRight", cluster)
	self.ScreenController:RegisterHighlightTarget("nav.shop", shopButton)

	-- ---- overlays (second ScreenGui — the exact classic path) ---------
	self:_BuildOverlays()

	self:_ApplyPackScale()
end

-- ======================================================================
-- GP layout (theme.LayoutKit == "GP") — THE STUDIO SHELF.
--
-- Same screen map, same slots, same components, same callbacks: rail at
-- x=16 on the 126px pitch, status line at y=14, the FIXED 220x60 timer at
-- y=118, the 190x52 action pair at the 202px pitch, Cash/Bux pills at
-- y=-14 and the objectives column above them. What changes is the
-- MATERIAL. Every readout becomes a small glazed ceramic tile floating on
-- the world: translucent so the scene reads through it, petal-cornered,
-- alternating by index so the rail and the objective column read
-- hand-arranged rather than stamped, and each casting a soft shadow in a
-- deepened tint of its OWN fill — never grey, never black.
--
-- Nothing here is opaque. That is the pack's HUD law and the reason the
-- classic arcade slate panels do not simply get recoloured: a pastel slab
-- is still a slab, and this HUD sits over live gameplay.
--
-- The round timer is the one piece carrying the full signature — a butter
-- tile (gold is this pack's value colour and the countdown is the most
-- valuable number on screen) with a glaze sheen and a scalloped lip, ink
-- digits, and the §5.3 panic intact down to its sine. Gold digits are what
-- the arcade uses because its box is near-black; on butter they measure
-- ~1.2:1, so the pairing inverts rather than the rule bending.
-- ======================================================================

local GP_OBJECTIVE_W = 340
local GP_OBJECTIVE_H = 34
local GP_TILE_TRANSPARENCY = 0.16
local GP_ROW_TRANSPARENCY = 0.22

-- One rail cell as a glazed tile. Structurally the classic cell exactly:
-- a full-size INVISIBLE button (whole-cell hit target, doc §11.6) over a
-- non-interactive art frame plus a caption strip, with the §5.2 big-button
-- juice on the ART so the rail never reflows. The tile lives INSIDE the art
-- frame, so it wobbles and squashes with the icon as one object.
function GameHUDScreen:_GPRailCell(parent: Instance, index: number, caption: string, onClick: () -> ()): (TextButton, Frame)
	local theme = self:GetTheme()

	local cell = Instance.new("TextButton")
	cell.Name = caption .. "Cell"
	cell.BackgroundTransparency = 1
	cell.BorderSizePixel = 0
	cell.Text = ""
	cell.AutoButtonColor = false
	cell.Size = UDim2.fromOffset(RAIL_CELL, RAIL_CELL)
	cell.Position = UDim2.fromOffset(RAIL_X, RAIL_Y0 + (index - 1) * RAIL_PITCH)
	cell.Parent = parent

	local art = UIStyler.Frame("Art")
	art.BackgroundTransparency = 1
	art.Size = UDim2.new(1, 0, 0, RAIL_CELL - RAIL_CAPTION_H - 4)
	art.Parent = cell

	local tileFill = theme.Colors.SurfaceRaised
	local tile = UIStyler.Frame("Tile")
	tile.BackgroundColor3 = tileFill
	tile.BackgroundTransparency = GP_TILE_TRANSPARENCY
	tile.Size = UDim2.fromScale(1, 1)
	tile.ZIndex = 1
	tile.Parent = art
	GPLayoutKit.Petal(theme, tile, index)
	GPLayoutKit.SoftStroke(theme, tile, tileFill)
	GPLayoutKit.Shadow(theme, tile, "sm", self._gpShadows, tileFill)

	-- Verbatim copy, never string.upper: this pack does not shout (law 5).
	local strip = GPLayoutKit.BodyText(theme, 15, theme.Colors.TextPrimary, "Caption")
	strip.Text = caption
	strip.Size = UDim2.new(1, 0, 0, RAIL_CAPTION_H)
	strip.Position = UDim2.new(0, 0, 1, -RAIL_CAPTION_H)
	strip.ZIndex = 2
	strip.Parent = cell

	cell.Activated:Connect(onClick)
	UIChrome.AnimateBig(theme, cell, art)
	return cell, art
end

function GameHUDScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	self._gpShadows = {} :: { any }

	-- Same wrapper contract as classic: Rebuild drops this, the baseline
	-- UIScale on Root survives, and the pack scale composes on top.
	local content = UIStyler.Frame("Content")
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = self.Root
	self._content = content

	local packScale = Instance.new("UIScale")
	packScale.Name = "PackScale"
	packScale.Parent = content
	self._packScale = packScale

	-- ---- LEFT EDGE: icon rail (Store / Index / Settings) --------------

	local _, storeArt = self:_GPRailCell(content, 1, "Store", function()
		self.ScreenController:ShowScreen("store")
	end)
	local cart = UIAssets.Icon(storeArt, "Cart", 76)
	cart.AnchorPoint = Vector2.new(0.5, 0.5)
	cart.Position = UDim2.fromScale(0.5, 0.5)
	cart.ZIndex = 3

	local _, indexArt = self:_GPRailCell(content, 2, "Index", function()
		self.ScreenController:ShowScreen("index")
	end)
	local star = UIAssets.Icon(indexArt, "Star", 76)
	star.AnchorPoint = Vector2.new(0.5, 0.5)
	star.Position = UDim2.fromScale(0.5, 0.5)
	star.ZIndex = 3

	local settingsCell, settingsArt = self:_GPRailCell(content, 3, "Settings", function()
		self.ScreenController:ShowScreen("settings")
	end)
	local gear = UIAssets.Icon(settingsArt, "Settings", 76)
	gear.AnchorPoint = Vector2.new(0.5, 0.5)
	gear.Position = UDim2.fromScale(0.5, 0.5)
	gear.ZIndex = 3

	-- The tutorial's theme step points at the Settings rail button.
	self.ScreenController:RegisterHighlightTarget("nav.theme", settingsCell)

	-- ---- TOP CENTRE: status line + round timer ------------------------

	-- Keeps the classic amber (doc §3.2: sunburst gold = amber status lines) and
	-- stays boxless, so it takes the pack's own halo instead of a plate: a soft
	-- Contextual stroke in a DEEPENED TINT OF ITS OWN colour, painted onto the
	-- glow UIChrome.TextOutline already owns (a second UIStroke would not
	-- render). Butter with a caramel rim lifts off a bright sky and a dark alley
	-- alike, which is the whole reason the line is not the pack's plum ink.
	local statusFill = theme.Arcade.SunburstGold
	local status = GPLayoutKit.Text(theme, 24, statusFill, "Status")
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.new(0.5, 0, 0, 14)
	status.Size = UDim2.fromOffset(500, 30)
	status.Parent = content
	self._statusLabel = status
	local statusGlow = status:FindFirstChild("TextGlow") :: UIStroke?
	if statusGlow then
		statusGlow.Color = GPLayoutKit.Deepen(theme, statusFill, 1)
		statusGlow.Thickness = 2
		statusGlow.Transparency = 0.12
	end

	-- Round timer: FIXED 220x60, exactly the classic footprint. Only the
	-- material changes — butter tile, glaze sheen, scalloped lip, ink digits.
	local timerFill = theme.Arcade.Gold
	local timerBox = UIStyler.Frame("RoundTimer")
	timerBox.BackgroundColor3 = timerFill
	timerBox.BackgroundTransparency = GP_TILE_TRANSPARENCY
	timerBox.AnchorPoint = Vector2.new(0.5, 0)
	timerBox.Position = UDim2.new(0.5, 0, 0, 118)
	timerBox.Size = UDim2.fromOffset(220, 60)
	timerBox.Parent = content
	UIStyler.Corner(theme.Radii.Large).Parent = timerBox
	GPLayoutKit.SoftStroke(theme, timerBox, timerFill)
	GPLayoutKit.Shadow(theme, timerBox, "md", self._gpShadows, timerFill)
	-- Sheen AFTER the corner (the wash clones it), and pinned below the
	-- digits: GlazeSheen defaults to host + 1, which would frost them.
	local sheen = GPLayoutKit.GlazeSheen(theme, timerBox)
	sheen.ZIndex = timerBox.ZIndex
	GPLayoutKit.Scallop(theme, timerBox, "Bottom", timerFill)
	self._timerBox = timerBox

	local timerValue = GPLayoutKit.Text(theme, TIMER_TEXT_SIZE, theme.Colors.TextPrimary, "Value")
	timerValue.Size = UDim2.fromScale(1, 1)
	timerValue.ZIndex = 3
	timerValue.Parent = timerBox
	self._timerLabel = timerValue
	-- The digits get ONE Contextual stroke, and it has to be the panic glow
	-- below: UIChrome.Text leaves an emphasis glow behind on a no-outline pack,
	-- it is the first UIStroke child, and the engine renders only the first —
	-- so the §5.3 panic would silently stop showing.
	local staleGlow = timerValue:FindFirstChild("TextGlow")
	if staleGlow then
		staleGlow:Destroy()
	end

	-- The breathing/panic glow. _StartTimerFx drives this exact stroke; the
	-- fields below are the only thing the pack moves about it.
	local glow = Instance.new("UIStroke")
	glow.Name = "Glow"
	glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	glow.LineJoinMode = Enum.LineJoinMode.Round
	glow.Color = GPLayoutKit.Deepen(theme, timerFill, 1)
	glow.Thickness = 3
	glow.Transparency = 0.45
	glow.Parent = timerValue
	self._timerGlow = glow

	-- Ink digits in a caramel breath; the panic flashes deep plum-coral toward
	-- the pack's soft coral. Same window, same sine, same 4->7 glow ramp — the
	-- BOX still never resizes.
	self._restInk = theme.Colors.TextPrimary
	self._restGlow = GPLayoutKit.Deepen(theme, timerFill, 1)
	self._panicHot = theme.Colors.Error:Lerp(theme.Colors.TextPrimary, 0.4)
	self._panicCool = theme.Colors.Error

	-- ---- TOP RIGHT: action row (SHOP / DAILY) -------------------------

	local actions = UIStyler.Frame("TopRightActions")
	actions.BackgroundTransparency = 1
	actions.AnchorPoint = Vector2.new(1, 0)
	actions.Position = UDim2.new(1, -16, 0, 14)
	actions.Size = UDim2.fromOffset(ACTION_PITCH + ACTION_W, ACTION_H)
	actions.Parent = content

	local shopButton = UIButtonComponent.new()
	shopButton:Create(actions, {
		text = "Shop",
		variant = "Green",
		size = UDim2.fromOffset(ACTION_W, ACTION_H),
		position = UDim2.fromOffset(ACTION_PITCH, 0),
		onClick = function()
			local shopScreen = self.ScreenController:GetScreen("shop")
			self.ScreenController:ToggleScreen("shop", { balances = shopScreen and shopScreen._balances })
		end,
	})
	table.insert(self._components, shopButton)

	local dailyButton = UIButtonComponent.new()
	dailyButton:Create(actions, {
		text = "Daily",
		variant = "Orange",
		size = UDim2.fromOffset(ACTION_W, ACTION_H),
		position = UDim2.fromOffset(0, 0),
		onClick = function()
			self:PushBanner({
				title = "Daily Reward",
				body = "Come back tomorrow for more!",
				variant = "Info",
			})
		end,
	})
	table.insert(self._components, dailyButton)

	self.ScreenController:RegisterHighlightTarget("hud.topRight", actions)
	self.ScreenController:RegisterHighlightTarget("nav.shop", shopButton.Root)

	-- ---- BOTTOM LEFT: currency pills + objectives ---------------------

	local pillRow = UIStyler.Frame("CurrencyPills")
	pillRow.BackgroundTransparency = 1
	pillRow.AnchorPoint = Vector2.new(0, 1)
	pillRow.Position = UDim2.new(0, 16, 1, -14)
	pillRow.Size = UDim2.fromOffset(220 + 10 + 180, 56)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = pillRow
	pillRow.Parent = content

	local cashPill = UICurrencyPillComponent.new()
	cashPill:Create(pillRow, {
		currencyId = "Cash",
		value = self._values.Cash,
		size = UDim2.fromOffset(220, 56),
		layoutOrder = 1,
	})
	self._pills.Cash = cashPill
	table.insert(self._components, cashPill)

	local buxPill = UICurrencyPillComponent.new()
	buxPill:Create(pillRow, {
		currencyId = "Bux",
		value = self._values.Bux,
		size = UDim2.fromOffset(180, 56),
		layoutOrder = 2,
	})
	self._pills.Bux = buxPill
	table.insert(self._components, buxPill)

	-- Objectives stack directly above the pills, growing upward. WIDER than
	-- classic's 320 (not narrower): the petal corner needs the check icon to
	-- start clear of the arc, and the column pays for that inset itself rather
	-- than taking the pixels out of the objective text.
	local objectives = UIStyler.Frame("Objectives")
	objectives.BackgroundTransparency = 1
	objectives.AnchorPoint = Vector2.new(0, 1)
	objectives.Position = UDim2.new(0, 16, 1, -(14 + 56 + 14))
	objectives.Size = UDim2.fromOffset(GP_OBJECTIVE_W, 0)
	objectives.AutomaticSize = Enum.AutomaticSize.Y
	UIStyler.ListLayout({
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = objectives
	objectives.Parent = content
	self._objectivesHolder = objectives

	-- ---- overlays (second ScreenGui — the exact classic path) ---------
	self:_BuildOverlays()

	self:_ApplyPackScale()
end

-- GP objectives: the same data on the same update path, rendered as petal
-- tiles alternating down the column. Ink copy on a translucent blush row —
-- never the near-white TextOnPrimary, which measures 2.14:1 on this pack's
-- pastels. Completion still pulls the REAL tick from the icon archive (never
-- a glyph), tinted matcha rather than gold so a done row reads finished
-- rather than valuable.
function GameHUDScreen:_RenderGPObjectives(objectives: any)
	if not self._objectivesHolder then
		return
	end
	local theme = self:GetTheme()
	for _, item in self._objectives do
		item:Destroy()
	end
	table.clear(self._objectives)
	for i, objective in objectives do
		local rowFill = theme.Colors.SurfaceRaised
		local row = UIStyler.Frame("ObjectiveRow")
		row.BackgroundColor3 = rowFill
		row.BackgroundTransparency = GP_ROW_TRANSPARENCY
		row.Size = UDim2.new(1, 0, 0, GP_OBJECTIVE_H)
		row.LayoutOrder = i
		GPLayoutKit.Petal(theme, row, i)
		GPLayoutKit.SoftStroke(theme, row, rowFill)

		local check = IconArchive.Image(row, "checkmark", 20)
		check.Name = "Check"
		check.ImageColor3 = theme.Arcade.Green
		check.Position = UDim2.fromOffset(14, 7)
		check.ZIndex = 2
		check.Visible = objective.done == true

		local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Label")
		label.Text = TextConfig.Resolve(objective.textKey or objective.text)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Position = UDim2.fromOffset(44, 0)
		label.Size = UDim2.new(1, -52, 1, 0)
		label.ZIndex = 2
		label.Parent = row

		row.Parent = self._objectivesHolder
		table.insert(self._objectives, row)
	end
end

-- Toasts + banner render in their own ScreenGui at DisplayOrder 60 (doc
-- §7.3: toasts/reveals sit above every panel), parented alongside the HUD.
function GameHUDScreen:_BuildOverlays()
	local overlay = Instance.new("ScreenGui")
	overlay.Name = "GameHUDOverlays"
	overlay.ResetOnSpawn = false
	overlay.IgnoreGuiInset = true
	overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	overlay.DisplayOrder = 60
	overlay.Enabled = true
	self._overlayGui = overlay

	local root = UIStyler.Frame("Root")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = overlay

	-- Same 1650×1020 baseline scale + arcade style enforcer as every screen
	-- (this gui is hand-made, so UIScreenBase doesn't do it for us).
	local _, cleanup = UIScaleHelper.Attach(root)
	self._overlayScaleCleanup = cleanup
	UIStyleEnforcer.Attach(overlay, "Arcade")

	-- Toast stack (bottom, stacking upward from the corner).
	local toastStack = UIStyler.Frame("Toasts")
	toastStack.BackgroundTransparency = 1
	toastStack.AnchorPoint = Vector2.new(1, 1)
	toastStack.Position = UDim2.new(1, -16, 1, -16)
	toastStack.Size = UDim2.fromOffset(400, 340)
	UIStyler.ListLayout({
		Padding = UDim.new(0, 8),
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
	}).Parent = toastStack
	toastStack.Parent = root
	self._toastStack = toastStack

	-- Banner slot (top-centre, clear of the round timer at y=118+60).
	local bannerSlot = UIStyler.Frame("Banner")
	bannerSlot.BackgroundTransparency = 1
	bannerSlot.AnchorPoint = Vector2.new(0.5, 0)
	bannerSlot.Position = UDim2.new(0.5, 0, 0, 200)
	bannerSlot.Size = UDim2.fromOffset(480, 100)
	bannerSlot.Parent = root
	self._bannerSlot = bannerSlot

	overlay.Parent = self.Gui.Parent
end

-- ---- banner -----------------------------------------------------------

-- Prominent top-center banner (level-up, achievement, unlock, daily).
function GameHUDScreen:PushBanner(data: any)
	self:_EnsureBuilt()
	self:_PlaySound(data.variant == "Info" and "Open" or "Success")
	if self._banner then
		self._banner:Destroy()
	end
	local banner = UINotificationComponent.new()
	self._banner = banner
	banner:Create(self._bannerSlot, {
		titleKey = data.titleKey,
		title = data.title,
		bodyKey = data.bodyKey,
		body = data.body,
		icon = data.icon,
		variant = data.variant,
		duration = data.duration,
		position = UDim2.fromScale(0.5, 0.5),
		anchorPoint = Vector2.new(0.5, 0.5),
		onDone = function()
			if self._banner == banner then
				self._banner = nil
			end
		end,
	})
	banner:Play()
end

-- ---- toasts -----------------------------------------------------------

function GameHUDScreen:PushToast(data: any)
	self:_EnsureBuilt()
	if data.variant == "Success" then
		self:_PlaySound("Success")
	elseif data.variant == "Error" then
		self:_PlaySound("Error")
	end
	local toast = UIToastComponent.new()
	toast:Create(self._toastStack, {
		textKey = data.textKey,
		text = data.text,
		variant = data.variant,
		icon = data.icon,
		duration = data.duration,
		onDone = function()
			local index = table.find(self._toasts, toast)
			if index then
				table.remove(self._toasts, index)
			end
		end,
	})
	table.insert(self._toasts, toast)
	toast:Play()
end

-- ---- values -----------------------------------------------------------

function GameHUDScreen:Update(data: any)
	if not data then
		return
	end
	if data.values then
		for id, value in data.values do
			self._values[id] = value
		end
		self:_RefreshValues()
	end
	if data.objectives then
		-- Cached so a rebuild (style switch, pack change) can re-render the
		-- list instead of losing it until the next server push.
		self._objectiveData = data.objectives
		self:_RenderObjectives(data.objectives)
	end
end

function GameHUDScreen:_RefreshValues()
	-- A fresh build has an empty objectives column; restore the cached list.
	if self._objectiveData and #self._objectives == 0 then
		self:_RenderObjectives(self._objectiveData)
	end
	local v = self._values
	local status = self._statusLabel
	if status and status.Parent then
		-- Same field, same number, same format width — only the case follows the
		-- layout kit, because the pastel pack does not shout (law 5). Derived
		-- rather than stored so it self-corrects on every style swap.
		local wave = if self:LayoutKit() == "GP" then "Wave %d" else "WAVE %d"
		status.Text = string.format(wave, math.floor(v.wave or 0))
	end
	local timerLabel = self._timerLabel
	if timerLabel and timerLabel.Parent then
		timerLabel.Text = UIChrome.FormatCountdown(v.timer or 0)
	end
	-- CurrencyChanged balances arrive keyed "Cash"/"Bux" — straight onto the
	-- pills (which pulse only when a value actually changes).
	for id, pill in self._pills do
		if pill.Root and pill.Root.Parent then
			pill:SetValue(math.floor(v[id] or 0))
		end
	end
end

-- Objectives as arcade slate rows: Arcade.Row @ 8% transparency, 2px black
-- stroke, FredokaOne 18, gold ✓ when done.
function GameHUDScreen:_RenderObjectives(objectives: any)
	if self:LayoutKit() == "GP" then
		self:_RenderGPObjectives(objectives)
		return
	end
	if self:LayoutKit() == "AC" then
		self:_RenderACObjectives(objectives)
		return
	end
	if not self._objectivesHolder then
		return
	end
	local theme = self:GetTheme()
	for _, item in self._objectives do
		item:Destroy()
	end
	table.clear(self._objectives)
	for i, objective in objectives do
		local row = UIStyler.Frame("ObjectiveRow")
		row.BackgroundColor3 = theme.Arcade.Row
		row.BackgroundTransparency = theme.Arcade.RowTransparency
		row.Size = UDim2.new(1, 0, 0, 34)
		row.LayoutOrder = i
		-- The objective-row recipe calls for a 2px black stroke (matching the
		-- enforcer's small-element weight), not the 3px panel border — the one
		-- sanctioned deviation from UIChrome.Stroke here. Styled chrome
		-- (theme.Chrome) swaps in its own framing stroke instead.
		if theme.Chrome then
			UIChrome.Stroke(theme, "Arcade").Parent = row
		else
			UIStyler.Stroke(BLACK, 2, 0).Parent = row
		end

		-- PACK LAW: never a glyph/emoji — completion pulls the real tick from
		-- the ICON GALLERY, tinted gold, hidden while the objective is open.
		local check = IconArchive.Image(row, "checkmark", 20)
		check.Name = "Check"
		check.ImageColor3 = theme.Arcade.Gold
		check.Position = UDim2.fromOffset(6, 7)
		check.Visible = objective.done == true

		local label = UIChrome.Text("Label", 18, WHITE)
		label.Text = TextConfig.Resolve(objective.textKey or objective.text)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Position = UDim2.fromOffset(36, 0)
		label.Size = UDim2.new(1, -44, 1, 0)
		label.Parent = row

		row.Parent = self._objectivesHolder
		table.insert(self._objectives, row)
	end
end

-- AC objectives: same data + update path, rendered as small dim mono rows —
-- a "[x]" ledger instead of arcade slates. Done rows tick in the accent.
function GameHUDScreen:_RenderACObjectives(objectives: any)
	if not self._objectivesHolder then
		return
	end
	local theme = self:GetTheme()
	for _, item in self._objectives do
		item:Destroy()
	end
	table.clear(self._objectives)
	for i, objective in objectives do
		local row = UIStyler.Frame("ObjectiveRow")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 15)
		row.LayoutOrder = i

		local check = UIChrome.BodyText("Check", 11, objective.done and theme.Colors.Accent or theme.Colors.TextSecondary)
		check.Text = objective.done and "[x]" or "[ ]"
		check.TextXAlignment = Enum.TextXAlignment.Left
		check.Size = UDim2.fromOffset(26, 15)
		check.Parent = row

		local label = UIChrome.BodyText("Label", 11, theme.Colors.TextSecondary)
		label.Text = string.upper(TextConfig.Resolve(objective.textKey or objective.text))
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Position = UDim2.fromOffset(30, 0)
		label.Size = UDim2.new(1, -30, 1, 0)
		label.Parent = row

		row.Parent = self._objectivesHolder
		table.insert(self._objectives, row)
	end
end

-- ---- round-timer effects (doc §5.3) -----------------------------------

-- One RenderStepped connection while the HUD is shown, gated on the timer
-- box being on-screen (doc §5.4 animation frugality). Normal state: the gold
-- glow breathes on sin(t·2.4). Final 10s: TextSize oscillates 52→66 on
-- sin(t·10), the colour flashes red toward near-white, the glow thickens
-- 4→7. Only text properties + the stroke animate — the box never resizes.
function GameHUDScreen:_StartTimerFx()
	if self._timerFx then
		return
	end
	self._timerFx = RunService.RenderStepped:Connect(function()
		local box = self._timerBox
		local label = self._timerLabel
		local glow = self._timerGlow
		if not (box and label and glow) or not box.Parent then
			return
		end
		if not UIChrome.IsOnScreen(box) then
			return
		end
		local theme = self:GetTheme()
		local t = os.clock()
		local remaining = self._values.timer or 0
		-- The four colours are FIELDS with the doc §5.3 constants as their
		-- fallbacks, because gold-on-slate is legible only because the classic
		-- box is near-black — a pack whose timer sits on a light tile has to
		-- move the pairing. Classic and AC set none of them, so they resolve to
		-- exactly the constants and this loop is unchanged for both.
		if remaining <= PANIC_WINDOW then
			local s = math.sin(t * 10)
			label.TextSize = 59 + 7 * s -- 52 → 66
			label.TextColor3 = (self._panicHot or PANIC_RED):Lerp(self._panicCool or PANIC_WHITE, (s + 1) / 2)
			glow.Color = self._panicHot or PANIC_RED
			glow.Transparency = 0
			glow.Thickness = 5.5 + 1.5 * s -- 4 → 7
		else
			label.TextSize = TIMER_TEXT_SIZE
			label.TextColor3 = self._restInk or theme.Arcade.Gold
			glow.Color = self._restGlow or theme.Arcade.Gold
			glow.Transparency = 0.45
			glow.Thickness = 3 + math.sin(t * 2.4) -- gentle breathe
		end
	end)
end

function GameHUDScreen:_StopTimerFx()
	if self._timerFx then
		self._timerFx:Disconnect()
		self._timerFx = nil
	end
end

-- ---- layout / scale hooks (public API preserved) ----------------------

-- The Pottery HUD layout is fixed by the doc's screen map, so per-element
-- region moves stay a no-op; the method survives for ClientHandler's
-- SetElementRegion binding + the UIDebug seam.
function GameHUDScreen:SetElementRegion(_elementId: string, _region: string) end

-- Apply a layout preset's HUD block. Placement is fixed, so only the
-- optional scale override is applied (kept so UILayoutController:Apply and
-- its bindings keep working).
function GameHUDScreen:ApplyLayout(opts: { money: string?, regions: { [string]: string }?, scaleOverride: number? })
	self._scaleOverride = opts.scaleOverride
	self:_ApplyPackScale()
end

function GameHUDScreen:_ApplyPackScale()
	if not self._packScale then
		return
	end
	local pack = self.ThemeController and self.ThemeController:GetPack()
	local packScale = (pack and pack.HUD.Scale) or 1
	self._packScale.Scale = self._scaleOverride or packScale
end

-- ---- show / hide / teardown -------------------------------------------

function GameHUDScreen:_OnShow(data: any?)
	if data then
		self:Update(data)
	end
	self:_RefreshValues()
	self:_ApplyPackScale()
	self:_StartTimerFx()
end

function GameHUDScreen:_OnHide()
	self:_StopTimerFx()
end

-- Style rebuilds destroy self.Gui for us — but the toast/banner overlays live
-- in a SECOND ScreenGui that would otherwise duplicate on every rebuild, and
-- the pastel HUD's shadow handles have to be released or the budget counter
-- never comes back down.
function GameHUDScreen:_OnTeardown()
	self:_StopTimerFx()
	for _, toast in self._toasts do
		toast:Destroy()
	end
	self._toasts = {}
	if self._banner then
		self._banner:Destroy()
		self._banner = nil
	end
	for _, component in self._components do
		component:Destroy()
	end
	self._components = {}
	self._pills = {}
	self._objectives = {}
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	if self._overlayScaleCleanup then
		self._overlayScaleCleanup()
		self._overlayScaleCleanup = nil
	end
	if self._overlayGui then
		self._overlayGui:Destroy()
		self._overlayGui = nil
	end
	self._content = nil
	self._timerBox = nil
	self._timerLabel = nil
	self._timerGlow = nil
	self._statusLabel = nil
	self._objectivesHolder = nil
	self._packScale = nil
	self._restInk = nil
	self._restGlow = nil
	self._panicHot = nil
	self._panicCool = nil
end

function GameHUDScreen:Destroy()
	self:_StopTimerFx()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	if self._overlayScaleCleanup then
		self._overlayScaleCleanup()
		self._overlayScaleCleanup = nil
	end
	if self._overlayGui then
		self._overlayGui:Destroy()
		self._overlayGui = nil
	end
	for _, component in self._components do
		component:Destroy()
	end
	self._components = {}
	UIScreenBase.Destroy(self)
end

return GameHUDScreen
