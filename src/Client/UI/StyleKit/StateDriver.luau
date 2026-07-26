--!strict
-- Style/StateDriver — THE SOLE TAG MUTATOR. No other module may call
-- CollectionService:AddTag/RemoveTag with a style tag; grep for AddTag
-- outside this file and Tags-registered names to enforce the invariant.
--
-- Why one gate: when native styling activates, transitions fire on tag
-- flips — so tag flips ARE state changes ARE animations. One mutator means
-- state changes are auditable, debounced sanely, and reduce-motion or debug
-- instrumentation has a single choke point.
--
--   StateDriver.Structural(instance, Tags.Structural.Button)  -- build time
--   StateDriver.Set(instance, Tags.Modifier.Selected, true)   -- runtime
--   StateDriver.SetDialect(panelRoot, Tags.Dialect.Comic)     -- pack scoping

local CollectionService = game:GetService("CollectionService")

local Tags = require(script.Parent:WaitForChild("Tags"))

local StateDriver = {}

-- Optional audit hook (DevConfig can wire a logger); nil = silent.
local auditor: ((instance: Instance, tag: string, on: boolean) -> ())? = nil

function StateDriver.SetAuditor(fn: ((Instance, string, boolean) -> ())?)
	auditor = fn
end

-- Structural tags: applied once at build, never removed (a button does not
-- stop being a button; a destroyed instance drops its tags with it).
function StateDriver.Structural(instance: Instance, tag: string)
	assert(Tags.IsStructural(tag), ("StateDriver.Structural: %q is not a registered structural tag"):format(tag))
	CollectionService:AddTag(instance, tag)
end

-- Modifier tags: the runtime state surface. Idempotent.
function StateDriver.Set(instance: Instance, tag: string, on: boolean)
	assert(Tags.IsModifier(tag), ("StateDriver.Set: %q is not a registered modifier tag"):format(tag))
	local has = CollectionService:HasTag(instance, tag)
	if on == has then
		return
	end
	if on then
		CollectionService:AddTag(instance, tag)
	else
		CollectionService:RemoveTag(instance, tag)
	end
	if auditor then
		auditor(instance, tag, on)
	end
end

function StateDriver.Has(instance: Instance, tag: string): boolean
	return CollectionService:HasTag(instance, tag)
end

-- Dialect tags are exclusive per subtree root: setting one clears the others.
-- Pass nil to clear all dialects (single-dialect packs simply never call this
-- and pay nothing).
function StateDriver.SetDialect(root: Instance, dialectTag: string?)
	for _, tag in Tags.Dialect do
		if tag ~= dialectTag and CollectionService:HasTag(root, tag) then
			CollectionService:RemoveTag(root, tag)
		end
	end
	if dialectTag then
		assert(Tags.IsDialect(dialectTag), ("StateDriver.SetDialect: %q is not a registered dialect tag"):format(dialectTag))
		if not CollectionService:HasTag(root, dialectTag) then
			CollectionService:AddTag(root, dialectTag)
		end
	end
end

return StateDriver
