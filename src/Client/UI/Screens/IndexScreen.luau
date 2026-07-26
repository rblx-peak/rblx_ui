--!strict
-- Index (collection browse) screen — Pottery Clash arcade family.
-- One §7.4 modal card ("INDEX") holding a gold category label, a scrollable
-- 5-column grid of square collection tiles (near-black arcade boxes; every
-- 4th tile locked behind the flat-cartoon Lock icon, unlocked tiles carrying
-- a gold "?" art placeholder) and a fixed footer: the gold ruler progress bar
-- (0/15 FOUND) + a green "x0" arcade badge. Browse-only: no live-data wiring.
--
-- Authored in fixed px at the 1650×1020 baseline (UIScreenBase attaches the
-- UIScale). Square tiles recompute their px CellSize from the scroll's live
-- AbsoluteSize (divided back through the baseline scale) so every tile stays
-- a true square at any viewport, exactly like the old reference grid did.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIAssets = require(script.Parent.Parent.Config.UIAssets)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIProgressBarComponent = require(script.Parent.Parent.Components.UIProgressBarComponent)
local UIBadgeComponent = require(script.Parent.Parent.Components.UIBadgeComponent)

local IndexScreen = setmetatable({}, { __index = UIScreenBase })
IndexScreen.__index = IndexScreen

local COLUMNS = 5
local TILE_COUNT = 15
local CELL_PAD_PX = 12 -- gap between square tiles, both axes
local SCROLLBAR_RESERVE_PX = 10 -- keeps the 5th column clear of the scrollbar
local FOOTER_H_PX = 52

function IndexScreen.new()
	local self = UIScreenBase.new("IndexScreen", 6)
	return setmetatable(self, IndexScreen)
end

-- One square collection tile. Placeholder content: locked tiles are the
-- dimmer NearBlack2 well behind the Lock icon; unlocked tiles show a gold
-- FredokaOne "?" art placeholder. Both carry the arcade chrome explicitly
-- (3px black stroke + glass sheen) so the look doesn't lean on the enforcer.
local function buildTile(theme: Types.UITheme, parent: Instance, index: number)
	local locked = index % 4 == 0
	local tile = UIStyler.Frame("Tile" .. index)
	tile.BackgroundTransparency = 0
	tile.BackgroundColor3 = if locked then theme.Arcade.NearBlack2 else theme.Arcade.NearBlack
	tile.LayoutOrder = index
	UIChrome.Stroke(theme, "Arcade").Parent = tile
	UIChrome.GlassGradient().Parent = tile

	if locked then
		-- Locked = dimmed in place (doc §11.2 language: dim, never remove).
		tile.BackgroundTransparency = 0.35
		local lock = UIAssets.Icon(tile, "Lock", 36)
		lock.AnchorPoint = Vector2.new(0.5, 0.5)
		lock.Position = UDim2.fromScale(0.5, 0.5)
		lock.ImageTransparency = 0.3
	else
		local art = UIChrome.Text("Art", 44, theme.Arcade.Gold)
		art.Text = "?"
		art.Size = UDim2.fromScale(1, 1)
		art.Parent = tile
	end

	tile.Parent = parent
end

function IndexScreen:_BuildContent()
	local theme = self:GetTheme()

	-- The one modal recipe (doc §7.4): dim → 920×680 card → red header with
	-- the title + close X → transparent content inset.
	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "INDEX",
		sizePx = Vector2.new(920, 680),
		onClose = function()
			self.ScreenController:HideScreen("index")
		end,
	})
	self._modal = modal
	local content = modal.content

	-- Category label: gold display type, 20px (doc §2 label tier).
	local category = UIChrome.Text("Category", 20, theme.Arcade.Gold)
	category.Text = "COLLECTION"
	category.TextXAlignment = Enum.TextXAlignment.Left
	category.Size = UDim2.new(1, 0, 0, 24)
	category.Parent = content

	-- Scrollable tile grid between the category label and the fixed footer.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Tiles"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 32)
	scroll.Size = UDim2.new(1, 0, 1, -(32 + FOOTER_H_PX + 12))
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Arcade.Gold
	scroll.Parent = content

	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(CELL_PAD_PX, CELL_PAD_PX)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirectionMaxCells = COLUMNS
	grid.Parent = scroll

	-- SQUARE cells in px: derive the cell edge from the scroll's live width so
	-- 5 columns always fit and every tile is a true square. AbsoluteSize is in
	-- real screen px, so divide the baseline UIScale back out first (offsets we
	-- assign get re-multiplied by that scale when rendered). Re-run on resize.
	local baseline = self.Root:FindFirstChild("BaselineScale")
	local function squareCells()
		local s = 1
		if baseline and baseline:IsA("UIScale") and baseline.Scale > 0 then
			s = baseline.Scale
		end
		local width = scroll.AbsoluteSize.X / s
		local cell = (width - SCROLLBAR_RESERVE_PX - CELL_PAD_PX * (COLUMNS - 1)) / COLUMNS
		local edge = math.max(1, math.floor(cell))
		grid.CellSize = UDim2.fromOffset(edge, edge)
	end
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(squareCells)
	squareCells()

	for i = 1, TILE_COUNT do
		buildTile(theme, scroll, i)
	end

	-- Fixed footer: gold ruler progress (doc §8) + green "x0" arcade badge.
	local footer = UIStyler.Frame("Footer")
	footer.BackgroundTransparency = 1
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.fromScale(0, 1)
	footer.Size = UDim2.new(1, 0, 0, FOOTER_H_PX)
	footer.Parent = content

	self._progress = UIProgressBarComponent.new()
	self._progress:Create(footer, {
		value = 0,
		maxValue = TILE_COUNT,
		label = "FOUND",
		size = UDim2.new(1, -96, 0, 26),
		position = UDim2.fromScale(0, 0.5),
		anchorPoint = Vector2.new(0, 0.5),
	})

	self._badge = UIBadgeComponent.new()
	self._badge:Create(footer, {
		text = "x0",
		variant = "New", -- Arcade green (doc §3.2)
		size = UDim2.new(0, 0, 0, 26), -- width auto-sizes off the label
		position = UDim2.fromScale(1, 0.5),
		anchorPoint = Vector2.new(1, 0.5),
	})
end

-- Open is an instant Visible flip (base); the pop lives on the CONTENT, not
-- the container (doc §7.4).
function IndexScreen:_OnShow(_data: any?)
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function IndexScreen:Destroy()
	if self._progress then
		self._progress:Destroy()
		self._progress = nil
	end
	if self._badge then
		self._badge:Destroy()
		self._badge = nil
	end
	UIScreenBase.Destroy(self)
end

return IndexScreen
