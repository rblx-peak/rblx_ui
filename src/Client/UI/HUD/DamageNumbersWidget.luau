--!strict
-- Floating damage numbers (HUD widget): world-anchored FredokaOne numerals
-- with the full black outline (doc §2 — this is world-space text grammar
-- rendered in 2D, so the outline is what lets it sit over any scene), rising
-- ~60px over 0.9s with a little random horizontal drift and a late fade.
--
-- Colour IS the kind (doc §3.3): white damage, gold crit, green heal.
--
-- THE LABELS ARE POOLED — 24 of them, allocated once. A combat HUD can spawn
-- a dozen numbers a second; creating and destroying TextLabels at that rate is
-- the single most reliable way to make a fight hitch. Show() takes a free
-- label (or steals the oldest live one) and a finished number just hides and
-- returns to the pool.

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local HUDWidgetBase = require(script.Parent.HUDWidgetBase)

local DamageNumbersWidget = setmetatable({}, { __index = HUDWidgetBase })
DamageNumbersWidget.__index = DamageNumbersWidget

local POOL_SIZE = 24
local LIFETIME = 0.9
local RISE_PX = 60
local DRIFT_PX = 22
local FADE_START = 0.45 -- fraction of the life where the fade begins
local LABEL_W, LABEL_H = 160, 44

local KINDS: { [string]: { size: number, colorToken: string, prefix: string, suffix: string } } = {
	damage = { size = 26, colorToken = "White", prefix = "", suffix = "" },
	crit = { size = 36, colorToken = "Gold", prefix = "", suffix = "!" },
	heal = { size = 26, colorToken = "MoneyGreen", prefix = "+", suffix = "" },
}

function DamageNumbersWidget.new()
	local self = HUDWidgetBase.new("damage", "DamageNumbersWidget")
	self._pool = {} :: { TextLabel }
	self._live = {} :: { any }
	self._random = Random.new()
	return setmetatable(self, DamageNumbersWidget)
end

function DamageNumbersWidget:_Build(_props: HUDWidgetBase.Props)
	for i = 1, POOL_SIZE do
		local label = UIChrome.Text("Number" .. i, 26, Color3.new(1, 1, 1))
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Size = UDim2.fromOffset(LABEL_W, LABEL_H)
		label.Visible = false
		label.ZIndex = 2
		label.Parent = self.Root
		table.insert(self._pool, label)
	end

	self:_RenderStep(function(_dt: number, clock: number)
		self:_Step(clock)
	end)
end

-- ---- API ---------------------------------------------------------------

-- data: { hits = { {position = Vector3, amount, kind} } }
function DamageNumbersWidget:Update(data: any)
	if type(data) ~= "table" then
		return
	end
	for _, hit in (data.hits or {}) do
		self:Show(hit.position, hit.amount or 0, hit.kind)
	end
end

-- kind: "damage" (default) | "crit" | "heal"
function DamageNumbersWidget:Show(worldPosition: Vector3, amount: number, kind: string?)
	local entry = self:_Take(amount, kind)
	if entry then
		entry.world = worldPosition
	end
end

-- Screen-space variant (fractions of the viewport, 0..1) for hosts and demos
-- that have a hit but no world position — e.g. a UI-driven practice mode.
function DamageNumbersWidget:ShowAt(fraction: Vector2, amount: number, kind: string?)
	local entry = self:_Take(amount, kind)
	if entry then
		entry.world = nil
		entry.fraction = fraction
	end
end

function DamageNumbersWidget:_Take(amount: number, kind: string?)
	local label = table.remove(self._pool)
	if not label then
		local oldest = table.remove(self._live, 1)
		if not oldest then
			return nil
		end
		label = oldest.label
	end
	assert(label)

	local spec = KINDS[kind or "damage"] or KINDS.damage
	label.Text = spec.prefix .. HUDWidgetBase.Commas(math.abs(amount)) .. spec.suffix
	label.TextSize = spec.size
	label.TextColor3 = self:_KindColor(spec.colorToken)
	label.TextTransparency = 0
	UIChrome.TextOutline(label)
	label.Visible = true

	local entry = {
		label = label,
		kind = kind or "damage",
		world = nil :: Vector3?,
		fraction = nil :: Vector2?,
		born = os.clock(),
		drift = self._random:NextNumber(-DRIFT_PX, DRIFT_PX),
	}
	table.insert(self._live, entry)
	return entry
end

function DamageNumbersWidget:_KindColor(token: string): Color3
	local arcade = self.Theme.Arcade
	if token == "Gold" then
		return arcade.Gold
	elseif token == "MoneyGreen" then
		return arcade.MoneyGreen
	end
	return self.Theme.Colors.TextPrimary
end

-- ---- per-frame ---------------------------------------------------------

function DamageNumbersWidget:_Step(clock: number)
	if #self._live == 0 then
		return
	end
	local camera = workspace.CurrentCamera
	-- The span viewport coordinates are measured against: the ScreenGui's own
	-- AbsoluteSize already accounts for the topbar inset the HUD layer
	-- respects, and (unlike our root) it is not multiplied by the baseline
	-- UIScale, so the fraction below stays correct at every viewport size.
	local gui = self.Root:FindFirstAncestorOfClass("ScreenGui")
	local span = (gui and gui.AbsoluteSize) or (camera and camera.ViewportSize)
	if not span or span.X <= 0 or span.Y <= 0 then
		return
	end

	for i = #self._live, 1, -1 do
		local entry = self._live[i]
		local u = (clock - entry.born) / LIFETIME
		if u >= 1 then
			entry.label.Visible = false
			table.remove(self._live, i)
			table.insert(self._pool, entry.label)
		else
			local fx, fy = -1, -1
			if entry.world and camera then
				local point = camera:WorldToViewportPoint(entry.world)
				if point.Z <= 0 then
					-- Behind the camera: WorldToViewportPoint mirrors the point
					-- to the wrong side of the screen, so hide rather than lie.
					entry.label.Visible = false
					continue
				end
				fx, fy = point.X / span.X, point.Y / span.Y
			elseif entry.fraction then
				fx, fy = entry.fraction.X, entry.fraction.Y
			else
				continue
			end

			-- Ease-out rise: fast off the hit, settling as it fades.
			local eased = 1 - (1 - u) * (1 - u)
			entry.label.Visible = true
			entry.label.Position = UDim2.new(fx, entry.drift * u, fy, -RISE_PX * eased)
			local fade = u <= FADE_START and 0 or (u - FADE_START) / (1 - FADE_START)
			entry.label.TextTransparency = fade
			UIChrome.TextOutline(entry.label, fade)
		end
	end
end

function DamageNumbersWidget:_Style(theme: Types.UITheme)
	for _, label in self._pool do
		label.FontFace = theme.Fonts.Numeric
		UIChrome.TextOutline(label)
	end
	for _, entry in self._live do
		entry.label.FontFace = theme.Fonts.Numeric
		local spec = KINDS[entry.kind] or KINDS.damage
		entry.label.TextColor3 = self:_KindColor(spec.colorToken)
	end
end

return DamageNumbersWidget
