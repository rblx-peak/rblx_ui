--!strict
-- Boot / teleport loading screen — the Backdrop-band full-bleed cover
-- (UI_DESIGN_DOCUMENT.md §7.3), built on the Pottery Clash arcade family:
-- a near-black sheet, a spinning house sunburst behind a FredokaOne 66
-- wordmark, the §8 gold ruler, and a tip line that rotates every 4 seconds.
--
-- The ruler is REAL. Show{ assets = {...} } hands the list to
-- ContentProvider:PreloadAsync in small chunks and advances the bar as each
-- asset resolves. It can never hang the boot: a deadline is checked between
-- chunks AND a watchdog forces the ruler to 100% + fires onComplete if a fetch
-- stalls — a loading screen that never finishes is worse than one that rounds
-- up. Callers with their own pipeline skip `assets` entirely and drive
-- SetProgress(alpha, label) by hand.
--
-- Layout is fixed px on a 900×560 stage centred at the 1650×1020 baseline
-- (UIScreenBase attaches the UIScale). The rainbow wordmark gradient exists but
-- ships OFF — it is a per-title opt-in via Show{ rainbow = true }.

local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local ACLayoutKit = require(script.Parent.Parent.Framework.ACLayoutKit)
local UIAssets = require(script.Parent.Parent.Config.UIAssets)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIProgressBarComponent = require(script.Parent.Parent.Components.UIProgressBarComponent)

local LoadingScreen = setmetatable({}, { __index = UIScreenBase })
LoadingScreen.__index = LoadingScreen

-- Fixed px at the 1650×1020 baseline.
local STAGE_W = 900
local STAGE_H = 560
local SUNBURST_PX = 430
local RULER_W = 720
local RULER_H = 28
local TIP_SECONDS = 4
-- Small chunks so the deadline is re-checked often; one PreloadAsync call over
-- the whole list would be a single un-interruptible yield.
local PRELOAD_CHUNK = 6
local DEFAULT_TIMEOUT = 20

local DEFAULT_TITLE = "POTTERY CLASH"

local DEFAULT_TIPS = {
	"Every tap answers — a blocked button still tells you why.",
	"Cash is green, Bux are blue, Robux are magenta. Always.",
	"Gold means valuable: rewards, countdowns, and anything selected.",
	"Escape (or gamepad B) closes whatever panel is on top.",
	"Menus never black out the world — it keeps running behind them.",
	"Hold a slider knob to read its exact value above your thumb.",
}

-- A standalone demo payload so the screen shows a REAL preload with no backend:
-- the house sunburst plus a spread of archive icons the game will want anyway.
local DEMO_ICON_NAMES = {
	"chest", "crown", "trophy", "star", "gift", "cash", "bux", "robux",
	"sword", "shield", "key", "compass", "fire", "bolt", "rainbow",
	"sparkle", "wheel", "dice", "quest", "book",
}

local function demoAssets(): { string }
	local assets = { UIAssets.Sunburst }
	for _, name in DEMO_ICON_NAMES do
		local id = IconArchive.Id(name)
		if id then
			table.insert(assets, id)
		end
	end
	return assets
end

function LoadingScreen.new()
	local self = UIScreenBase.new("LoadingScreen", 5)
	self._alpha = 0
	self._phase = "LOADING"
	self._tips = DEFAULT_TIPS
	self._tipIndex = 0
	self._title = DEFAULT_TITLE
	-- Generation token: bumped on every new Show/preload and on hide, so an
	-- in-flight PreloadAsync from a previous session can never report onto a
	-- newer one (or onto a hidden screen).
	self._run = 0
	self._onComplete = nil :: ((timedOut: boolean) -> ())?
	-- Frugal ambient effects (doc §5.4): both connections live only while shown.
	self._spinConn = nil :: RBXScriptConnection?
	self._tipConn = nil :: RBXScriptConnection?
	return setmetatable(self, LoadingScreen)
end

function LoadingScreen:_BuildContent()
	if self:LayoutKit() == "AC" then
		self:_BuildACLayout()
		return
	end
	local theme = self:GetTheme()

	-- Full-bleed near-black sheet. Root is inverse-sized by the baseline
	-- UIScale, so fromScale(1,1) is the TRUE viewport at any resolution.
	local backdrop = UIStyler.Frame("Backdrop")
	backdrop.BackgroundColor3 = theme.Arcade.NearBlack
	backdrop.BackgroundTransparency = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 1
	backdrop.Parent = self.Root

	local stage = UIStyler.Frame("Stage")
	stage.BackgroundTransparency = 1
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromOffset(STAGE_W, STAGE_H)
	stage.ZIndex = 2
	stage.Parent = self.Root
	self._stage = stage

	-- The house glow motif (doc §10): sunburst behind the wordmark, gold at
	-- 0.86, spinning 45°/s and gated on being on-screen.
	local burstSlot = UIStyler.Frame("BurstSlot")
	burstSlot.BackgroundTransparency = 1
	burstSlot.AnchorPoint = Vector2.new(0.5, 0.5)
	burstSlot.Position = UDim2.fromOffset(STAGE_W / 2, 152)
	burstSlot.Size = UDim2.fromOffset(SUNBURST_PX, SUNBURST_PX)
	burstSlot.ZIndex = 3
	burstSlot.Parent = stage
	local burst, spin = UIAssets.SunburstBehind(burstSlot, theme.Arcade.SunburstGold, 0.86, 45)
	self._burst = burst
	self._spinConn = spin

	-- Wordmark: FredokaOne 66 white with the full black outline. The rainbow
	-- gradient is attached but disabled — SetRainbow(true) turns it on and
	-- starts the 0.45 cycles/sec offset scroll (doc §3.2).
	local wordmark = UIChrome.Text("Wordmark", 66, theme.Colors.TextPrimary)
	wordmark.RichText = false
	wordmark.Text = self._title
	wordmark.Position = UDim2.fromOffset(0, 104)
	wordmark.Size = UDim2.fromOffset(STAGE_W, 90)
	wordmark.ZIndex = 5
	local rainbow = UIChrome.RainbowGradient(theme)
	rainbow.Enabled = false
	rainbow.Parent = wordmark
	wordmark.Parent = stage
	self._wordmark = wordmark
	self._rainbow = rainbow

	local strap = UIChrome.BodyText("Strap", 17, theme.Arcade.IceBlue)
	strap.Text = "PREPARING YOUR SESSION"
	strap.Position = UDim2.fromOffset(0, 198)
	strap.Size = UDim2.fromOffset(STAGE_W, 24)
	strap.ZIndex = 5
	strap.Parent = stage

	-- Ruler caption row: phase left, percent right, both gold display type.
	local phase = UIChrome.Text("Phase", 20, theme.Arcade.Gold)
	phase.RichText = false
	phase.Text = self._phase
	phase.TextXAlignment = Enum.TextXAlignment.Left
	phase.Position = UDim2.fromOffset((STAGE_W - RULER_W) / 2, 296)
	phase.Size = UDim2.fromOffset(RULER_W - 120, 26)
	phase.TextTruncate = Enum.TextTruncate.AtEnd
	phase.ZIndex = 5
	phase.Parent = stage
	self._phaseLabel = phase

	local percent = UIChrome.Text("Percent", 20, theme.Arcade.SunburstGold)
	percent.RichText = false
	percent.Text = "0%"
	percent.TextXAlignment = Enum.TextXAlignment.Right
	percent.AnchorPoint = Vector2.new(1, 0)
	percent.Position = UDim2.fromOffset((STAGE_W + RULER_W) / 2, 296)
	percent.Size = UDim2.fromOffset(120, 26)
	percent.ZIndex = 5
	percent.Parent = stage
	self._percentLabel = percent

	-- The §8 ruler: near-black track, gold fill, alternating pale ticks.
	self._bar = UIProgressBarComponent.new()
	self._bar:Create(stage, {
		value = 0,
		maxValue = 100,
		size = UDim2.fromOffset(RULER_W, RULER_H),
		position = UDim2.fromOffset(STAGE_W / 2, 330),
		anchorPoint = Vector2.new(0.5, 0),
	})
	self._bar.Root.ZIndex = 5

	-- Rotating tip line. Wrapped (FredokaOne runs wide) inside a fixed box so a
	-- long tip never pushes the layout around.
	local tip = UIChrome.Text("Tip", 22, theme.Arcade.Gold)
	tip.Text = ""
	tip.TextWrapped = true
	tip.Position = UDim2.fromOffset(40, 410)
	tip.Size = UDim2.fromOffset(STAGE_W - 80, 76)
	tip.ZIndex = 5
	tip.Parent = stage
	self._tipLabel = tip

	self:_RenderProgress()
	self:_NextTip()
end

-- ARMORED CORE layout: no sunburst, no wordmark spectacle — a token-black
-- void with corner brackets and a centre-left boot column: mono SYSTEM BOOT
-- header, the title line, a hairline progress track with an accent fill, and
-- dim mono status lines. Every progress/status field of the classic contract
-- is mapped — a shim answers self._bar:Set/:Destroy and the phase / percent /
-- tip labels are reassigned — so SetProgress, _RenderProgress, _NextTip, the
-- preload pipeline and Update drive both layouts unchanged.
function LoadingScreen:_BuildACLayout()
	local theme = self:GetTheme()

	-- The void. Full-bleed over the TRUE viewport (Root is inverse-sized by
	-- the baseline UIScale, same as classic's backdrop).
	local page = UIStyler.Frame("Page")
	page.BackgroundColor3 = theme.Colors.Background
	page.BackgroundTransparency = 0
	page.Size = UDim2.fromScale(1, 1)
	page.ZIndex = 1
	page.Parent = self.Root
	ACLayoutKit.Brackets(theme, page)

	-- No sunburst in this language; nil the classic handles so _OnShow's spin
	-- restart stays quiet after a style swap.
	self._burst = nil
	self._spinConn = nil

	local TRACK_W = 360

	-- Centre-left boot column (x ≈ 15%, vertically centred).
	local column = UIStyler.Frame("BootColumn")
	column.BackgroundTransparency = 1
	column.AnchorPoint = Vector2.new(0, 0.5)
	column.Position = UDim2.new(0.15, 0, 0.5, 0)
	column.Size = UDim2.fromOffset(420, 180)
	column.ZIndex = 2
	column.Parent = page
	self._stage = column

	local boot = ACLayoutKit.SectionLabel(theme, column, "SYSTEM BOOT")
	boot.Position = UDim2.fromOffset(0, 0)
	boot.Size = UDim2.new(0, TRACK_W, 0, 14)

	-- The title still lands here (_OnShow/Update write self._wordmark.Text);
	-- mono 18, with the opt-in rainbow gradient attached but disabled.
	local wordmark = UIChrome.Text("Wordmark", 18, theme.Colors.TextPrimary)
	wordmark.RichText = false
	wordmark.Text = self._title
	wordmark.TextXAlignment = Enum.TextXAlignment.Left
	wordmark.TextTruncate = Enum.TextTruncate.AtEnd
	wordmark.Position = UDim2.fromOffset(0, 18)
	wordmark.Size = UDim2.new(0, TRACK_W, 0, 24)
	wordmark.Parent = column
	local rainbow = UIChrome.RainbowGradient(theme)
	rainbow.Enabled = false
	rainbow.Parent = wordmark
	self._wordmark = wordmark
	self._rainbow = rainbow

	local rule = ACLayoutKit.Rule(theme, column, 0.5)
	rule.Position = UDim2.fromOffset(0, 50)
	rule.Size = UDim2.new(0, TRACK_W, 0, 1)

	-- Track caption row: phase left, percent right — the same labels
	-- _RenderProgress rewrites.
	local phase = UIChrome.BodyText("Phase", 12, theme.Colors.TextSecondary)
	phase.RichText = false
	phase.Text = self._phase
	phase.TextXAlignment = Enum.TextXAlignment.Left
	phase.TextTruncate = Enum.TextTruncate.AtEnd
	phase.Position = UDim2.fromOffset(0, 62)
	phase.Size = UDim2.fromOffset(TRACK_W - 70, 16)
	phase.Parent = column
	self._phaseLabel = phase

	local percent = UIChrome.BodyText("Percent", 12, theme.Colors.Accent)
	percent.RichText = false
	percent.Text = "0%"
	percent.TextXAlignment = Enum.TextXAlignment.Right
	percent.Position = UDim2.fromOffset(TRACK_W - 70, 62)
	percent.Size = UDim2.fromOffset(70, 16)
	percent.Parent = column
	self._percentLabel = percent

	-- Hairline progress track + accent fill. The shim answers the classic
	-- ruler contract (self._bar:Set(value, max) / :Destroy()) so
	-- _RenderProgress and Destroy drive it unchanged.
	local track = UIStyler.Frame("Track")
	track.BackgroundColor3 = theme.Colors.Accent
	track.BackgroundTransparency = 0.85
	track.Position = UDim2.fromOffset(0, 84)
	track.Size = UDim2.fromOffset(TRACK_W, 2)
	track.Parent = column

	local fill = UIStyler.Frame("Fill")
	fill.BackgroundColor3 = theme.Colors.Accent
	fill.BackgroundTransparency = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Parent = track

	self._bar = {
		Root = track,
		Set = function(_bar: any, value: number, maxValue: number?)
			local max = if maxValue and maxValue > 0 then maxValue else 100
			fill.Size = UDim2.new(math.clamp(value / max, 0, 1), 0, 1, 0)
		end,
		Destroy = function(_bar: any) end,
	} :: any

	-- Dim mono status lines under the track: the session strap and the
	-- rotating tip (same _NextTip / tip-timer contract as classic).
	local strap = UIChrome.BodyText("Strap", 11, theme.Colors.TextSecondary)
	strap.Text = "PREPARING YOUR SESSION"
	strap.TextXAlignment = Enum.TextXAlignment.Left
	strap.Position = UDim2.fromOffset(0, 102)
	strap.Size = UDim2.fromOffset(TRACK_W, 14)
	strap.Parent = column

	local tip = UIChrome.BodyText("Tip", 11, theme.Colors.TextSecondary)
	tip.Text = ""
	tip.TextWrapped = true
	tip.TextXAlignment = Enum.TextXAlignment.Left
	tip.TextYAlignment = Enum.TextYAlignment.Top
	tip.Position = UDim2.fromOffset(0, 122)
	tip.Size = UDim2.fromOffset(TRACK_W, 44)
	tip.Parent = column
	self._tipLabel = tip

	self:_RenderProgress()
	self:_NextTip()
end

-- ---- progress ----------------------------------------------------------

-- Public: drive the ruler by hand (callers with their own asset pipeline).
-- alpha is 0..1; label re-captions the ruler's left side.
function LoadingScreen:SetProgress(alpha: number, label: string?)
	self._alpha = math.clamp(alpha or 0, 0, 1)
	if label and label ~= "" then
		self._phase = string.upper(label)
	end
	self:_RenderProgress()
end

function LoadingScreen:GetProgress(): number
	return self._alpha
end

function LoadingScreen:_RenderProgress()
	-- The ruler may not exist yet (progress driven before the first Show) or
	-- any more (a watchdog firing after teardown) — the value is still stored.
	if not self._bar then
		return
	end
	self._bar:Set(self._alpha * 100, 100)
	self._percentLabel.Text = string.format("%d%%", math.floor(self._alpha * 100 + 0.5))
	self._phaseLabel.Text = self._phase
end

-- Preload `assets` (asset-id strings or Instances) and report progress as each
-- one resolves. Chunked so the deadline is re-checked often; the watchdog is
-- the hard guarantee that the screen finishes even if PreloadAsync never
-- returns for a chunk.
function LoadingScreen:_StartPreload(assets: { any }, timeout: number)
	self._run += 1
	local run = self._run
	local total = #assets
	if total == 0 then
		self:SetProgress(1, "READY")
		self:_Complete(run, false)
		return
	end

	self:SetProgress(0, "LOADING ASSETS")
	local deadline = os.clock() + timeout

	task.delay(timeout, function()
		if self._run == run and self._alpha < 1 then
			self:SetProgress(1, "READY")
			self:_Complete(run, true)
		end
	end)

	task.spawn(function()
		local done = 0
		local index = 1
		while index <= total do
			if self._run ~= run or os.clock() >= deadline then
				break
			end
			local last = math.min(index + PRELOAD_CHUNK - 1, total)
			local chunk = table.move(assets, index, last, 1, {})
			-- A malformed id makes PreloadAsync throw: one bad asset must not
			-- strand the boot, so each chunk is isolated.
			pcall(function()
				ContentProvider:PreloadAsync(chunk, function()
					done += 1
					if self._run == run then
						self:SetProgress(done / total, "LOADING ASSETS")
					end
				end)
			end)
			index = last + 1
		end
		if self._run == run and self._alpha < 1 then
			self:SetProgress(1, "READY")
			self:_Complete(run, os.clock() >= deadline)
		end
	end)
end

function LoadingScreen:_Complete(run: number, timedOut: boolean)
	if self._run ~= run or self._completed then
		return
	end
	self._completed = true
	local callback = self._onComplete
	if callback then
		task.spawn(callback, timedOut)
	end
end

-- ---- wordmark / tips ---------------------------------------------------

-- The rainbow headline treatment (doc §3.2) — OFF by default; on, it scrolls
-- at 0.45 cycles/sec while the screen is on-screen.
function LoadingScreen:SetRainbow(enabled: boolean)
	self:_EnsureBuilt()
	self._rainbow.Enabled = enabled
	if enabled then
		if not self._rainbowConn then
			self._rainbowConn = UIChrome.ScrollGradient(self._rainbow, 0.45)
		end
	elseif self._rainbowConn then
		self._rainbowConn:Disconnect()
		self._rainbowConn = nil
	end
end

function LoadingScreen:_NextTip()
	local tips = self._tips
	if not self._tipLabel or #tips == 0 then
		return
	end
	self._tipIndex = (self._tipIndex % #tips) + 1
	self._tipLabel.Text = "TIP · " .. tips[self._tipIndex]
	-- A new tip POPS in (doc §5.1) so the change is read as an event, not as
	-- text quietly swapping under the player.
	UIChrome.PopIn(self:GetTheme(), self._tipLabel)
end

-- ---- lifecycle ---------------------------------------------------------

-- Show{ title, tips, assets, timeout, rainbow, onComplete }. Everything is
-- optional: with no data the screen renders its demo payload and still runs a
-- real preload, so it is shippable standalone.
function LoadingScreen:_OnShow(data: any?)
	local theme = self:GetTheme()
	local d = data or {}

	self._title = d.title or self._title
	self._wordmark.Text = self._title
	if type(d.tips) == "table" and #d.tips > 0 then
		self._tips = d.tips
		self._tipIndex = 0
	end
	self:SetRainbow(d.rainbow == true)
	self._onComplete = d.onComplete
	self._completed = false
	self:_NextTip()

	-- Restart the frugal ambient effects (they are disconnected on hide).
	if self._burst and not self._spinConn then
		self._spinConn = UIChrome.Spin(self._burst, 45)
	end
	if not self._tipConn then
		local elapsed = 0
		self._tipConn = RunService.Heartbeat:Connect(function(dt: number)
			if not UIChrome.IsOnScreen(self._tipLabel) then
				return
			end
			elapsed += dt
			if elapsed >= TIP_SECONDS then
				elapsed -= TIP_SECONDS
				self:_NextTip()
			end
		end)
	end

	UIChrome.PopIn(theme, self._stage)
	self:_StartPreload(d.assets or demoAssets(), d.timeout or DEFAULT_TIMEOUT)
end

function LoadingScreen:_OnHide()
	-- Bumping the token orphans any in-flight preload so it stops reporting
	-- onto a hidden screen.
	self._run += 1
	if self._spinConn then
		self._spinConn:Disconnect()
		self._spinConn = nil
	end
	if self._tipConn then
		self._tipConn:Disconnect()
		self._tipConn = nil
	end
	if self._rainbowConn then
		self._rainbowConn:Disconnect()
		self._rainbowConn = nil
	end
end

function LoadingScreen:Update(data: any)
	if not data then
		return
	end
	if data.progress ~= nil then
		self:SetProgress(data.progress, data.label)
	end
	if data.title and self._built then
		self._title = data.title
		self._wordmark.Text = data.title
	end
end

function LoadingScreen:Destroy()
	self:_OnHide()
	if self._bar then
		self._bar:Destroy()
		self._bar = nil
	end
	UIScreenBase.Destroy(self)
end

return LoadingScreen
