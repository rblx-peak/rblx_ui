--!strict
-- REDEEM CODES — the compact promo-code modal, Pottery Clash arcade family.
-- One §7.4 modal card: a big slate code field (3px black rim, FredokaOne, grey
-- placeholder), a full-width green REDEEM button, an inline result line (green
-- success / red reason) and a scrolling history of what has already been used.
--
-- The field uppercases as you type. Codes are compared uppercased and trimmed,
-- so "  kilnmaster " and "KILNMASTER" are the same code. Enter submits.
--
-- Show(data) accepts { history = {...}, onRedeem = function(code) }. onRedeem
-- may return either a { success, reward, message } record or (ok, message);
-- with no handler supplied the screen falls back to its own demo code table so
-- it is fully playable with no backend.
--
-- Fixed px at the 1650×1020 baseline (UIScreenBase attaches the UIScale).

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIScreenBase = require(script.Parent.UIScreenBase)

type Entry = { code: string, reward: string, date: string }

-- Card 760×640 → content 732×552 after the §7.4 inset.
local CARD = Vector2.new(760, 640)
local CONTENT_W = 732
local CONTENT_H = 552
local FIELD_H = 68
local BUTTON_H = 56
local ROW_W = CONTENT_W - 8 -- scrollbar reserve
local ROW_H = 60
local HISTORY_Y = 248

local WHITE = Color3.new(1, 1, 1)

-- Demo codes so the screen works standalone; a real game injects onRedeem.
local DEMO_CODES: { [string]: string } = {
	KILNMASTER = "500 CASH",
	POTTERY100 = "100 BUX",
	FIRSTFIRE = "EMBER CRATE x1",
	GLAZEDAY = "250 GLAZE DUST",
	CLAYSTART = "STARTER TOOL KIT",
}

local function demoHistory(): { Entry }
	return {
		{ code = "WELCOME2024", reward = "1,000 CASH", date = "12 MAR" },
		{ code = "KILNPARTY", reward = "50 BUX", date = "04 MAR" },
		{ code = "TENKLIKES", reward = "GOLD CRATE x2", date = "27 FEB" },
		{ code = "SPRINGGLAZE", reward = "400 GLAZE DUST", date = "19 FEB" },
		{ code = "BETAPOTTER", reward = "FOUNDER TITLE", date = "02 FEB" },
	}
end

local function today(): string
	return string.upper(os.date("%d %b"))
end

-- Normalise whatever the injected handler returns into (ok, message).
local function normalizeResult(result: any, extra: any): (boolean, string)
	if type(result) == "table" then
		local ok = result.success == true
		local text = result.reward or result.message
		return ok, string.upper(tostring(text or (if ok then "REWARD GRANTED" else "CODE REJECTED")))
	end
	if type(result) == "boolean" then
		return result, string.upper(tostring(extra or (if result then "REWARD GRANTED" else "CODE REJECTED")))
	end
	return false, "CODE REJECTED"
end

local RedeemCodesScreen = setmetatable({}, { __index = UIScreenBase })
RedeemCodesScreen.__index = RedeemCodesScreen

function RedeemCodesScreen.new()
	local self = UIScreenBase.new("RedeemCodesScreen", 10)
	self._history = demoHistory()
	self._onRedeem = nil :: ((string) -> any)?
	self._rows = {} :: { GuiObject }
	return setmetatable(self, RedeemCodesScreen)
end

function RedeemCodesScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function RedeemCodesScreen:_Ingest(data: any)
	if type(data) ~= "table" then
		return
	end
	if type(data.history) == "table" then
		self._history = data.history
	end
	if type(data.onRedeem) == "function" then
		self._onRedeem = data.onRedeem
	end
end

-- ========================================================================
-- Build
-- ========================================================================

function RedeemCodesScreen:_BuildField(theme: Types.UITheme, content: Frame)
	local caption = UIChrome.Text("Caption", 20, theme.Arcade.Gold)
	caption.Text = "ENTER A PROMO CODE"
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Size = UDim2.fromOffset(CONTENT_W, 26)
	caption.ZIndex = 44
	caption.Parent = content

	-- Chrome rides a wrapper frame, not the TextBox: a UIPadding on the box
	-- itself would also inset the icon child sitting inside it.
	local field = UIStyler.Frame("Field")
	field.BackgroundColor3 = theme.Arcade.Panel
	field.Position = UDim2.fromOffset(0, 32)
	field.Size = UDim2.fromOffset(CONTENT_W, FIELD_H)
	field.ZIndex = 44
	UIChrome.Corner("Arcade").Parent = field
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = field
	UIChrome.GlassGradient().Parent = field
	field.Parent = content

	local icon = IconArchive.Image(field, "codes", 36)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 16, 0.5, 0)
	icon.ZIndex = 45

	local box = Instance.new("TextBox")
	box.Name = "Code"
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Text = ""
	box.PlaceholderText = "TYPE YOUR CODE"
	box.PlaceholderColor3 = theme.Arcade.GreyOwned
	box.FontFace = theme.Fonts.Title
	box.TextSize = 30
	box.TextColor3 = WHITE
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Position = UDim2.fromOffset(64, 0)
	box.Size = UDim2.new(1, -80, 1, 0)
	box.ZIndex = 45
	UIChrome.TextOutline(box)
	box.Parent = field
	self._box = box

	-- Uppercase as typed. Re-assigning the same string never re-fires the
	-- changed signal, so this settles after one pass instead of looping.
	box:GetPropertyChangedSignal("Text"):Connect(function()
		box.Text = string.upper(box.Text)
	end)
	box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			self:_Redeem()
		end
	end)

	self._redeemBtn = UIButtonComponent.new()
	self._redeemBtn:Create(content, {
		text = "REDEEM",
		variant = "Green",
		size = UDim2.fromOffset(CONTENT_W, BUTTON_H),
		position = UDim2.fromOffset(0, 32 + FIELD_H + 12),
		onClick = function()
			self:_Redeem()
		end,
	})
	self._redeemBtn.Root.ZIndex = 45

	local result = UIChrome.Text("Result", 20, theme.Arcade.IceBlue)
	result.RichText = false
	result.Text = "CODES ARE CASE-INSENSITIVE AND SINGLE-USE."
	result.Position = UDim2.fromOffset(0, 32 + FIELD_H + 12 + BUTTON_H + 10)
	result.Size = UDim2.fromOffset(CONTENT_W, 28)
	result.ZIndex = 44
	result.Parent = content
	self._result = result
end

function RedeemCodesScreen:_BuildHistory(theme: Types.UITheme, content: Frame)
	local title = UIChrome.Text("HistoryTitle", 20, theme.Arcade.Gold)
	title.Text = "REDEEMED CODES"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(0, HISTORY_Y - 32)
	title.Size = UDim2.fromOffset(CONTENT_W, 26)
	title.ZIndex = 44
	title.Parent = content

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "History"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, HISTORY_Y)
	scroll.Size = UDim2.fromOffset(CONTENT_W, CONTENT_H - HISTORY_Y)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Arcade.Gold
	scroll.ZIndex = 43
	scroll.Parent = content
	UIStyler.ListLayout({ Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Left }).Parent = scroll
	self._historyList = scroll

	local empty = UIChrome.Text("HistoryEmpty", 20, theme.Arcade.GreyOwned)
	empty.Text = "NO CODES REDEEMED YET"
	empty.Position = UDim2.fromOffset(0, HISTORY_Y + 40)
	empty.Size = UDim2.fromOffset(CONTENT_W, 40)
	empty.Visible = false
	empty.ZIndex = 44
	empty.Parent = content
	self._historyEmpty = empty
end

function RedeemCodesScreen:_BuildHistoryRow(theme: Types.UITheme, entry: Entry, order: number)
	local row = UIStyler.Frame("Row" .. order)
	-- Zebra by list position (doc §9 row grammar), both fills at 0.15.
	row.BackgroundColor3 = if order % 2 == 1 then theme.Arcade.NearBlack2 else theme.Arcade.Row
	row.BackgroundTransparency = 0.15
	row.LayoutOrder = order
	row.Size = UDim2.fromOffset(ROW_W, ROW_H)
	row.ZIndex = 44
	UIChrome.Corner("Arcade").Parent = row
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = row
	UIChrome.GlassGradient().Parent = row
	row.Parent = self._historyList

	local tick = IconArchive.Image(row, "check", 24)
	tick.AnchorPoint = Vector2.new(0, 0.5)
	tick.Position = UDim2.new(0, 12, 0.5, 0)
	tick.ZIndex = 45
	if tick:IsA("ImageLabel") then
		tick.ImageColor3 = theme.Arcade.Green
	else
		(tick :: any).TextColor3 = theme.Arcade.Green
	end

	local code = UIChrome.Text("Code", 22, WHITE)
	code.RichText = false
	code.Text = entry.code
	code.TextXAlignment = Enum.TextXAlignment.Left
	code.TextTruncate = Enum.TextTruncate.AtEnd
	code.Position = UDim2.fromOffset(48, 0)
	code.Size = UDim2.fromOffset(240, ROW_H)
	code.ZIndex = 45
	code.Parent = row

	local reward = UIChrome.Text("Reward", 18, theme.Arcade.Gold)
	reward.RichText = false
	reward.Text = entry.reward
	reward.TextXAlignment = Enum.TextXAlignment.Left
	reward.TextTruncate = Enum.TextTruncate.AtEnd
	reward.Position = UDim2.fromOffset(296, 0)
	reward.Size = UDim2.fromOffset(280, ROW_H)
	reward.ZIndex = 45
	reward.Parent = row

	local date = UIChrome.Text("Date", 16, theme.Arcade.IceBlue)
	date.RichText = false
	date.Text = entry.date
	date.TextXAlignment = Enum.TextXAlignment.Right
	date.AnchorPoint = Vector2.new(1, 0.5)
	date.Position = UDim2.new(1, -14, 0.5, 0)
	date.Size = UDim2.fromOffset(120, ROW_H)
	date.ZIndex = 45
	date.Parent = row

	table.insert(self._rows, row)
end

function RedeemCodesScreen:_RenderHistory()
	if not self._historyList then
		return
	end
	local theme = self:GetTheme()
	for _, row in self._rows do
		row:Destroy()
	end
	table.clear(self._rows)
	for order, entry in self._history do
		self:_BuildHistoryRow(theme, entry, order)
	end
	self._historyEmpty.Visible = #self._history == 0
end

-- ========================================================================
-- Redeem
-- ========================================================================

function RedeemCodesScreen:_SetResult(ok: boolean, text: string)
	local theme = self:GetTheme()
	self._result.Text = text
	self._result.TextColor3 = if ok then theme.Arcade.Green else theme.Arcade.Red
	UIChrome.Pulse(theme, self._result)
end

function RedeemCodesScreen:_Redeem()
	local raw = string.upper((string.gsub(self._box.Text, "%s", "")))
	if raw == "" then
		self:_SetResult(false, "ENTER A CODE FIRST")
		self:_Toast("ENTER A CODE FIRST", "Error")
		return
	end
	for _, entry in self._history do
		if string.upper(entry.code) == raw then
			self:_SetResult(false, raw .. " HAS ALREADY BEEN USED")
			self:_Toast("CODE ALREADY USED", "Error")
			return
		end
	end

	local ok, message
	if self._onRedeem then
		ok, message = normalizeResult(self._onRedeem(raw))
	else
		local reward = DEMO_CODES[raw]
		ok = reward ~= nil
		message = if reward then reward else "THAT CODE ISN'T VALID"
	end

	if not ok then
		self:_SetResult(false, message)
		self:_Toast(message, "Error")
		return
	end

	table.insert(self._history, 1, { code = raw, reward = message, date = today() })
	self._box.Text = ""
	self:_SetResult(true, "REDEEMED  ·  " .. message)
	self:_Toast("REDEEMED " .. raw, "Success")
	self:_RenderHistory()
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function RedeemCodesScreen:_BuildContent()
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "REDEEM CODES",
		sizePx = CARD,
		onClose = function()
			self.ScreenController:HideScreen("codes")
		end,
	})
	self._modal = modal

	self:_BuildField(theme, modal.content)
	self:_BuildHistory(theme, modal.content)
	self:_RenderHistory()
end

function RedeemCodesScreen:_OnShow(data: any?)
	self:_Ingest(data)
	if self._built then
		self._box.Text = ""
		self:_RenderHistory()
	end
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function RedeemCodesScreen:Update(data: any)
	self:_Ingest(data)
	if self._built then
		self:_RenderHistory()
	end
end

function RedeemCodesScreen:Destroy()
	if self._redeemBtn then
		self._redeemBtn:Destroy()
		self._redeemBtn = nil
	end
	UIScreenBase.Destroy(self)
end

return RedeemCodesScreen
