--!strict
-- The style enforcer (UI_DESIGN_DOCUMENT.md §4.1.3): a DescendantAdded sweep
-- per ScreenGui that backstops anything hand-built so no caller can deviate
-- from the arcade ruleset:
--
--   * every text object → black text stroke at 0 transparency;
--   * every solid button missing a stroke → 2px black stroke;
--   * every solid button missing a gradient → the arcade bevel (vertical
--     white → RGB(140,140,140) multiply).
--
-- Studio-family screens (the ceramic booth) keep the softer grammar: only
-- DISPLAY-font (FredokaOne) text gets the outline — quiet GothamMedium body
-- text stays clean — and no strokes/bevels are forced onto buttons.

local Types = require(script.Parent.Types)
local UIChrome = require(script.Parent.UIChrome)

local UIStyleEnforcer = {}

local BLACK = Color3.new(0, 0, 0)

local function isTextObject(instance: Instance): boolean
	return instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")
end

local function isDisplayFont(instance: Instance): boolean
	local ok, family = pcall(function()
		return (instance :: any).FontFace.Family
	end)
	return ok and typeof(family) == "string" and string.find(family, "FredokaOne", 1, true) ~= nil
end

local function enforce(instance: Instance, family: Types.UIFamily)
	local chrome = UIChrome.ActiveChrome()
	if isTextObject(instance) then
		if family == "Arcade" or isDisplayFont(instance) then
			-- Outline vs glow is decided by the active STYLE inside
			-- UIChrome.TextOutline — the enforcer just opts the object in.
			UIChrome.TextOutline(instance)
		end
		-- Buttons fall through: a solid TextButton needs chrome too.
	end
	if family ~= "Arcade" then
		return
	end
	if instance:IsA("GuiButton") and (instance :: GuiButton).BackgroundTransparency < 1 then
		local button = instance :: GuiButton
		if not button:FindFirstChildOfClass("UIStroke") then
			local stroke = Instance.new("UIStroke")
			-- Backstop stroke follows the style: black 2px classic, or the
			-- style's own hairline weight (colour stays neutral — accents
			-- come from deliberate UIChrome.Stroke calls, not the backstop).
			stroke.Color = BLACK
			stroke.Thickness = chrome.TextOutline and 2 or chrome.StrokeThickness
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = button
		end
		if chrome.Bevel and not button:FindFirstChildOfClass("UIGradient") then
			UIChrome.ArcadeBevel().Parent = button
		end
	end
end

-- Sweep everything already under the gui, then watch every new descendant.
-- Deferred a frame on add so the creator's own styling (font, transparency)
-- lands first and the enforcer judges the finished object.
function UIStyleEnforcer.Attach(gui: ScreenGui, family: Types.UIFamily?): RBXScriptConnection
	local fam: Types.UIFamily = family or "Arcade"
	for _, descendant in gui:GetDescendants() do
		enforce(descendant, fam)
	end
	return gui.DescendantAdded:Connect(function(descendant)
		task.defer(function()
			if descendant.Parent then
				enforce(descendant, fam)
			end
		end)
	end)
end

return UIStyleEnforcer
