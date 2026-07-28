--!strict
-- Mailbox — Pottery Clash arcade family (doc §7.4).
-- One modal card, two panes. Left: the message list (sender icon, subject,
-- date, gold unread dot, 📎 attachment marker) over a footer with DELETE READ
-- (danger — routed through the shared confirm modal) and MARK ALL READ.
-- Right: the reader (subject, sender line, body, and an ATTACHMENTS strip of
-- reward chips with one CLAIM button).
--
-- Ring language: the SELECTED row wears the solid gold selection ring (§4.3);
-- a message with unclaimed attachments wears a softer gold ring (same gold at
-- 0.35 transparency) so "there is loot in here" reads across the whole list
-- without impersonating the selection. CLAIM flips to grey CLAIMED in place
-- (§11.2) and keeps answering taps with a toast (§11.1). Opening a message is
-- what marks it read; DELETE READ deliberately keeps read messages that still
-- hold unclaimed rewards.

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPCelebrationKit = require(script.Parent.Parent.Framework.GPCelebrationKit)
local UITicker = require(script.Parent.Parent.Framework.UITicker)

type Attachment = { icon: string, amount: number }
type Message = {
	id: string,
	from: string,
	subject: string,
	body: string,
	date: string,
	read: boolean,
	icon: string?,
	attachments: { Attachment }?,
	claimed: boolean?,
}
type MailData = { messages: { Message } }

local CARD_W, CARD_H = 1280, 700
local CONTENT_W = CARD_W - 28
local CONTENT_H = CARD_H - 88
local LIST_W = 470
local FOOTER_H = 52
local LIST_H = CONTENT_H - FOOTER_H - 12
local ROW_H = 76
local ROW_GAP = 8
local READER_X = LIST_W + 16
local READER_W = CONTENT_W - READER_X
local CHIP_W, CHIP_H = 92, 110
local SCROLLBAR = 8

local function demoMessages(): { Message }
	return {
		{ id = "m1", from = "POTTERY CLASH TEAM", icon = "star", subject = "WELCOME TO SEASON 3", date = "14 JUL",
			read = false, claimed = false,
			attachments = { { icon = "cash", amount = 500 }, { icon = "ticket", amount = 2 } },
			body = "Kiln & Cobalt is live! The season track is stocked, the bayside stalls rotated their glazes, and the ranked ladder has been reset. Here is a little starter clay for the road." },
		{ id = "m2", from = "KILN WARDENS", icon = "fire", subject = "REPUTATION REWARD", date = "13 JUL",
			read = true, claimed = false,
			attachments = { { icon = "crate", amount = 1 } },
			body = "Your standing with the Wardens has reached FRIENDLY. The watch commander left a crate with your name scratched into the lid. Do not ask what is in it. Open it and find out." },
		{ id = "m3", from = "GALLERY CURATOR", icon = "trophy", subject = "YOUR POT PLACED 2ND!", date = "12 JUL",
			read = false, claimed = false,
			attachments = { { icon = "cash", amount = 1200 } },
			body = "Your tall-neck amphora took second place in this week's gallery vote — a whisker behind KILNKING's double-handled monster. Prize money enclosed. The judges want to see more cobalt from you." },
		{ id = "m4", from = "TRADE DESK", icon = "trade", subject = "TRADE COMPLETED", date = "10 JUL",
			read = true,
			body = "Your trade with CLAYCRUSHER has settled: one speckled glaze recipe out, one bag of ridge slip in. Both parties confirmed. Receipts are kept for thirty days." },
		{ id = "m5", from = "SYSTEM", icon = "settings", subject = "MAINTENANCE NOTES", date = "9 JUL",
			read = false,
			body = "Scheduled kiln maintenance completed. Firing times are back to normal and the waystone network is fully lit. Thanks for your patience while the sparks flew." },
		{ id = "m6", from = "BRENDA", icon = "heart", subject = "ABOUT THAT BOWL...", date = "6 JUL",
			read = true,
			body = "You KNOW the one. The commission board says it is still pending and the soup is getting cold. No pressure. Some pressure. — B" },
	}
end

local function comma(n: number): string
	local formatted = tostring(math.floor(n))
	while true do
		local replaced
		formatted, replaced = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return formatted
end

local function hasUnclaimed(message: Message): boolean
	local attachments = message.attachments
	return attachments ~= nil and #attachments > 0 and message.claimed ~= true
end

local MailboxScreen = setmetatable({}, { __index = UIScreenBase })
MailboxScreen.__index = MailboxScreen

function MailboxScreen.new()
	local self = UIScreenBase.new("MailboxScreen", 6)
	self._data = { messages = demoMessages() } :: MailData
	self._selectedId = nil :: string?
	self._listComponents = {} :: { any }
	self._readerComponents = {} :: { any }
	return setmetatable(self, MailboxScreen)
end

function MailboxScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function MailboxScreen:_BuildContent()
	-- GP layout language: the pastel mail shelf — cream page, petal message
	-- cards, a glazed reader plate — see _BuildGPLayout at the bottom.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end

	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "MAILBOX",
		sizePx = Vector2.new(CARD_W, CARD_H),
		onClose = function()
			self.ScreenController:HideScreen("mailbox")
		end,
	})
	self._modal = modal
	local content = modal.content

	-- Left: message list.
	local list = Instance.new("ScrollingFrame")
	list.Name = "MessageList"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.fromOffset(LIST_W, LIST_H)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = SCROLLBAR
	list.ScrollBarImageColor3 = theme.Arcade.Gold
	list.Parent = content
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, ROW_GAP),
	}).Parent = list
	self._list = list

	-- Footer actions under the list.
	local footer = UIStyler.Frame("Footer")
	footer.BackgroundTransparency = 1
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 0, 1, 0)
	footer.Size = UDim2.fromOffset(LIST_W, FOOTER_H)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = footer
	footer.Parent = content

	self._deleteButton = UIButtonComponent.new()
	self._deleteButton:Create(footer, {
		text = "DELETE READ",
		variant = "Red",
		size = UDim2.fromOffset(220, 48),
		layoutOrder = 1,
		onClick = function()
			self:_DeleteRead()
		end,
	})
	self._markAllButton = UIButtonComponent.new()
	self._markAllButton:Create(footer, {
		text = "MARK ALL READ",
		variant = "Blue",
		size = UDim2.fromOffset(230, 48),
		layoutOrder = 2,
		onClick = function()
			self:_MarkAllRead()
		end,
	})

	-- Right: reader pane.
	local reader = UIChrome.Panel(theme, "Arcade", "Reader")
	reader.Position = UDim2.fromOffset(READER_X, 0)
	reader.Size = UDim2.fromOffset(READER_W, CONTENT_H)
	reader.Parent = content
	self._reader = reader

	local subject = UIChrome.Text("Subject", 26, theme.Colors.TextPrimary)
	subject.TextXAlignment = Enum.TextXAlignment.Left
	subject.Position = UDim2.fromOffset(24, 16)
	subject.Size = UDim2.new(1, -48, 0, 32)
	subject.RichText = false
	subject.TextTruncate = Enum.TextTruncate.AtEnd
	subject.Parent = reader
	self._subjectLabel = subject

	local fromLine = UIChrome.BodyText("FromLine", 15, theme.Arcade.IceBlue)
	fromLine.TextXAlignment = Enum.TextXAlignment.Left
	fromLine.Position = UDim2.fromOffset(24, 54)
	fromLine.Size = UDim2.new(1, -48, 0, 20)
	fromLine.Parent = reader
	self._fromLabel = fromLine

	local rule = UIStyler.Frame("Rule")
	rule.BackgroundColor3 = theme.Arcade.RulerTick
	rule.BackgroundTransparency = 0.65
	rule.Position = UDim2.fromOffset(24, 84)
	rule.Size = UDim2.new(1, -48, 0, 2)
	rule.Parent = reader

	local bodyScroll = Instance.new("ScrollingFrame")
	bodyScroll.Name = "Body"
	bodyScroll.BackgroundTransparency = 1
	bodyScroll.BorderSizePixel = 0
	bodyScroll.Position = UDim2.fromOffset(24, 98)
	bodyScroll.Size = UDim2.new(1, -48, 0, 296)
	bodyScroll.CanvasSize = UDim2.new()
	bodyScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	bodyScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	bodyScroll.ScrollBarThickness = SCROLLBAR
	bodyScroll.ScrollBarImageColor3 = theme.Arcade.Gold
	bodyScroll.Parent = reader

	local body = UIChrome.BodyText("BodyText", 17, theme.Colors.TextPrimary)
	body.Size = UDim2.new(1, -SCROLLBAR - 4, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.RichText = false
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.LineHeight = 1.3
	body.Parent = bodyScroll
	self._bodyLabel = body

	local attachCaption = UIChrome.Text("AttachCaption", 18, theme.Arcade.Gold)
	attachCaption.Text = "ATTACHMENTS"
	attachCaption.TextXAlignment = Enum.TextXAlignment.Left
	attachCaption.Position = UDim2.fromOffset(24, 410)
	attachCaption.Size = UDim2.new(1, -48, 0, 24)
	attachCaption.Parent = reader
	self._attachCaption = attachCaption

	local strip = UIStyler.Frame("Attachments")
	strip.BackgroundTransparency = 1
	strip.Position = UDim2.fromOffset(24, 440)
	strip.Size = UDim2.new(1, -48, 0, CHIP_H)
	strip.Parent = reader
	self._attachStrip = strip

	local chips = UIStyler.Frame("Chips")
	chips.BackgroundTransparency = 1
	chips.Size = UDim2.new(1, -180, 1, 0)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12),
	}).Parent = chips
	chips.Parent = strip
	self._chipRow = chips

	self:_RenderList()
	self:_RenderReader()
end

function MailboxScreen:_Messages(): { Message }
	return (self._data :: MailData).messages
end

function MailboxScreen:_Selected(): Message?
	for _, message in self:_Messages() do
		if message.id == self._selectedId then
			return message
		end
	end
	return nil
end

function MailboxScreen:_RenderList()
	-- GP repaints the pastel list in its own copy and its own silhouettes —
	-- see _GPRenderList.
	if self:LayoutKit() == "GP" then
		self:_GPRenderList()
		return
	end
	local theme = self:GetTheme()
	for _, component in self._listComponents do
		component:Destroy()
	end
	table.clear(self._listComponents)
	for _, child in self._list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local messages = self:_Messages()
	if #messages == 0 then
		local empty = UIChrome.Text("Empty", 22, theme.Arcade.GreyOwned)
		empty.Text = "NO MAIL"
		empty.Size = UDim2.new(1, -SCROLLBAR, 0, 80)
		empty.Parent = self._list
		self._selectedId = nil
		return
	end

	if not self:_Selected() then
		self._selectedId = messages[1].id
	end
	for index, message in messages do
		self:_BuildRow(message, index)
	end
end

function MailboxScreen:_BuildRow(message: Message, index: number)
	local theme = self:GetTheme()

	local root = UIStyler.Frame("Row_" .. message.id)
	root.BackgroundTransparency = 1
	root.Size = UDim2.new(1, -SCROLLBAR, 0, ROW_H)
	root.LayoutOrder = index
	root.Parent = self._list

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 1
	hit.Parent = root

	local surface = UIStyler.Frame("Surface")
	surface.BackgroundColor3 = theme.Arcade.Row
	surface.BackgroundTransparency = theme.Arcade.RowTransparency
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 2
	-- Selection = solid gold ring; unclaimed loot = the same gold softened to
	-- 0.35 so it beckons without impersonating the selection (§4.3).
	if message.id == self._selectedId then
		UIChrome.Stroke(theme, "Arcade", "Selection").Parent = surface
	elseif hasUnclaimed(message) then
		UIStyler.Stroke(theme.Semantic.Selection, 3, 0.35).Parent = surface
	else
		UIChrome.Stroke(theme, "Arcade").Parent = surface
	end
	UIChrome.GlassGradient().Parent = surface
	surface.Parent = root

	if not message.read then
		local dot = UIStyler.Frame("UnreadDot")
		dot.BackgroundColor3 = theme.Arcade.Gold
		dot.BackgroundTransparency = 0
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.Position = UDim2.new(0, 10, 0.5, 0)
		dot.Size = UDim2.fromOffset(12, 12)
		UIChrome.Corner("Arcade", "Pill").Parent = dot
		-- Micro chrome rim: Classic keeps the bespoke 2px small-solid weight;
		-- a styled chrome (theme.Chrome) frames the dot through the UIChrome
		-- policy instead (same gate as UIBadgeComponent's chip border).
		if theme.Chrome ~= nil then
			UIChrome.Stroke(theme, "Arcade", "Button").Parent = dot
		else
			UIStyler.Stroke(Color3.new(0, 0, 0), 2, 0).Parent = dot -- micro chrome: the 2px small-solid weight
		end
		dot.Parent = surface
	end

	local icon = IconArchive.Image(surface, message.icon or "player", 40)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 30, 0.5, 0)

	local subject = UIChrome.Text("Subject", 19, message.read and theme.Colors.TextPrimary or theme.Arcade.Gold)
	subject.Text = message.subject
	subject.TextXAlignment = Enum.TextXAlignment.Left
	subject.Position = UDim2.fromOffset(82, 12)
	subject.Size = UDim2.new(1, -200, 0, 24)
	subject.RichText = false
	subject.TextTruncate = Enum.TextTruncate.AtEnd
	subject.Parent = surface

	local from = UIChrome.BodyText("From", 14, theme.Colors.TextSecondary)
	from.Text = message.from
	from.TextXAlignment = Enum.TextXAlignment.Left
	from.Position = UDim2.fromOffset(82, 42)
	from.Size = UDim2.new(1, -240, 0, 18)
	from.RichText = false
	from.TextTruncate = Enum.TextTruncate.AtEnd
	from.Parent = surface

	local date = UIChrome.BodyText("Date", 13, theme.Colors.TextSecondary)
	date.Text = message.date
	date.TextXAlignment = Enum.TextXAlignment.Right
	date.AnchorPoint = Vector2.new(1, 0)
	date.Position = UDim2.new(1, -14, 0, 12)
	date.Size = UDim2.fromOffset(90, 16)
	date.Parent = surface

	local attachments = message.attachments
	if attachments and #attachments > 0 then
		-- 📎 is a symbol glyph: FontFace must be assigned explicitly or the
		-- engine-default font renders nothing.
		local clip = UIStyler.TextLabel("Clip")
		clip.Text = "📎"
		clip.FontFace = theme.Fonts.Title
		clip.TextSize = 16
		clip.TextColor3 = if hasUnclaimed(message) then theme.Arcade.Gold else theme.Arcade.GreyOwned
		clip.RichText = false
		clip.AnchorPoint = Vector2.new(1, 1)
		clip.Position = UDim2.new(1, -14, 1, -8)
		clip.Size = UDim2.fromOffset(22, 22)
		clip.Parent = surface
	end

	hit.Activated:Connect(function()
		self:_SelectMessage(message)
	end)
	-- Animate LAST, after the final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, hit, surface)
end

function MailboxScreen:_SelectMessage(message: Message)
	self._selectedId = message.id
	-- Opening a message is what marks it read (clears the gold dot in place).
	message.read = true
	self:_RenderList()
	self:_RenderReader()
end

function MailboxScreen:_RenderReader()
	-- GP repaints the glazed reader plate in its own copy — see _GPRenderReader.
	if self:LayoutKit() == "GP" then
		self:_GPRenderReader()
		return
	end
	local theme = self:GetTheme()
	for _, component in self._readerComponents do
		component:Destroy()
	end
	table.clear(self._readerComponents)
	for _, child in self._chipRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local message = self:_Selected()
	if not message then
		self._subjectLabel.Text = "NO MAIL"
		self._fromLabel.Text = ""
		self._bodyLabel.Text = "Your mailbox is empty. Rewards, receipts and faction news land here."
		self._attachCaption.Visible = false
		self._attachStrip.Visible = false
		return
	end

	self._subjectLabel.Text = message.subject
	self._fromLabel.Text = string.format("FROM %s   ·   %s", message.from, message.date)
	self._bodyLabel.Text = message.body

	local attachments = message.attachments
	local hasAny = attachments ~= nil and #attachments > 0
	self._attachCaption.Visible = hasAny
	self._attachStrip.Visible = hasAny
	if not hasAny or not attachments then
		return
	end

	for order, attachment in attachments do
		local chip = UIStyler.Frame("Chip" .. order)
		chip.BackgroundColor3 = theme.Arcade.NearBlack
		chip.BackgroundTransparency = 0
		chip.Size = UDim2.fromOffset(CHIP_W, CHIP_H)
		chip.LayoutOrder = order
		UIChrome.Stroke(theme, "Arcade").Parent = chip
		UIChrome.GlassGradient().Parent = chip
		chip.Parent = self._chipRow

		local icon = IconArchive.Image(chip, attachment.icon, 44)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 12)
		if message.claimed then
			-- CLAIMED recolours grey in place (doc §11.2).
			if icon:IsA("ImageLabel") then
				icon.ImageColor3 = theme.Arcade.GreyOwned
			end
		end

		-- Currency amounts keep their currency colour (doc §3.3); other
		-- rewards read as gold/valuable.
		local currencyId = if attachment.icon == "cash" then "Cash"
			elseif attachment.icon == "bux" then "Bux"
			elseif attachment.icon == "robux" then "Robux"
			else nil
		local amount = UIChrome.Text("Amount", 16, if message.claimed then theme.Arcade.GreyOwned
			elseif currencyId then UIChrome.CurrencyColor(theme, currencyId)
			else theme.Arcade.SunburstGold)
		amount.Text = comma(attachment.amount)
		amount.Position = UDim2.fromOffset(0, 64)
		amount.Size = UDim2.new(1, 0, 0, 22)
		amount.Parent = chip

		local state = UIChrome.Text("State", 12, message.claimed and theme.Arcade.GreyOwned or theme.Arcade.Green)
		state.Text = message.claimed and "CLAIMED" or "READY"
		state.Position = UDim2.fromOffset(0, 88)
		state.Size = UDim2.new(1, 0, 0, 16)
		state.Parent = chip
	end

	local claim = UIButtonComponent.new()
	claim:Create(self._attachStrip, {
		text = message.claimed and "CLAIMED" or "CLAIM",
		variant = message.claimed and "Grey" or "Green",
		size = UDim2.fromOffset(150, 48),
		anchorPoint = Vector2.new(1, 0.5),
		position = UDim2.new(1, 0, 0.5, 0),
		onClick = function()
			self:_Claim(message)
		end,
	})
	table.insert(self._readerComponents, claim)
end

function MailboxScreen:_Claim(message: Message)
	if message.claimed then
		self:_Toast("Already claimed.", "Info")
		return
	end
	message.claimed = true
	local attachments = message.attachments
	local count = attachments and #attachments or 0
	self:_Toast(string.format("Claimed %d reward%s.", count, count == 1 and "" or "s"), "Success")
	self:_RenderList()
	self:_RenderReader()
end

function MailboxScreen:_DeleteRead()
	local readCount = 0
	local keptForLoot = 0
	for _, message in self:_Messages() do
		if message.read then
			if hasUnclaimed(message) then
				keptForLoot += 1
			else
				readCount += 1
			end
		end
	end
	if readCount == 0 then
		self:_Toast(keptForLoot > 0 and "Read mail still holds unclaimed rewards — claim first." or "No read mail to delete.", "Error")
		return
	end
	self.ScreenController:ShowModal({
		kind = "Danger",
		title = "DELETE READ MAIL",
		body = string.format("Delete %d read message%s? Messages with unclaimed rewards are kept.",
			readCount, readCount == 1 and "" or "s"),
		confirmKey = "DELETE",
		cancelKey = "KEEP",
		onConfirm = function()
			local kept = {}
			for _, message in self:_Messages() do
				if not message.read or hasUnclaimed(message) then
					table.insert(kept, message)
				end
			end
			self._data = { messages = kept }
			self._selectedId = nil
			self:_Toast(string.format("Deleted %d message%s.", readCount, readCount == 1 and "" or "s"), "Success")
			self:_RenderList()
			self:_RenderReader()
		end,
	})
end

function MailboxScreen:_MarkAllRead()
	local unread = 0
	for _, message in self:_Messages() do
		if not message.read then
			unread += 1
		end
	end
	if unread == 0 then
		self:_Toast("Everything is already read.", "Info")
		return
	end
	for _, message in self:_Messages() do
		message.read = true
	end
	self:_Toast(string.format("Marked %d message%s read.", unread, unread == 1 and "" or "s"), "Success")
	self:_RenderList()
end

function MailboxScreen:_Apply(data: any)
	if data.messages then
		self._data = { messages = data.messages }
		self._selectedId = nil
	end
end

function MailboxScreen:_OnShow(data: any?)
	if data then
		self:_Apply(data)
		self:_RenderList()
		self:_RenderReader()
	end
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function MailboxScreen:Update(data: any)
	if not data then
		return
	end
	self:_Apply(data)
	if self._built then
		self:_RenderList()
		self:_RenderReader()
	end
end

function MailboxScreen:Destroy()
	-- UIScreenBase.Destroy throws the Gui away but never runs _OnTeardown (only
	-- _ResetShell does), and a destroyed UIShadow does NOT decrement the budget
	-- counter on its own. Without this, closing the mailbox for good leaves the
	-- page, the reader plate, both footer chips and every card shadow counted.
	self:_OnTeardown()
	for _, component in self._listComponents do
		component:Destroy()
	end
	table.clear(self._listComponents)
	for _, component in self._readerComponents do
		component:Destroy()
	end
	table.clear(self._readerComponents)
	if self._deleteButton then
		self._deleteButton:Destroy()
		self._deleteButton = nil
	end
	if self._markAllButton then
		self._markAllButton:Destroy()
		self._markAllButton = nil
	end
	UIScreenBase.Destroy(self)
end

-- ======================================================================
-- GP layout (theme.LayoutKit == "GP") — THE MAIL SHELF.
--
-- Same two panes, re-thrown in the pack's clay: a cream Page, petal message
-- cards whose silhouette alternates down the column, and a glazed reader plate
-- with a scalloped attachment shelf. Every surface casts a HUE-MATCHED shadow
-- of its own fill; nothing here is grey and nothing here is black.
--
-- THE RING LANGUAGE SURVIVES INTACT, because it is information:
--   selected            — the solid Semantic.Selection ring (rose), 3px, the
--                         one unambiguous "you are reading this".
--   unclaimed loot      — the SAME rose softened to 0.4, exactly the classic
--                         relationship, PLUS this pack's claimable signal: a
--                         soft butter aura and a ring of sparkles. Nothing
--                         else on the page twinkles.
--   read / claimed      — the card deepens to blush in place and its clip
--                         marker quiets. Nothing is ever removed.
-- A claimed message's attachment chips wear the sticker-stamp rosette.
--
-- PRESENTATION ONLY. The same _data.messages, the same _SelectMessage (opening
-- is still what marks a message read), the same _Claim / _DeleteRead /
-- _MarkAllRead — including DELETE READ still routing through the shared confirm
-- modal and still keeping read mail that holds unclaimed rewards.
--
-- DENSITY IS UNCHANGED: sender icon, subject, sender name, date, unread pip,
-- attachment marker, the full body, the attachments caption, EVERY chip with
-- its icon, its comma-grouped amount and its ready/claimed line, the claim
-- control, and both footer actions. Nothing was dropped for the pastel.
-- ======================================================================

local GP_PAGE = Vector2.new(1280, 744)
local GP_LIST_W = 456
local GP_FOOTER_H = 52
local GP_ROW_H = 80
local GP_ROW_GAP = 8
local GP_READER_X = GP_LIST_W + 18
local GP_CHIP_W, GP_CHIP_H = 96, 112
local GP_BODY_H = 296
local GP_GLOW_BASE = 0.44
local GP_GLOW_SWING = 0.16
local GP_GLOW_HZ = 1.5

function MailboxScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	self._gpShadows = {} :: { any }
	self._gpRowShadows = {} :: { any }
	self._gpReaderShadows = {} :: { any }
	-- Two sparkle registers, not one: the list and the reader repaint on
	-- INDEPENDENT triggers (_MarkAllRead repaints only the list), and a shared
	-- register would have the list's clear silently stop the reader twinkling.
	self._gpSparkles = {} :: { any }
	self._gpReaderSparkles = {} :: { any }
	self._gpGlows = {} :: { any }

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Mailbox",
		subtitleText = "Notes, receipts and the odd parcel.",
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("mailbox")
		end,
	})
	for _, handle in page.shadows do
		table.insert(self._gpShadows, handle)
	end
	self._modal = { card = page.panel, content = page.panel }

	local content = page.content
	local listH = -(GP_FOOTER_H + 12)

	-- Left: the message shelf. MUST clip — unclipped rows spilling past the
	-- frame is a known past bug here — with padding so the clip edge never
	-- slices a card's own shadow in half.
	local list = GPCelebrationKit.Scroller(theme, content, { padPx = 6, gapPx = GP_ROW_GAP, zIndex = 3 })
	list.Size = UDim2.new(0, GP_LIST_W, 1, listH)
	self._list = list

	local footer = UIStyler.Frame("Footer")
	footer.BackgroundColor3 = theme.Colors.Background
	footer.BackgroundTransparency = 1
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 0, 1, 0)
	footer.Size = UDim2.fromOffset(GP_LIST_W, GP_FOOTER_H)
	footer.ZIndex = 4
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = footer
	footer.Parent = content

	self._deleteButton = GPCelebrationKit.Button(theme, footer, {
		text = "Delete read",
		variant = "Red",
		size = UDim2.fromOffset(212, 48),
		layoutOrder = 1,
		zIndex = 5,
		cornerIndex = 0,
		onClick = function()
			self:_DeleteRead()
		end,
	}, self._gpShadows)
	self._markAllButton = GPCelebrationKit.Button(theme, footer, {
		text = "Mark all read",
		variant = "Gold",
		size = UDim2.fromOffset(222, 48),
		layoutOrder = 2,
		zIndex = 5,
		cornerIndex = 1,
		onClick = function()
			self:_MarkAllRead()
		end,
	}, self._gpShadows)

	-- Right: the reader plate. Clipped for the same reason the page is.
	local readerFill = theme.Colors.SurfaceRaised
	local reader = UIStyler.Frame("Reader")
	reader.BackgroundColor3 = readerFill
	reader.BackgroundTransparency = 0
	reader.Position = UDim2.fromOffset(GP_READER_X, 0)
	reader.Size = UDim2.new(1, -GP_READER_X, 1, 0)
	reader.ClipsDescendants = true
	reader.ZIndex = 4
	reader.Parent = content
	GPLayoutKit.Petal(theme, reader, 0)
	GPLayoutKit.SoftStroke(theme, reader, readerFill)
	GPLayoutKit.Shadow(theme, reader, "md", self._gpShadows, readerFill)
	-- Corner first, then the sheen: the wash clones the host's UICorner, so it
	-- can never square off the petal.
	GPLayoutKit.GlazeSheen(theme, reader)
	self._reader = reader

	local subject = GPLayoutKit.Text(theme, theme.TextSizes.Title - 4, theme.Colors.TextPrimary, "Subject")
	subject.TextXAlignment = Enum.TextXAlignment.Left
	subject.Position = UDim2.fromOffset(22, 16)
	subject.Size = UDim2.new(1, -44, 0, 32)
	subject.RichText = false
	subject.TextTruncate = Enum.TextTruncate.AtEnd
	subject.ZIndex = 7
	subject.Parent = reader
	self._subjectLabel = subject

	local fromLine = GPLayoutKit.BodyText(theme, theme.TextSizes.Small + 2, theme.Colors.TextSecondary, "FromLine")
	fromLine.TextXAlignment = Enum.TextXAlignment.Left
	fromLine.Position = UDim2.fromOffset(22, 52)
	fromLine.Size = UDim2.new(1, -44, 0, 20)
	fromLine.RichText = false
	fromLine.ZIndex = 7
	fromLine.Parent = reader
	self._fromLabel = fromLine

	local rule = GPLayoutKit.Divider(theme, reader)
	rule.Position = UDim2.fromOffset(22, 80)
	rule.Size = UDim2.new(1, -44, 0, rule.Size.Y.Offset)
	rule.ZIndex = 7

	local bodyScroll = GPCelebrationKit.Scroller(theme, reader, { padPx = 2, list = false, zIndex = 6 })
	bodyScroll.Name = "Body"
	bodyScroll.Position = UDim2.fromOffset(22, 100)
	bodyScroll.Size = UDim2.new(1, -44, 0, GP_BODY_H)

	local body = GPLayoutKit.BodyText(theme, theme.TextSizes.Body + 1, theme.Colors.TextPrimary, "BodyText")
	body.Size = UDim2.new(1, -SCROLLBAR - 4, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.RichText = false
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.LineHeight = 1.3
	body.ZIndex = 7
	body.Parent = bodyScroll
	self._bodyLabel = body

	local attachCaption = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "AttachCaption")
	attachCaption.Text = "Attachments"
	attachCaption.TextXAlignment = Enum.TextXAlignment.Left
	attachCaption.Position = UDim2.fromOffset(22, 100 + GP_BODY_H + 16)
	attachCaption.Size = UDim2.new(1, -44, 0, 26)
	attachCaption.ZIndex = 7
	attachCaption.Parent = reader
	self._attachCaption = attachCaption

	local strip = UIStyler.Frame("Attachments")
	strip.BackgroundColor3 = theme.Colors.SurfaceRaised
	strip.BackgroundTransparency = 1
	strip.Position = UDim2.fromOffset(22, 100 + GP_BODY_H + 46)
	strip.Size = UDim2.new(1, -44, 0, GP_CHIP_H)
	strip.ZIndex = 7
	strip.Parent = reader
	self._attachStrip = strip

	local chips = UIStyler.Frame("Chips")
	chips.BackgroundColor3 = theme.Colors.SurfaceRaised
	chips.BackgroundTransparency = 1
	chips.Size = UDim2.new(1, -184, 1, 0)
	chips.ZIndex = 7
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12),
	}).Parent = chips
	chips.Parent = strip
	self._chipRow = chips

	-- ONE ticker handler for the whole page (never a RunService connection):
	-- the sparkle shimmer and the claimable aura's breath.
	self._gpStop = UITicker.Register(function(_dt: number, now: number)
		if not UIChrome.IsOnScreen(page.panel) then
			return
		end
		for _, sparkles in self._gpSparkles do
			sparkles.Step(now)
		end
		for _, sparkles in self._gpReaderSparkles do
			sparkles.Step(now)
		end
		local breath = GP_GLOW_BASE + GP_GLOW_SWING * (0.5 + 0.5 * math.sin(now * GP_GLOW_HZ))
		for _, glow in self._gpGlows do
			glow.Instance.Transparency = breath
		end
	end, page.panel)

	self:_GPRenderList()
	self:_GPRenderReader()
end

-- The GP answer to _RenderList (see the dispatch at the top of that function).
function MailboxScreen:_GPRenderList()
	local theme = self:GetTheme()
	for _, component in self._listComponents do
		component:Destroy()
	end
	table.clear(self._listComponents)
	table.clear(self._gpSparkles)
	table.clear(self._gpGlows)
	-- Release BEFORE the rows are destroyed: a destroyed GuiObject alone leaves
	-- the live-UIShadow budget counter high forever.
	GPLayoutKit.ReleaseShadows(self._gpRowShadows)
	for _, child in self._list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local messages = self:_Messages()
	if #messages == 0 then
		local empty = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Empty")
		empty.Text = "No mail on the shelf"
		empty.Size = UDim2.new(1, -SCROLLBAR, 0, 80)
		empty.Parent = self._list
		self._selectedId = nil
		return
	end

	if not self:_Selected() then
		self._selectedId = messages[1].id
	end
	for index, message in messages do
		self:_GPBuildMessageCard(message, index)
	end
end

-- One message, as a petal card. Same information as the arcade row, in this
-- pack's silhouette: unread pip, sender art, subject, sender, date, and the
-- attachment marker that brightens while there is loot inside.
function MailboxScreen:_GPBuildMessageCard(message: Message, index: number)
	local theme = self:GetTheme()
	local selected = message.id == self._selectedId
	local loot = hasUnclaimed(message)

	local row = GPCelebrationKit.Row(theme, self._list, index, self._gpRowShadows, {
		widthPx = GP_LIST_W - SCROLLBAR - 8,
		heightPx = GP_ROW_H,
		zIndex = 4,
	})
	row.root.Name = "Row_" .. message.id
	local body = row.body
	-- A read card DEEPENS to blush in place; unread keeps the alternating
	-- lighter fill so the column reads at a glance without a grey-out.
	if message.read then
		row.SetTone(theme.Colors.Surface)
	end

	-- The ring language, unchanged in meaning (see the section header): a solid
	-- rose ring is selection, the same rose at 0.4 is "there is loot in here",
	-- and everything else keeps the soft hue-matched hairline Row already gave
	-- it. One UIStroke per surface, so the existing one is retuned, not joined.
	if selected then
		row.stroke.Color = theme.Semantic.Selection
		row.stroke.Thickness = 3
		row.stroke.Transparency = 0
	elseif loot then
		row.stroke.Color = theme.Semantic.Selection
		row.stroke.Thickness = 3
		row.stroke.Transparency = 0.4
	end

	if not message.read then
		local pipFill = theme.Colors.Accent
		local dot = UIStyler.Frame("UnreadDot")
		dot.BackgroundColor3 = pipFill
		dot.BackgroundTransparency = 0
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.Position = UDim2.new(0, 12, 0.5, 0)
		dot.Size = UDim2.fromOffset(12, 12)
		dot.ZIndex = 7
		UIStyler.Corner(theme.Radii.Pill).Parent = dot
		GPLayoutKit.SoftStroke(theme, dot, pipFill)
		dot.Parent = body
	end

	local icon = GPCelebrationKit.Icon(theme, body, message.icon or "player", 40)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 32, 0.5, 0)
	icon.ZIndex = 7

	local subject = GPLayoutKit.Text(
		theme,
		theme.TextSizes.Subtitle,
		if message.read then theme.Colors.TextPrimary else GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1),
		"Subject"
	)
	-- SoftCase, exactly as _GPRenderReader casts the SAME string: subject lines
	-- arrive SHOUTED from shared mail data ("WELCOME TO SEASON 3") and law 5
	-- forbids that here. Without this the one message reads two different ways
	-- depending on which pane you are looking at.
	subject.Text = GPCelebrationKit.SoftCase(message.subject)
	subject.TextXAlignment = Enum.TextXAlignment.Left
	subject.Position = UDim2.fromOffset(84, 12)
	subject.Size = UDim2.new(1, -180, 0, 24)
	subject.RichText = false
	subject.TextTruncate = Enum.TextTruncate.AtEnd
	subject.ZIndex = 7
	subject.Parent = body

	local from = GPLayoutKit.BodyText(theme, theme.TextSizes.Small + 1, theme.Colors.TextSecondary, "From")
	from.Text = message.from
	from.TextXAlignment = Enum.TextXAlignment.Left
	from.Position = UDim2.fromOffset(84, 42)
	from.Size = UDim2.new(1, -200, 0, 20)
	from.RichText = false
	from.TextTruncate = Enum.TextTruncate.AtEnd
	from.ZIndex = 7
	from.Parent = body

	local date = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Date")
	-- "14 JUL" -> "14 Jul", the same treatment the redeem ledger and the
	-- achievements shelf give a date under this pack.
	date.Text = GPCelebrationKit.SoftCase(message.date)
	date.TextXAlignment = Enum.TextXAlignment.Right
	date.AnchorPoint = Vector2.new(1, 0)
	date.Position = UDim2.new(1, -14, 0, 12)
	date.Size = UDim2.fromOffset(94, 18)
	date.RichText = false
	date.ZIndex = 7
	date.Parent = body

	local attachments = message.attachments
	if attachments and #attachments > 0 then
		-- The archive's own parcel art, falling back to its glyph — never the
		-- arcade build's raw 📎, which would arrive in a default font.
		local clip = GPCelebrationKit.Icon(theme, body, "gift", 22, {
			tint = if loot then GPLayoutKit.Deepen(theme, theme.Colors.Accent, 1) else theme.Colors.Disabled,
		})
		clip.AnchorPoint = Vector2.new(1, 1)
		clip.Position = UDim2.new(1, -14, 1, -8)
		clip.ZIndex = 7
		clip.Parent = body
	end

	-- CLAIMABLE ONLY: a card holding unclaimed loot blooms and twinkles. A
	-- selected card does not, and neither does a claimed one — otherwise the
	-- twinkle stops meaning "there is something for you in here".
	if loot then
		local glow = GPLayoutKit.Glow(theme, body, theme.Colors.Accent, self._gpRowShadows)
		table.insert(self._gpGlows, glow)
		local sparkles = GPCelebrationKit.Sparkles(theme, body, { count = 4, inflatePx = 6, zIndex = 8 })
		sparkles.SetEnabled(true)
		table.insert(self._gpSparkles, sparkles)
	end

	row.root.Activated:Connect(function()
		self:_SelectMessage(message)
	end)
	-- Animate LAST, after the final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, row.root, body)
end

-- The GP answer to _RenderReader (see the dispatch at the top of that
-- function). Same fields, same chip anatomy, this pack's copy.
function MailboxScreen:_GPRenderReader()
	local theme = self:GetTheme()
	for _, component in self._readerComponents do
		component:Destroy()
	end
	table.clear(self._readerComponents)
	table.clear(self._gpReaderSparkles)
	GPLayoutKit.ReleaseShadows(self._gpReaderShadows)
	for _, child in self._chipRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local message = self:_Selected()
	if not message then
		self._subjectLabel.Text = "No mail"
		self._fromLabel.Text = ""
		self._bodyLabel.Text = "Your shelf is clear. Rewards, receipts and studio news land right here."
		self._attachCaption.Visible = false
		self._attachStrip.Visible = false
		return
	end

	self._subjectLabel.Text = GPCelebrationKit.SoftCase(message.subject)
	-- The sender is an IDENTITY and stays exactly as it was authored (the same
	-- call the gift shelf makes on its "From" line); the date is copy and softens.
	self._fromLabel.Text = string.format("From %s   ·   %s", message.from, GPCelebrationKit.SoftCase(message.date))
	self._bodyLabel.Text = message.body

	local attachments = message.attachments
	local hasAny = attachments ~= nil and #attachments > 0
	self._attachCaption.Visible = hasAny
	self._attachStrip.Visible = hasAny
	if not hasAny or not attachments then
		return
	end

	for order, attachment in attachments do
		local chipFill = theme.Colors.Background
		local chip = UIStyler.Frame("Chip" .. order)
		chip.BackgroundColor3 = chipFill
		chip.BackgroundTransparency = 0
		chip.Size = UDim2.fromOffset(GP_CHIP_W, GP_CHIP_H)
		chip.LayoutOrder = order
		chip.ZIndex = 8
		chip.Parent = self._chipRow
		GPLayoutKit.Petal(theme, chip, order)
		GPLayoutKit.SoftStroke(theme, chip, chipFill)
		GPLayoutKit.Shadow(theme, chip, "sm", self._gpReaderShadows, chipFill)

		local icon = GPCelebrationKit.Icon(theme, chip, attachment.icon, 44)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 12)
		icon.ZIndex = 9
		if message.claimed then
			-- Claimed recolours in place (doc §11.2); the row is never removed.
			GPCelebrationKit.TintIcon(icon, theme.Colors.Disabled, 0.2)
		end

		-- Currency amounts keep their currency colour (doc §3.3); other rewards
		-- read as the pack's value colour, deepened so it holds on cream.
		local currencyId = if attachment.icon == "cash" then "Cash"
			elseif attachment.icon == "bux" then "Bux"
			elseif attachment.icon == "robux" then "Robux"
			else nil
		local amountTone = if message.claimed then theme.Colors.TextSecondary
			elseif currencyId then GPLayoutKit.Deepen(theme, UIChrome.CurrencyColor(theme, currencyId), 0.6)
			else GPLayoutKit.Deepen(theme, theme.Colors.Accent, 1)
		local amount = GPLayoutKit.NumberText(theme, theme.TextSizes.Body, amountTone, "Amount")
		amount.Text = comma(attachment.amount)
		amount.TextXAlignment = Enum.TextXAlignment.Center
		amount.Position = UDim2.fromOffset(0, 64)
		amount.Size = UDim2.new(1, 0, 0, 22)
		amount.ZIndex = 9
		amount.Parent = chip

		local state = GPLayoutKit.BodyText(
			theme,
			theme.TextSizes.Small,
			if message.claimed then theme.Colors.TextSecondary else GPLayoutKit.Deepen(theme, theme.Colors.Secondary, 1),
			"State"
		)
		state.Text = if message.claimed then "Claimed" else "Ready"
		state.Position = UDim2.fromOffset(0, 88)
		state.Size = UDim2.new(1, 0, 0, 18)
		state.ZIndex = 9
		state.Parent = chip

		-- The sticker stamp lands on the chip that has been taken.
		local stamp = GPCelebrationKit.Stamp(theme, chip, "Claimed", {
			sizePx = GP_CHIP_W - 4,
			textSize = theme.TextSizes.Small,
			zIndex = 10,
		})
		stamp.SetVisible(message.claimed == true)
	end

	local claim = GPCelebrationKit.Button(theme, self._attachStrip, {
		text = if message.claimed then "Claimed" else "Claim",
		variant = if message.claimed then "Grey" else "Green",
		size = UDim2.fromOffset(158, 48),
		anchorPoint = Vector2.new(1, 0.5),
		position = UDim2.new(1, 0, 0.5, 0),
		zIndex = 8,
		cornerIndex = 1,
		onClick = function()
			self:_Claim(message)
		end,
		-- Tracked in _readerComponents AND in the reader sink on purpose:
		-- _GPRenderReader releases through the component, teardown releases
		-- through the sink, and a second Release is a no-op.
	}, self._gpReaderShadows)
	table.insert(self._readerComponents, claim)

	if not message.claimed then
		local sparkles = GPCelebrationKit.Sparkles(theme, claim.Root, { inflatePx = 14, zIndex = 9 })
		sparkles.SetEnabled(true)
		table.insert(self._gpReaderSparkles, sparkles)
	end
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts only fall when a
-- handle is released — hand every GP shadow back here, and stop the one ticker.
function MailboxScreen:_OnTeardown()
	if self._gpStop then
		self._gpStop()
		self._gpStop = nil :: any
	end
	GPLayoutKit.ReleaseShadows(self._gpRowShadows)
	GPLayoutKit.ReleaseShadows(self._gpReaderShadows)
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	-- Cleared, not nil'd: _BuildGPLayout re-seeds all three on the next build.
	if self._gpSparkles then
		table.clear(self._gpSparkles)
	end
	if self._gpReaderSparkles then
		table.clear(self._gpReaderSparkles)
	end
	if self._gpGlows then
		table.clear(self._gpGlows)
	end
end

return MailboxScreen
