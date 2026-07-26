--!strict
-- Contextual interaction prompt (HUD widget): the "[E] OPEN" chip, plus a
-- hold-progress fill for hold-to-use targets.
--
-- The chip rebuilds itself per input device (doc §11.7 — device adaptation is
-- centralised, and the ONLY per-device code is the copy): keyboard shows the
-- letter in a square arcade chip, a gamepad shows its face button in a green
-- pill (colour is how a console player finds the button), touch shows the word
-- TAP. UserInputService.LastInputTypeChanged drives the swap, so picking up a
-- controller mid-session re-labels the prompt without anything else asking.
--
-- Hold is real input, not a decoration: holding the mapped key (or the chip
-- itself, for touch) fills the bar over `holdSeconds`; letting go drains it
-- fast, and completing fires onComplete once and re-arms.

local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local HUDWidgetBase = require(script.Parent.HUDWidgetBase)

local InteractionPromptWidget = setmetatable({}, { __index = HUDWidgetBase })
InteractionPromptWidget.__index = InteractionPromptWidget

local CHIP = 48
local BAR_W, BAR_H = 220, 6
local RELEASE_DRAIN = 0.25 -- seconds to empty a released hold

-- One row per input mode: the label on the chip, its size, and the fill token.
local MODES = {
	Keyboard = { text = "E", width = CHIP, fill = "NearBlack2", pill = false, key = Enum.KeyCode.E },
	Gamepad = { text = "A", width = CHIP, fill = "Green", pill = true, key = Enum.KeyCode.ButtonA },
	Touch = { text = "TAP", width = 84, fill = "Blue", pill = false, key = Enum.KeyCode.Unknown },
}

function InteractionPromptWidget.new()
	local self = HUDWidgetBase.new("interact", "InteractionPromptWidget")
	self._label = "OPEN CRATE"
	self._hold = 1.2
	self._progress = 0
	self._holding = false
	self._mode = "Keyboard"
	return setmetatable(self, InteractionPromptWidget)
end

function InteractionPromptWidget:_Build(props: HUDWidgetBase.Props)
	local theme = self.Theme
	if props.text then
		self._label = props.text
	end
	if props.holdSeconds then
		self._hold = props.holdSeconds
	end

	local row = UIStyler.Frame("Row")
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.fromScale(0.5, 0)
	row.Size = UDim2.fromOffset(0, CHIP)
	row.AutomaticSize = Enum.AutomaticSize.X
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = row
	row.Parent = self.Root

	-- The chip is a real button so touch (and a mouse click) can drive the
	-- hold on devices with no key to press.
	local chip = Instance.new("TextButton")
	chip.Name = "Chip"
	chip.AutoButtonColor = false
	chip.BorderSizePixel = 0
	chip.Text = "E"
	chip.FontFace = theme.Fonts.Button
	chip.TextSize = 24
	chip.TextColor3 = Color3.new(1, 1, 1)
	chip.BackgroundColor3 = theme.Arcade.NearBlack2
	chip.Size = UDim2.fromOffset(CHIP, CHIP)
	chip.LayoutOrder = 1
	UIChrome.TextOutline(chip)
	self._chipCorner = UIChrome.Corner("Arcade")
	self._chipCorner.Parent = chip
	self._chipStroke = UIChrome.Stroke(theme, "Arcade", "Panel")
	self._chipStroke.Parent = chip
	chip.Parent = row
	self._chip = chip

	local caption = UIChrome.Text("Caption", 26, Color3.new(1, 1, 1))
	caption.Text = self._label
	caption.Size = UDim2.fromOffset(0, CHIP)
	caption.AutomaticSize = Enum.AutomaticSize.X
	caption.LayoutOrder = 2
	caption.Parent = row
	self._caption = caption

	local track = UIStyler.Frame("HoldTrack")
	track.BackgroundColor3 = theme.Arcade.RulerTrack
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.new(0.5, 0, 0, CHIP + 10)
	track.Size = UDim2.fromOffset(BAR_W, BAR_H)
	track.ClipsDescendants = true
	UIChrome.Corner("Arcade").Parent = track
	self._trackStroke = UIChrome.Stroke(theme, "Arcade", "Wheel")
	self._trackStroke.Parent = track
	track.Parent = self.Root
	self._track = track

	local fill = UIStyler.Frame("HoldFill")
	fill.BackgroundColor3 = theme.Arcade.SunburstGold
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	self._fill = fill

	-- Press/release on the chip itself (touch + mouse).
	self:_Connect(chip.MouseButton1Down, function()
		self:_SetHolding(true)
	end)
	self:_Connect(chip.MouseButton1Up, function()
		self:_SetHolding(false)
	end)
	self:_Connect(chip.MouseLeave, function()
		self:_SetHolding(false)
	end)
	UIChrome.Animate(self.Theme, chip)

	-- Press/release on the mapped key.
	-- Touch has no key (its spec maps to KeyCode.Unknown, which is also what a
	-- mouse click reports) — those devices drive the hold through the chip.
	self:_Connect(UserInputService.InputBegan, function(input: InputObject, processed: boolean)
		local key = self:_ModeSpec().key
		if not processed and key ~= Enum.KeyCode.Unknown and input.KeyCode == key then
			self:_SetHolding(true)
		end
	end)
	self:_Connect(UserInputService.InputEnded, function(input: InputObject)
		local key = self:_ModeSpec().key
		if key ~= Enum.KeyCode.Unknown and input.KeyCode == key then
			self:_SetHolding(false)
		end
	end)
	self:_Connect(UserInputService.LastInputTypeChanged, function()
		self:_RefreshMode()
	end)

	self:_RenderStep(function(dt: number)
		self:_StepHold(dt)
	end)

	self:_RefreshMode()
	self:_Render()
end

-- ---- API ---------------------------------------------------------------

-- data: { text, holdSeconds, visible }
function InteractionPromptWidget:Update(data: any)
	if data == nil then
		self:SetVisible(false)
		return
	end
	if type(data) == "string" then
		self:SetTarget(data, 0)
		return
	end
	if data.text then
		self:SetTarget(data.text, data.holdSeconds)
	end
	if data.visible ~= nil then
		self:SetVisible(data.visible)
	end
end

function InteractionPromptWidget:SetTarget(text: string, holdSeconds: number?)
	self._label = text
	self._hold = holdSeconds or 0
	self._progress = 0
	self._holding = false
	self:SetVisible(true)
	self:_Render()
end

function InteractionPromptWidget:Clear()
	self._holding = false
	self._progress = 0
	self:_Render()
	self:SetVisible(false)
end

-- ---- input -------------------------------------------------------------

function InteractionPromptWidget:_ModeSpec()
	return MODES[self._mode] or MODES.Keyboard
end

function InteractionPromptWidget:_RefreshMode()
	local last = UserInputService:GetLastInputType()
	local mode = "Keyboard"
	if last == Enum.UserInputType.Touch then
		mode = "Touch"
	elseif last.Name:sub(1, 7) == "Gamepad" then
		mode = "Gamepad"
	end
	if mode == self._mode then
		return
	end
	self._mode = mode
	self:_Render()
end

function InteractionPromptWidget:_SetHolding(holding: boolean)
	if not self.Root.Visible then
		return
	end
	if holding and self._hold <= 0 then
		-- Tap targets fire on the press and answer with a pulse.
		self:_Pulse(self._chip)
		local onComplete = self.Props.onComplete
		if onComplete then
			onComplete(self._label)
		end
		return
	end
	self._holding = holding
end

function InteractionPromptWidget:_StepHold(dt: number)
	if self._hold <= 0 then
		return
	end
	local before = self._progress
	if self._holding then
		self._progress = math.min(self._progress + dt / self._hold, 1)
	else
		self._progress = math.max(self._progress - dt / RELEASE_DRAIN, 0)
	end
	if self._progress ~= before and self._fill then
		self._fill.Size = UDim2.fromScale(self._progress, 1)
	end
	if self._progress >= 1 then
		self._progress = 0
		self._holding = false
		if self._fill then
			self._fill.Size = UDim2.fromScale(0, 1)
		end
		self:_Pulse(self._chip)
		local onComplete = self.Props.onComplete
		if onComplete then
			onComplete(self._label)
		end
	end
end

-- ---- paint -------------------------------------------------------------

function InteractionPromptWidget:_Render()
	local spec = self:_ModeSpec()
	local chip, caption, track = self._chip, self._caption, self._track
	if not (chip and caption and track) then
		return
	end
	chip.Text = spec.text
	chip.Size = UDim2.fromOffset(spec.width, CHIP)
	chip.TextSize = spec.text == "TAP" and 20 or 24
	chip.BackgroundColor3 = (self.Theme.Arcade :: any)[spec.fill]
	-- A gamepad face button is round; a key cap is not (doc §4.2: pills are
	-- the arcade's one sanctioned round exception).
	self._chipCorner.CornerRadius = UDim.new(0, UIChrome.Radius("Arcade", spec.pill and "Pill" or nil))
	caption.Text = self._label
	track.Visible = self._hold > 0
end

function InteractionPromptWidget:_Style(theme: Types.UITheme)
	if self._chip then
		self._chip.FontFace = theme.Fonts.Button
		self._chip.TextColor3 = theme.Colors.TextPrimary
		UIChrome.TextOutline(self._chip)
	end
	if self._chipStroke then
		self._chipStroke.Color = theme.Colors.Stroke
	end
	if self._caption then
		self._caption.FontFace = theme.Fonts.Button
		self._caption.TextColor3 = theme.Colors.TextPrimary
		UIChrome.TextOutline(self._caption)
	end
	if self._track then
		self._track.BackgroundColor3 = theme.Arcade.RulerTrack
	end
	if self._trackStroke then
		self._trackStroke.Color = theme.Colors.Stroke
	end
	if self._fill then
		self._fill.BackgroundColor3 = theme.Arcade.SunburstGold
	end
	self:_Render()
end

return InteractionPromptWidget
