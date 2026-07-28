--!strict
-- Buff / debuff tray (HUD widget): a left-to-right row of chips, each an
-- arcade icon box carrying a stack badge, a depleting duration line and a
-- remaining-time label.
--
-- Colour IS meaning (doc §3.3): the ring around a chip is green for something
-- helping you and red for something hurting you, so the tray is readable at a
-- glance without reading a single word. Rings are strokes, never fills —
-- selection/state language in this system is always a ring (§4.3).
--
-- Chips POP in (§5.1) and HARD-HIDE out: an expiring buff is destroyed on the
-- frame it expires, because a fading chip is indistinguishable from a chip
-- that is merely about to expire.

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIBadgeComponent = require(script.Parent.Parent.Components.UIBadgeComponent)
local HUDWidgetBase = require(script.Parent.HUDWidgetBase)
local GPHUDStyle = require(script.Parent.GPHUDStyle)

local BuffTrayWidget = setmetatable({}, { __index = HUDWidgetBase })
BuffTrayWidget.__index = BuffTrayWidget

local CHIP = 56
local CHIP_GAP = 8
local TIME_H = 18
local LINE_H = 3

-- Demo tray: two buffs, two debuffs, mixed stacks and durations.
local DEMO_BUFFS = {
	{ id = "haste", name = "Haste", icon = "bolt", kind = "buff", stacks = 2, remaining = 42, duration = 60 },
	{ id = "ward", name = "Ward", icon = "shield", kind = "buff", stacks = 1, remaining = 18, duration = 30 },
	{ id = "burn", name = "Burning", icon = "fire", kind = "debuff", stacks = 3, remaining = 7, duration = 12 },
	{ id = "slow", name = "Slowed", icon = "hourglass", kind = "debuff", stacks = 1, remaining = 12, duration = 20 },
}

function BuffTrayWidget.new()
	local self = HUDWidgetBase.new("buffs", "BuffTrayWidget")
	self._chips = {} :: { [string]: any }
	self._order = {} :: { string }
	self._tick = 0
	return setmetatable(self, BuffTrayWidget)
end

function BuffTrayWidget:_Build(props: HUDWidgetBase.Props)
	local row = UIStyler.Frame("Chips")
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, CHIP_GAP),
	}).Parent = row
	row.Parent = self.Root
	self._row = row

	self:SetBuffs(props.buffs or DEMO_BUFFS)

	self:_RenderStep(function(dt: number)
		self:_Step(dt)
	end)
end

-- data: { buffs = { {id, name, icon, kind = "buff"|"debuff", stacks,
--          remaining, duration} } }
function BuffTrayWidget:Update(data: any)
	if type(data) ~= "table" then
		return
	end
	self:SetBuffs(data.buffs or data)
end

function BuffTrayWidget:SetBuffs(buffs: { any })
	local seen: { [string]: boolean } = {}
	table.clear(self._order)

	for index, buff in buffs do
		local id = buff.id or ("buff" .. index)
		seen[id] = true
		table.insert(self._order, id)
		local chip = self._chips[id]
		if not chip then
			chip = self:_BuildChip(id, buff)
			self._chips[id] = chip
			self:_PopIn(chip.root)
		end
		chip.kind = buff.kind or chip.kind
		chip.stacks = buff.stacks or 1
		chip.duration = buff.duration or buff.remaining or chip.duration
		chip.remaining = buff.remaining or chip.remaining
		chip.root.LayoutOrder = index
		self:_PaintChip(chip)
		self:_RenderChip(chip, true)
	end

	for id, chip in self._chips do
		if not seen[id] then
			self:_DropChip(id, chip)
		end
	end
end

function BuffTrayWidget:_BuildChip(id: string, buff: any)
	local theme = self.Theme

	local root = UIStyler.Frame("Chip_" .. id)
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(CHIP, CHIP + TIME_H)
	root.Parent = self._row

	local box = UIStyler.Frame("Box")
	box.BackgroundColor3 = theme.Arcade.NearBlack2
	box.Size = UDim2.fromOffset(CHIP, CHIP)
	box.ClipsDescendants = true
	UIChrome.Corner("Arcade").Parent = box
	-- The ring: UIChrome's "Selection" stroke intent (3px, solid) supplies the
	-- POLICY; only the semantic colour changes per kind (§4.3 rings, §3.3
	-- colour is meaning).
	local ring = UIChrome.Stroke(theme, "Arcade", "Selection")
	ring.Parent = box
	box.Parent = root

	local icon = IconArchive.Image(box, buff.icon or "star", 34)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.45)
	icon.ZIndex = 2

	local line = UIStyler.Frame("DurationLine")
	line.AnchorPoint = Vector2.new(0, 1)
	line.Position = UDim2.fromScale(0, 1)
	line.Size = UDim2.new(1, 0, 0, LINE_H)
	line.ZIndex = 3
	line.Parent = box

	-- Stack badge slot: the badge component fills its parent's height and
	-- auto-sizes its width, so the slot is what fixes the badge's 18px scale.
	local badgeSlot = UIStyler.Frame("StackSlot")
	badgeSlot.BackgroundTransparency = 1
	badgeSlot.AnchorPoint = Vector2.new(1, 0)
	badgeSlot.Position = UDim2.new(1, 2, 0, -3)
	badgeSlot.Size = UDim2.fromOffset(24, 18)
	badgeSlot.ZIndex = 8
	badgeSlot.Parent = root

	local badge = UIBadgeComponent.new()
	badge:Create(badgeSlot, { text = "x1", variant = "Accent" })
	badge.Root.ZIndex = 9

	local time = UIChrome.Text("Time", 13, theme.Arcade.Gold)
	time.Position = UDim2.fromOffset(0, CHIP + 2)
	time.Size = UDim2.fromOffset(CHIP, TIME_H - 2)
	time.Parent = root

	return {
		id = id,
		name = buff.name or id,
		kind = buff.kind or "buff",
		stacks = buff.stacks or 1,
		remaining = buff.remaining or 0,
		duration = buff.duration or buff.remaining or 1,
		root = root,
		box = box,
		ring = ring,
		icon = icon,
		line = line,
		badge = badge,
		badgeSlot = badgeSlot,
		time = time,
	}
end

function BuffTrayWidget:_DropChip(id: string, chip: any)
	chip.badge:Destroy()
	-- Hand the tile's shadow back before the instance goes: the budget counter
	-- only falls on a released handle, and this tray churns every few seconds.
	GPHUDStyle.Drop(chip.box, self._shadows)
	chip.root:Destroy()
	self._chips[id] = nil
end

-- ---- per-frame ---------------------------------------------------------

-- The duration LINE is per-frame (it must drain smoothly), the time LABEL is
-- 1Hz (doc §11.3: countdown surfaces tick at 1Hz — a per-frame number is
-- unreadable noise).
function BuffTrayWidget:_Step(dt: number)
	self._tick += dt
	local secondPassed = self._tick >= 1
	if secondPassed then
		self._tick -= 1
	end
	for id, chip in self._chips do
		if chip.remaining > 0 then
			chip.remaining = math.max(chip.remaining - dt, 0)
			if chip.remaining <= 0 then
				self:_DropChip(id, chip)
			else
				self:_RenderChip(chip, secondPassed)
			end
		end
	end
end

function BuffTrayWidget:_RenderChip(chip: any, updateText: boolean)
	local fraction = chip.duration > 0 and math.clamp(chip.remaining / chip.duration, 0, 1) or 0
	chip.line.Size = UDim2.new(fraction, 0, 0, LINE_H)
	if updateText then
		chip.time.Text = chip.remaining >= 60
			and UIChrome.FormatCountdown(chip.remaining)
			or string.format("%ds", math.ceil(chip.remaining))
	end
	local stacked = chip.stacks > 1
	chip.badgeSlot.Visible = stacked
	if stacked then
		chip.badge:SetContent({ text = "x" .. tostring(math.floor(chip.stacks)) })
	end
end

function BuffTrayWidget:_PaintChip(chip: any)
	local theme = self.Theme
	local arcade = theme.Arcade
	local accent = chip.kind == "debuff" and arcade.Red or arcade.Green
	chip.box.BackgroundColor3 = arcade.NearBlack2
	chip.ring.Color = accent
	chip.line.BackgroundColor3 = accent
	chip.time.FontFace = theme.Fonts.Numeric
	chip.time.TextColor3 = arcade.Gold
	UIChrome.TextOutline(chip.time)

	-- GIRLY POP: a shelf of little glazed tiles, petal corners alternating along
	-- the tray by layout order (pack law 4). The RING keeps its own colour in
	-- both directions — matcha for something helping you, coral for something
	-- hurting you — because that ring IS the meaning (§3.3) and deepening it to
	-- match its tile would erase it. Stack badge, duration line and the 1Hz
	-- remaining-time label are untouched.
	GPHUDStyle.Surface(theme, chip.box, {
		transparency = GPHUDStyle.Chip,
		petal = chip.root.LayoutOrder,
		stroke = true,
		strokeIntent = "Selection",
		strokeKeepColor = true,
		shadow = "sm",
		sink = self._shadows,
	})
	GPHUDStyle.Surface(theme, chip.line, { keepTransparency = true, radius = theme.Radii.Pill })
	GPHUDStyle.Halo(theme, chip.time)
end

function BuffTrayWidget:_Style(theme: Types.UITheme)
	for _, chip in self._chips do
		self:_PaintChip(chip)
		chip.badge:ApplyTheme(theme)
	end
end

function BuffTrayWidget:Destroy()
	for id, chip in self._chips do
		chip.badge:Destroy()
		GPHUDStyle.Drop(chip.box, self._shadows)
		self._chips[id] = nil
	end
	HUDWidgetBase.Destroy(self)
end

return BuffTrayWidget
