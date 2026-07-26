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

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIPanelComponent = require(script.Parent.Parent.Components.UIPanelComponent)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)

local ModalScreen = setmetatable({}, { __index = UIScreenBase })
ModalScreen.__index = ModalScreen

function ModalScreen.new()
	local self = UIScreenBase.new("ModalScreen", 20)
	self._data = nil :: any
	return setmetatable(self, ModalScreen)
end

function ModalScreen:_BuildContent()
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
	-- Title lands on the panel's own header label (§7.4: FredokaOne 34 white
	-- on the red bar).
	self._panel._title.Text = TextConfig.Resolve(data.titleKey or data.title)
	self._body.Text = TextConfig.Resolve(data.bodyKey or data.body)

	-- Confirm = green (HUD confirm colour, doc §3.3); Danger flips it to the
	-- arcade red. Danger also wants a red header — which the §7.4 header bar
	-- already is (#EB2D1E for every kind), so no header work is needed.
	self._confirmButton:SetContent({ textKey = data.confirmKey or (isInfo and "modal.ok" or "modal.confirm") })
	self._confirmButton.Props.variant = data.kind == "Danger" and "Red" or "Green"
	self._confirmButton:ApplyTheme(self:GetTheme())
	self._cancelButton.Root.Visible = not isInfo
	if not isInfo then
		self._cancelButton:SetContent({ textKey = data.cancelKey or "modal.cancel" })
	end
end

return ModalScreen
