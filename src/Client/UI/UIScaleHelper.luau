--!strict
-- Device scaling (UI_DESIGN_DOCUMENT.md §7.1). Everything is authored at a
-- fixed 1650×1020 px baseline; one shared helper attaches a UIScale to every
-- screen root: scale = clamp(min(viewportX/1650, viewportY/1020), 0.5, 1.6).
--
-- The root frame is simultaneously resized to fromScale(1/s, 1/s) so its
-- effective coverage stays exactly full-screen: children whose POSITIONS use
-- Scale stay glued to true screen edges, while px Offset space shrinks/grows
-- with the viewport — the doc's exact behaviour.

local UIChrome = require(script.Parent.UIChrome)

local UIScaleHelper = {}

local MIN_SCALE = 0.5
local MAX_SCALE = 1.6

function UIScaleHelper.Compute(viewport: Vector2): number
	local scale = math.min(viewport.X / UIChrome.BASE_WIDTH, viewport.Y / UIChrome.BASE_HEIGHT)
	return math.clamp(scale, MIN_SCALE, MAX_SCALE)
end

-- Attach the baseline UIScale to a screen's full-screen root frame and keep
-- it live on viewport resizes. Returns the UIScale plus a Disconnect.
function UIScaleHelper.Attach(root: GuiObject): (UIScale, () -> ())
	local scale = Instance.new("UIScale")
	scale.Name = "BaselineScale"
	scale.Parent = root

	local connection: RBXScriptConnection? = nil

	local function apply()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local s = UIScaleHelper.Compute(camera.ViewportSize)
		scale.Scale = s
		-- Inverse-size so the scaled root still covers the whole screen.
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end

	local camera = workspace.CurrentCamera
	if camera then
		connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
	end
	apply()

	return scale, function()
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end
end

return UIScaleHelper
