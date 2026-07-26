--!strict
-- THE shared ambient ticker: one Heartbeat connection for every pulsing,
-- scrolling, scrambling, counting thing in the UI. Per-widget RunService
-- connections are a rejected pattern — a garage screen alone has 60+ live
-- readouts, and 60 connections is 59 too many.
--
--   local stop = UITicker.Register(function(dt, now) ... end)
--   stop() -- or let the bound instance's destruction clean it up
--
-- Handlers run inside pcall isolation (one broken readout can't stall the
-- rest) and the connection exists only while at least one handler does.

local RunService = game:GetService("RunService")

local UITicker = {}

export type Handler = (dt: number, now: number) -> ()

local handlers: { [{}]: Handler } = {}
local count = 0
local connection: RBXScriptConnection? = nil
local clock = 0

local function step(dt: number)
	clock += dt
	for _, handler in handlers do
		local ok, err = pcall(handler, dt, clock)
		if not ok then
			warn("[UITicker] handler error: " .. tostring(err))
		end
	end
end

-- Register a per-frame handler. Returns an unregister function (idempotent).
-- Pass `bindTo` to auto-unregister when that instance leaves the DataModel —
-- the usual pattern for widget effects.
function UITicker.Register(handler: Handler, bindTo: Instance?): () -> ()
	local key = {}
	handlers[key] = handler
	count += 1
	if not connection then
		connection = RunService.Heartbeat:Connect(step)
	end

	local ancestryConn: RBXScriptConnection? = nil
	local function stop()
		if handlers[key] then
			handlers[key] = nil
			count -= 1
			if count <= 0 and connection then
				connection:Disconnect()
				connection = nil
			end
		end
		if ancestryConn then
			ancestryConn:Disconnect()
			ancestryConn = nil
		end
	end

	if bindTo then
		ancestryConn = bindTo.AncestryChanged:Connect(function(_, parent)
			if not parent then
				stop()
			end
		end)
	end
	return stop
end

-- The shared clock (seconds since the first handler registered) — for phase
-- math without every widget keeping its own accumulator.
function UITicker.Now(): number
	return clock
end

return UITicker
