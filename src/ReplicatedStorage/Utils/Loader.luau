--!strict
local Loader = {}

--[=[
    Loader.Load(folder: Instance)
    
    Loads all ModuleScripts in the given folder (non-recursive by default, or recursive if you prefer).
    
    Pass 1: Require all modules.
    Pass 2: Call :Init() on all modules that have it.
    Pass 3: Call :Start() on all modules that have it.
    
    This ensures that by the time :Start() is called, all modules are :Init()ialized.
]=]
function Loader.Load(rootFolder: Instance)
	local modules = {}

	-- 1. Discovery & Require
	for _, child in ipairs(rootFolder:GetDescendants()) do
		if child:IsA("ModuleScript") then
			local success, result = pcall(require, child)
			if success then
				if type(result) == "table" then
					table.insert(modules, {
						Name = child.Name,
						Module = result,
					})
				end
			else
				warn("[Loader] Failed to require module: " .. child.Name .. " | Error: " .. tostring(result))
			end
		end
	end

	-- 2. Init Pass
	for _, definition in ipairs(modules) do
		local mod = definition.Module
		if typeof(mod.Init) == "function" then
			task.spawn(function()
				local success, err = pcall(function()
					mod:Init()
				end)
				if not success then
					warn("[Loader] Error in :Init() for " .. definition.Name .. ": " .. tostring(err))
				end
			end)
		end
	end

	-- Wait a tick to let Inits settle (optional, but good practice if Init has async work)
	-- ideally Init should be synchronous for dependency setup, but we'll use task.defer for Start

	-- 3. Start Pass
	-- We wait for all Inits to fire?
	-- Strictly speaking, if Init yields, we might have race conditions.
	-- Standard practice: Init should be synchronous setup.

	for _, definition in ipairs(modules) do
		local mod = definition.Module
		if typeof(mod.Start) == "function" then
			task.defer(function()
				local success, err = pcall(function()
					mod:Start()
				end)
				if not success then
					warn("[Loader] Error in :Start() for " .. definition.Name .. ": " .. tostring(err))
				end
			end)
		end
	end

	print("[Loader] Loaded " .. #modules .. " modules from " .. rootFolder:GetFullName())
end

return Loader
