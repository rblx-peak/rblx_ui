--!strict
-- JUDGING — the five-mark verdict, ported from the live pottery duel's
-- grading beat (DuelController's `grading` phase, PotCommissions.gradeParts).
--
-- The shipped game grades a pot into FIVE weighted sub-scores and prints two
-- of them ("shape 88%  colour 82%") on a results column. This screen is that
-- verdict opened all the way up: every mark the grader actually computes, its
-- weight, what it contributed to the total, how it compares to the rival's
-- same mark, its own star rating on the engine's ladder — plus the recipe
-- comparison (the commission's ring profile against the one you threw) that
-- the live commission card and the results pot preview only ever showed
-- separately.
--
-- DENSITY IS THE POINT (pack law §0.3 / anti-condescension). Five marks x ten
-- printed facts, seven recipe comparisons, three glaze-zone comparisons and a
-- six-field grade band. Soft is not simple: this reads denser than the Armored
-- Core assembly stat block it is measured against, and every number on it is
-- one the grader really produces.
--
-- THE CEREMONY, and why it is a pure function of time:
--   Marks bounce in one at a time, their values count up to one decimal, their
--   stars punch in, and the final grade lands with a sparkle burst. All of it
--   is rendered by _ApplyTimeline(t) from a single elapsed clock on the shared
--   UITicker -- no per-stage state machine, no tween bookkeeping. SKIP is
--   therefore free and total: set the clock to the end and apply. That is what
--   makes this genuinely skippable AT EVERY STAGE rather than "skippable
--   between stages", which is the usual way a reveal cheats.

local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local IconVisibility = require(script.Parent.Parent.Icons.IconVisibility)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local PotteryDuelConfig = require(script.Parent.Parent.Config.PotteryDuelConfig)
local UIScreenBase = require(script.Parent.UIScreenBase)

local Copy = PotteryDuelConfig.Copy
local STATS = PotteryDuelConfig.Stats
local MAX_STARS = PotteryDuelConfig.MaxStars

export type Verdict = {
	potter: string?,
	rival: string?,
	roundNum: number?,
	totalRounds: number?,
	mode: string?,
	-- A tiebreak round is scored on shape alone whatever the mode says, so it
	-- overrides the mode's own glaze caption.
	tiebreak: boolean?,
	reward: number?,
	subs: { [string]: number }?, -- engine keys, 0..1
	rivalSubs: { [string]: number }?,
	target: PotteryDuelConfig.PotRecipe?,
	made: PotteryDuelConfig.PotRecipe?,
}

-- ---- timeline (seconds) ----------------------------------------------------
local T_START = 0.30 -- the first mark reveals
local T_STAGGER = 0.55 -- gap between marks
local T_BOUNCE = 0.34 -- bounce-in duration per mark
local T_COUNT = 0.60 -- count-up duration per mark
local T_STAR_DELAY = 0.42 -- after a mark reveals, its stars begin
local T_STAR_STEP = 0.07 -- gap between that mark's stars
local T_STAR_PUNCH = 0.20 -- one star's punch-in
local T_GRADE_GAP = 0.35 -- breath before the grade band
local T_GRADE_COUNT = 0.90 -- the final score counting up
local T_BURST = 0.80 -- the sparkle burst

local T_GRADE_AT = T_START + (#STATS - 1) * T_STAGGER + T_COUNT + T_GRADE_GAP
local T_TOTAL = T_GRADE_AT + T_GRADE_COUNT + T_BURST

-- ---- fixed px at the 1650x1020 baseline ------------------------------------
local PAGE = Vector2.new(1180, 700)
local LEFT_W = 372
local COL_GAP = 16
local BLOCK_H = 62 -- StatRow (30) + the sub-line under it
local SUBLINE_Y = 34
local SUBLINE_H = 24
local STAR_PIP = 16
local STAR_GAP = 4
local GRADE_H = 178
local BIG_STAR = 30
local SPARKLES = 6
local PROFILE_H = 210
local COMPACT_ROW_H = 22

-- The overshoot a textbook easeOutBack reaches with c1 = 1.70158. Solving for
-- the pack's own Motion.PulseScale instead keeps the bounce TOKENIZED -- a
-- theme that caps its overshoot at 1.06 gets a 6% bounce here, not a 10% one.
local BACK_STANDARD_PEAK = 0.0999
local BACK_C1 = 1.70158

local function easeOutBack(a: number, peak: number): number
	local c1 = BACK_C1 * math.max(0, peak - 1) / BACK_STANDARD_PEAK
	local c3 = c1 + 1
	local x = math.clamp(a, 0, 1) - 1
	return 1 + c3 * x * x * x + c1 * x * x
end

local function easeOutQuad(a: number): number
	local x = math.clamp(a, 0, 1)
	return 1 - (1 - x) * (1 - x)
end

-- Recipe fields the comparison table prints, in reading order. `digits` is
-- how many decimals the value carries; `suffix` is printed verbatim. Each
-- reads BOTH recipes, so adding a field here adds a target/made/delta row.
local RECIPE_FIELDS = {
	{ label = "Rings compared", key = "rings", digits = 0, suffix = "" },
	{ label = "Widest ring", key = "widest", digits = 2, suffix = "" },
	{ label = "Rim radius", key = "rim", digits = 2, suffix = "" },
	{ label = "Base radius", key = "base", digits = 2, suffix = "" },
	{ label = "Height scale", key = "height", digits = 2, suffix = "x" },
	{ label = "Hollow depth", key = "hollow", digits = 2, suffix = "" },
	{ label = "Paint coverage", key = "coverage", digits = 0, suffix = "%" },
	{ label = "Add-ons", key = "accessories", digits = 0, suffix = "" },
}

local ZONE_NAMES = { "Base zone", "Belly zone", "Rim zone" }

local JudgingScreen = setmetatable({}, { __index = UIScreenBase })
JudgingScreen.__index = JudgingScreen

function JudgingScreen.new()
	local self = UIScreenBase.new("JudgingScreen", 52)
	self._verdict = {} :: Verdict
	self._elapsed = 0
	self._skipped = false
	self._soundFired = false
	self._stopTicker = nil :: (() -> ())?
	self._shadows = {} :: { any }
	self._blocks = {} :: { any }
	self._recipeRows = {} :: { any }
	self._zoneRows = {} :: { any }
	self._targetBars = {} :: { Frame }
	self._madeBars = {} :: { Frame }
	self._sparkles = {} :: { ImageLabel }
	self._gradeStars = {} :: { any }
	return setmetatable(self, JudgingScreen)
end

-- ========================================================================
-- Derived verdict
-- ========================================================================

local function recipeOf(value: any, fallback: PotteryDuelConfig.PotRecipe): PotteryDuelConfig.PotRecipe
	return (type(value) == "table" and value or fallback) :: PotteryDuelConfig.PotRecipe
end

-- Everything the render needs, computed once per show: the weighted total, the
-- ladder's star count, the tier, the payout, and per-mark values. Kept out of
-- the timeline so a 60Hz apply() never re-derives it.
function JudgingScreen:_Derive()
	local v = self._verdict
	local subs = (type(v.subs) == "table" and v.subs or PotteryDuelConfig.DemoVerdict.subs) :: { [string]: number }
	local rivalSubs = (type(v.rivalSubs) == "table" and v.rivalSubs or nil) :: { [string]: number }?
	local target = recipeOf(v.target, PotteryDuelConfig.DemoTarget)
	local made = recipeOf(v.made, PotteryDuelConfig.DemoMade)
	local reward = tonumber(v.reward) or target.reward or 0

	local score = PotteryDuelConfig.WeightedScore(subs)
	local stars = PotteryDuelConfig.StarsFor(score)

	local marks = {}
	for index, def in STATS do
		local mine = math.clamp(subs[def.sourceKey] or 0, 0, 1)
		local theirs = rivalSubs and math.clamp(rivalSubs[def.sourceKey] or 0, 0, 1) or nil
		marks[index] = {
			value = mine * 100,
			rival = theirs and theirs * 100 or nil,
			stars = PotteryDuelConfig.StarsFor(mine),
			contribution = def.weight * mine * 100,
			ceiling = def.weight * 100,
		}
	end

	self._derived = {
		subs = subs,
		rivalSubs = rivalSubs,
		target = target,
		made = made,
		reward = reward,
		score = score * 100,
		stars = stars,
		tier = PotteryDuelConfig.TierFor(stars),
		line = PotteryDuelConfig.GradeLine(stars),
		payout = PotteryDuelConfig.Payout(reward, stars),
		marks = marks,
	}
end

-- ========================================================================
-- Build
-- ========================================================================

function JudgingScreen:_BuildContent()
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
	self:_BuildClassicLayout()
end

-- ---- GP: a star pip ---------------------------------------------------------

-- The pack's own monochrome sparkle art, tinted per star tier, with a petal
-- chip as the soft fallback when the asset has not uploaded. Registered with
-- IconVisibility because it IS iconography -- and safe to register because the
-- punch-in animates UIScale, never ImageTransparency, so the global toggle and
-- the ceremony can never fight over the same property.
function JudgingScreen:_MakeStar(parent: Instance, size: number, index: number): any
	local theme = self:GetTheme()
	local holder = UIStyler.Frame("Star" .. index)
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)
	holder.LayoutOrder = index
	holder.Parent = parent

	local scale = Instance.new("UIScale")
	scale.Scale = 0.01
	scale.Parent = holder

	local empty = theme.Arcade.RulerTrack
	local art: ImageLabel? = nil
	local def = (theme :: any).Assets and (theme :: any).Assets.sparkle
	if def then
		local image = Instance.new("ImageLabel")
		image.Name = "Art"
		image.BackgroundTransparency = 1
		image.Image = def.image
		image.ScaleType = Enum.ScaleType.Fit
		image.ImageColor3 = empty
		image.Size = UDim2.fromScale(1, 1)
		image.Parent = holder
		IconVisibility.Register(image)
		art = image
	else
		-- TODO: asset missing -- a petal chip in the same tint, same silhouette
		-- language as the rest of the pack.
		local chip = UIStyler.Frame("Chip")
		chip.BackgroundColor3 = empty
		chip.Size = UDim2.fromScale(1, 1)
		chip.Parent = holder
		GPLayoutKit.Petal(theme, chip, index)
	end

	local function paint(color: Color3)
		if art then
			art.ImageColor3 = color
		else
			local chip = holder:FindFirstChild("Chip")
			if chip and chip:IsA("Frame") then
				chip.BackgroundColor3 = color
			end
		end
	end

	return {
		holder = holder,
		scale = scale,
		On = function(color: Color3, punch: number)
			paint(color)
			scale.Scale = math.max(punch, 0.01)
		end,
		Off = function()
			paint(empty)
			scale.Scale = 0.01
		end,
	}
end

function JudgingScreen:_MakeStarStrip(parent: Instance, size: number, gap: number): { any }
	local strip = UIStyler.Frame("Stars")
	strip.BackgroundTransparency = 1
	strip.Size = UDim2.fromOffset(MAX_STARS * size + (MAX_STARS - 1) * gap, size)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, gap),
	}).Parent = strip
	strip.Parent = parent

	local stars = {}
	for index = 1, MAX_STARS do
		stars[index] = self:_MakeStar(strip, size, index)
	end
	return stars
end

-- ---- GP: one mark ----------------------------------------------------------

-- A slot the list lays out (fixed size, never scaled) wrapping an INNER frame
-- that carries the UIScale. Scaling the slot itself would change its
-- AbsoluteSize and make the whole column reflow mid-bounce -- squash and
-- stretch rides UIScale precisely so layout does not move.
function JudgingScreen:_BuildGPBlock(def: PotteryDuelConfig.StatDef, index: number, parent: Instance): any
	local theme = self:GetTheme()
	local tone = PotteryDuelConfig.Tone(theme, def.tone)

	local slot = UIStyler.Frame("Mark_" .. def.id)
	slot.BackgroundTransparency = 1
	slot.Size = UDim2.new(1, 0, 0, BLOCK_H)
	slot.LayoutOrder = index
	slot.Visible = false
	slot.Parent = parent

	local inner = UIStyler.Frame("Inner")
	inner.BackgroundTransparency = 1
	inner.Size = UDim2.fromScale(1, 1)
	inner.Parent = slot

	local scale = Instance.new("UIScale")
	scale.Scale = 0.01
	scale.Parent = inner

	-- invertGoodness = true is deliberate and load-bearing: the row's preview
	-- carries the RIVAL's mark, so the printed delta is (rival - you). A
	-- POSITIVE delta means the rival is ahead, which is bad for you, and the
	-- inverted mapping is what paints it Error instead of Success. The sign is
	-- always printed, so the meaning never rides on hue alone.
	local row = GPLayoutKit.StatRow(theme, inner, {
		label = def.label,
		value = 0,
		maxValue = 100,
		unit = def.unit,
		precision = 1,
		invertGoodness = true,
		accent = tone,
	})

	local sub = UIStyler.Frame("SubLine")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromOffset(0, SUBLINE_Y)
	sub.Size = UDim2.new(1, 0, 0, SUBLINE_H)
	sub.Parent = inner

	local stars = self:_MakeStarStrip(sub, STAR_PIP, STAR_GAP)
	local starW = MAX_STARS * STAR_PIP + (MAX_STARS - 1) * STAR_GAP

	local weight = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Weight")
	weight.Text = string.format("%s %d%%", Copy.Weight, math.round(def.weight * 100))
	weight.TextXAlignment = Enum.TextXAlignment.Left
	weight.Position = UDim2.fromOffset(starW + theme.Spacing.M, 0)
	weight.Size = UDim2.fromOffset(96, SUBLINE_H)
	weight.Parent = sub

	local contribution = GPLayoutKit.NumberText(theme, theme.TextSizes.Small, tone, "Contribution")
	contribution.TextXAlignment = Enum.TextXAlignment.Left
	contribution.Position = UDim2.fromOffset(starW + theme.Spacing.M + 96, 0)
	contribution.Size = UDim2.fromOffset(150, SUBLINE_H)
	contribution.Parent = sub

	local note = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Note")
	note.Text = def.note
	note.TextXAlignment = Enum.TextXAlignment.Right
	note.TextTruncate = Enum.TextTruncate.AtEnd
	note.AnchorPoint = Vector2.new(1, 0)
	note.Position = UDim2.new(1, 0, 0, 0)
	note.Size = UDim2.new(1, -(starW + theme.Spacing.M + 96 + 150 + theme.Spacing.M), 0, SUBLINE_H)
	note.Parent = sub

	return {
		slot = slot,
		scale = scale,
		row = row,
		stars = stars,
		contribution = contribution,
		def = def,
	}
end

-- ---- GP: the recipe comparison ---------------------------------------------

-- A lathe profile drawn as its rings: one centred bar per sampled ring, width
-- proportional to that ring's radius, base at the bottom. Two of these stacked
-- in the same well IS the comparison -- the commission behind as a ghost, the
-- pot you actually threw in front.
function JudgingScreen:_BuildProfile(parent: Instance, name: string, tint: Color3, transparency: number, index: number): { Frame }
	local theme = self:GetTheme()
	local holder = UIStyler.Frame(name)
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = 3 + index
	holder.Parent = parent

	local count = PotteryDuelConfig.SampleRings
	local bars = table.create(count)
	local step = 1 / count
	for ring = 1, count do
		local bar = UIStyler.Frame("Ring" .. ring)
		bar.BackgroundColor3 = tint
		bar.BackgroundTransparency = transparency
		bar.AnchorPoint = Vector2.new(0.5, 1)
		-- Ring 1 is the BASE, so it sits at the bottom of the well.
		bar.Position = UDim2.new(0.5, 0, 1 - (ring - 1) * step, 0)
		bar.Size = UDim2.new(0, 0, step, 1)
		bar.ZIndex = holder.ZIndex
		bar.Parent = holder
		UIStyler.Corner(theme.Radii.Small).Parent = bar
		bars[ring] = bar
	end
	return bars
end

-- Label | commission | yours | delta. Not a StatRow: StatRow is the MARK's
-- shape and reusing it here would say these rows are graded, which they are
-- not -- they are the inputs the grader read.
function JudgingScreen:_BuildCompareRow(parent: Instance, label: string, order: number): any
	local theme = self:GetTheme()
	local row = UIStyler.Frame("Compare_" .. order)
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, COMPACT_ROW_H)
	row.LayoutOrder = order
	row.Parent = parent

	local name = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Name")
	name.Text = label
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Size = UDim2.new(1, -216, 1, 0)
	name.Parent = row

	local function column(x: number, width: number, color: Color3, id: string): TextLabel
		local value = GPLayoutKit.NumberText(theme, theme.TextSizes.Small, color, id)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, -x, 0, 0)
		value.Size = UDim2.fromOffset(width, COMPACT_ROW_H)
		value.Parent = row
		return value
	end

	return {
		root = row,
		name = name,
		target = column(140, 66, theme.Colors.TextSecondary, "Target"),
		made = column(70, 66, theme.Colors.TextPrimary, "Made"),
		delta = column(0, 62, theme.Colors.TextSecondary, "Delta"),
	}
end

function JudgingScreen:_BuildZoneRow(parent: Instance, order: number): any
	local theme = self:GetTheme()
	local row = UIStyler.Frame("Zone_" .. order)
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, COMPACT_ROW_H + 4)
	row.LayoutOrder = order
	row.Parent = parent

	local name = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Name")
	name.Text = ZONE_NAMES[order] or ("Zone " .. order)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Size = UDim2.new(1, -206, 1, 0)
	name.Parent = row

	local function chip(x: number, id: string, petalIndex: number): Frame
		local swatch = UIStyler.Frame(id)
		swatch.BackgroundColor3 = theme.Colors.Surface
		swatch.AnchorPoint = Vector2.new(1, 0.5)
		swatch.Position = UDim2.new(1, -x, 0.5, 0)
		swatch.Size = UDim2.fromOffset(26, 20)
		swatch.Parent = row
		GPLayoutKit.Petal(theme, swatch, petalIndex)
		GPLayoutKit.SoftStroke(theme, swatch)
		return swatch
	end

	-- Right to left: match % | your glaze | arrow | the glaze asked for. The
	-- offsets are laid so the four never overlap at any row width.
	local targetChip = chip(170, "TargetChip", order)
	local madeChip = chip(112, "MadeChip", order + 1)

	local arrow = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Arrow")
	arrow.Text = "\u{2192}"
	arrow.AnchorPoint = Vector2.new(1, 0)
	arrow.Position = UDim2.new(1, -144, 0, 0)
	arrow.Size = UDim2.fromOffset(22, COMPACT_ROW_H + 4)
	arrow.Parent = row

	local match = GPLayoutKit.NumberText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Match")
	match.AnchorPoint = Vector2.new(1, 0)
	match.Position = UDim2.new(1, 0, 0, 0)
	match.Size = UDim2.fromOffset(100, COMPACT_ROW_H + 4)
	match.Parent = row

	return { root = row, name = name, target = targetChip, made = madeChip, match = match }
end

function JudgingScreen:_BuildGPRecipeColumn(content: Instance)
	local theme = self:GetTheme()
	local spacing = theme.Spacing

	local column = Instance.new("ScrollingFrame")
	column.Name = "RecipeColumn"
	column.BackgroundTransparency = 1
	column.BorderSizePixel = 0
	column.Size = UDim2.new(0, LEFT_W, 1, 0)
	column.CanvasSize = UDim2.new()
	column.AutomaticCanvasSize = Enum.AutomaticSize.Y
	column.ScrollBarThickness = 4
	column.ScrollBarImageColor3 = GPLayoutKit.Deepen(theme, theme.Colors.Surface, 1)
	column.ClipsDescendants = true
	column.ZIndex = 4
	column.Parent = content
	-- Padding so the wells' soft shadows are not sliced by the clip (the shadow
	-- blooms OUTSIDE the well's own rect, and a scrolling viewport clips it).
	UIStyler.Padding(spacing.M).Parent = column
	UIStyler.ListLayout({ Padding = UDim.new(0, spacing.S) }).Parent = column

	GPLayoutKit.SectionLabel(theme, column, Copy.RecipeHeading).LayoutOrder = 1

	local wellFill = theme.Colors.SurfaceRaised
	local well = UIStyler.Frame("ProfileWell")
	well.BackgroundColor3 = wellFill
	well.Size = UDim2.new(1, 0, 0, PROFILE_H)
	well.ClipsDescendants = true
	well.LayoutOrder = 2
	well.ZIndex = 4
	well.Parent = column
	GPLayoutKit.Petal(theme, well, 0)
	GPLayoutKit.SoftStroke(theme, well, wellFill)
	GPLayoutKit.Shadow(theme, well, "sm", self._shadows, wellFill)

	local field = UIStyler.Frame("Field")
	field.BackgroundTransparency = 1
	field.Position = UDim2.fromOffset(spacing.M, spacing.M)
	field.Size = UDim2.new(1, -spacing.M * 2, 1, -(spacing.M + 30))
	field.ZIndex = 4
	field.Parent = well

	local ghost = GPLayoutKit.Deepen(theme, theme.Colors.Surface, 1)
	self._targetBars = self:_BuildProfile(field, "Commission", ghost, 0.35, 0)
	self._madeBars = self:_BuildProfile(field, "Yours", theme.Colors.Primary, 0.05, 1)

	local legend = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Legend")
	legend.Text = string.format("%s (behind) \u{00B7} %s (front)", Copy.TargetHeading, Copy.MadeHeading)
	legend.TextXAlignment = Enum.TextXAlignment.Left
	legend.AnchorPoint = Vector2.new(0, 1)
	legend.Position = UDim2.new(0, spacing.M, 1, -spacing.S)
	legend.Size = UDim2.new(1, -spacing.M * 2, 0, 18)
	legend.ZIndex = 6
	legend.Parent = well

	local title = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "CommissionTitle")
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Size = UDim2.new(1, 0, 0, 26)
	title.LayoutOrder = 3
	title.Parent = column
	self._commissionTitle = title

	local blurb = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "CommissionBlurb")
	blurb.TextXAlignment = Enum.TextXAlignment.Left
	blurb.TextWrapped = true
	blurb.Size = UDim2.new(1, 0, 0, 34)
	blurb.LayoutOrder = 4
	blurb.Parent = column
	self._commissionBlurb = blurb

	-- The brief's own instruction, in the four states the live commission card
	-- picks between. It is an INSTRUCTION, not metadata, so it sits on the
	-- mode's tone rather than in with the family/difficulty line.
	local caption = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "CommissionCaption")
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.TextTruncate = Enum.TextTruncate.AtEnd
	caption.Size = UDim2.new(1, 0, 0, 24)
	caption.LayoutOrder = 5
	caption.Parent = column
	self._commissionCaption = caption

	GPLayoutKit.Divider(theme, column).LayoutOrder = 6

	local zoneLabel = GPLayoutKit.SectionLabel(theme, column, "Glaze zones, bottom to top")
	zoneLabel.LayoutOrder = 7

	self._zoneRows = {}
	for index = 1, #ZONE_NAMES do
		self._zoneRows[index] = self:_BuildZoneRow(column, index)
		self._zoneRows[index].root.LayoutOrder = 7 + index
	end

	GPLayoutKit.Divider(theme, column).LayoutOrder = 20

	local header = self:_BuildCompareRow(column, "Measurement", 21)
	header.target.Text = "asked"
	header.made.Text = "yours"
	header.delta.Text = "off by"
	header.name.TextColor3 = theme.Colors.TextPrimary

	self._recipeRows = {}
	for index, field2 in RECIPE_FIELDS do
		self._recipeRows[index] = self:_BuildCompareRow(column, field2.label, 21 + index)
	end
end

-- ---- GP: the grade band -----------------------------------------------------

function JudgingScreen:_BuildGPGradeBand(parent: Instance)
	local theme = self:GetTheme()
	local spacing = theme.Spacing

	local slot = UIStyler.Frame("GradeSlot")
	slot.BackgroundTransparency = 1
	slot.AnchorPoint = Vector2.new(0, 1)
	slot.Position = UDim2.new(0, 0, 1, 0)
	slot.Size = UDim2.new(1, 0, 0, GRADE_H)
	slot.Visible = false
	slot.ZIndex = 5
	slot.Parent = parent

	local inner = UIStyler.Frame("Inner")
	inner.BackgroundTransparency = 1
	inner.Size = UDim2.fromScale(1, 1)
	inner.ZIndex = 5
	inner.Parent = slot

	local scale = Instance.new("UIScale")
	scale.Scale = 0.01
	scale.Parent = inner
	self._gradeScale = scale
	self._gradeSlot = slot

	local fill = theme.Colors.SurfaceRaised
	local band = UIStyler.Frame("GradeBand")
	band.BackgroundColor3 = fill
	band.Size = UDim2.fromScale(1, 1)
	band.ClipsDescendants = true
	band.ZIndex = 5
	band.Parent = inner
	GPLayoutKit.Petal(theme, band, 1)
	GPLayoutKit.SoftStroke(theme, band, fill)
	GPLayoutKit.Shadow(theme, band, "lg", self._shadows, fill)
	GPLayoutKit.GlazeSheen(theme, band)

	-- The burst rides UNDER the numerals and inside the band's own clip, so it
	-- can never bloom over the page chrome. Pack chrome, not iconography:
	-- deliberately NOT registered with IconVisibility, because the ceremony
	-- drives ImageTransparency every frame and the two would fight.
	local burstDef = (theme :: any).Assets and (theme :: any).Assets.sparkleBurst
	if burstDef then
		local burst = Instance.new("ImageLabel")
		burst.Name = "Burst"
		burst.BackgroundTransparency = 1
		burst.Image = burstDef.image
		burst.ImageColor3 = theme.Arcade.Gold
		burst.ImageTransparency = 1
		burst.ScaleType = Enum.ScaleType.Fit
		burst.AnchorPoint = Vector2.new(0.5, 0.5)
		burst.Position = UDim2.fromScale(0.22, 0.5)
		burst.Size = UDim2.fromOffset(GRADE_H + 60, GRADE_H + 60)
		burst.ZIndex = 6
		burst.Parent = band
		self._burst = burst
	end

	local sparkleDef = (theme :: any).Assets and (theme :: any).Assets.sparkle
	self._sparkles = {}
	if sparkleDef then
		for index = 1, SPARKLES do
			local spark = Instance.new("ImageLabel")
			spark.Name = "Spark" .. index
			spark.BackgroundTransparency = 1
			spark.Image = sparkleDef.image
			spark.ImageColor3 = theme.Arcade.Gold
			spark.ImageTransparency = 1
			spark.ScaleType = Enum.ScaleType.Fit
			spark.AnchorPoint = Vector2.new(0.5, 0.5)
			spark.Size = UDim2.fromOffset(26, 26)
			spark.ZIndex = 9
			spark.Parent = band
			self._sparkles[index] = spark
		end
	end

	local caption = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Caption")
	caption.Text = Copy.Verdict
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Position = UDim2.fromOffset(spacing.L, spacing.M)
	caption.Size = UDim2.fromOffset(240, 18)
	caption.ZIndex = 8
	caption.Parent = band

	local score = GPLayoutKit.NumberText(theme, 66, theme.Colors.TextPrimary, "Score")
	score.TextXAlignment = Enum.TextXAlignment.Left
	score.Position = UDim2.fromOffset(spacing.L, spacing.M + 16)
	score.Size = UDim2.fromOffset(220, 74)
	score.ZIndex = 8
	score.Parent = band
	self._scoreLabel = score

	local tier = GPLayoutKit.Text(theme, 30, theme.Arcade.Gold, "Tier")
	tier.TextXAlignment = Enum.TextXAlignment.Left
	tier.Position = UDim2.fromOffset(spacing.L + 232, spacing.M + 22)
	tier.Size = UDim2.fromOffset(280, 40)
	tier.ZIndex = 8
	tier.Parent = band
	self._tierLabel = tier

	local starHolder = UIStyler.Frame("GradeStars")
	starHolder.BackgroundTransparency = 1
	starHolder.Position = UDim2.fromOffset(spacing.L + 232, spacing.M + 64)
	starHolder.Size = UDim2.fromOffset(MAX_STARS * BIG_STAR + (MAX_STARS - 1) * 6, BIG_STAR)
	starHolder.ZIndex = 8
	starHolder.Parent = band
	self._gradeStars = self:_MakeStarStrip(starHolder, BIG_STAR, 6)

	local line = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "GradeLine")
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextTruncate = Enum.TextTruncate.AtEnd
	line.AnchorPoint = Vector2.new(0, 1)
	line.Position = UDim2.new(0, spacing.L, 1, -spacing.M)
	line.Size = UDim2.new(1, -(spacing.L * 2 + 200), 0, 24)
	line.ZIndex = 8
	line.Parent = band
	self._gradeLine = line

	local payoutCaption = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "PayoutCaption")
	payoutCaption.Text = Copy.Payout
	payoutCaption.TextXAlignment = Enum.TextXAlignment.Right
	payoutCaption.AnchorPoint = Vector2.new(1, 0)
	payoutCaption.Position = UDim2.new(1, -spacing.L, 0, spacing.M)
	payoutCaption.Size = UDim2.fromOffset(180, 18)
	payoutCaption.ZIndex = 8
	payoutCaption.Parent = band

	local pill = GPLayoutKit.PricePill(theme, band, self._shadows)
	pill.root.AnchorPoint = Vector2.new(1, 0)
	pill.root.Position = UDim2.new(1, -spacing.L, 0, spacing.M + 22)
	pill.root.ZIndex = 8
	pill.icon.Image = IconArchive.Id("cash") or ""
	pill.amount.ZIndex = 9
	self._payoutPill = pill

	local rewardNote = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "RewardNote")
	rewardNote.TextXAlignment = Enum.TextXAlignment.Right
	rewardNote.AnchorPoint = Vector2.new(1, 0)
	rewardNote.Position = UDim2.new(1, -spacing.L, 0, spacing.M + 66)
	rewardNote.Size = UDim2.fromOffset(240, 18)
	rewardNote.ZIndex = 8
	rewardNote.Parent = band
	self._rewardNote = rewardNote

	-- Transparent button + chip child: the enforcer backstops any SOLID
	-- GuiButton with a BLACK stroke, and this pack forbids pure black outright.
	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.BackgroundTransparency = 1
	skip.Text = ""
	skip.AutoButtonColor = false
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -spacing.L, 1, -spacing.M)
	skip.Size = UDim2.fromOffset(150, 42)
	skip.ZIndex = 9
	skip.Parent = band

	local chipFill = theme.Colors.Secondary
	local chip = UIStyler.Frame("Chip")
	chip.BackgroundColor3 = chipFill
	chip.Size = UDim2.fromScale(1, 1)
	chip.ZIndex = 9
	chip.Parent = skip
	GPLayoutKit.Petal(theme, chip, 0)
	GPLayoutKit.SoftStroke(theme, chip, chipFill)
	GPLayoutKit.Shadow(theme, chip, "sm", self._shadows, chipFill)

	-- Body-sized copy on matcha uses TextPrimary (6.39:1); TextOnPrimary
	-- measures 1.72:1 there and is illegal for anything but display text.
	local skipLabel = GPLayoutKit.BodyText(theme, theme.TextSizes.Button, theme.Colors.TextPrimary, "SkipLabel")
	skipLabel.Text = Copy.Skip
	skipLabel.Size = UDim2.fromScale(1, 1)
	skipLabel.ZIndex = 10
	skipLabel.Parent = chip
	self._skipLabel = skipLabel

	skip.Activated:Connect(function()
		self:_SkipPressed()
	end)
	UIChrome.Animate(theme, skip, chip)
end

-- ---- GP: the page -----------------------------------------------------------

function JudgingScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	local spacing = theme.Spacing
	self._shadows = {}

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = Copy.JudgingTitle,
		subtitleText = Copy.JudgingSubtitle,
		sizePx = PAGE,
		onClose = function()
			self.ScreenController:HideScreen("judging")
		end,
	})
	for _, handle in page.shadows do
		table.insert(self._shadows, handle)
	end
	self._page = page

	-- Round / mode chip in the header's right slot.
	local roundChip = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "RoundChip")
	roundChip.TextXAlignment = Enum.TextXAlignment.Right
	roundChip.Size = UDim2.fromOffset(320, 40)
	roundChip.LayoutOrder = 1
	roundChip.Parent = page.topRight
	self._roundChip = roundChip

	self:_BuildGPRecipeColumn(page.content)

	local right = UIStyler.Frame("MarkColumn")
	right.BackgroundTransparency = 1
	right.Position = UDim2.fromOffset(LEFT_W + COL_GAP, 0)
	right.Size = UDim2.new(1, -(LEFT_W + COL_GAP), 1, 0)
	right.ZIndex = 4
	right.Parent = page.content

	local legend = GPLayoutKit.SectionLabel(theme, right, string.format("Five marks  \u{00B7}  %s", Copy.Delta))
	legend.Size = UDim2.new(1, 0, 0, 22)
	legend.ZIndex = 4

	local field = Instance.new("ScrollingFrame")
	field.Name = "Marks"
	field.BackgroundTransparency = 1
	field.BorderSizePixel = 0
	field.Position = UDim2.fromOffset(0, 28)
	field.Size = UDim2.new(1, 0, 1, -(28 + GRADE_H + spacing.M))
	field.CanvasSize = UDim2.new()
	field.AutomaticCanvasSize = Enum.AutomaticSize.Y
	field.ScrollBarThickness = 4
	field.ScrollBarImageColor3 = GPLayoutKit.Deepen(theme, theme.Colors.Surface, 1)
	field.ClipsDescendants = true
	field.ZIndex = 4
	field.Parent = right
	UIStyler.Padding(spacing.S).Parent = field
	UIStyler.ListLayout({ Padding = UDim.new(0, spacing.S) }).Parent = field

	self._blocks = {}
	for index, def in STATS do
		self._blocks[index] = self:_BuildGPBlock(def, index, field)
	end

	self:_BuildGPGradeBand(right)
end

-- ========================================================================
-- Classic layout (any pack that is not GP)
-- ========================================================================

-- Same five marks, same ladder, same skippable ceremony — the arcade chrome
-- just draws them with the house modal card instead of the petal page. The
-- block/star/grade INTERFACES are identical, so _ApplyTimeline never branches.
function JudgingScreen:_BuildClassicLayout()
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = string.upper(Copy.JudgingTitle),
		sizePx = Vector2.new(900, 620),
		onClose = function()
			self.ScreenController:HideScreen("judging")
		end,
	})
	self._modal = modal

	local list = UIStyler.Frame("Marks")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(24, 8)
	list.Size = UDim2.new(1, -48, 1, -(GRADE_H + 24))
	list.ClipsDescendants = true
	list.ZIndex = 43
	list.Parent = modal.content
	UIStyler.ListLayout({ Padding = UDim.new(0, 10) }).Parent = list

	self._blocks = {}
	for index, def in STATS do
		local tone = PotteryDuelConfig.Tone(theme, def.tone)

		local slot = UIStyler.Frame("Mark_" .. def.id)
		slot.BackgroundTransparency = 1
		slot.Size = UDim2.new(1, 0, 0, BLOCK_H)
		slot.LayoutOrder = index
		slot.Visible = false
		slot.ZIndex = 43
		slot.Parent = list

		local inner = UIStyler.Frame("Inner")
		inner.BackgroundTransparency = 1
		inner.Size = UDim2.fromScale(1, 1)
		inner.ZIndex = 43
		inner.Parent = slot

		local scale = Instance.new("UIScale")
		scale.Scale = 0.01
		scale.Parent = inner

		local label = UIChrome.Text("Label", 22, theme.Colors.TextPrimary)
		label.Text = string.upper(def.label)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Size = UDim2.new(1, -260, 0, 26)
		label.ZIndex = 43
		label.Parent = inner

		local value = UIChrome.Text("Value", 24, tone)
		value.FontFace = theme.Fonts.Numeric
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, -96, 0, 0)
		value.Size = UDim2.fromOffset(120, 26)
		value.ZIndex = 43
		value.Parent = inner

		local delta = UIChrome.BodyText("Delta", 14, theme.Colors.TextSecondary)
		delta.FontFace = theme.Fonts.Numeric
		delta.TextXAlignment = Enum.TextXAlignment.Right
		delta.AnchorPoint = Vector2.new(1, 0)
		delta.Position = UDim2.new(1, 0, 0, 4)
		delta.Size = UDim2.fromOffset(90, 22)
		delta.ZIndex = 43
		delta.Parent = inner

		local track = UIStyler.Frame("Track")
		track.BackgroundColor3 = theme.Arcade.RulerTrack
		track.Position = UDim2.fromOffset(0, 30)
		track.Size = UDim2.new(1, 0, 0, 8)
		track.ZIndex = 43
		track.Parent = inner

		local barFill = UIStyler.Frame("Fill")
		barFill.BackgroundColor3 = tone
		barFill.Size = UDim2.fromScale(0, 1)
		barFill.ZIndex = 44
		barFill.Parent = track

		local contribution = UIChrome.BodyText("Contribution", 13, theme.Colors.TextSecondary)
		contribution.FontFace = theme.Fonts.Numeric
		contribution.TextXAlignment = Enum.TextXAlignment.Left
		contribution.Position = UDim2.fromOffset(0, 42)
		contribution.Size = UDim2.new(0.5, 0, 0, 18)
		contribution.ZIndex = 43
		contribution.Parent = inner

		local starHolder = UIStyler.Frame("Stars")
		starHolder.BackgroundTransparency = 1
		starHolder.AnchorPoint = Vector2.new(1, 0)
		starHolder.Position = UDim2.new(1, 0, 0, 42)
		starHolder.Size = UDim2.fromOffset(MAX_STARS * STAR_PIP + (MAX_STARS - 1) * STAR_GAP, STAR_PIP)
		starHolder.ZIndex = 43
		starHolder.Parent = inner

		local stars = self:_MakeStarStrip(starHolder, STAR_PIP, STAR_GAP)

		-- The GP row's SetValue/SetPreview contract, hand-built: one interface,
		-- so the ceremony below is layout-blind. `current` is kept as an upvalue
		-- rather than re-parsed off the label — a formatted string is a display,
		-- never a data source.
		local current = 0
		local row = {
			SetValue = function(v: number)
				current = v
				value.Text = string.format("%.1f%s", v, def.unit)
				barFill.Size = UDim2.fromScale(math.clamp(v / 100, 0, 1), 1)
			end,
			-- The preview carries the RIVAL's mark, so a POSITIVE delta means
			-- the rival is ahead — bad for you, hence Error on positive.
			SetPreview = function(v: number?)
				if v == nil then
					delta.Text = ""
					delta.TextColor3 = theme.Colors.TextSecondary
					return
				end
				local diff = v - current
				delta.Text = string.format("%+.1f", diff)
				delta.TextColor3 = if diff > 0 then theme.Colors.Error else theme.Colors.Success
			end,
		}

		self._blocks[index] = {
			slot = slot,
			scale = scale,
			row = row,
			stars = stars,
			contribution = contribution,
			def = def,
		}
	end

	-- ---- the grade band ----
	local slot = UIStyler.Frame("GradeSlot")
	slot.BackgroundTransparency = 1
	slot.AnchorPoint = Vector2.new(0.5, 1)
	slot.Position = UDim2.new(0.5, 0, 1, -14)
	slot.Size = UDim2.new(1, -48, 0, GRADE_H)
	slot.Visible = false
	slot.ZIndex = 43
	slot.Parent = modal.content

	local inner = UIStyler.Frame("Inner")
	inner.BackgroundTransparency = 1
	inner.Size = UDim2.fromScale(1, 1)
	inner.ZIndex = 43
	inner.Parent = slot

	local gradeScale = Instance.new("UIScale")
	gradeScale.Scale = 0.01
	gradeScale.Parent = inner
	self._gradeScale = gradeScale
	self._gradeSlot = slot

	local band = UIStyler.Frame("GradeBand")
	band.BackgroundColor3 = theme.Arcade.NearBlack
	band.Size = UDim2.fromScale(1, 1)
	band.ClipsDescendants = true
	band.ZIndex = 43
	band.Parent = inner
	UIChrome.Stroke(theme, "Arcade").Parent = band

	local score = UIChrome.Text("Score", 64, theme.Arcade.Gold)
	score.FontFace = theme.Fonts.Numeric
	score.TextXAlignment = Enum.TextXAlignment.Left
	score.Position = UDim2.fromOffset(20, 14)
	score.Size = UDim2.fromOffset(230, 72)
	score.ZIndex = 44
	score.Parent = band
	self._scoreLabel = score

	local tier = UIChrome.Text("Tier", 28, theme.Arcade.Gold)
	tier.TextXAlignment = Enum.TextXAlignment.Left
	tier.Position = UDim2.fromOffset(258, 22)
	tier.Size = UDim2.fromOffset(280, 36)
	tier.ZIndex = 44
	tier.Parent = band
	self._tierLabel = tier

	local starHolder = UIStyler.Frame("GradeStars")
	starHolder.BackgroundTransparency = 1
	starHolder.Position = UDim2.fromOffset(258, 62)
	starHolder.Size = UDim2.fromOffset(MAX_STARS * BIG_STAR + (MAX_STARS - 1) * 6, BIG_STAR)
	starHolder.ZIndex = 44
	starHolder.Parent = band
	self._gradeStars = self:_MakeStarStrip(starHolder, BIG_STAR, 6)

	local line = UIChrome.BodyText("GradeLine", 16, theme.Colors.TextPrimary)
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.AnchorPoint = Vector2.new(0, 1)
	line.Position = UDim2.new(0, 20, 1, -14)
	line.Size = UDim2.new(1, -240, 0, 22)
	line.ZIndex = 44
	line.Parent = band
	self._gradeLine = line

	local payout = UIChrome.Text("Payout", 30, theme.Arcade.MoneyGreen)
	payout.FontFace = theme.Fonts.Numeric
	payout.TextXAlignment = Enum.TextXAlignment.Right
	payout.AnchorPoint = Vector2.new(1, 0)
	payout.Position = UDim2.new(1, -20, 0, 22)
	payout.Size = UDim2.fromOffset(220, 38)
	payout.ZIndex = 44
	payout.Parent = band
	self._payoutPill = { amount = payout, icon = nil :: any, root = payout }

	local rewardNote = UIChrome.BodyText("RewardNote", 13, theme.Colors.TextSecondary)
	rewardNote.TextXAlignment = Enum.TextXAlignment.Right
	rewardNote.AnchorPoint = Vector2.new(1, 0)
	rewardNote.Position = UDim2.new(1, -20, 0, 62)
	rewardNote.Size = UDim2.fromOffset(240, 18)
	rewardNote.ZIndex = 44
	rewardNote.Parent = band
	self._rewardNote = rewardNote

	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.BackgroundTransparency = 1
	skip.Text = ""
	skip.AutoButtonColor = false
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -20, 1, -12)
	skip.Size = UDim2.fromOffset(150, 40)
	skip.ZIndex = 45
	skip.Parent = band

	local chip = UIStyler.Frame("Chip")
	chip.BackgroundColor3 = theme.Arcade.Green
	chip.Size = UDim2.fromScale(1, 1)
	chip.ZIndex = 45
	chip.Parent = skip
	UIChrome.Corner("Arcade", "Button").Parent = chip
	UIChrome.Stroke(theme, "Arcade", "Button").Parent = chip

	local skipLabel = UIChrome.Text("SkipLabel", 20, theme.Colors.TextOnPrimary)
	skipLabel.Text = string.upper(Copy.Skip)
	skipLabel.Size = UDim2.fromScale(1, 1)
	skipLabel.ZIndex = 46
	skipLabel.Parent = chip
	self._skipLabel = skipLabel

	skip.Activated:Connect(function()
		self:_SkipPressed()
	end)
	UIChrome.Animate(theme, skip, chip)

	-- The classic branch has no recipe column; the marks and the grade are the
	-- screen. Clear the pooled tables so the render never reaches for one.
	self._recipeRows = {}
	self._zoneRows = {}
	self._targetBars = {}
	self._madeBars = {}
	self._sparkles = {}
	self._burst = nil
end

-- ========================================================================
-- Static render (everything that does NOT move)
-- ========================================================================

local function formatValue(value: number, digits: number, suffix: string): string
	return string.format("%." .. digits .. "f%s", value, suffix)
end

local function recipeMetrics(recipe: PotteryDuelConfig.PotRecipe): { [string]: number }
	local radii = recipe.radii
	local widest = 0
	for _, r in radii do
		widest = math.max(widest, r)
	end
	return {
		rings = PotteryDuelConfig.RingCount,
		widest = widest,
		rim = radii[#radii] or 0,
		base = radii[1] or 0,
		height = recipe.heightScale,
		hollow = recipe.hollow,
		coverage = (recipe.coverage or 1) * 100,
		accessories = recipe.accessories,
	}
end

function JudgingScreen:_RenderStatic()
	local theme = self:GetTheme()
	local d = self._derived
	local v = self._verdict
	local mode = PotteryDuelConfig.GetMode(v.mode)

	if self._roundChip then
		self._roundChip.Text = string.format(
			"%s  \u{00B7}  %s %s",
			string.format(Copy.RoundHeading, tonumber(v.roundNum) or 1, tonumber(v.totalRounds) or mode.rounds),
			mode.emoji,
			mode.displayName
		)
	end
	if self._page then
		self._page.subtitle.Text = string.format(
			"%s  \u{00B7}  %s",
			Copy.JudgingSubtitle,
			if d.rivalSubs then string.format("%s: %s", Copy.Rival, tostring(v.rival or PotteryDuelConfig.DemoVerdict.rival)) else Copy.NoRival
		)
		self._page.subtitle.Visible = true
	end

	if self._commissionTitle then
		self._commissionTitle.Text = d.target.title
		self._commissionBlurb.Text = string.format(
			"%s  \u{00B7}  difficulty %d  \u{00B7}  %d rings on the wheel",
			d.target.family,
			d.target.difficulty,
			PotteryDuelConfig.RingCount
		)
		-- A tiebreak round is graded on silhouette alone, exactly like Shape
		-- Only, so it takes the same caption.
		local coloured = v.tiebreak ~= true
		self._commissionCaption.Text = PotteryDuelConfig.CommissionCaption(mode, coloured)
		self._commissionCaption.TextColor3 = PotteryDuelConfig.Tone(theme, mode.tone)
	end

	-- Profiles share ONE normaliser so the two silhouettes are comparable; a
	-- per-pot normaliser would make a narrow pot look identical to a wide one.
	local widest = 0.001
	for _, r in d.target.radii do
		widest = math.max(widest, r)
	end
	for _, r in d.made.radii do
		widest = math.max(widest, r)
	end
	local function layProfile(bars: { Frame }, recipe: PotteryDuelConfig.PotRecipe)
		for index, bar in bars do
			local radius = recipe.radii[index] or 0
			bar.Size = UDim2.new(math.clamp(radius / widest, 0, 1), 0, 1 / #bars, 1)
		end
	end
	layProfile(self._targetBars, d.target)
	layProfile(self._madeBars, d.made)

	local targetMetrics = recipeMetrics(d.target)
	local madeMetrics = recipeMetrics(d.made)
	for index, field in RECIPE_FIELDS do
		local row = self._recipeRows[index]
		if row then
			local asked = targetMetrics[field.key] or 0
			local made = madeMetrics[field.key] or 0
			local diff = made - asked
			row.target.Text = formatValue(asked, field.digits, field.suffix)
			row.made.Text = formatValue(made, field.digits, field.suffix)
			if math.abs(diff) < 0.5 * 10 ^ -field.digits then
				row.delta.Text = "on target"
				row.delta.TextColor3 = theme.Colors.Success
			else
				row.delta.Text = string.format("%+." .. field.digits .. "f", diff)
				row.delta.TextColor3 = theme.Colors.Error
			end
		end
	end

	local targetZones = d.target.zones or {}
	local madeZones = d.made.zones or {}
	for index, row in self._zoneRows do
		local asked = targetZones[index]
		local made = madeZones[index]
		if asked and made then
			row.root.Visible = true
			row.target.BackgroundColor3 = asked
			row.made.BackgroundColor3 = made
			-- The grader's own falloff is RGB distance normalised to [0,1];
			-- this is that same distance, printed.
			local dr, dg, db = asked.R - made.R, asked.G - made.G, asked.B - made.B
			local distance = math.sqrt(dr * dr + dg * dg + db * db) / math.sqrt(3)
			row.match.Text = string.format("%.1f%% match", math.clamp(1 - distance, 0, 1) * 100)
		else
			row.root.Visible = false
		end
	end

	if self._rewardNote then
		self._rewardNote.Text = string.format("of %d at six stars", d.reward)
	end
end

-- ========================================================================
-- The ceremony — a pure function of elapsed time
-- ========================================================================

function JudgingScreen:_ApplyTimeline(t: number)
	local theme = self:GetTheme()
	local d = self._derived
	local peak = theme.Motion.PulseScale or 1.12
	local empty = theme.Arcade.RulerTrack

	for index, block in self._blocks do
		local mark = d.marks[index]
		local start = T_START + (index - 1) * T_STAGGER
		if t < start then
			block.slot.Visible = false
			block.scale.Scale = 0.01
			block.row.SetValue(0)
			block.row.SetPreview(nil)
			block.contribution.Text = ""
			for _, star in block.stars do
				star.Off()
			end
		else
			block.slot.Visible = true
			block.scale.Scale = math.max(easeOutBack((t - start) / T_BOUNCE, peak), 0.01)

			local progress = easeOutQuad((t - start) / T_COUNT)
			block.row.SetValue(mark.value * progress)
			block.contribution.Text = string.format(
				"%s %.1f of %.1f",
				Copy.Contribution,
				mark.contribution * progress,
				mark.ceiling
			)
			-- The rival ghost only lands once the number has stopped moving —
			-- a delta chasing a counting value reads as a glitch.
			block.row.SetPreview(if progress >= 1 then mark.rival else nil)

			local tier = PotteryDuelConfig.TierFor(mark.stars)
			for starIndex, star in block.stars do
				local at = start + T_STAR_DELAY + (starIndex - 1) * T_STAR_STEP
				if starIndex > mark.stars or t < at then
					star.Off()
				else
					star.On(tier.color, math.max(easeOutBack((t - at) / T_STAR_PUNCH, peak), 0.01))
				end
			end
		end
	end

	-- ---- the grade band ----
	if t < T_GRADE_AT then
		self._gradeSlot.Visible = false
		self._gradeScale.Scale = 0.01
		self._scoreLabel.Text = "0.0%"
		self._tierLabel.Text = ""
		self._gradeLine.Text = ""
		self._payoutPill.amount.Text = "0"
		for _, star in self._gradeStars do
			star.Off()
		end
		self:_ApplyBurst(-1, empty)
		return
	end

	self._gradeSlot.Visible = true
	self._gradeScale.Scale = math.max(easeOutBack((t - T_GRADE_AT) / T_BOUNCE, peak), 0.01)

	local progress = easeOutQuad((t - T_GRADE_AT) / T_GRADE_COUNT)
	self._scoreLabel.Text = string.format("%.1f%%", d.score * progress)
	self._payoutPill.amount.Text = string.format("%d", math.round(d.payout * progress))

	if progress >= 1 then
		self._tierLabel.Text = d.tier.name
		self._tierLabel.TextColor3 = d.tier.color
		self._gradeLine.Text = d.line
		if not self._soundFired then
			self._soundFired = true
			self:_PlaySound(if d.stars >= 5 then "Success" else "Click")
		end
	else
		self._tierLabel.Text = ""
		self._gradeLine.Text = ""
	end

	local starsAt = T_GRADE_AT + T_GRADE_COUNT
	for starIndex, star in self._gradeStars do
		local at = starsAt + (starIndex - 1) * T_STAR_STEP
		if starIndex > d.stars or t < at then
			star.Off()
		else
			star.On(d.tier.color, math.max(easeOutBack((t - at) / T_STAR_PUNCH, peak), 0.01))
		end
	end

	self:_ApplyBurst((t - starsAt) / T_BURST, d.tier.color)
end

-- The sparkle burst: `progress` < 0 means "not yet", so the same call clears
-- the effect on a rewind (a re-show replays from zero).
function JudgingScreen:_ApplyBurst(progress: number, tint: Color3)
	local eased = math.clamp(progress, 0, 1)
	local hidden = progress < 0

	if self._burst then
		self._burst.ImageColor3 = tint
		self._burst.ImageTransparency = if hidden then 1 else 0.2 + 0.8 * eased
		local size = GRADE_H + 60
		local grown = size * (0.45 + 0.9 * eased)
		self._burst.Size = UDim2.fromOffset(grown, grown)
		self._burst.Rotation = 24 * eased
	end

	for index, spark in self._sparkles do
		local angle = (index - 1) * (2 * math.pi / math.max(1, #self._sparkles))
		local radius = 34 + 96 * eased
		spark.ImageColor3 = tint
		spark.ImageTransparency = if hidden then 1 else 0.1 + 0.9 * eased
		spark.Position = UDim2.new(0.22, math.cos(angle) * radius, 0.5, math.sin(angle) * radius * 0.62)
		local scale = 0.4 + 0.9 * (1 - eased)
		spark.Size = UDim2.fromOffset(26 * scale, 26 * scale)
	end
end

-- ========================================================================
-- Skip
-- ========================================================================

-- First press SKIPS (the timeline jumps to its final state); once there, the
-- same button closes. Skipping mid-count is safe because _ApplyTimeline is a
-- pure function of t — there is no half-finished stage to reconcile.
function JudgingScreen:_SkipPressed()
	if self._skipped then
		self.ScreenController:HideScreen("judging")
		return
	end
	self:_Skip()
end

function JudgingScreen:_Skip()
	if self._skipped then
		return
	end
	self._skipped = true
	self._elapsed = T_TOTAL
	self._soundFired = true
	self:_ApplyTimeline(T_TOTAL)
	self:_StopTicker()
	if self._skipLabel then
		self._skipLabel.Text = if self:LayoutKit() == "GP" then "Done" else "DONE"
	end
end

-- ========================================================================
-- Ticker
-- ========================================================================

function JudgingScreen:_StartTicker()
	self:_StopTicker()
	-- ONE handler on the shared Heartbeat, bound to the root so a destroyed
	-- screen releases it even if a teardown path is ever missed.
	self._stopTicker = UITicker.Register(function(dt: number)
		if not self:IsVisible() then
			return
		end
		self._elapsed += dt
		if self._elapsed >= T_TOTAL then
			self._elapsed = T_TOTAL
			self:_ApplyTimeline(T_TOTAL)
			self:_StopTicker()
			return
		end
		self:_ApplyTimeline(self._elapsed)
	end, self.Root)
end

function JudgingScreen:_StopTicker()
	if self._stopTicker then
		self._stopTicker()
		self._stopTicker = nil
	end
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function JudgingScreen:_OnShow(data: any?)
	if type(data) == "table" then
		self._verdict = data :: Verdict
	end
	self:_Derive()
	self:_RenderStatic()

	self._elapsed = 0
	self._skipped = false
	self._soundFired = false
	if self._skipLabel then
		self._skipLabel.Text = if self:LayoutKit() == "GP" then Copy.Skip else string.upper(Copy.Skip)
	end
	self:_ApplyTimeline(0)
	self:_StartTicker()
end

function JudgingScreen:_OnHide()
	self:_StopTicker()
end

function JudgingScreen:Update(data: any)
	if self._built and self:IsVisible() then
		self:_OnShow(data)
	end
end

-- A style rebuild throws the Gui away, but a UIShadow's BUDGET count only
-- falls when its handle is released — hand every one back here, and drop the
-- pooled row tables that would otherwise point at dead instances.
function JudgingScreen:_OnTeardown()
	self:_StopTicker()
	GPLayoutKit.ReleaseShadows(self._shadows)
	table.clear(self._blocks)
	table.clear(self._recipeRows)
	table.clear(self._zoneRows)
	table.clear(self._targetBars)
	table.clear(self._madeBars)
	table.clear(self._sparkles)
	table.clear(self._gradeStars)
	self._page = nil
	self._modal = nil
	self._burst = nil
	self._gradeSlot = nil
	self._gradeScale = nil
	self._scoreLabel = nil
	self._tierLabel = nil
	self._gradeLine = nil
	self._payoutPill = nil
	self._rewardNote = nil
	self._skipLabel = nil
	self._roundChip = nil
	self._commissionTitle = nil
	self._commissionBlurb = nil
	self._commissionCaption = nil
end

function JudgingScreen:Destroy()
	self:_OnTeardown()
	UIScreenBase.Destroy(self)
end

return JudgingScreen
