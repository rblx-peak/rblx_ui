--!strict
-- THE POTTERY DUEL, AS DATA.
--
-- Every string, ladder and number the three duel screens (DuelIntroScreen,
-- DuelResultScreen, JudgingScreen) render lives here, so a build never carries
-- a literal. The values are the LIVE GAME's, transcribed from the shipped
-- match client and its shared modules:
--
--   * Timing        <- DuelConfig (round/countdown/results/second-chance windows)
--   * Modes         <- DuelModes (six modes: name, emoji, blurb, signature hue,
--                      the scoring overrides each one applies)
--   * Phases        <- DuelController's PHASE_TEXT banner table
--   * Stats         <- PotCommissions.WEIGHTS, renamed to the words a POTTER
--                      uses. The engine keys stay attached (`sourceKey`) so a
--                      real grade payload maps onto a row without a lookup
--                      table living in the screen.
--   * StarCuts /
--     StarTiers /
--     PayoutFrac    <- PotCommissions' exponential 7-star ladder, its
--                      slate->prismatic metal ramp, and its back-loaded payout
--                      curve, verbatim.
--
-- COPY LAW (pack §5): nothing here is written in caps. The GP screens print
-- these strings verbatim; the classic/AC branches uppercase at the call site
-- if their own language demands it.

local Types = require(script.Parent.Parent.Types)

local PotteryDuelConfig = {}

-- ========================================================================
-- Tone resolution
-- ========================================================================

-- Modes and stats name a tone rather than carrying a Color3, because in this
-- collection the PACK owns colour. One mapping, shared by all three duel
-- screens, so a mode's hue can never drift between the face-off and the
-- verdict. Every branch falls back through tokens that exist on every theme.
function PotteryDuelConfig.Tone(theme: Types.UITheme, tone: string?): Color3
	local arcade = theme.Arcade
	local semantic = theme.Semantic :: any
	if tone == "Rose" then
		return theme.Colors.Primary
	elseif tone == "Matcha" then
		return theme.Colors.Secondary
	elseif tone == "Gold" then
		return arcade.Gold
	elseif tone == "Clay" then
		return (semantic.Currency and semantic.Currency.Clay) or arcade.Orange
	elseif tone == "Lilac" then
		return arcade.Magenta
	elseif tone == "Sky" then
		return semantic.VSSky or arcade.Blue
	elseif tone == "Danger" then
		return theme.Colors.Error
	end
	return theme.Colors.Primary
end

-- ========================================================================
-- Match timing
-- ========================================================================

-- Seconds. TickFrom/PanicFrom are the two separate thresholds the live HUD
-- keeps apart on purpose: the AUDIBLE tick is the last 3 whole seconds, the
-- VISUAL panic (pulse + flash) starts a full 10 out.
PotteryDuelConfig.Timing = {
	PrematchSeconds = 6,
	ModeLockSeconds = 3,
	CountdownSeconds = 6,
	WalkSeconds = 2.5,
	MainRoundSeconds = 35,
	TiebreakRoundSeconds = 35,
	RoundCountdownSeconds = 5,
	RoundBreakSeconds = 8,
	CarrySeconds = 7,
	ResultsSeconds = 9,
	IntermissionSeconds = 6,
	SecondChanceSeconds = 10,
	SecondChanceGraceSeconds = 30,
	TickFromSeconds = 3,
	PanicFromSeconds = 10,
	Rounds = 3,
}

-- ========================================================================
-- Duel modes
-- ========================================================================

-- `tone` names a SEMANTIC theme slot rather than carrying a literal Color3:
-- the live game hardcodes each mode's hue, but a pack-driven collection must
-- let the theme own colour. Screens resolve it through their own tone map.
export type Mode = {
	key: string,
	displayName: string,
	emoji: string,
	blurb: string,
	tone: string,
	roundSeconds: number,
	rounds: number,
	skipGlaze: boolean,
	hideCommissionAfter: number, -- 0 = the reference card never hides
	colourZones: number, -- paint zones the target asks for, bottom -> top
	rewardBlurb: string,
}

PotteryDuelConfig.Modes = {
	{
		key = "default",
		displayName = "Classic",
		emoji = "\u{1F3FA}",
		blurb = "Best-of-3. Shape and paint to match the image. Round 3 paints two colours!",
		tone = "Gold",
		roundSeconds = 35,
		rounds = 3,
		skipGlaze = false,
		hideCommissionAfter = 0,
		colourZones = 1,
		rewardBlurb = "Standard clay",
	},
	{
		key = "blitz",
		displayName = "Blitz",
		emoji = "\u{26A1}",
		blurb = "15-second rounds, best-of-5. Twitchy, momentum swings.",
		tone = "Sky",
		roundSeconds = 15,
		rounds = 5,
		skipGlaze = false,
		hideCommissionAfter = 0,
		colourZones = 1,
		rewardBlurb = "Standard clay",
	},
	{
		key = "sudden",
		displayName = "Sudden Death",
		emoji = "\u{1F480}",
		blurb = "One pot, two paint zones, highest accuracy takes it. A dead heat re-pots.",
		tone = "Danger",
		roundSeconds = 35,
		rounds = 1,
		skipGlaze = false,
		hideCommissionAfter = 0,
		colourZones = 2,
		rewardBlurb = "2x clay",
	},
	{
		key = "shape",
		displayName = "Shape Only",
		emoji = "\u{1F5FF}",
		blurb = "No painting — pure silhouette skill. Best-of-3, 20s.",
		tone = "Matcha",
		roundSeconds = 20,
		rounds = 3,
		skipGlaze = true,
		hideCommissionAfter = 0,
		colourZones = 0,
		rewardBlurb = "Standard clay",
	},
	{
		key = "blind",
		displayName = "Blind Potter",
		emoji = "\u{1F648}",
		blurb = "The target flashes for 3s, then vanishes. Build from memory.",
		tone = "Lilac",
		roundSeconds = 35,
		rounds = 3,
		skipGlaze = false,
		hideCommissionAfter = 3,
		colourZones = 1,
		rewardBlurb = "2x clay",
	},
	{
		key = "extreme",
		displayName = "Extreme",
		emoji = "\u{1F525}",
		blurb = "Brutal shapes, three tight paint zones, no easy marks.",
		tone = "Clay",
		roundSeconds = 35,
		rounds = 3,
		skipGlaze = false,
		hideCommissionAfter = 0,
		colourZones = 3,
		rewardBlurb = "3x clay + bux",
	},
} :: { Mode }

local modesByKey: { [string]: Mode } = {}
for _, mode in PotteryDuelConfig.Modes do
	modesByKey[mode.key] = mode
end

-- Lookup by key OR by display name, case-insensitively: screens are handed a
-- mode from a match payload in one form and from a demo string in the other,
-- and neither should have to normalise before asking.
function PotteryDuelConfig.GetMode(key: string?): Mode
	if key then
		local direct = modesByKey[key]
		if direct then
			return direct
		end
		local lowered = string.lower(key)
		for _, mode in PotteryDuelConfig.Modes do
			if string.lower(mode.key) == lowered or string.lower(mode.displayName) == lowered then
				return mode
			end
		end
	end
	return PotteryDuelConfig.Modes[1]
end

-- ========================================================================
-- Phase banner copy
-- ========================================================================

-- The live PHASE_TEXT table. `waiting` and `results` are deliberately blank —
-- the lobby panel and the results screen own that strip of screen, and a
-- second title competing with them is what the game removed.
PotteryDuelConfig.Phases = {
	waiting = { title = "", subtitle = "" },
	prematch = { title = "Get ready!", subtitle = "Duel starting — change mode or leave" },
	countdown = { title = "Get ready!", subtitle = "Same commission — best pot wins" },
	walk = { title = "To your wheel!", subtitle = "Round 1 is about to start..." },
	main = { title = "Shape & paint", subtitle = "Match the commission!" },
	tiebreak = { title = "Tiebreak", subtitle = "Shape only — closest pot wins" },
	grading = { title = "Judging the pots...", subtitle = "" },
	roundend = { title = "", subtitle = "" },
	secondchance = { title = "Second chance?", subtitle = "The loser can buy one redemption round — its winner takes the match!" },
	carry = { title = "Present your pots!", subtitle = "Bring them to the table" },
	results = { title = "", subtitle = "" },
	intermission = { title = "Good duel!", subtitle = "Next match starting soon" },
} :: { [string]: { title: string, subtitle: string } }

function PotteryDuelConfig.PhaseText(phase: string?): (string, string)
	local entry = phase and PotteryDuelConfig.Phases[phase]
	if not entry then
		return phase or "", ""
	end
	return entry.title, entry.subtitle
end

-- ========================================================================
-- How to play (rides the opening face-off and the walk)
-- ========================================================================

PotteryDuelConfig.RulesTitle = "How to play"
PotteryDuelConfig.RuleLines = {
	{ iconKey = "cursor", text = "Click and drag the clay to mold it into the target shape" },
	{ iconKey = "edit", text = "Then grab the paint tools and click to paint the pot" },
} :: { { iconKey: string, text: string } }

-- ========================================================================
-- THE VERDICT — five stats
-- ========================================================================

-- Weights are PotCommissions.WEIGHTS exactly (0.45 / 0.20 / 0.15 / 0.10 /
-- 0.10, summing to 1). `sourceKey` is the engine's own sub-score key, kept so
-- a live Grade.sub table drops straight onto these rows.
export type StatDef = {
	id: string,
	label: string,
	sourceKey: string,
	weight: number,
	tone: string,
	unit: string,
	note: string,
}

PotteryDuelConfig.Stats = {
	{
		id = "FORM",
		label = "Form",
		sourceKey = "shape",
		weight = 0.45,
		tone = "Rose",
		unit = "%",
		note = "Ring-by-ring silhouette against the commission",
	},
	{
		id = "SYMMETRY",
		label = "Symmetry",
		sourceKey = "hollow",
		weight = 0.10,
		tone = "Matcha",
		unit = "%",
		note = "How true the walls run once the pot is opened out",
	},
	{
		id = "GLAZE",
		label = "Glaze quality",
		sourceKey = "glaze",
		weight = 0.20,
		tone = "Gold",
		unit = "%",
		note = "Colour accuracy, gated by how much of the pot you covered",
	},
	{
		id = "FIRING",
		label = "Firing",
		sourceKey = "height",
		weight = 0.15,
		tone = "Clay",
		unit = "%",
		note = "Finished height against the rise the brief asked for",
	},
	{
		id = "FLAIR",
		label = "Flair",
		sourceKey = "accessories",
		weight = 0.10,
		tone = "Lilac",
		unit = "%",
		note = "Handles, lips and add-ons — the exact count, no more",
	},
} :: { StatDef }

-- ========================================================================
-- Star ladder, tiers, payout
-- ========================================================================

-- Exponential 7-star curve, highest cut first: >= 0.97 is the secret seventh
-- grade, below every cut floors at one star.
PotteryDuelConfig.StarCuts = { 0.97, 0.92, 0.80, 0.66, 0.50, 0.32 }
PotteryDuelConfig.MaxStars = 7

-- Index = stars. The metals climb dull -> precious; seven carries a two-stop
-- shimmer with a solid fallback for a consumer that cannot gradient.
PotteryDuelConfig.StarTiers = {
	{ name = "Slate", color = Color3.fromRGB(118, 106, 110) },
	{ name = "Pewter", color = Color3.fromRGB(176, 178, 184) },
	{ name = "Bronze", color = Color3.fromRGB(176, 120, 66) },
	{ name = "Copper", color = Color3.fromRGB(196, 110, 66) },
	{ name = "Silver", color = Color3.fromRGB(206, 210, 220) },
	{ name = "Gold", color = Color3.fromRGB(244, 199, 91) },
	{
		name = "Prismatic",
		color = Color3.fromRGB(236, 120, 200),
		gradient = { Color3.fromRGB(255, 150, 214), Color3.fromRGB(150, 90, 220) },
	},
} :: { { name: string, color: Color3, gradient: { Color3 }? } }

-- Back-loaded: 1-3 stars are near-misses that barely pay, 6 pays the full
-- reward, 7 pays a 150% bonus.
PotteryDuelConfig.PayoutFrac = { 0.01, 0.025, 0.05, 0.35, 0.80, 1.00, 1.50 }

-- One line of flavour per grade, so the verdict never lands as a bare number.
PotteryDuelConfig.GradeLines = {
	"That one goes back on the wheel.",
	"Rough, but it stands up.",
	"Honest work — the shape is in there.",
	"Clean lines. The kiln approves.",
	"Lovely. Barely a wobble on it.",
	"Gorgeous — that belongs on a shelf.",
	"Perfect. The judges are speechless.",
}

-- Walk the cut ladder exactly the way the grader does.
function PotteryDuelConfig.StarsFor(score01: number): number
	for index, cut in PotteryDuelConfig.StarCuts do
		if score01 >= cut then
			return 8 - index
		end
	end
	return 1
end

function PotteryDuelConfig.TierFor(stars: number): { name: string, color: Color3, gradient: { Color3 }? }
	local index = math.clamp(math.round(stars), 1, PotteryDuelConfig.MaxStars)
	return PotteryDuelConfig.StarTiers[index]
end

function PotteryDuelConfig.GradeLine(stars: number): string
	local index = math.clamp(math.round(stars), 1, PotteryDuelConfig.MaxStars)
	return PotteryDuelConfig.GradeLines[index]
end

function PotteryDuelConfig.Payout(reward: number, stars: number): number
	local index = math.clamp(math.round(stars), 1, PotteryDuelConfig.MaxStars)
	return math.round(reward * PotteryDuelConfig.PayoutFrac[index])
end

-- Weighted total from a sub-score table keyed by ENGINE keys (shape/height/
-- hollow/glaze/accessories), each 0..1. Fixed iteration over Stats keeps the
-- sum order stable, which is what makes two peers agree on the same float.
function PotteryDuelConfig.WeightedScore(subs: { [string]: number }): number
	local total = 0
	for _, def in PotteryDuelConfig.Stats do
		total += def.weight * math.clamp(subs[def.sourceKey] or 0, 0, 1)
	end
	return math.clamp(total, 0, 1)
end

-- ========================================================================
-- Copy
-- ========================================================================

PotteryDuelConfig.Copy = {
	JudgingTitle = "The judges have your pot",
	JudgingSubtitle = "Five marks, one grade",
	Skip = "Skip",
	Verdict = "Final grade",
	Payout = "Clay earned",
	Rival = "Rival",
	Delta = "vs rival",
	Weight = "weight",
	Contribution = "adds",
	TargetHeading = "The commission",
	MadeHeading = "What you made",
	RecipeHeading = "Recipe check",
	NoRival = "No rival this round — you are potting solo.",
	Win = "You win!",
	Lose = "You lose",
	Tie = "It's a tie!",
	RoundWins = "Round wins",
	SeeVerdict = "See the full verdict",
	Leave = "Leave",
	Leaving = "Leaving...",
	Finalizing = "Game finalizing...",
	ReseatFormat = "Returning to your seat in %d...",
	SecondChanceTitle = "You lost! Want another chance to beat your opponent?",
	SecondChanceTimer = "Offer gone in: %.1f",
	SecondChanceBadge = "70% off!",
	SecondChanceYes = "Yes",
	SecondChanceNo = "No",
	SecondChanceLocked = "Starting extra round...",
	ShapeBreakdown = "shape %d%%    colour %d%%",
	RoundHeading = "Round %d of %d",
	BestOf = "Best of %d",
	Wins = "%d wins",
	SkillLevel = "Skill level %d",
	CommissionCaptionOne = "match this colour",
	CommissionCaptionMany = "match these %d colours (bottom to top)",
	CommissionCaptionAny = "any colour is fine",
	CommissionCaptionNone = "shape only!",
	-- The seated waiting lobby, which shares the mode banner's band: how many
	-- chairs are filled, the prematch hold, and the three things you can still
	-- do while it runs. CHANGE MODE freezes for the last few seconds and says
	-- so on the button rather than letting a tap silently do nothing.
	SeatCount = "%d / 2",
	Prematch = "Starting in %d...",
	ChangeMode = "Change mode",
	ModeLocked = "Mode locked",
	LeaveTable = "Leave",
	InviteFriends = "Invite friends",
	-- The between-rounds beat: which round just ended, who took it, and both
	-- pots' marks. A tie prints its own line rather than a nameless winner.
	RoundResultHeading = "Round %d / %d",
	RoundWinner = "%s wins the round!",
	RoundTied = "Round tied",
	MatchPoint = "Match point",
}

-- The commission card's four caption states, exactly as the live card picks
-- them: a multicolour brief names its zone count, a single-glaze brief names
-- the one colour, a glazed brief with no target colour frees you, and a
-- shape-only round (Shape Only, or any tiebreak) says so outright.
function PotteryDuelConfig.CommissionCaption(mode: Mode, coloured: boolean?): string
	local paints = coloured ~= false and not mode.skipGlaze
	if not paints then
		return PotteryDuelConfig.Copy.CommissionCaptionNone
	end
	if mode.colourZones >= 2 then
		return string.format(PotteryDuelConfig.Copy.CommissionCaptionMany, mode.colourZones)
	elseif mode.colourZones == 1 then
		return PotteryDuelConfig.Copy.CommissionCaptionOne
	end
	return PotteryDuelConfig.Copy.CommissionCaptionAny
end

-- ========================================================================
-- Demo data (the collection renders with no live match behind it)
-- ========================================================================

-- The live recipe carries PotConstants.RING_COUNT = 29 wall rings; these are
-- the 15 the card SAMPLES for its silhouette, in mesh-space radii, base -> rim.
PotteryDuelConfig.RingCount = 29
PotteryDuelConfig.SampleRings = 15

export type PotRecipe = {
	title: string,
	family: string,
	difficulty: number,
	reward: number,
	radii: { number },
	heightScale: number,
	hollow: number,
	coverage: number,
	accessories: number,
	glaze: Color3?,
	zones: { Color3 }?,
}

PotteryDuelConfig.DemoTarget = {
	title = "Tall Vase for Maren",
	family = "Vase",
	difficulty = 2,
	reward = 480,
	radii = { 0.62, 0.78, 0.96, 1.14, 1.28, 1.34, 1.30, 1.18, 1.02, 0.88, 0.80, 0.82, 0.94, 1.06, 1.10 },
	heightScale = 1.28,
	hollow = 1.40,
	coverage = 1,
	accessories = 2,
	zones = { Color3.fromRGB(255, 138, 175), Color3.fromRGB(168, 205, 145), Color3.fromRGB(255, 214, 122) },
} :: PotRecipe

PotteryDuelConfig.DemoMade = {
	title = "Your pot",
	family = "Vase",
	difficulty = 2,
	reward = 480,
	radii = { 0.66, 0.80, 0.94, 1.10, 1.26, 1.30, 1.24, 1.14, 1.04, 0.92, 0.86, 0.88, 0.96, 1.02, 1.04 },
	heightScale = 1.21,
	hollow = 1.12,
	coverage = 0.86,
	accessories = 2,
	zones = { Color3.fromRGB(252, 150, 182), Color3.fromRGB(176, 210, 158), Color3.fromRGB(248, 206, 128) },
} :: PotRecipe

-- The rival's pot: closer on the belly, well short at the rim, and barely
-- glazed — so the comparison silhouette and the lower score agree.
PotteryDuelConfig.DemoRival = {
	title = "Rival pot",
	family = "Vase",
	difficulty = 2,
	reward = 480,
	radii = { 0.58, 0.72, 0.90, 1.12, 1.30, 1.36, 1.32, 1.16, 0.96, 0.78, 0.66, 0.62, 0.66, 0.72, 0.74 },
	heightScale = 1.18,
	hollow = 1.52,
	coverage = 0.64,
	accessories = 1,
	zones = { Color3.fromRGB(238, 166, 190), Color3.fromRGB(196, 214, 176), Color3.fromRGB(236, 214, 158) },
} :: PotRecipe

-- Sub-scores keyed by the ENGINE keys, exactly as a Grade.sub arrives.
PotteryDuelConfig.DemoVerdict = {
	potter = "ClayCrusher",
	rival = "KilnKing",
	roundNum = 3,
	totalRounds = 3,
	mode = "default",
	subs = { shape = 0.884, hollow = 0.792, glaze = 0.816, height = 0.945, accessories = 1.0 },
	rivalSubs = { shape = 0.802, hollow = 0.874, glaze = 0.744, height = 0.918, accessories = 0.5 },
}

PotteryDuelConfig.DemoCompetitors = {
	left = { name = "ClayCrusher", skill = 1284, title = "Kiln Keeper", wins = 1 },
	right = { name = "KilnKing", skill = 1197, title = "Rookie", wins = 0 },
}

return PotteryDuelConfig
