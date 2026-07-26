--!strict
-- Plays UI sounds by abstract event name from the active sound pack, and owns
-- the two doc-§6 behaviours:
--   * ONE global UI click auto-hooked onto Activated of every current AND
--     future GuiButton under PlayerGui (AttachGlobalClick) — no per-UI wiring.
--   * Music that crossfades (~1.2s) between lobby tracks, never hard cuts
--     (StartMusic).
-- One pooled Sound instance per event is reused, so there's no per-click
-- allocation. Swapping packs (SetPack) just re-points the pooled sounds; the
-- "Muted" pack yields no sounds without any special-casing.

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local UISoundConfig = require(script.Parent.Parent.Config.UISoundConfig)

local UISoundController = {}
UISoundController.__index = UISoundController

function UISoundController.new(packId: string?)
	local self = setmetatable({}, UISoundController)
	self._folder = Instance.new("Folder")
	self._folder.Name = "UISounds"
	self._folder.Parent = SoundService
	self._sounds = {} :: { [string]: Sound }
	self._pack = nil :: any
	self:SetPack(packId or UISoundConfig.DefaultPackId)
	return self
end

-- Build/refresh one pooled Sound per event for the chosen pack.
function UISoundController:SetPack(packId: string)
	local pack = UISoundConfig.GetById(packId)
	if not pack then
		return
	end
	self._pack = pack
	for _, sound in self._sounds do
		sound:Destroy()
	end
	self._sounds = {}
	for event, def in pack.Events do
		local sound = Instance.new("Sound")
		sound.Name = event
		sound.SoundId = def.id
		sound.Volume = def.volume
		sound.PlaybackSpeed = def.pitch
		sound.Parent = self._folder
		self._sounds[event] = sound
	end
end

function UISoundController:GetPackId(): string
	return self._pack and self._pack.Id or "Muted"
end

-- Play a UI event sound. Unknown events / the Muted pack are silent no-ops.
function UISoundController:Play(event: string)
	local sound = self._sounds[event]
	if sound then
		-- Restart so rapid repeats (fast clicks) always retrigger.
		sound.TimePosition = 0
		sound:Play()
	end
end

-- The doc-§6 global click: hook Activated of every GuiButton currently under
-- PlayerGui and every one added later. Buttons never wire their own click
-- sound — the whole game has literally one button sound.
function UISoundController:AttachGlobalClick(playerGui: Instance)
	local function hook(instance: Instance)
		if instance:IsA("GuiButton") then
			(instance :: GuiButton).Activated:Connect(function()
				self:Play("Click")
			end)
		end
	end
	for _, descendant in playerGui:GetDescendants() do
		hook(descendant)
	end
	playerGui.DescendantAdded:Connect(hook)
end

-- Cycle the lobby tracks with a crossfade — music swings over ~1.2s, never
-- cuts (doc §6). Fire-and-forget; safe to call once at boot.
function UISoundController:StartMusic()
	local trackIds = UISoundConfig.MusicTracks
	if #trackIds == 0 then
		return
	end
	local volume = UISoundConfig.MusicVolume
	local fade = UISoundConfig.MusicCrossfade
	local folder = self._folder

	task.spawn(function()
		local index = 1
		local current: Sound? = nil
		while folder.Parent do
			local sound = Instance.new("Sound")
			sound.Name = "Music" .. index
			sound.SoundId = trackIds[index]
			sound.Volume = 0
			sound.Parent = folder
			sound:Play()
			TweenService:Create(sound, TweenInfo.new(fade), { Volume = volume }):Play()
			if current then
				local old = current
				TweenService:Create(old, TweenInfo.new(fade), { Volume = 0 }):Play()
				task.delay(fade + 0.1, function()
					old:Destroy()
				end)
			end
			current = sound
			sound.Ended:Wait()
			index = index % #trackIds + 1
		end
	end)
end

return UISoundController
