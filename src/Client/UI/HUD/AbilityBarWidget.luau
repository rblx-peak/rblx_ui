--!strict
-- Ability bar (HUD widget): a row of five slots, each an arcade icon box with
-- a keybind chip, a cooldown readout, charge pips and a cooldown wipe — plus a
-- global-cooldown dim across the whole row.
--
-- WHY A VERTICAL WIPE AND NOT A RADIAL SWEEP: a true radial cooldown needs an
-- ImageLabel driven by a shader-ish alpha mask (a 360° sweep texture) — Roblox
-- has no arc primitive and no partial-fill on a UICorner, so every real radial
-- ships as an uploaded asset. The archive owns all artwork (IconArchive) and
-- there is no sweep asset in it, so faking one with rotated half-frames would
-- be exactly the kind of hand-rolled chrome this system forbids. A vertical
-- wipe — a dark cap over the icon whose height IS the remaining fraction —
-- reads the same information, costs one Frame, and stays inside the policy.
--
-- Every tap answers (doc §11.1): pressing a cooling slot still plays the full
-- press juice and flashes the slot red, it just doesn't fire.

local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local HUDWidgetBase = require(script.Parent.HUDWidgetBase)
local GPHUDStyle = require(script.Parent.GPHUDStyle)

local AbilityBarWidget = setmetatable({}, { __index = HUDWidgetBase })
AbilityBarWidget.__index = AbilityBarWidget

local SLOT_GAP = 10
local GLOBAL_COOLDOWN = 0.6
local BLOCK_FLASH = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DIM_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local WIPE_TRANSPARENCY = 0.42
local GCD_TRANSPARENCY = 0.55

-- Demo loadout: renders a believable, already-in-play bar with no backend —
-- one ability mid-cooldown and a charge ability with a pip spent.
local DEMO_ABILITIES = {
	{ id = "slash", name = "Slash", icon = "sword", key = "Q", cooldown = 6 },
	{ id = "guard", name = "Guard", icon = "shield", key = "E", cooldown = 12 },
	{ id = "flame", name = "Flame", icon = "fire", key = "R", cooldown = 20, remaining = 13.4 },
	{ id = "dash", name = "Dash", icon = "bolt", key = "F", cooldown = 8 },
	{ id = "brew", name = "Brew", icon = "potion", key = "C", cooldown = 25, maxCharges = 3, charges = 2, remaining = 9 },
}

function AbilityBarWidget.new()
	local self = HUDWidgetBase.new("abilities", "AbilityBarWidget")
	self._slots = {} :: { any }
	self._gcd = 0
	return setmetatable(self, AbilityBarWidget)
end

function AbilityBarWidget:_Build(props: HUDWidgetBase.Props)
	local holder = UIStyler.Frame("Slots")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = self.Root
	self._holder = holder

	-- Global-cooldown dim: one overlay over the whole row rather than five
	-- per-slot dims, because the GCD is a property of the ROW, not the slot.
	local dim = UIStyler.Frame("GlobalCooldown")
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 20
	dim.Visible = false
	dim.Parent = self.Root
	self._dim = dim

	self:_SetAbilities(props.abilities or DEMO_ABILITIES)

	-- Keyboard/gamepad presses go through the same path as a click so the
	-- juice, the block answer and the cooldown all behave identically.
	self:_Connect(UserInputService.InputBegan, function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		local pressed = input.KeyCode.Name
		for index, slot in self._slots do
			if slot.key ~= "" and string.upper(slot.key) == string.upper(pressed) then
				self:Activate(index)
				break
			end
		end
	end)

	self:_RenderStep(function(dt: number)
		self:_Step(dt)
	end)
end

-- ---- structure ---------------------------------------------------------

function AbilityBarWidget:_SetAbilities(abilities: { any })
	for _, slot in self._slots do
		-- The tile's shadow handle goes back to the budget before the instance
		-- does; a loadout swap otherwise strands one per slot, permanently.
		GPHUDStyle.Drop(slot.button, self._shadows)
		slot.button:Destroy()
	end
	table.clear(self._slots)

	local count = math.max(#abilities, 1)
	local width = self.Root.Size.X.Offset
	local height = self.Root.Size.Y.Offset
	local size = math.floor((width - SLOT_GAP * (count - 1)) / count)
	-- Slots hang off the BOTTOM of the widget box: the spare headroom above is
	-- where the press/pulse scale expands into without touching the bar below.
	local top = math.max(height - size, 0)

	for index, ability in abilities do
		local slot = self:_BuildSlot(index, ability, size, (index - 1) * (size + SLOT_GAP), top)
		table.insert(self._slots, slot)
	end
	if self.Theme then
		self:_Style(self.Theme)
	end
end

function AbilityBarWidget:_BuildSlot(index: number, ability: any, size: number, x: number, y: number)
	local theme = self.Theme

	-- Whole-cell hit target (doc §11.6): the button IS the slot; everything
	-- inside it is non-interactive.
	local button = Instance.new("TextButton")
	button.Name = "Slot" .. index
	button.Text = ""
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = theme.Arcade.NearBlack2
	button.Size = UDim2.fromOffset(size, size)
	button.Position = UDim2.fromOffset(x, y)
	UIChrome.Corner("Arcade").Parent = button
	local stroke = UIChrome.Stroke(theme, "Arcade", "Panel")
	stroke.Parent = button
	button.Parent = self._holder

	-- Hover/press motion is a UIScale on an inner surface — never a Size
	-- change, which would reflow the row.
	local surface = UIStyler.Frame("Surface")
	surface.BackgroundTransparency = 1
	surface.Size = UDim2.fromScale(1, 1)
	surface.Parent = button

	local icon = IconArchive.Image(surface, ability.icon or "star", math.floor(size * 0.52))
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 2

	local wipe = UIStyler.Frame("CooldownWipe")
	wipe.BackgroundColor3 = Color3.new(0, 0, 0)
	wipe.BackgroundTransparency = WIPE_TRANSPARENCY
	wipe.AnchorPoint = Vector2.new(0, 0)
	wipe.Position = UDim2.fromScale(0, 0)
	wipe.Size = UDim2.fromScale(1, 0)
	wipe.ZIndex = 3
	wipe.Visible = false
	wipe.Parent = surface

	local remainingText = UIChrome.Text("Remaining", 24, Color3.new(1, 1, 1))
	remainingText.Size = UDim2.fromScale(1, 1)
	remainingText.ZIndex = 4
	remainingText.Visible = false
	remainingText.Parent = surface

	-- Keybind chip, top-left, on the light chrome weight (a 3px border on a
	-- 26px chip would be all edge).
	local chip = UIStyler.Frame("KeyChip")
	chip.BackgroundColor3 = theme.Arcade.Panel
	chip.Position = UDim2.fromOffset(3, 3)
	chip.Size = UDim2.fromOffset(26, 19)
	chip.ZIndex = 5
	UIChrome.Corner("Arcade").Parent = chip
	local chipStroke = UIChrome.Stroke(theme, "Arcade", "Wheel")
	chipStroke.Parent = chip
	chip.Parent = surface

	local chipText = UIChrome.Text("Key", 13, Color3.new(1, 1, 1))
	chipText.Text = string.upper(ability.key or "")
	chipText.Size = UDim2.fromScale(1, 1)
	chipText.ZIndex = 6
	chipText.Parent = chip

	-- Charge pips, bottom-centre: gold = a charge in hand, near-black = spent.
	local maxCharges = math.max(ability.maxCharges or 1, 1)
	local pips = {}
	if maxCharges > 1 then
		local pipRow = UIStyler.Frame("Pips")
		pipRow.BackgroundTransparency = 1
		pipRow.AnchorPoint = Vector2.new(0.5, 1)
		pipRow.Position = UDim2.new(0.5, 0, 1, -4)
		pipRow.Size = UDim2.fromOffset(maxCharges * 12, 8)
		pipRow.ZIndex = 5
		UIStyler.ListLayout({
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 4),
		}).Parent = pipRow
		pipRow.Parent = surface
		for p = 1, maxCharges do
			local pip = UIStyler.Frame("Pip")
			pip.Size = UDim2.fromOffset(8, 8)
			pip.LayoutOrder = p
			pip.ZIndex = 6
			UIChrome.Corner("Arcade").Parent = pip
			pip.Parent = pipRow
			table.insert(pips, pip)
		end
	end

	local slot = {
		index = index,
		id = ability.id or ("slot" .. index),
		name = ability.name or ability.id or "",
		key = ability.key or "",
		cooldown = ability.cooldown or 0,
		remaining = ability.remaining or 0,
		maxCharges = maxCharges,
		charges = math.clamp(ability.charges or maxCharges, 0, maxCharges),
		button = button,
		stroke = stroke,
		chip = chip,
		chipStroke = chipStroke,
		chipText = chipText,
		surface = surface,
		icon = icon,
		wipe = wipe,
		remainingText = remainingText,
		pips = pips,
	}

	button.Activated:Connect(function()
		self:Activate(index)
	end)
	-- animate() is applied LAST, after the final colours: it snapshots the
	-- rest colour (doc §5.1 contract). The scale target is the inner surface.
	UIChrome.Animate(theme, button, surface)

	self:_RenderSlot(slot)
	return slot
end

-- ---- state -------------------------------------------------------------

-- data: { abilities = { {id, name, icon, key, cooldown, remaining, charges,
--          maxCharges} }, globalCooldown = seconds }
function AbilityBarWidget:Update(data: any)
	if type(data) ~= "table" then
		return
	end
	if data.abilities then
		if self:_SameLoadout(data.abilities) then
			for index, ability in data.abilities do
				local slot = self._slots[index]
				if slot then
					slot.cooldown = ability.cooldown or slot.cooldown
					slot.remaining = ability.remaining or 0
					slot.charges = math.clamp(ability.charges or slot.charges, 0, slot.maxCharges)
					self:_RenderSlot(slot)
				end
			end
		else
			self:_SetAbilities(data.abilities)
		end
	end
	if data.globalCooldown then
		self._gcd = data.globalCooldown
	end
end

function AbilityBarWidget:_SameLoadout(abilities: { any }): boolean
	if #abilities ~= #self._slots then
		return false
	end
	for index, ability in abilities do
		local id = ability.id or ("slot" .. index)
		if self._slots[index].id ~= id then
			return false
		end
	end
	return true
end

function AbilityBarWidget:IsReady(index: number): boolean
	local slot = self._slots[index]
	if not slot then
		return false
	end
	if self._gcd > 0 or slot.charges <= 0 then
		return false
	end
	-- A single-charge ability is gated by its cooldown; a multi-charge one is
	-- gated by the pips (it keeps rolling its cooldown while charges remain).
	return slot.maxCharges > 1 or slot.remaining <= 0
end

function AbilityBarWidget:Activate(index: number)
	local slot = self._slots[index]
	if not slot then
		return
	end
	local ready = self:IsReady(index)
	if not ready then
		-- Blocked taps still answer: the press juice already played on the
		-- button, and the slot flashes red so the refusal is legible.
		self:_FlashBlocked(slot)
		local onBlocked = self.Props.onBlocked
		if onBlocked then
			onBlocked(index, slot.id, slot.name)
		end
		return
	end

	slot.charges -= 1
	if slot.remaining <= 0 and slot.cooldown > 0 then
		slot.remaining = slot.cooldown
	end
	self._gcd = self.Props.globalCooldown or GLOBAL_COOLDOWN
	self:_Pulse(slot.surface)
	self:_RenderSlot(slot)

	local onActivate = self.Props.onActivate
	if onActivate then
		onActivate(index, slot.id, slot.name)
	end
end

function AbilityBarWidget:_FlashBlocked(slot: any)
	slot.stroke.Color = self.Theme.Arcade.Red
	self:_Tween(slot.stroke, BLOCK_FLASH, { Color = self.Theme.Colors.Stroke })
end

-- ---- per-frame ---------------------------------------------------------

function AbilityBarWidget:_Step(dt: number)
	if self._gcd > 0 then
		self._gcd = math.max(self._gcd - dt, 0)
		local dim = self._dim
		if dim then
			dim.Visible = true
			dim.BackgroundTransparency = GCD_TRANSPARENCY
			if self._gcd <= 0 then
				local fade = self:_Tween(dim, DIM_TWEEN, { BackgroundTransparency = 1 })
				fade.Completed:Once(function()
					if self._gcd <= 0 and dim.Parent then
						dim.Visible = false
					end
				end)
			end
		end
	end

	for _, slot in self._slots do
		if slot.remaining > 0 then
			slot.remaining = math.max(slot.remaining - dt, 0)
			if slot.remaining <= 0 then
				-- A charge ability rolls straight into the next charge's
				-- cooldown until its magazine is full again.
				slot.charges = math.min(slot.charges + 1, slot.maxCharges)
				if slot.charges < slot.maxCharges and slot.cooldown > 0 then
					slot.remaining = slot.cooldown
				end
				self:_Pulse(slot.surface)
			end
			self:_RenderSlot(slot)
		end
	end
end

function AbilityBarWidget:_RenderSlot(slot: any)
	local cooling = slot.remaining > 0
	local fraction = (slot.cooldown > 0) and math.clamp(slot.remaining / slot.cooldown, 0, 1) or 0
	slot.wipe.Visible = cooling
	slot.wipe.Size = UDim2.fromScale(1, fraction)
	slot.remainingText.Visible = cooling
	if cooling then
		slot.remainingText.Text = slot.remaining >= 10
			and string.format("%d", math.ceil(slot.remaining))
			or string.format("%.1f", slot.remaining)
	end
	-- Out of charges reads as a dead slot: the icon dims in place, never
	-- disappears (doc §11.2 — controls are dimmed, never removed).
	local spent = slot.charges <= 0
	-- IconArchive returns an ImageLabel OR a glyph TextLabel (a pending
	-- upload must never leave a hole), so dim whichever one we got.
	if slot.icon:IsA("ImageLabel") then
		slot.icon.ImageTransparency = spent and 0.6 or 0
	elseif slot.icon:IsA("TextLabel") then
		slot.icon.TextTransparency = spent and 0.6 or 0
	end
	for p, pip in slot.pips do
		pip.BackgroundColor3 = (p <= slot.charges) and self.Theme.Arcade.Gold or self.Theme.Arcade.NearBlack
	end
end

function AbilityBarWidget:_Style(theme: Types.UITheme)
	-- GIRLY POP: five glazed tiles on a shelf. Petal corners ALTERNATE across
	-- the row by slot index so the bar reads hand-arranged rather than stamped
	-- (pack law 4), each tile translucent over the world with a soft hue shadow.
	-- The two pure blacks this widget hard-codes — the cooldown wipe and the
	-- global-cooldown dim — become the pack's warm plum scrim, because law 1
	-- bans pure black even when it is only being used as shade.
	-- Every slot keeps its keybind chip, its cooldown readout to the same tenth
	-- of a second, its charge pips and its spent-state dimming.
	local gp = GPHUDStyle.Active(theme)
	local shade = if gp then theme.Colors.Overlay else Color3.new(0, 0, 0)
	if self._dim then
		self._dim.BackgroundColor3 = shade
	end
	for index, slot in self._slots do
		slot.button.BackgroundColor3 = theme.Arcade.NearBlack2
		slot.stroke.Color = theme.Colors.Stroke
		slot.chip.BackgroundColor3 = theme.Arcade.Panel
		slot.chipStroke.Color = theme.Colors.Stroke
		slot.chipText.FontFace = theme.Fonts.Button
		slot.chipText.TextColor3 = theme.Colors.TextPrimary
		UIChrome.TextOutline(slot.chipText)
		slot.remainingText.FontFace = theme.Fonts.Numeric
		slot.remainingText.TextColor3 = theme.Colors.TextPrimary
		UIChrome.TextOutline(slot.remainingText)

		slot.wipe.BackgroundColor3 = shade
		GPHUDStyle.Surface(theme, slot.button, {
			transparency = GPHUDStyle.Chip,
			petal = index,
			stroke = true,
			strokeIntent = "Panel",
			strokeKeepColor = true,
			shadow = "sm",
			sink = self._shadows,
		})
		-- The wipe is a full-bleed cap over the tile, so it takes the tile's OWN
		-- petal, not a uniform radius: nothing here clips (the slot is a bare
		-- button), so a 16px square-ish cap would hang past a 24px petal arc and
		-- show a dark ear on every other slot. Same index = same silhouette.
		GPHUDStyle.Surface(theme, slot.wipe, {
			keepTransparency = true,
			petal = index,
		})
		-- The keybind chip is authored at (3,3) because the arcade tile has 90°
		-- corners. A 24px petal arc passes straight through that point, so under
		-- this pack the chip steps inside the curve — the tile pays for its own
		-- shape rather than the chip hanging off the corner. Nothing shrinks.
		slot.chip.Position = if gp then UDim2.fromOffset(9, 7) else UDim2.fromOffset(3, 3)
		GPHUDStyle.Surface(theme, slot.chip, {
			transparency = GPHUDStyle.Chip,
			radius = theme.Radii.Small,
			cornerIntent = "Panel",
			stroke = true,
			strokeIntent = "Wheel",
			strokeKeepColor = true,
		})
		for _, pip in slot.pips do
			GPHUDStyle.Surface(theme, pip, { keepTransparency = true, radius = theme.Radii.Pill })
		end
		GPHUDStyle.Halo(theme, slot.chipText)
		GPHUDStyle.Halo(theme, slot.remainingText)
		self:_RenderSlot(slot)
	end
end

return AbilityBarWidget
