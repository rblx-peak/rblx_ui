--!strict
-- Killfeed (HUD widget): "<killer> [icon] <victim>" rows stacked under the
-- §7.2 top-right action row, newest on top, each expiring 5 seconds after it
-- lands. Your own name renders in gold wherever it appears (doc §11.4 "local
-- player first" — you should be able to find yourself in the feed without
-- reading it).
--
-- ROWS ARE POOLED. A killfeed is the highest-churn surface on the HUD — a
-- busy round can push a row a second — and building/destroying a Frame plus
-- three labels per event is exactly the kind of garbage that shows up as a
-- hitch mid-fight. The pool is allocated once at build; pushing a row takes a
-- free instance (or steals the oldest active one), repaints it, and expiring a
-- row just hides it and hands it back.

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local HUDWidgetBase = require(script.Parent.HUDWidgetBase)
local GPHUDStyle = require(script.Parent.GPHUDStyle)

local KillfeedWidget = setmetatable({}, { __index = HUDWidgetBase })
KillfeedWidget.__index = KillfeedWidget

local POOL_SIZE = 6
local ROW_H = 32
local ROW_GAP = 6
local LIFETIME = 5
local NAME_SIZE = 17
local ICON = 20

function KillfeedWidget.new()
	local self = HUDWidgetBase.new("killfeed", "KillfeedWidget")
	self._pool = {} :: { any }
	self._active = {} :: { any }
	self._seq = 0
	self._localName = HUDWidgetBase.LocalName()
	return setmetatable(self, KillfeedWidget)
end

function KillfeedWidget:_Build(props: HUDWidgetBase.Props)
	if props.localName then
		self._localName = props.localName
	end

	local stack = UIStyler.Frame("Rows")
	stack.BackgroundTransparency = 1
	stack.Size = UDim2.fromScale(1, 1)
	UIStyler.ListLayout({
		Padding = UDim.new(0, ROW_GAP),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	}).Parent = stack
	stack.Parent = self.Root
	self._stack = stack

	for i = 1, POOL_SIZE do
		table.insert(self._pool, self:_BuildRow(i))
	end

	local events = props.events or {
		{ killer = self._localName, victim = "ClayGoblin", icon = "sword" },
		{ killer = "Kiln_Warden", victim = "PotShard99", icon = "bolt" },
		{ killer = "PotShard99", victim = self._localName, icon = "skull" },
	}
	self:SetEvents(events)

	self:_RenderStep(function(_dt: number, clock: number)
		self:_Expire(clock)
	end)
end

function KillfeedWidget:_BuildRow(index: number)
	local theme = self.Theme

	local row = UIStyler.Frame("Row" .. index)
	row.BackgroundColor3 = theme.Arcade.Row
	row.BackgroundTransparency = theme.Arcade.RowTransparency
	row.Size = UDim2.fromOffset(0, ROW_H)
	row.AutomaticSize = Enum.AutomaticSize.X
	row.Visible = false
	UIChrome.Corner("Arcade").Parent = row
	local stroke = UIChrome.Stroke(theme, "Arcade", "Panel")
	stroke.Parent = row
	UIStyler.PaddingXY(10, 0).Parent = row
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}).Parent = row
	row.Parent = self._stack

	local killer = UIChrome.Text("Killer", NAME_SIZE, Color3.new(1, 1, 1))
	killer.Size = UDim2.fromOffset(0, ROW_H)
	killer.AutomaticSize = Enum.AutomaticSize.X
	killer.LayoutOrder = 1
	killer.ZIndex = 2
	killer.Parent = row

	local icon = IconArchive.Image(row, "swords", ICON)
	icon.LayoutOrder = 2
	icon.ZIndex = 2

	local victim = UIChrome.Text("Victim", NAME_SIZE, Color3.new(1, 1, 1))
	victim.Size = UDim2.fromOffset(0, ROW_H)
	victim.AutomaticSize = Enum.AutomaticSize.X
	victim.LayoutOrder = 3
	victim.ZIndex = 2
	victim.Parent = row

	return {
		root = row,
		stroke = stroke,
		killer = killer,
		victim = victim,
		icon = icon,
		expires = 0,
	}
end

-- ---- feed --------------------------------------------------------------

-- data: { events = { {killer, victim, icon} } } replaces the visible feed;
-- { event = {...} } pushes a single row.
function KillfeedWidget:Update(data: any)
	if type(data) ~= "table" then
		return
	end
	if data.events then
		self:SetEvents(data.events)
	end
	if data.event then
		self:Push(data.event.killer, data.event.victim, data.event.icon)
	end
end

function KillfeedWidget:SetEvents(events: { any })
	for _, row in self._active do
		row.root.Visible = false
		table.insert(self._pool, row)
	end
	table.clear(self._active)
	for _, event in events do
		self:Push(event.killer, event.victim, event.icon)
	end
end

function KillfeedWidget:Push(killer: string?, victim: string?, iconName: string?)
	local row = table.remove(self._pool)
	if not row then
		-- Pool exhausted: steal the OLDEST active row (the one nearest to
		-- expiring anyway) so a burst of kills never allocates.
		row = table.remove(self._active, 1)
	end
	if not row then
		return
	end

	local gold = self.Theme.Arcade.Gold
	local white = self.Theme.Colors.TextPrimary
	row.killer.Text = killer or "?"
	row.victim.Text = victim or "?"
	row.killer.TextColor3 = (killer == self._localName) and gold or white
	row.victim.TextColor3 = (victim == self._localName) and gold or white
	self:_SetRowIcon(row, iconName or "swords")

	self._seq -= 1
	row.root.LayoutOrder = self._seq -- newest sorts to the top
	row.expires = os.clock() + LIFETIME
	row.root.Visible = true
	table.insert(self._active, row)
	self:_PopIn(row.root)
end

-- Pooled rows keep the instance IconArchive handed us at build time, so the
-- swap has to cover both of its shapes (uploaded image, or glyph fallback).
function KillfeedWidget:_SetRowIcon(row: any, iconName: string)
	local icon = row.icon
	if icon:IsA("ImageLabel") then
		local id = IconArchive.Id(iconName)
		if id then
			icon.Image = id
		end
	elseif icon:IsA("TextLabel") then
		icon.Text = IconArchive.Glyph(iconName)
	end
end

-- Rows hard-hide the moment they expire — no fade, no slide (doc §5).
-- Expiry runs inside the on-screen gate, which is correct rather than lossy:
-- while the feed is hidden nothing ages visibly, and the first frame it comes
-- back every stale row is already past its deadline and clears at once.
function KillfeedWidget:_Expire(clock: number)
	for i = #self._active, 1, -1 do
		local row = self._active[i]
		if clock >= row.expires then
			row.root.Visible = false
			table.remove(self._active, i)
			table.insert(self._pool, row)
		end
	end
end

-- GIRLY POP: rows go LIGHTER than any other surface on the HUD — a killfeed
-- stacks, and a stack of plates is a panel by another name over the exact part
-- of the screen a fight happens in. Petal corners alternate down the feed so the
-- stack reads hand-arranged (law 4), and the two names take the pack's halo so
-- they stay legible on a nearly-clear row. Deliberately SHADOWLESS: six pooled
-- rows would spend six of the ~100 live-UIShadow budget for a read that the
-- rim already gives. Nothing is dropped — killer, icon, victim, the gold
-- local-player highlight and the 5s expiry all behave exactly as before.
function KillfeedWidget:_Style(theme: Types.UITheme)
	local gold = theme.Arcade.Gold
	local white = theme.Colors.TextPrimary
	local function paint(row: any, index: number)
		row.root.BackgroundColor3 = theme.Arcade.Row
		row.root.BackgroundTransparency = theme.Arcade.RowTransparency
		row.stroke.Color = theme.Colors.Stroke
		for _, label in { row.killer, row.victim } do
			label.FontFace = theme.Fonts.Button
			GPHUDStyle.Halo(theme, label)
		end
		row.killer.TextColor3 = (row.killer.Text == self._localName) and gold or white
		row.victim.TextColor3 = (row.victim.Text == self._localName) and gold or white
		GPHUDStyle.Surface(theme, row.root, {
			transparency = GPHUDStyle.Row,
			restTransparency = theme.Arcade.RowTransparency,
			petal = index,
			stroke = true,
			strokeIntent = "Panel",
			strokeKeepColor = true,
		})
	end
	for index, row in self._pool do
		paint(row, index)
	end
	for index, row in self._active do
		paint(row, index + #self._pool)
	end
end

return KillfeedWidget
