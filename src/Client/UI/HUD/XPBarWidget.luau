--!strict
-- XP meter (HUD widget): circular gold-ringed level badge + the §8 gold ruler
-- + a "1,240 / 2,000" readout.
--
-- The ruler is UIProgressBarComponent, not a hand-built bar — the ticks, the
-- near-black track and the sunburst-gold fill are that component's whole job,
-- and reusing it means the XP bar and every other meter in the game measure
-- with the same instrument (doc §8).
--
-- Level-up is the one choreographed moment: the badge pulses (1.14 spike,
-- §5.1 PULSE) and the ruler flashes white, because a number quietly resetting
-- to zero is indistinguishable from a bug.

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIProgressBarComponent = require(script.Parent.Parent.Components.UIProgressBarComponent)
local HUDWidgetBase = require(script.Parent.HUDWidgetBase)
local GPHUDStyle = require(script.Parent.GPHUDStyle)

local XPBarWidget = setmetatable({}, { __index = HUDWidgetBase })
XPBarWidget.__index = XPBarWidget

local BADGE = 46
local GAP = 10
local RULER_H = 20
local FLASH_IN = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_OUT = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function XPBarWidget.new()
	local self = HUDWidgetBase.new("xp", "XPBarWidget")
	self._level = 12
	self._value = 1240
	self._max = 2000
	return setmetatable(self, XPBarWidget)
end

function XPBarWidget:_Build(_props: HUDWidgetBase.Props)
	local theme = self.Theme
	local width = self.Root.Size.X.Offset
	local columnX = BADGE + GAP
	local columnW = math.max(width - columnX, 120)

	-- Circular badge: "Pill" is the arcade's only sanctioned round corner
	-- (doc §4.2 — win pips, avatar heads), and the gold ring is the house
	-- selection stroke (§4.3 selection is a RING, never a fill change).
	local badge = UIStyler.Frame("LevelBadge")
	badge.Size = UDim2.fromOffset(BADGE, BADGE)
	badge.AnchorPoint = Vector2.new(0, 1)
	badge.Position = UDim2.new(0, 0, 1, 0)
	UIChrome.Corner("Arcade", "Pill").Parent = badge
	self._badgeRing = UIChrome.Stroke(theme, "Arcade", "Selection")
	self._badgeRing.Parent = badge
	UIChrome.GlassGradient().Parent = badge
	badge.Parent = self.Root
	self._badge = badge

	local levelText = UIChrome.Text("Level", 22, Color3.new(1, 1, 1))
	levelText.Size = UDim2.fromScale(1, 1)
	levelText.ZIndex = 2
	levelText.Parent = badge
	self._levelText = levelText

	local caption = UIChrome.BodyText("Caption", 14, theme.Arcade.IceBlue)
	caption.Text = "EXPERIENCE"
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Position = UDim2.fromOffset(columnX, 0)
	caption.Size = UDim2.fromOffset(columnW * 0.5, 20)
	caption.Parent = self.Root
	self._caption = caption

	local readout = UIChrome.Text("Readout", 16, theme.Arcade.Gold)
	readout.TextXAlignment = Enum.TextXAlignment.Right
	readout.Position = UDim2.fromOffset(columnX + columnW * 0.5, 0)
	readout.Size = UDim2.fromOffset(columnW * 0.5, 20)
	readout.Parent = self.Root
	self._readout = readout

	local ruler = UIProgressBarComponent.new()
	ruler:Create(self.Root, {
		value = self._value,
		maxValue = self._max,
		size = UDim2.fromOffset(columnW, RULER_H),
		position = UDim2.fromOffset(columnX, BADGE - RULER_H),
	})
	self._ruler = ruler

	-- Level-up flash overlay, sized over the ruler. Transparency animation is
	-- the sanctioned effect-overlay exception to the no-fades rule (doc §5).
	local flash = UIStyler.Frame("LevelFlash")
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.Position = UDim2.fromOffset(columnX, BADGE - RULER_H)
	flash.Size = UDim2.fromOffset(columnW, RULER_H)
	flash.ZIndex = 6
	flash.Parent = self.Root
	self._flash = flash

	self:_Render()
end

-- data: { level, xp, xpToNext } | { level, value, max }.
function XPBarWidget:Update(data: any)
	if type(data) ~= "table" then
		return
	end
	self:SetXP(
		data.level or self._level,
		data.xp or data.value or self._value,
		data.xpToNext or data.max or data.maxValue or self._max
	)
end

function XPBarWidget:SetXP(level: number, value: number, max: number?)
	local leveledUp = level > self._level
	self._level = level
	if max and max > 0 then
		self._max = max
	end
	self._value = math.clamp(value, 0, self._max)
	self:_Render()
	if leveledUp then
		self:LevelUp()
	end
end

function XPBarWidget:LevelUp()
	if self._badge then
		self:_Pulse(self._badge)
	end
	local flash = self._flash
	if not flash then
		return
	end
	local up = self:_Tween(flash, FLASH_IN, { BackgroundTransparency = 0.15 })
	up.Completed:Once(function()
		if flash.Parent then
			self:_Tween(flash, FLASH_OUT, { BackgroundTransparency = 1 })
		end
	end)
end

function XPBarWidget:_Render()
	if self._levelText then
		self._levelText.Text = tostring(math.floor(self._level))
	end
	if self._readout then
		self._readout.Text = string.format(
			"%s / %s",
			HUDWidgetBase.Commas(self._value),
			HUDWidgetBase.Commas(self._max)
		)
	end
	if self._ruler then
		self._ruler:Set(self._value, self._max)
	end
end

function XPBarWidget:_Style(theme: Types.UITheme)
	local arcade = theme.Arcade
	if self._badge then
		self._badge.BackgroundColor3 = arcade.NearBlack
	end
	if self._badgeRing then
		self._badgeRing.Color = theme.Semantic.Selection
	end
	if self._levelText then
		self._levelText.FontFace = theme.Fonts.Numeric
		self._levelText.TextColor3 = theme.Colors.TextPrimary
		UIChrome.TextOutline(self._levelText)
	end
	if self._caption then
		self._caption.FontFace = theme.Fonts.Body
		self._caption.TextColor3 = arcade.IceBlue
	end
	if self._readout then
		self._readout.FontFace = theme.Fonts.Numeric
		self._readout.TextColor3 = arcade.Gold
		UIChrome.TextOutline(self._readout)
	end
	-- The ruler is a component: it repaints itself from the same theme (and
	-- self-registers for live swaps when a controller exists).
	if self._ruler then
		self._ruler:ApplyTheme(theme)
	end

	-- GIRLY POP: the level badge is a glazed button of clay — already round in
	-- every pack, so only its weight changes: translucent so the world reads
	-- through, a rose selection ring the widget still owns, and a soft shadow
	-- lifting it off the scene. The caption drops out of caps (law 5) without
	-- losing a word, and the level-up flash swaps pure white — which this pack
	-- bans outright — for warm cream. The badge, the caption, the "1,240 / 2,000"
	-- readout and the ruler all stay: nothing here loses a figure.
	if self._caption then
		self._caption.Text = GPHUDStyle.Copy(theme, "Experience", "EXPERIENCE")
	end
	if self._flash then
		self._flash.BackgroundColor3 = if GPHUDStyle.Active(theme) then theme.Colors.Background else Color3.new(1, 1, 1)
	end
	GPHUDStyle.Surface(theme, self._badge, {
		transparency = GPHUDStyle.Chip,
		keepCorner = true,
		stroke = true,
		strokeIntent = "Selection",
		strokeKeepColor = true,
		shadow = "sm",
		sink = self._shadows,
	})
	GPHUDStyle.Halo(theme, self._levelText)
	GPHUDStyle.Halo(theme, self._readout)
end

function XPBarWidget:Destroy()
	if self._ruler then
		self._ruler:Destroy()
		self._ruler = nil
	end
	HUDWidgetBase.Destroy(self)
end

return XPBarWidget
