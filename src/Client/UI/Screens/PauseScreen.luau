--!strict
-- Pause overlay. A Roblox server cannot actually pause, so this screen never
-- pretends to: it reads as a MENU (the §7.4 modal recipe — dim 0.45, centred
-- card, red header) with one honest muted line saying the world keeps running.
-- That line is the whole design brief for this screen; everything else is the
-- standard arcade button stack.
--
-- The stack is four big 380×64 arcade buttons in the house colour grammar
-- (green = confirm/forward, blue = secondary, red = danger). LEAVE is
-- destructive, so it never fires straight through — it raises the shared
-- confirm modal first (ModalScreen, kind = "Danger").
--
-- Show{ title, onResume, onSettings, onInventory, onLeave } — every field is
-- optional; unwired routes fall back to the screen controller, and a route
-- with nowhere to go answers with a toast instead of going silent (§11.1).

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local ACLayoutKit = require(script.Parent.Parent.Framework.ACLayoutKit)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)

local PauseScreen = setmetatable({}, { __index = UIScreenBase })
PauseScreen.__index = PauseScreen

-- GPLayoutKit ships Page/Card/Tabs/StatRow/PricePill but NO button builder, and
-- UIButtonComponent frames itself through UIChrome.Stroke — which under this
-- pack's Chrome (StrokeFollowsAccent = false) returns a BLACK hairline and
-- breaks pack law 1 on sight. So the pack's menu button is improvised here: a
-- TRANSPARENT hit target (a solid GuiButton would also trip UIStyleEnforcer's
-- black stroke backstop) over a painted petal chip with its own deepened stroke
-- and hue-matched shadow, the archive icon in its authored slot, an ink label,
-- and UIChrome.Animate's hover/press juice.
local function gpMenuButton(theme: Types.UITheme, parent: Instance, opts: {
	text: string,
	fill: Color3,
	sizePx: Vector2,
	index: number,
	layoutOrder: number?,
	iconName: string?,
	onClick: (() -> ())?,
}, sink: { any }?): TextButton
	local button = Instance.new("TextButton")
	button.Name = "GPMenuAction"
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(opts.sizePx.X, opts.sizePx.Y)
	if opts.layoutOrder then
		button.LayoutOrder = opts.layoutOrder
	end
	button.Parent = parent

	local chip = UIStyler.Frame("Chip")
	chip.BackgroundColor3 = opts.fill
	chip.BackgroundTransparency = 0
	chip.Size = UDim2.fromScale(1, 1)
	chip.ZIndex = 43
	chip.Parent = button
	-- Alternating petal/mirror by index: the stack reads hand-arranged.
	GPLayoutKit.Petal(theme, chip, opts.index)
	GPLayoutKit.SoftStroke(theme, chip, opts.fill)
	GPLayoutKit.Shadow(theme, chip, "sm", sink, opts.fill)

	-- Ink, never TextOnPrimary: the near-white measures 2.14:1 on rose.
	local label = GPLayoutKit.Text(theme, 22, theme.Colors.TextPrimary, "Label")
	label.Text = opts.text -- verbatim: this pack never shouts
	label.ZIndex = 44
	label.Parent = chip

	if opts.iconName then
		-- Through the KIT: the archive's glyph FALLBACK is born pure white on a
		-- pure black text stroke, and both are banned here.
		local icon = GPLayoutKit.Icon(theme, chip, opts.iconName, 34)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 20, 0.5, 0)
		icon.ZIndex = 44
		label.Position = UDim2.fromOffset(66, 0)
		label.Size = UDim2.new(1, -86, 1, 0)
		label.TextXAlignment = Enum.TextXAlignment.Left
	else
		label.Size = UDim2.fromScale(1, 1)
	end

	if opts.onClick then
		button.Activated:Connect(opts.onClick)
	end
	UIChrome.Animate(theme, button, chip)
	return button
end

-- Fixed px at the 1650×1020 baseline.
local CARD = Vector2.new(540, 560)
local BUTTON_W = 380
local BUTTON_H = 64
local BUTTON_GAP = 14
local STACK_Y = 96

local DEFAULT_TITLE = "POTTERY CLASH"
local WORLD_NOTE = "The world keeps running while this is open."

function PauseScreen.new()
	local self = UIScreenBase.new("PauseScreen", 14)
	self._title = DEFAULT_TITLE
	self._handlers = {} :: { [string]: () -> () }
	self._buttons = {} :: { any }
	return setmetatable(self, PauseScreen)
end

function PauseScreen:_Close()
	self.ScreenController:HideScreen("pause")
end

-- Route to another screen, closing the pause menu on the way. The exclusive
-- panel set already closes pause when a panel opens, but a missing screen
-- (a catalog entry a given game didn't build) must still ANSWER — dimming or
-- silence is not an option, so it toasts the reason (doc §11.1).
function PauseScreen:_Route(id: string, missingText: string)
	local controller = self.ScreenController
	if controller:GetScreen(id) then
		controller:ShowScreen(id)
		return
	end
	local hud = controller:GetScreen("hud")
	if hud then
		hud:PushToast({ text = missingText, variant = "Error" })
	end
end

function PauseScreen:_Fire(name: string)
	local handler = self._handlers[name]
	if handler then
		task.spawn(handler)
		return true
	end
	return false
end

function PauseScreen:_Leave()
	-- Destructive: the shared confirm modal owns the decision, not this screen.
	-- The payload stays STYLE-INDEPENDENT: ModalScreen retitles shouted copy for
	-- display under GP (pack law 5), so no caller has to fork its own data.
	self.ScreenController:ShowModal({
		kind = "Danger",
		title = "LEAVE GAME?",
		body = "Your progress saves automatically. You can rejoin any time.",
		confirmKey = "LEAVE",
		cancelKey = "STAY",
		onConfirm = function()
			self:_Close()
			if not self:_Fire("leave") then
				local hud = self.ScreenController:GetScreen("hud")
				if hud then
					hud:PushToast({ text = "Leaving...", variant = "Info" })
				end
			end
		end,
	})
end

function PauseScreen:_AddButton(parent: Instance, order: number, text: string, variant: string, iconName: string, onClick: () -> ())
	local button = UIButtonComponent.new()
	button:Create(parent, {
		text = text,
		variant = variant,
		iconId = IconArchive.Id(iconName),
		size = UDim2.fromOffset(BUTTON_W, BUTTON_H),
		layoutOrder = order,
		onClick = onClick,
	})
	table.insert(self._buttons, button)
	return button
end

function PauseScreen:_BuildContent()
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
	if self:LayoutKit() == "AC" then
		self:_BuildACLayout()
		return
	end
	local theme = self:GetTheme()

	-- The one modal recipe (doc §7.4). Closing the card == resuming: a pause
	-- menu's X can only mean "back to the game".
	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "PAUSED",
		sizePx = CARD,
		onClose = function()
			self:_Close()
			self:_Fire("resume")
		end,
	})
	self._modal = modal
	local content = modal.content

	-- The game's own wordmark sits above the stack: this is a menu, and a menu
	-- says whose menu it is.
	local title = UIChrome.Text("Title", 34, theme.Arcade.Gold)
	title.RichText = false
	title.Text = self._title
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Size = UDim2.new(1, 0, 0, 40)
	title.ZIndex = 43
	title.Parent = content
	self._titleLabel = title

	-- The honest line. Quiet body font on purpose — it is information, not a
	-- warning, and it must never compete with the buttons.
	local note = UIChrome.BodyText("WorldNote", 15, theme.Studio.TextMuted)
	note.Text = WORLD_NOTE
	note.Position = UDim2.fromOffset(0, 46)
	note.Size = UDim2.new(1, 0, 0, 22)
	note.ZIndex = 43
	note.Parent = content

	local stack = UIStyler.Frame("Stack")
	stack.BackgroundTransparency = 1
	stack.Position = UDim2.fromOffset(0, STACK_Y)
	stack.Size = UDim2.new(1, 0, 0, BUTTON_H * 4 + BUTTON_GAP * 3)
	stack.ZIndex = 43
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, BUTTON_GAP),
	}).Parent = stack
	stack.Parent = content

	self:_AddButton(stack, 1, "RESUME", "Green", "arrowRight", function()
		self:_Close()
		self:_Fire("resume")
	end)
	self:_AddButton(stack, 2, "SETTINGS", "Blue", "settings", function()
		if not self:_Fire("settings") then
			self:_Route("settings", "Settings aren't available here")
		end
	end)
	self:_AddButton(stack, 3, "INVENTORY", "Blue", "backpack", function()
		if not self:_Fire("inventory") then
			self:_Route("inventory", "Inventory isn't available here")
		end
	end)
	self:_AddButton(stack, 4, "LEAVE", "Red", "teleport", function()
		self:_Leave()
	end)

	-- Footer hint: the keyboard/gamepad way out, so the menu teaches its own
	-- shortcut instead of trapping players who opened it by accident.
	local hint = UIChrome.BodyText("Hint", 14, theme.Arcade.IceBlue)
	hint.Text = "ESC to resume"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.fromScale(0.5, 1)
	hint.Size = UDim2.new(1, 0, 0, 20)
	hint.ZIndex = 43
	hint.Parent = content
end

-- GIRLY POP menu (theme.LayoutKit == "GP"): UIChrome.ModalCard already IS the
-- pastel ceramics card under this pack (warm plum scrim, cream plate on a large
-- radius with a hue-matched shadow, rose header slab wearing its glaze sheen
-- and scalloped skirt, leaf-cornered coral close), so this branch supplies the
-- CONTENT only — the wordmark, the one honest line, the same four routes as
-- petal chips in the same order at the same 380×64, and the shortcut hint.
--
-- Nothing is dropped: four buttons stay four buttons, each keeping its archive
-- icon and its exact callback. The colour grammar survives the re-skin — matcha
-- reads forward, sky reads secondary, coral reads destructive.
function PauseScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	self._gpShadows = {}

	-- Closing the card == resuming: a pause menu's X can only mean "back to
	-- the game". Title Case is applied by the GP modal itself.
	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "Paused",
		sizePx = CARD,
		onClose = function()
			self:_Close()
			self:_Fire("resume")
		end,
	})
	self._modal = modal
	local content = modal.content

	-- The game's own wordmark: a menu says whose menu it is. INK on cream —
	-- butter gold there is a 1.6:1 headline.
	local title = GPLayoutKit.Text(theme, 34, theme.Colors.TextPrimary, "Title")
	title.RichText = false
	title.Text = self._title
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Size = UDim2.new(1, 0, 0, 40)
	title.ZIndex = 43
	title.Parent = content
	self._titleLabel = title

	-- The honest line, unchanged: information, not a warning, and it must never
	-- compete with the buttons.
	local note = GPLayoutKit.BodyText(theme, 15, theme.Colors.TextSecondary, "WorldNote")
	note.Text = WORLD_NOTE
	note.Position = UDim2.fromOffset(0, 46)
	note.Size = UDim2.new(1, 0, 0, 22)
	note.ZIndex = 43
	note.Parent = content

	local stack = UIStyler.Frame("Stack")
	stack.BackgroundTransparency = 1
	stack.Position = UDim2.fromOffset(0, STACK_Y)
	stack.Size = UDim2.new(1, 0, 0, BUTTON_H * 4 + BUTTON_GAP * 3)
	stack.ZIndex = 43
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, BUTTON_GAP),
	}).Parent = stack
	stack.Parent = content

	local size = Vector2.new(BUTTON_W, BUTTON_H)
	gpMenuButton(theme, stack, {
		text = "Resume",
		fill = theme.Colors.Secondary,
		sizePx = size,
		index = 1,
		layoutOrder = 1,
		iconName = "arrowRight",
		onClick = function()
			self:_Close()
			self:_Fire("resume")
		end,
	}, self._gpShadows)
	gpMenuButton(theme, stack, {
		text = "Settings",
		fill = theme.Arcade.Blue,
		sizePx = size,
		index = 2,
		layoutOrder = 2,
		iconName = "settings",
		onClick = function()
			if not self:_Fire("settings") then
				self:_Route("settings", "Settings aren't available here")
			end
		end,
	}, self._gpShadows)
	gpMenuButton(theme, stack, {
		text = "Inventory",
		fill = theme.Arcade.Blue,
		sizePx = size,
		index = 3,
		layoutOrder = 3,
		iconName = "backpack",
		onClick = function()
			if not self:_Fire("inventory") then
				self:_Route("inventory", "Inventory isn't available here")
			end
		end,
	}, self._gpShadows)
	gpMenuButton(theme, stack, {
		text = "Leave",
		fill = theme.Arcade.Red,
		sizePx = size,
		index = 4,
		layoutOrder = 4,
		iconName = "teleport",
		onClick = function()
			self:_Leave()
		end,
	}, self._gpShadows)

	-- Footer hint: the menu teaches its own way out.
	local hint = GPLayoutKit.BodyText(theme, 14, theme.Colors.TextSecondary, "Hint")
	hint.Text = "ESC to resume"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.fromScale(0.5, 1)
	hint.Size = UDim2.new(1, 0, 0, 20)
	hint.ZIndex = 43
	hint.Parent = content
end

-- A style rebuild destroys the Gui, but the UIShadow BUDGET only falls when a
-- handle is released — hand every GP shadow back here.
function PauseScreen:_OnTeardown()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
end

-- AC system menu (theme.LayoutKit == "AC"): the same dim over the world, but
-- the card gives way to a left-anchored terminal column — mono "SYSTEM"
-- title over quiet rows (one per classic action, same callbacks/order), each
-- lighting an accent notch + bright ink on hover, with a key-hint line
-- below. The column is self._modal.content so _OnShow's PopIn lands on it.
function PauseScreen:_BuildACLayout()
	local theme = self:GetTheme()

	-- Same dim class as the classic modal recipe (doc §7.4: black @ 0.45).
	local dim = UIStyler.Frame("Dim")
	dim.BackgroundColor3 = theme.Colors.Overlay
	dim.BackgroundTransparency = 0.45
	dim.ZIndex = 40
	dim.Parent = self.Root

	local column = UIStyler.Frame("Menu")
	column.BackgroundTransparency = 1
	column.AnchorPoint = Vector2.new(0, 0.5)
	column.Position = UDim2.new(0, 110, 0.5, 0)
	column.Size = UDim2.fromOffset(340, 280)
	column.ZIndex = 41
	column.Parent = self.Root
	ACLayoutKit.Brackets(theme, column)
	self._modal = { content = column } :: any

	-- Whose menu this is: the wordmark as a dim mono strap line.
	local wordmark = UIChrome.BodyText("Wordmark", 11, theme.Colors.TextSecondary)
	wordmark.RichText = false
	wordmark.Text = self._title
	wordmark.TextXAlignment = Enum.TextXAlignment.Left
	wordmark.TextTruncate = Enum.TextTruncate.AtEnd
	wordmark.Position = UDim2.fromOffset(14, 0)
	wordmark.Size = UDim2.new(1, -28, 0, 16)
	wordmark.Parent = column
	self._titleLabel = wordmark

	local tick = UIStyler.Frame("Tick")
	tick.BackgroundColor3 = theme.Colors.Accent
	tick.BorderSizePixel = 0
	tick.Position = UDim2.fromOffset(0, 24)
	tick.Size = UDim2.fromOffset(4, 18)
	tick.Parent = column

	local title = UIChrome.Text("Title", 18, theme.Colors.TextPrimary)
	title.Text = "SYSTEM"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(14, 22)
	title.Size = UDim2.new(1, -14, 0, 22)
	title.Parent = column

	local rule = ACLayoutKit.Rule(theme, column, 0.5)
	rule.Position = UDim2.fromOffset(0, 50)

	-- The honest line survives the style swap: information, not a warning.
	local note = UIChrome.BodyText("WorldNote", 11, theme.Colors.TextSecondary)
	note.Text = WORLD_NOTE
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.Position = UDim2.fromOffset(14, 56)
	note.Size = UDim2.new(1, -14, 0, 14)
	note.Parent = column

	-- One quiet mono row per classic action: accent notch + bright ink on
	-- hover, hairline underline, danger rows keep the semantic red ink.
	local function menuRow(order: number, text: string, danger: boolean, onClick: () -> ()): TextButton
		local restInk = danger and theme.Colors.Error or theme.Colors.TextSecondary
		local hotInk = danger and theme.Colors.Error or theme.Colors.TextPrimary

		local row = Instance.new("TextButton")
		row.Name = text .. "Row"
		row.BackgroundColor3 = theme.Colors.SurfaceRaised
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.AutoButtonColor = false
		row.Position = UDim2.fromOffset(0, 84 + (order - 1) * 38)
		row.Size = UDim2.new(1, 0, 0, 34)
		row.FontFace = theme.Fonts.Button
		row.TextSize = 14
		row.TextColor3 = restInk
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Text = "   " .. text
		row.Parent = column

		local notch = UIStyler.Frame("Notch")
		notch.BackgroundColor3 = danger and theme.Colors.Error or theme.Colors.Accent
		notch.BorderSizePixel = 0
		notch.Position = UDim2.fromOffset(0, 5)
		notch.Size = UDim2.new(0, 3, 1, -10)
		notch.Visible = false
		notch.Parent = row

		local underline = ACLayoutKit.Rule(theme, row, 0.85)
		underline.AnchorPoint = Vector2.new(0, 1)
		underline.Position = UDim2.new(0, 0, 1, 0)

		row.MouseEnter:Connect(function()
			notch.Visible = true
			row.TextColor3 = hotInk
			row.BackgroundTransparency = 0.85
		end)
		row.MouseLeave:Connect(function()
			notch.Visible = false
			row.TextColor3 = restInk
			row.BackgroundTransparency = 1
		end)
		row.Activated:Connect(onClick)
		return row
	end

	menuRow(1, "RESUME", false, function()
		self:_Close()
		self:_Fire("resume")
	end)
	menuRow(2, "SETTINGS", false, function()
		if not self:_Fire("settings") then
			self:_Route("settings", "Settings aren't available here")
		end
	end)
	menuRow(3, "INVENTORY", false, function()
		if not self:_Fire("inventory") then
			self:_Route("inventory", "Inventory isn't available here")
		end
	end)
	menuRow(4, "LEAVE", true, function()
		self:_Leave()
	end)

	-- Footer hints: the menu teaches its own way out.
	local hint = UIChrome.BodyText("Hint", 11, theme.Colors.TextSecondary)
	hint.Text = "[ESC] RESUME   [CLICK] SELECT"
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.Position = UDim2.new(0, 0, 1, 0)
	hint.Size = UDim2.new(1, 0, 0, 14)
	hint.Parent = column
end

function PauseScreen:_OnShow(data: any?)
	local d = data or {}
	if d.title then
		self._title = d.title
		self._titleLabel.Text = d.title
	end
	self._handlers = {
		resume = d.onResume,
		settings = d.onSettings,
		inventory = d.onInventory,
		leave = d.onLeave,
	} :: any
	UIChrome.PopIn(self:GetTheme(), self._modal.content)
end

function PauseScreen:Destroy()
	for _, button in self._buttons do
		button:Destroy()
	end
	table.clear(self._buttons)
	UIScreenBase.Destroy(self)
end

return PauseScreen
