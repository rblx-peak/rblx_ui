--!strict
-- ADMIN / TEST PANEL — ported from Brick Game's AdminMenu.client.luau onto the
-- Pottery Clash chrome.
--
-- The source gates itself on an allow-list before building anything; this
-- screen deliberately does NOT. Permission is not a UI concern: the panel is a
-- dumb command surface, the CALLER decides whether to open it, and the SERVER
-- re-checks every command it receives (the source's AdminService does exactly
-- that — "nothing here is trusted"). The banner across the top says so on
-- screen so nobody mistakes a rendered button for an authorisation.
--
-- Compact dark panel: a command list where each row is a labelled arcade button
-- plus an optional numeric field, a free-text command box, and a scrolling
-- output log in a monospace font — Enum.Font.Code under Classic, the styled
-- body font otherwise (the one place the display font would hurt — monospaced
-- echo of what was actually sent).

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPControlKit = require(script.Parent.Parent.Framework.GPControlKit)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIScreenBase = require(script.Parent.UIScreenBase)

export type Command = {
	id: string,
	label: string,
	-- "value" adds a numeric field whose contents ride along with the command;
	-- anything else is a plain fire-and-forget action.
	kind: string?,
	variant: string?,
}

-- Fixed px at the 1650×1020 baseline.
local PANEL_W, PANEL_H = 560, 730
local PAD = 14
local INNER = PANEL_W - PAD * 2
local HEADER_H = 56
local NOTE_Y = HEADER_H + 8
local NOTE_H = 46
local LIST_Y = NOTE_Y + NOTE_H + 10
local LIST_H = 300
local ENTRY_Y = LIST_Y + LIST_H + 12
local ENTRY_H = 44
local LOG_LABEL_Y = ENTRY_Y + ENTRY_H + 12
local LOG_Y = LOG_LABEL_Y + 26
local ROW_H = 46
local FIELD_W = 108
local LOG_LIMIT = 80

local DEMO_COMMANDS: { Command } = {
	{ id = "giveCurrency", label = "GIVE CURRENCY", kind = "value", variant = "Green" },
	{ id = "setLevel", label = "SET LEVEL", kind = "value", variant = "Blue" },
	{ id = "teleport", label = "TELEPORT", kind = "value", variant = "Magenta" },
	{ id = "spawnItem", label = "SPAWN ITEM", kind = "value", variant = "Orange" },
	{ id = "toggleHUD", label = "TOGGLE HUD", kind = "action", variant = "Gold" },
	{ id = "reloadUI", label = "RELOAD UI", kind = "action", variant = "Red" },
}

-- "GIVE CURRENCY" -> "Give Currency". Pack law 5 forbids all-caps copy.
local function gpTitle(text: string): string
	return (string.gsub(string.lower(text), "(%a[%w']*)", function(word: string)
		return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
	end))
end

-- The command's `variant` is DATA the caller supplies (Green / Blue / Magenta /
-- Orange / Gold / Red). GP keeps that colour coding intact — it is how you tell
-- a destructive command from a harmless one at a glance — and resolves it
-- through the pack's own tokens, all of which are pastel here.
local function gpVariantFill(theme: Types.UITheme, variant: string?): Color3
	local a = theme.Arcade
	if variant == "Green" then
		return a.Green
	elseif variant == "Blue" then
		return a.Blue
	elseif variant == "Magenta" then
		return a.Magenta
	elseif variant == "Orange" then
		return a.Orange
	elseif variant == "Gold" then
		return a.Gold
	elseif variant == "Red" then
		return a.Red
	end
	return theme.Colors.Surface
end

local AdminPanelScreen = setmetatable({}, { __index = UIScreenBase })
AdminPanelScreen.__index = AdminPanelScreen

function AdminPanelScreen.new()
	local self = UIScreenBase.new("AdminPanelScreen", 9999)
	self._commands = DEMO_COMMANDS :: { Command }
	-- Injected by Show(data): (id, value) -> string? — an optional line to echo
	-- into the log. Unbound, the panel logs the command locally so it demos.
	self._onCommand = nil :: ((string, any) -> string?)?
	self._rowButtons = {} :: { any }
	self._runButton = nil :: any
	self._logLines = {} :: { TextLabel }
	self._logCount = 0
	-- GP branch state: the flag _RenderCommands reads, plus the panel and
	-- command-row shadow sinks the budget is released from.
	self._gp = false
	self._gpShadows = nil :: { any }?
	self._gpRowShadows = nil :: { any }?
	return setmetatable(self, AdminPanelScreen)
end

-- ========================================================================
-- Chrome helpers
-- ========================================================================

-- A recessed well with a TextBox inside. A TextBox has no UIChrome builder, so
-- the WELL carries the chrome (corner + stroke policy through UIChrome) and the
-- box itself is a transparent child — the same nesting the booth uses.
local function makeField(theme: Types.UITheme, parent: Instance, placeholder: string, font: Font, textSize: number): TextBox
	local well = UIStyler.Frame("Field")
	well.BackgroundColor3 = theme.Arcade.NearBlack
	well.Size = UDim2.fromScale(1, 1)
	well.ZIndex = 46
	UIChrome.Corner("Arcade", "Sub").Parent = well
	UIChrome.Stroke(theme, "Arcade").Parent = well
	well.Parent = parent

	local box = Instance.new("TextBox")
	box.Name = "Input"
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.Size = UDim2.new(1, -16, 1, 0)
	box.Position = UDim2.fromOffset(8, 0)
	box.ClearTextOnFocus = false
	box.Text = ""
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = theme.Arcade.GreyOwned
	box.TextColor3 = theme.Colors.TextPrimary
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.FontFace = font
	box.TextSize = textSize
	box.ZIndex = 47
	UIChrome.TextOutline(box)
	box.Parent = well
	return box
end

-- ========================================================================
-- Build
-- ========================================================================

-- ========================================================================
-- GIRLY POP
-- ========================================================================
-- A command surface stays a command surface: every command row, its numeric
-- field, the free-text box, RUN, the bounded output log and — above all — the
-- PERMISSION BANNER are all here, at the same sizes and in the same order. The
-- banner keeps its amber warning palette verbatim; making a security notice
-- prettier than it is would be the single worst thing this pack could do.
--
-- The one thing that changes is the chrome: cream plate, rose header ribbon,
-- petal-cornered rows, hue-matched shade. Controls come from GPControlKit
-- because UIChrome.Stroke resolves to BLACK under this pack's Chrome policy and
-- UIStyleEnforcer backstops solid buttons with a black rim (pack law 1).

function AdminPanelScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	self._gpShadows = {}
	self._gpRowShadows = {}

	local panelFill = theme.Colors.Background
	local panel = UIStyler.Frame("Panel")
	panel.BackgroundColor3 = panelFill
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	panel.ZIndex = 41
	-- Safe to clip: nothing in this pack rotates, and no child needs to hang
	-- outside the plate.
	panel.ClipsDescendants = true
	panel.Parent = self.Root
	UIStyler.Corner(theme.Radii.Large).Parent = panel
	GPLayoutKit.SoftStroke(theme, panel, theme.Colors.Primary)
	GPLayoutKit.Shadow(theme, panel, "lg", self._gpShadows, panelFill)
	self._panel = panel

	local studio = ((theme :: any).DialectTokens and (theme :: any).DialectTokens.studio) or {}
	local grain = GPLayoutKit.Tile(
		theme,
		studio.patternKey or "speckle",
		GPLayoutKit.Deepen(theme, panelFill, 1),
		studio.speckleTransparency or 0.94,
		"ClayGrain"
	)
	grain.ZIndex = 41
	grain.Parent = panel

	-- Rose ribbon with the glaze sheen. No scalloped lip here: the lip would
	-- hang 18px down over the permission banner, and the banner wins.
	local headerFill = theme.Colors.Primary
	local header = UIStyler.Frame("Header")
	header.BackgroundColor3 = headerFill
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.ZIndex = 42
	header.Parent = panel
	GPLayoutKit.CornerSet(theme, header, "Tab")
	GPLayoutKit.SoftStroke(theme, header, headerFill)
	GPLayoutKit.GlazeSheen(theme, header)

	local title = GPLayoutKit.Text(theme, 28, theme.Colors.TextPrimary, "Title")
	title.Text = "Admin / test panel"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(PAD, 0)
	title.Size = UDim2.new(1, -(PAD + 66), 1, 0)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 44
	title.Parent = header

	self._gpClose = GPControlKit.Button(theme, header, {
		text = "X",
		fill = theme.Colors.SurfaceRaised,
		index = 1,
		textSize = 20,
		size = UDim2.fromOffset(40, 40),
		position = UDim2.new(1, -6, 0.5, 0),
		anchorPoint = Vector2.new(1, 0.5),
		zIndex = 44,
		sink = self._gpShadows,
		onClick = function()
			self.ScreenController:HideScreen("adminPanel")
		end,
	})

	-- The permission banner, verbatim. Its amber palette is NOT re-tinted: a
	-- warning that blends into the decoration is a broken warning.
	local note = UIStyler.Frame("Note")
	note.BackgroundColor3 = theme.Studio.WarnBg
	note.Position = UDim2.fromOffset(PAD, NOTE_Y)
	note.Size = UDim2.fromOffset(INNER, NOTE_H)
	note.ZIndex = 42
	note.Parent = panel
	GPLayoutKit.Petal(theme, note, 0)
	GPLayoutKit.SoftStroke(theme, note, theme.Studio.WarnBg)
	GPLayoutKit.Shadow(theme, note, "sm", self._gpShadows, theme.Studio.WarnBg)

	local noteText = GPLayoutKit.BodyText(theme, 15, theme.Studio.WarnText, "NoteText")
	noteText.Text = "Authorized users only — this panel only SENDS commands.\nThe server must re-check permission on every one."
	noteText.Size = UDim2.new(1, -24, 1, 0)
	noteText.Position = UDim2.fromOffset(12, 0)
	noteText.TextXAlignment = Enum.TextXAlignment.Left
	noteText.ZIndex = 43
	noteText.TextWrapped = true
	noteText.Parent = note

	local list = Instance.new("ScrollingFrame")
	list.Name = "Commands"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(PAD, LIST_Y)
	list.Size = UDim2.fromOffset(INNER, LIST_H)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1)
	-- Scrolled rows must never spill onto the plate.
	list.ClipsDescendants = true
	list.ZIndex = 42
	list.Parent = panel
	-- Vertical breathing room INSIDE the clip: the command rows cast hue-matched
	-- shadows, and without it the first and last row's shade is sliced flat
	-- against the clip edge. Zero horizontal inset, so the row widths (and the
	-- field column that hangs off their right edge) are untouched.
	UIStyler.PaddingXY(0, 6).Parent = list
	self._list = list -- _RenderCommands owns its layout (it clears and rebuilds)

	local entry = UIStyler.Frame("Entry")
	entry.BackgroundTransparency = 1
	entry.Position = UDim2.fromOffset(PAD, ENTRY_Y)
	entry.Size = UDim2.fromOffset(INNER, ENTRY_H)
	entry.ZIndex = 42
	entry.Parent = panel

	local field = GPControlKit.Field(theme, entry, {
		placeholder = "/command arg",
		textSize = 17,
		size = UDim2.new(1, -(FIELD_W + 8), 1, 0),
		zIndex = 45,
	})
	self._entryBox = field.box
	self._entryBox.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			self:_RunFreeText()
		end
	end)

	self._runButton = GPControlKit.Button(theme, entry, {
		text = "Run",
		fill = theme.Arcade.Blue,
		index = 1,
		size = UDim2.fromOffset(FIELD_W, ENTRY_H),
		position = UDim2.new(1, 0, 0, 0),
		anchorPoint = Vector2.new(1, 0),
		zIndex = 45,
		sink = self._gpShadows,
		onClick = function()
			self:_RunFreeText()
		end,
	})

	local logLabel = GPLayoutKit.SectionLabel(theme, panel, "Output")
	logLabel.Position = UDim2.fromOffset(PAD, LOG_LABEL_Y)
	logLabel.Size = UDim2.fromOffset(INNER, 24)
	logLabel.ZIndex = 42

	local logWell = GPControlKit.Well(theme, panel, {
		fill = theme.Colors.Surface,
		index = 1,
		shadow = "sm",
		position = UDim2.fromOffset(PAD, LOG_Y),
		size = UDim2.fromOffset(INNER, PANEL_H - LOG_Y - PAD),
		zIndex = 42,
		sink = self._gpShadows,
	})

	local log = Instance.new("ScrollingFrame")
	log.Name = "Log"
	log.BackgroundTransparency = 1
	log.BorderSizePixel = 0
	log.Position = UDim2.fromOffset(12, 8)
	log.Size = UDim2.new(1, -24, 1, -16)
	log.CanvasSize = UDim2.new()
	log.AutomaticCanvasSize = Enum.AutomaticSize.Y
	log.ScrollingDirection = Enum.ScrollingDirection.Y
	log.ScrollBarThickness = 6
	log.ScrollBarImageColor3 = GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1)
	log.ClipsDescendants = true
	log.ZIndex = 43
	log.Parent = logWell
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 2),
	}).Parent = log
	self._log = log

	self:_RenderCommands()
	self:_Log("panel ready — commands are advisory; the server decides.")
end

-- One GP command row: the labelled action chip plus, for "value" commands, the
-- same numeric field beside it. Same row height, same field width, same order.
function AdminPanelScreen:_RenderGPCommands()
	local theme = self:GetTheme()
	for _, button in self._rowButtons do
		button:Destroy()
	end
	table.clear(self._rowButtons)
	-- Row shadows are budget handles; a rebuilt list hands the old ones back.
	GPLayoutKit.ReleaseShadows(self._gpRowShadows)
	self._gpRowShadows = self._gpRowShadows or {}
	self._list:ClearAllChildren()
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 8),
	}).Parent = self._list

	for order, command in self._commands do
		local hasField = command.kind == "value"
		local row = UIStyler.Frame("Row_" .. command.id)
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, -14, 0, ROW_H)
		row.LayoutOrder = order
		row.ZIndex = 44
		row.Parent = self._list

		local field: TextBox? = nil
		if hasField then
			local holder = GPControlKit.Field(theme, row, {
				placeholder = "0",
				numeric = true,
				textSize = 20,
				index = order + 1,
				size = UDim2.fromOffset(FIELD_W, ROW_H),
				position = UDim2.new(1, 0, 0, 0),
				anchorPoint = Vector2.new(1, 0),
				zIndex = 45,
			})
			field = holder.box
		end

		local button = GPControlKit.Button(theme, row, {
			text = gpTitle(command.label),
			fill = gpVariantFill(theme, command.variant),
			index = order,
			size = UDim2.new(1, if hasField then -(FIELD_W + 8) else 0, 0, ROW_H),
			zIndex = 45,
			sink = self._gpRowShadows,
			onClick = function()
				local value: any = nil
				if field then
					value = tonumber(field.Text)
					if value == nil and field.Text ~= "" then
						value = field.Text
					end
				end
				self:_Run(command, value)
			end,
		})
		table.insert(self._rowButtons, button)
	end
end

function AdminPanelScreen:_BuildContent()
	-- GP layout language: the same command surface on cream paper.
	if self:LayoutKit() == "GP" then
		self._gp = true
		self:_BuildGPLayout()
		return
	end
	self._gp = false

	local theme = self:GetTheme()

	local panel = UIChrome.Panel(theme, "Arcade", "Panel")
	panel.BackgroundColor3 = theme.Arcade.NearBlack2
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	panel.ZIndex = 41
	panel.Parent = self.Root
	self._panel = panel

	local header = UIStyler.Frame("Header")
	header.BackgroundColor3 = theme.Arcade.Red
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.ZIndex = 42
	UIChrome.GlassGradient().Parent = header
	header.Parent = panel

	local title = UIChrome.Text("Title", 28, theme.Colors.TextPrimary)
	title.Text = "ADMIN / TEST PANEL"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(PAD, 0)
	title.Size = UDim2.new(1, -(PAD + 66), 1, 0)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 43
	title.Parent = header

	local close = UIChrome.CloseButton(theme, header, function()
		self.ScreenController:HideScreen("adminPanel")
	end)
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -6, 0.5, 0)
	close.ZIndex = 43

	-- The permission banner: this screen never asserts permission itself.
	local note = UIStyler.Frame("Note")
	note.BackgroundColor3 = theme.Studio.WarnBg
	note.Position = UDim2.fromOffset(PAD, NOTE_Y)
	note.Size = UDim2.fromOffset(INNER, NOTE_H)
	note.ZIndex = 42
	UIChrome.Corner("Arcade", "Sub").Parent = note
	UIChrome.Stroke(theme, "Arcade").Parent = note
	note.Parent = panel

	local noteText = UIChrome.BodyText("NoteText", 15, theme.Studio.WarnText)
	noteText.Text = "AUTHORIZED USERS ONLY — this panel only SENDS commands.\nThe server must re-check permission on every one."
	noteText.Size = UDim2.new(1, -16, 1, 0)
	noteText.Position = UDim2.fromOffset(8, 0)
	noteText.TextXAlignment = Enum.TextXAlignment.Left
	noteText.ZIndex = 43
	noteText.TextWrapped = true
	noteText.Parent = note

	local list = Instance.new("ScrollingFrame")
	list.Name = "Commands"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(PAD, LIST_Y)
	list.Size = UDim2.fromOffset(INNER, LIST_H)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = theme.Arcade.Gold
	list.ZIndex = 42
	list.Parent = panel
	self._list = list -- _RenderCommands owns its layout (it clears and rebuilds)

	-- Free-text command box + RUN.
	local entry = UIStyler.Frame("Entry")
	entry.BackgroundTransparency = 1
	entry.Position = UDim2.fromOffset(PAD, ENTRY_Y)
	entry.Size = UDim2.fromOffset(INNER, ENTRY_H)
	entry.ZIndex = 42
	entry.Parent = panel

	local boxHolder = UIStyler.Frame("BoxHolder")
	boxHolder.BackgroundTransparency = 1
	boxHolder.Size = UDim2.new(1, -(FIELD_W + 8), 1, 0)
	boxHolder.ZIndex = 45
	boxHolder.Parent = entry
	local styled = theme.Chrome ~= nil
	self._entryBox = makeField(theme, boxHolder, "/command arg", if styled then theme.Fonts.Body else Font.fromEnum(Enum.Font.Code), 17)
	self._entryBox.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			self:_RunFreeText()
		end
	end)

	local run = UIButtonComponent.new()
	run:Create(entry, {
		text = "RUN",
		variant = "Blue",
		size = UDim2.fromOffset(FIELD_W, ENTRY_H),
		position = UDim2.new(1, 0, 0, 0),
		anchorPoint = Vector2.new(1, 0),
		onClick = function()
			self:_RunFreeText()
		end,
	})
	run.Root.ZIndex = 45
	self._runButton = run

	local logLabel = UIChrome.Text("LogLabel", 20, theme.Arcade.Gold)
	logLabel.Text = "OUTPUT"
	logLabel.TextXAlignment = Enum.TextXAlignment.Left
	logLabel.Position = UDim2.fromOffset(PAD, LOG_LABEL_Y)
	logLabel.Size = UDim2.fromOffset(INNER, 24)
	logLabel.ZIndex = 42
	logLabel.Parent = panel

	local logWell = UIStyler.Frame("LogWell")
	logWell.BackgroundColor3 = theme.Arcade.NearBlack
	logWell.Position = UDim2.fromOffset(PAD, LOG_Y)
	logWell.Size = UDim2.fromOffset(INNER, PANEL_H - LOG_Y - PAD)
	logWell.ZIndex = 42
	UIChrome.Corner("Arcade", "Sub").Parent = logWell
	UIChrome.Stroke(theme, "Arcade").Parent = logWell
	logWell.Parent = panel

	local log = Instance.new("ScrollingFrame")
	log.Name = "Log"
	log.BackgroundTransparency = 1
	log.BorderSizePixel = 0
	log.Position = UDim2.fromOffset(8, 6)
	log.Size = UDim2.new(1, -16, 1, -12)
	log.CanvasSize = UDim2.new()
	log.AutomaticCanvasSize = Enum.AutomaticSize.Y
	log.ScrollingDirection = Enum.ScrollingDirection.Y
	log.ScrollBarThickness = 6
	log.ScrollBarImageColor3 = theme.Arcade.GreyOwned
	log.ZIndex = 43
	log.Parent = logWell
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 2),
	}).Parent = log
	self._log = log

	self:_RenderCommands()
	self:_Log("panel ready — commands are advisory; the server decides.")
end

-- ========================================================================
-- Command rows
-- ========================================================================

function AdminPanelScreen:_RenderCommands()
	-- Reached from _ApplyData on every payload, so it branches here.
	if self._gp then
		self:_RenderGPCommands()
		return
	end
	local theme = self:GetTheme()
	-- Destroy the components (not just their instances) so their theme
	-- registrations and connections go with them.
	for _, button in self._rowButtons do
		button:Destroy()
	end
	table.clear(self._rowButtons)
	self._list:ClearAllChildren()
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 8),
	}).Parent = self._list

	for order, command in self._commands do
		local hasField = command.kind == "value"
		local row = UIStyler.Frame("Row_" .. command.id)
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, -8, 0, ROW_H)
		row.LayoutOrder = order
		row.ZIndex = 44
		row.Parent = self._list

		local field: TextBox? = nil
		if hasField then
			local holder = UIStyler.Frame("FieldHolder")
			holder.BackgroundTransparency = 1
			holder.AnchorPoint = Vector2.new(1, 0)
			holder.Position = UDim2.new(1, 0, 0, 0)
			holder.Size = UDim2.fromOffset(FIELD_W, ROW_H)
			holder.ZIndex = 45
			holder.Parent = row
			field = makeField(theme, holder, "0", theme.Fonts.Numeric, 20)
		end

		local button = UIButtonComponent.new()
		button:Create(row, {
			text = command.label,
			variant = command.variant or "Grey",
			size = UDim2.new(1, if hasField then -(FIELD_W + 8) else 0, 0, ROW_H),
			onClick = function()
				local value: any = nil
				if field then
					value = tonumber(field.Text)
					if value == nil and field.Text ~= "" then
						value = field.Text
					end
				end
				self:_Run(command, value)
			end,
		})
		button.Root.ZIndex = 45
		table.insert(self._rowButtons, button)
	end
end

-- ========================================================================
-- Running + log
-- ========================================================================

function AdminPanelScreen:_Log(line: string)
	local theme = self:GetTheme()
	self._logCount += 1
	local label = UIStyler.TextLabel("Line")
	label.RichText = false
	label.Text = string.format("[%03d] %s", self._logCount % 1000, line)
	local styled = theme.Chrome ~= nil
	label.FontFace = if styled then theme.Fonts.Body else Font.fromEnum(Enum.Font.Code)
	label.TextSize = 15
	-- Under GP the log rides a BLUSH well, where the soft ink measures 4.12:1;
	-- the output you actually read gets full ink instead.
	label.TextColor3 = if self._gp then theme.Colors.TextPrimary else theme.Arcade.IceBlue
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(1, 0, 0, 18)
	label.LayoutOrder = self._logCount
	label.ZIndex = 44
	label.Parent = self._log
	table.insert(self._logLines, label)
	-- Bounded: the log is a debug tail, not a transcript.
	while #self._logLines > LOG_LIMIT do
		local oldest = table.remove(self._logLines, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	-- AutomaticCanvasSize resolves a frame later, so pin to the tail next frame.
	local log = self._log
	task.defer(function()
		if log.Parent then
			log.CanvasPosition = Vector2.new(0, log.AbsoluteCanvasSize.Y)
		end
	end)
end

function AdminPanelScreen:_Run(command: Command, value: any)
	local echo: string? = nil
	if self._onCommand then
		local ok, result = pcall(self._onCommand, command.id, value)
		echo = if ok and type(result) == "string" then result else nil
		if not ok then
			self:_Log("ERROR " .. command.id .. ": " .. tostring(result))
			return
		end
	end
	if echo then
		self:_Log(echo)
	elseif value ~= nil then
		self:_Log(string.format("%s %s%s", command.id, tostring(value), if self._onCommand then "" else "  (no handler)"))
	else
		self:_Log(command.id .. (if self._onCommand then "" else "  (no handler)"))
	end
end

function AdminPanelScreen:_RunFreeText()
	local text = self._entryBox.Text
	if text == "" then
		return
	end
	self._entryBox.Text = ""
	self:_Run({ id = text, label = text, kind = "action" }, nil)
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function AdminPanelScreen:_ApplyData(data: any?)
	if type(data) ~= "table" then
		return
	end
	if type(data.commands) == "table" and #data.commands > 0 then
		self._commands = data.commands
		self:_RenderCommands()
	end
	if type(data.onCommand) == "function" then
		self._onCommand = data.onCommand
	end
end

function AdminPanelScreen:_OnShow(data: any?)
	self:_ApplyData(data)
	UIChrome.PopIn(self:GetTheme(), self._panel)
end

-- Update never re-pops: only Show is an entrance (doc §5).
function AdminPanelScreen:Update(data: any)
	if self._built then
		self:_ApplyData(data)
	end
end

-- A style rebuild destroys the Gui but NOT the shadow budget count, and the
-- pooled log-line table outlives the shell.
function AdminPanelScreen:_OnTeardown()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	GPLayoutKit.ReleaseShadows(self._gpRowShadows)
	self._gpShadows = nil
	self._gpRowShadows = nil
	table.clear(self._rowButtons)
	table.clear(self._logLines)
	self._logCount = 0
	self._runButton = nil
	self._gpClose = nil
	self._panel = nil
end

function AdminPanelScreen:Destroy()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	GPLayoutKit.ReleaseShadows(self._gpRowShadows)
	for _, button in self._rowButtons do
		button:Destroy()
	end
	table.clear(self._rowButtons)
	if self._runButton then
		self._runButton:Destroy()
		self._runButton = nil
	end
	UIScreenBase.Destroy(self)
end

return AdminPanelScreen
