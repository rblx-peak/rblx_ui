--!strict
-- The universal system-alert host (id "systemAlert", Overlay layer, NOT
-- exclusive): one screen for every "the session itself is in trouble" surface,
-- kind-driven through Show(data = { kind, ... }).
--
--   Banners (stack top-down in arrival order, each dismissed independently):
--     dataLoss    — persistent terracotta Studio.WarnBg bar: "PROGRESS WON'T
--                   SAVE" + RETRY; stays until a retry SUCCEEDS.
--     maintenance — near-black bar, 1Hz gold restart countdown (§11.3),
--                   pulsing once it drops under a minute.
--   Centred cards (only one at a time — the newest wins):
--     sessionLock — lock icon, LEAVE / RETRY.
--     kick        — banned icon, reason text, a single OK firing onAck (the
--                   SERVER performs the actual kick).
--     afk         — hourglass, a 30s draining gold ruler, I'M HERE; fires
--                   onTimeout when the ruler empties.
--
-- All ticking runs through ONE token-guarded 1Hz loop, gated on
-- UIChrome.IsOnScreen and stopped in _OnHide (doc §5.4). Real deployments hand
-- callbacks in via Show data (onRetry/onLeave/onAck/onTimeout...); with no
-- backend every control still answers with a plausible demo path (§11.1).
-- Show with no kind demos the dataLoss banner — the critical alert almost
-- every game ships without.

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIProgressBarComponent = require(script.Parent.Parent.Components.UIProgressBarComponent)

type Banner = {
	kind: string,
	frame: Frame,
	components: { any },
	countdownLabel: TextLabel?,
	remaining: number?,
	firedZero: boolean?,
	onRetry: (() -> ())?,
	onRestart: (() -> ())?,
}

type Card = {
	kind: string,
	dim: Frame,
	frame: Frame,
	components: { any },
	countdownLabel: TextLabel?,
	ruler: any?,
	remaining: number?,
	seconds: number?,
	onTimeout: (() -> ())?,
}

local BANNER_W = 1080
local BANNER_H = 56
local CARD_W = 540
local AFK_SECONDS = 30
local MAINTENANCE_DEMO_SECONDS = 4 * 60 + 32
local PULSE_UNDER = 60

local SystemAlertScreen = setmetatable({}, { __index = UIScreenBase })
SystemAlertScreen.__index = SystemAlertScreen

function SystemAlertScreen.new()
	-- 70: above every panel, modal (20) and reveal (62) — a kick or data-loss
	-- surface may never lose a z-fight. Only the debug band sits higher.
	local self = UIScreenBase.new("SystemAlertScreen", 70)
	self._banners = {} :: { Banner }
	self._card = nil :: Card?
	self._bannerOrder = 0
	self._tickToken = 0
	-- Demo-only retry state: the first attempt fails so the "blocked tap still
	-- answers" path is visible, the second succeeds and dismisses.
	self._dataRetryFailedOnce = false
	self._lockRetryFailedOnce = false
	return setmetatable(self, SystemAlertScreen)
end

function SystemAlertScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function SystemAlertScreen:_BuildContent()
	-- The banner stack: banners are fixed-width strips centred at the very top
	-- (the doc's warning-banner band), flowing downward in arrival order.
	local stack = UIStyler.Frame("BannerStack")
	stack.BackgroundTransparency = 1
	stack.AnchorPoint = Vector2.new(0.5, 0)
	stack.Position = UDim2.new(0.5, 0, 0, 10)
	stack.Size = UDim2.new(1, 0, 0, 0)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, 8),
	}).Parent = stack
	stack.Parent = self.Root
	self._stack = stack
end

-- ========================================================================
-- Dispatch
-- ========================================================================

function SystemAlertScreen:_Dispatch(data: any?)
	local payload: any = if typeof(data) == "table" then data else {}
	local kind: string? = payload.kind
	if kind == "dataLoss" then
		self:_ShowDataLoss(payload)
	elseif kind == "maintenance" then
		self:_ShowMaintenance(payload)
	elseif kind == "sessionLock" then
		self:_ShowSessionLock(payload)
	elseif kind == "kick" then
		self:_ShowKick(payload)
	elseif kind == "afk" then
		self:_ShowAfk(payload)
	elseif #self._banners == 0 and not self._card then
		-- No kind: default to the dataLoss banner — but never stomp alerts
		-- that are already up.
		self:_ShowDataLoss(payload)
	end
end

function SystemAlertScreen:_OnShow(data: any?)
	self:_Dispatch(data)
	self:_StartTicker()
end

function SystemAlertScreen:_OnHide()
	self:_StopTicker()
end

-- Live re-show without flicker: a visible host accepts new kinds via Update
-- exactly like Show (repeat ShowScreen calls land here too via Show).
function SystemAlertScreen:Update(data: any)
	if self._built and typeof(data) == "table" and data.kind then
		self:_Dispatch(data)
	end
end

-- Host affordance: the server-side owner of an alert dismisses it by kind
-- (e.g. its own retry succeeded, or ops cancelled the restart).
function SystemAlertScreen:Dismiss(kind: string)
	local card = self._card
	if card and card.kind == kind then
		self:_ClearCard()
	else
		self:_RemoveBanner(kind)
	end
	self:_HideIfEmpty()
end

function SystemAlertScreen:_HideIfEmpty()
	if #self._banners == 0 and not self._card then
		self.ScreenController:HideScreen("systemAlert")
	end
end

-- ========================================================================
-- Banners
-- ========================================================================

function SystemAlertScreen:_FindBanner(kind: string): Banner?
	for _, banner in self._banners do
		if banner.kind == kind then
			return banner
		end
	end
	return nil
end

function SystemAlertScreen:_RemoveBanner(kind: string)
	for i = #self._banners, 1, -1 do
		local banner = self._banners[i]
		if banner.kind == kind then
			for _, component in banner.components do
				component:Destroy()
			end
			banner.frame:Destroy()
			table.remove(self._banners, i)
		end
	end
end

-- One strip: solid fill, 3px black stroke, glass sheen, a centred horizontal
-- row for the content. A re-shown kind replaces its old banner (fresh data
-- wins); different kinds stack.
function SystemAlertScreen:_AddBanner(kind: string, fill: Color3): (Banner, Frame)
	self:_RemoveBanner(kind)
	local theme = self:GetTheme()
	self._bannerOrder += 1

	local frame = UIStyler.Frame(kind .. "Banner")
	frame.BackgroundColor3 = fill
	frame.BackgroundTransparency = 0
	frame.Size = UDim2.fromOffset(BANNER_W, BANNER_H)
	frame.LayoutOrder = self._bannerOrder
	UIChrome.Stroke(theme, "Arcade").Parent = frame
	UIChrome.GlassGradient().Parent = frame
	frame.Parent = self._stack

	local row = UIStyler.Frame("Row")
	row.BackgroundTransparency = 1
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 14),
	}).Parent = row
	row.Parent = frame

	local record: Banner = { kind = kind, frame = frame, components = {} }
	table.insert(self._banners, record)
	-- Entrance pop on the CONTENT row, never a container fade (doc §5).
	UIChrome.PopIn(theme, row)
	return record, row
end

-- Fixed-TextSize label sized by AutomaticSize.X so the row's list layout
-- measures the real string.
local function rowLabel(row: Frame, label: TextLabel, order: number): TextLabel
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 30)
	label.LayoutOrder = order
	label.Parent = row
	return label
end

function SystemAlertScreen:_ShowDataLoss(payload: any)
	local theme = self:GetTheme()
	local record, row = self:_AddBanner("dataLoss", theme.Studio.WarnBg)
	record.onRetry = payload.onRetry
	self._dataRetryFailedOnce = false

	IconArchive.Image(row, "warning", 32).LayoutOrder = 1

	local headline = rowLabel(row, UIChrome.Text("Headline", 21, theme.Studio.WarnText), 2)
	headline.Text = "PROGRESS WON'T SAVE"

	-- GothamMedium carries the quiet half (and the em dash FredokaOne lacks).
	local body = rowLabel(row, UIChrome.BodyText("Body", 16, theme.Studio.WarnText), 3)
	body.Text = "— data failed to load"

	local retry = UIButtonComponent.new()
	retry:Create(row, {
		text = "RETRY",
		variant = "Green",
		size = UDim2.fromOffset(128, 38),
		layoutOrder = 4,
		onClick = function()
			self:_RetryDataLoss(record)
		end,
	})
	table.insert(record.components, retry)
	self:_PlaySound("Error")
end

function SystemAlertScreen:_RetryDataLoss(record: Banner)
	if record.onRetry then
		-- The host owns the outcome: it re-Shows on another failure or calls
		-- Dismiss("dataLoss") once its retry succeeds.
		record.onRetry()
		return
	end
	if not self._dataRetryFailedOnce then
		self._dataRetryFailedOnce = true
		UIChrome.Pulse(self:GetTheme(), record.frame)
		self:_Toast("Still can't reach the data store. Try again.", "Error")
		return
	end
	self:_RemoveBanner("dataLoss")
	self:_Toast("Data loaded. Progress is saving again.", "Success")
	self:_HideIfEmpty()
end

function SystemAlertScreen:_ShowMaintenance(payload: any)
	local theme = self:GetTheme()
	local record, row = self:_AddBanner("maintenance", theme.Arcade.NearBlack2)
	record.remaining = payload.seconds or MAINTENANCE_DEMO_SECONDS
	record.onRestart = payload.onRestart
	record.firedZero = false

	IconArchive.Image(row, "clock", 32).LayoutOrder = 1

	local countdown = rowLabel(row, UIChrome.Text("Countdown", 22, theme.Arcade.SunburstGold), 2)
	countdown.Text = "SERVER RESTART IN " .. UIChrome.FormatCountdown(record.remaining :: number)
	record.countdownLabel = countdown
end

-- ========================================================================
-- Centred cards (one at a time — the newest wins)
-- ========================================================================

function SystemAlertScreen:_ClearCard()
	local card = self._card
	if not card then
		return
	end
	for _, component in card.components do
		component:Destroy()
	end
	card.dim:Destroy()
	card.frame:Destroy()
	self._card = nil
end

-- Shared card shell: dim → arcade panel → big icon → title. Kinds add their
-- body/extras at fixed px below. No close X: these are forced choices, the
-- buttons are the only doors out.
function SystemAlertScreen:_CardShell(kind: string, heightPx: number, iconName: string, titleText: string): Card
	self:_ClearCard()
	local theme = self:GetTheme()

	local dim = UIStyler.Frame("AlertDim")
	dim.BackgroundColor3 = theme.Colors.Overlay
	dim.BackgroundTransparency = 0.45
	dim.ZIndex = 30
	dim.Parent = self.Root

	local frame = UIChrome.Panel(theme, "Arcade", kind .. "Card")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(CARD_W, heightPx)
	frame.ZIndex = 31
	frame.Parent = self.Root

	local icon = IconArchive.Image(frame, iconName, 72)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 26)

	local title = UIChrome.Text("Title", 30, theme.Colors.TextPrimary)
	title.Text = titleText
	title.Position = UDim2.fromOffset(24, 108)
	title.Size = UDim2.new(1, -48, 0, 36)
	title.Parent = frame

	local card: Card = { kind = kind, dim = dim, frame = frame, components = {} }
	self._card = card
	UIChrome.PopIn(theme, frame)
	self:_PlaySound("Error")
	return card
end

function SystemAlertScreen:_CardBody(card: Card, text: string, y: number, height: number)
	local theme = self:GetTheme()
	local body = UIChrome.BodyText("Body", 18, theme.Colors.TextSecondary)
	body.Text = text
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Center
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.Position = UDim2.fromOffset(40, y)
	body.Size = UDim2.new(1, -80, 0, height)
	body.Parent = card.frame
end

function SystemAlertScreen:_CardButtonRow(card: Card): Frame
	local row = UIStyler.Frame("Buttons")
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -24)
	row.Size = UDim2.new(1, -48, 0, 52)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 16),
	}).Parent = row
	row.Parent = card.frame
	return row
end

function SystemAlertScreen:_ShowSessionLock(payload: any)
	local card = self:_CardShell("sessionLock", 348, "lock", "ALREADY PLAYING ELSEWHERE")
	self:_CardBody(card, "This account is connected to another server. Leave that session, or retry once it has closed.", 152, 56)
	self._lockRetryFailedOnce = false

	local row = self:_CardButtonRow(card)

	local leave = UIButtonComponent.new()
	leave:Create(row, {
		text = "LEAVE",
		variant = "Red",
		size = UDim2.fromOffset(170, 52),
		layoutOrder = 1,
		onClick = function()
			if payload.onLeave then
				payload.onLeave()
				return
			end
			self:_ClearCard()
			self:_Toast("This is where the client would leave the game.", "Info")
			self:_HideIfEmpty()
		end,
	})
	table.insert(card.components, leave)

	local retry = UIButtonComponent.new()
	retry:Create(row, {
		text = "RETRY",
		variant = "Green",
		size = UDim2.fromOffset(170, 52),
		layoutOrder = 2,
		onClick = function()
			if payload.onRetry then
				payload.onRetry()
				return
			end
			if not self._lockRetryFailedOnce then
				self._lockRetryFailedOnce = true
				UIChrome.Pulse(self:GetTheme(), card.frame)
				self:_Toast("Still locked. That session is active.", "Error")
				return
			end
			self:_ClearCard()
			self:_Toast("Session lock released. You're in.", "Success")
			self:_HideIfEmpty()
		end,
	})
	table.insert(card.components, retry)
end

function SystemAlertScreen:_ShowKick(payload: any)
	local card = self:_CardShell("kick", 330, "banned", "REMOVED FROM THIS SERVER")
	local reason = payload.reason or "Kicked by a moderator: repeated griefing after two warnings."
	self:_CardBody(card, reason, 152, 56)

	local row = self:_CardButtonRow(card)
	local ok = UIButtonComponent.new()
	ok:Create(row, {
		text = "OK",
		variant = "Red",
		size = UDim2.fromOffset(200, 52),
		onClick = function()
			if payload.onAck then
				-- The card stays up: the SERVER completes the kick, and the
				-- disconnect takes the whole Gui with it.
				payload.onAck()
				return
			end
			self:_ClearCard()
			self:_Toast("The server would disconnect you now.", "Info")
			self:_HideIfEmpty()
		end,
	})
	table.insert(card.components, ok)
end

function SystemAlertScreen:_ShowAfk(payload: any)
	local theme = self:GetTheme()
	local seconds: number = payload.seconds or AFK_SECONDS
	local card = self:_CardShell("afk", 408, "hourglass", "ARE YOU STILL THERE?")
	self:_CardBody(card, "You've been idle for a while. Answer before the ruler empties or you'll be dropped from the server.", 152, 44)
	card.remaining = seconds
	card.seconds = seconds
	card.onTimeout = payload.onTimeout

	-- Countdown surface (doc §11.3): gold FredokaOne, 1Hz via the ticker.
	local countdown = UIChrome.Text("Countdown", 26, theme.Arcade.SunburstGold)
	countdown.Text = UIChrome.FormatCountdown(seconds)
	countdown.Position = UDim2.fromOffset(24, 202)
	countdown.Size = UDim2.new(1, -48, 0, 32)
	countdown.Parent = card.frame
	card.countdownLabel = countdown

	-- The shrinking 30s gold ruler: value = seconds LEFT, so it drains.
	local ruler = UIProgressBarComponent.new()
	ruler:Create(card.frame, {
		value = seconds,
		maxValue = seconds,
		size = UDim2.fromOffset(380, 22),
		position = UDim2.new(0.5, 0, 0, 246),
		anchorPoint = Vector2.new(0.5, 0),
	})
	card.ruler = ruler
	table.insert(card.components, ruler)

	local row = self:_CardButtonRow(card)
	local here = UIButtonComponent.new()
	here:Create(row, {
		text = "I'M HERE",
		variant = "Green",
		size = UDim2.fromOffset(220, 52),
		onClick = function()
			if payload.onConfirm then
				payload.onConfirm()
			end
			self:_ClearCard()
			self:_Toast("Welcome back!", "Success")
			self:_HideIfEmpty()
		end,
	})
	table.insert(card.components, here)
end

-- ========================================================================
-- The 1Hz ticker: one token-guarded loop drives every countdown. The token
-- bump in _StopTicker ends the loop; a re-Show starts a fresh one, so at most
-- one loop is ever alive.
-- ========================================================================

function SystemAlertScreen:_StartTicker()
	self._tickToken += 1
	local token = self._tickToken
	task.spawn(function()
		while token == self._tickToken do
			task.wait(1)
			if token ~= self._tickToken then
				break
			end
			if UIChrome.IsOnScreen(self.Root) then
				self:_Tick()
			end
		end
	end)
end

function SystemAlertScreen:_StopTicker()
	self._tickToken += 1
end

function SystemAlertScreen:_Tick()
	local theme = self:GetTheme()

	for _, banner in self._banners do
		local remaining = banner.remaining
		if banner.kind == "maintenance" and remaining and remaining > 0 then
			remaining -= 1
			banner.remaining = remaining
			local label = banner.countdownLabel
			if label then
				if remaining == 0 then
					label.Text = "SERVER RESTARTING NOW"
				else
					label.Text = "SERVER RESTART IN " .. UIChrome.FormatCountdown(remaining)
					if remaining <= PULSE_UNDER then
						UIChrome.Pulse(theme, label)
					end
				end
			end
			if remaining == 0 and not banner.firedZero then
				banner.firedZero = true
				if banner.onRestart then
					banner.onRestart()
				end
			end
		end
	end

	local card = self._card
	if card and card.kind == "afk" then
		local remaining = card.remaining
		if remaining and remaining > 0 then
			remaining -= 1
			card.remaining = remaining
			local label = card.countdownLabel
			if label then
				label.Text = UIChrome.FormatCountdown(remaining)
				if remaining <= 10 and remaining > 0 then
					UIChrome.Pulse(theme, label)
				end
			end
			if card.ruler then
				card.ruler:Set(remaining, card.seconds or AFK_SECONDS)
			end
			if remaining == 0 then
				local onTimeout = card.onTimeout
				self:_ClearCard()
				if onTimeout then
					onTimeout()
				else
					self:_Toast("Disconnected for inactivity. (The server would kick here.)", "Error")
				end
				self:_HideIfEmpty()
			end
		end
	end
end

function SystemAlertScreen:Destroy()
	self:_StopTicker()
	for _, banner in self._banners do
		for _, component in banner.components do
			component:Destroy()
		end
	end
	table.clear(self._banners)
	self:_ClearCard()
	UIScreenBase.Destroy(self)
end

return SystemAlertScreen
