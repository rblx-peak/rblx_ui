--!strict
-- RADIAL WHEEL — the generic quick-pick ring (manifest: Overlay layer, not
-- exclusive). ONE screen serves emotes, weapon swaps, pings — the data
-- decides: Show(data) = { title, entries = {{id, label, icon}} (4–8),
-- onPick = function(idOrNil), held = boolean? }.
--
-- Roblox GUI has no triangle primitive, so each wedge is a FAN of thin
-- rotated bars around the hub (SpinWheelScreen's technique): bars overlap
-- solid at the centre and splay to full sector width at the rim. Each wedge
-- lives in its own wheel-sized container whose UIScale pops it 1.08 about
-- the wheel centre on hover — an outward swell, with the gold selection ring
-- on the wedge's icon chip (§4.3 selection-is-a-ring). The hub echoes the
-- hovered label big.
--
-- Input: hover is resolved every frame from the mouse's ANGLE around the
-- wheel centre (dead inside the hub), so both gestures work — point + click,
-- or (held = true, the hold-a-key-to-open idiom) sweep outward and RELEASE
-- to pick. Esc / right-click cancels with onPick(nil). Pick pulses the
-- chosen wedge, then hard-hides (§5). The hover loop gates on
-- UIChrome.IsOnScreen and every connection drops in _OnHide (§5.4).
--
-- Fixed px at the 1650×1020 baseline (UIScreenBase attaches the UIScale).

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPControlKit = require(script.Parent.Parent.Framework.GPControlKit)
local UIScreenBase = require(script.Parent.UIScreenBase)

export type WheelEntry = {
	id: string,
	label: string,
	icon: string?,
}

local WHITE = Color3.new(1, 1, 1)

local WHEEL = 540 -- ring diameter
local C = WHEEL / 2
local HUB = 170 -- centre hub diameter (also the hover dead-zone)
local RADIUS = 252 -- wedge bars run from the hub out to this radius
local BARS = 11 -- fan bars per wedge (the SpinWheel count)
local FAN_COVERAGE = 0.91 -- fraction of the wedge the fan spans
local CHIP = 74 -- wedge icon chip diameter
local RING = 92 -- gold hover ring diameter around the chip
local HOVER_SCALE = 1.08
local MAX_ENTRIES = 8
local PICK_DELAY = 0.18 -- pulse-then-hide beat

type Wedge = {
	id: string,
	label: string,
	container: Frame,
	scale: UIScale,
	ring: Frame,
}

-- The demo payload: an 8-emote wheel, so the screen is exercisable with no
-- backend at all.
local DEMO: { entries: { WheelEntry }, title: string } = {
	title = "EMOTES",
	entries = {
		{ id = "wave", label = "WAVE", icon = "player" },
		{ id = "cheer", label = "CHEER", icon = "star" },
		{ id = "love", label = "LOVE", icon = "heart" },
		{ id = "hype", label = "HYPE", icon = "fire" },
		{ id = "dance", label = "DANCE", icon = "bolt" },
		{ id = "gg", label = "GG", icon = "trophy" },
		{ id = "taunt", label = "TAUNT", icon = "skull" },
		{ id = "random", label = "RANDOM", icon = "dice" },
	},
}

-- GP (Girly Pop): the wheel floats over LIVE GAMEPLAY, not over a cream card,
-- so every piece of copy gets its own pastel plate to sit on — ink on a warm
-- scrim over arbitrary world colour would be a contrast lottery.
local GP_PLATE_H = 52
local GP_HINT_H = 40
-- How far each wedge wash is pulled toward the cream paper. Full-strength rose
-- and matcha across a 540px fan is a poster; half-strength is a pinwheel.
local GP_WASH = 0.5

-- The wheel's copy is authored in arcade caps ("EMOTES", "PICK ONE"). Pack law
-- 5 forbids all-caps copy, so GP title-cases on the way to the screen.
local function gpTitle(text: string): string
	return (string.gsub(string.lower(text), "(%a[%w']*)", function(word: string)
		return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
	end))
end

local RadialWheelScreen = setmetatable({}, { __index = UIScreenBase })
RadialWheelScreen.__index = RadialWheelScreen

function RadialWheelScreen.new()
	local self = UIScreenBase.new("RadialWheelScreen", 45)
	self._entries = DEMO.entries :: { WheelEntry }
	self._title = DEMO.title
	self._onPick = nil :: ((string?) -> ())?
	self._held = false
	self._wedges = {} :: { Wedge }
	self._hovered = nil :: number?
	self._picking = false
	self._gen = 0
	self._conns = {} :: { RBXScriptConnection }
	-- GP branch state: the flag _Render / _SetHovered / _OnShow read, plus the
	-- page and fan shadow sinks the budget is released from.
	self._gp = false
	self._gpShadows = nil :: { any }?
	self._gpWedgeShadows = nil :: { any }?
	return setmetatable(self, RadialWheelScreen)
end

function RadialWheelScreen:_Ingest(data: any)
	if type(data) ~= "table" then
		return
	end
	if type(data.entries) == "table" and #data.entries > 0 then
		-- The ring reads well at 4–8 wedges; extra entries are dropped rather
		-- than crushed into slivers.
		local entries = {}
		for index, entry in data.entries do
			if index > MAX_ENTRIES then
				break
			end
			table.insert(entries, entry)
		end
		self._entries = entries
	end
	if type(data.title) == "string" then
		self._title = data.title
	end
	if type(data.onPick) == "function" then
		self._onPick = data.onPick
	end
	if data.held ~= nil then
		self._held = data.held == true
	end
end

-- ========================================================================
-- Build
-- ========================================================================

-- ========================================================================
-- GIRLY POP
-- ========================================================================
-- The same ring at the same radius, the same fan technique, the same 4–8
-- wedges and the same hub echo — re-cut as a pastel pinwheel. Rose and matcha
-- alternate as the pack's twin colour masses (butter closes an odd count so
-- first and last never match), each wedge chip is a cream pill casting a shadow
-- of the wedge's own hue, and the selection ring goes rose instead of gold.
--
-- Everything the arcade wheel prints prints here: the title above the ring, the
-- title again inside the hub, the hovered label echoed big, the per-wedge
-- captions, and the gesture hint underneath.

function RadialWheelScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	local root = self.Root
	self._gpShadows = {}
	self._gpWedgeShadows = {}

	-- Warm plum scrim, never black: the world stays readable behind it.
	local dim = UIStyler.Frame("Dim")
	dim.BackgroundColor3 = theme.Colors.Overlay
	dim.BackgroundTransparency = 0.5
	dim.ZIndex = 1
	dim.Parent = root

	-- The title rides its OWN cream plate. Over live gameplay there is no
	-- guaranteed backdrop, and ink floating on a scrim is a contrast lottery.
	local titlePlate = UIStyler.Frame("TitlePlate")
	titlePlate.BackgroundColor3 = theme.Colors.Background
	titlePlate.AnchorPoint = Vector2.new(0.5, 1)
	titlePlate.Position = UDim2.new(0.5, 0, 0.5, -(C + 24))
	titlePlate.Size = UDim2.fromOffset(420, GP_PLATE_H)
	titlePlate.ZIndex = 5
	titlePlate.Parent = root
	GPLayoutKit.CornerSet(theme, titlePlate, "Petal")
	GPLayoutKit.SoftStroke(theme, titlePlate, theme.Colors.Primary)
	GPLayoutKit.Shadow(theme, titlePlate, "md", self._gpShadows, theme.Colors.Primary)

	local title = GPLayoutKit.Text(theme, 30, theme.Colors.TextPrimary, "Title")
	title.Text = gpTitle(self._title)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Size = UDim2.new(1, -24, 1, 0)
	title.Position = UDim2.fromOffset(12, 0)
	title.ZIndex = 6
	title.Parent = titlePlate
	self._titleLabel = title

	local wheel = UIStyler.Frame("Wheel")
	wheel.BackgroundTransparency = 1
	wheel.AnchorPoint = Vector2.new(0.5, 0.5)
	wheel.Position = UDim2.fromScale(0.5, 0.5)
	wheel.Size = UDim2.fromOffset(WHEEL, WHEEL)
	wheel.ZIndex = 5
	wheel.Parent = root
	self._wheel = wheel

	-- Wedges rebuild per payload into this layer; the hub above is static.
	local face = UIStyler.Frame("Face")
	face.BackgroundTransparency = 1
	face.ZIndex = 6
	face.Parent = wheel
	self._face = face

	local hubFill = theme.Colors.Background
	local hub = UIStyler.Frame("Hub")
	hub.BackgroundColor3 = hubFill
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(HUB, HUB)
	hub.ZIndex = 10
	hub.Parent = wheel
	UIStyler.Corner(theme.Radii.Pill).Parent = hub
	GPLayoutKit.SoftStroke(theme, hub, theme.Colors.Primary)
	GPLayoutKit.Shadow(theme, hub, "md", self._gpShadows, theme.Colors.Primary)

	local hubTitle = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "HubTitle")
	hubTitle.Text = gpTitle(self._title)
	hubTitle.TextTruncate = Enum.TextTruncate.AtEnd
	hubTitle.Position = UDim2.fromOffset(12, 34)
	hubTitle.Size = UDim2.new(1, -24, 0, 20)
	hubTitle.ZIndex = 11
	hubTitle.Parent = hub
	self._hubTitle = hubTitle

	local hubLabel = GPLayoutKit.Text(theme, 24, theme.Colors.TextPrimary, "HubLabel")
	hubLabel.Text = "Pick one"
	hubLabel.Position = UDim2.fromOffset(12, 58)
	hubLabel.Size = UDim2.new(1, -24, 0, 56)
	hubLabel.ZIndex = 11
	-- Long labels shrink under a cap; TextScaled LAST (engine landmine).
	hubLabel.TextWrapped = true
	UIStyler.TextSizeConstraint(24, 12).Parent = hubLabel
	hubLabel.TextScaled = true
	hubLabel.Parent = hub
	self._hubLabel = hubLabel

	local hintPlate = UIStyler.Frame("HintPlate")
	hintPlate.BackgroundColor3 = theme.Colors.Surface
	hintPlate.AnchorPoint = Vector2.new(0.5, 0)
	hintPlate.Position = UDim2.new(0.5, 0, 0.5, C + 20)
	hintPlate.Size = UDim2.fromOffset(720, GP_HINT_H)
	hintPlate.ZIndex = 5
	hintPlate.Parent = root
	GPLayoutKit.CornerSet(theme, hintPlate, "PetalMirror")
	GPLayoutKit.SoftStroke(theme, hintPlate, theme.Colors.Surface)
	GPLayoutKit.Shadow(theme, hintPlate, "sm", self._gpShadows, theme.Colors.Surface)

	local hint = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Hint")
	hint.Text = ""
	hint.Size = UDim2.new(1, -24, 1, 0)
	hint.Position = UDim2.fromOffset(12, 0)
	hint.ZIndex = 6
	hint.Parent = hintPlate
	self._hint = hint

	self:_Render()
end

function RadialWheelScreen:_RenderGP()
	local theme = self:GetTheme()
	table.clear(self._wedges)
	self._hovered = nil
	self._face:ClearAllChildren()
	-- The fan is rebuilt per payload; hand the old shadow handles back first.
	GPLayoutKit.ReleaseShadows(self._gpWedgeShadows)
	self._gpWedgeShadows = self._gpWedgeShadows or {}
	local sink = self._gpWedgeShadows

	local entries = self._entries :: { WheelEntry }
	local n = #entries
	if n == 0 then
		return
	end

	local paper = theme.Colors.Background
	-- Rose and matcha as the twin masses, washed halfway toward the paper;
	-- butter closes an odd count so the first and last wedge never match.
	local washes = {
		theme.Colors.Primary:Lerp(paper, GP_WASH),
		theme.Colors.Secondary:Lerp(paper, GP_WASH),
	}
	local oddCloser = theme.Colors.Accent:Lerp(paper, GP_WASH)

	local segAngle = 360 / n
	local step = segAngle * FAN_COVERAGE / (BARS - 1)
	-- Bar width = the arc one fan step subtends at the rim (+3px overlap), so
	-- the fan closes into a solid wedge at ANY entry count (4–8).
	local barW = math.ceil(RADIUS * math.rad(step)) + 3

	for i, entry in entries do
		local baseAngle = (i - 1) * segAngle

		local container = UIStyler.Frame("Wedge" .. i)
		container.BackgroundTransparency = 1
		container.AnchorPoint = Vector2.new(0.5, 0.5)
		container.Position = UDim2.fromScale(0.5, 0.5)
		container.Size = UDim2.fromOffset(WHEEL, WHEEL)
		container.ZIndex = 6
		container.Parent = self._face
		local scale = Instance.new("UIScale")
		scale.Parent = container

		local fill = washes[(i - 1) % 2 + 1]
		if i == n and n % 2 == 1 then
			fill = oddCloser
		end

		for k = 1, BARS do
			local angle = baseAngle + (k - (BARS + 1) / 2) * step
			local rad = math.rad(angle)
			local bar = UIStyler.Frame("Bar")
			bar.BackgroundColor3 = fill
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromOffset(
				C + math.sin(rad) * RADIUS / 2,
				C - math.cos(rad) * RADIUS / 2
			)
			bar.Size = UDim2.fromOffset(barW, RADIUS)
			bar.Rotation = angle
			bar.ZIndex = 6
			bar.Parent = container
		end

		local sector = UIStyler.Frame("Sector")
		sector.BackgroundTransparency = 1
		sector.AnchorPoint = Vector2.new(0.5, 0.5)
		sector.Position = UDim2.fromScale(0.5, 0.5)
		sector.Size = UDim2.fromOffset(WHEEL, WHEEL)
		sector.Rotation = baseAngle
		sector.ZIndex = 8
		sector.Parent = container

		-- Selection is a RING (§4.3) — rose here, not gold.
		local ring = UIStyler.Frame("HoverRing")
		ring.BackgroundTransparency = 1
		ring.AnchorPoint = Vector2.new(0.5, 0)
		ring.Position = UDim2.new(0.5, 0, 0, 30 - (RING - CHIP) // 2)
		ring.Size = UDim2.fromOffset(RING, RING)
		ring.Visible = false
		ring.ZIndex = 8
		ring.Parent = sector
		UIStyler.Corner(theme.Radii.Pill).Parent = ring
		local ringStroke = UIStyler.Stroke(GPLayoutKit.Deepen(theme, theme.Semantic.Selection, 1), 3, 0)
		ringStroke.LineJoinMode = Enum.LineJoinMode.Round
		ringStroke.Parent = ring

		local chipFill = theme.Colors.Background
		local chip = UIStyler.Frame("Chip")
		chip.BackgroundColor3 = chipFill
		chip.AnchorPoint = Vector2.new(0.5, 0)
		chip.Position = UDim2.new(0.5, 0, 0, 30)
		chip.Size = UDim2.fromOffset(CHIP, CHIP)
		chip.ZIndex = 9
		chip.Parent = sector
		UIStyler.Corner(theme.Radii.Pill).Parent = chip
		GPLayoutKit.SoftStroke(theme, chip, fill)
		-- Hue-matched to the WEDGE, not the chip: a rose wedge's chip casts rose.
		GPLayoutKit.Shadow(theme, chip, "sm", sink, fill)

		-- Through the kit wrapper: IconArchive's GLYPH FALLBACK is born pure
		-- white with a pure black outline, which pack law 1 forbids.
		local icon = GPControlKit.Icon(theme, chip, entry.icon or "sparkle", 46)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = 10

		local label = GPLayoutKit.Text(theme, 18, theme.Colors.TextPrimary, "Label")
		label.Text = gpTitle(entry.label)
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, 112)
		label.Size = UDim2.fromOffset(130, 26)
		label.ZIndex = 9
		label.TextWrapped = true
		UIStyler.TextSizeConstraint(18, 10).Parent = label
		label.TextScaled = true
		label.Parent = sector

		table.insert(self._wedges, {
			id = entry.id,
			-- Title-cased HERE so _SetHovered and _Pick, which echo this string
			-- into the hub, stay untouched.
			label = gpTitle(entry.label),
			container = container,
			scale = scale,
			ring = ring,
		})
	end
end

function RadialWheelScreen:_BuildContent()
	-- GP layout language: the pastel pinwheel.
	if self:LayoutKit() == "GP" then
		self._gp = true
		self:_BuildGPLayout()
		return
	end
	self._gp = false

	local theme = self:GetTheme()
	local root = self.Root

	-- Light scrim: this is an overlay over live gameplay, not a modal.
	local dim = UIStyler.Frame("Dim")
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.6
	dim.ZIndex = 1
	dim.Parent = root

	local title = UIChrome.Text("Title", 34, theme.Arcade.Gold)
	title.Text = self._title
	title.AnchorPoint = Vector2.new(0.5, 1)
	title.Position = UDim2.new(0.5, 0, 0.5, -(C + 28))
	title.Size = UDim2.fromOffset(600, 44)
	title.ZIndex = 5
	title.Parent = root
	self._titleLabel = title

	local wheel = UIStyler.Frame("Wheel")
	wheel.BackgroundTransparency = 1
	wheel.AnchorPoint = Vector2.new(0.5, 0.5)
	wheel.Position = UDim2.fromScale(0.5, 0.5)
	wheel.Size = UDim2.fromOffset(WHEEL, WHEEL)
	wheel.ZIndex = 5
	wheel.Parent = root
	self._wheel = wheel

	-- Wedges rebuild per payload into this layer; the hub above is static.
	local face = UIStyler.Frame("Face")
	face.BackgroundTransparency = 1
	face.ZIndex = 6
	face.Parent = wheel
	self._face = face

	local hub = UIStyler.Frame("Hub")
	hub.BackgroundColor3 = theme.Arcade.NearBlack2
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(HUB, HUB)
	hub.ZIndex = 10
	UIChrome.Corner("Arcade", "Pill").Parent = hub
	UIChrome.Stroke(theme, "Arcade", "Wheel").Parent = hub
	UIChrome.GlassGradient().Parent = hub
	hub.Parent = wheel

	local hubTitle = UIChrome.Text("HubTitle", 15, theme.Arcade.Gold)
	hubTitle.Text = self._title
	hubTitle.TextTruncate = Enum.TextTruncate.AtEnd
	hubTitle.Position = UDim2.fromOffset(12, 34)
	hubTitle.Size = UDim2.new(1, -24, 0, 20)
	hubTitle.ZIndex = 11
	hubTitle.Parent = hub
	self._hubTitle = hubTitle

	local hubLabel = UIChrome.Text("HubLabel", 24, WHITE)
	hubLabel.Text = "PICK ONE"
	hubLabel.Position = UDim2.fromOffset(12, 58)
	hubLabel.Size = UDim2.new(1, -24, 0, 56)
	hubLabel.ZIndex = 11
	-- Long labels shrink under a cap; TextScaled LAST (engine landmine).
	hubLabel.TextWrapped = true
	UIStyler.TextSizeConstraint(24, 12).Parent = hubLabel
	hubLabel.TextScaled = true
	hubLabel.Parent = hub
	self._hubLabel = hubLabel

	local hint = UIChrome.BodyText("Hint", 15, theme.Colors.TextSecondary)
	hint.Text = ""
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0.5, C + 24)
	hint.Size = UDim2.fromOffset(700, 22)
	hint.ZIndex = 5
	hint.Parent = root
	self._hint = hint

	self:_Render()
end

function RadialWheelScreen:_Render()
	-- Reached from _OnShow and Update as well as the build, so it branches here.
	if self._gp then
		self:_RenderGP()
		return
	end
	local theme = self:GetTheme()
	table.clear(self._wedges)
	self._hovered = nil
	self._face:ClearAllChildren()

	local entries = self._entries :: { WheelEntry }
	local n = #entries
	if n == 0 then
		return
	end

	local segAngle = 360 / n
	local step = segAngle * FAN_COVERAGE / (BARS - 1)
	-- Bar width = the arc one fan step subtends at the rim (+3px overlap), so
	-- the fan closes into a solid wedge at ANY entry count (4–8).
	local barW = math.ceil(RADIUS * math.rad(step)) + 3

	for i, entry in entries do
		local baseAngle = (i - 1) * segAngle

		-- The wedge container is wheel-sized and centre-anchored, so its
		-- UIScale swells the wedge ABOUT THE WHEEL CENTRE — hover reads as
		-- the wedge popping outward, and layout never reflows.
		local container = UIStyler.Frame("Wedge" .. i)
		container.BackgroundTransparency = 1
		container.AnchorPoint = Vector2.new(0.5, 0.5)
		container.Position = UDim2.fromScale(0.5, 0.5)
		container.Size = UDim2.fromOffset(WHEEL, WHEEL)
		container.ZIndex = 6
		container.Parent = self._face
		local scale = Instance.new("UIScale")
		scale.Parent = container

		-- Alternating slate tones tell neighbouring wedges apart; an odd
		-- count gets one Row-toned closer so first/last never match.
		local fill = if i % 2 == 1 then theme.Arcade.Panel else theme.Arcade.NearBlack2
		if i == n and n % 2 == 1 then
			fill = theme.Arcade.Row
		end

		for k = 1, BARS do
			local angle = baseAngle + (k - (BARS + 1) / 2) * step
			local rad = math.rad(angle)
			local bar = UIStyler.Frame("Bar")
			bar.BackgroundColor3 = fill
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromOffset(
				C + math.sin(rad) * RADIUS / 2,
				C - math.cos(rad) * RADIUS / 2
			)
			bar.Size = UDim2.fromOffset(barW, RADIUS)
			bar.Rotation = angle
			bar.ZIndex = 6
			UIChrome.GlassGradient().Parent = bar
			bar.Parent = container
		end

		-- Icon + label ride a rotated sector over the fan, like the prize
		-- wheel — kept upright-ish relative to their wedge.
		local sector = UIStyler.Frame("Sector")
		sector.BackgroundTransparency = 1
		sector.AnchorPoint = Vector2.new(0.5, 0.5)
		sector.Position = UDim2.fromScale(0.5, 0.5)
		sector.Size = UDim2.fromOffset(WHEEL, WHEEL)
		sector.Rotation = baseAngle
		sector.ZIndex = 8
		sector.Parent = container

		local ring = UIStyler.Frame("HoverRing")
		ring.BackgroundTransparency = 1
		ring.AnchorPoint = Vector2.new(0.5, 0)
		ring.Position = UDim2.new(0.5, 0, 0, 30 - (RING - CHIP) // 2)
		ring.Size = UDim2.fromOffset(RING, RING)
		ring.Visible = false
		ring.ZIndex = 8
		UIChrome.Corner("Arcade", "Pill").Parent = ring
		UIChrome.Stroke(theme, "Arcade", "Selection").Parent = ring
		ring.Parent = sector

		local chip = UIStyler.Frame("Chip")
		chip.BackgroundColor3 = theme.Arcade.NearBlack2
		chip.AnchorPoint = Vector2.new(0.5, 0)
		chip.Position = UDim2.new(0.5, 0, 0, 30)
		chip.Size = UDim2.fromOffset(CHIP, CHIP)
		chip.ZIndex = 9
		UIChrome.Corner("Arcade", "Pill").Parent = chip
		UIChrome.Stroke(theme, "Arcade", "Wheel").Parent = chip
		UIChrome.GlassGradient().Parent = chip
		chip.Parent = sector

		local icon = IconArchive.Image(chip, entry.icon or "sparkle", 46)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = 10

		local label = UIChrome.Text("Label", 18, WHITE)
		label.Text = entry.label
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, 112)
		label.Size = UDim2.fromOffset(130, 26)
		label.ZIndex = 9
		label.TextWrapped = true
		UIStyler.TextSizeConstraint(18, 10).Parent = label
		label.TextScaled = true
		label.Parent = sector

		table.insert(self._wedges, {
			id = entry.id,
			label = entry.label,
			container = container,
			scale = scale,
			ring = ring,
		})
	end
end

-- ========================================================================
-- Hover / input
-- ========================================================================

function RadialWheelScreen:_SetHovered(index: number?)
	if index == self._hovered then
		return
	end
	local motion = self:GetTheme().Motion
	local old = self._hovered and self._wedges[self._hovered :: number]
	if old then
		TweenService:Create(old.scale, motion.HoverOut, { Scale = 1 }):Play()
		old.ring.Visible = false
	end
	self._hovered = index
	local new = index and self._wedges[index :: number]
	if new then
		TweenService:Create(new.scale, motion.HoverIn, { Scale = HOVER_SCALE }):Play()
		new.ring.Visible = true
		self._hubLabel.Text = new.label
	else
		-- The wedge labels are already title-cased at record-build time under
		-- GP; only the resting prompt needs the kit branch.
		self._hubLabel.Text = if self._gp then "Pick one" else "PICK ONE"
	end
end

-- Angle around the wheel centre resolves the wedge; inside the hub is the
-- dead zone. Distance has no outer cap so the held-open "sweep way out and
-- release" gesture still selects.
function RadialWheelScreen:_HoverFromMouse()
	if self._picking then
		return
	end
	local wheel = self._wheel
	if not UIChrome.IsOnScreen(wheel) then
		return
	end
	local n = #self._wedges
	if n == 0 then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	local centre = wheel.AbsolutePosition + wheel.AbsoluteSize / 2
	local offset = mouse - centre
	-- AbsoluteSize already carries the baseline UIScale, so the hub radius
	-- converts through the wheel's real on-screen pixel size.
	local hubRadius = (HUB / 2 + 8) * (wheel.AbsoluteSize.X / WHEEL)
	if offset.Magnitude <= hubRadius then
		self:_SetHovered(nil)
		return
	end
	local segAngle = 360 / n
	local angle = (math.deg(math.atan2(offset.X, -offset.Y)) + segAngle / 2) % 360
	self:_SetHovered(math.floor(angle / segAngle) % n + 1)
end

function RadialWheelScreen:_Connect()
	self:_DropConnections()
	table.insert(self._conns, RunService.RenderStepped:Connect(function()
		self:_HoverFromMouse()
	end))
	-- gameProcessedEvent is deliberately ignored: Esc arrives processed once
	-- anything else claims it, and a cancel gesture must still cancel.
	table.insert(self._conns, UserInputService.InputBegan:Connect(function(input: InputObject)
		if not self:IsVisible() or self._picking then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:_Cancel()
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not self._held then
			if self._hovered then
				self:_Pick(self._hovered :: number)
			end
		end
	end))
	table.insert(self._conns, UserInputService.InputEnded:Connect(function(input: InputObject)
		if not self:IsVisible() or self._picking or not self._held then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- Release-to-pick; releasing over the hub backs out quietly.
			if self._hovered then
				self:_Pick(self._hovered :: number)
			else
				self:_Cancel()
			end
		end
	end))
end

function RadialWheelScreen:_DropConnections()
	for _, conn in self._conns do
		conn:Disconnect()
	end
	table.clear(self._conns)
end

-- ========================================================================
-- Pick / cancel
-- ========================================================================

function RadialWheelScreen:_Pick(index: number)
	local wedge = self._wedges[index]
	if not wedge then
		return
	end
	self._picking = true
	local gen = self._gen
	self._hubLabel.Text = wedge.label
	UIChrome.Pulse(self:GetTheme(), wedge.container)
	self:_PlaySound("Click")
	-- One pulse beat on the chosen wedge, THEN the hard-hide (§5).
	task.delay(PICK_DELAY, function()
		if gen ~= self._gen or not self:IsVisible() then
			return
		end
		local onPick = self._onPick
		self.ScreenController:HideScreen("radialWheel")
		if onPick then
			pcall(onPick, wedge.id)
		end
	end)
end

function RadialWheelScreen:_Cancel()
	local onPick = self._onPick
	self.ScreenController:HideScreen("radialWheel")
	if onPick then
		pcall(onPick, nil)
	end
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function RadialWheelScreen:_OnShow(data: any?)
	self:_Ingest(data)
	self._picking = false
	self._gen += 1
	self._titleLabel.Text = if self._gp then gpTitle(self._title) else self._title
	self._hubTitle.Text = if self._gp then gpTitle(self._title) else self._title
	if self._gp then
		self._hint.Text = if self._held
			then "Sweep out and let go to pick  ·  Esc or right-click backs out"
			else "Hover and click to pick  ·  Esc or right-click backs out"
	else
		self._hint.Text = if self._held
			then "SWEEP OUT AND RELEASE TO PICK  ·  ESC / RIGHT-CLICK CANCELS"
			else "HOVER AND CLICK TO PICK  ·  ESC / RIGHT-CLICK CANCELS"
	end
	self:_Render()
	self:_Connect()
	UIChrome.PopIn(self:GetTheme(), self._wheel)
end

function RadialWheelScreen:_OnHide()
	self._gen += 1
	self._picking = false
	self:_DropConnections()
	self:_SetHovered(nil)
end

function RadialWheelScreen:Update(data: any)
	self:_Ingest(data)
	if self._built then
		self._titleLabel.Text = if self._gp then gpTitle(self._title) else self._title
		self._hubTitle.Text = if self._gp then gpTitle(self._title) else self._title
		self:_Render()
	end
end

-- A style rebuild destroys the Gui but NOT the shadow budget count.
function RadialWheelScreen:_OnTeardown()
	self:_DropConnections()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	GPLayoutKit.ReleaseShadows(self._gpWedgeShadows)
	self._gpShadows = nil
	self._gpWedgeShadows = nil
	table.clear(self._wedges)
	self._hovered = nil
end

function RadialWheelScreen:Destroy()
	self:_DropConnections()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	GPLayoutKit.ReleaseShadows(self._gpWedgeShadows)
	UIScreenBase.Destroy(self)
end

return RadialWheelScreen
