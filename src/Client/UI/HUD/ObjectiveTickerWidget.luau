--!strict
-- Objective ticker (HUD widget) — the top-centre status line the doc §7.2
-- screen map puts at y=14: one gold FredokaOne objective with an ice-blue hint
-- underneath it.
--
-- Two states, no third: ACTIVE (gold, full strength) and COMPLETE (a check
-- icon appears and the whole line dims in place — doc §11.2, things go grey
-- where they stand, they are never yanked off screen). A new objective POPS
-- (§5.1) so a silent text swap can't slip past the player.

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local HUDWidgetBase = require(script.Parent.HUDWidgetBase)

local ObjectiveTickerWidget = setmetatable({}, { __index = HUDWidgetBase })
ObjectiveTickerWidget.__index = ObjectiveTickerWidget

local LINE_H = 26
local HINT_H = 18
local CHECK = 20
local DONE_TRANSPARENCY = 0.45

local DEMO_TEXT = "DEFEND THE KILN — 3 / 5 WAVES"
local DEMO_HINT = "Hold the east ramp until the round timer runs out"

function ObjectiveTickerWidget.new()
	local self = HUDWidgetBase.new("objective", "ObjectiveTickerWidget")
	self._text = DEMO_TEXT
	self._hint = DEMO_HINT
	self._completed = false
	return setmetatable(self, ObjectiveTickerWidget)
end

function ObjectiveTickerWidget:_Build(props: HUDWidgetBase.Props)
	local theme = self.Theme
	local width = math.max(self.Root.Size.X.Offset, 240)

	-- The pop lives on this wrapper, so the widget's own placement (and the
	-- baseline UIScale) is never what animates.
	local content = UIStyler.Frame("Content")
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = self.Root
	self._content = content

	-- Icon + text group, auto-width and centre-anchored so the pair reads as
	-- one centred line however long the objective is.
	local row = UIStyler.Frame("Line")
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.fromScale(0.5, 0)
	row.Size = UDim2.fromOffset(0, LINE_H)
	row.AutomaticSize = Enum.AutomaticSize.X
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
	}).Parent = row
	row.Parent = content
	self._row = row

	local check = IconArchive.Image(row, "check", CHECK)
	check.LayoutOrder = 1
	check.Visible = false
	self._check = check

	local label = UIChrome.Text("Objective", 24, theme.Arcade.Gold)
	label.Text = self._text
	label.Size = UDim2.fromOffset(0, LINE_H)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.LayoutOrder = 2
	label.TextTruncate = Enum.TextTruncate.AtEnd
	-- Caps the auto-width so a long objective truncates inside the widget box
	-- instead of growing past the screen map's 640px slot.
	local cap = Instance.new("UISizeConstraint")
	cap.MaxSize = Vector2.new(width - CHECK - 12, math.huge)
	cap.Parent = label
	label.Parent = row
	self._label = label

	local hint = UIChrome.BodyText("Hint", 15, theme.Arcade.IceBlue)
	hint.Text = self._hint
	hint.Position = UDim2.fromOffset(0, LINE_H)
	hint.Size = UDim2.new(1, 0, 0, HINT_H)
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	hint.Parent = content
	self._hint_label = hint

	if props.objective then
		self:Update(props.objective)
	else
		self:_Render()
	end
end

-- data: { text, hint, completed } | { objective = "..." } | a raw string.
function ObjectiveTickerWidget:Update(data: any)
	if data == nil then
		return
	end
	local text, hint, completed
	if type(data) == "string" then
		text = data
	else
		local objective = data.objective
		if type(objective) == "table" then
			text = objective.text
			hint = objective.hint
			completed = objective.completed or objective.done
		elseif type(objective) == "string" then
			text = objective
		end
		text = data.text or text
		hint = data.hint or hint
		if completed == nil then
			completed = data.completed or data.done
		end
	end
	self:SetObjective(text or self._text, hint, completed == true)
end

function ObjectiveTickerWidget:SetObjective(text: string, hint: string?, completed: boolean?)
	local changed = text ~= self._text
	self._text = text
	if hint ~= nil then
		self._hint = hint
	end
	self._completed = completed == true
	self:_Render()
	if changed and self._content then
		self:_PopIn(self._content)
	end
end

function ObjectiveTickerWidget:_Render()
	local theme = self.Theme
	local label, hint, check = self._label, self._hint_label, self._check
	if not (label and hint and check) then
		return
	end
	label.Text = self._text
	hint.Text = self._hint
	hint.Visible = self._hint ~= ""
	check.Visible = self._completed

	local done = self._completed
	label.TextColor3 = done and theme.Arcade.GreyOwned or theme.Arcade.Gold
	label.TextTransparency = done and DONE_TRANSPARENCY or 0
	UIChrome.TextOutline(label, done and DONE_TRANSPARENCY or 0)
	hint.TextTransparency = done and DONE_TRANSPARENCY or 0
	if check:IsA("ImageLabel") then
		check.ImageColor3 = theme.Arcade.Green
	end
end

function ObjectiveTickerWidget:_Style(theme: Types.UITheme)
	if self._label then
		self._label.FontFace = theme.Fonts.Title
		UIChrome.TextOutline(self._label)
	end
	if self._hint_label then
		self._hint_label.FontFace = theme.Fonts.Body
		self._hint_label.TextColor3 = theme.Arcade.IceBlue
	end
	self:_Render()
end

return ObjectiveTickerWidget
