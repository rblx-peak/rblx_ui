--!strict
-- SPECTATOR chrome — HUD layer, non-exclusive. A bottom-centre strip: PREV /
-- NEXT arrow buttons flanking the spectated player card (round avatar, name,
-- a small live stat line, and a gold "2/6" position chip), then a FREE CAM
-- toggle (gold = active, doc §3.3 selection colour) and a red EXIT. A boxless
-- outlined "SPECTATING" tag floats at the top centre in ice blue — world-style
-- text, no box (doc §8 toast grammar).
--
-- Player switching calls the injected onSwitch(delta) AND cycles the local
-- index so the strip stays alive with no backend; Update(data) re-renders the
-- card from fresh data. The card is rebuilt per switch (headshot fetch runs
-- off-thread with the flat-cartoon icon as the resting art, doc §10).
--
-- Show(data) = { players, index, freecam, onSwitch, onFreecam, onExit }.

local Players = game:GetService("Players")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)

type SpectatedPlayer = { userId: number, name: string, kills: number?, deaths: number?, score: number? }

local WHITE = Color3.new(1, 1, 1)

-- Fixed px at the 1650×1020 baseline. Strip 760×96, bottom-centre.
local STRIP_W = 760
local STRIP_H = 96
local STRIP_Y = -18
local CARD_X = 76
local CARD_W = 360
local CARD_H = 72

local DEMO_PLAYERS: { SpectatedPlayer } = {
	{ userId = 1, name = "ClayCrusher", kills = 7, deaths = 2, score = 1240 },
	{ userId = 156, name = "KilnKing", kills = 5, deaths = 4, score = 980 },
	{ userId = 2, name = "GlazeGoblin", kills = 3, deaths = 1, score = 760 },
	{ userId = 3, name = "WheelWitch", kills = 9, deaths = 6, score = 1815 },
	{ userId = 1101, name = "MugMerchant", kills = 1, deaths = 5, score = 340 },
	{ userId = 55, name = "TerracottaTom", kills = 4, deaths = 4, score = 890 },
}

local function formatNumber(n: number): string
	local formatted = tostring(math.floor(n))
	while true do
		local replaced: number
		formatted, replaced = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return formatted
end

local function avatarCircle(theme: Types.UITheme, parent: Instance, userId: number, sizePx: number): Frame
	local holder = UIStyler.Frame("Avatar")
	holder.BackgroundColor3 = theme.Arcade.NearBlack
	holder.Size = UDim2.fromOffset(sizePx, sizePx)
	holder.ClipsDescendants = true
	UIChrome.Corner("Arcade", "Pill").Parent = holder
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = holder
	holder.Parent = parent

	local glyph = IconArchive.Image(holder, "player", math.floor(sizePx * 0.62))
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)

	local photo = Instance.new("ImageLabel")
	photo.Name = "Headshot"
	photo.BackgroundTransparency = 1
	photo.ScaleType = Enum.ScaleType.Crop
	photo.Size = UDim2.fromScale(1, 1)
	photo.Visible = false
	photo.Parent = holder

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and typeof(content) == "string" and content ~= "" and holder.Parent then
			photo.Image = content
			photo.Visible = true
			glyph.Visible = false
		end
	end)

	return holder
end

local SpectatorScreen = setmetatable({}, { __index = UIScreenBase })
SpectatorScreen.__index = SpectatorScreen

function SpectatorScreen.new()
	local self = UIScreenBase.new("SpectatorScreen", 3)
	self._players = DEMO_PLAYERS :: { SpectatedPlayer }
	self._index = 1
	self._freecam = false
	self._onSwitch = nil :: ((delta: number) -> ())?
	self._onFreecam = nil :: ((enabled: boolean) -> ())?
	self._onExit = nil :: (() -> ())?
	return setmetatable(self, SpectatorScreen)
end

function SpectatorScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function SpectatorScreen:_BuildContent()
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
	local theme = self:GetTheme()

	-- Boxless top tag (doc §8): outlined FredokaOne floating over the scene.
	local tag = UIChrome.Text("SpectatingTag", 28, theme.Arcade.IceBlue)
	tag.Text = "SPECTATING"
	tag.AnchorPoint = Vector2.new(0.5, 0)
	tag.Position = UDim2.new(0.5, 0, 0, 14)
	tag.Size = UDim2.fromOffset(360, 34)
	tag.Parent = self.Root
	self._tag = tag

	local strip = UIChrome.Panel(theme, "Arcade", "SpectatorStrip")
	strip.AnchorPoint = Vector2.new(0.5, 1)
	strip.Position = UDim2.new(0.5, 0, 1, STRIP_Y)
	strip.Size = UDim2.fromOffset(STRIP_W, STRIP_H)
	strip.Parent = self.Root
	self._strip = strip

	self._prevButton = UIButtonComponent.new()
	self._prevButton:Create(strip, {
		iconId = IconArchive.Id("arrowLeft"),
		variant = "Blue",
		size = UDim2.fromOffset(56, CARD_H),
		position = UDim2.fromOffset(12, 12),
		onClick = function()
			self:_Switch(-1)
		end,
	})

	-- The spectated player card: contents rebuilt per switch.
	local card = UIStyler.Frame("PlayerCard")
	card.BackgroundColor3 = theme.Arcade.NearBlack2
	card.BackgroundTransparency = 0
	card.Position = UDim2.fromOffset(CARD_X, 12)
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	UIChrome.Stroke(theme, "Arcade").Parent = card
	UIChrome.GlassGradient().Parent = card
	card.Parent = strip
	self._card = card

	self._nextButton = UIButtonComponent.new()
	self._nextButton:Create(strip, {
		iconId = IconArchive.Id("arrowRight"),
		variant = "Blue",
		size = UDim2.fromOffset(56, CARD_H),
		position = UDim2.fromOffset(444, 12),
		onClick = function()
			self:_Switch(1)
		end,
	})

	self._freecamButton = UIButtonComponent.new()
	self._freecamButton:Create(strip, {
		text = "FREE CAM",
		variant = "Ghost",
		size = UDim2.fromOffset(132, CARD_H),
		position = UDim2.fromOffset(512, 12),
		onClick = function()
			self:_ToggleFreecam()
		end,
	})

	self._exitButton = UIButtonComponent.new()
	self._exitButton:Create(strip, {
		text = self:_R("EXIT"),
		variant = "Red",
		size = UDim2.fromOffset(92, CARD_H),
		position = UDim2.fromOffset(656, 12),
		onClick = function()
			self:_Exit()
		end,
	})

	self:_RenderCard()
end

function SpectatorScreen:_Current(): SpectatedPlayer?
	return self._players[self._index]
end

function SpectatorScreen:_RenderCard()
	if self:LayoutKit() == "GP" then
		self:_GPRenderCard()
		return
	end
	local theme = self:GetTheme()
	local card = self._card :: Frame
	for _, child in card:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local player = self:_Current()
	if not player then
		local empty = UIChrome.Text("Empty", 18, theme.Arcade.GreyOwned)
		empty.Text = "NOBODY TO SPECTATE"
		empty.Size = UDim2.fromScale(1, 1)
		empty.Parent = card
		return
	end

	local avatar = avatarCircle(theme, card, player.userId, 52)
	avatar.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Position = UDim2.new(0, 10, 0.5, 0)

	local name = UIChrome.Text("Name", 22, WHITE)
	name.RichText = false
	name.Text = player.name
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(74, 8)
	name.Size = UDim2.fromOffset(CARD_W - 74 - 66, 26)
	name.Parent = card

	-- Small live stat line, ice blue secondary note (doc §3.2).
	local stats = UIChrome.Text("Stats", 15, theme.Arcade.IceBlue)
	stats.Text = string.format(
		"K %d  •  D %d  •  %s PTS",
		player.kills or 0,
		player.deaths or 0,
		formatNumber(player.score or 0)
	)
	stats.TextXAlignment = Enum.TextXAlignment.Left
	stats.Position = UDim2.fromOffset(74, 40)
	stats.Size = UDim2.fromOffset(CARD_W - 74 - 66, 20)
	stats.Parent = card

	local position = UIChrome.Text("Index", 15, theme.Arcade.Gold)
	position.Text = string.format("%d/%d", self._index, #self._players)
	position.TextXAlignment = Enum.TextXAlignment.Right
	position.AnchorPoint = Vector2.new(1, 0)
	position.Position = UDim2.new(1, -10, 0, 8)
	position.Size = UDim2.fromOffset(52, 20)
	position.Parent = card
end

function SpectatorScreen:_Switch(delta: number)
	if #self._players == 0 then
		self:_Toast("NOBODY TO SPECTATE", "Error")
		return
	end
	self._index = ((self._index - 1 + delta) % #self._players) + 1
	self:_RenderCard()
	UIChrome.Pulse(self:GetTheme(), self._card)
	if self._onSwitch then
		self._onSwitch(delta)
	end
end

function SpectatorScreen:_ToggleFreecam()
	self._freecam = not self._freecam
	self:_SyncFreecamButton()
	if self._onFreecam then
		self._onFreecam(self._freecam)
	end
	if self._freecam then
		self:_Toast("FREE CAM ON — FLY ANYWHERE", "Info")
	else
		local player = self:_Current()
		self:_Toast(if player then "FOLLOWING " .. string.upper(player.name) else "FREE CAM OFF", "Info")
	end
end

-- Gold = active (doc §3.3 selection colour); ghost = resting toggle.
function SpectatorScreen:_SyncFreecamButton()
	self._freecamButton:SetContent({
		text = "FREE CAM",
		variant = if self._freecam then "Gold" else "Ghost",
	})
end

function SpectatorScreen:_Exit()
	if self._onExit then
		self._onExit()
	end
	self:_Toast("SPECTATOR MODE CLOSED", "Info")
	self.ScreenController:HideScreen("spectator")
end

function SpectatorScreen:_Ingest(data: any?)
	if not data then
		return
	end
	if data.players then
		self._players = data.players
	end
	if data.index then
		self._index = math.clamp(data.index, 1, math.max(1, #self._players))
	end
	if data.freecam ~= nil then
		self._freecam = data.freecam == true
	end
	if data.onSwitch then
		self._onSwitch = data.onSwitch
	end
	if data.onFreecam then
		self._onFreecam = data.onFreecam
	end
	if data.onExit then
		self._onExit = data.onExit
	end
end

function SpectatorScreen:_OnShow(data: any?)
	self:_Ingest(data)
	self:_RenderCard()
	self:_SyncFreecamButton()
	UIChrome.PopIn(self:GetTheme(), self._strip)
end

function SpectatorScreen:Update(data: any)
	self:_Ingest(data)
	if self._built then
		self:_RenderCard()
		self:_SyncFreecamButton()
	end
end

-- ========================================================================
-- GP layout — THE VIEWING SHELF (theme.LayoutKit == "GP").
--
-- §6 anti-condescension, stated as an inventory: the Spectating tag, Prev,
-- Next, the player card with its headshot, name, FULL K / D / points stat line
-- and the "2/6" position chip, the Free cam toggle and Exit all survive, in the
-- same 760x96 strip at the same bottom-centre anchor and on the same px ladder.
-- Only the grammar is re-drawn: a cream plate with a scalloped lip instead of a
-- near-black panel, petal chips instead of arcade buttons, and the tag reading
-- as a soft rose pill rather than a black-outlined floating word — this pack
-- has no text outline to float with (Chrome.TextOutline = false), so a boxless
-- label over an arbitrary 3D scene would have nothing holding it up.
--
-- IMPROVISED LOCALLY (noted for the kit): GPLayoutKit ships no button builder
-- and UIButtonComponent branches GL, not GP, so `gpChip` below is this screen's
-- pack-correct chip button, returning the {Root, SetContent, Destroy} handle
-- _SyncFreecamButton and the teardown already call. `gpAvatar` exists because
-- the classic avatarCircle calls UIChrome.Stroke, which under this pack's
-- Chrome policy (StrokeFollowsAccent = false) resolves to a BLACK stroke and
-- breaks pack law 1.
-- ========================================================================

local GP_TAG_W = 220
local GP_TAG_H = 44
local GP_AVATAR = 52

-- Two passes of the pack's own hue-preserving Deepen: one leaves butter and
-- matcha near 3:1 on cream, two lands them past 6:1 while staying recognisably
-- that hue.
local function gpInk(theme: Types.UITheme, color: Color3): Color3
	return GPLayoutKit.Deepen(theme, GPLayoutKit.Deepen(theme, color, 1), 1)
end

-- Pack law 5: no all-caps copy. A FULLY uppercase string is re-cased; anything
-- already mixed-case (and every player name) passes through verbatim.
local function gpCopy(text: string): string
	if text == "" or string.find(text, "<", 1, true) or text ~= string.upper(text) then
		return text
	end
	return (string.gsub(string.lower(text), "(%a[\'%a]*)", function(word: string): string
		return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
	end))
end

local function gpIcon(theme: Types.UITheme, parent: Instance, key: string, sizePx: number, query: any?): GuiObject
	local icon = IconArchive.Image(parent, key, sizePx, query)
	if icon:IsA("TextLabel") then
		-- IconArchive's GLYPH fallback is born pure-white with a black text
		-- stroke — both banned by this pack.
		icon.TextColor3 = theme.Colors.TextPrimary
		icon.TextStrokeTransparency = 1
	end
	return icon
end

-- The GP headshot medallion: same fetch and same icon-first fallback chain as
-- avatarCircle above, with a soft deepened-tint rim in place of the black one.
local function gpAvatar(theme: Types.UITheme, parent: Instance, userId: number, sizePx: number): Frame
	local wellFill = theme.Colors.Surface
	local holder = UIStyler.Frame("Avatar")
	holder.BackgroundColor3 = wellFill
	holder.Size = UDim2.fromOffset(sizePx, sizePx)
	holder.ClipsDescendants = true
	holder.ZIndex = 3
	UIStyler.Corner(theme.Radii.Pill).Parent = holder
	holder.Parent = parent
	GPLayoutKit.SoftStroke(theme, holder, wellFill)

	local glyph = gpIcon(theme, holder, "player", math.floor(sizePx * 0.62))
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)

	local photo = Instance.new("ImageLabel")
	photo.Name = "Headshot"
	photo.BackgroundTransparency = 1
	photo.ScaleType = Enum.ScaleType.Crop
	photo.Size = UDim2.fromScale(1, 1)
	photo.Visible = false
	photo.Parent = holder

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and typeof(content) == "string" and content ~= "" and holder.Parent then
			photo.Image = content
			photo.Visible = true
			glyph.Visible = false
		end
	end)

	return holder
end

-- "Gold" is this screen's ACTIVE-toggle token and "Ghost" its resting one (see
-- _SyncFreecamButton, which is shared and stays byte-identical).
local function gpVariantFill(theme: Types.UITheme, variant: string?): Color3
	local map: { [string]: Color3 } = {
		Green = theme.Colors.Secondary,
		Red = theme.Colors.Error,
		Blue = theme.Arcade.Blue,
		Gold = theme.Arcade.Gold,
		Grey = theme.Arcade.GreyOwned,
		Rose = theme.Colors.Primary,
		Ghost = theme.Colors.Surface,
	}
	return map[variant or "Ghost"] or theme.Colors.Surface
end

-- The pack's chip button. The TextButton itself stays TRANSPARENT and the fill
-- lives on a petal chip child, because UIStyleEnforcer backstops any SOLID
-- GuiButton with a BLACK 2px stroke — pack law 1 broken on sight.
local function gpChip(theme: Types.UITheme, parent: Instance, props: any, sink: { any }?): any
	local handle: any = {}

	local root = Instance.new("TextButton")
	root.Name = "GPChip"
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.Size = props.size or UDim2.fromOffset(140, 44)
	root.Position = props.position or UDim2.new()
	root.AnchorPoint = props.anchorPoint or Vector2.new(0, 0)
	root.ZIndex = props.zIndex or 4
	root.Parent = parent

	local fill = gpVariantFill(theme, props.variant)
	local chip = UIStyler.Frame("Chip")
	chip.BackgroundColor3 = fill
	chip.Size = UDim2.fromScale(1, 1)
	chip.ZIndex = root.ZIndex
	chip.Parent = root
	GPLayoutKit.Petal(theme, chip, props.petalIndex or 0)
	local stroke = GPLayoutKit.SoftStroke(theme, chip, fill)
	local shadow = GPLayoutKit.Shadow(theme, chip, "sm", sink, fill)

	local icon: GuiObject? = nil
	if props.iconKey then
		icon = gpIcon(theme, chip, props.iconKey, props.iconPx or 26)
		local img = icon :: GuiObject
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.ZIndex = root.ZIndex + 1
	end

	-- Ink on every pastel: TextOnPrimary (near-white) measures 2.14:1 on rose
	-- and is not legal for a control label.
	local label = GPLayoutKit.Text(theme, theme.TextSizes.Button, theme.Colors.TextPrimary, "Label")
	label.Text = gpCopy(props.text or "")
	label.RichText = false
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Size = UDim2.fromScale(1, 1)
	label.Visible = props.text ~= nil and props.text ~= ""
	label.ZIndex = root.ZIndex + 1
	label.Parent = chip

	local function paint(variant: string?, dimmed: boolean?)
		local nextFill = gpVariantFill(theme, variant)
		chip.BackgroundColor3 = nextFill
		chip.BackgroundTransparency = if dimmed then 0.45 else 0
		stroke.Color = GPLayoutKit.Deepen(theme, nextFill, 1)
		stroke.Transparency = if dimmed then 0.6 else 0.35
		shadow.Instance.Color = GPLayoutKit.Deepen(theme, nextFill, 1)
		shadow:SetEnabled(not dimmed)
		label.TextTransparency = if dimmed then 0.35 else 0
	end

	local variant = props.variant
	paint(variant, props.dimmed)
	if props.onClick then
		root.Activated:Connect(props.onClick)
	end
	UIChrome.Animate(theme, root, chip)

	handle.Root = root
	handle.chip = chip
	handle.label = label
	handle.shadow = shadow
	handle.SetContent = function(_self: any, next: any)
		if next.text ~= nil then
			label.Text = gpCopy(next.text)
			label.Visible = next.text ~= ""
		end
		if next.variant ~= nil then
			variant = next.variant
		end
		paint(variant, next.dimmed)
	end
	handle.Destroy = function(_self: any)
		shadow:Release()
		if root.Parent then
			root:Destroy()
		end
	end
	return handle
end

function SpectatorScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	self._gpShadows = {}

	-- The tag: a rose pill with a scalloped foot. This pack has no text outline
	-- to float a boxless word over the scene with, so the word gets a plate.
	local tagFill = theme.Colors.Primary
	local tag = UIStyler.Frame("SpectatingTag")
	tag.BackgroundColor3 = tagFill
	tag.AnchorPoint = Vector2.new(0.5, 0)
	tag.Position = UDim2.new(0.5, 0, 0, 14)
	tag.Size = UDim2.fromOffset(GP_TAG_W, GP_TAG_H)
	tag.Parent = self.Root
	GPLayoutKit.CornerSet(theme, tag, "Tab")
	GPLayoutKit.SoftStroke(theme, tag, tagFill)
	GPLayoutKit.Shadow(theme, tag, "sm", self._gpShadows, tagFill)
	GPLayoutKit.Scallop(theme, tag, "Bottom", tagFill)
	self._tag = tag

	local tagLabel = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Label")
	tagLabel.Text = "Spectating"
	tagLabel.Size = UDim2.fromScale(1, 1)
	tagLabel.ZIndex = 3
	tagLabel.Parent = tag

	local stripFill = theme.Colors.Background
	local strip = UIStyler.Frame("SpectatorStrip")
	strip.BackgroundColor3 = stripFill
	strip.AnchorPoint = Vector2.new(0.5, 1)
	strip.Position = UDim2.new(0.5, 0, 1, STRIP_Y)
	strip.Size = UDim2.fromOffset(STRIP_W, STRIP_H)
	strip.Parent = self.Root
	GPLayoutKit.Petal(theme, strip, 0)
	GPLayoutKit.SoftStroke(theme, strip, stripFill)
	GPLayoutKit.Shadow(theme, strip, "lg", self._gpShadows, stripFill)
	-- Scallop "Top" rotates its strip, and a rotated descendant is not clipped
	-- by an ancestor — safe here because self.Root never clips and the lip sits
	-- inside the screen (GPLayoutKit's clipping caveat).
	GPLayoutKit.Scallop(theme, strip, "Top", stripFill)
	self._strip = strip

	self._prevButton = gpChip(theme, strip, {
		iconKey = "arrowLeft",
		variant = "Rose",
		size = UDim2.fromOffset(56, CARD_H),
		position = UDim2.fromOffset(12, 12),
		onClick = function()
			self:_Switch(-1)
		end,
	}, self._gpShadows)

	-- The spectated player card: contents rebuilt per switch.
	local cardFill = theme.Colors.SurfaceRaised
	local card = UIStyler.Frame("PlayerCard")
	card.BackgroundColor3 = cardFill
	card.BackgroundTransparency = 0
	card.Position = UDim2.fromOffset(CARD_X, 12)
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.ZIndex = 2
	card.Parent = strip
	GPLayoutKit.Petal(theme, card, 1)
	GPLayoutKit.SoftStroke(theme, card, cardFill)
	GPLayoutKit.Shadow(theme, card, "sm", self._gpShadows, cardFill)
	self._card = card

	self._nextButton = gpChip(theme, strip, {
		iconKey = "arrowRight",
		variant = "Rose",
		size = UDim2.fromOffset(56, CARD_H),
		position = UDim2.fromOffset(444, 12),
		petalIndex = 1,
		onClick = function()
			self:_Switch(1)
		end,
	}, self._gpShadows)

	self._freecamButton = gpChip(theme, strip, {
		text = "FREE CAM",
		variant = "Ghost",
		size = UDim2.fromOffset(132, CARD_H),
		position = UDim2.fromOffset(512, 12),
		onClick = function()
			self:_ToggleFreecam()
		end,
	}, self._gpShadows)

	self._exitButton = gpChip(theme, strip, {
		text = self:_R("EXIT"),
		variant = "Red",
		size = UDim2.fromOffset(92, CARD_H),
		position = UDim2.fromOffset(656, 12),
		petalIndex = 1,
		onClick = function()
			self:_Exit()
		end,
	}, self._gpShadows)

	self:_RenderCard()
end

-- Every reading the classic card carries: headshot, name, the full K / D /
-- points stat line and the position chip. Nothing is folded away.
function SpectatorScreen:_GPRenderCard()
	local theme = self:GetTheme()
	local card = self._card :: Frame
	for _, child in card:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local player = self:_Current()
	if not player then
		local empty = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Empty")
		empty.Text = "Nobody to spectate"
		empty.Size = UDim2.fromScale(1, 1)
		empty.ZIndex = 3
		empty.Parent = card
		return
	end

	local avatar = gpAvatar(theme, card, player.userId, GP_AVATAR)
	avatar.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Position = UDim2.new(0, 10, 0.5, 0)

	local name = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Name")
	name.RichText = false
	name.Text = player.name -- a player NAME is data, not copy
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(74, 8)
	name.Size = UDim2.fromOffset(CARD_W - 74 - 66, 26)
	name.ZIndex = 3
	name.Parent = card

	local stats = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Stats")
	stats.Text = string.format(
		"K %d  •  D %d  •  %s pts",
		player.kills or 0,
		player.deaths or 0,
		formatNumber(player.score or 0)
	)
	stats.TextXAlignment = Enum.TextXAlignment.Left
	stats.Position = UDim2.fromOffset(74, 40)
	stats.Size = UDim2.fromOffset(CARD_W - 74 - 66, 20)
	stats.ZIndex = 3
	stats.Parent = card

	local position = GPLayoutKit.NumberText(theme, theme.TextSizes.Small, gpInk(theme, theme.Colors.Accent), "Index")
	position.Text = string.format("%d/%d", self._index, #self._players)
	position.AnchorPoint = Vector2.new(1, 0)
	position.Position = UDim2.new(1, -10, 0, 8)
	position.Size = UDim2.fromOffset(52, 20)
	position.ZIndex = 3
	position.Parent = card
end

-- A STYLE REBUILD runs this hook and then throws the shell away, so the
-- component teardown Destroy already did lives here now and Destroy delegates —
-- previously a style swap dropped the button components on the floor. Shadow
-- handles are budget-registered: a destroyed GuiObject alone leaves the counter
-- high.
function SpectatorScreen:_OnTeardown()
	if self._prevButton then
		self._prevButton:Destroy()
		self._prevButton = nil
	end
	if self._nextButton then
		self._nextButton:Destroy()
		self._nextButton = nil
	end
	if self._freecamButton then
		self._freecamButton:Destroy()
		self._freecamButton = nil
	end
	if self._exitButton then
		self._exitButton:Destroy()
		self._exitButton = nil
	end
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
end

function SpectatorScreen:Destroy()
	self:_OnTeardown()
	UIScreenBase.Destroy(self)
end

return SpectatorScreen
