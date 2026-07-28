--!strict
-- Skill tree — Pottery Clash arcade family (doc §7.4). One modal card holds a
-- node graph on the left and a detail panel on the right; the available-points
-- chip lives in the red header bar next to the close X.
--
-- The graph is authored, not solved: every node carries its own px CENTRE
-- (x, y) in the data, and each connector is a thin Frame rotated to face its
-- parent — length = |child − parent|, Rotation = atan2(dy, dx) in degrees,
-- positioned at the midpoint with AnchorPoint (0.5, 0.5). That keeps the whole
-- graph in the fixed-px 1650×1020 baseline with no layout engine involved.
--
-- Node states follow the doc's language: UNLOCKED wears the solid gold ring
-- with the golden icon and a green check, AVAILABLE wears a PULSING gold ring
-- (§4.3 selection-is-a-ring, §5.4 visibility-gated), LOCKED is the near-black
-- well dimmed in place behind the lock mark — dimmed, never removed (§11.2),
-- and every tap still answers (§11.1).

local RunService = game:GetService("RunService")

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPStudioKit = require(script.Parent.Parent.Framework.GPStudioKit)
local UITicker = require(script.Parent.Parent.Framework.UITicker)

type Node = {
	id: string,
	name: string,
	description: string?,
	icon: string?,
	x: number,
	y: number,
	cost: number,
	state: string, -- "unlocked" | "available" | "locked"
	requires: { string },
}

local CARD_W, CARD_H = 1300, 740
local CONTENT_W = CARD_W - 28
local CONTENT_H = CARD_H - 88
local DETAIL_W = 376
local CANVAS_W = CONTENT_W - DETAIL_W - 16
local NODE = 88
local CONNECTOR_THICKNESS = 4
local SCROLLBAR = 8

-- Authored graph: x/y are the node CENTRES in px at the 1650×1020 baseline,
-- laid on a 220px column / 120px row grid that centres inside the canvas.
local DEMO_NODES: { Node } = {
	{ id = "centering", name = "CENTERING", description = "The first lesson: a lump that will not centre will never hold a wall. Wheel speed control unlocked.", icon = "target", x = 440, y = 70, cost = 1, state = "unlocked", requires = {} },

	{ id = "pull", name = "TALL PULLS", description = "Raise a wall two centimetres higher per pull without thinning it.", icon = "arrowUp", x = 220, y = 190, cost = 1, state = "unlocked", requires = { "centering" } },
	{ id = "trim", name = "CLEAN TRIM", description = "Trim a leather-hard foot without chattering the surface.", icon = "sword", x = 440, y = 190, cost = 1, state = "available", requires = { "centering" } },
	{ id = "kiln", name = "KILN SENSE", description = "Read the cone by eye. Firings finish 10% faster.", icon = "fire", x = 660, y = 190, cost = 1, state = "available", requires = { "centering" } },

	{ id = "handles", name = "PULLED HANDLES", description = "Handles that survive the drying rack. Mugs sell for 15% more.", icon = "hammer", x = 220, y = 310, cost = 2, state = "locked", requires = { "pull" } },
	{ id = "lids", name = "FITTED LIDS", description = "Lids that seat first try. Unlocks the jar family.", icon = "shield", x = 440, y = 310, cost = 2, state = "locked", requires = { "trim" } },
	{ id = "reduction", name = "REDUCTION FIRE", description = "Starve the kiln of oxygen for the deep cobalt blues.", icon = "bolt", x = 660, y = 310, cost = 2, state = "locked", requires = { "kiln" } },

	{ id = "throwing_big", name = "BIG FORMS", description = "Throw over ten kilos in one piece. Urns, planters, the gallery commissions.", icon = "crate", x = 220, y = 430, cost = 3, state = "locked", requires = { "handles" } },
	{ id = "carving", name = "CARVED RELIEF", description = "Cut pattern into leather-hard walls without breaking through.", icon = "sparkle", x = 440, y = 430, cost = 3, state = "locked", requires = { "lids" } },
	{ id = "crystalline", name = "CRYSTAL GLAZE", description = "Grow zinc crystals in the glaze on the cooling ramp. Rare finishes.", icon = "crystal", x = 660, y = 430, cost = 3, state = "locked", requires = { "reduction" } },

	{ id = "master", name = "MASTER POTTER", description = "Everything the booth can teach. Doubles the value of every finished piece.", icon = "crown", x = 440, y = 550, cost = 5, state = "locked", requires = { "throwing_big", "carving", "crystalline" } },
}

local function tintIcon(icon: GuiObject, color: Color3)
	if icon:IsA("ImageLabel") then
		icon.ImageColor3 = color
	elseif icon:IsA("TextLabel") then
		icon.TextColor3 = color
	end
end

local function dimIcon(icon: GuiObject, transparency: number)
	if icon:IsA("ImageLabel") then
		icon.ImageTransparency = transparency
	elseif icon:IsA("TextLabel") then
		icon.TextTransparency = transparency
	end
end

local SkillTreeScreen = setmetatable({}, { __index = UIScreenBase })
SkillTreeScreen.__index = SkillTreeScreen

function SkillTreeScreen.new()
	local self = UIScreenBase.new("SkillTreeScreen", 6)
	self._points = 4
	self._nodes = DEMO_NODES
	self._selectedId = "trim"
	self._nodeViews = {} :: { { node: Node, surface: Frame, stroke: UIStroke } }
	self._pulseRings = {} :: { UIStroke }
	self._detailComponents = {} :: { any }
	self._tickConn = nil :: RBXScriptConnection?
	self._phase = 0
	return setmetatable(self, SkillTreeScreen)
end

function SkillTreeScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function SkillTreeScreen:_Node(id: string): Node?
	for _, node in self._nodes do
		if node.id == id then
			return node
		end
	end
	return nil
end

-- A node whose prerequisites are all unlocked becomes AVAILABLE; anything else
-- that isn't already unlocked falls back to LOCKED. Runs after every unlock so
-- the graph opens up as the player spends points.
function SkillTreeScreen:_Recompute()
	for _, node in self._nodes do
		if node.state ~= "unlocked" then
			local ready = true
			for _, requirement in node.requires do
				local parent = self:_Node(requirement)
				if not parent or parent.state ~= "unlocked" then
					ready = false
					break
				end
			end
			node.state = ready and "available" or "locked"
		end
	end
end

function SkillTreeScreen:_BuildContent()
	-- GP layout language: the matte apprenticeship board (see _BuildGPLayout
	-- below); the classic arcade modal build stays untouched.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "SKILL TREE",
		sizePx = Vector2.new(CARD_W, CARD_H),
		onClose = function()
			self.ScreenController:HideScreen("skillTree")
		end,
	})
	self._modal = modal
	local content = modal.content

	-- Points chip in the 64px header bar, tucked left of the close X — the
	-- currency-pill recipe (§8) at header scale.
	local chip = UIStyler.Frame("Points")
	chip.BackgroundColor3 = theme.Arcade.NearBlack
	chip.BackgroundTransparency = 0
	chip.AnchorPoint = Vector2.new(1, 0.5)
	chip.Position = UDim2.new(1, -68, 0.5, 0)
	chip.Size = UDim2.fromOffset(210, 44)
	chip.ZIndex = 43
	UIChrome.Stroke(theme, "Arcade").Parent = chip
	UIChrome.GlassGradient().Parent = chip
	chip.Parent = modal.header

	local chipIcon = IconArchive.Image(chip, "star", 30, { golden = true })
	chipIcon.AnchorPoint = Vector2.new(0, 0.5)
	chipIcon.Position = UDim2.new(0, 8, 0.5, 0)
	chipIcon.ZIndex = 44

	local pointsLabel = UIChrome.Text("Value", 22, theme.Arcade.Gold)
	pointsLabel.TextXAlignment = Enum.TextXAlignment.Left
	pointsLabel.Position = UDim2.fromOffset(46, 0)
	pointsLabel.Size = UDim2.new(1, -52, 1, 0)
	pointsLabel.ZIndex = 44
	pointsLabel.Parent = chip
	self._pointsLabel = pointsLabel

	-- Graph canvas.
	local canvas = Instance.new("ScrollingFrame")
	canvas.Name = "Graph"
	canvas.BackgroundColor3 = theme.Arcade.NearBlack
	canvas.BackgroundTransparency = 0.25
	canvas.BorderSizePixel = 0
	canvas.Size = UDim2.fromOffset(CANVAS_W, CONTENT_H)
	canvas.ScrollingDirection = Enum.ScrollingDirection.XY
	canvas.ScrollBarThickness = SCROLLBAR
	canvas.ScrollBarImageColor3 = theme.Arcade.Gold
	canvas.Parent = content
	UIChrome.Stroke(theme, "Arcade").Parent = canvas
	self._canvas = canvas

	-- Detail panel.
	local detail = UIChrome.Panel(theme, "Arcade", "Detail")
	detail.Position = UDim2.fromOffset(CANVAS_W + 16, 0)
	detail.Size = UDim2.fromOffset(DETAIL_W, CONTENT_H)
	detail.Parent = content
	self._detail = detail

	local detailBody = Instance.new("ScrollingFrame")
	detailBody.Name = "DetailBody"
	detailBody.BackgroundTransparency = 1
	detailBody.BorderSizePixel = 0
	detailBody.Position = UDim2.fromOffset(16, 16)
	detailBody.Size = UDim2.new(1, -32, 1, -(16 + 16 + 60))
	detailBody.CanvasSize = UDim2.new()
	detailBody.AutomaticCanvasSize = Enum.AutomaticSize.Y
	detailBody.ScrollingDirection = Enum.ScrollingDirection.Y
	detailBody.ScrollBarThickness = 6
	detailBody.ScrollBarImageColor3 = theme.Arcade.Gold
	detailBody.Parent = detail
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 8),
	}).Parent = detailBody
	self._detailBody = detailBody

	local actionSlot = UIStyler.Frame("Action")
	actionSlot.BackgroundTransparency = 1
	actionSlot.AnchorPoint = Vector2.new(0, 1)
	actionSlot.Position = UDim2.new(0, 16, 1, -14)
	actionSlot.Size = UDim2.new(1, -32, 0, 48)
	actionSlot.Parent = detail
	self._actionSlot = actionSlot

	self:_Recompute()
	self:_RenderGraph()
	self:_RenderPoints()
	self:_RenderDetail()
end

function SkillTreeScreen:_RenderPoints()
	if self:LayoutKit() == "GP" then
		self._gpPointsChip.SetText(string.format("%d point%s", self._points, self._points == 1 and "" or "s"))
		return
	end
	self._pointsLabel.Text = string.format("%d POINTS", self._points)
end

function SkillTreeScreen:_RenderGraph()
	if self:LayoutKit() == "GP" then
		self:_GPRenderGraph()
		return
	end
	table.clear(self._nodeViews)
	table.clear(self._pulseRings)
	for _, child in self._canvas:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local maxX, maxY = 0, 0
	for _, node in self._nodes do
		maxX = math.max(maxX, node.x)
		maxY = math.max(maxY, node.y)
	end
	-- Canvas extent covers the right-most node's name label (which is wider
	-- than the node) and the bottom row's label strip.
	self._canvas.CanvasSize = UDim2.fromOffset(maxX + NODE, maxY + 80)

	-- Connectors first so every node paints over them.
	for _, node in self._nodes do
		for _, requirement in node.requires do
			local parent = self:_Node(requirement)
			if parent then
				self:_BuildConnector(parent, node)
			end
		end
	end
	for _, node in self._nodes do
		self:_BuildNode(node)
	end
	-- Nothing selected yet (or the selection vanished with new data).
	if not self:_Node(self._selectedId or "") then
		self._selectedId = self._nodes[1] and self._nodes[1].id or nil
	end
	self:_HighlightSelection()
end

function SkillTreeScreen:_BuildConnector(parent: Node, child: Node)
	local theme = self:GetTheme()
	local dx, dy = child.x - parent.x, child.y - parent.y
	local length = math.sqrt(dx * dx + dy * dy)

	local line = UIStyler.Frame("Link_" .. parent.id .. "_" .. child.id)
	line.BorderSizePixel = 0
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromOffset((parent.x + child.x) // 2, (parent.y + child.y) // 2)
	line.Size = UDim2.fromOffset(math.floor(length), CONNECTOR_THICKNESS)
	line.Rotation = math.deg(math.atan2(dy, dx))
	line.ZIndex = 1
	if child.state == "unlocked" then
		line.BackgroundColor3 = theme.Arcade.SunburstGold
		line.BackgroundTransparency = 0.1
	elseif child.state == "available" then
		line.BackgroundColor3 = theme.Arcade.SunburstGold
		line.BackgroundTransparency = 0.55
	else
		line.BackgroundColor3 = theme.Arcade.RulerTick
		line.BackgroundTransparency = 0.75
	end
	line.Parent = self._canvas
end

function SkillTreeScreen:_BuildNode(node: Node)
	local theme = self:GetTheme()

	local root = UIStyler.Frame("Node_" .. node.id)
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromOffset(node.x, node.y)
	root.Size = UDim2.fromOffset(NODE, NODE)
	root.ZIndex = 2
	root.Parent = self._canvas

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 2
	hit.Parent = root

	local surface = UIStyler.Frame("Surface")
	surface.BackgroundColor3 = node.state == "unlocked" and theme.Arcade.Row or theme.Arcade.NearBlack
	surface.BackgroundTransparency = node.state == "locked" and 0.5 or 0
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 3
	local ringed = node.state ~= "locked"
	local stroke = UIChrome.Stroke(theme, "Arcade", ringed and "Selection" or "Panel")
	stroke.Parent = surface
	UIChrome.GlassGradient().Parent = surface
	surface.Parent = root
	if node.state == "available" then
		table.insert(self._pulseRings, stroke)
	end

	local icon = IconArchive.Image(surface, node.icon or "star", 48, { golden = node.state == "unlocked" })
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 4
	if node.state == "locked" then
		dimIcon(icon, 0.6)
		local lock = IconArchive.Image(surface, "lock", 26)
		lock.AnchorPoint = Vector2.new(0.5, 1)
		lock.Position = UDim2.new(0.5, 0, 1, -4)
		lock.ZIndex = 5
	elseif node.state == "unlocked" then
		local check = IconArchive.Image(surface, "check", 22)
		check.AnchorPoint = Vector2.new(1, 1)
		check.Position = UDim2.new(1, -3, 1, -3)
		check.ZIndex = 5
		tintIcon(check, theme.Arcade.Green)
	end

	-- Name sits under the node so the graph reads without hovering.
	local name = UIChrome.Text("Name", 13, node.state == "locked" and theme.Arcade.GreyOwned or theme.Colors.TextPrimary)
	name.Text = node.name
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.new(0.5, 0, 1, 4)
	name.Size = UDim2.fromOffset(150, 18)
	name.RichText = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 3
	name.Parent = root

	hit.Activated:Connect(function()
		self._selectedId = node.id
		self:_HighlightSelection()
		self:_RenderDetail()
	end)
	-- Animate LAST, after the final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, hit, surface)

	table.insert(self._nodeViews, { node = node, surface = surface, stroke = stroke })
end

-- Selection thickens the node's ring, so the graph never changes fill colour
-- under the hover spring (doc §4.3). AVAILABLE rings are left alone — the
-- pulse ticker owns their thickness, and the breathing already marks them.
-- Thickness rides the active style's stroke weight (Classic 3 → 5 selected;
-- hairline styles keep their thin resting weight and bump by the same +2).
function SkillTreeScreen:_HighlightSelection()
	local base = UIChrome.ActiveChrome().StrokeThickness
	local gp = self:LayoutKit() == "GP"
	for _, view in self._nodeViews do
		if view.node.state ~= "available" then
			-- Under GP an UNLOCKED node already wears a 3px matcha ring, so
			-- selection thickens from THAT resting weight: the ring must never
			-- come out thinner than the state it is reporting.
			local rest = if gp and view.node.state == "unlocked" then 3 else base
			view.stroke.Thickness = if view.node.id == self._selectedId then rest + 2 else rest
		end
	end
end

function SkillTreeScreen:_RenderDetail()
	if self:LayoutKit() == "GP" then
		self:_GPRenderDetail()
		return
	end
	local theme = self:GetTheme()
	for _, component in self._detailComponents do
		component:Destroy()
	end
	table.clear(self._detailComponents)
	for _, child in self._detailBody:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, child in self._actionSlot:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local node = self:_Node(self._selectedId or "")
	if not node then
		local empty = UIChrome.Text("Empty", 20, theme.Arcade.GreyOwned)
		empty.Text = "SELECT A SKILL"
		empty.Size = UDim2.new(1, 0, 0, 60)
		empty.Parent = self._detailBody
		return
	end

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local head = UIStyler.Frame("Head")
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, -6, 0, 56)
	head.LayoutOrder = nextOrder()
	head.Parent = self._detailBody

	local headIcon = IconArchive.Image(head, node.icon or "star", 48, { golden = node.state == "unlocked" })
	headIcon.AnchorPoint = Vector2.new(0, 0.5)
	headIcon.Position = UDim2.new(0, 0, 0.5, 0)

	local title = UIChrome.Text("Title", 24, theme.Arcade.Gold)
	title.Text = node.name
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(60, 0)
	title.Size = UDim2.new(1, -60, 1, 0)
	title.RichText = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = head

	local stateColors: { [string]: Color3 } = {
		unlocked = theme.Arcade.Green,
		available = theme.Arcade.SunburstGold,
		locked = theme.Arcade.GreyOwned,
	}
	local state = UIChrome.Text("State", 17, stateColors[node.state] or theme.Arcade.Gold)
	state.Text = string.upper(node.state)
	state.TextXAlignment = Enum.TextXAlignment.Left
	state.Size = UDim2.new(1, -6, 0, 22)
	state.LayoutOrder = nextOrder()
	state.Parent = self._detailBody

	local description = UIChrome.BodyText("Description", 15, theme.Colors.TextPrimary)
	description.Text = node.description or ""
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.Size = UDim2.new(1, -6, 0, 0)
	description.AutomaticSize = Enum.AutomaticSize.Y
	description.TextWrapped = true
	description.LayoutOrder = nextOrder()
	description.Parent = self._detailBody

	local costRow = UIStyler.Frame("Cost")
	costRow.BackgroundTransparency = 1
	costRow.Size = UDim2.new(1, -6, 0, 34)
	costRow.LayoutOrder = nextOrder()
	costRow.Parent = self._detailBody

	local costIcon = IconArchive.Image(costRow, "star", 26, { golden = true })
	costIcon.AnchorPoint = Vector2.new(0, 0.5)
	costIcon.Position = UDim2.new(0, 0, 0.5, 0)

	local costText = UIChrome.Text("CostText", 20, theme.Arcade.SunburstGold)
	costText.Text = string.format("%d POINT%s", node.cost, node.cost == 1 and "" or "S")
	costText.TextXAlignment = Enum.TextXAlignment.Left
	costText.Position = UDim2.fromOffset(34, 0)
	costText.Size = UDim2.new(1, -34, 1, 0)
	costText.Parent = costRow

	local prereqHeader = UIChrome.Text("PrereqHeader", 18, theme.Arcade.Gold)
	prereqHeader.Text = "PREREQUISITES"
	prereqHeader.TextXAlignment = Enum.TextXAlignment.Left
	prereqHeader.Size = UDim2.new(1, -6, 0, 28)
	prereqHeader.LayoutOrder = nextOrder()
	prereqHeader.Parent = self._detailBody

	if #node.requires == 0 then
		local none = UIChrome.BodyText("NoPrereq", 15, theme.Arcade.GreyOwned)
		none.Text = "None — this is a root skill."
		none.TextXAlignment = Enum.TextXAlignment.Left
		none.Size = UDim2.new(1, -6, 0, 24)
		none.LayoutOrder = nextOrder()
		none.Parent = self._detailBody
	end

	for _, requirement in node.requires do
		local parent = self:_Node(requirement)
		local row = UIStyler.Frame("Prereq_" .. requirement)
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, -6, 0, 28)
		row.LayoutOrder = nextOrder()
		row.Parent = self._detailBody

		local met = parent ~= nil and parent.state == "unlocked"
		local mark = IconArchive.Image(row, met and "check" or "lock", 20)
		mark.AnchorPoint = Vector2.new(0, 0.5)
		mark.Position = UDim2.new(0, 0, 0.5, 0)
		tintIcon(mark, met and theme.Arcade.Green or theme.Arcade.GreyOwned)

		local text = UIChrome.BodyText("Text", 15, met and theme.Arcade.GreyOwned or theme.Colors.TextPrimary)
		text.Text = parent and parent.name or requirement
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.Position = UDim2.fromOffset(30, 0)
		text.Size = UDim2.new(1, -30, 1, 0)
		text.RichText = false
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text.Parent = row
	end

	-- UNLOCK dims in place when it can't be afforded/reached; the tap still
	-- plays the full press juice and then explains (doc §11.1).
	local affordable = self._points >= node.cost
	local action = UIButtonComponent.new()
	if node.state == "unlocked" then
		action:Create(self._actionSlot, {
			text = "UNLOCKED",
			variant = "Grey",
			enabled = false,
			size = UDim2.new(1, 0, 0, 48),
		})
	else
		action:Create(self._actionSlot, {
			text = "UNLOCK",
			variant = "Green",
			dimmed = not (affordable and node.state == "available"),
			size = UDim2.new(1, 0, 0, 48),
			onClick = function()
				self:_Unlock(node)
			end,
		})
	end
	table.insert(self._detailComponents, action)
end

function SkillTreeScreen:_Unlock(node: Node)
	if node.state == "unlocked" then
		self:_Toast("Already unlocked.", "Info")
		return
	end
	if node.state == "locked" then
		self:_Toast("Unlock its prerequisites first.", "Error")
		return
	end
	if self._points < node.cost then
		self:_Toast(string.format("Not enough skill points — %s needs %d.", node.name, node.cost), "Error")
		return
	end
	self._points -= node.cost
	node.state = "unlocked"
	self:_Recompute()
	self:_RenderPoints()
	self:_RenderGraph()
	self:_RenderDetail()
	self:_Toast(node.name .. " unlocked.", "Success")
	for _, view in self._nodeViews do
		if view.node.id == node.id then
			UIChrome.Pulse(self:GetTheme(), view.surface)
		end
	end
end

-- The AVAILABLE rings breathe on sin(t) through ONE visibility-gated
-- RenderStepped connection (doc §5.4), dropped on hide.
function SkillTreeScreen:_StartTicker()
	-- GP runs its ambient work on the ONE shared Heartbeat (UITicker); a
	-- per-screen RunService connection is a rejected pattern under this pack.
	if self:LayoutKit() == "GP" then
		self:_GPStartTicker()
		return
	end
	if self._tickConn then
		return
	end
	self._tickConn = RunService.RenderStepped:Connect(function(dt: number)
		local card = self._modal and self._modal.card
		if not card or not UIChrome.IsOnScreen(card) then
			return
		end
		self._phase += dt
		local breathe = 0.5 + 0.5 * math.sin(self._phase * 3)
		for index = #self._pulseRings, 1, -1 do
			local ring = self._pulseRings[index]
			if ring.Parent then
				ring.Thickness = 3 + 2.5 * breathe
				ring.Transparency = 0.3 * (1 - breathe)
			else
				table.remove(self._pulseRings, index)
			end
		end
	end)
end

function SkillTreeScreen:_StopTicker()
	if self._gpTickerStop then
		self._gpTickerStop()
		self._gpTickerStop = nil
	end
	if self._tickConn then
		self._tickConn:Disconnect()
		self._tickConn = nil
	end
end

function SkillTreeScreen:_Apply(data: any)
	if data.points ~= nil then
		self._points = data.points
	end
	if data.nodes then
		self._nodes = data.nodes
		self._selectedId = nil
	end
	self:_Recompute()
end

-- _EnsureBuilt has already rendered with the data the screen was holding, so
-- only a fresh payload re-renders here.
function SkillTreeScreen:_OnShow(data: any?)
	if data then
		self:_Apply(data)
		self:_RenderGraph()
		self:_RenderPoints()
		self:_RenderDetail()
	end
	self:_StartTicker()
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function SkillTreeScreen:_OnHide()
	self:_StopTicker()
end

function SkillTreeScreen:Update(data: any)
	if not data then
		return
	end
	self:_Apply(data)
	if self._built then
		self:_RenderGraph()
		self:_RenderPoints()
		self:_RenderDetail()
	end
end

-- ========================================================================
-- GP layout (theme.LayoutKit == "GP") — THE APPRENTICESHIP BOARD, in the
-- pack's MATTE dialect: cream paper, clay speckle, sage hairlines.
--
-- ANTI-CONDESCENSION LEDGER — every reading the arcade page carries:
--   the points chip in the header · EVERY node at its authored px centre,
--   with its icon, its three states (unlocked ring + check, available
--   breathing ring, locked dim + lock mark) and its name label · EVERY
--   parent→child link · the detail pane's icon, title, state line, full
--   description, cost row, "prerequisites" header, one row PER prerequisite
--   with its met/unmet mark, the root-skill line when there are none, and
--   the UNLOCK / UNLOCKED action with its dimmed-but-still-answering rule.
-- ADDED: the detail pane now names the cost against what you HAVE
-- ("2 points · you have 4"), which the arcade build leaves the player to
-- read off the header chip.
--
-- CONNECTORS ARE ELBOWS, NOT ROTATED BARS, and that is structural rather
-- than decorative: ClipsDescendants is axis-aligned and does NOT clip
-- ROTATED descendants, so the arcade build's single rotated connector Frame
-- would render straight through the scrolling canvas's edge — the exact
-- leaking-content bug this codebase has been bitten by before. Two or three
-- axis-aligned pill segments draw the SAME link, clip correctly, and read as
-- the soft right angle this pack wants anyway.
--
-- BUDGET NOTE: nodes and connectors are SHADOWLESS. The graph is
-- caller-supplied and a shadow per node would scale straight into the
-- engine's on-screen budget; depth here comes from the petal plates.
-- ========================================================================

local GP_PAGE = Vector2.new(CARD_W, CARD_H + 48)
local GP_DETAIL_W = DETAIL_W
local GP_CANVAS_W = CONTENT_W - GP_DETAIL_W - 16
local GP_LINK = 6
local GP_NODE = NODE
local GP_ACTION_H = 52
local GP_SCROLL_PAD = 12

function SkillTreeScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	local spacing = theme.Spacing

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Skill Tree",
		subtitleText = "Everything the booth can teach, and the order it teaches it in.",
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("skillTree")
		end,
	})
	self._gpShadows = page.shadows
	self._gpActionShadows = {} :: { any }
	self._modal = { content = page.content, card = page.panel } :: any
	local content = page.content

	-- Points chip in the page's top-right slot, left of the close chip.
	self._gpPointsChip = GPStudioKit.Chip(theme, page.topRight, {
		name = "Points",
		text = "0 points",
		tone = theme.Arcade.Gold,
		iconKey = "star",
		iconPx = 26,
		golden = true,
		pill = true,
		sizeUDim = UDim2.fromOffset(190, 40),
		layoutOrder = 1,
		textSize = theme.TextSizes.Button,
	})

	-- Graph canvas, on its own sheet of paper.
	local canvasPlate = GPStudioKit.Paper(theme, content, {
		name = "GPGraphPlate",
		index = 0,
		fill = theme.Studio.PanelSoft,
		shadow = "md",
	}, self._gpShadows)
	canvasPlate.Size = UDim2.fromOffset(GP_CANVAS_W, CONTENT_H)

	local canvas = GPStudioKit.Scroller(theme, canvasPlate, {
		name = "GPGraph",
		direction = Enum.ScrollingDirection.XY,
		automatic = Enum.AutomaticSize.None,
		padPx = GP_SCROLL_PAD,
	})
	canvas.Position = UDim2.fromOffset(spacing.S, spacing.S)
	canvas.Size = UDim2.new(1, -spacing.S * 2, 1, -spacing.S * 2)
	canvas.ZIndex = 3
	self._gpCanvas = canvas

	-- Detail pane.
	local detail = GPStudioKit.Paper(theme, content, {
		name = "GPDetail",
		index = 1,
		fill = theme.Studio.Card,
		shadow = "md",
	}, self._gpShadows)
	detail.Position = UDim2.fromOffset(GP_CANVAS_W + 16, 0)
	detail.Size = UDim2.fromOffset(GP_DETAIL_W, CONTENT_H)

	local detailBody = GPStudioKit.Scroller(theme, detail, {
		name = "GPDetailBody",
		thickness = 6,
		padPx = spacing.S,
	})
	detailBody.Position = UDim2.fromOffset(spacing.M, spacing.M)
	detailBody.Size = UDim2.new(1, -spacing.M * 2, 1, -(spacing.M * 2 + GP_ACTION_H + spacing.M))
	detailBody.ZIndex = 3
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, spacing.S),
	}).Parent = detailBody
	self._gpDetailBody = detailBody

	-- The action slot is pinned at the pane's foot so the scrolling body above
	-- it can never push UNLOCK off the page.
	local actionSlot = UIStyler.Frame("GPAction")
	actionSlot.BackgroundTransparency = 1
	actionSlot.AnchorPoint = Vector2.new(0, 1)
	actionSlot.Position = UDim2.new(0, spacing.M, 1, -spacing.M)
	actionSlot.Size = UDim2.new(1, -spacing.M * 2, 0, GP_ACTION_H)
	actionSlot.ZIndex = 3
	actionSlot.Parent = detail
	self._actionSlot = actionSlot

	self:_Recompute()
	self:_GPRenderGraph()
	self:_RenderPoints()
	self:_GPRenderDetail()
end

function SkillTreeScreen:_GPRenderGraph()
	table.clear(self._nodeViews)
	table.clear(self._pulseRings)
	for _, child in self._gpCanvas:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local maxX, maxY = 0, 0
	for _, node in self._nodes do
		maxX = math.max(maxX, node.x)
		maxY = math.max(maxY, node.y)
	end
	-- Canvas extent covers the right-most node's name label (wider than the
	-- node) and the bottom row's label strip, exactly as the arcade build does.
	self._gpCanvas.CanvasSize = UDim2.fromOffset(maxX + GP_NODE, maxY + 84)

	-- Connectors first so every node paints over them.
	for _, node in self._nodes do
		for _, requirement in node.requires do
			local parent = self:_Node(requirement)
			if parent then
				self:_GPBuildConnector(parent, node)
			end
		end
	end
	for _, node in self._nodes do
		self:_GPBuildNode(node)
	end
	-- Nothing selected yet (or the selection vanished with new data).
	if not self:_Node(self._selectedId or "") then
		self._selectedId = self._nodes[1] and self._nodes[1].id or nil
	end
	self:_HighlightSelection()
end

-- One axis-aligned pill segment of an elbow connector, centred on (x, y).
function SkillTreeScreen:_GPSegment(x: number, y: number, width: number, height: number, tone: Color3, transparency: number)
	if width <= 0 or height <= 0 then
		return
	end
	local theme = self:GetTheme()
	local seg = UIStyler.Frame("Link")
	seg.BackgroundColor3 = tone
	seg.BackgroundTransparency = transparency
	seg.AnchorPoint = Vector2.new(0.5, 0.5)
	seg.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	seg.Size = UDim2.fromOffset(math.floor(width), math.floor(height))
	seg.ZIndex = 1
	UIStyler.Corner(theme.Radii.Pill).Parent = seg
	seg.Parent = self._gpCanvas
end

function SkillTreeScreen:_GPBuildConnector(parent: Node, child: Node)
	local theme = self:GetTheme()
	local tokens = (theme :: any).DialectTokens
	local studio = tokens and tokens.studio
	local sage = (studio and studio.rule) or theme.Studio.Tan

	local tone, transparency
	if child.state == "unlocked" then
		tone, transparency = GPLayoutKit.Deepen(theme, theme.Colors.Secondary, 1), 0
	elseif child.state == "available" then
		tone, transparency = theme.Colors.Primary, 0.15
	else
		tone, transparency = sage, 0.35
	end

	local midY = (parent.y + child.y) / 2
	-- Down from the parent, across at the midline, down into the child. The
	-- horizontal run is over-long by one thickness so the two right angles meet
	-- without a notch.
	self:_GPSegment(parent.x, (parent.y + midY) / 2, GP_LINK, math.abs(midY - parent.y), tone, transparency)
	if parent.x ~= child.x then
		self:_GPSegment((parent.x + child.x) / 2, midY, math.abs(child.x - parent.x) + GP_LINK, GP_LINK, tone, transparency)
	end
	self:_GPSegment(child.x, (midY + child.y) / 2, GP_LINK, math.abs(child.y - midY), tone, transparency)
end

function SkillTreeScreen:_GPBuildNode(node: Node)
	local theme = self:GetTheme()
	local locked = node.state == "locked"
	local unlocked = node.state == "unlocked"

	local root = Instance.new("TextButton")
	root.Name = "GPNode_" .. node.id
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromOffset(node.x, node.y)
	root.Size = UDim2.fromOffset(GP_NODE, GP_NODE)
	root.ZIndex = 2
	root.Parent = self._gpCanvas

	-- Ringed states borrow the pack's twin colour masses: matcha for done,
	-- rose for reachable. Both deepened so a 3px ring reads on cream.
	local ringTint: Color3? = nil
	if unlocked then
		ringTint = GPLayoutKit.Deepen(theme, theme.Colors.Secondary, 1)
	elseif node.state == "available" then
		ringTint = GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1)
	end

	local plate = GPStudioKit.Paper(theme, root, {
		name = "Plate",
		index = if unlocked then 0 else 1,
		fill = if unlocked then theme.Colors.SurfaceRaised else theme.Colors.Surface,
		strokeTint = ringTint,
		strokeThickness = if ringTint then 3 else nil,
	})
	plate.Size = UDim2.fromScale(1, 1)
	plate.ZIndex = 3
	local stroke = plate:FindFirstChildOfClass("UIStroke") :: UIStroke
	if node.state == "available" then
		table.insert(self._pulseRings, stroke)
	end

	local icon = GPStudioKit.Icon(theme, plate, node.icon or "star", 48, {
		golden = unlocked,
		dim = if locked then 0.6 else nil,
	})
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 4

	if locked then
		local lock = GPStudioKit.Icon(theme, plate, "lock", 26, { tint = theme.Colors.TextSecondary })
		lock.AnchorPoint = Vector2.new(0.5, 1)
		lock.Position = UDim2.new(0.5, 0, 1, -4)
		lock.ZIndex = 5
	elseif unlocked then
		local check = GPStudioKit.Icon(theme, plate, "check", 22, {
			tint = GPLayoutKit.Deepen(theme, theme.Colors.Secondary, 1),
		})
		check.AnchorPoint = Vector2.new(1, 1)
		check.Position = UDim2.new(1, -3, 1, -3)
		check.ZIndex = 5
	end

	-- Name sits under the node so the graph reads without hovering.
	local name = GPLayoutKit.BodyText(theme, 13, if locked then theme.Colors.TextSecondary else theme.Colors.TextPrimary, "Name")
	name.Text = GPStudioKit.SoftCase(node.name)
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.new(0.5, 0, 1, 4)
	name.Size = UDim2.fromOffset(160, 20)
	name.RichText = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 3
	name.Parent = root

	root.Activated:Connect(function()
		self._selectedId = node.id
		self:_HighlightSelection()
		self:_GPRenderDetail()
	end)
	-- Animate LAST, after the final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, root, plate)

	-- The same view record the arcade build keeps, so _HighlightSelection and
	-- _Unlock's pulse work across both layouts without branching.
	table.insert(self._nodeViews, { node = node, surface = plate, stroke = stroke })
end

function SkillTreeScreen:_GPRenderDetail()
	local theme = self:GetTheme()
	local spacing = theme.Spacing
	GPStudioKit.ReleaseShadows(self._gpActionShadows)
	for _, child in self._gpDetailBody:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, child in self._actionSlot:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local node = self:_Node(self._selectedId or "")
	if not node then
		GPStudioKit.Empty(theme, self._gpDetailBody, "Pick a skill on the board to read it.", 60)
		return
	end

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local head = UIStyler.Frame("Head")
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, 56)
	head.LayoutOrder = nextOrder()
	head.Parent = self._gpDetailBody

	local headIcon = GPStudioKit.Icon(theme, head, node.icon or "star", 48, {
		golden = node.state == "unlocked",
	})
	headIcon.AnchorPoint = Vector2.new(0, 0.5)
	headIcon.Position = UDim2.new(0, 0, 0.5, 0)

	local title = GPLayoutKit.Text(theme, 24, theme.Colors.TextPrimary, "Title")
	title.Text = GPStudioKit.SoftCase(node.name)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(60, 0)
	title.Size = UDim2.new(1, -60, 1, 0)
	title.RichText = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = head

	local stateInk: { [string]: Color3 } = {
		unlocked = GPLayoutKit.Deepen(theme, theme.Colors.Secondary, 1),
		available = GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1),
		locked = theme.Colors.TextSecondary,
	}
	local stateWord: { [string]: string } = {
		unlocked = "Unlocked",
		available = "Ready to learn",
		locked = "Locked",
	}
	local state = GPLayoutKit.BodyText(theme, 17, stateInk[node.state] or theme.Colors.TextPrimary, "State")
	state.Text = stateWord[node.state] or GPStudioKit.SoftCase(node.state)
	state.TextXAlignment = Enum.TextXAlignment.Left
	state.Size = UDim2.new(1, 0, 0, 22)
	state.LayoutOrder = nextOrder()
	state.Parent = self._gpDetailBody

	local description = GPLayoutKit.BodyText(theme, 15, theme.Colors.TextPrimary, "Description")
	description.Text = node.description or ""
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.Size = UDim2.new(1, 0, 0, 0)
	description.AutomaticSize = Enum.AutomaticSize.Y
	description.TextWrapped = true
	description.RichText = false
	description.LayoutOrder = nextOrder()
	description.Parent = self._gpDetailBody

	GPStudioKit.Rule(theme, self._gpDetailBody, { layoutOrder = nextOrder() })

	local costRow = UIStyler.Frame("Cost")
	costRow.BackgroundTransparency = 1
	costRow.Size = UDim2.new(1, 0, 0, 34)
	costRow.LayoutOrder = nextOrder()
	costRow.Parent = self._gpDetailBody

	local costIcon = GPStudioKit.Icon(theme, costRow, "star", 26, { golden = true })
	costIcon.AnchorPoint = Vector2.new(0, 0.5)
	costIcon.Position = UDim2.new(0, 0, 0.5, 0)

	-- The cost AND what you have, so the affordability judgement does not need
	-- the header chip to be in view.
	local costText = GPLayoutKit.BodyText(theme, 18, theme.Colors.TextPrimary, "CostText")
	costText.Text = string.format("%d point%s · you have %d", node.cost, node.cost == 1 and "" or "s", self._points)
	costText.TextXAlignment = Enum.TextXAlignment.Left
	costText.Position = UDim2.fromOffset(34, 0)
	costText.Size = UDim2.new(1, -34, 1, 0)
	costText.Parent = costRow

	GPStudioKit.Heading(theme, self._gpDetailBody, "Prerequisites", {
		sizePx = theme.TextSizes.Body,
		heightPx = 28,
		layoutOrder = nextOrder(),
		name = "PrereqHeader",
	})
	GPStudioKit.Rule(theme, self._gpDetailBody, { layoutOrder = nextOrder() })

	if #node.requires == 0 then
		local none = GPLayoutKit.BodyText(theme, 15, theme.Colors.TextSecondary, "NoPrereq")
		none.Text = "None — this is a root skill."
		none.TextXAlignment = Enum.TextXAlignment.Left
		none.Size = UDim2.new(1, 0, 0, 24)
		none.LayoutOrder = nextOrder()
		none.Parent = self._gpDetailBody
	end

	for _, requirement in node.requires do
		local parent = self:_Node(requirement)
		local row = UIStyler.Frame("Prereq_" .. requirement)
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 28)
		row.LayoutOrder = nextOrder()
		row.Parent = self._gpDetailBody

		local met = parent ~= nil and parent.state == "unlocked"
		local mark = GPStudioKit.Icon(theme, row, met and "check" or "lock", 20, {
			tint = if met then GPLayoutKit.Deepen(theme, theme.Colors.Secondary, 1) else theme.Colors.TextSecondary,
		})
		mark.AnchorPoint = Vector2.new(0, 0.5)
		mark.Position = UDim2.new(0, 0, 0.5, 0)

		local text = GPLayoutKit.BodyText(theme, 15, if met then theme.Colors.TextSecondary else theme.Colors.TextPrimary, "Text")
		text.Text = GPStudioKit.SoftCase(parent and parent.name or requirement)
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.Position = UDim2.fromOffset(30, 0)
		text.Size = UDim2.new(1, -30, 1, 0)
		text.RichText = false
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text.Parent = row
	end

	-- UNLOCK dims in place when it cannot be afforded or reached; the tap still
	-- plays the full press juice and then explains (doc §11.1).
	local affordable = self._points >= node.cost
	if node.state == "unlocked" then
		GPStudioKit.Button(theme, self._actionSlot, {
			text = "Unlocked",
			tone = theme.Colors.Disabled,
			sizeUDim = UDim2.new(1, 0, 0, GP_ACTION_H),
			dimmed = true,
		}, self._gpActionShadows)
	else
		GPStudioKit.Button(theme, self._actionSlot, {
			text = "Unlock",
			tone = theme.Colors.Secondary,
			sizeUDim = UDim2.new(1, 0, 0, GP_ACTION_H),
			dimmed = not (affordable and node.state == "available"),
			onClick = function()
				self:_Unlock(node)
			end,
		}, self._gpActionShadows)
	end
end

-- The AVAILABLE rings breathe on sin(t) through the ONE shared Heartbeat,
-- bound to the page so a style rebuild unregisters it.
function SkillTreeScreen:_GPStartTicker()
	if self._gpTickerStop then
		return
	end
	local card = self._modal and self._modal.card
	self._gpTickerStop = UITicker.Register(function(dt: number)
		if not card or not UIChrome.IsOnScreen(card) then
			return
		end
		self._phase += dt
		local breathe = 0.5 + 0.5 * math.sin(self._phase * 2.4)
		for index = #self._pulseRings, 1, -1 do
			local ring = self._pulseRings[index]
			if ring.Parent then
				ring.Thickness = 2.5 + 2 * breathe
				ring.Transparency = 0.25 * (1 - breathe)
			else
				table.remove(self._pulseRings, index)
			end
		end
	end, card)
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts live in
-- StyleKit.Capabilities and only fall when a handle is released.
function SkillTreeScreen:_OnTeardown()
	self:_StopTicker()
	GPStudioKit.ReleaseShadows(self._gpShadows)
	GPStudioKit.ReleaseShadows(self._gpActionShadows)
	self._gpShadows = nil
	self._gpActionShadows = nil
	self._gpCanvas = nil
	self._gpDetailBody = nil
	self._gpPointsChip = nil
	table.clear(self._nodeViews)
	table.clear(self._pulseRings)
end

function SkillTreeScreen:Destroy()
	self:_StopTicker()
	for _, component in self._detailComponents do
		component:Destroy()
	end
	table.clear(self._detailComponents)
	UIScreenBase.Destroy(self)
end

return SkillTreeScreen
