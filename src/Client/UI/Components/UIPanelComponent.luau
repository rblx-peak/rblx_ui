--!strict
-- The §7.4 modal CARD (UI_DESIGN_DOCUMENT.md) — one recipe for every menu.
-- Root IS the card: pure black at 0.4 BackgroundTransparency (the world stays
-- visible through every menu), hard 90° arcade corners, 3px black stroke,
-- glass sheen. On top sits the red 64px header bar (title FredokaOne 34 white
-- at x=18, 48×48 red close X at the right end) and the transparent Body
-- content frame inset (14, 74, −28, −88). The full-screen black dim @ 0.45 is
-- the OWNING SCREEN's job (ladder, doc §7.3: dim 40 < card 41 < content 42).
--
-- Open/close is an instant Visible flip (doc §5: things pop in and hard-hide
-- out): AnimateIn() pops the CONTENTS (UIChrome.PopIn on Body) and returns
-- nil; AnimateOut() returns nil so UIScreenBase disables the Gui instantly.
--
-- Extra props:
--   titleKey / title
--   showClose : boolean (default true)
--   onClose   : () -> ()

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local UIComponentBase = require(script.Parent.UIComponentBase)

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

-- The fixed header bar height (doc §7.4); the Body inset derives from it.
local HEADER_HEIGHT = 64

local UIPanelComponent = setmetatable({}, { __index = UIComponentBase })
UIPanelComponent.__index = UIPanelComponent

function UIPanelComponent.new()
	local self = UIComponentBase.new("UIPanel")
	return setmetatable(self, UIPanelComponent)
end

function UIPanelComponent:_Build(props: Types.UIComponentProps)
	local root = self.Root

	-- Root = the card. Pure black @ 0.4 so the world reads through the menu.
	-- Hard corners are the arcade default (no UICorner at all); the 3px black
	-- stroke is attached in _Style via UIChrome.Stroke (the policy helper
	-- takes the theme).
	root.BackgroundColor3 = BLACK
	root.BackgroundTransparency = 0.4
	root.ZIndex = 41
	if not props.anchorPoint then
		root.AnchorPoint = Vector2.new(0.5, 0.5)
	end
	if not props.position then
		root.Position = UDim2.fromScale(0.5, 0.5)
	end
	if not props.size then
		-- Fixed-size card, px at the 1650×1020 baseline (UIScreenBase's
		-- UIScale handles devices); screens pass their own px size.
		root.Size = UDim2.fromOffset(820, 560)
		self._baseSize = root.Size
	end
	UIChrome.GlassGradient().Parent = root

	-- The red 64px header bar with the glass sheen. The frame itself carries
	-- the fill (painted in _Style: theme.Arcade.HeaderRed). Public: screens
	-- parent extra header-row content here (ShopScreen's currency chips) —
	-- the title deliberately claims only the left ~60% of the bar so the
	-- right end stays free for them and the close X.
	local header = UIStyler.Frame("Header")
	header.BackgroundTransparency = 0
	header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	header.ZIndex = 42
	-- Tag for the ClientHandler ThemeChanged sweep: palette presets move the
	-- header hue, and the sweep retints every live header instantly — the
	-- component's own _Style tween is the polish on top, the tag is the
	-- guarantee ("the head trim wasn't changing" — the owner).
	game:GetService("CollectionService"):AddTag(header, UIChrome.HEADER_TAG)
	UIChrome.GlassGradient().Parent = header
	header.Parent = root
	self._header = header
	self.Header = header

	-- Title: FredokaOne 34 white with the black outline, left-aligned at x=18.
	local title = UIChrome.Text("Title", 34, WHITE)
	title.Text = TextConfig.Resolve(props.titleKey or props.title)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(18, 0)
	title.Size = UDim2.new(0.6, -18, 1, 0)
	-- Plain text only: TextTruncate is ignored while RichText is on, and a
	-- long title must clip with "…" instead of running under header widgets.
	title.RichText = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 43
	title.Parent = header
	self._title = title

	if props.showClose ~= false then
		-- The 48×48 red close X (doc §7.4). Fixed px is safe now that the
		-- header is a fixed 64px bar — no AbsoluteSize-derived sizing. Plain
		-- "X": FredokaOne has no ✕ glyph. The font, stroke, red fill +
		-- UIChrome.Animate land in _Style (they need the theme; Animate is
		-- applied LAST, after the final colours, because it snapshots the
		-- rest colour).
		local close = Instance.new("TextButton")
		close.Name = "Close"
		close.Size = UDim2.fromOffset(48, 48)
		close.AnchorPoint = Vector2.new(1, 0.5)
		close.Position = UDim2.new(1, -8, 0.5, 0)
		close.BackgroundTransparency = 0
		close.BorderSizePixel = 0
		close.AutoButtonColor = false
		close.Text = "X"
		close.TextSize = 28
		close.TextColor3 = WHITE
		UIChrome.TextOutline(close)
		UIChrome.ArcadeBevel().Parent = close
		close.ZIndex = 43
		game:GetService("CollectionService"):AddTag(close, UIChrome.CLOSE_TAG)
		close.Parent = header
		self._close = close
		self:_Connect(close.Activated, function()
			if self.Props.onClose then
				self.Props.onClose()
			end
		end)
	end

	-- Body: transparent content frame inset (14, 74, −28, −88) — children go
	-- here. AnimateIn pops THIS (the contents), never the card container.
	local body = UIStyler.Frame("Body")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(14, HEADER_HEIGHT + 10)
	body.Size = UDim2.new(1, -28, 1, -(HEADER_HEIGHT + 24))
	body.ZIndex = 42
	body.Parent = root
	self.Body = body
end

-- Open is an INSTANT flip (doc §7.4) — no container tween. The pop/juice
-- lives on the contents: POP_IN (0.82 → 1 Back Out) on Body. Returns nil so
-- the owning screen treats the show as instantaneous.
function UIPanelComponent:AnimateIn(): Tween?
	self.Root.Visible = true
	local theme = self.Theme
	if theme then
		UIChrome.PopIn(theme, self.Body)
	end
	return nil
end

-- Hard-hide out (doc §5): nothing to tween — returning nil makes
-- UIScreenBase disable its Gui instantly.
function UIPanelComponent:AnimateOut(): Tween?
	return nil
end

function UIPanelComponent:_Style(theme: Types.UITheme)
	-- One-time chrome that needs the theme: the card's 3px black stroke comes
	-- from the UIChrome policy helper (never hand-rolled).
	if not self._stroke then
		self._stroke = UIChrome.Stroke(theme, "Arcade")
		self._stroke.Parent = self.Root
	end
	self:_SetColor(self._header, "BackgroundColor3", theme.Arcade.HeaderRed)
	if self._close then
		-- Display font for the X (Classic: FredokaOne) — theme-driven so
		-- live style swaps land.
		self._close.FontFace = theme.Fonts.Title
		if not self._closeStroke then
			-- 2px black — the close recipe's one deviation from the 3px card
			-- stroke (matches UIChrome's own close-button recipe). Styled
			-- chrome frames the X like every other surface (hairline) instead.
			self._closeStroke = if theme.Chrome ~= nil
				then UIChrome.Stroke(theme, "Arcade", "Button")
				else UIStyler.Stroke(BLACK, 2, 0)
			self._closeStroke.Parent = self._close
		end
		self:_SetColor(self._close, "BackgroundColor3", theme.Arcade.Red)
		if not self._closeAnimated then
			self._closeAnimated = true
			-- Contract: Animate is applied LAST, after the final colours —
			-- it snapshots the rest colour (and re-captures it every hover,
			-- so later theme swaps stay correct).
			UIChrome.Animate(theme, self._close)
		end
	end
end

return UIPanelComponent
