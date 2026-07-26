--!strict
-- Above-character billboard UI, Pottery Clash world-space grammar (doc §9):
-- NO boxes, no backgrounds — the world is the background. Each plate is a
-- BillboardGui at a fixed px offset size carrying stacked transparent
-- TextLabels in FredokaOne with black TEXT strokes (set directly here — these
-- billboards live outside the ScreenGui style enforcers):
--   gold "LV %d" title 22 / white DisplayName 24 / money-green cash 20
-- plus slim 6px boxless rulers (RulerTrack @ 0.35 + colour-token fill, no
-- strokes) for pushed vitals. One controller manages every plate it creates,
-- re-skins them all on a live theme swap, and lets you move a plate to a
-- different overhead location preset at runtime (SetLocation).
--
-- Usage (from a controller/handler with the theme controller):
--   local overhead = UIOverheadController.new(themeController)
--   overhead:Attach(character, { name = "Pip", level = 7 })
--   overhead:SetValues(character, { health = 80, mana = 40, cash = 1250 })
--   overhead:SetLocation(character, "High")   -- move it
--   overhead:Detach(character)
--
-- It intentionally does NOT read Humanoid.Health itself — the game feeds values
-- via SetValues so the same plate works for players, NPCs and mobs alike.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local OverheadConfig = require(script.Parent.Parent.Config.OverheadConfig)

local UIOverheadController = {}
UIOverheadController.__index = UIOverheadController

-- Doc §9 MaxDistance ladder: player nameplates reach 90 studs, AlwaysOnTop.
local MAX_DISTANCE = 90
-- Doc §2 stroke-density ladder: nameplates are the densest tier — a full
-- hard outline at 0 transparency.
local NAME_STROKE_TRANSPARENCY = 0
-- Slim boxless ruler (task spec): 6px track @ 0.35 transparency, no strokes.
local BAR_HEIGHT = 6
local BAR_TRACK_TRANSPARENCY = 0.35
-- Rulers run slimmer than the name line so they read as an underline accent.
local BAR_WIDTH_SCALE = 0.6

export type OverheadController = typeof(setmetatable({} :: {
	_themeController: any,
	_plates: { [Instance]: any },
}, UIOverheadController))

function UIOverheadController.new(themeController: any): OverheadController
	local self = setmetatable({}, UIOverheadController)
	self._themeController = themeController
	self._plates = {}
	-- Live re-skin: repaint every plate when the theme changes. Deferred a
	-- frame (the same pattern as UIScreenBase's deferred rebuild) so the
	-- ClientHandler handler that refreshes UIChrome's active style runs
	-- first — _StylePlate consults that policy through UIChrome.TextOutline.
	if themeController and themeController.ThemeChanged then
		themeController.ThemeChanged:Connect(function()
			task.defer(function()
				self:_RestyleAll()
			end)
		end)
	end
	return self :: any
end

-- Find the part a billboard should adorn (Head for R6/R15, else the root).
local function adornPart(character: Instance): BasePart?
	if character:IsA("Model") then
		return (character:FindFirstChild("Head") :: BasePart?)
			or (character :: Model).PrimaryPart
			or (character:FindFirstChildWhichIsA("BasePart") :: BasePart?)
	end
	return character:IsA("BasePart") and character or nil
end

-- "$1,250" — thousands-separated money text for the green cash line.
local function formatCash(amount: number): string
	local text = tostring(math.floor(amount + 0.5))
	while true do
		local replaced
		text, replaced = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return "$" .. text
end

-- Build (or return the existing) plate for a character.
function UIOverheadController:Attach(character: Instance, info: { name: string?, level: number? }?)
	if self._plates[character] then
		self:_ApplyInfo(character, info)
		return
	end
	local part = adornPart(character)
	if not part then
		return
	end

	local theme: Types.UITheme = self._themeController:GetTheme()

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "OverheadUI"
	billboard.Adornee = part
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MAX_DISTANCE
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	-- Fixed px offset size (doc §9): 300 × (66 nameplate + 7 per ruler) = 300×80.
	local rows = #OverheadConfig.Bars
	local height = (OverheadConfig.ShowNameplate and OverheadConfig.NameHeight or 0)
		+ rows * OverheadConfig.RowHeight
	billboard.Size = UDim2.fromOffset(OverheadConfig.Width, height)
	billboard.StudsOffsetWorldSpace = OverheadConfig.Locations[OverheadConfig.DefaultLocation]

	-- Boxless: a fully transparent stack frame, purely for vertical layout.
	local stack = UIStyler.Frame("Stack")
	stack.BackgroundTransparency = 1
	stack.Size = UDim2.fromScale(1, 1)
	stack.Parent = billboard
	UIStyler.ListLayout({
		Padding = UDim.new(0, 0),
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}).Parent = stack

	local plate = {
		billboard = billboard,
		stack = stack,
		bars = {},
		title = nil :: TextLabel?,
		name = nil :: TextLabel?,
		cash = nil :: TextLabel?,
		location = OverheadConfig.DefaultLocation,
	}

	-- The nameplate stack (doc §9): gold title 22 / white name 24 / green cash 20.
	if OverheadConfig.ShowNameplate then
		local title = UIChrome.Text("Title", 22, theme.Arcade.Gold)
		title.Size = UDim2.new(1, 0, 0, 22)
		title.LayoutOrder = 0
		title.Visible = false -- until a level is supplied via Attach info
		title.Parent = stack
		plate.title = title

		local name = UIChrome.Text("Name", 24, theme.Colors.TextPrimary)
		name.Size = UDim2.new(1, 0, 0, 24)
		name.LayoutOrder = 1
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Parent = stack
		plate.name = name

		local cash = UIChrome.Text("Cash", 20, theme.Arcade.MoneyGreen)
		cash.Size = UDim2.new(1, 0, 0, 20)
		cash.LayoutOrder = 2
		cash.Visible = false -- until SetValues pushes a cash value
		cash.Parent = stack
		plate.cash = cash
	end

	-- Vitals: slim boxless rulers. Each row is a transparent RowHeight budget
	-- holding a 6px track bottom-anchored (so 1px of air sits above the ruler).
	for i, barCfg in OverheadConfig.Bars do
		local row = UIStyler.Frame("bar_" .. barCfg.id)
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, OverheadConfig.RowHeight)
		row.LayoutOrder = 10 + i
		row.Parent = stack

		local track = UIStyler.Frame("Track")
		track.BackgroundTransparency = BAR_TRACK_TRANSPARENCY
		track.AnchorPoint = Vector2.new(0.5, 1)
		track.Position = UDim2.fromScale(0.5, 1)
		track.Size = UDim2.new(BAR_WIDTH_SCALE, 0, 0, BAR_HEIGHT)
		track.Parent = row

		local fill = UIStyler.Frame("Fill")
		fill.Size = UDim2.fromScale(1, 1)
		fill.Parent = track

		plate.bars[barCfg.id] = { row = row, track = track, fill = fill, cfg = barCfg }
	end

	billboard.Parent = part
	self._plates[character] = plate

	self:_ApplyInfo(character, info)
	self:_StylePlate(plate, theme)

	-- Auto-clean when the character goes away.
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			self:Detach(character)
		end
	end)
end

function UIOverheadController:_ApplyInfo(character: Instance, info: { name: string?, level: number? }?)
	local plate = self._plates[character]
	if not plate or not info then
		return
	end
	if plate.name then
		plate.name.Text = info.name or (character :: Instance).Name
	end
	if plate.title then
		if OverheadConfig.ShowLevel and info.level then
			plate.title.Text = string.format("LV %d", info.level)
			plate.title.Visible = true
		else
			plate.title.Visible = false
		end
	end
end

-- Feed values (0..maxValue) for any bar. Missing keys are left unchanged.
-- A `cash` value additionally feeds the money-green nameplate line.
function UIOverheadController:SetValues(character: Instance, values: { [string]: number })
	local plate = self._plates[character]
	if not plate then
		return
	end
	for id, bar in plate.bars do
		local v = values[id]
		if v ~= nil then
			local max = bar.cfg.maxValue or 100
			bar.fill.Size = UDim2.fromScale(math.clamp(v / max, 0, 1), 1)
		end
	end
	local cash = values.cash
	if cash ~= nil and plate.cash then
		plate.cash.Text = formatCash(cash)
		plate.cash.Visible = true
	end
end

-- Move a plate to a different overhead location preset (Above/High/Front/…).
function UIOverheadController:SetLocation(character: Instance, locationId: string)
	local plate = self._plates[character]
	local offset = OverheadConfig.Locations[locationId]
	if not plate or not offset then
		return
	end
	plate.location = locationId
	plate.billboard.StudsOffsetWorldSpace = offset
end

function UIOverheadController:Detach(character: Instance)
	local plate = self._plates[character]
	if not plate then
		return
	end
	plate.billboard:Destroy()
	self._plates[character] = nil
end

function UIOverheadController:_RestyleAll()
	local theme = self._themeController:GetTheme()
	for _, plate in self._plates do
		self:_StylePlate(plate, theme)
	end
end

function UIOverheadController:_StylePlate(plate: any, theme: Types.UITheme)
	-- World grammar: the display font everywhere, the style's text emphasis at
	-- the densest tier (Classic: black TEXT strokes @ 0) — set directly, no
	-- ScreenGui enforcer out here.
	local display = theme.Fonts.Title
	local outlined = UIChrome.ActiveChrome().TextOutline
	local function styleLine(label: TextLabel?, color: Color3)
		if label then
			label.FontFace = display
			label.TextColor3 = color
			UIChrome.TextOutline(label, NAME_STROKE_TRANSPARENCY)
			-- A swap BACK to an outline style must also drop the styled-era
			-- glow stroke: UIChrome.TextOutline leaves it in place, and no
			-- ScreenGui enforcer reaches billboards. Absent under Classic-only
			-- sessions — no-op there.
			if outlined then
				local glow = label:FindFirstChild("TextGlow")
				if glow then
					glow:Destroy()
				end
			end
		end
	end
	styleLine(plate.title, theme.Arcade.Gold)
	styleLine(plate.name, theme.Colors.TextPrimary)
	styleLine(plate.cash, theme.Arcade.MoneyGreen)
	for _, bar in plate.bars do
		bar.track.BackgroundColor3 = theme.Arcade.RulerTrack
		bar.track.BackgroundTransparency = BAR_TRACK_TRANSPARENCY
		bar.fill.BackgroundColor3 = (theme.Colors :: any)[bar.cfg.colorToken] or theme.Colors.Primary
	end
end

return UIOverheadController
