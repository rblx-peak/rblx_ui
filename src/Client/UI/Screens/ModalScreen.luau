--!strict
-- Generic confirm/cancel/info dialog host. One instance serves all modals; the
-- controller shows it with ModalData describing the current dialog.
--
-- Pottery Clash §7.4: the panel component IS the modal card recipe (centred
-- black-@-0.4 card, 3px black stroke, red 64px header, transparent content
-- inset) — this screen only supplies the fixed 560×320 px card size (authored
-- at the 1650×1020 baseline; UIScreenBase's UIScale handles devices), the body
-- text and the confirm/cancel row. Open/close is an instant Visible flip; the
-- pop lives on the panel's content.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIPanelComponent = require(script.Parent.Parent.Components.UIPanelComponent)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)

local ModalScreen = setmetatable({}, { __index = UIScreenBase })
ModalScreen.__index = ModalScreen

-- GP never shouts (pack law 5), and THIS screen is where the pack's copy law
-- has to be enforced for everybody: a modal's title and its two button captions
-- arrive from whichever screen raised it, and six of them ("LEAVE GAME?",
-- "ABANDON QUEST", "DELETE READ MAIL", "UNLOCK PREMIUM", "LEAVE PARTY", "FAST
-- TRAVEL") are authored in arcade all-caps. Retitling them HERE, at display
-- time, is what keeps that law from depending on each caller remembering it —
-- and it means no ModalData payload has to vary by layout kit. Every other kit
-- gets the strings byte-identical.
local gpTitleCase = GPLayoutKit.TitleCase

-- GP has no button builder in its kit, and UIButtonComponent frames itself
-- through UIChrome.Stroke — which under this pack's Chrome
-- (StrokeFollowsAccent = false) returns a BLACK hairline and breaks pack law 1.
-- This shim is the pack's dialog button AND answers the exact surface _OnShow
-- drives on the classic components: .Root, .Props.variant, :SetContent and
-- :ApplyTheme. The variant GRAMMAR is preserved intact — Green reads forward
-- (matcha), Red reads destructive (the pack's soft coral, never fire-engine),
-- Ghost reads quiet (blush) — so a Danger modal still recolours its confirm.
local function gpDialogButton(theme: Types.UITheme, parent: Instance, opts: {
	variant: string,
	textKey: string,
	sizePx: Vector2,
	index: number,
	layoutOrder: number,
	onClick: () -> (),
}, sink: { any }?): any
	local button = Instance.new("TextButton")
	button.Name = "GPDialogAction"
	button.BackgroundTransparency = 1 -- solid GuiButtons trip the enforcer's black stroke
	button.Text = ""
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(opts.sizePx.X, opts.sizePx.Y)
	button.LayoutOrder = opts.layoutOrder
	button.Parent = parent

	local chip = UIStyler.Frame("Chip")
	chip.BackgroundTransparency = 0
	chip.Size = UDim2.fromScale(1, 1)
	chip.Parent = button
	GPLayoutKit.Petal(theme, chip, opts.index)
	local stroke = GPLayoutKit.SoftStroke(theme, chip, theme.Colors.Surface)
	local shadow = GPLayoutKit.Shadow(theme, chip, "sm", sink, theme.Colors.Surface)

	-- Ink on every fill: TextOnPrimary (near-white) measures 2.14:1 on rose.
	local label = GPLayoutKit.Text(theme, theme.TextSizes.Button + 3, theme.Colors.TextPrimary, "Label")
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 2
	label.Parent = chip

	local shim: any = { Root = button, Props = { variant = opts.variant } }
	function shim.ApplyTheme(_self: any, activeTheme: Types.UITheme)
		local variant = shim.Props.variant
		local fill = activeTheme.Colors.Surface
		if variant == "Green" then
			fill = activeTheme.Colors.Secondary
		elseif variant == "Red" then
			fill = activeTheme.Arcade.Red
		elseif variant == "Blue" then
			fill = activeTheme.Arcade.Blue
		end
		chip.BackgroundColor3 = fill
		-- The stroke and the SHADOW retint with the fill: a rose element casts a
		-- rose shadow, a matcha one casts matcha. Never grey.
		local deep = GPLayoutKit.Deepen(activeTheme, fill, 1)
		stroke.Color = deep
		shadow.Instance.Color = deep
		label.TextColor3 = activeTheme.Colors.TextPrimary
	end
	function shim.SetContent(_self: any, content: any)
		if content and content.textKey then
			label.Text = TextConfig.Resolve(content.textKey)
		elseif content and content.text then
			label.Text = content.text
		end
	end
	function shim.Destroy(_self: any)
		button:Destroy()
	end

	shim:ApplyTheme(theme)
	shim:SetContent({ textKey = opts.textKey })
	button.Activated:Connect(opts.onClick)
	UIChrome.Animate(theme, button, chip)
	return shim
end

function ModalScreen.new()
	local self = UIScreenBase.new("ModalScreen", 20)
	self._data = nil :: any
	return setmetatable(self, ModalScreen)
end

function ModalScreen:_BuildContent()
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
	if self:LayoutKit() == "AC" then
		self:_BuildACLayout()
		return
	end
	local theme = self:GetTheme()

	-- Invisible click-catcher, not a dim overlay — blocks clicks from passing
	-- through to whatever's behind the modal, without a second black tint on
	-- top of the card's own §7.4 dim. Full-screen on purpose: it must cover
	-- the TRUE viewport, so it carries no aspect/size lock of any kind.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundTransparency = 1
	backdrop.Parent = self.Root
	self._backdrop = backdrop

	-- The §7.4 modal card, fixed px (no pack WidthScale, no aspect constraint).
	local panel = UIPanelComponent.new()
	self._panel = panel
	self:_SetAnimatedPanel(panel)
	panel:Create(self.Root, {
		title = "",
		showClose = false,
		size = UDim2.fromOffset(560, 320),
	})

	-- Body: white FredokaOne 22 with the black outline, wrapped, sitting
	-- directly on the transparent content — the world shows through the
	-- black-0.4 card behind it. (UIChrome.Text labels default to RichText,
	-- so dialogs may pass styled bodies: coloured item lists, bold totals.)
	local body = UIChrome.Text("Body", 22, theme.Colors.TextPrimary)
	body.Size = UDim2.new(1, 0, 1, -64)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.Parent = panel.Body
	self._body = body

	-- Confirm/cancel row, bottom-right (52px tall, matching the 170×52 buttons).
	local buttonRow = UIStyler.Frame("Buttons")
	buttonRow.BackgroundTransparency = 1
	buttonRow.AnchorPoint = Vector2.new(0, 1)
	buttonRow.Position = UDim2.new(0, 0, 1, 0)
	buttonRow.Size = UDim2.new(1, 0, 0, 52)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12),
	}).Parent = buttonRow
	buttonRow.Parent = panel.Body

	self._cancelButton = UIButtonComponent.new()
	self._cancelButton:Create(buttonRow, {
		textKey = "modal.cancel",
		variant = "Ghost",
		size = UDim2.fromOffset(170, 52),
		layoutOrder = 1,
		onClick = function()
			self:_Close(false)
		end,
	})

	self._confirmButton = UIButtonComponent.new()
	self._confirmButton:Create(buttonRow, {
		textKey = "modal.confirm",
		variant = "Green",
		size = UDim2.fromOffset(170, 52),
		layoutOrder = 2,
		onClick = function()
			self:_Close(true)
		end,
	})
end

-- GIRLY POP layout: UIChrome.ModalCard already IS the pastel ceramics dialog
-- under GP (warm plum scrim, cream card on a large radius with a hue-matched
-- shadow, rose header slab with its glaze sheen and scalloped skirt, leaf-
-- cornered coral close) — so this branch only supplies the CONTENT: ink body
-- copy on the cream well and a confirm/cancel row of petal chips. Same
-- ModalData contract as every other branch: _OnShow keeps writing
-- self._panel._title / self._body and driving the same two button handles.
function ModalScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	self._gpShadows = {}

	-- Same invisible click-catcher as classic: it must cover the TRUE
	-- viewport so clicks cannot fall through to whatever is behind the dialog.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundTransparency = 1
	backdrop.Parent = self.Root
	self._backdrop = backdrop

	local card = UIChrome.ModalCard(theme, self.Root, {
		title = "",
		sizePx = Vector2.new(560, 320),
		showClose = false,
	})
	-- _OnShow writes the title through the classic panel handle; expose the
	-- card's own title label under the same `_title` contract.
	self._panel = { _title = card.title } :: any
	-- The base drives the intro/outro through the registered panel, and this
	-- card is not a UIPanelComponent — so a two-method shim gives the GP dialog
	-- the house POP without touching the shared Show/Hide path.
	self:_SetAnimatedPanel({
		AnimateIn = function(_self: any)
			UIChrome.PopIn(self:GetTheme(), card.card)
		end,
		AnimateOut = function(_self: any)
			return nil
		end,
	} :: any)

	-- Body in the pack's warm plum ink on the cream well (RichText stays on:
	-- dialogs may pass styled bodies — coloured item lists, bold totals).
	local body = GPLayoutKit.Text(theme, 22, theme.Colors.TextPrimary, "Body")
	body.Size = UDim2.new(1, 0, 1, -64)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.ZIndex = 43
	body.Parent = card.content
	self._body = body

	-- Confirm/cancel row, bottom-right — the classic 170×52 metrics, so no
	-- button shrinks for being cute.
	local buttonRow = UIStyler.Frame("Buttons")
	buttonRow.BackgroundTransparency = 1
	buttonRow.AnchorPoint = Vector2.new(0, 1)
	buttonRow.Position = UDim2.new(0, 0, 1, 0)
	buttonRow.Size = UDim2.new(1, 0, 0, 52)
	buttonRow.ZIndex = 43
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12),
	}).Parent = buttonRow
	buttonRow.Parent = card.content

	self._cancelButton = gpDialogButton(theme, buttonRow, {
		variant = "Ghost",
		textKey = "modal.cancel",
		sizePx = Vector2.new(170, 52),
		index = 0,
		layoutOrder = 1,
		onClick = function()
			self:_Close(false)
		end,
	}, self._gpShadows)

	self._confirmButton = gpDialogButton(theme, buttonRow, {
		variant = "Green",
		textKey = "modal.confirm",
		sizePx = Vector2.new(170, 52),
		index = 1,
		layoutOrder = 2,
		onClick = function()
			self:_Close(true)
		end,
	}, self._gpShadows)
end

-- A style rebuild destroys the Gui, but the UIShadow BUDGET only falls when a
-- handle is released — hand every GP shadow back here.
function ModalScreen:_OnTeardown()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
end

-- ARMORED CORE layout: UIChrome.ModalCard already IS the terminal alert box
-- under AC (hairline card, accent-tick mono header, corner brackets, footer
-- strip) — this branch only swaps the arcade content for dense mono
-- equivalents: a 13px body and a tight 30px confirm/cancel row. Same ModalData
-- contract: _OnShow keeps writing self._panel._title / self._body and driving
-- the same button components unchanged.
function ModalScreen:_BuildACLayout()
	local theme = self:GetTheme()

	-- Same invisible click-catcher as classic: it must cover the TRUE
	-- viewport so clicks cannot fall through to whatever is behind the dialog.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundTransparency = 1
	backdrop.Parent = self.Root
	self._backdrop = backdrop

	-- The terminal alert box (under 400px tall stays a centred dialog).
	local card = UIChrome.ModalCard(theme, self.Root, {
		title = "",
		sizePx = Vector2.new(560, 320),
		showClose = false,
	})
	-- _OnShow writes the title through the classic panel handle; expose the
	-- card's terminal title label under the same `_title` contract. No
	-- _SetAnimatedPanel here — AC dialogs snap, they do not pop.
	self._panel = { _title = card.title } :: any

	-- Dense mono body (RichText stays on: dialogs may pass styled bodies).
	local body = UIChrome.BodyText("Body", 13, theme.Colors.TextPrimary)
	body.Size = UDim2.new(1, 0, 1, -44)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.Parent = card.content
	self._body = body

	-- Confirm/cancel row, bottom-right, terminal metrics; the button
	-- components restyle themselves under AC.
	local buttonRow = UIStyler.Frame("Buttons")
	buttonRow.BackgroundTransparency = 1
	buttonRow.AnchorPoint = Vector2.new(0, 1)
	buttonRow.Position = UDim2.new(0, 0, 1, 0)
	buttonRow.Size = UDim2.new(1, 0, 0, 30)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = buttonRow
	buttonRow.Parent = card.content

	self._cancelButton = UIButtonComponent.new()
	self._cancelButton:Create(buttonRow, {
		textKey = "modal.cancel",
		variant = "Ghost",
		size = UDim2.fromOffset(150, 30),
		layoutOrder = 1,
		onClick = function()
			self:_Close(false)
		end,
	})

	self._confirmButton = UIButtonComponent.new()
	self._confirmButton:Create(buttonRow, {
		textKey = "modal.confirm",
		variant = "Green",
		size = UDim2.fromOffset(150, 30),
		layoutOrder = 2,
		onClick = function()
			self:_Close(true)
		end,
	})
end

function ModalScreen:_Close(confirmed: boolean)
	local data = self._data
	self.ScreenController:HideModal()
	if data then
		if confirmed and data.onConfirm then
			data.onConfirm()
		elseif not confirmed and data.onCancel then
			data.onCancel()
		end
	end
end

function ModalScreen:_OnShow(data: any?)
	self._data = data
	if not data then
		return
	end
	local isInfo = data.kind == "Info"
	-- Display-only casing seam. Under GP the caller's shouted copy is retitled
	-- on the way to the label; under every other kit the key is passed through
	-- untouched, so those branches resolve it exactly as they always did.
	local gp = self:LayoutKit() == "GP"
	local function caption(key: string): any
		if gp then
			return { text = gpTitleCase(TextConfig.Resolve(key)) }
		end
		return { textKey = key }
	end

	-- Title lands on the panel's own header label (§7.4: FredokaOne 34 white
	-- on the red bar).
	local title = TextConfig.Resolve(data.titleKey or data.title)
	self._panel._title.Text = if gp then gpTitleCase(title) else title
	self._body.Text = TextConfig.Resolve(data.bodyKey or data.body)

	-- Confirm = green (HUD confirm colour, doc §3.3); Danger flips it to the
	-- arcade red. Danger also wants a red header — which the §7.4 header bar
	-- already is (#EB2D1E for every kind), so no header work is needed.
	self._confirmButton:SetContent(caption(data.confirmKey or (isInfo and "modal.ok" or "modal.confirm")))
	self._confirmButton.Props.variant = data.kind == "Danger" and "Red" or "Green"
	self._confirmButton:ApplyTheme(self:GetTheme())
	self._cancelButton.Root.Visible = not isInfo
	if not isInfo then
		self._cancelButton:SetContent(caption(data.cancelKey or "modal.cancel"))
	end
end

return ModalScreen
