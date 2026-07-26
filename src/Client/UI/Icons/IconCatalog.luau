--!strict
-- GENERATED FILE - do not hand-edit. Regenerate with scratchpad/gen-catalog.js.
--
-- The icon archive DATA: the Gvesster pack indexed by semantic key, with
-- every colourway/outline/size variant and the uploaded Roblox asset id for
-- each variant pushed so far. The raw tables live in IconCatalogData1/2
-- (Studio caps a script Source at 200k chars); this module is the API over
-- both — consumers never know about the split.
--
-- Art: Gvesster Icon Pack v6 (@gvesster). Licensed for use in this project;
-- do not resell or redistribute the source PNGs.

export type Variant = {
	colorway: string,
	outline: boolean,
	size: number, -- source pixel width (64 or 256)
	assetId: string?, -- nil until uploaded
	path: string, -- source file, relative to the pack root
}

export type Icon = {
	key: string,
	name: string,
	category: string,
	variants: { Variant },
}

local IconCatalog = {}

local icons: { Icon } = require(script.Parent.IconCatalogData1) :: { Icon }
for _, icon in require(script.Parent.IconCatalogData2) :: { Icon } do
	table.insert(icons, icon)
end

IconCatalog.Icons = icons

local byKey: { [string]: Icon } = {}
for _, icon in IconCatalog.Icons do
	byKey[icon.key] = icon
end

function IconCatalog.Get(key: string): Icon?
	return byKey[key]
end

function IconCatalog.Keys(): { string }
	local out = {}
	for _, icon in IconCatalog.Icons do
		table.insert(out, icon.key)
	end
	table.sort(out)
	return out
end

function IconCatalog.ByCategory(category: string): { Icon }
	local out = {}
	for _, icon in IconCatalog.Icons do
		if icon.category == category then
			table.insert(out, icon)
		end
	end
	return out
end

function IconCatalog.Categories(): { string }
	local seen, out = {}, {}
	for _, icon in IconCatalog.Icons do
		if not seen[icon.category] then
			seen[icon.category] = true
			table.insert(out, icon.category)
		end
	end
	table.sort(out)
	return out
end

return IconCatalog
