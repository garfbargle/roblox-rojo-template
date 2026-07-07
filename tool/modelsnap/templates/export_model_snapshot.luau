--!nonstrict
-- selene: allow(unused_variable)
-- TEMPLATE — per-game exporter. Copy to tool/export_model_snapshot.luau and add
-- entries to TARGETS for your game's builders. Each target returns a Model (and
-- optionally a label); the snapshot JSON is printed to stdout for render_core.py.
--
-- Run (the `-a` tells the luau CLI the rest are script args):
--   luau tool/export_model_snapshot.luau -a --target HAT > /tmp/hat.json
--   python3 tool/modelsnap/render_core.py --snapshot /tmp/hat.json --out hat.png

local Roblox = require("@ReplicatedStorage/Shared/RobloxCliShim")
local Snapshot = require("@modelsnap/snapshot")

local game = Roblox.game
local RS = game:GetService("ReplicatedStorage")

-- Require a module through the shim's WaitForChild chain so its module tree
-- resolves the alias. (Direct `require("@ReplicatedStorage/...")` also works.)
local function _need(...)
	local node = RS
	for _, name in { ... } do
		node = node:WaitForChild(name)
	end
	return require(node)
end

-- ── Add your build targets here. Each is `name = function() return Model[, label] end`.
local TARGETS = {
	-- item = function()
	-- 	local ItemPreview = _need("Builders", "ItemPreview")
	-- 	local Items = _need("Data", "Items")
	-- 	return ItemPreview.Build(Items.Resolve("SomeItemId")), "Some Item"
	-- end,
	-- weapon = function()
	-- 	local WeaponBuilder = _need("Builders", "WeaponBuilder")
	-- 	return WeaponBuilder.Build("Sword"), "Sword"
	-- end,
}
-- ─────────────────────────────────────────────────────────────────────────────

local CLI_ARGS = { ... }
local function argsTable()
	local parsed = {}
	local index = 1
	while index <= #CLI_ARGS do
		local name = string.sub(CLI_ARGS[index], 3)
		local nextValue = CLI_ARGS[index + 1]
		if nextValue and string.sub(nextValue, 1, 2) ~= "--" then
			parsed[name] = nextValue
			index += 2
		else
			parsed[name] = true
			index += 1
		end
	end
	return parsed
end

local opts = argsTable()
if not opts.target or not TARGETS[opts.target] then
	local names = {}
	for k in TARGETS do
		table.insert(names, k)
	end
	print(`Usage: --target NAME  (known: {table.concat(names, ", ")})`)
	return
end

local model, label = TARGETS[opts.target]()
print(Snapshot.Encode(Snapshot.FromModel(model, label or opts.target, `target:{opts.target}`)))
