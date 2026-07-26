--!strict
-- UI sound (UI_DESIGN_DOCUMENT.md §6): ONE global UI click —
-- rbxassetid://88442833509532 at volume 0.5 — auto-hooked onto Activated of
-- every current and future GuiButton under PlayerGui (see UISoundController.
-- AttachGlobalClick). The whole game has literally one button sound.
--
-- The pack/event structure survives (packs are swappable, Play(unknown) is a
-- silent no-op — that's how "Muted" works), but the Pottery pack maps ONLY
-- Click; Hover/Open/Close/Success/Error are deliberately silent.

local UISoundConfig = {}

export type SoundDef = { id: string, volume: number, pitch: number }
export type SoundPack = {
	Id: string,
	DisplayName: string,
	Events: { [string]: SoundDef },
}

-- The one global UI click (doc §6).
UISoundConfig.ClickSoundId = "rbxassetid://88442833509532"

-- Lobby music, cycled with ~1.2s crossfades (doc §6) — never hard cuts.
UISoundConfig.MusicTracks = {
	"rbxassetid://132319769870114",
	"rbxassetid://125586394550795",
}
UISoundConfig.MusicVolume = 0.35
UISoundConfig.MusicCrossfade = 1.2

UISoundConfig.DefaultPackId = "Pottery"

UISoundConfig.Packs = {
	{
		Id = "Pottery",
		DisplayName = "Pottery Clash",
		Events = {
			Click = { id = UISoundConfig.ClickSoundId, volume = 0.5, pitch = 1.0 },
		},
	},
	-- Silent pack — drop-in mute without touching call sites.
	{
		Id = "Muted",
		DisplayName = "Muted",
		Events = {},
	},
} :: { SoundPack }

function UISoundConfig.GetById(id: string): SoundPack?
	for _, pack in UISoundConfig.Packs do
		if pack.Id == id then
			return pack
		end
	end
	return nil
end

return UISoundConfig
