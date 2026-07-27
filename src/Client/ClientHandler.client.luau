--!strict
-- The one client LocalScript. Boots the UI system in a controlled order,
-- injects controllers into components/screens, registers every screen, wires
-- input actions, and kicks off a demo: HUD + a nav rail + tutorial, with the
-- shop and Theme Editor reachable by button or hotkey.
--
-- Adding a screen NO LONGER means touching this file: declare it in
-- Manifests/ScreenManifest and the ScreenRegistry builds it the first time
-- something opens that id. The explicit constructions below are the core ten
-- that boot eagerly (the HUD must exist before anything can toast to it) plus
-- the ones this demo injects handlers into. Adding a theme or pack = drop a
-- module and register in config; no change here either.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = script.Parent.UI
local Components = UI.Components
local Screens = UI.Screens
local Controllers = UI.Controllers

-- Config / shared.
local DevConfig = require(UI.Config.DevConfig)
local HUDConfig = require(UI.Config.HUDConfig)
local LayoutPresetConfig = require(UI.Config.LayoutPresetConfig)
local PanelAnimConfig = require(UI.Config.PanelAnimConfig)
local TutorialConfig = require(UI.Config.TutorialConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SharedTypes = require(ReplicatedStorage.Shared.Types)

-- Component base, for dependency injection into every component/screen.
local UIComponentBase = require(Components.UIComponentBase)

-- Framework: the layer stack + the on-demand screen library.
local Layers = require(UI.Framework.Layers)
local ScreenRegistry = require(UI.Framework.ScreenRegistry)

-- Controllers.
local UIThemeController = require(Controllers.UIThemeController)
local UIScreenController = require(Controllers.UIScreenController)
local UIInputController = require(Controllers.UIInputController)
local UISoundController = require(Controllers.UISoundController)
local UIOverheadController = require(Controllers.UIOverheadController)
local UIChatBubbleController = require(Controllers.UIChatBubbleController)
local UILayoutController = require(Controllers.UILayoutController)
local UINavRailController = require(Controllers.UINavRailController)

-- Screens.
local GameHUDScreen = require(Screens.GameHUDScreen)
local ShopScreen = require(Screens.ShopScreen)
local StoreScreen = require(Screens.StoreScreen)
local IndexScreen = require(Screens.IndexScreen)
local ModalScreen = require(Screens.ModalScreen)
local TutorialScreen = require(Screens.TutorialScreen)
local ThemeSelectorScreen = require(Screens.ThemeSelectorScreen)
local NPCDialogScreen = require(Screens.NPCDialogScreen)
local SettingsScreen = require(Screens.SettingsScreen)
local ChatBarScreen = require(Screens.ChatBarScreen)

local player = Players.LocalPlayer

-- ---- boot controllers -------------------------------------------------

local themeController = UIThemeController.new()
local screenController = UIScreenController.new(themeController)
local inputController = UIInputController.new()
local soundController = UISoundController.new()
local overheadController = UIOverheadController.new(themeController)
local chatBubbleController = UIChatBubbleController.new(themeController)

-- Inject controllers into the component base: theme = live re-skinning; sound
-- for the screens' Success/Error hooks. Both are nil-safe.
UIComponentBase.SetThemeController(themeController)
UIComponentBase.SetSoundController(soundController)
require(Screens.UIScreenBase).SetSoundController(soundController)

-- The ONE global UI click (design doc §6): auto-hooked onto Activated of
-- every current and future GuiButton under PlayerGui — no per-UI wiring.
-- Plus the lobby music cycle (crossfades, never cuts).
do
	local playerGui = player:WaitForChild("PlayerGui")
	soundController:AttachGlobalClick(playerGui)
	soundController:StartMusic()
end

-- Raw modal-card headers and close buttons (ModalCard + UIPanelComponent, both tagged) are painted
-- once at build; retint every live one when the theme changes so a colour
-- preset moves the WHOLE red family — header bars and X buttons included.
-- (UIPanelComponent repaints its own header through ApplyTheme already.)
do
	local CollectionService = game:GetService("CollectionService")
	local UIChrome = require(UI.UIChrome)
	-- The style's chrome policy (outline vs glow, bevel, hairlines) must be
	-- active before ANY screen builds, and must follow style switches.
	UIChrome.SetActiveTheme(themeController:GetTheme())
	-- Probe whether the engine actually APPLIES native UI Styling here
	-- (classes existing is not the same fact — see Style/Capabilities).
	require(UI:WaitForChild("StyleKit"):WaitForChild("Capabilities")).Detect()
	themeController.ThemeChanged:Connect(function(theme)
		UIChrome.SetActiveTheme(theme)
		for _, header in CollectionService:GetTagged(UIChrome.HEADER_TAG) do
			header.BackgroundColor3 = theme.Arcade.HeaderRed
		end
		for _, close in CollectionService:GetTagged(UIChrome.CLOSE_TAG) do
			close.BackgroundColor3 = theme.Arcade.Red
		end
	end)
end

-- ---- register screens -------------------------------------------------

local hud = GameHUDScreen.new()
local shop = ShopScreen.new()
local store = StoreScreen.new()
local index = IndexScreen.new()
local modal = ModalScreen.new()
local tutorial = TutorialScreen.new()
local themeSelector = ThemeSelectorScreen.new()
local npcDialog = NPCDialogScreen.new()
local settings = SettingsScreen.new()
local chatBar = ChatBarScreen.new()

-- Layout presets (nav placement + HUD regions). Injected into the Theme Editor
-- so its Layout picker can switch presets live; nav rebuild wired below.
local layoutController = UILayoutController.new(hud)

-- Build the layer stack up-front so DisplayOrder conflicts surface at boot,
-- and give the controller the catalog so ANY manifest id (inventory, quests,
-- spinWheel, leaderboard, ...) resolves on first use without being wired here.
Layers.Init()
local screenRegistry = ScreenRegistry.new(themeController, screenController)
screenController:SetRegistry(screenRegistry)

screenController:RegisterScreen("hud", hud)
screenController:RegisterScreen("shop", shop)
screenController:RegisterScreen("store", store)
screenController:RegisterScreen("index", index)
screenController:RegisterScreen("modal", modal)
screenController:RegisterScreen("tutorial", tutorial)
screenController:RegisterScreen("themeSelector", themeSelector)
screenController:RegisterScreen("npcDialog", npcDialog)
screenController:RegisterScreen("settings", settings)
screenController:RegisterScreen("chatBar", chatBar)
screenController:SetModalScreen("modal")

-- ---- purchase wiring (client -> server) -------------------------------

local purchaseRemote = Remotes.WaitFor("PurchaseItem", 5) :: RemoteFunction?
local currencyChanged = Remotes.WaitFor("CurrencyChanged", 5) :: RemoteEvent?

-- Injected into the shop: authoritative purchase with a local fallback so the
-- shop still works in a UI-only / test place where the server isn't present.
-- Shared by the shop AND the exclusive store (both raise the same confirm modal
-- and route through the same authoritative purchase).
local function purchaseItem(item: SharedTypes.ShopItem): SharedTypes.PurchaseResult
	if purchaseRemote then
		local ok, result = pcall(function()
			return purchaseRemote:InvokeServer(item.id)
		end)
		if ok and typeof(result) == "table" then
			return result
		end
	end
	-- Local fallback (offline preview).
	return { success = true, messageKey = "shop.purchase_success" }
end
shop:SetPurchaseHandler(purchaseItem)
store:SetPurchaseHandler(purchaseItem)

if currencyChanged then
	currencyChanged.OnClientEvent:Connect(function(balances: SharedTypes.CurrencyBalances)
		hud:Update({ values = balances })
		shop:Update({ balances = balances })
		store:Update({ balances = balances })
	end)
end

-- ---- floating nav rail (dev/demo) -------------------------------------

local navRailController = UINavRailController.new(themeController, screenController, layoutController, DevConfig)

-- Maps a NavConfig button `action` to what it does. Adding a nav button is a
-- data edit in NavConfig plus (if it's a new action) one row here.
navRailController:SetActionHandler(function(action: string)
	if action == "ToggleShop" then
		screenController:ToggleScreen("shop", { balances = shop._balances })
	elseif action == "ToggleThemeEditor" then
		screenController:ToggleScreen("themeSelector")
	elseif action == "ToggleSettings" then
		screenController:ToggleScreen("settings")
	elseif action == "ShowTutorial" then
		screenController:ShowScreen("tutorial", {
			steps = TutorialConfig.Steps,
			onComplete = function() end,
		})
	end
end)

-- The layout controller triggers a nav rebuild whenever a preset is applied.
layoutController:SetNavRebuilder(function()
	navRailController:Rebuild()
end)

-- Swap the active pack: re-skin/relayout the shop shape, rebuild the HUD and the
-- nav rail (both read pack settings). Shared by the nav/dev screen and the seam.
local function applyPack(packId: string)
	themeController:SetPack(packId)
	navRailController:Rebuild()
	hud:Rebuild()
	if screenController:IsVisible("shop") then
		-- Pack swap changes the layout shape (columns/spec), not just data.
		screenController:GetScreen("shop"):_RebuildLayout()
	end
end

-- ---- "Test All" harness ----------------------------------------------
-- Fires every transient piece of UI (toasts, banner, modal, NPC dialog, chat
-- bar, settings) in sequence, then rotates through every theme so you can eyeball
-- them all quickly. Guarded so it can't stack on itself. Driven by the Theme
-- Editor's "Test All" button and the Studio UIDebug seam.
local testAllRunning = false
local function runTestAll()
	if testAllRunning then
		return
	end
	testAllRunning = true
	task.spawn(function()
		local originalTheme = themeController:GetTheme().Id
		hud:PushToast({ text = "Test All ▶ starting…", variant = "Info", duration = 2 })
		task.wait(1)
		for _, v in { "Success", "Info", "Warning", "Error" } do
			hud:PushToast({ text = "Toast: " .. v, variant = v, duration = 2 })
			task.wait(0.5)
		end
		task.wait(1.2)
		hud:PushBanner({ titleKey = "notify.levelup.title", bodyKey = "notify.levelup.body", variant = "LevelUp", duration = 2.4 })
		task.wait(2.4)
		hud:PushBanner({ titleKey = "notify.achievement.title", bodyKey = "notify.achievement.body", variant = "Achievement", duration = 2.4 })
		task.wait(2.4)
		screenController:ShowModal({
			kind = "Confirm",
			titleKey = "modal.confirm_purchase.title",
			body = "Test All — does this modal read cleanly in the current theme?",
			confirmKey = "modal.confirm",
			cancelKey = "modal.cancel",
			onConfirm = function() end,
		})
		task.wait(2.2)
		screenController:HideModal()
		screenController:ShowScreen("npcDialog", { sequenceId = "welcome_merchant" })
		task.wait(2.6)
		screenController:HideScreen("npcDialog")
		screenController:ShowScreen("chatBar", { speaker = "Narrator", text = "Test All — bottom chat / subtitles bar.", duration = 3 })
		task.wait(2.2)
		screenController:ShowScreen("settings")
		task.wait(2.6)
		screenController:HideScreen("settings")
		-- Rotate every theme so each transient look is visible themed.
		for _, t in themeController:GetThemeList() do
			themeController:SetTheme(t.Id)
			hud:PushToast({ text = "Theme: " .. t.DisplayName, variant = "Info", duration = 1 })
			task.wait(0.85)
		end
		themeController:SetTheme(originalTheme)
		hud:PushToast({ text = "Test All ✅ complete", variant = "Success", duration = 3 })
		testAllRunning = false
	end)
end

-- Individual preview triggers — same pieces "Test All" fires in sequence,
-- but each on its own button so a specific one can be shown on demand and
-- left up (to inspect/tweak live in the Theme Editor) instead of only ever
-- seeing it flash by mid-sequence.
local individualPreviews = {
	{
		label = "Toast",
		icon = "🔔",
		fn = function()
			hud:PushToast({ text = "Sample toast message", variant = "Info", duration = 5 })
		end,
	},
	{
		label = "Banner",
		icon = "⭐",
		fn = function()
			hud:PushBanner({ titleKey = "notify.levelup.title", bodyKey = "notify.levelup.body", variant = "LevelUp", duration = 6 })
		end,
	},
	{
		label = "Modal",
		icon = "❗",
		fn = function()
			screenController:ShowModal({
				kind = "Confirm",
				titleKey = "modal.confirm_purchase.title",
				body = "Preview — does this modal read cleanly in the current theme?",
				confirmKey = "modal.confirm",
				cancelKey = "modal.cancel",
				onConfirm = function() end,
			})
		end,
	},
	{
		label = "NPC Dialog",
		icon = "💬",
		fn = function()
			screenController:ShowScreen("npcDialog", { sequenceId = "welcome_merchant" })
		end,
	},
	{
		label = "Chat Bar",
		icon = "💭",
		fn = function()
			screenController:ShowScreen("chatBar", { speaker = "Narrator", text = "Preview — bottom chat / subtitles bar.", duration = 5 })
		end,
	},
	{
		label = "Settings",
		icon = "⚙️",
		fn = function()
			screenController:ToggleScreen("settings")
		end,
	},
	{
		label = "Tutorial",
		icon = "❓",
		fn = function()
			screenController:ToggleScreen("tutorial", {
				steps = TutorialConfig.Steps,
				onComplete = function()
					hud:PushToast({ text = "Tutorial complete!", variant = "Success", duration = 3 })
				end,
			})
		end,
	},
	{
		label = "Shop",
		icon = "🛒",
		fn = function()
			screenController:ToggleScreen("shop", { balances = shop._balances })
		end,
	},
}

-- Hand the Theme Editor its dev tools (layout presets, the Test All runner,
-- and the individual preview buttons above) so its buttons can drive them
-- without reaching back into the handler globally.
if themeSelector.SetDevTools then
	themeSelector:SetDevTools(layoutController, runTestAll, individualPreviews)
end

-- ---- input actions ----------------------------------------------------

inputController:BindAction("ToggleShop", function()
	screenController:ToggleScreen("shop", { balances = shop._balances })
end)
inputController:BindAction("ToggleThemeEditor", function()
	if DevConfig.IsAuthorized(player.UserId) then
		screenController:ToggleScreen("themeSelector")
	end
end)
inputController:BindAction("ToggleHUD", function()
	screenController:ToggleScreen("hud")
end)
-- Y: global iconography switch. Icons hide by transparency, so layout never
-- reflows — the toggle is a pure look change, useful for judging the chrome
-- and typography on their own. IconVisibility.Init() watches for icons built
-- AFTER a toggle (lazy screens, pooled rows, style rebuilds) so the state
-- sticks instead of silently reverting.
do
	local IconVisibility = require(UI.Icons.IconVisibility)
	IconVisibility.Init()
	inputController:BindAction("ToggleIcons", function()
		IconVisibility.Toggle()
	end)
end
inputController:BindAction("CloseTop", function()
	screenController:CloseTopmost()
end)
inputController:BindAction("AdvanceTutorial", function()
	if screenController:IsVisible("tutorial") then
		tutorial:Advance()
	end
end)
-- ` (or gamepad Start) hides/shows the screen dock — the strip that can open
-- every screen in the catalog.
inputController:BindAction("ToggleScreenCatalog", function()
	screenController:ToggleScreen("screenDock")
end)

-- ---- launch -----------------------------------------------------------

-- HUD is always on; seed it with config defaults + sample objectives.
screenController:ShowScreen("hud", {
	values = HUDConfig.DefaultValues,
	objectives = {
		{ id = "reach_shop", textKey = "objective.reach_shop", done = true },
		{ id = "buy_boost", textKey = "objective.buy_boost", done = false },
		{ id = "survive", textKey = "objective.survive", done = false },
	},
})

-- The screen dock: the way into the library. Every screen the manifest
-- declares is one click away, and the dock survives panel switches because it
-- is not in the exclusive set. Toggle it with ` — or set enabled = false on
-- the manifest entry to ship a game without it.
screenController:ShowScreen("screenDock")

-- The build toolbar: persistent bottom hotbar (1-9 to select, B / its INV
-- button opens the palette above it). HUD-band, so panels never close it.
screenController:ShowScreen("hotbar")

-- Keep the dock's open/closed markers honest when a screen is opened or closed
-- by something OTHER than the dock (a HUD button, a hotkey, a screen closing
-- itself).
local function syncDock()
	local dock = screenController:GetScreen("screenDock")
	if dock and dock.Update then
		dock:Update({})
	end
end
screenController.ScreenShown:Connect(syncDock)
screenController.ScreenHidden:Connect(syncDock)

navRailController:Build()
navRailController:WatchViewportResize()

-- Studio-only debug seam. Exposed via BindableFunctions in ReplicatedStorage
-- (not _G, which is not shared with externally-injected code) so the MCP
-- screenshot harness (tools/ui-shots.lua) can drive theme/pack/screen switches
-- at runtime. Never present in a live game (guarded by IsStudio).
if game:GetService("RunService"):IsStudio() then
	local folder = Instance.new("Folder")
	folder.Name = "UIDebug"
	local function bind(name: string, fn: (...any) -> ...any)
		local bindable = Instance.new("BindableFunction")
		bindable.Name = name
		bindable.OnInvoke = fn
		bindable.Parent = folder
	end
	bind("ApplyPack", function(packId: string)
		applyPack(packId)
		return true
	end)
	bind("SetTheme", function(themeId: string)
		themeController:SetTheme(themeId)
		return true
	end)
	bind("ShowScreen", function(id: string)
		if id == "shop" then
			screenController:ShowScreen("shop", { balances = shop._balances })
		else
			screenController:ShowScreen(id)
		end
		return true
	end)
	-- The catalog seam: what CAN be opened, and what actually built. Lets the
	-- screenshot harness walk every library screen without a hardcoded list.
	bind("ListScreens", function()
		return table.concat(screenRegistry:Catalog(), ",")
	end)
	bind("ScreenFailures", function()
		local out = {}
		for id, err in screenRegistry:Failures() do
			table.insert(out, id .. ": " .. err)
		end
		return table.concat(out, " | ")
	end)
	bind("HideScreen", function(id: string)
		screenController:HideScreen(id)
		return true
	end)
	bind("SelectCategory", function(categoryId: string)
		if screenController:IsVisible("shop") then
			screenController:GetScreen("shop"):_SelectCategory(categoryId)
		end
		return true
	end)
	bind("SetSoundPack", function(packId: string)
		soundController:SetPack(packId)
		return true
	end)
	bind("SetElementRegion", function(elementId: string, region: string)
		hud:SetElementRegion(elementId, region)
		return true
	end)
	bind("ApplyLayout", function(presetId: string)
		return layoutController:Apply(presetId)
	end)
	bind("SetAnimPack", function(packId: string)
		return PanelAnimConfig.SetActive(packId)
	end)
	bind("ListAnimPacks", function()
		local ids = {}
		for _, p in PanelAnimConfig.Packs do
			table.insert(ids, p.id)
		end
		return table.concat(ids, ",")
	end)
	bind("ListLayouts", function()
		local ids = {}
		for _, preset in LayoutPresetConfig.Presets do
			table.insert(ids, preset.id)
		end
		return table.concat(ids, ",")
	end)
	bind("TestAll", function()
		runTestAll()
		return true
	end)
	bind("ShowDialog", function()
		screenController:ShowScreen("npcDialog", { sequenceId = "welcome_merchant" })
		return true
	end)
	bind("ShowBanner", function(variant: string)
		hud:PushBanner({
			titleKey = variant == "Achievement" and "notify.achievement.title" or "notify.levelup.title",
			bodyKey = variant == "Achievement" and "notify.achievement.body" or "notify.levelup.body",
			variant = variant or "LevelUp",
			duration = 4,
		})
		return true
	end)
	bind("SetOverheadLocation", function(locationId: string)
		if player.Character then
			overheadController:SetLocation(player.Character, locationId)
		end
		return true
	end)
	bind("SayOverhead", function(text: string)
		if player.Character then
			chatBubbleController:Say(player.Character, text or "Hey there! 👋", { duration = 4 })
		end
		return true
	end)
	bind("ShowChatBar", function(text: string)
		screenController:ShowScreen("chatBar", {
			speaker = "Narrator",
			text = text or "This is the bottom chat bar — subtitles, narration, radio chatter.",
			duration = 5,
		})
		return true
	end)
	bind("ShowSettings", function()
		screenController:ShowScreen("settings")
		return true
	end)
	-- Recolour the active style with a palette preset (Config/ColorPresetConfig)
	-- — the same path the Theme & Style screen's preset rows run.
	bind("ApplyColorPreset", function(presetId: string)
		local ColorPresetConfig = require(UI.Config.ColorPresetConfig)
		local preset = ColorPresetConfig.Get(presetId)
		if not preset then
			return false
		end
		local stock = themeController:GetThemeList()[1]
		for _, registered in themeController:GetThemeList() do
			if registered.Id == themeController:GetTheme().Id then
				stock = registered
			end
		end
		themeController:ApplyThemeObject(ColorPresetConfig.Apply(stock, preset))
		return true
	end)
	-- Build-palette seams: drive the hotbar/palette model from tests (clicks
	-- can't be simulated — VirtualInputManager needs RobloxScript capability).
	bind("ToggleIcons", function(force: boolean?)
		local IconVisibility = require(UI.Icons.IconVisibility)
		if force == nil then
			return IconVisibility.Toggle()
		end
		IconVisibility.Set(force)
		return IconVisibility.IsEnabled()
	end)
	bind("SelectHotbar", function(index: number)
		local BuildPaletteState = require(UI.Framework.BuildPaletteState)
		BuildPaletteState.Select(index)
		return BuildPaletteState.GetSelectedIndex()
	end)
	bind("SetHotbarSlot", function(index: number, itemId: string?)
		local BuildPaletteState = require(UI.Framework.BuildPaletteState)
		BuildPaletteState.SetSlot(index, itemId and BuildPaletteState.FindItem(itemId) or nil)
		local entry = BuildPaletteState.GetSlot(index)
		return entry and entry.id or ""
	end)
	bind("SwapHotbarSlots", function(a: number, b: number)
		local BuildPaletteState = require(UI.Framework.BuildPaletteState)
		BuildPaletteState.SwapSlots(a, b)
		return true
	end)
	-- Native-styling capability report (probed at boot, async).
	bind("StyleReport", function()
		local Capabilities = require(UI:WaitForChild("StyleKit"):WaitForChild("Capabilities"))
		return ("classes=%s shadow=%s perCorner=%s resolved=%s stylingActive=%s transitions=%s liveShadows=%d"):format(
			tostring(Capabilities.SheetClassesAvailable),
			tostring(Capabilities.ShadowAvailable),
			tostring(Capabilities.PerCornerRadii),
			tostring(Capabilities.Resolved),
			tostring(Capabilities.StylingActive),
			tostring(Capabilities.TransitionsActive),
			Capabilities.LiveShadowCount())
	end)
	folder.Parent = ReplicatedStorage
end

-- ---- overhead billboard (demo on the local player) -------------------

-- Attach a themed nameplate + vitals bars above the local character's head and
-- keep them in sync with the HUD values, so the overhead UI is visible in-play.
-- A game would call these for every player/NPC/mob it wants a plate on.
local function attachOwnOverhead(character: Model)
	-- Wait for the Head so the billboard has something to adorn (the character
	-- may exist before all parts have replicated).
	character:WaitForChild("Head", 5)
	overheadController:Attach(character, { name = player.DisplayName, level = HUDConfig.DefaultValues.level })
	overheadController:SetValues(character, {
		health = HUDConfig.DefaultValues.health,
		mana = HUDConfig.DefaultValues.mana,
	})
end
-- Handle the character whether it already exists or spawns later.
if player.Character then
	task.spawn(attachOwnOverhead, player.Character)
end
player.CharacterAdded:Connect(attachOwnOverhead)

-- Live-ticking timer to show HUD updates working.
task.spawn(function()
	local timer = HUDConfig.DefaultValues.timer
	while true do
		task.wait(1)
		timer = timer > 0 and timer - 1 or 90
		hud:Update({ values = { timer = timer } })
	end
end)

-- Kick off onboarding on join.
if DevConfig.AutoStartTutorial then
	task.delay(1, function()
		screenController:ShowScreen("tutorial", {
			steps = TutorialConfig.Steps,
			onComplete = function()
				hud:PushToast({ text = "Tutorial complete! Press B for the shop, T for the Theme Editor.", variant = "Success", duration = 5 })
			end,
		})
	end)
end

print("[ClientHandler] rblx_ui client booted — themes:", #themeController:GetThemeList(), "packs:", #themeController:GetPackList())
