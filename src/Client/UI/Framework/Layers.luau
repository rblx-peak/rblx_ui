--!strict
-- The layer stack: one ScreenGui per layer, created once at boot. Screens
-- never create their own ScreenGui — they ask for a layer and parent into it.
-- This is what makes z-ordering a property of the SYSTEM rather than something
-- each screen negotiates (and gets wrong).
--
-- DisplayOrder ladder follows the Pottery spec's §7.3 bands, widened to cover
-- the universal catalog (backdrop/world tints below the HUD, toasts above every
-- panel, cursor and debug above everything).

local Players = game:GetService("Players")

local UIScaleHelper = require(script.Parent.Parent.UIScaleHelper)
local UIStyleEnforcer = require(script.Parent.Parent.UIStyleEnforcer)
local UIStyler = require(script.Parent.Parent.UIStyler)
local Types = require(script.Parent.Parent.Types)

local Layers = {}

export type LayerId =
	"Backdrop" | "HUD" | "Screens" | "Overlay" | "Modal" | "Toast" | "Cursor" | "Debug"

-- name -> { order, ignoreInset }. Ignoring the topbar inset is right for
-- full-bleed art (backdrop, cursor, debug) and wrong for anything the player
-- must be able to reach around the Roblox topbar.
local SPEC: { [string]: { order: number, ignoreInset: boolean } } = {
	Backdrop = { order = 5, ignoreInset = true },
	HUD = { order = 10, ignoreInset = false },
	Screens = { order = 100, ignoreInset = false },
	Overlay = { order = 300, ignoreInset = false },
	Modal = { order = 500, ignoreInset = false },
	Toast = { order = 800, ignoreInset = false },
	Cursor = { order = 900, ignoreInset = true },
	Debug = { order = 9999, ignoreInset = true },
}

local guis: { [string]: ScreenGui } = {}
local roots: { [string]: Frame } = {}
-- One StyleLink per layer ScreenGui (styling applies to all descendants of
-- the link's parent, so per-screen links are unnecessary — one per layer
-- root covers every screen parented into it). Created lazily when a sheet
-- is first assigned; re-pointed on every theme swap.
local links: { [string]: StyleLink } = {}
local activeSheet: StyleSheet? = nil

local function playerGui(): Instance?
	local player = Players.LocalPlayer
	return player and player:FindFirstChildOfClass("PlayerGui")
end

-- Build (or fetch) one layer. Every layer gets the 1650x1020 baseline UIScale
-- and the arcade style enforcer, so anything parented in inherits the house
-- rules without opting in.
function Layers.Get(id: LayerId): Frame
	local existing = roots[id]
	if existing and existing.Parent then
		return existing
	end
	local spec = SPEC[id] or SPEC.Screens

	local gui = Instance.new("ScreenGui")
	gui.Name = "UILayer_" .. id
	gui.DisplayOrder = spec.order
	gui.IgnoreGuiInset = spec.ignoreInset
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = true
	gui.Parent = playerGui()
	guis[id] = gui

	local root = UIStyler.Frame("Root")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	roots[id] = root

	UIScaleHelper.Attach(root)
	-- The Debug layer keeps raw engine styling: dev overlays must stay legible
	-- and cheap, not inherit the arcade bevel/outline sweep.
	if id ~= "Debug" then
		UIStyleEnforcer.Attach(gui, "Arcade" :: Types.UIFamily)
	end
	-- Late-created layers pick up the active pack sheet immediately.
	if activeSheet and id ~= "Debug" then
		local link = Instance.new("StyleLink")
		link.StyleSheet = activeSheet
		link.Parent = gui
		links[id] = link
	end
	return root
end

-- Point every layer at the pack's StyleSheet (native UI Styling). One link
-- per layer ScreenGui; swapping sheets re-points existing links. Inert while
-- the engine has styling application disabled (see Style/Capabilities).
function Layers.SetStyleSheet(sheet: StyleSheet?)
	activeSheet = sheet
	for id, gui in guis do
		if id == "Debug" then
			continue
		end
		local link = links[id]
		if sheet then
			if not link or link.Parent == nil then
				link = Instance.new("StyleLink")
				link.Parent = gui
				links[id] = link
			end
			link.StyleSheet = sheet
		elseif link then
			link:Destroy()
			links[id] = nil
		end
	end
end

function Layers.GetGui(id: LayerId): ScreenGui?
	Layers.Get(id)
	return guis[id]
end

-- Toggle a whole layer (e.g. hide the HUD during a cinematic or a focused
-- walk-up UI — doc §11.5 "focused moments disable the HUD").
function Layers.SetVisible(id: LayerId, visible: boolean)
	local gui = Layers.GetGui(id)
	if gui then
		gui.Enabled = visible
	end
end

function Layers.IsVisible(id: LayerId): boolean
	local gui = guis[id]
	return gui ~= nil and gui.Enabled
end

-- Create every layer up-front so DisplayOrder conflicts surface at boot rather
-- than the first time some screen happens to open.
function Layers.Init()
	for id in SPEC do
		Layers.Get(id :: LayerId)
	end
end

function Layers.Destroy()
	for _, gui in guis do
		gui:Destroy()
	end
	table.clear(guis)
	table.clear(roots)
end

return Layers
