--!strict
-- Cross-platform input bindings. Actions are abstract ("ToggleShop"); this maps
-- each to keyboard keys and gamepad buttons. UIInputController consumes it so
-- screens never hardcode a KeyCode. Add a binding here to wire a new hotkey.

local InputConfig = {}

export type ActionBinding = {
	keyboard: { Enum.KeyCode },
	gamepad: { Enum.KeyCode },
}

InputConfig.Actions = {
	-- B belongs to the build palette (HotbarScreen binds it per the builder-
	-- genre spec), so the shop's keyboard hotkey lives on P; gamepad keeps Y.
	ToggleShop = { keyboard = { Enum.KeyCode.P }, gamepad = { Enum.KeyCode.ButtonY } },
	ToggleThemeEditor = { keyboard = { Enum.KeyCode.T }, gamepad = { Enum.KeyCode.ButtonSelect } },
	ToggleHUD = { keyboard = { Enum.KeyCode.H }, gamepad = {} },
	-- Global iconography switch: hides every archive icon and art-slot image
	-- without reflowing layout (see Icons/IconVisibility).
	ToggleIcons = { keyboard = { Enum.KeyCode.Y }, gamepad = {} },
	CloseTop = { keyboard = { Enum.KeyCode.Escape }, gamepad = { Enum.KeyCode.ButtonB } },
	AdvanceTutorial = { keyboard = { Enum.KeyCode.E }, gamepad = { Enum.KeyCode.ButtonA } },
	-- The way IN to the screen library: opens the catalog launcher, which can
	-- open every screen the manifest declares.
	ToggleScreenCatalog = { keyboard = { Enum.KeyCode.Backquote }, gamepad = { Enum.KeyCode.ButtonStart } },
} :: { [string]: ActionBinding }

return InputConfig
