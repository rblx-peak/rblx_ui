--!strict
-- Ammo block (HUD widget, shipped disabled — a shooter flips it on in
-- HUDManifest): bottom-right arcade box with the weapon icon, a big FredokaOne
-- 44 mag count and the "/ 120" reserve in ice blue on a shared baseline.
--
-- States, all in place (§11.2 — never reflow the block):
--   low   — mag under 25% flashes the count toward red on a sine
--   empty — count locks red and a red RELOAD chip pops above the box
--   reload — Update({reloading = duration}) runs a thin gold ruler under the
--           numbers that fills over the duration then SNAPS away (no fade)
--
-- The count/reserve labels only rewrite on Update — the per-frame work is the
-- flash colour and the sweep width, both gated through _RenderStep.

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local HUDWidgetBase = require(script.Parent.HUDWidgetBase)

local AmmoWidget = setmetatable({}, { __index = HUDWidgetBase })
AmmoWidget.__index = AmmoWidget

local LOW_FRACTION = 0.25
local MAG_SIZE_TEXT = 44
local RESERVE_SIZE_TEXT = 22

function AmmoWidget.new()
	local self = HUDWidgetBase.new("ammo", "AmmoWidget")
	self._mag = 17
	self._magSize = 30
	self._reserve = 120
	self._reloadDuration = nil :: number?
	self._reloadStart = 0
	self._wasLow = false
	return setmetatable(self, AmmoWidget)
end

function AmmoWidget:_Build(props: HUDWidgetBase.Props)
	local theme = self.Theme
	if props.mag ~= nil then
		self._mag = props.mag
	end
	if props.magSize then
		self._magSize = props.magSize
	end
	if props.reserve ~= nil then
		self._reserve = props.reserve
	end

	local box = UIChrome.Panel(theme, "Arcade", "Box")
	box.Size = UDim2.fromScale(1, 1)
	box.Parent = self.Root
	self._box = box

	self._icon = IconArchive.Image(box, props.weaponIcon or "target", 44)
	self._icon.Position = UDim2.fromOffset(14, 20)
	self._icon.ZIndex = 2

	-- Both number labels bottom-align into boxes ending on the same y, so the
	-- big count and the small reserve share a baseline.
	local mag = UIChrome.Text("Mag", MAG_SIZE_TEXT, theme.Colors.TextPrimary)
	mag.TextXAlignment = Enum.TextXAlignment.Right
	mag.TextYAlignment = Enum.TextYAlignment.Bottom
	mag.Position = UDim2.fromOffset(64, 8)
	mag.Size = UDim2.fromOffset(104, 54)
	mag.ZIndex = 2
	mag.Parent = box
	self._magLabel = mag

	local reserve = UIChrome.Text("Reserve", RESERVE_SIZE_TEXT, theme.Arcade.IceBlue)
	reserve.TextXAlignment = Enum.TextXAlignment.Left
	reserve.TextYAlignment = Enum.TextYAlignment.Bottom
	reserve.Position = UDim2.fromOffset(174, 26)
	reserve.Size = UDim2.fromOffset(76, 36)
	reserve.ZIndex = 2
	reserve.Parent = box
	self._reserveLabel = reserve

	local track = UIStyler.Frame("ReloadTrack")
	track.BackgroundColor3 = theme.Arcade.RulerTrack
	track.Position = UDim2.fromOffset(64, 70)
	track.Size = UDim2.fromOffset(184, 6)
	track.Visible = false
	track.ZIndex = 2
	track.Parent = box
	self._track = track

	local fill = UIStyler.Frame("ReloadFill")
	fill.BackgroundColor3 = theme.Arcade.Gold
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.ZIndex = 3
	fill.Parent = track
	self._fill = fill

	local chip = UIStyler.Frame("ReloadChip")
	chip.BackgroundColor3 = theme.Arcade.Red
	chip.AnchorPoint = Vector2.new(0.5, 1)
	chip.Position = UDim2.new(0.5, 0, 0, -8)
	chip.Size = UDim2.fromOffset(112, 30)
	UIChrome.Corner("Arcade").Parent = chip
	self._chipStroke = UIChrome.Stroke(theme, "Arcade", "Panel")
	self._chipStroke.Parent = chip
	UIChrome.ArcadeBevel().Parent = chip
	chip.Visible = false
	chip.Parent = self.Root
	self._chip = chip

	local chipText = UIChrome.Text("ChipText", 17, theme.Colors.TextPrimary)
	chipText.Text = "RELOAD"
	chipText.Size = UDim2.fromScale(1, 1)
	chipText.ZIndex = 2
	chipText.Parent = chip
	self._chipText = chipText

	self:_Render()

	self:_RenderStep(function(_dt: number, clock: number)
		self:_Step(clock)
	end)
end

-- ---- data --------------------------------------------------------------

-- data: { mag, reserve, magSize, weaponIcon, reloading = seconds }
function AmmoWidget:Update(data: any)
	if type(data) ~= "table" then
		return
	end
	if data.magSize then
		self._magSize = math.max(data.magSize, 1)
	end
	if data.mag ~= nil then
		self._mag = math.max(math.floor(data.mag), 0)
	end
	if data.reserve ~= nil then
		self._reserve = math.max(math.floor(data.reserve), 0)
	end
	if data.weaponIcon then
		self:_SetIcon(data.weaponIcon)
	end
	if data.reloading then
		self:_StartReload(data.reloading)
	end
	self:_Render()
end

-- The build-time instance can be an ImageLabel or the glyph fallback; cover
-- both shapes (same swap KillfeedWidget uses).
function AmmoWidget:_SetIcon(iconName: string)
	local icon = self._icon
	if icon:IsA("ImageLabel") then
		local id = IconArchive.Id(iconName)
		if id then
			icon.Image = id
		end
	elseif icon:IsA("TextLabel") then
		icon.Text = IconArchive.Glyph(iconName)
	end
end

function AmmoWidget:_IsLow(): boolean
	return self._mag > 0 and self._mag / self._magSize < LOW_FRACTION
end

function AmmoWidget:_StartReload(duration: number)
	self._reloadStart = os.clock()
	self._reloadDuration = math.max(duration, 0.05)
	self._track.Visible = true
	self._fill.Size = UDim2.new(0, 0, 1, 0)
end

function AmmoWidget:_Render()
	local theme = self.Theme
	self._magLabel.Text = tostring(self._mag)
	self._reserveLabel.Text = "/ " .. HUDWidgetBase.Commas(self._reserve)
	if self._mag <= 0 then
		self._magLabel.TextColor3 = theme.Arcade.Red
	elseif not self:_IsLow() then
		self._magLabel.TextColor3 = theme.Colors.TextPrimary
	end
	local showChip = self._mag <= 0 and self._reloadDuration == nil
	if showChip and not self._chip.Visible then
		self._chip.Visible = true
		self:_Pulse(self._chip)
	elseif not showChip and self._chip.Visible then
		self._chip.Visible = false
	end
end

-- ---- per-frame ---------------------------------------------------------

function AmmoWidget:_Step(clock: number)
	local duration = self._reloadDuration
	if duration then
		local frac = math.min((clock - self._reloadStart) / duration, 1)
		self._fill.Size = UDim2.new(frac, 0, 1, 0)
		if frac >= 1 then
			-- The sweep SNAPS away (doc §5: hard-hide, no fade). Demo nicety:
			-- with no backend nobody sends the refilled mag, so finish the
			-- loop ourselves — a real host overwrites with Update({mag}).
			self._reloadDuration = nil
			self._track.Visible = false
			self._mag = self._magSize
			self:_Render()
		end
	end

	local low = self:_IsLow()
	if low then
		local s = (math.sin(clock * 9) + 1) / 2
		self._magLabel.TextColor3 = self.Theme.Arcade.Red:Lerp(self.Theme.Colors.TextPrimary, s * 0.6)
	elseif self._wasLow then
		self._magLabel.TextColor3 = self.Theme.Colors.TextPrimary
	end
	self._wasLow = low
end

function AmmoWidget:_Style(theme: Types.UITheme)
	if self._box then
		self._box.BackgroundColor3 = theme.Arcade.Panel
	end
	if self._magLabel then
		self._magLabel.FontFace = theme.Fonts.Numeric
		UIChrome.TextOutline(self._magLabel)
		if self._mag <= 0 then
			self._magLabel.TextColor3 = theme.Arcade.Red
		elseif not self:_IsLow() then
			self._magLabel.TextColor3 = theme.Colors.TextPrimary
		end
	end
	if self._reserveLabel then
		self._reserveLabel.FontFace = theme.Fonts.Numeric
		self._reserveLabel.TextColor3 = theme.Arcade.IceBlue
		UIChrome.TextOutline(self._reserveLabel)
	end
	if self._track then
		self._track.BackgroundColor3 = theme.Arcade.RulerTrack
	end
	if self._fill then
		self._fill.BackgroundColor3 = theme.Arcade.Gold
	end
	if self._chip then
		self._chip.BackgroundColor3 = theme.Arcade.Red
	end
	if self._chipStroke then
		self._chipStroke.Color = theme.Colors.Stroke
	end
	if self._chipText then
		self._chipText.FontFace = theme.Fonts.Button
		self._chipText.TextColor3 = theme.Colors.TextPrimary
		UIChrome.TextOutline(self._chipText)
	end
end

return AmmoWidget
