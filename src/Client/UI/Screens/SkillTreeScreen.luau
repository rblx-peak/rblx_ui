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
	self._pointsLabel.Text = string.format("%d POINTS", self._points)
end

function SkillTreeScreen:_RenderGraph()
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
	for _, view in self._nodeViews do
		if view.node.state ~= "available" then
			view.stroke.Thickness = view.node.id == self._selectedId and base + 2 or base
		end
	end
end

function SkillTreeScreen:_RenderDetail()
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

function SkillTreeScreen:Destroy()
	self:_StopTicker()
	for _, component in self._detailComponents do
		component:Destroy()
	end
	table.clear(self._detailComponents)
	UIScreenBase.Destroy(self)
end

return SkillTreeScreen
