--!strict
-- Zone entry banner (HUD widget): Show(name, subtitle) pops a centred BOXLESS
-- title — zone name FredokaOne 54 gold with the full black outline, subtitle
-- 20 ice blue — no panel, no dim; the outline is what lets it sit over any
-- scene (doc §2).
--
-- Entrance is a letter-spaced MaxVisibleGraphemes reveal at a constant
-- characters-per-second rate (so "KILN HOLLOW" and a long zone name pace the
-- same), the subtitle follows the title, the banner holds 2.5s fully revealed
-- and then HARD-HIDES (doc §5 — no exit fade). Show() calls queue: two zone
-- lines never overlap, the second simply plays after the first finishes.
--
-- Engine landmine: MaxVisibleGraphemes is silently ignored on RichText labels,
-- and UIStyler.TextLabel defaults RichText on — both labels turn it off.

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local HUDWidgetBase = require(script.Parent.HUDWidgetBase)
local GPHUDStyle = require(script.Parent.GPHUDStyle)

local ZoneBannerWidget = setmetatable({}, { __index = HUDWidgetBase })
ZoneBannerWidget.__index = ZoneBannerWidget

local TITLE_CPS = 24 -- title reveal, characters per second
local SUB_CPS = 45
local HOLD = 2.5

function ZoneBannerWidget.new()
	local self = HUDWidgetBase.new("zoneBanner", "ZoneBannerWidget")
	self._queue = {} :: { any }
	self._active = nil :: any
	self._titleShown = -1
	self._subShown = -1
	return setmetatable(self, ZoneBannerWidget)
end

function ZoneBannerWidget:_Build(props: HUDWidgetBase.Props)
	local theme = self.Theme

	local banner = UIStyler.Frame("Banner")
	banner.BackgroundTransparency = 1
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.3)
	banner.Size = UDim2.fromOffset(1000, 110)
	banner.Visible = false
	banner.ZIndex = 2
	banner.Parent = self.Root
	self._banner = banner

	local title = UIChrome.Text("Zone", 54, theme.Arcade.Gold)
	title.RichText = false -- MaxVisibleGraphemes needs this off
	title.Size = UDim2.new(1, 0, 0, 62)
	title.ZIndex = 2
	title.Parent = banner
	self._title = title

	local subtitle = UIChrome.Text("Subtitle", 20, theme.Arcade.IceBlue)
	subtitle.RichText = false
	subtitle.Position = UDim2.fromOffset(0, 66)
	subtitle.Size = UDim2.new(1, 0, 0, 26)
	subtitle.ZIndex = 2
	subtitle.Parent = banner
	self._subtitle = subtitle

	self:_RenderStep(function(_dt: number, clock: number)
		self:_Step(clock)
	end)

	-- Demo: announce a zone on spawn so the widget shows itself standalone.
	if props.zone ~= false then
		self:Show((props.zone :: string?) or "KILN HOLLOW", props.subtitle or "The old firing grounds")
	end
end

-- ---- API ---------------------------------------------------------------

-- data: { zone = "NAME", subtitle = "..." }
function ZoneBannerWidget:Update(data: any)
	if type(data) == "string" then
		self:Show(data)
		return
	end
	if type(data) ~= "table" then
		return
	end
	local name = data.zone or data.name
	if name then
		self:Show(name, data.subtitle)
	end
end

function ZoneBannerWidget:Show(name: string, subtitle: string?)
	local titleLen = utf8.len(name) or #name
	local subLen = if subtitle then (utf8.len(subtitle) or #subtitle) else 0
	table.insert(self._queue, {
		name = name,
		subtitle = subtitle,
		titleLen = titleLen,
		subLen = subLen,
		titleTime = titleLen / TITLE_CPS,
		subTime = subLen / SUB_CPS,
		start = 0,
	})
	if not self._active then
		self:_StartNext()
	end
end

function ZoneBannerWidget:_StartNext()
	local nextItem = table.remove(self._queue, 1)
	if not nextItem then
		self._banner.Visible = false -- hard-hide, no exit fade (doc §5)
		return
	end
	self._active = nextItem
	nextItem.start = os.clock()
	self._titleShown = -1
	self._subShown = -1
	self._title.Text = nextItem.name
	self._title.MaxVisibleGraphemes = 0
	self._subtitle.Text = nextItem.subtitle or ""
	self._subtitle.Visible = (nextItem.subtitle or "") ~= ""
	self._subtitle.MaxVisibleGraphemes = 0
	self._banner.Visible = true
	self:_PopIn(self._banner)
end

-- ---- per-frame ---------------------------------------------------------

function ZoneBannerWidget:_Step(clock: number)
	local active = self._active
	if not active then
		return
	end
	local elapsed = clock - active.start

	local shown = math.clamp(math.floor(elapsed * TITLE_CPS), 0, active.titleLen)
	if shown ~= self._titleShown then
		self._titleShown = shown
		self._title.MaxVisibleGraphemes = shown
	end

	if active.subLen > 0 then
		local subShown = math.clamp(math.floor((elapsed - active.titleTime) * SUB_CPS), 0, active.subLen)
		if subShown ~= self._subShown then
			self._subShown = subShown
			self._subtitle.MaxVisibleGraphemes = subShown
		end
	end

	if elapsed >= active.titleTime + active.subTime + HOLD then
		self._active = nil
		self:_StartNext() -- hides the banner when the queue is empty
	end
end

-- BOXLESS by design: no panel, no dim, the outline is what lets a zone name sit
-- over any scene (doc §2). GIRLY POP bans that outline, so the same job is done
-- by the pack's own halo — a deepened tint of each line's own colour. The
-- subtitle additionally moves off the pack's soft plum (which reads on cream and
-- disappears over a night sky) onto its warm cream, so both lines carry.
-- The letter-spaced reveal, the pacing, the 2.5s hold, the hard-hide and the
-- Show() queue are all untouched.
function ZoneBannerWidget:_Style(theme: Types.UITheme)
	if self._title then
		self._title.FontFace = theme.Fonts.Title
		self._title.TextColor3 = theme.Arcade.Gold
		GPHUDStyle.Halo(theme, self._title)
	end
	if self._subtitle then
		self._subtitle.FontFace = theme.Fonts.Button
		self._subtitle.TextColor3 = GPHUDStyle.SkyInk(theme, theme.Arcade.IceBlue)
		GPHUDStyle.Halo(theme, self._subtitle)
	end
end

return ZoneBannerWidget
