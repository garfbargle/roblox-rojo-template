--!strict
local Loader = {}

type ModuleDefinition = {
	Name: string,
	Path: string,
	Module: any,
}

--[=[
    Loader.Load(folder: Instance)

    Loads all ModuleScripts under the given folder.

    Pass 1: Require all modules.
    Pass 2: Call :Init() on all modules that have it.
    Pass 3: Call :Start() on all modules that have it.

    This ensures that by the time :Start() is called, all modules are :Init()ialized.
]=]
function Loader.Load(rootFolder: Instance): { ModuleDefinition }
	local moduleScripts = {}
	for _, descendant in rootFolder:GetDescendants() do
		if descendant:IsA("ModuleScript") then
			table.insert(moduleScripts, descendant)
		end
	end

	table.sort(moduleScripts, function(left, right)
		return left:GetFullName() < right:GetFullName()
	end)

	local modules: { ModuleDefinition } = {}

	for _, moduleScript in moduleScripts do
		local success, result = pcall(require, moduleScript)
		if success then
			if type(result) == "table" then
				table.insert(modules, {
					Name = moduleScript.Name,
					Path = moduleScript:GetFullName(),
					Module = result,
				})
			end
		else
			warn(`[Loader] Failed to require {moduleScript:GetFullName()}: {tostring(result)}`)
		end
	end

	for _, definition in ipairs(modules) do
		local mod = definition.Module
		if type(mod.Init) == "function" then
			local success, err = pcall(function()
				mod:Init()
			end)
			if not success then
				warn(`[Loader] Error in :Init() for {definition.Path}: {tostring(err)}`)
			end
		end
	end

	for _, definition in ipairs(modules) do
		local mod = definition.Module
		if type(mod.Start) == "function" then
			task.defer(function()
				local success, err = pcall(function()
					mod:Start()
				end)
				if not success then
					warn(`[Loader] Error in :Start() for {definition.Path}: {tostring(err)}`)
				end
			end)
		end
	end

	print(`[Loader] Loaded {#modules} modules from {rootFolder:GetFullName()}`)
	return modules
end

return Loader
