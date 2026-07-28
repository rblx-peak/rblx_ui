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
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPCelebrationKit = require(script.Parent.Parent.Framework.GPCelebrationKit)
local UITicker = require(script.Parent.Parent.Framework.UITicker)

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
	-- GP repaints the pastel ledger in its own silhouettes and copy — see
	-- _GPRenderHistory.
	if self:LayoutKit() == "GP" then
		self:_GPRenderHistory()
		return
	end
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
	-- The result string is generated by SHARED _Redeem code in block capitals
	-- ("REDEEMED · 500 CASH"), and this pack does not shout — so the same string
	-- is re-cased for display, and the verdict tones come from the pack rather
	-- than the arcade green/red pair.
	if self:LayoutKit() == "GP" then
		self._result.Text = GPCelebrationKit.SoftCase(text)
		self._result.TextColor3 = if ok
			then GPLayoutKit.Deepen(theme, theme.Colors.Secondary, 1)
			else theme.Colors.Error
		UIChrome.Pulse(theme, self._result)
		return
	end
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
	-- GP layout language: the pastel code desk — cream page, a glazed code
	-- well, a stamped ledger — see _BuildGPLayout at the bottom.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end

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
	-- UIScreenBase.Destroy throws the Gui away but never runs _OnTeardown (only
	-- _ResetShell does), and a destroyed UIShadow does NOT decrement the budget
	-- counter on its own — so a Destroy without this leaves the page, the code
	-- well, the redeem chip's aura and every ledger row shadow counted forever.
	self:_OnTeardown()
	if self._redeemBtn then
		self._redeemBtn:Destroy()
		self._redeemBtn = nil
	end
	UIScreenBase.Destroy(self)
end

-- ======================================================================
-- GP layout (theme.LayoutKit == "GP") — THE CODE DESK.
--
-- Same modal, re-thrown in the pack's clay: a cream Page, a glazed petal well
-- for the code, a matcha redeem chip, and a ledger of petal rows each wearing
-- the sticker-stamp rosette that says this one is spent. Everything casts a
-- HUE-MATCHED shadow of its own fill.
--
-- THE CLAIMABLE SIGNAL IS EARNED HERE, NOT SPRINKLED: the redeem chip blooms
-- and sparkles ONLY while there is something in the field to redeem. An empty
-- field is not a claimable state, so it does not twinkle — and because nothing
-- else on the page ever twinkles, the twinkle means exactly one thing.
--
-- PRESENTATION ONLY. The same _history, the same injected _onRedeem contract
-- (record or (ok, message)), the same demo table, the same normalization, the
-- same already-used check, the same Enter-submits and uppercase-as-you-type.
-- Codes are IDENTIFIERS, not copy, so they stay upper — law 5 is about copy,
-- and _Redeem compares uppercased and trimmed either way.
--
-- DENSITY IS UNCHANGED: the caption, the field, the redeem control, the inline
-- result line, the ledger title, the empty-ledger line, and every history row's
-- tick, code, reward and date all survive.
-- ======================================================================

local GP_PAGE = Vector2.new(800, 700)
local GP_FIELD_H = 72
local GP_BUTTON_H = 56
local GP_ROW_H = 62
local GP_STAMP = 40
local GP_GLOW_BASE = 0.44
local GP_GLOW_SWING = 0.16
local GP_GLOW_HZ = 1.5

function RedeemCodesScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	local spacing = theme.Spacing

	self._gpShadows = {} :: { any }
	self._gpRowShadows = {} :: { any }
	self._gpSparkles = {} :: { any }
	self._gpGlows = {} :: { any }

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Redeem Codes",
		subtitleText = "Type it in, we will fire it for you.",
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("codes")
		end,
	})
	for _, handle in page.shadows do
		table.insert(self._gpShadows, handle)
	end
	self._modal = { card = page.panel, content = page.panel }

	local content = page.content

	local caption = GPLayoutKit.SectionLabel(theme, content, "Enter a promo code")
	caption.Size = UDim2.new(1, 0, 0, 26)
	caption.ZIndex = 4

	-- Chrome rides a wrapper frame, not the TextBox: a UIPadding on the box
	-- itself would also inset the icon child sitting inside it.
	local fieldFill = theme.Colors.SurfaceRaised
	local field = UIStyler.Frame("Field")
	field.BackgroundColor3 = fieldFill
	field.BackgroundTransparency = 0
	field.Position = UDim2.fromOffset(0, 32)
	field.Size = UDim2.new(1, 0, 0, GP_FIELD_H)
	field.ZIndex = 4
	field.Parent = content
	GPLayoutKit.Petal(theme, field, 0)
	GPLayoutKit.SoftStroke(theme, field, fieldFill)
	GPLayoutKit.Shadow(theme, field, "sm", self._gpShadows, fieldFill)
	-- Corner first, then the sheen (the kit's ordering contract).
	GPLayoutKit.GlazeSheen(theme, field)

	local icon = GPCelebrationKit.Icon(theme, field, "codes", 36)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, spacing.M, 0.5, 0)
	icon.ZIndex = 6

	local box = Instance.new("TextBox")
	box.Name = "Code"
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Text = ""
	box.PlaceholderText = "Type your code"
	box.PlaceholderColor3 = theme.Colors.TextSecondary
	box.FontFace = theme.Fonts.Title
	box.TextSize = theme.TextSizes.Title
	-- Ink, never near-white: TextOnPrimary measures 2.14:1 on this pack's
	-- pastels and the field is a pale surface.
	box.TextColor3 = theme.Colors.TextPrimary
	box.TextStrokeTransparency = 1
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Position = UDim2.fromOffset(spacing.M + 46, 0)
	box.Size = UDim2.new(1, -(spacing.M * 2 + 46), 1, 0)
	box.ZIndex = 6
	box.Parent = field
	self._box = box

	self._redeemBtn = GPCelebrationKit.Button(theme, content, {
		text = "Redeem",
		variant = "Green",
		textSize = theme.TextSizes.Subtitle,
		size = UDim2.new(1, 0, 0, GP_BUTTON_H),
		position = UDim2.fromOffset(0, 32 + GP_FIELD_H + 12),
		zIndex = 5,
		cornerIndex = 1,
		onClick = function()
			self:_Redeem()
		end,
	}, self._gpShadows)

	-- THE CLAIMABLE SIGNAL: the redeem chip only blooms and twinkles while
	-- there is something in the field to redeem (see the section header).
	local ready = GPLayoutKit.Glow(theme, self._redeemBtn.Chip, theme.Colors.Accent, self._gpShadows)
	ready:SetEnabled(false)
	local sparkles = GPCelebrationKit.Sparkles(theme, self._redeemBtn.Root, { inflatePx = 12, zIndex = 8 })
	table.insert(self._gpSparkles, sparkles)

	local function refreshReady()
		local armed = string.gsub(box.Text, "%s", "") ~= ""
		ready:SetEnabled(armed)
		sparkles.SetEnabled(armed)
		if armed then
			-- Registered only while it is actually breathing, so an idle desk
			-- costs the ticker nothing.
			self._gpGlows[1] = ready
		else
			table.clear(self._gpGlows)
		end
	end

	-- Uppercase as typed. Re-assigning the same string never re-fires the
	-- changed signal, so this settles after one pass instead of looping.
	box:GetPropertyChangedSignal("Text"):Connect(function()
		box.Text = string.upper(box.Text)
		refreshReady()
	end)
	box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			self:_Redeem()
		end
	end)
	refreshReady()

	local resultY = 32 + GP_FIELD_H + 12 + GP_BUTTON_H + 12
	local result = GPLayoutKit.BodyText(theme, theme.TextSizes.Body + 2, theme.Colors.TextSecondary, "Result")
	result.Text = "Codes are case-insensitive and single-use."
	result.RichText = false
	result.TextXAlignment = Enum.TextXAlignment.Left
	result.Position = UDim2.fromOffset(0, resultY)
	result.Size = UDim2.new(1, 0, 0, 30)
	result.ZIndex = 4
	result.Parent = content
	self._result = result

	local historyY = resultY + 42
	local title = GPLayoutKit.SectionLabel(theme, content, "Already fired")
	title.Position = UDim2.fromOffset(0, historyY)
	title.Size = UDim2.new(1, 0, 0, 26)
	title.ZIndex = 4

	-- MUST clip: unclipped rows spilling past the frame is a known past bug
	-- here, and the padding keeps the clip edge off the row shadows.
	local scroll = GPCelebrationKit.Scroller(theme, content, { padPx = 6, gapPx = spacing.S, zIndex = 3 })
	scroll.Name = "History"
	scroll.Position = UDim2.fromOffset(0, historyY + 32)
	scroll.Size = UDim2.new(1, 0, 1, -(historyY + 32))
	self._historyList = scroll

	local empty = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "HistoryEmpty")
	empty.Text = "Nothing fired yet — codes you use land here."
	empty.RichText = false
	empty.TextXAlignment = Enum.TextXAlignment.Left
	empty.Position = UDim2.fromOffset(0, historyY + 44)
	empty.Size = UDim2.new(1, 0, 0, 40)
	empty.Visible = false
	empty.ZIndex = 5
	empty.Parent = content
	self._historyEmpty = empty

	-- ONE ticker handler for the whole page (never a RunService connection).
	self._gpStop = UITicker.Register(function(_dt: number, now: number)
		if not UIChrome.IsOnScreen(page.panel) then
			return
		end
		for _, twinkle in self._gpSparkles do
			twinkle.Step(now)
		end
		local breath = GP_GLOW_BASE + GP_GLOW_SWING * (0.5 + 0.5 * math.sin(now * GP_GLOW_HZ))
		for _, glow in self._gpGlows do
			glow.Instance.Transparency = breath
		end
	end, page.panel)

	self:_GPRenderHistory()
end

-- One spent code, as a petal row wearing the stamp rosette.
function RedeemCodesScreen:_GPBuildHistoryRow(theme: Types.UITheme, entry: Entry, order: number)
	local row = GPCelebrationKit.Row(theme, self._historyList, order, self._gpRowShadows, {
		heightPx = GP_ROW_H,
		zIndex = 4,
	})
	row.root.Name = "Row" .. order
	row.root.Size = UDim2.new(1, -8, 0, GP_ROW_H)
	local body = row.body

	-- THE STICKER STAMP: a burst rosette with the archive tick sitting on it,
	-- which is how this pack says "spent". It does not rotate — a rotated
	-- descendant is NOT clipped by the scroller above it.
	local stamp = GPLayoutKit.Slice(theme, "sparkleBurst", theme.Colors.Accent, "Stamped")
	stamp.AnchorPoint = Vector2.new(0, 0.5)
	stamp.Position = UDim2.new(0, 12, 0.5, 0)
	stamp.Size = UDim2.fromOffset(GP_STAMP, GP_STAMP)
	stamp.ZIndex = 7
	stamp.Parent = body

	local tick = GPCelebrationKit.Icon(theme, stamp, "check", 22, {
		tint = GPLayoutKit.Deepen(theme, theme.Colors.Secondary, 1),
	})
	tick.AnchorPoint = Vector2.new(0.5, 0.5)
	tick.Position = UDim2.fromScale(0.5, 0.5)
	tick.ZIndex = 8

	-- The code is an IDENTIFIER, printed as the player typed it.
	local code = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Code")
	code.Text = entry.code
	code.RichText = false
	code.TextXAlignment = Enum.TextXAlignment.Left
	code.TextTruncate = Enum.TextTruncate.AtEnd
	code.Position = UDim2.fromOffset(GP_STAMP + 24, 0)
	code.Size = UDim2.new(0.36, 0, 1, 0)
	code.ZIndex = 7
	code.Parent = body

	local reward = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, GPLayoutKit.Deepen(theme, theme.Colors.Accent, 1), "Reward")
	reward.Text = GPCelebrationKit.SoftCase(entry.reward)
	reward.RichText = false
	reward.TextXAlignment = Enum.TextXAlignment.Left
	reward.TextTruncate = Enum.TextTruncate.AtEnd
	-- Column stops clear of the right-anchored date so a long reward line
	-- truncates instead of running under it.
	reward.Position = UDim2.new(0.36, GP_STAMP + 32, 0, 0)
	reward.Size = UDim2.new(0.34, 0, 1, 0)
	reward.ZIndex = 7
	reward.Parent = body

	local date = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Date")
	date.Text = GPCelebrationKit.SoftCase(entry.date)
	date.RichText = false
	date.TextXAlignment = Enum.TextXAlignment.Right
	date.AnchorPoint = Vector2.new(1, 0.5)
	date.Position = UDim2.new(1, -16, 0.5, 0)
	date.Size = UDim2.fromOffset(120, GP_ROW_H)
	date.ZIndex = 7
	date.Parent = body

	table.insert(self._rows, row.root)
end

-- The GP answer to _RenderHistory (see the dispatch at the top of that
-- function). Same clear/rebuild sequence, with the shadow sink handed back
-- BEFORE the rows that own it are destroyed.
function RedeemCodesScreen:_GPRenderHistory()
	if not self._historyList then
		return
	end
	local theme = self:GetTheme()
	GPLayoutKit.ReleaseShadows(self._gpRowShadows)
	for _, row in self._rows do
		row:Destroy()
	end
	table.clear(self._rows)
	for order, entry in self._history do
		self:_GPBuildHistoryRow(theme, entry, order)
	end
	self._historyEmpty.Visible = #self._history == 0
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts only fall when a
-- handle is released — hand every GP shadow back here, and stop the one ticker.
function RedeemCodesScreen:_OnTeardown()
	if self._gpStop then
		self._gpStop()
		self._gpStop = nil :: any
	end
	GPLayoutKit.ReleaseShadows(self._gpRowShadows)
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	-- Cleared, not nil'd: _BuildGPLayout re-seeds both on the next build.
	if self._gpSparkles then
		table.clear(self._gpSparkles)
	end
	if self._gpGlows then
		table.clear(self._gpGlows)
	end
end

return RedeemCodesScreen
