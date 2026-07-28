--!strict
-- CRAFTING — recipe list left, recipe detail right, Pottery Clash arcade family.
-- One §7.4 modal card: a scrolling recipe list (icon, name, green READY / red
-- MISSING indicator) beside a detail pane holding the result preview, the
-- ingredient ledger (have / need, shortfall in red), a gold readiness ruler
-- (doc §8) and the CRAFT button with its quantity stepper.
--
-- CRAFT is never removed when materials are short — it dims in place and still
-- plays the full press juice, then answers with a toast naming what is missing
-- (doc §11.1/§11.2). Crafting consumes materials across EVERY recipe that lists
-- the same ingredient, so the demo ledger stays internally consistent.
--
-- Fixed px at the 1650×1020 baseline (UIScreenBase attaches the UIScale).

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIProgressBarComponent = require(script.Parent.Parent.Components.UIProgressBarComponent)
local UIScreenBase = require(script.Parent.UIScreenBase)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)

type Ingredient = { name: string, icon: string, have: number, need: number }
type Recipe = { id: string, name: string, icon: string, output: any, ingredients: { Ingredient } }

-- Card 1280×780 → content 1252×692 after the §7.4 inset.
local CARD = Vector2.new(1280, 780)
local CONTENT_W = 1252
local CONTENT_H = 692
local LIST_W = 420
local GAP = 16
local DETAIL_W = CONTENT_W - LIST_W - GAP
local ROW_W = LIST_W - 8 -- scrollbar reserve
local ROW_H = 96
local PAD = 20
local ING_W = DETAIL_W - PAD * 2
local ING_ROW_H = 56
local STEP_H = 56
local MAX_QTY = 9

local WHITE = Color3.new(1, 1, 1)

local function demoRecipes(): { Recipe }
	return {
		{
			id = "emberBlade", name = "EMBER BLADE", icon = "sword", output = 1,
			ingredients = {
				{ name = "IRON INGOT", icon = "shield", have = 6, need = 8 },
				{ name = "KILN CRYSTAL", icon = "crystal", have = 2, need = 2 },
				{ name = "EMBER CORE", icon = "explosion", have = 0, need = 1 },
				{ name = "GLAZE DUST", icon = "sparkle", have = 40, need = 25 },
			},
		},
		{
			id = "kilnGuard", name = "KILN GUARD", icon = "shield", output = 1,
			ingredients = {
				{ name = "IRON INGOT", icon = "shield", have = 6, need = 10 },
				{ name = "OAK LEAF", icon = "leaf", have = 88, need = 12 },
			},
		},
		{
			id = "greaterPotion", name = "GREATER POTION", icon = "potion", output = 3,
			ingredients = {
				{ name = "SPRING WATER", icon = "water", have = 52, need = 4 },
				{ name = "OAK LEAF", icon = "leaf", have = 88, need = 6 },
				{ name = "GLAZE DUST", icon = "sparkle", have = 40, need = 2 },
			},
		},
		{
			id = "tricksterBomb", name = "TRICKSTER BOMB", icon = "bomb", output = 5,
			ingredients = {
				{ name = "IRON INGOT", icon = "shield", have = 6, need = 1 },
				{ name = "FIRECRACKER", icon = "fire", have = 16, need = 3 },
			},
		},
		{
			id = "luckyClover", name = "LUCKY CLOVER", icon = "luck", output = 1,
			ingredients = {
				{ name = "STAR FRAGMENT", icon = "star", have = 7, need = 2 },
				{ name = "GLAZE DUST", icon = "sparkle", have = 40, need = 30 },
			},
		},
		{
			id = "vaultKey", name = "VAULT KEY", icon = "key", output = 2,
			ingredients = {
				{ name = "IRON INGOT", icon = "shield", have = 6, need = 3 },
				{ name = "PORTAL SHARD", icon = "portal", have = 1, need = 1 },
			},
		},
		{
			id = "rainbowTrail", name = "RAINBOW TRAIL", icon = "rainbow", output = 1,
			ingredients = {
				{ name = "STAR FRAGMENT", icon = "star", have = 7, need = 5 },
				{ name = "KILN CRYSTAL", icon = "crystal", have = 2, need = 4 },
				{ name = "GLAZE DUST", icon = "sparkle", have = 40, need = 60 },
			},
		},
		{
			id = "magnetCoil", name = "MAGNET COIL", icon = "magnet", output = 4,
			ingredients = {
				{ name = "IRON INGOT", icon = "shield", have = 6, need = 2 },
				{ name = "SPEED BOLT", icon = "bolt", have = 24, need = 4 },
			},
		},
	}
end

local CraftingScreen = setmetatable({}, { __index = UIScreenBase })
CraftingScreen.__index = CraftingScreen

function CraftingScreen.new()
	local self = UIScreenBase.new("CraftingScreen", 8)
	self._recipes = demoRecipes()
	self._selectedId = nil :: string?
	self._quantity = 1
	self._rows = {} :: { GuiObject }
	self._ingredientRows = {} :: { GuiObject }
	return setmetatable(self, CraftingScreen)
end

function CraftingScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function CraftingScreen:_Selected(): Recipe?
	for _, recipe in self._recipes do
		if recipe.id == self._selectedId then
			return recipe
		end
	end
	return self._recipes[1]
end

-- How short the recipe is at the current quantity: the total missing units and
-- the first ingredient that runs out (what the blocked-tap toast names).
local function shortfall(recipe: Recipe, quantity: number): (number, string?)
	local missing, firstName = 0, nil
	for _, ingredient in recipe.ingredients do
		local need = ingredient.need * quantity
		if ingredient.have < need then
			missing += need - ingredient.have
			if not firstName then
				firstName = ingredient.name
			end
		end
	end
	return missing, firstName
end

local function readiness(recipe: Recipe, quantity: number): (number, number)
	local have, need = 0, 0
	for _, ingredient in recipe.ingredients do
		local want = ingredient.need * quantity
		need += want
		have += math.min(ingredient.have, want)
	end
	return have, need
end

-- ========================================================================
-- Recipe list
-- ========================================================================

function CraftingScreen:_BuildList(theme: Types.UITheme, content: Frame)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Recipes"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromOffset(LIST_W, CONTENT_H)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Arcade.Gold
	scroll.ZIndex = 43
	scroll.Parent = content
	UIStyler.ListLayout({ Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Left }).Parent = scroll
	self._list = scroll
end

function CraftingScreen:_BuildRow(theme: Types.UITheme, recipe: Recipe, order: number)
	local ready = select(1, shortfall(recipe, 1)) == 0

	local root = UIStyler.Frame("Recipe_" .. recipe.id)
	root.BackgroundTransparency = 1
	root.LayoutOrder = order
	root.Size = UDim2.fromOffset(ROW_W, ROW_H)
	root.ZIndex = 43
	root.Parent = self._list

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 43
	hit.Parent = root

	-- Zebra by list position (doc §9 row grammar), both fills at 0.15.
	local surface = UIStyler.Frame("Surface")
	surface.BackgroundColor3 = if order % 2 == 1 then theme.Arcade.NearBlack2 else theme.Arcade.Row
	surface.BackgroundTransparency = 0.15
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 44
	UIChrome.Corner("Arcade").Parent = surface
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = surface
	UIChrome.GlassGradient().Parent = surface
	surface.Parent = root

	local well = UIStyler.Frame("IconWell")
	well.BackgroundColor3 = theme.Arcade.NearBlack
	well.AnchorPoint = Vector2.new(0, 0.5)
	well.Position = UDim2.new(0, 12, 0.5, 0)
	well.Size = UDim2.fromOffset(64, 64)
	well.ZIndex = 45
	UIChrome.Corner("Arcade").Parent = well
	UIChrome.Stroke(theme, "Arcade", "Button").Parent = well
	well.Parent = surface

	local icon = IconArchive.Image(well, recipe.icon, 44)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 46

	local name = UIChrome.Text("Name", 22, WHITE)
	name.RichText = false
	name.Text = recipe.name
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(90, 18)
	name.Size = UDim2.fromOffset(ROW_W - 104, 28)
	name.ZIndex = 45
	name.Parent = surface

	-- The have-indicator: a colour-coded pip plus its word, so the state reads
	-- at a glance and never relies on colour alone.
	local pip = UIStyler.Frame("Pip")
	pip.BackgroundColor3 = if ready then theme.Arcade.Green else theme.Arcade.Red
	pip.AnchorPoint = Vector2.new(0, 0.5)
	pip.Position = UDim2.new(0, 90, 0, 62)
	pip.Size = UDim2.fromOffset(12, 12)
	pip.ZIndex = 45
	UIChrome.Corner("Arcade", "Pill").Parent = pip
	pip.Parent = surface

	local state = UIChrome.Text("State", 17, if ready then theme.Arcade.Green else theme.Arcade.Red)
	state.RichText = false
	local missing, firstName = shortfall(recipe, 1)
	state.Text = if ready then "READY TO CRAFT" else string.format("MISSING %d %s", missing, firstName or "")
	state.TextXAlignment = Enum.TextXAlignment.Left
	state.TextTruncate = Enum.TextTruncate.AtEnd
	state.Position = UDim2.fromOffset(110, 50)
	state.Size = UDim2.fromOffset(ROW_W - 124, 24)
	state.ZIndex = 45
	state.Parent = surface

	local ring = UIStyler.Frame("SelRing")
	ring.BackgroundTransparency = 1
	ring.Position = UDim2.fromOffset(-3, -3)
	ring.Size = UDim2.new(1, 6, 1, 6)
	ring.Visible = self._selectedId == recipe.id
	ring.ZIndex = 45
	UIChrome.Stroke(theme, "Arcade", "Selection").Parent = ring
	ring.Parent = root

	hit.Activated:Connect(function()
		self._selectedId = recipe.id
		self._quantity = 1
		UIChrome.Pulse(theme, surface)
		self:_RenderList()
		self:_RenderDetail()
	end)
	UIChrome.Animate(theme, hit, surface)

	table.insert(self._rows, root)
end

function CraftingScreen:_RenderList()
	-- GP pastel studio: the same recipe ledger as petal rows (see _GPRenderList).
	if self:LayoutKit() == "GP" then
		self:_GPRenderList()
		return
	end
	if not self._list then
		return
	end
	local theme = self:GetTheme()
	for _, child in self._list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(self._rows)
	for order, recipe in self._recipes do
		self:_BuildRow(theme, recipe, order)
	end
end

-- ========================================================================
-- Detail pane
-- ========================================================================

function CraftingScreen:_BuildDetail(theme: Types.UITheme, content: Frame)
	local pane = UIChrome.Panel(theme, "Arcade", "Detail")
	pane.Position = UDim2.fromOffset(LIST_W + GAP, 0)
	pane.Size = UDim2.fromOffset(DETAIL_W, CONTENT_H)
	pane.ZIndex = 43
	pane.Parent = content
	self._detail = pane

	local well = UIStyler.Frame("ResultWell")
	well.BackgroundColor3 = theme.Arcade.NearBlack
	well.Position = UDim2.fromOffset(PAD, PAD)
	well.Size = UDim2.fromOffset(160, 160)
	well.ZIndex = 44
	UIChrome.Corner("Arcade").Parent = well
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = well
	UIChrome.GlassGradient().Parent = well
	well.Parent = pane
	self._resultWell = well

	local goldRing = UIStyler.Frame("Ring")
	goldRing.BackgroundTransparency = 1
	goldRing.Position = UDim2.fromOffset(6, 6)
	goldRing.Size = UDim2.new(1, -12, 1, -12)
	goldRing.ZIndex = 45
	UIChrome.Stroke(theme, "Arcade", "Selection").Parent = goldRing
	goldRing.Parent = well

	local name = UIChrome.Text("ResultName", 34, theme.Arcade.Gold)
	name.RichText = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(PAD + 180, PAD + 24)
	name.Size = UDim2.fromOffset(DETAIL_W - PAD * 2 - 180, 40)
	name.ZIndex = 44
	name.Parent = pane
	self._resultName = name

	local output = UIChrome.Text("Output", 22, theme.Arcade.IceBlue)
	output.RichText = false
	output.TextXAlignment = Enum.TextXAlignment.Left
	output.Position = UDim2.fromOffset(PAD + 180, PAD + 70)
	output.Size = UDim2.fromOffset(DETAIL_W - PAD * 2 - 180, 28)
	output.ZIndex = 44
	output.Parent = pane
	self._resultOutput = output

	local blurb = UIChrome.BodyText("Blurb", 17, theme.Arcade.IceBlue)
	blurb.RichText = false
	blurb.Text = "Materials are consumed the moment the kiln closes."
	blurb.TextXAlignment = Enum.TextXAlignment.Left
	blurb.Position = UDim2.fromOffset(PAD + 180, PAD + 106)
	blurb.Size = UDim2.fromOffset(DETAIL_W - PAD * 2 - 180, 24)
	blurb.ZIndex = 44
	blurb.Parent = pane

	local title = UIChrome.Text("MaterialsTitle", 20, theme.Arcade.Gold)
	title.Text = "MATERIALS"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(PAD, 196)
	title.Size = UDim2.fromOffset(ING_W, 26)
	title.ZIndex = 44
	title.Parent = pane

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Ingredients"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(PAD, 228)
	scroll.Size = UDim2.fromOffset(ING_W, 272)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Arcade.Gold
	scroll.ZIndex = 44
	scroll.Parent = pane
	UIStyler.ListLayout({ Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Left }).Parent = scroll
	self._ingredients = scroll

	self._readiness = UIProgressBarComponent.new()
	self._readiness:Create(pane, {
		value = 0,
		maxValue = 1,
		label = "READINESS",
		size = UDim2.fromOffset(ING_W, 30),
		position = UDim2.fromOffset(PAD, 516),
	})
	self._readiness.Root.ZIndex = 44

	-- Quantity stepper: minus / N / plus, sitting left of CRAFT. The icon ids
	-- are kept because SetContent rebuilds the whole label/icon slot from the
	-- props it is handed — omitting iconId later would blank the glyph.
	local minusId = IconArchive.Id("minus")
	self._minusIconId = minusId
	self._minusBtn = UIButtonComponent.new()
	self._minusBtn:Create(pane, {
		text = if minusId then "" else "-",
		iconId = minusId,
		variant = "Grey",
		size = UDim2.fromOffset(52, STEP_H),
		position = UDim2.new(0, PAD, 1, -PAD),
		anchorPoint = Vector2.new(0, 1),
		onClick = function()
			self:_SetQuantity(self._quantity - 1)
		end,
	})
	self._minusBtn.Root.ZIndex = 45

	local qtyWell = UIStyler.Frame("QtyWell")
	qtyWell.BackgroundColor3 = theme.Arcade.NearBlack
	qtyWell.AnchorPoint = Vector2.new(0, 1)
	qtyWell.Position = UDim2.new(0, PAD + 58, 1, -PAD)
	qtyWell.Size = UDim2.fromOffset(84, STEP_H)
	qtyWell.ZIndex = 45
	UIChrome.Corner("Arcade").Parent = qtyWell
	UIChrome.Stroke(theme, "Arcade", "Button").Parent = qtyWell
	UIChrome.GlassGradient().Parent = qtyWell
	qtyWell.Parent = pane

	local qty = UIChrome.Text("Qty", 28, theme.Arcade.Gold)
	qty.Text = "1"
	qty.Size = UDim2.fromScale(1, 1)
	qty.ZIndex = 46
	qty.Parent = qtyWell
	self._qtyLabel = qty

	local plusId = IconArchive.Id("plus")
	self._plusIconId = plusId
	self._plusBtn = UIButtonComponent.new()
	self._plusBtn:Create(pane, {
		text = if plusId then "" else "+",
		iconId = plusId,
		variant = "Grey",
		size = UDim2.fromOffset(52, STEP_H),
		position = UDim2.new(0, PAD + 148, 1, -PAD),
		anchorPoint = Vector2.new(0, 1),
		onClick = function()
			self:_SetQuantity(self._quantity + 1)
		end,
	})
	self._plusBtn.Root.ZIndex = 45

	self._craftBtn = UIButtonComponent.new()
	self._craftBtn:Create(pane, {
		text = "CRAFT",
		variant = "Green",
		size = UDim2.fromOffset(300, STEP_H),
		position = UDim2.new(1, -PAD, 1, -PAD),
		anchorPoint = Vector2.new(1, 1),
		onClick = function()
			self:_Craft()
		end,
	})
	self._craftBtn.Root.ZIndex = 45
end

function CraftingScreen:_BuildIngredientRow(theme: Types.UITheme, ingredient: Ingredient, order: number)
	local need = ingredient.need * self._quantity
	local satisfied = ingredient.have >= need

	local row = UIStyler.Frame("Ing" .. order)
	row.BackgroundColor3 = theme.Arcade.Row
	row.BackgroundTransparency = 0.15
	row.LayoutOrder = order
	row.Size = UDim2.fromOffset(ING_W - 8, ING_ROW_H)
	row.ZIndex = 45
	UIChrome.Corner("Arcade").Parent = row
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = row
	UIChrome.GlassGradient().Parent = row
	row.Parent = self._ingredients

	local icon = IconArchive.Image(row, ingredient.icon, 34)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 12, 0.5, 0)
	icon.ZIndex = 46

	local name = UIChrome.Text("Name", 20, WHITE)
	name.RichText = false
	name.Text = ingredient.name
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(58, 0)
	-- Stops short of the counts column (right −120, 140 wide) so a long
	-- material name truncates instead of colliding with its numbers.
	name.Size = UDim2.fromOffset(ING_W - 334, ING_ROW_H)
	name.ZIndex = 46
	name.Parent = row

	local counts = UIChrome.Text("Counts", 22, if satisfied then theme.Arcade.Green else theme.Arcade.Red)
	counts.RichText = false
	counts.Text = string.format("%d / %d", ingredient.have, need)
	counts.TextXAlignment = Enum.TextXAlignment.Right
	counts.AnchorPoint = Vector2.new(1, 0.5)
	counts.Position = UDim2.new(1, -120, 0.5, 0)
	counts.Size = UDim2.fromOffset(140, ING_ROW_H)
	counts.ZIndex = 46
	counts.Parent = row

	if satisfied then
		local check = IconArchive.Image(row, "check", 26)
		check.AnchorPoint = Vector2.new(1, 0.5)
		check.Position = UDim2.new(1, -14, 0.5, 0)
		check.ZIndex = 46
		if check:IsA("ImageLabel") then
			check.ImageColor3 = theme.Arcade.Green
		else
			(check :: any).TextColor3 = theme.Arcade.Green
		end
	else
		local missing = UIChrome.Text("Missing", 22, theme.Arcade.Red)
		missing.RichText = false
		missing.Text = string.format("-%d", need - ingredient.have)
		missing.TextXAlignment = Enum.TextXAlignment.Right
		missing.AnchorPoint = Vector2.new(1, 0.5)
		missing.Position = UDim2.new(1, -14, 0.5, 0)
		missing.Size = UDim2.fromOffset(100, ING_ROW_H)
		missing.ZIndex = 46
		missing.Parent = row
	end

	table.insert(self._ingredientRows, row)
end

function CraftingScreen:_RenderDetail()
	-- GP pastel studio: the same result / ledger / readiness / stepper pane in
	-- the pack's own parts (see _GPRenderDetail).
	if self:LayoutKit() == "GP" then
		self:_GPRenderDetail()
		return
	end

	local theme = self:GetTheme()
	local recipe = self:_Selected()
	if not recipe or not self._ingredients then
		return
	end
	self._selectedId = recipe.id

	if self._resultArt then
		self._resultArt:Destroy()
	end
	local art = IconArchive.Image(self._resultWell, recipe.icon, 104, { golden = true })
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.ZIndex = 46
	self._resultArt = art

	local perCraft = if type(recipe.output) == "number" then recipe.output else 1
	self._resultName.Text = recipe.name
	self._resultOutput.Text = string.format("MAKES x%d  ·  %d BATCH", perCraft * self._quantity, self._quantity)
	self._qtyLabel.Text = tostring(self._quantity)

	for _, row in self._ingredientRows do
		row:Destroy()
	end
	table.clear(self._ingredientRows)
	for order, ingredient in recipe.ingredients do
		self:_BuildIngredientRow(theme, ingredient, order)
	end

	local have, need = readiness(recipe, self._quantity)
	self._readiness:Set(have, math.max(need, 1))

	-- Blocked = dimmed IN PLACE; the tap still answers with the reason.
	local missing = select(1, shortfall(recipe, self._quantity))
	self._craftBtn:SetContent({ text = "CRAFT", variant = "Green", dimmed = missing > 0 })
	self._minusBtn:SetContent({
		text = if self._minusIconId then "" else "-",
		iconId = self._minusIconId,
		dimmed = self._quantity <= 1,
	})
	self._plusBtn:SetContent({
		text = if self._plusIconId then "" else "+",
		iconId = self._plusIconId,
		dimmed = self._quantity >= MAX_QTY,
	})
end

-- ========================================================================
-- Actions
-- ========================================================================

function CraftingScreen:_SetQuantity(value: number)
	local clamped = math.clamp(value, 1, MAX_QTY)
	if clamped == self._quantity then
		self:_Toast(if value < 1 then "MINIMUM IS 1" else string.format("MAXIMUM IS %d", MAX_QTY), "Info")
		return
	end
	self._quantity = clamped
	UIChrome.Pulse(self:GetTheme(), self._qtyLabel)
	self:_RenderDetail()
end

function CraftingScreen:_Craft()
	local recipe = self:_Selected()
	if not recipe then
		return
	end
	local missing, firstName = shortfall(recipe, self._quantity)
	if missing > 0 then
		self:_Toast(string.format("NEED %d MORE %s", missing, firstName or "MATERIALS"), "Error")
		return
	end

	-- Consume across every recipe listing the same material, so the whole
	-- ledger stays consistent without a backend behind it.
	local spent: { [string]: number } = {}
	for _, ingredient in recipe.ingredients do
		spent[ingredient.name] = (spent[ingredient.name] or 0) + ingredient.need * self._quantity
	end
	for _, other in self._recipes do
		for _, ingredient in other.ingredients do
			local cost = spent[ingredient.name]
			if cost then
				ingredient.have = math.max(0, ingredient.have - cost)
			end
		end
	end

	local perCraft = if type(recipe.output) == "number" then recipe.output else 1
	self:_Toast(string.format("CRAFTED x%d %s", perCraft * self._quantity, recipe.name), "Success")
	UIChrome.Pulse(self:GetTheme(), self._resultWell)
	self._quantity = 1
	self:_RenderList()
	self:_RenderDetail()
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function CraftingScreen:_Ingest(data: any)
	if type(data) ~= "table" then
		return
	end
	local list = if type(data.recipes) == "table" then data.recipes elseif #data > 0 then data else nil
	if list then
		self._recipes = list
		self._selectedId = nil
		self._quantity = 1
	end
end

function CraftingScreen:_BuildContent()
	-- GP layout language: the pastel STUDIO (cream page, rose ribbon, petal
	-- recipe rows alternating mirror, a matte materials ledger at the AC
	-- assembly row's density) — see _BuildGPLayout below.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end

	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "CRAFTING",
		sizePx = CARD,
		onClose = function()
			self.ScreenController:HideScreen("crafting")
		end,
	})
	self._modal = modal

	self:_BuildList(theme, modal.content)
	self:_BuildDetail(theme, modal.content)
	self:_RenderList()
	self:_RenderDetail()
end

function CraftingScreen:_OnShow(data: any?)
	self:_Ingest(data)
	if self._built then
		self:_RenderList()
		self:_RenderDetail()
	end
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	elseif self._gpPage then
		-- Same POP_IN contract, on the pack's own plate (theme.Motion tokens).
		UIChrome.PopIn(self:GetTheme(), self._gpPage.panel)
	end
end

function CraftingScreen:Update(data: any)
	self:_Ingest(data)
	if self._built then
		self:_RenderList()
		self:_RenderDetail()
	end
end

function CraftingScreen:Destroy()
	for _, component in { self._readiness, self._craftBtn, self._minusBtn, self._plusBtn } do
		if component then
			component:Destroy()
		end
	end
	self._readiness, self._craftBtn = nil, nil
	self._minusBtn, self._plusBtn = nil, nil
	UIScreenBase.Destroy(self)
end

-- ======================================================================
-- GP layout (theme.LayoutKit == "GP") — the pastel STUDIO, composed from
-- GPLayoutKit: a cream Page under a rose ribbon, the recipe shelf on the
-- left as petal rows whose corners ALTERNATE mirror down the list (pack law
-- 4), and the workbench on the right — result well, materials ledger,
-- readiness row, quantity stepper and the fire control. Every plate casts a
-- shadow deepened from its OWN fill (pack law 2).
--
-- Presentation only: the same recipes, the same shortfall/readiness maths,
-- the same cross-recipe material consumption, the same handlers. CRAFT is
-- still never removed when materials are short — it quietens IN PLACE, still
-- plays the full press juice, and _Craft still answers with the toast naming
-- what is missing (doc §11.1/§11.2).
--
-- DENSITY (pack law 6): every field the arcade build shows is here — per
-- recipe the icon, name and the READY / MISSING n <material> state; per
-- material the icon, name, the have/need counts AND the exact shortfall; the
-- result art, name, "makes xN · N batch" line, blurb, the materials heading,
-- the readiness meter, the quantity and the craft control. The readiness bar
-- is UPGRADED, not reduced: GPLayoutKit.StatRow prints the same ratio as a
-- labelled bar PLUS the numeric have-value and its unit in a fixed column
-- ladder, which is the Armored Core assembly row's density.
-- ======================================================================

local GP_PAGE = Vector2.new(1280, 800)
local GP_LIST_W = 420
local GP_PANE_GAP = 16
local GP_PAD = 20
local GP_ROW_H = 100
local GP_ROW_GAP = 10
local GP_ING_ROW_H = 60
local GP_ING_GAP = 8
local GP_STEP_H = 56
local GP_WELL = 160
local GP_STATE_W = 262
local GP_COUNT_W = 130
local GP_ING_CHIP_W = 112

-- The icon archive's GLYPH FALLBACK is born pure-white with a black text
-- stroke — both banned outright by pack law 1. Every archive placement in
-- this branch goes through here so a pending upload cannot punch a hole in
-- the palette.
local function gpArt(theme: Types.UITheme, parent: Instance, key: string, sizePx: number, query: any?): GuiObject
	local art = IconArchive.Image(parent, key, sizePx, query)
	if art:IsA("TextLabel") then
		art.TextColor3 = theme.Colors.TextPrimary
		art.TextStrokeTransparency = 1
	end
	return art
end

-- GP never shouts (pack law 5). The recipe and material tables are authored in
-- arcade caps ("EMBER BLADE", "IRON INGOT"), so the SAME strings are retitled
-- for DISPLAY only — the data, the ids, the shortfall maths and every other
-- branch are untouched.
local function gpTitleCase(text: string): string
	if string.find(text, "<", 1, true) then
		return text
	end
	-- Only SHOUTED copy is retitled: a string already carrying a lowercase
	-- letter was cased deliberately and flattening it would do real damage.
	if string.find(text, "%l") then
		return text
	end
	local retitled = string.gsub(string.lower(text), "[%a][%w']*", function(word: string): string
		return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
	end)
	return retitled
end

-- A painted petal plate. UIStyler.Frame is born PURE WHITE, so nothing in
-- this branch is ever left unpainted. Shadow is opt-in: this screen renders
-- up to eight recipe rows plus a materials ledger, and a shadow on every
-- chip would spend a third of the engine's ~100-shadow budget on furniture.
local function gpPlate(theme: Types.UITheme, parent: Instance, fill: Color3, index: number, sink: { any }?): Frame
	local plate = UIStyler.Frame("Plate")
	plate.BackgroundColor3 = fill
	plate.Parent = parent
	GPLayoutKit.Petal(theme, plate, index)
	GPLayoutKit.SoftStroke(theme, plate, fill)
	if sink then
		GPLayoutKit.Shadow(theme, plate, "sm", sink, fill)
	end
	return plate
end

-- A state chip: pastel plate, INK copy. Colors.TextOnPrimary (near-white)
-- measures 2.14:1 on these tints and is legal only for LARGE display text on
-- a deepened one, so nothing small in this branch ever uses it. The FILL
-- carries the hue and the WORDS carry the meaning — never hue alone.
local function gpChip(theme: Types.UITheme, parent: Instance, fill: Color3, text: string, index: number): Frame
	local root = gpPlate(theme, parent, fill, index)
	root.Name = "Chip"
	root.ZIndex = 4

	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "ChipText")
	label.Text = text
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 5
	label.Parent = root
	return root
end

type GPButton = { root: TextButton, shape: Frame, label: TextLabel, stroke: UIStroke, shadow: any }

-- GPLayoutKit ships no action button, so this is the local one: a petal plate
-- in a pack colour, a deepened-tint stroke, its own hue-matched shadow and
-- the shared hover/press juice. The BUTTON stays transparent and the fill
-- lives on a child — UIStyleEnforcer backstops any SOLID GuiButton with a
-- BLACK 2px stroke, which would break pack law 1 on sight.
local function gpButton(
	theme: Types.UITheme,
	parent: Instance,
	text: string,
	fill: Color3,
	index: number,
	sink: { any }?,
	onClick: () -> ()
): GPButton
	local root = Instance.new("TextButton")
	root.Name = "GPButton"
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.ZIndex = 5
	root.Parent = parent

	local shape = UIStyler.Frame("Shape")
	shape.BackgroundColor3 = fill
	shape.Size = UDim2.fromScale(1, 1)
	shape.ZIndex = 5
	shape.Parent = root
	GPLayoutKit.Petal(theme, shape, index)
	local stroke = GPLayoutKit.SoftStroke(theme, shape, fill)
	local shadow = GPLayoutKit.Shadow(theme, shape, "sm", sink, fill)

	local label = GPLayoutKit.Text(theme, theme.TextSizes.Button, theme.Colors.TextPrimary, "Label")
	label.Text = text
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 6
	label.Parent = shape

	root.Activated:Connect(onClick)
	UIChrome.Animate(theme, root, shape)
	return { root = root, shape = shape, label = label, stroke = stroke, shadow = shadow }
end

-- Repaint a control IN PLACE without rebuilding it (doc §11.2). The SHADOW
-- retints with the fill: a quietened plate still casting matcha would be the
-- grey-shadow bug inverted, which is the one thing this pack cannot do.
local function gpSetFill(theme: Types.UITheme, button: GPButton, fill: Color3)
	button.shape.BackgroundColor3 = fill
	local deep = GPLayoutKit.Deepen(theme, fill, 1)
	button.stroke.Color = deep
	button.shadow.Instance.Color = deep
end

function CraftingScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	-- Arcade leftovers must not leak into the pastel page: _OnShow pops
	-- self._modal if present, and Destroy walks the component fields.
	self._modal = nil
	self._gpShadows = {} :: { any }
	-- THREE sinks by design. Page chrome is built once and released at
	-- teardown; the recipe rows and the materials ledger are destroyed and
	-- rebuilt on every render, so those handles are released at the TOP of
	-- their render or the budget counter climbs forever behind dead instances.
	self._gpRowShadows = {} :: { any }
	self._gpDetailShadows = {} :: { any }

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Crafting",
		subtitleText = "Throw it, glaze it, fire it",
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("crafting")
		end,
	})
	for _, handle in page.shadows do
		table.insert(self._gpShadows, handle)
	end
	self._gpPage = page

	-- ---- left: the recipe shelf -----------------------------------------
	local list = Instance.new("ScrollingFrame")
	list.Name = "Recipes"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.new(0, GP_LIST_W, 1, 0)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = theme.Colors.Primary
	-- MUST clip: unclipped rows spilling past the frame is a known past bug
	-- here. The padding keeps a row's SOFT shadow off the clip edge so a plate
	-- is never sliced flat on the boundary.
	list.ClipsDescendants = true
	local listPad = Instance.new("UIPadding")
	listPad.Name = "gpRecipePad"
	listPad.PaddingTop = UDim.new(0, 6)
	listPad.PaddingBottom = UDim.new(0, 18)
	listPad.PaddingLeft = UDim.new(0, 8)
	listPad.PaddingRight = UDim.new(0, 8)
	listPad.Parent = list
	UIStyler.ListLayout({
		Padding = UDim.new(0, GP_ROW_GAP),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = list
	list.Parent = page.content
	self._list = list

	-- ---- right: the workbench -------------------------------------------
	local paneFill = theme.Colors.Surface
	local pane = gpPlate(theme, page.content, paneFill, 1, self._gpShadows)
	pane.Name = "Workbench"
	pane.Position = UDim2.fromOffset(GP_LIST_W + GP_PANE_GAP, 0)
	pane.Size = UDim2.new(1, -(GP_LIST_W + GP_PANE_GAP), 1, 0)
	self._detail = pane

	local wellFill = theme.Colors.SurfaceRaised
	local well = gpPlate(theme, pane, wellFill, 0, self._gpShadows)
	well.Name = "ResultWell"
	well.Position = UDim2.fromOffset(GP_PAD, GP_PAD)
	well.Size = UDim2.fromOffset(GP_WELL, GP_WELL)
	well.ZIndex = 3
	self._resultWell = well

	local name = GPLayoutKit.Text(theme, 30, theme.Colors.TextPrimary, "ResultName")
	name.RichText = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(GP_PAD + GP_WELL + GP_PAD, GP_PAD + 8)
	name.Size = UDim2.new(1, -(GP_PAD * 3 + GP_WELL), 0, 40)
	name.ZIndex = 3
	name.Parent = pane
	self._resultName = name

	local output = GPLayoutKit.BodyText(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Output")
	output.RichText = false
	output.TextXAlignment = Enum.TextXAlignment.Left
	output.Position = UDim2.fromOffset(GP_PAD + GP_WELL + GP_PAD, GP_PAD + 54)
	output.Size = UDim2.new(1, -(GP_PAD * 3 + GP_WELL), 0, 28)
	output.ZIndex = 3
	output.Parent = pane
	self._resultOutput = output

	-- Warm and playful, never patronizing — and never shouted (pack law 5).
	local blurb = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Blurb")
	blurb.RichText = false
	blurb.Text = "Clay is consumed the moment the kiln door closes."
	blurb.TextXAlignment = Enum.TextXAlignment.Left
	blurb.Position = UDim2.fromOffset(GP_PAD + GP_WELL + GP_PAD, GP_PAD + 88)
	blurb.Size = UDim2.new(1, -(GP_PAD * 3 + GP_WELL), 0, 24)
	blurb.ZIndex = 3
	blurb.Parent = pane

	local heading = GPLayoutKit.SectionLabel(theme, pane, "Materials")
	heading.FontFace = theme.Fonts.Subtitle
	heading.TextColor3 = theme.Colors.TextPrimary
	heading.TextSize = theme.TextSizes.Subtitle
	heading.Position = UDim2.fromOffset(GP_PAD, 196)
	heading.Size = UDim2.new(1, -GP_PAD * 2, 0, 26)
	heading.ZIndex = 3

	local rule = GPLayoutKit.Divider(theme, pane)
	rule.Position = UDim2.fromOffset(GP_PAD, 224)
	rule.Size = UDim2.new(1, -GP_PAD * 2, 0, rule.Size.Y.Offset)
	rule.ZIndex = 3

	local ingredients = Instance.new("ScrollingFrame")
	ingredients.Name = "Materials"
	ingredients.BackgroundTransparency = 1
	ingredients.BorderSizePixel = 0
	ingredients.Position = UDim2.fromOffset(GP_PAD, 246)
	ingredients.Size = UDim2.new(1, -GP_PAD * 2, 0, 262)
	ingredients.CanvasSize = UDim2.new()
	ingredients.AutomaticCanvasSize = Enum.AutomaticSize.Y
	ingredients.ScrollingDirection = Enum.ScrollingDirection.Y
	ingredients.ScrollBarThickness = 6
	ingredients.ScrollBarImageColor3 = theme.Colors.Primary
	-- Same clipping law, same shadow gutter as the recipe shelf.
	ingredients.ClipsDescendants = true
	local ingPad = Instance.new("UIPadding")
	ingPad.Name = "gpMaterialPad"
	ingPad.PaddingTop = UDim.new(0, 4)
	ingPad.PaddingBottom = UDim.new(0, 14)
	ingPad.PaddingLeft = UDim.new(0, 6)
	ingPad.PaddingRight = UDim.new(0, 6)
	ingPad.Parent = ingredients
	UIStyler.ListLayout({
		Padding = UDim.new(0, GP_ING_GAP),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = ingredients
	ingredients.ZIndex = 3
	ingredients.Parent = pane
	self._ingredients = ingredients

	-- The readiness meter's host. The StatRow inside is REBUILT per render
	-- because its maxValue (the total parts a batch wants) moves with the
	-- quantity, and StatRow fixes its scale at construction.
	local readinessHost = UIStyler.Frame("ReadinessHost")
	readinessHost.BackgroundColor3 = theme.Colors.Background
	readinessHost.BackgroundTransparency = 1
	readinessHost.Position = UDim2.fromOffset(GP_PAD, 520)
	readinessHost.Size = UDim2.new(1, -GP_PAD * 2, 0, 34)
	readinessHost.ZIndex = 3
	readinessHost.Parent = pane
	self._gpReadinessHost = readinessHost

	-- ---- quantity stepper + the fire control -----------------------------
	-- Plain ASCII glyphs, not the archive's minus/plus art: that art is full
	-- colour and would be the loudest thing on a pastel workbench.
	self._gpMinus = gpButton(theme, pane, "-", theme.Colors.Surface, 0, self._gpShadows, function()
		self:_SetQuantity(self._quantity - 1)
	end)
	self._gpMinus.root.AnchorPoint = Vector2.new(0, 1)
	self._gpMinus.root.Position = UDim2.new(0, GP_PAD, 1, -GP_PAD)
	self._gpMinus.root.Size = UDim2.fromOffset(52, GP_STEP_H)

	local qtyWell = gpPlate(theme, pane, theme.Colors.Accent, 1, self._gpShadows)
	qtyWell.Name = "QtyWell"
	qtyWell.AnchorPoint = Vector2.new(0, 1)
	qtyWell.Position = UDim2.new(0, GP_PAD + 58, 1, -GP_PAD)
	qtyWell.Size = UDim2.fromOffset(84, GP_STEP_H)
	qtyWell.ZIndex = 4

	-- Ink on butter: butter is a LIGHT fill and the near-white TextOnPrimary
	-- would vanish on it. _SetQuantity pulses this label, so the field name
	-- matches the arcade build's and that shared path works unchanged.
	local qty = GPLayoutKit.Text(theme, 28, theme.Colors.TextPrimary, "Qty")
	qty.Text = tostring(self._quantity)
	qty.Size = UDim2.fromScale(1, 1)
	qty.ZIndex = 5
	qty.Parent = qtyWell
	self._qtyLabel = qty

	self._gpPlus = gpButton(theme, pane, "+", theme.Colors.Surface, 1, self._gpShadows, function()
		self:_SetQuantity(self._quantity + 1)
	end)
	self._gpPlus.root.AnchorPoint = Vector2.new(0, 1)
	self._gpPlus.root.Position = UDim2.new(0, GP_PAD + 148, 1, -GP_PAD)
	self._gpPlus.root.Size = UDim2.fromOffset(52, GP_STEP_H)

	self._gpCraft = gpButton(theme, pane, "Fire the kiln", theme.Colors.Secondary, 0, self._gpShadows, function()
		self:_Craft()
	end)
	self._gpCraft.root.AnchorPoint = Vector2.new(1, 1)
	self._gpCraft.root.Position = UDim2.new(1, -GP_PAD, 1, -GP_PAD)
	self._gpCraft.root.Size = UDim2.fromOffset(300, GP_STEP_H)

	self:_RenderList()
	self:_RenderDetail()
end

function CraftingScreen:_GPRenderList()
	-- _gpPage is the definitive "was this tree built under GP" test. A style
	-- change flips LayoutKit() one frame BEFORE the deferred rebuild lands, so
	-- a render can arrive against the previous layout's instances.
	if not self._gpPage or not self._list then
		return
	end
	local theme = self:GetTheme()
	-- Release BEFORE the destroy: a destroyed UIShadow still owes the budget
	-- until its handle is released.
	GPLayoutKit.ReleaseShadows(self._gpRowShadows)
	for _, child in self._list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(self._rows)

	for order, recipe in self._recipes do
		local missing, firstName = shortfall(recipe, 1)
		local ready = missing == 0
		local selected = self._selectedId == recipe.id

		-- SELECTED lifts the plate to the blush surface and lights a butter
		-- rail; unselected sits on the raised cream. Fill AND furniture, never
		-- a colour swap alone.
		local rowFill = if selected then theme.Colors.Surface else theme.Colors.SurfaceRaised
		local row = gpPlate(theme, self._list, rowFill, order, self._gpRowShadows)
		row.Name = "Recipe_" .. recipe.id
		row.LayoutOrder = order
		row.Size = UDim2.new(1, -20, 0, GP_ROW_H)

		local rail = UIStyler.Frame("Rail")
		rail.BackgroundColor3 = theme.Colors.Accent
		rail.AnchorPoint = Vector2.new(0, 0.5)
		rail.Position = UDim2.new(0, 6, 0.5, 0)
		rail.Size = UDim2.fromOffset(6, GP_ROW_H - 28)
		rail.Visible = selected
		rail.ZIndex = 4
		UIStyler.Corner(theme.Radii.Pill).Parent = rail
		rail.Parent = row

		-- The well takes the MIRROR of the row's petal so the two silhouettes
		-- nest instead of fighting.
		local wellFill = theme.Colors.Background
		local well = gpPlate(theme, row, wellFill, order + 1)
		well.Name = "IconWell"
		well.AnchorPoint = Vector2.new(0, 0.5)
		well.Position = UDim2.new(0, 20, 0.5, 0)
		well.Size = UDim2.fromOffset(64, 64)
		well.ZIndex = 3

		local icon = gpArt(theme, well, recipe.icon, 44)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = 4

		local name = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Name")
		name.RichText = false
		name.Text = gpTitleCase(recipe.name)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Position = UDim2.fromOffset(96, 14)
		name.Size = UDim2.new(1, -110, 0, 28)
		name.ZIndex = 3
		name.Parent = row

		-- The arcade row's pip + word, merged: the CHIP is the pip and the
		-- copy inside it is the word, so the state never rides on hue alone.
		local stateChip = gpChip(
			theme,
			row,
			if ready then theme.Colors.Secondary else theme.Colors.Warning,
			if ready then "Ready to fire" else string.format("Missing %d %s", missing, gpTitleCase(firstName or "")),
			order + 1
		)
		stateChip.Position = UDim2.fromOffset(96, 50)
		stateChip.Size = UDim2.fromOffset(GP_STATE_W, 30)
		stateChip.ZIndex = 3

		-- Whole-row hit control (doc §11.6 — no dead zones inside a card).
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 6
		hit.Parent = row
		hit.Activated:Connect(function()
			self._selectedId = recipe.id
			self._quantity = 1
			UIChrome.Pulse(theme, row)
			self:_RenderList()
			self:_RenderDetail()
		end)
		UIChrome.Animate(theme, hit, row)

		table.insert(self._rows, row)
	end
end

function CraftingScreen:_GPRenderDetail()
	-- Same deferred-rebuild guard as _GPRenderList, plus the two fields this
	-- path writes that only the GP build creates.
	if not self._gpPage or not self._gpReadinessHost or not self._gpCraft then
		return
	end
	local theme = self:GetTheme()
	local recipe = self:_Selected()
	if not recipe or not self._ingredients then
		return
	end
	self._selectedId = recipe.id

	GPLayoutKit.ReleaseShadows(self._gpDetailShadows)

	if self._resultArt then
		self._resultArt:Destroy()
	end
	local art = gpArt(theme, self._resultWell, recipe.icon, 104, { golden = true })
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.ZIndex = 5
	self._resultArt = art

	local perCraft = if type(recipe.output) == "number" then recipe.output else 1
	self._resultName.Text = gpTitleCase(recipe.name)
	-- The arcade line's exact two facts, sentence-cased (pack law 5).
	self._resultOutput.Text = string.format("Makes x%d  ·  %d batch", perCraft * self._quantity, self._quantity)
	self._qtyLabel.Text = tostring(self._quantity)

	for _, row in self._ingredientRows do
		row:Destroy()
	end
	table.clear(self._ingredientRows)

	for order, ingredient in recipe.ingredients do
		local need = ingredient.need * self._quantity
		local satisfied = ingredient.have >= need

		local row = gpPlate(theme, self._ingredients, theme.Colors.SurfaceRaised, order, self._gpDetailShadows)
		row.Name = "Material" .. order
		row.LayoutOrder = order
		row.Size = UDim2.new(1, -16, 0, GP_ING_ROW_H)

		local icon = gpArt(theme, row, ingredient.icon, 34)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 14, 0.5, 0)
		icon.ZIndex = 3

		local name = GPLayoutKit.Text(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Name")
		name.RichText = false
		name.Text = gpTitleCase(ingredient.name)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Position = UDim2.fromOffset(58, 0)
		-- Stops short of the counts column so a long material name truncates
		-- instead of colliding with its numbers.
		name.Size = UDim2.new(1, -(58 + GP_COUNT_W + GP_ING_CHIP_W + 40), 1, 0)
		name.ZIndex = 3
		name.Parent = row

		-- Tabular numerals in INK: the have/need pair is a DATA column, and
		-- the pack's matcha/coral would not clear 4.5:1 as small type on this
		-- cream — the chip beside it carries the hue instead.
		local counts = GPLayoutKit.NumberText(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Counts")
		counts.Text = string.format("%d / %d", ingredient.have, need)
		counts.AnchorPoint = Vector2.new(1, 0.5)
		counts.Position = UDim2.new(1, -(GP_ING_CHIP_W + 22), 0.5, 0)
		counts.Size = UDim2.fromOffset(GP_COUNT_W, GP_ING_ROW_H)
		counts.ZIndex = 3
		counts.Parent = row

		local chip = gpChip(
			theme,
			row,
			if satisfied then theme.Colors.Secondary else theme.Colors.Warning,
			-- The arcade row prints a check OR the exact shortfall; this one
			-- prints a word AND, when short, the exact shortfall.
			if satisfied then "Have it" else string.format("-%d", need - ingredient.have),
			order + 1
		)
		chip.AnchorPoint = Vector2.new(1, 0.5)
		chip.Position = UDim2.new(1, -14, 0.5, 0)
		chip.Size = UDim2.fromOffset(GP_ING_CHIP_W, 30)
		chip.ZIndex = 3

		table.insert(self._ingredientRows, row)
	end

	-- The readiness meter, rebuilt because its scale moves with the quantity.
	local host = self._gpReadinessHost
	for _, child in host:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local have, need = readiness(recipe, self._quantity)
	GPLayoutKit.StatRow(theme, host, {
		label = "Readiness",
		value = have,
		maxValue = math.max(need, 1),
		unit = "parts",
		precision = 0,
		accent = theme.Colors.Secondary,
		heightPx = 34,
	})

	-- Blocked = quietened IN PLACE; the tap still answers with the reason.
	local missing = select(1, shortfall(recipe, self._quantity))
	gpSetFill(theme, self._gpCraft, if missing > 0 then theme.Colors.Disabled else theme.Colors.Secondary)
	gpSetFill(theme, self._gpMinus, if self._quantity <= 1 then theme.Colors.Disabled else theme.Colors.Surface)
	gpSetFill(theme, self._gpPlus, if self._quantity >= MAX_QTY then theme.Colors.Disabled else theme.Colors.Surface)
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts live in
-- StyleKit.Capabilities and only fall when a handle is released — so every
-- GP shadow handle is handed back here.
function CraftingScreen:_OnTeardown()
	GPLayoutKit.ReleaseShadows(self._gpDetailShadows)
	GPLayoutKit.ReleaseShadows(self._gpRowShadows)
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpPage = nil
	self._gpReadinessHost = nil
	self._gpMinus, self._gpPlus, self._gpCraft = nil, nil, nil
	self._resultArt = nil
end

return CraftingScreen
