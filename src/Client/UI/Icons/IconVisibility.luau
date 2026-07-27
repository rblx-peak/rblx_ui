--!strict
-- IconVisibility — the global "icons on/off" switch (bound to Y by default,
-- see InputConfig.ToggleIcons).
--
-- WHY A TAG AND NOT A WALK: icons are created continuously — screens build
-- lazily, rows pool and repool, and a style change rebuilds whole screens. A
-- one-shot sweep would only catch what existed at the moment it ran, so newly
-- built icons would come back visible while the toggle still said "off".
-- Every icon is TAGGED at creation instead, and this module drives the tag:
--   * flipping the switch repaints every currently tagged instance;
--   * GetInstanceAddedSignal repaints anything created later, so the state
--     survives screen rebuilds, pooling, and theme swaps for free.
--
-- Icons hide by TRANSPARENCY, never by Visible or by clearing Image: layout
-- must not reflow when icons go away (a hidden icon still occupies its slot,
-- so nothing shifts), and the original asset id is preserved so turning them
-- back on needs no re-resolution.

local CollectionService = game:GetService("CollectionService")

local UISignal = require(script.Parent.Parent.UISignal)

local IconVisibility = {}

-- Canonical tag. Anything wearing it is treated as decorative iconography.
IconVisibility.TAG = "UIIcon"

IconVisibility.Changed = UISignal.new()

local enabled = true
local listening = false

local function paint(instance: Instance, on: boolean)
	if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		local image = instance :: any
		if on then
			-- Restore the transparency the icon was built with (0 unless the
			-- creator deliberately faded it).
			local original = image:GetAttribute("IconRestTransparency")
			image.ImageTransparency = typeof(original) == "number" and original or 0
		else
			if image:GetAttribute("IconRestTransparency") == nil then
				image:SetAttribute("IconRestTransparency", image.ImageTransparency)
			end
			image.ImageTransparency = 1
		end
	elseif instance:IsA("TextLabel") or instance:IsA("TextButton") then
		-- Glyph fallbacks (the archive emits a text glyph when an asset is
		-- missing) hide the same way.
		local label = instance :: any
		if on then
			local original = label:GetAttribute("IconRestTransparency")
			label.TextTransparency = typeof(original) == "number" and original or 0
		else
			if label:GetAttribute("IconRestTransparency") == nil then
				label:SetAttribute("IconRestTransparency", label.TextTransparency)
			end
			label.TextTransparency = 1
		end
	end
end

-- Tag an instance as an icon. Safe to call repeatedly; applies the CURRENT
-- state immediately so an icon built while icons are off is born hidden.
function IconVisibility.Register(instance: Instance)
	if not instance:IsDescendantOf(game) and instance.Parent == nil then
		-- Still fine: the added-signal listener will paint it when parented.
	end
	CollectionService:AddTag(instance, IconVisibility.TAG)
	if not enabled then
		paint(instance, false)
	end
end

function IconVisibility.IsEnabled(): boolean
	return enabled
end

function IconVisibility.Set(on: boolean)
	if on == enabled then
		return
	end
	enabled = on
	for _, instance in CollectionService:GetTagged(IconVisibility.TAG) do
		paint(instance, on)
	end
	IconVisibility.Changed:Fire(on)
end

function IconVisibility.Toggle(): boolean
	IconVisibility.Set(not enabled)
	return enabled
end

-- Start watching for icons created after a toggle. Called once at boot.
function IconVisibility.Init()
	if listening then
		return
	end
	listening = true
	CollectionService:GetInstanceAddedSignal(IconVisibility.TAG):Connect(function(instance)
		if not enabled then
			paint(instance, false)
		end
	end)
end

return IconVisibility
