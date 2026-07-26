--!strict
-- Configures the floating nav rail — the on-screen shortcut buttons (open shop,
-- theme editor, help, …) that behave like a regular game's "open shop" GUI
-- buttons. Everything about their look and placement is data here: button size,
-- shape, spacing, which corner/side the rail hugs, and the per-button list.
--
-- The rail's side/vertical anchor still comes from the active pack (pack.Nav) so
-- packs can relocate it for a different feel; this config layers the *geometry*
-- (size/spacing/offset) and the *button set* on top. Change a size or add a
-- button here — no handler code edits.

local NavConfig = {}

-- Design resolution every fraction below is authored against (matches
-- UIScreenBase's own design resolution) — SizeFor/geometry below convert these
-- into pure Scale fractions of the REAL viewport, so the rail's buttons/gaps
-- shrink and grow with the screen exactly like the reference MainGui does,
-- instead of staying a constant physical pixel size at any viewport.
NavConfig.DesignWidth = 1280
NavConfig.DesignHeight = 720

-- Rail geometry, authored in DESIGN-SPACE pixels (at DesignWidth x DesignHeight)
-- then converted to Scale fractions by SizeFor/UINavRailController — never used
-- as raw Offset pixels directly. ButtonSize is the SQUARE size for icon-only
-- buttons; LabeledButtonSize is the wider size for any button with a text
-- `label`. FillDirection lets the rail be a vertical column or horizontal bar.
NavConfig.ButtonSize = Vector2.new(56, 56)
NavConfig.LabeledButtonSize = Vector2.new(150, 46)
NavConfig.Spacing = 10
NavConfig.EdgeOffset = 12 -- design-space gap from the screen edge
NavConfig.FillDirection = "Vertical" :: "Vertical" | "Horizontal"

-- Global toggle: DEFAULT false = the rail is compact icon-only SQUARES, each with
-- an emoji placeholder (the normal "open shop" GUI-button look). Flip to true to
-- opt the whole rail into the wider labelled buttons instead. Individual buttons
-- keep their `label`/`iconId` data either way; this just decides if labels show.
NavConfig.ShowLabels = true

-- Per-button definitions. Each button can show an emoji `icon`, an `iconId`
-- image, a text `label`, or any combination — that's the "emoji, text, or
-- both" the rail supports out of the box:
--   icon only            -> { icon = "🛒" }
--   text only            -> { label = "Shop" }
--   icon + text          -> { icon = "🛒", label = "Shop" }
--   image (asset) + text -> { iconId = "rbxassetid://123", label = "Shop" }
-- `id` is stable (a highlight target for the tutorial), `action` names what it
-- does (the handler maps these), `authorizedOnly` hides dev tools from live
-- players. A button is icon-only (square) unless it has a `label` AND
-- ShowLabels is on, in which case it uses LabeledButtonSize.
export type NavButton = {
	id: string,
	action: string,
	-- Content: any mix of these three (at least one). icon = emoji placeholder,
	-- iconId = image asset id, label = text shown beside/instead of the icon.
	icon: string?,
	iconId: string?,
	label: string?,
	authorizedOnly: boolean?,
	-- Optional per-button size override (e.g. a bigger primary shop button).
	size: Vector2?,
	variant: string?,
}

NavConfig.Buttons = {
	-- All buttons are COLORED nested boxes (no Ghost/light) so the rail reads as
	-- the boxy reference look — distinct colour per action.
	{ id = "nav.shop", icon = "🛒", label = "Shop", action = "ToggleShop", variant = "Primary" },
	{ id = "nav.settings", icon = "⚙️", label = "Settings", action = "ToggleSettings", variant = "Accent" },
	{ id = "nav.theme", icon = "🎨", label = "Theme Editor", action = "ToggleThemeEditor", authorizedOnly = true, variant = "Secondary" },
	{ id = "nav.help", icon = "❓", label = "Help", action = "ShowTutorial", variant = "Success" },
} :: { NavButton }

-- The size a button should render at: the wide labelled size when labels are on
-- AND it has a label, else its square override or the default square size.
-- `showLabels` lets a layout preset override the NavConfig global per rebuild;
-- pass nil to use the global.
function NavConfig.SizeFor(button: NavButton, showLabels: boolean?): Vector2
	local labelsOn = showLabels
	if labelsOn == nil then
		labelsOn = NavConfig.ShowLabels
	end
	if labelsOn and button.label and button.label ~= "" then
		return NavConfig.LabeledButtonSize
	end
	return button.size or NavConfig.ButtonSize
end

-- Converts a design-space X pixel value (authored at DesignWidth) into a Scale
-- fraction of the real viewport width — the pure-Scale counterpart to using
-- the value as a raw Offset. Used for anything measured along the horizontal
-- axis (button widths, horizontal spacing/edge offsets).
function NavConfig.ScaleX(designPx: number): number
	return designPx / NavConfig.DesignWidth
end

-- Same as ScaleX but for the vertical axis (button heights, vertical spacing/
-- edge margins), converted against DesignHeight.
function NavConfig.ScaleY(designPx: number): number
	return designPx / NavConfig.DesignHeight
end

return NavConfig
