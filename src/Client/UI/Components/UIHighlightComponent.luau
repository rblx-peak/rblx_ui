--!strict
-- Reusable "spotlight" annotation that draws a shape around an arbitrary
-- target GuiObject (Circle / Square / RoundedSquare) and optionally a
-- directional arrow pointing at it. Used by TutorialScreen; general enough
-- for any future "point at this UI element" need (quest markers, hints, …).
--
-- The old ad-hoc version of this (a one-off ring built inline in
-- TutorialScreen) computed the target's on-screen box ONCE per step and
-- never again — so it visibly drifted off the real target the moment the
-- viewport resized or the target itself moved/resized (an animated panel,
-- a HUD region reflowing). Track() fixes that at the root: instead of a
-- single snapshot, it wires live PropertyChangedSignal connections on both
-- the target and this component's own parent, so every AbsolutePosition/
-- AbsoluteSize change (viewport resize, target animating, parent reflow)
-- immediately repositions the highlight — no polling loop needed.
--
-- Extra props:
--   shape           : "Circle" | "Square" | "RoundedSquare" (default "RoundedSquare")
--   padding         : px gap between the target's real edge and the drawn ring (default 8)
--   strokeThickness : px (default 3 — the gold selection ring per doc §4.3;
--                     a styled chrome defaults to its own stroke weight instead)
--   colorToken      : legacy theme Colors token for the stroke + arrow glyph.
--                     Default is NO token: the ring paints in the gold
--                     selection colour (theme.Semantic.Selection) — gold =
--                     "this is selected / active / valuable" (doc §3.3)
--   imageId         : rbxassetid:// image used for the ring INSTEAD of the drawn
--                     corner+stroke (placeholder drawn shapes are the default —
--                     what most callers should keep using; imageId is an escape
--                     hatch for a custom ring graphic)
--   showArrow       : boolean (default false)
--   arrowDirection  : "Up" | "Down" | "Left" | "Right" (default "Up") — the arrow
--                     sits just OUTSIDE the ring on this side and points INWARD at
--                     it, e.g. "Up" sits below the ring pointing up into it
--   arrow           : glyph override (default is a plain ▲▼◀▶ per direction)
--   arrowImageId    : rbxassetid:// image used for the arrow instead of the glyph —
--                     authored pointing UP; auto-rotated to match arrowDirection
--
-- Call Track(targetOrNil) to start/stop following a target; call it again with
-- a different target to retarget (e.g. advancing to the next tutorial step).

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIComponentBase = require(script.Parent.UIComponentBase)

local UIHighlightComponent = setmetatable({}, { __index = UIComponentBase })
UIHighlightComponent.__index = UIHighlightComponent

local ARROW_GAP = 6
local ARROW_GLYPH = { Up = "▲", Down = "▼", Left = "◀", Right = "▶" }
-- Assumes the custom arrow image is authored pointing UP; rotated to match
-- whichever side/direction the caller asked for.
local ARROW_ROTATION = { Up = 0, Right = 90, Down = 180, Left = 270 }

function UIHighlightComponent.new()
	local self = UIComponentBase.new("UIHighlight")
	self._target = nil :: GuiObject?
	self._trackConnections = {} :: { RBXScriptConnection }
	return setmetatable(self, UIHighlightComponent)
end

function UIHighlightComponent:_Build(props: Types.UIComponentProps)
	local root = self.Root
	root.BackgroundTransparency = 1
	-- Real Size/Position are computed entirely by _Reposition once tracking
	-- starts; this is just a safe non-visible starting state.
	root.Size = UDim2.fromOffset(0, 0)
	root.Visible = false

	-- RoundedSquare default; a HardCorners style flattens it (see _ApplyContent,
	-- which re-derives this radius per shape).
	self._corner = UIStyler.Corner(if UIChrome.ActiveChrome().HardCorners then 0 else 14)
	self._corner.Parent = root
	self._stroke = UIStyler.Stroke(Color3.new(1, 1, 1), 3)
	self._stroke.Parent = root

	-- Image variant of the ring itself — hidden unless props.imageId is set
	-- (see _ApplyContent). Kept as a permanent sibling instead of swapped in/
	-- out so SetContent can toggle between drawn/image at runtime for free.
	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.ScaleType = Enum.ScaleType.Fit
	image.Visible = false
	image.Parent = root
	self._image = image

	-- Arrow: anchored to whichever edge of Root its direction points from, so
	-- as a CHILD of Root it rides along automatically with every reposition —
	-- no separate tracking needed for it.
	local arrowHolder = UIStyler.Frame("Arrow")
	arrowHolder.BackgroundTransparency = 1
	arrowHolder.Size = UDim2.fromOffset(32, 32)
	arrowHolder.Visible = false
	arrowHolder.ZIndex = 2
	arrowHolder.Parent = root
	self._arrowHolder = arrowHolder

	local arrowGlyph = UIStyler.TextLabel("Glyph")
	arrowGlyph.RichText = false
	arrowGlyph.Size = UDim2.fromScale(1, 1)
	-- ▲▼◀▶ are symbol glyphs, so FontFace is assigned explicitly (never left
	-- on a default font with missing glyphs) — the style's display font, set
	-- in _Style (the first paint runs synchronously inside Create), carries
	-- the doc's Unicode iconography (§10), and every display-font string gets
	-- the style's text emphasis (§2). TextScaled stays the LAST wrap-related
	-- assignment.
	UIChrome.TextOutline(arrowGlyph)
	arrowGlyph.TextScaled = true
	self._arrowGlyphConstraint = UIStyler.TextSizeConstraint(32, 12)
	self._arrowGlyphConstraint.Parent = arrowGlyph
	arrowGlyph.Parent = arrowHolder
	self._arrowGlyph = arrowGlyph

	local arrowImage = Instance.new("ImageLabel")
	arrowImage.Name = "Image"
	arrowImage.BackgroundTransparency = 1
	arrowImage.Size = UDim2.fromScale(1, 1)
	arrowImage.ScaleType = Enum.ScaleType.Fit
	arrowImage.Visible = false
	arrowImage.Parent = arrowHolder
	self._arrowImage = arrowImage

	self:_ApplyContent(props)
end

-- Update shape/image/arrow config without rebuilding or losing tracking —
-- callers (e.g. a tutorial step) can restyle the highlight, then Track() a
-- (possibly different) target.
function UIHighlightComponent:SetContent(props: Types.UIComponentProps)
	for key, value in props do
		self.Props[key] = value
	end
	self:_ApplyContent(self.Props)
	if self.Theme then
		self:_Style(self.Theme)
	end
end

function UIHighlightComponent:_ApplyContent(props: Types.UIComponentProps)
	local shape = props.shape or "RoundedSquare"
	-- "Circle" is deliberately allowed despite the hard-arcade 90° rule:
	-- circles are the arcade's round exception (doc §4.2 — win pips, cursor
	-- rings, world/selection circles), and a spotlight ring is exactly that.
	if shape == "Circle" then
		self._corner.CornerRadius = UDim.new(0.5, 0)
	elseif shape == "Square" then
		self._corner.CornerRadius = UDim.new(0, 0)
	else
		-- RoundedSquare: the doc's 14px spotlight rounding, flattened when the
		-- active style declares HardCorners (the arcade's Circle exception
		-- above is geometry, not decoration, so it stays round).
		self._corner.CornerRadius = UDim.new(0, if UIChrome.ActiveChrome().HardCorners then 0 else 14)
	end
	self._stroke.Thickness = props.strokeThickness or 3

	local hasImage = props.imageId ~= nil and props.imageId ~= ""
	self._stroke.Enabled = not hasImage
	self._image.Visible = hasImage
	if hasImage then
		self._image.Image = props.imageId :: string
	end

	local showArrow = props.showArrow == true
	self._arrowHolder.Visible = showArrow
	if showArrow then
		local direction = (props.arrowDirection :: string?) or "Up"
		self:_PositionArrow(direction)
		local hasArrowImage = props.arrowImageId ~= nil and props.arrowImageId ~= ""
		self._arrowImage.Visible = hasArrowImage
		self._arrowGlyph.Visible = not hasArrowImage
		if hasArrowImage then
			self._arrowImage.Image = props.arrowImageId :: string
			self._arrowImage.Rotation = ARROW_ROTATION[direction] or 0
		else
			self._arrowGlyph.Text = (props.arrow :: string?) or ARROW_GLYPH[direction] or ARROW_GLYPH.Up
		end
	end
end

function UIHighlightComponent:_PositionArrow(direction: string)
	local holder = self._arrowHolder
	if direction == "Down" then
		holder.AnchorPoint = Vector2.new(0.5, 1)
		holder.Position = UDim2.new(0.5, 0, 0, -ARROW_GAP)
	elseif direction == "Left" then
		holder.AnchorPoint = Vector2.new(0, 0.5)
		holder.Position = UDim2.new(1, ARROW_GAP, 0.5, 0)
	elseif direction == "Right" then
		holder.AnchorPoint = Vector2.new(1, 0.5)
		holder.Position = UDim2.new(0, -ARROW_GAP, 0.5, 0)
	else -- "Up"
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.Position = UDim2.new(0.5, 0, 1, ARROW_GAP)
	end
end

-- Start (or stop, with nil) following a target. Safe to call repeatedly with
-- a new target — e.g. once per tutorial step — always tears down the
-- previous connections first.
function UIHighlightComponent:Track(target: GuiObject?)
	for _, connection in self._trackConnections do
		connection:Disconnect()
	end
	table.clear(self._trackConnections)
	self._target = target

	if not target then
		self.Root.Visible = false
		return
	end

	local function reposition()
		self:_Reposition()
	end
	table.insert(self._trackConnections, target:GetPropertyChangedSignal("AbsolutePosition"):Connect(reposition))
	table.insert(self._trackConnections, target:GetPropertyChangedSignal("AbsoluteSize"):Connect(reposition))
	-- If the target is destroyed/unparented while tracked (e.g. a rebuilt nav
	-- rail), stop cleanly and hide instead of drifting to a stale position.
	table.insert(
		self._trackConnections,
		target.AncestryChanged:Connect(function(_, newParent)
			if not newParent then
				self:Track(nil)
			end
		end)
	)
	local parent = self.Root.Parent
	if parent and parent:IsA("GuiObject") then
		table.insert(self._trackConnections, parent:GetPropertyChangedSignal("AbsolutePosition"):Connect(reposition))
		table.insert(self._trackConnections, parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(reposition))
	end
	reposition()
end

function UIHighlightComponent:_Reposition()
	local target = self._target
	if not target or not target.Parent then
		self.Root.Visible = false
		return
	end
	-- Target hasn't resolved a real size yet (built this frame, AutomaticSize
	-- still settling) — skip this pass; the next AbsoluteSize change retries.
	if target.AbsoluteSize.X <= 0 or target.AbsoluteSize.Y <= 0 then
		return
	end
	local parent = self.Root.Parent
	if not parent or not parent:IsA("GuiObject") then
		return
	end
	local parentPos = (parent :: GuiObject).AbsolutePosition
	local padding = (self.Props.padding :: number?) or 8
	local localX = target.AbsolutePosition.X - parentPos.X - padding
	local localY = target.AbsolutePosition.Y - parentPos.Y - padding
	self.Root.Position = UDim2.fromOffset(localX, localY)
	self.Root.Size = UDim2.fromOffset(target.AbsoluteSize.X + padding * 2, target.AbsoluteSize.Y + padding * 2)
	self.Root.Visible = true
end

function UIHighlightComponent:_Style(theme: Types.UITheme)
	-- Default ring = the gold selection colour (doc §3.3/§4.3: gold means
	-- "this is selected / active / valuable"). A colorToken prop still lets a
	-- caller point at any legacy Colors token instead.
	local token = self.Props.colorToken :: string?
	local color: Color3 = theme.Semantic.Selection
	if token then
		color = (theme.Colors :: any)[token] or theme.Semantic.Selection
	end
	self._stroke.Color = color
	-- A styled chrome (theme.Chrome) rings at its own stroke weight — the same
	-- weight UIChrome's Selection intent resolves to — unless the caller pinned
	-- an explicit strokeThickness; Classic keeps the doc's 3px default.
	local chrome = theme.Chrome
	if chrome and self.Props.strokeThickness == nil then
		self._stroke.Thickness = math.max(chrome.StrokeThickness, 1)
	end
	-- Custom images (ring or arrow) are left untinted/as-authored — matches
	-- the convention elsewhere (e.g. UIButtonComponent never tints iconImage)
	-- so a multi-color custom asset never gets unexpectedly recolored.
	self._arrowGlyph.TextColor3 = color
	-- Re-assert the arrow's display styling on every theme paint: the style's
	-- display font wearing the style's text emphasis (outline or glow), set
	-- AFTER the colour so a styled glow tracks it.
	self._arrowGlyph.FontFace = theme.Fonts.Title
	UIChrome.TextOutline(self._arrowGlyph)
end

function UIHighlightComponent:Destroy()
	for _, connection in self._trackConnections do
		connection:Disconnect()
	end
	table.clear(self._trackConnections)
	UIComponentBase.Destroy(self)
end

return UIHighlightComponent
