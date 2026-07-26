--!strict
-- Dev-only flags. Gates the Theme Editor / selector behind a keybind or a
-- userId allowlist so it doesn't ship to live players. During MVP everything
-- is on; tighten before release by setting ThemeEditorEnabled = false or
-- filling AuthorizedUserIds.

local DevConfig = {}

-- Master switch for the in-game Theme Editor + selector.
DevConfig.ThemeEditorEnabled = true

-- If non-empty, only these userIds may open the Theme Editor (even when the
-- keybind fires). Empty = allow everyone (MVP default).
DevConfig.AuthorizedUserIds = {} :: { number }

-- Show the floating nav rail. OFF now that the RefHUD icon rail (Store / Index /
-- Settings on the HUD itself) provides those shortcuts — a separate rail would
-- duplicate them. (Theme Editor stays reachable via its hotkey.)
DevConfig.ShowNavRail = false

-- Auto-start the tutorial on join.
-- Off: the tutorial lives in the screen dock now, and auto-popping it over
-- every session got in the way of actually looking at the UI.
DevConfig.AutoStartTutorial = false

function DevConfig.IsAuthorized(userId: number): boolean
	if not DevConfig.ThemeEditorEnabled then
		return false
	end
	if #DevConfig.AuthorizedUserIds == 0 then
		return true
	end
	return table.find(DevConfig.AuthorizedUserIds, userId) ~= nil
end

return DevConfig
