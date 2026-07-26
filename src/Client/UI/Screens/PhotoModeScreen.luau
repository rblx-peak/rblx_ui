--!strict
-- Photo mode (id "photoMode", hidesHUD): a boxless full-screen viewfinder —
-- the world IS the picture (doc §11.8) — with a control rail on the left.
-- The rail is deliberately the STUDIO family: photo mode is a creative
-- workbench, the one surface outside the pottery booth where the chocolate
-- palette belongs (doc §1).
--
--   * FOV slider (40–100) drives workspace.CurrentCamera.FieldOfView — this
--     screen's ONLY write outside the GUI layer; captured on show and
--     restored in _OnHide no matter which door closed the screen.
--   * Filters (NONE/WARM/NOIR/VIVID) apply as a full-screen tinted frame at
--     high transparency. A real game would drive Lighting ColorCorrection
--     instead; this screen keeps to the GUI layer on purpose.
--   * Frames render as overlay chrome on a transparent full-screen frame:
--     CINEMATIC letterbox bars, or a cream POLAROID border + caption strip.
--   * CAPTURE flashes a white 0.1s overlay and toasts — the engine cannot
--     write screenshots, so the flash frames the moment for Roblox's own
--     capture button.
--   * HIDE UI collapses the rail to a single SHOW UI chip so the shot stays
--     clean without losing the way back.
--
-- Show(data) = { onClose } — fired from _OnHide, so it reports EVERY exit
-- (close pill, Esc where the engine forwards it, or an exclusivity hide).

local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UISliderComponent = require(script.Parent.Parent.Components.UISliderComponent)
local UIToggleComponent = require(script.Parent.Parent.Components.UIToggleComponent)

local RAIL_W = 340
local RAIL_H = 570
local PAD = 18
local INNER_W = RAIL_W - PAD * 2
local SWATCH_W = 70
local SWATCH_H = 54
local SWATCH_GAP = 8
local FOV_MIN = 40
local FOV_MAX = 100
local DEFAULT_FOV = 70
local LETTERBOX_H = 120
local POLAROID_EDGE = 34
local POLAROID_BOTTOM = 140

-- Intrinsic effect colours, mirroring UIChrome's own locals: the capture
-- flash is white and a letterbox crop is black in ANY theme — these must not
-- follow a re-theme, so they are not token lookups.
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local FILTER_IDS = { "NONE", "WARM", "NOIR", "VIVID" }
local FRAME_IDS = { "NONE", "POLAROID", "CINEMATIC" }

-- Filter recipe: overlay tint + transparency. Tints are theme tokens so a
-- re-theme re-grades the filters with the palette.
local function filterTint(theme: Types.UITheme, id: string): (Color3?, number)
	if id == "WARM" then
		return theme.Arcade.Orange, 0.8
	elseif id == "NOIR" then
		return theme.Arcade.NearBlack, 0.45
	elseif id == "VIVID" then
		return theme.Arcade.Magenta, 0.88
	end
	return nil, 1
end

local PhotoModeScreen = setmetatable({}, { __index = UIScreenBase })
PhotoModeScreen.__index = PhotoModeScreen

function PhotoModeScreen.new()
	local self = UIScreenBase.new("PhotoModeScreen", 26)
	-- Set before the first Show so UIStyleEnforcer attaches with the studio
	-- ruleset (no forced black strokes/bevels on the rail's soft controls).
	self.Family = "Arcade" :: Types.UIFamily
	self._fov = DEFAULT_FOV
	self._filter = "NONE"
	self._frame = "NONE"
	self._filterChips = {} :: { [string]: { chip: TextButton, ring: UIStroke } }
	self._frameBars = {} :: { [string]: TextButton }
	self._savedFov = nil :: number?
	self._onClose = nil :: (() -> ())?
	self._escConn = nil :: RBXScriptConnection?
	return setmetatable(self, PhotoModeScreen)
end

function PhotoModeScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function PhotoModeScreen:_BuildContent()
	local theme = self:GetTheme()

	-- Effect layers under the chrome: tint first, frame chrome above it.
	local filterOverlay = UIStyler.Frame("FilterOverlay")
	filterOverlay.BackgroundTransparency = 1
	filterOverlay.Visible = false
	filterOverlay.ZIndex = 2
	filterOverlay.Parent = self.Root
	self._filterOverlay = filterOverlay

	local frameOverlay = UIStyler.Frame("FrameOverlay")
	frameOverlay.BackgroundTransparency = 1
	frameOverlay.ZIndex = 4
	frameOverlay.Parent = self.Root
	self._frameOverlay = frameOverlay

	-- The capture flash covers EVERYTHING in this gui, rail included.
	local flash = UIStyler.Frame("CaptureFlash")
	flash.BackgroundColor3 = WHITE
	flash.BackgroundTransparency = 0
	flash.Visible = false
	flash.ZIndex = 40
	flash.Parent = self.Root
	self._flash = flash

	-- ---- the studio control rail ----------------------------------------
	local rail = UIChrome.Panel(theme, "Arcade", "ControlRail")
	rail.AnchorPoint = Vector2.new(0, 0.5)
	rail.Position = UDim2.new(0, 16, 0.5, 0)
	rail.Size = UDim2.fromOffset(RAIL_W, RAIL_H)
	rail.ZIndex = 10
	rail.Parent = self.Root
	self._rail = rail

	local title = UIChrome.Text("Title", 24, theme.Arcade.Gold)
	title.Text = "PHOTO MODE"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(PAD, 14)
	title.Size = UDim2.fromOffset(INNER_W - 44, 30)
	title.Parent = rail

	-- Terracotta close pill, studio grammar ("X": FredokaOne has no ✕ glyph).
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AutoButtonColor = false
	close.BorderSizePixel = 0
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 12)
	close.Size = UDim2.fromOffset(36, 36)
	close.BackgroundColor3 = theme.Arcade.Red
	close.Text = "X"
	close.FontFace = theme.Fonts.Button
	close.TextSize = 18
	close.TextColor3 = theme.Colors.TextPrimary
	UIChrome.Corner("Arcade").Parent = close
	UIChrome.Stroke(theme, "Arcade").Parent = close
	close.Parent = rail
	close.Activated:Connect(function()
		self:_Close()
	end)
	UIChrome.Animate(theme, close)

	local slider = UISliderComponent.new()
	slider:Create(rail, {
		label = "FIELD OF VIEW",
		min = FOV_MIN,
		max = FOV_MAX,
		step = 1,
		value = self._fov,
		decimals = 0,
		size = UDim2.fromOffset(INNER_W, 44),
		position = UDim2.fromOffset(PAD, 58),
		onChanged = function(value: number)
			self._fov = value
			local camera = workspace.CurrentCamera
			if camera then
				camera.FieldOfView = value
			end
		end,
	})
	self._slider = slider

	self:_SectionLabel("FILTER", 116)
	for index, id in FILTER_IDS do
		self:_BuildFilterSwatch(rail, id, index)
	end

	self:_SectionLabel("FRAME", 214)
	for index, id in FRAME_IDS do
		self:_BuildFrameBar(rail, id, 240 + (index - 1) * 44)
	end

	local toggle = UIToggleComponent.new()
	toggle:Create(rail, {
		label = "HIDE UI",
		value = false,
		size = UDim2.fromOffset(INNER_W, 36),
		position = UDim2.fromOffset(PAD, 382),
		onChanged = function(on: boolean)
			self:_SetUiHidden(on)
		end,
	})
	self._toggle = toggle

	local capture = UIButtonComponent.new()
	capture:Create(rail, {
		text = "CAPTURE",
		variant = "Gold",
		size = UDim2.fromOffset(INNER_W, 56),
		position = UDim2.fromOffset(PAD, 434),
		onClick = function()
			self:_Capture()
		end,
	})
	self._captureButton = capture

	local hint = UIChrome.BodyText("Hint", 13, theme.Arcade.IceBlue)
	hint.Text = "Scripts can't save screenshots — frame the shot here, then use Roblox's capture button to keep it."
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextYAlignment = Enum.TextYAlignment.Top
	hint.Position = UDim2.fromOffset(PAD, 502)
	hint.Size = UDim2.fromOffset(INNER_W, 52)
	hint.Parent = rail

	-- The way back once HIDE UI collapses the rail.
	local chip = Instance.new("TextButton")
	chip.Name = "ShowUiChip"
	chip.AutoButtonColor = false
	chip.BorderSizePixel = 0
	chip.AnchorPoint = Vector2.new(0, 1)
	chip.Position = UDim2.new(0, 16, 1, -16)
	chip.Size = UDim2.fromOffset(120, 36)
	chip.BackgroundColor3 = theme.Arcade.NearBlack2
	chip.BackgroundTransparency = 0.2
	chip.Text = "SHOW UI"
	chip.FontFace = theme.Fonts.Button
	chip.TextSize = 14
	chip.TextColor3 = theme.Colors.TextPrimary
	chip.Visible = false
	chip.ZIndex = 12
	UIChrome.Corner("Arcade").Parent = chip
	UIChrome.Stroke(theme, "Arcade").Parent = chip
	chip.Parent = self.Root
	chip.Activated:Connect(function()
		if self._toggle then
			self._toggle:Set(false, false)
		end
		self:_SetUiHidden(false)
	end)
	UIChrome.Animate(theme, chip)
	self._showChip = chip

	self:_StyleFilterRings()
	self:_StyleFrameBars()
end

-- Arcade section label: FredokaOne 15 in ice blue (secondary notes, §3.2).
function PhotoModeScreen:_SectionLabel(text: string, y: number)
	local theme = self:GetTheme()
	local label = UIChrome.Text("Section", 15, theme.Arcade.IceBlue)
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Position = UDim2.fromOffset(PAD, y)
	label.Size = UDim2.fromOffset(INNER_W, 22)
	label.Parent = self._rail
end

-- ========================================================================
-- Filters
-- ========================================================================

-- Glaze-swatch grammar (doc §4.3): a tinted chip wearing a cream ring; the
-- ring goes solid on the selected filter.
function PhotoModeScreen:_BuildFilterSwatch(parent: Instance, id: string, index: number)
	local theme = self:GetTheme()
	local chip = Instance.new("TextButton")
	chip.Name = id .. "Swatch"
	chip.AutoButtonColor = false
	chip.BorderSizePixel = 0
	chip.Text = ""
	chip.Position = UDim2.fromOffset(PAD + (index - 1) * (SWATCH_W + SWATCH_GAP), 142)
	chip.Size = UDim2.fromOffset(SWATCH_W, SWATCH_H)
	local tint = filterTint(theme, id)
	chip.BackgroundColor3 = tint or theme.Arcade.NearBlack2
	UIChrome.Corner("Arcade").Parent = chip
	local ring = UIChrome.Stroke(theme, "Arcade", "Selection")
	ring.Parent = chip
	UIChrome.GlassGradient().Parent = chip

	local name = UIChrome.Text("Name", 13, theme.Colors.TextPrimary)
	name.Text = id
	name.Size = UDim2.fromScale(1, 1)
	name.Parent = chip

	chip.Parent = parent
	chip.Activated:Connect(function()
		self:_SetFilter(id)
	end)
	-- Applied LAST, after the final fill (it snapshots the rest colour).
	UIChrome.Animate(theme, chip)
	self._filterChips[id] = { chip = chip, ring = ring }
end

function PhotoModeScreen:_StyleFilterRings()
	for id, entry in self._filterChips do
		-- Swatch policy ring: 0.8 resting, solid cream when selected.
		entry.ring.Transparency = if id == self._filter then 0 else 0.8
	end
end

function PhotoModeScreen:_SetFilter(id: string)
	self._filter = id
	self:_ApplyFilter()
	self:_StyleFilterRings()
	local selected = self._filterChips[id]
	if selected then
		UIChrome.Pulse(self:GetTheme(), selected.chip)
	end
end

function PhotoModeScreen:_ApplyFilter()
	local overlay = self._filterOverlay :: Frame
	local tint, transparency = filterTint(self:GetTheme(), self._filter)
	if tint then
		overlay.BackgroundColor3 = tint
		overlay.BackgroundTransparency = transparency
		overlay.Visible = true
	else
		overlay.Visible = false
	end
end

-- ========================================================================
-- Frames
-- ========================================================================

function PhotoModeScreen:_BuildFrameBar(parent: Instance, id: string, y: number)
	local theme = self:GetTheme()
	local bar = Instance.new("TextButton")
	bar.Name = id .. "Bar"
	bar.AutoButtonColor = false
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromOffset(PAD, y)
	bar.Size = UDim2.fromOffset(INNER_W, 36)
	bar.Text = id
	bar.FontFace = theme.Fonts.Button
	bar.TextSize = 14
	bar.BackgroundColor3 = theme.Arcade.NearBlack2
	bar.TextColor3 = theme.Colors.Disabled
	UIChrome.Corner("Arcade").Parent = bar
	UIChrome.Stroke(theme, "Arcade").Parent = bar
	bar.Parent = parent
	bar.Activated:Connect(function()
		self:_SetFrame(id)
	end)
	-- Applied LAST; hover re-captures the rest colour, so the selected
	-- honey/deep recolours below stay safe.
	UIChrome.Animate(theme, bar)
	self._frameBars[id] = bar
end

-- Phase-pill states (doc §8): selected = honey + dark ink, rest = recessed.
function PhotoModeScreen:_StyleFrameBars()
	local theme = self:GetTheme()
	for id, bar in self._frameBars do
		local selected = id == self._frame
		bar.BackgroundColor3 = if selected then theme.Arcade.Gold else theme.Arcade.NearBlack2
		-- White + the enforced black outline reads cleanly on the gold bar;
		-- dark ink under a black outline smudged into an unreadable blob.
		bar.TextColor3 = if selected then theme.Colors.TextPrimary else theme.Colors.Disabled
	end
end

function PhotoModeScreen:_SetFrame(id: string)
	self._frame = id
	self:_ApplyFrame()
	self:_StyleFrameBars()
	local bar = self._frameBars[id]
	if bar then
		UIChrome.Pulse(self:GetTheme(), bar)
	end
end

function PhotoModeScreen:_ApplyFrame()
	local overlay = self._frameOverlay :: Frame
	for _, child in overlay:GetChildren() do
		child:Destroy()
	end
	local theme = self:GetTheme()

	if self._frame == "CINEMATIC" then
		local top = UIStyler.Frame("LetterboxTop")
		top.BackgroundColor3 = BLACK
		top.Size = UDim2.new(1, 0, 0, LETTERBOX_H)
		top.Parent = overlay

		local bottom = UIStyler.Frame("LetterboxBottom")
		bottom.BackgroundColor3 = BLACK
		bottom.AnchorPoint = Vector2.new(0, 1)
		bottom.Position = UDim2.fromScale(0, 1)
		bottom.Size = UDim2.new(1, 0, 0, LETTERBOX_H)
		bottom.Parent = overlay
	elseif self._frame == "POLAROID" then
		-- Cream, not pure white: the polaroid is chrome, so it wears the
		-- studio card colour and re-themes with the palette.
		local card = theme.Studio.Card
		local top = UIStyler.Frame("PolaroidTop")
		top.BackgroundColor3 = card
		top.Size = UDim2.new(1, 0, 0, POLAROID_EDGE)
		top.Parent = overlay

		local left = UIStyler.Frame("PolaroidLeft")
		left.BackgroundColor3 = card
		left.Size = UDim2.new(0, POLAROID_EDGE, 1, 0)
		left.Parent = overlay

		local right = UIStyler.Frame("PolaroidRight")
		right.BackgroundColor3 = card
		right.AnchorPoint = Vector2.new(1, 0)
		right.Position = UDim2.fromScale(1, 0)
		right.Size = UDim2.new(0, POLAROID_EDGE, 1, 0)
		right.Parent = overlay

		local strip = UIStyler.Frame("PolaroidBottom")
		strip.BackgroundColor3 = card
		strip.AnchorPoint = Vector2.new(0, 1)
		strip.Position = UDim2.fromScale(0, 1)
		strip.Size = UDim2.new(1, 0, 0, POLAROID_BOTTOM)
		strip.Parent = overlay

		local caption = UIChrome.Text("Caption", 30, theme.Studio.TextDark)
		caption.Text = "TODAY'S MASTERPIECE"
		caption.Position = UDim2.fromOffset(0, 32)
		caption.Size = UDim2.new(1, 0, 0, 38)
		caption.Parent = strip

		local sub = UIChrome.BodyText("Sub", 14, theme.Studio.TextMuted)
		sub.Text = "shot in photo mode"
		sub.Position = UDim2.fromOffset(0, 76)
		sub.Size = UDim2.new(1, 0, 0, 20)
		sub.TextXAlignment = Enum.TextXAlignment.Center
		sub.Parent = strip
	end
end

-- ========================================================================
-- Capture / hide-UI / lifecycle
-- ========================================================================

function PhotoModeScreen:_Capture()
	local flash = self._flash :: Frame
	flash.Visible = true
	task.delay(0.1, function()
		if flash.Parent then
			flash.Visible = false
		end
	end)
	self:_Toast("Use Roblox's capture button to save.", "Info")
end

function PhotoModeScreen:_SetUiHidden(hidden: boolean)
	self._uiHidden = hidden
	local rail = self._rail :: Frame
	rail.Visible = not hidden
	local chip = self._showChip :: TextButton
	chip.Visible = hidden
end

function PhotoModeScreen:_Close()
	self.ScreenController:HideScreen("photoMode")
end

function PhotoModeScreen:_OnShow(data: any?)
	self._onClose = if typeof(data) == "table" then data.onClose else nil

	-- Capture the live FOV and start the slider from it, so opening photo
	-- mode never visibly jumps the camera.
	local camera = workspace.CurrentCamera
	if camera then
		self._savedFov = camera.FieldOfView
		self._fov = math.clamp(camera.FieldOfView, FOV_MIN, FOV_MAX)
		if self._slider then
			self._slider:Set(self._fov)
		end
	end

	-- Filter/frame selections persist across opens (a photographer's setup);
	-- only the camera write leaves the GUI layer, so only it needs restoring.
	self:_ApplyFilter()
	self:_ApplyFrame()
	if self._toggle then
		self._toggle:Set(false, false)
	end
	self:_SetUiHidden(false)
	UIChrome.PopIn(self:GetTheme(), self._rail)

	-- Roblox reserves Esc for its own menu on most platforms; where the
	-- engine forwards it this closes photo mode, and the close pill remains
	-- the guaranteed door. _OnHide restores state whichever door was used.
	self._escConn = UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Escape then
			self:_Close()
		end
	end)
end

function PhotoModeScreen:_OnHide()
	if self._escConn then
		self._escConn:Disconnect()
		self._escConn = nil
	end
	local camera = workspace.CurrentCamera
	local savedFov = self._savedFov
	if camera and savedFov then
		camera.FieldOfView = savedFov
	end
	self._savedFov = nil
	if self._toggle then
		self._toggle:Set(false, false)
	end
	self:_SetUiHidden(false)
	local onClose = self._onClose
	self._onClose = nil
	if onClose then
		onClose()
	end
end

function PhotoModeScreen:Destroy()
	if self._escConn then
		self._escConn:Disconnect()
		self._escConn = nil
	end
	if self._slider then
		self._slider:Destroy()
		self._slider = nil
	end
	if self._toggle then
		self._toggle:Destroy()
		self._toggle = nil
	end
	if self._captureButton then
		self._captureButton:Destroy()
		self._captureButton = nil
	end
	UIScreenBase.Destroy(self)
end

return PhotoModeScreen
