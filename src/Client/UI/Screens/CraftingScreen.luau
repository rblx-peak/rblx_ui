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

return CraftingScreen
