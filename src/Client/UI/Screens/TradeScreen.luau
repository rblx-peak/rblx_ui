--!strict
-- TRADE screen — the dual-confirm trade window, Pottery Clash arcade family.
-- Two mirrored panels (YOU / THEM) flank a centre column:
--
--   * each panel = a 4×3 item slot grid, a currency offer row (icon + amount,
--     with a −/+ stepper on your side only) and a READY state light;
--   * the centre = the trade status, the swap mark, the flashing "OFFER
--     CHANGED" warning, then READY (green, toggles) and CONFIRM TRADE (gold).
--
-- The safety rule the whole screen exists to express: ANY change to either
-- offer resets BOTH ready states and flashes the warning line in Arcade.Orange.
-- CONFIRM TRADE is dimmed — never removed — until both sides are ready, and a
-- tap on it while dimmed still plays full press juice, then answers with a
-- toast (doc §11.1/§11.2).
--
-- Show(data) = { you = {items, currency, ready}, them = {name, items, currency,
-- ready} }, where an item is {name, icon} and `icon` is an IconArchive name.
-- With no data the demo offer below renders, and the partner acknowledges your
-- READY after a beat so the confirm path is walkable with no backend.

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)

type Item = { name: string, icon: string }
type Side = { name: string?, items: { Item }, currency: number, ready: boolean }

local TradeScreen = setmetatable({}, { __index = UIScreenBase })
TradeScreen.__index = TradeScreen

-- Fixed px at the 1650×1020 baseline. Card 1300×740 → content 1272×652.
local CARD = Vector2.new(1300, 740)
local PANEL_W = 470
local PANEL_H = 652
local CENTRE_X = 486
local CENTRE_W = 300
local THEM_X = 802
local PAD = 14
local INNER_W = PANEL_W - PAD * 2
local HEADER_H = 44
local GRID_COLS = 4
local GRID_ROWS = 3
local SLOT = 103
local SLOT_GAP = 10
local GRID_Y = 78
local CURRENCY_Y = 444
local STEPPER_W = 48
local STEP = 50
local LAMP_STRIP_Y = 582
local LAMP_STRIP_H = 56

-- Dashed "+ ADD" outline for your own empty slots (drawn: the arcade has no
-- dashed stroke, and an empty slot on YOUR side is an invitation, not a hole).
local DASH_LEN = 10
local DASH_GAP = 7
local DASH_THICK = 2

local WHITE = Color3.new(1, 1, 1)

local DEMO_YOU: Side = {
	items = {
		{ name = "EMBER VASE", icon = "crystal" },
		{ name = "KILN KEY", icon = "key" },
		{ name = "GLAZE FLASK", icon = "potion" },
		{ name = "OXIDE SHARD", icon = "gem" },
		{ name = "CLAY COMPASS", icon = "compass" },
	},
	currency = 450,
	ready = false,
}

local DEMO_THEM: Side = {
	name = "KILNKING",
	items = {
		{ name = "BISQUE BLADE", icon = "sword" },
		{ name = "STONEWARE SHIELD", icon = "shield" },
		{ name = "LUCKY CLOVER", icon = "luck" },
		{ name = "FIRING SCROLL", icon = "quest" },
	},
	currency = 1200,
	ready = false,
}

-- Items pulled OUT of your offer land here and can be put back — the grid stays
-- reversible instead of degrading with every click.
local DEMO_POOL: { Item } = {
	{ name = "SPARE HANDLE", icon = "hammer" },
	{ name = "TRAVEL MUG", icon = "chest" },
}

local DEMO_BALANCE = 2500

local function dashedOutline(parent: Instance, widthPx: number, heightPx: number, color: Color3)
	local pitch = DASH_LEN + DASH_GAP
	local function edge(horizontal: boolean, atStart: boolean)
		local span = if horizontal then widthPx else heightPx
		local count = math.max(1, math.floor(span / pitch))
		local inset = (span - (count * pitch - DASH_GAP)) / 2
		for i = 0, count - 1 do
			local dash = UIStyler.Frame("Dash")
			dash.BackgroundColor3 = color
			dash.BackgroundTransparency = 0.35
			if horizontal then
				dash.Size = UDim2.fromOffset(DASH_LEN, DASH_THICK)
				dash.Position = UDim2.fromOffset(inset + i * pitch, if atStart then 0 else heightPx - DASH_THICK)
			else
				dash.Size = UDim2.fromOffset(DASH_THICK, DASH_LEN)
				dash.Position = UDim2.fromOffset(if atStart then 0 else widthPx - DASH_THICK, inset + i * pitch)
			end
			dash.Parent = parent
		end
	end
	edge(true, true)
	edge(true, false)
	edge(false, true)
	edge(false, false)
end

function TradeScreen.new()
	local self = UIScreenBase.new("TradeScreen", 9)
	-- Cloned, not referenced: the offer lists are mutated as items move between
	-- the grid and the backpack, and the demo tables must stay pristine.
	self._you = { items = table.clone(DEMO_YOU.items), currency = DEMO_YOU.currency, ready = false }
	self._them = {
		name = DEMO_THEM.name,
		items = table.clone(DEMO_THEM.items),
		currency = DEMO_THEM.currency,
		ready = false,
	}
	self._pool = table.clone(DEMO_POOL)
	self._balance = DEMO_BALANCE
	self._sent = false
	-- Bumped by every offer change so a pending partner acknowledgement (and
	-- any other delayed work) is cancelled instead of landing on stale state.
	self._epoch = 0
	self._refs = {} :: { [string]: any }
	self._buttons = {} :: { any }
	return setmetatable(self, TradeScreen)
end

function TradeScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

-- ---- panels ------------------------------------------------------------

function TradeScreen:_BuildPanel(parent: Instance, sideKey: string, x: number): any
	local theme = self:GetTheme()
	local mine = sideKey == "you"

	local panel = UIStyler.Frame("Panel_" .. sideKey)
	panel.BackgroundColor3 = theme.Arcade.NearBlack2
	panel.BackgroundTransparency = 0
	panel.Position = UDim2.fromOffset(x, 0)
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	UIChrome.Stroke(theme, "Arcade").Parent = panel
	UIChrome.GlassGradient().Parent = panel
	panel.Parent = parent

	local header = UIStyler.Frame("Header")
	header.BackgroundColor3 = theme.Arcade.Panel
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	UIChrome.GlassGradient().Parent = header
	header.Parent = panel

	local title = UIChrome.Text("Title", 24, if mine then theme.Arcade.Green else theme.Arcade.IceBlue)
	title.Text = if mine then "YOU" else "THEM"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Position = UDim2.fromOffset(PAD, 0)
	title.Size = UDim2.new(1, -PAD * 2, 1, 0)
	title.Parent = header

	local offering = UIChrome.Text("Offering", 17, theme.Arcade.Gold)
	offering.Text = "OFFERING"
	offering.TextXAlignment = Enum.TextXAlignment.Left
	offering.Position = UDim2.fromOffset(PAD, HEADER_H + 8)
	offering.Size = UDim2.fromOffset(PANEL_W - PAD * 2, 22)
	offering.Parent = panel

	local grid = UIStyler.Frame("Grid")
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(PAD, GRID_Y)
	grid.Size = UDim2.fromOffset(
		GRID_COLS * SLOT + (GRID_COLS - 1) * SLOT_GAP,
		GRID_ROWS * SLOT + (GRID_ROWS - 1) * SLOT_GAP
	)
	grid.Parent = panel

	-- Currency offer row: the caption, then the amount box with the boxless
	-- Cash icon leading the number in Cash green (doc §3.3 currency colour).
	local caption = UIChrome.Text("CashCaption", 17, theme.Arcade.Gold)
	caption.Text = "CASH OFFER"
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Position = UDim2.fromOffset(PAD, CURRENCY_Y - 26)
	caption.Size = UDim2.fromOffset(PANEL_W - PAD * 2, 22)
	caption.Parent = panel

	local amountBox = UIStyler.Frame("AmountBox")
	amountBox.BackgroundColor3 = theme.Arcade.Panel
	-- Your row is [−][amount][+] across the panel's inner width; theirs is the
	-- amount alone, spanning the same span so the two panels stay mirrored.
	amountBox.Position = UDim2.fromOffset(if mine then PAD + STEPPER_W + 8 else PAD, CURRENCY_Y)
	amountBox.Size = UDim2.fromOffset(if mine then INNER_W - (STEPPER_W + 8) * 2 else INNER_W, 52)
	UIChrome.Stroke(theme, "Arcade").Parent = amountBox
	UIChrome.GlassGradient().Parent = amountBox
	amountBox.Parent = panel

	local cashIcon = IconArchive.Image(amountBox, "cash", 34)
	cashIcon.AnchorPoint = Vector2.new(0, 0.5)
	cashIcon.Position = UDim2.new(0, 10, 0.5, 0)

	local amount = UIChrome.Text("Amount", 28, UIChrome.CurrencyColor(theme, "Cash"))
	amount.TextXAlignment = Enum.TextXAlignment.Left
	amount.Position = UDim2.fromOffset(54, 0)
	amount.Size = UDim2.new(1, -64, 1, 0)
	amount.Parent = amountBox

	if mine then
		local minusId = IconArchive.Id("minus")
		local minus = UIButtonComponent.new()
		minus:Create(panel, {
			text = if minusId then nil else "-",
			iconId = minusId,
			variant = "Grey",
			size = UDim2.fromOffset(STEPPER_W, 52),
			position = UDim2.fromOffset(PAD, CURRENCY_Y),
			onClick = function()
				self:_StepCurrency(-STEP)
			end,
		})
		table.insert(self._buttons, minus)

		local plusId = IconArchive.Id("plus")
		local plus = UIButtonComponent.new()
		plus:Create(panel, {
			text = if plusId then nil else "+",
			iconId = plusId,
			variant = "Green",
			size = UDim2.fromOffset(STEPPER_W, 52),
			position = UDim2.fromOffset(PAD + INNER_W - STEPPER_W, CURRENCY_Y),
			onClick = function()
				self:_StepCurrency(STEP)
			end,
		})
		table.insert(self._buttons, plus)
	end

	local summary = UIChrome.Text("Summary", 18, theme.Arcade.IceBlue)
	summary.TextXAlignment = Enum.TextXAlignment.Left
	summary.Position = UDim2.fromOffset(PAD, CURRENCY_Y + 70)
	summary.Size = UDim2.fromOffset(PANEL_W - PAD * 2, 24)
	summary.Parent = panel

	-- The READY state light: a lamp pip that goes Cash green when this side has
	-- locked its offer in, grey while it hasn't.
	local strip = UIStyler.Frame("ReadyStrip")
	strip.BackgroundColor3 = theme.Arcade.NearBlack
	strip.Position = UDim2.fromOffset(PAD, LAMP_STRIP_Y)
	strip.Size = UDim2.fromOffset(PANEL_W - PAD * 2, LAMP_STRIP_H)
	UIChrome.Stroke(theme, "Arcade").Parent = strip
	UIChrome.GlassGradient().Parent = strip
	strip.Parent = panel

	local lamp = UIStyler.Frame("Lamp")
	lamp.BackgroundColor3 = theme.Arcade.GreyOwned
	lamp.AnchorPoint = Vector2.new(0, 0.5)
	lamp.Position = UDim2.new(0, 16, 0.5, 0)
	lamp.Size = UDim2.fromOffset(24, 24)
	UIChrome.Corner("Arcade", "Pill").Parent = lamp
	UIChrome.Stroke(theme, "Arcade").Parent = lamp
	lamp.Parent = strip

	local lampLabel = UIChrome.Text("LampLabel", 20, theme.Arcade.GreyOwned)
	lampLabel.TextXAlignment = Enum.TextXAlignment.Left
	lampLabel.Position = UDim2.fromOffset(52, 0)
	lampLabel.Size = UDim2.new(1, -62, 1, 0)
	lampLabel.Parent = strip

	return {
		panel = panel,
		title = title,
		grid = grid,
		amount = amount,
		summary = summary,
		lamp = lamp,
		lampLabel = lampLabel,
	}
end

-- One 103×103 item slot. Filled slots on YOUR side pull the item back out of
-- the offer; empty slots on your side push the next spare item in. Their side
-- is read-only and answers a tap by naming the item.
function TradeScreen:_BuildSlot(sideKey: string, index: number, item: Item?)
	local theme = self:GetTheme()
	local mine = sideKey == "you"
	local refs = self._refs[sideKey]
	local col = (index - 1) % GRID_COLS
	local row = (index - 1) // GRID_COLS

	local slot = UIStyler.Frame("Slot" .. index)
	slot.BackgroundColor3 = theme.Arcade.NearBlack
	slot.BackgroundTransparency = if item then 0 else 0.5
	slot.Position = UDim2.fromOffset(col * (SLOT + SLOT_GAP), row * (SLOT + SLOT_GAP))
	slot.Size = UDim2.fromOffset(SLOT, SLOT)
	slot.Parent = refs.grid

	if item then
		UIChrome.Stroke(theme, "Arcade").Parent = slot
		UIChrome.GlassGradient().Parent = slot

		local art = IconArchive.Image(slot, item.icon, 54)
		art.AnchorPoint = Vector2.new(0.5, 0)
		art.Position = UDim2.new(0.5, 0, 0, 10)

		local name = UIChrome.Text("Name", 13, WHITE)
		name.Text = item.name
		name.RichText = false
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextWrapped = true
		name.AnchorPoint = Vector2.new(0.5, 1)
		name.Position = UDim2.new(0.5, 0, 1, -6)
		name.Size = UDim2.fromOffset(SLOT - 10, 30)
		name.Parent = slot
	elseif mine then
		dashedOutline(slot, SLOT, SLOT, theme.Arcade.Gold)
		local plus = UIChrome.Text("Add", 30, theme.Arcade.Gold)
		plus.Text = "+"
		plus.Size = UDim2.fromScale(1, 1)
		plus.Parent = slot
	end

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.Parent = slot
	hit.Activated:Connect(function()
		if not mine then
			if item then
				self:_Toast(item.name .. " • OFFERED BY " .. self:_ThemName(), "Info")
			end
			return
		end
		if item then
			self:_RemoveItem(index)
		else
			self:_AddItem()
		end
	end)
	UIChrome.Animate(theme, hit, slot)
end

function TradeScreen:_ThemName(): string
	return string.upper(self._them.name or "TRADER")
end

-- ---- offer mutation ----------------------------------------------------

-- The rule the screen exists for: any change to either offer drops BOTH ready
-- states and flashes the warning line (doc §11.1 — the UI always answers).
function TradeScreen:_ChangeOffer()
	self._epoch += 1
	self._sent = false
	self._you.ready = false
	self._them.ready = false
	local warning = self._refs.warning
	if warning then
		warning.Visible = true
		UIChrome.Pulse(self:GetTheme(), warning)
	end
	self:_Repaint()
end

function TradeScreen:_RemoveItem(index: number)
	local item = self._you.items[index]
	if not item then
		return
	end
	table.remove(self._you.items, index)
	table.insert(self._pool, 1, item)
	self:_ChangeOffer()
end

function TradeScreen:_AddItem()
	if #self._pool == 0 then
		self:_Toast("NOTHING LEFT IN YOUR BACKPACK TO OFFER", "Error")
		return
	end
	if #self._you.items >= GRID_COLS * GRID_ROWS then
		self:_Toast("OFFER IS FULL (12 ITEMS)", "Error")
		return
	end
	table.insert(self._you.items, table.remove(self._pool, 1) :: Item)
	self:_ChangeOffer()
end

function TradeScreen:_StepCurrency(delta: number)
	local target = math.clamp(self._you.currency + delta, 0, self._balance)
	if target == self._you.currency then
		self:_Toast(
			if delta > 0 then "THAT'S ALL THE CASH YOU HAVE" else "NOTHING LEFT TO TAKE BACK",
			"Error"
		)
		return
	end
	self._you.currency = target
	self:_ChangeOffer()
end

function TradeScreen:_ToggleReady()
	if self._sent then
		self:_Toast("TRADE ALREADY SENT — WAITING ON THE SERVER", "Info")
		return
	end
	self._you.ready = not self._you.ready
	self:_Repaint()
	if self._you.ready then
		self:_SchedulePartnerAck()
	end
end

-- With no backend driving Update(), the partner mirrors your READY after a beat
-- so the confirm path is actually walkable. Cancelled by any offer change (the
-- epoch guard) and by the screen closing.
function TradeScreen:_SchedulePartnerAck()
	local epoch = self._epoch
	task.delay(1.2, function()
		if self._epoch ~= epoch or not self._built or not self._you.ready or self._them.ready then
			return
		end
		self._them.ready = true
		self:_Repaint()
		self:_Toast(self:_ThemName() .. " IS READY", "Success")
	end)
end

function TradeScreen:_Confirm()
	if not (self._you.ready and self._them.ready) then
		self:_Toast("BOTH SIDES MUST BE READY BEFORE CONFIRMING", "Error")
		return
	end
	if self._sent then
		self:_Toast("TRADE ALREADY SENT — WAITING ON THE SERVER", "Info")
		return
	end
	self._sent = true
	self:_Repaint()
	self:_Toast("TRADE SENT FOR SERVER VALIDATION", "Success")
end

-- ---- paint -------------------------------------------------------------

function TradeScreen:_RenderGrid(sideKey: string)
	local refs = self._refs[sideKey]
	for _, child in refs.grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local side: Side = if sideKey == "you" then self._you else self._them
	for index = 1, GRID_COLS * GRID_ROWS do
		self:_BuildSlot(sideKey, index, side.items[index])
	end
end

function TradeScreen:_Repaint()
	local theme = self:GetTheme()
	local refs = self._refs

	refs.them.title.Text = "THEM • " .. self:_ThemName()

	for _, sideKey in { "you", "them" } do
		local side: Side = if sideKey == "you" then self._you else self._them
		local sideRefs = refs[sideKey]
		self:_RenderGrid(sideKey)
		sideRefs.amount.Text = string.format("%d", math.floor(side.currency))
		sideRefs.summary.Text = string.format("%d ITEMS • %d CASH", #side.items, math.floor(side.currency))
		local lit = side.ready
		sideRefs.lamp.BackgroundColor3 = if lit then theme.Arcade.Green else theme.Arcade.GreyOwned
		sideRefs.lampLabel.TextColor3 = if lit then theme.Arcade.Green else theme.Arcade.GreyOwned
		sideRefs.lampLabel.Text = if lit then "READY" else "NOT READY"
	end

	local both = self._you.ready and self._them.ready
	if self._sent then
		refs.status.Text = "TRADE SENT — SERVER VALIDATING"
		refs.status.TextColor3 = theme.Arcade.Green
	elseif both then
		refs.status.Text = "BOTH READY — CONFIRM TO TRADE"
		refs.status.TextColor3 = theme.Arcade.Gold
	elseif self._you.ready then
		refs.status.Text = "WAITING FOR " .. self:_ThemName()
		refs.status.TextColor3 = theme.Arcade.IceBlue
	else
		refs.status.Text = "REVIEW BOTH OFFERS"
		refs.status.TextColor3 = theme.Arcade.Gold
	end

	self._readyButton:SetContent({
		text = if self._you.ready then "CANCEL READY" else "READY",
		variant = if self._you.ready then "Grey" else "Green",
	})
	-- Dimmed in place until both sides are ready: still fully tappable, and the
	-- tap answers with the reason (doc §11.1/§11.2).
	self._confirmButton:SetContent({ text = "CONFIRM TRADE", variant = "Gold", dimmed = not both })
end

function TradeScreen:_BuildContent()
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = self:_R("TRADE"),
		sizePx = CARD,
		onClose = function()
			self.ScreenController:HideScreen("trade")
		end,
	})
	self._modal = modal
	local content = modal.content

	self._refs.you = self:_BuildPanel(content, "you", 0)
	self._refs.them = self:_BuildPanel(content, "them", THEM_X)

	local centre = UIStyler.Frame("Centre")
	centre.BackgroundTransparency = 1
	centre.Position = UDim2.fromOffset(CENTRE_X, 0)
	centre.Size = UDim2.fromOffset(CENTRE_W, PANEL_H)
	centre.Parent = content

	local status = UIChrome.Text("Status", 24, theme.Arcade.Gold)
	status.TextWrapped = true
	status.Size = UDim2.new(1, 0, 0, 70)
	status.Parent = centre
	self._refs.status = status

	local swap = IconArchive.Image(centre, "trade", 96)
	swap.AnchorPoint = Vector2.new(0.5, 0)
	swap.Position = UDim2.new(0.5, 0, 0, 84)

	-- The warning line: hidden until an offer changes, then flashed with the
	-- §5.1 pulse in the arcade orange.
	local warning = UIChrome.Text("Warning", 19, theme.Arcade.Orange)
	warning.Text = "OFFER CHANGED — REVIEW AGAIN"
	warning.TextWrapped = true
	warning.Position = UDim2.fromOffset(0, 198)
	warning.Size = UDim2.new(1, 0, 0, 56)
	warning.Visible = false
	warning.Parent = centre
	self._refs.warning = warning

	local ready = UIButtonComponent.new()
	ready:Create(centre, {
		text = "READY",
		variant = "Green",
		size = UDim2.fromOffset(280, 60),
		position = UDim2.new(0.5, 0, 0, 280),
		anchorPoint = Vector2.new(0.5, 0),
		onClick = function()
			self:_ToggleReady()
		end,
	})
	self._readyButton = ready

	local confirm = UIButtonComponent.new()
	confirm:Create(centre, {
		text = "CONFIRM TRADE",
		variant = "Gold",
		size = UDim2.fromOffset(280, 60),
		position = UDim2.new(0.5, 0, 0, 356),
		anchorPoint = Vector2.new(0.5, 0),
		onClick = function()
			self:_Confirm()
		end,
	})
	self._confirmButton = confirm

	-- The quiet body-font note (doc §2): the client window is a preview of an
	-- exchange the server owns.
	local note = UIChrome.BodyText("Note", 15, theme.Arcade.GreyOwned)
	note.Text = "The server re-checks both offers before anything moves. Nothing here is final until it says so."
	note.TextWrapped = true
	note.TextYAlignment = Enum.TextYAlignment.Bottom
	note.AnchorPoint = Vector2.new(0.5, 1)
	note.Position = UDim2.fromScale(0.5, 1)
	note.Size = UDim2.new(1, 0, 0, 90)
	note.Parent = centre

	self:_Repaint()
end

function TradeScreen:_Ingest(data: any?)
	if not data then
		return false
	end
	local changed = false
	if data.you then
		self._you = {
			items = data.you.items or self._you.items,
			currency = data.you.currency or self._you.currency,
			ready = data.you.ready == true,
		}
		changed = true
	end
	if data.them then
		self._them = {
			name = data.them.name or self._them.name,
			items = data.them.items or self._them.items,
			currency = data.them.currency or self._them.currency,
			ready = data.them.ready == true,
		}
		changed = true
	end
	if changed then
		-- Authoritative state landed: cancel any pending simulated ack.
		self._epoch += 1
	end
	return changed
end

function TradeScreen:_OnShow(data: any?)
	if self:_Ingest(data) then
		self._sent = false
		if self._refs.warning then
			self._refs.warning.Visible = false
		end
		self:_Repaint()
	end
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

-- Closing cancels the pending partner acknowledgement.
function TradeScreen:_OnHide()
	self._epoch += 1
end

function TradeScreen:Update(data: any)
	if self:_Ingest(data) and self._built then
		self:_Repaint()
	end
end

function TradeScreen:Destroy()
	self._epoch += 1
	for _, button in self._buttons do
		button:Destroy()
	end
	table.clear(self._buttons)
	if self._readyButton then
		self._readyButton:Destroy()
		self._readyButton = nil
	end
	if self._confirmButton then
		self._confirmButton:Destroy()
		self._confirmButton = nil
	end
	UIScreenBase.Destroy(self)
end

return TradeScreen
