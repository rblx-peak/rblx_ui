--!strict
-- ACLayoutKit — the shared builders of the "AC" LAYOUT language (theme.LayoutKit
-- == "AC"): full-bleed terminal pages, thin top status bars, left category
-- rails, dense hairline-separated list rows, footer key hints, corner brackets.
--
-- Screens that ship a bespoke AC layout branch their _BuildContent:
--
--   function MyScreen:_BuildContent()
--       if self:LayoutKit() == "AC" then
--           self:_BuildAC()
--           return
--       end
--       ... classic build ...
--   end
--
-- and compose the page from these builders plus the existing data components
-- (UISegmentedBarComponent, UIStatRowComponent, UIListRowComponent). Screens
-- REBUILD on style change, so the branch re-evaluates live.
--
-- Everything here is raw-instance construction (no component lifecycle): the
-- host screen's rebuild throws the whole page away, which is the AC fantasy
-- anyway — pages boot, they do not morph.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)

local ACLayoutKit = {}

export type Shell = {
	page: Frame,
	top: Frame,
	title: TextLabel,
	topRight: Frame,
	content: Frame,
	footer: Frame,
	hint: TextLabel,
}

export type Rail = {
	frame: Frame,
	AddEntry: (text: string, onClick: (() -> ())?) -> TextButton,
	Select: (index: number) -> (),
}

function ACLayoutKit.IsActive(theme: Types.UITheme): boolean
	return theme.LayoutKit == "AC"
end

-- A 1px accent hairline. `transparency` defaults to the quiet 0.6 rule weight.
function ACLayoutKit.Rule(theme: Types.UITheme, parent: Instance, transparency: number?): Frame
	local rule = UIStyler.Frame("Rule")
	rule.BackgroundColor3 = theme.Colors.Accent
	rule.BackgroundTransparency = transparency or 0.6
	rule.BorderSizePixel = 0
	rule.Size = UDim2.new(1, 0, 0, 1)
	rule.Parent = parent
	return rule
end

-- The four corner L-brackets that mark a live terminal region.
function ACLayoutKit.Brackets(theme: Types.UITheme, host: GuiObject)
	local accent = theme.Colors.Accent
	local LEN, THICK = 14, 2
	for _, corner in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		local ax, ay = corner[1], corner[2]
		local h = UIStyler.Frame("BracketH")
		h.BackgroundColor3 = accent
		h.BorderSizePixel = 0
		h.AnchorPoint = Vector2.new(ax, ay)
		h.Position = UDim2.fromScale(ax, ay)
		h.Size = UDim2.fromOffset(LEN, THICK)
		h.ZIndex = host.ZIndex + 2
		h.Parent = host
		local v = UIStyler.Frame("BracketV")
		v.BackgroundColor3 = accent
		v.BorderSizePixel = 0
		v.AnchorPoint = Vector2.new(ax, ay)
		v.Position = UDim2.fromScale(ax, ay)
		v.Size = UDim2.fromOffset(THICK, LEN)
		v.ZIndex = host.ZIndex + 2
		v.Parent = host
	end
end

-- The full-bleed terminal page: opaque void, 40px top status bar (accent tick
-- + mono title left, a free slot right), content region, 24px footer hint bar.
-- Every bespoke AC screen starts here.
function ACLayoutKit.Shell(theme: Types.UITheme, root: Instance, titleText: string): Shell
	local page = UIStyler.Frame("ACPage")
	page.BackgroundColor3 = theme.Colors.Background
	page.BackgroundTransparency = 0.03
	page.Size = UDim2.fromScale(1, 1)
	page.Parent = root

	local top = UIStyler.Frame("TopBar")
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0, 40)
	top.Parent = page
	local underline = ACLayoutKit.Rule(theme, top, 0.5)
	underline.AnchorPoint = Vector2.new(0, 1)
	underline.Position = UDim2.new(0, 0, 1, 0)

	local tick = UIStyler.Frame("Tick")
	tick.BackgroundColor3 = theme.Colors.Accent
	tick.BorderSizePixel = 0
	tick.AnchorPoint = Vector2.new(0, 0.5)
	tick.Position = UDim2.new(0, 16, 0.5, 0)
	tick.Size = UDim2.fromOffset(4, 16)
	tick.Parent = top

	local title = UIChrome.Text("Title", 18, theme.Colors.TextPrimary)
	title.Text = titleText
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(30, 0)
	title.Size = UDim2.new(0.5, 0, 1, 0)
	title.Parent = top

	-- Right-hand slot of the top bar (currency readouts, status chips).
	local topRight = UIStyler.Frame("TopRight")
	topRight.BackgroundTransparency = 1
	topRight.AnchorPoint = Vector2.new(1, 0)
	topRight.Position = UDim2.new(1, -16, 0, 0)
	topRight.Size = UDim2.new(0.4, 0, 1, 0)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 18),
	}).Parent = topRight
	topRight.Parent = top

	local footer = UIStyler.Frame("Footer")
	footer.BackgroundTransparency = 1
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 0, 1, 0)
	footer.Size = UDim2.new(1, 0, 0, 24)
	footer.Parent = page
	local overline = ACLayoutKit.Rule(theme, footer, 0.75)
	overline.Position = UDim2.new(0, 0, 0, 0)

	local hint = UIChrome.BodyText("Hint", 11, theme.Colors.TextSecondary)
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.Position = UDim2.new(0, 16, 0, 0)
	hint.Size = UDim2.new(1, -32, 1, 0)
	hint.Parent = footer

	local content = UIStyler.Frame("Content")
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(16, 48)
	content.Size = UDim2.new(1, -32, 1, -80)
	content.Parent = page

	return {
		page = page,
		top = top,
		title = title,
		topRight = topRight,
		content = content,
		footer = footer,
		hint = hint,
	}
end

-- Dim, small, mono, upper-tracking section label ("CATEGORY", "PART LIST").
function ACLayoutKit.SectionLabel(theme: Types.UITheme, parent: Instance, text: string, layoutOrder: number?): TextLabel
	local label = UIChrome.BodyText("Section", 10, theme.Colors.TextSecondary)
	label.Text = string.upper(text)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(1, 0, 0, 18)
	if layoutOrder then
		label.LayoutOrder = layoutOrder
	end
	label.Parent = parent
	return label
end

-- The left category rail: fixed-width column of quiet mono entries; the
-- selected row gets an accent notch + bright ink + a faint raised fill.
function ACLayoutKit.Rail(theme: Types.UITheme, parent: Instance, widthPx: number): Rail
	local frame = UIStyler.Frame("Rail")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(0, widthPx, 1, 0)
	UIStyler.ListLayout({ Padding = UDim.new(0, 2) }).Parent = frame
	frame.Parent = parent

	local rows: { TextButton } = {}
	local notches: { Frame } = {}

	local function select(index: number)
		for i, row in rows do
			local on = i == index
			row.TextColor3 = on and theme.Colors.TextPrimary or theme.Colors.TextSecondary
			row.BackgroundTransparency = on and 0.85 or 1
			notches[i].Visible = on
		end
	end

	local function addEntry(text: string, onClick: (() -> ())?): TextButton
		local row = Instance.new("TextButton")
		row.Name = "RailRow"
		row.BackgroundColor3 = theme.Colors.SurfaceRaised
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.AutoButtonColor = false
		row.Size = UDim2.new(1, 0, 0, 26)
		row.FontFace = theme.Fonts.Body
		row.TextSize = 12
		row.TextColor3 = theme.Colors.TextSecondary
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Text = "  " .. string.upper(text)
		row.LayoutOrder = #rows + 1
		row.Parent = frame

		local notch = UIStyler.Frame("Notch")
		notch.BackgroundColor3 = theme.Colors.Accent
		notch.BorderSizePixel = 0
		notch.Size = UDim2.new(0, 3, 1, -8)
		notch.Position = UDim2.new(0, 0, 0, 4)
		notch.Visible = false
		notch.Parent = row

		table.insert(rows, row)
		table.insert(notches, notch)
		local index = #rows
		row.Activated:Connect(function()
			select(index)
			if onClick then
				onClick()
			end
		end)
		return row
	end

	return {
		frame = frame,
		AddEntry = addEntry,
		Select = select,
	}
end

export type ListColumn = {
	text: string,
	widthScale: number, -- fraction of the row width
	align: Enum.TextXAlignment?,
	color: Color3?,
	dim: boolean?, -- secondary ink
}

-- One dense data row: mono columns over a hairline underline. Returns the row
-- plus its column labels for later updates. Pass a GuiButton parent-behaviour
-- via `clickable` to get a TextButton-backed row.
function ACLayoutKit.ListRow(theme: Types.UITheme, parent: Instance, columns: { ListColumn }, opts: {
	heightPx: number?,
	layoutOrder: number?,
	clickable: boolean?,
}?): (GuiObject, { TextLabel })
	local o = opts or {}
	local row: GuiObject
	if o.clickable then
		local button = Instance.new("TextButton")
		button.Text = ""
		button.AutoButtonColor = false
		row = button
	else
		row = UIStyler.Frame("Row")
	end
	row.Name = "DataRow"
	row.BackgroundColor3 = theme.Colors.SurfaceRaised
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, o.heightPx or 28)
	if o.layoutOrder then
		row.LayoutOrder = o.layoutOrder
	end
	row.Parent = parent

	local underline = ACLayoutKit.Rule(theme, row, 0.85)
	underline.AnchorPoint = Vector2.new(0, 1)
	underline.Position = UDim2.new(0, 0, 1, 0)

	local labels: { TextLabel } = {}
	local x = 0
	for i, column in columns do
		local label = UIChrome.BodyText("Col" .. i, 12, column.dim and theme.Colors.TextSecondary or (column.color or theme.Colors.TextPrimary))
		label.Text = column.text
		label.TextXAlignment = column.align or Enum.TextXAlignment.Left
		label.Position = UDim2.new(x, 4, 0, 0)
		label.Size = UDim2.new(column.widthScale, -8, 1, 0)
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Parent = row
		table.insert(labels, label)
		x += column.widthScale
	end

	return row, labels
end

-- A bordered terminal action button: hairline frame, mono caption, quiet
-- until hovered. The AC replacement for chunky arcade CTA buttons.
function ACLayoutKit.ActionButton(theme: Types.UITheme, parent: Instance, text: string, onClick: (() -> ())?): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Action"
	button.BackgroundColor3 = theme.Colors.Surface
	button.BackgroundTransparency = 0.2
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(180, 30)
	button.FontFace = theme.Fonts.Button
	button.TextSize = 13
	button.TextColor3 = theme.Colors.TextPrimary
	button.Text = string.upper(text)
	UIChrome.Stroke(theme, "Arcade", "Button").Parent = button
	button.Parent = parent
	if onClick then
		button.Activated:Connect(onClick)
	end
	UIChrome.Animate(theme, button)
	return button
end

-- Standard footer hint line: "[TAB] CATEGORY   [CLICK] EQUIP   [ESC] EXIT".
function ACLayoutKit.SetHints(shell: Shell, hints: { { key: string, action: string } })
	local parts = {}
	for _, hintDef in hints do
		table.insert(parts, "[" .. string.upper(hintDef.key) .. "] " .. string.upper(hintDef.action))
	end
	shell.hint.Text = table.concat(parts, "   ")
end

return ACLayoutKit
