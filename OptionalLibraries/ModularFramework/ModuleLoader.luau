--!strict
--[[
	ModuleLoader

	A two-pass loader for ModuleScripts. It requires every module under the
	provided root, runs Setup on each module that defines it, then runs Start.
]]

local config = {
	ATTEMPT_LIMIT = 3,
	RETRY_DELAY = 1,
	Debug = false,
}

type ModuleDefinition = {
	Name: string,
	Path: string,
	Module: any,
}

local function log(message: string, isWarning: boolean?)
	local formattedMessage = `[ModuleLoader] {message}`
	if isWarning then
		warn(formattedMessage)
	elseif config.Debug then
		print(formattedMessage)
	end
end

local function processLifecycleMethod(methodName: string, methodFunc: () -> any?, moduleName: string): (boolean, any?)
	local success, result
	for attempt = 1, config.ATTEMPT_LIMIT do
		success, result = pcall(methodFunc)
		if success then
			return true, result
		end

		log(
			`Module '{moduleName}' failed on lifecycle '{methodName}' (attempt {attempt}/{config.ATTEMPT_LIMIT}): {tostring(
				result
			)}`,
			true
		)

		if attempt < config.ATTEMPT_LIMIT then
			task.wait(config.RETRY_DELAY)
		end
	end

	return false, result
end

local function discover(moduleDirectory: Instance): { ModuleScript }
	local moduleScripts = {}
	for _, descendant in moduleDirectory:GetDescendants() do
		if descendant:IsA("ModuleScript") then
			table.insert(moduleScripts, descendant)
		end
	end

	table.sort(moduleScripts, function(left, right)
		return left:GetFullName() < right:GetFullName()
	end)

	return moduleScripts
end

local function requireModules(moduleDirectory: Instance): { ModuleDefinition }
	local modules: { ModuleDefinition } = {}
	for _, moduleScript in discover(moduleDirectory) do
		local success, module = pcall(require, moduleScript)
		if success and type(module) == "table" then
			table.insert(modules, {
				Name = moduleScript.Name,
				Path = moduleScript:GetFullName(),
				Module = module,
			})
		elseif not success then
			log(`Failed to require module '{moduleScript:GetFullName()}': {tostring(module)}`, true)
		end
	end

	return modules
end

local function runLifecyclePass(modules: { ModuleDefinition }, methodName: string)
	log(`Starting '{methodName}' lifecycle pass.`)

	for _, definition in modules do
		local method = definition.Module[methodName]
		if type(method) ~= "function" then
			continue
		end

		local wasSuccessful, result = processLifecycleMethod(methodName, function()
			return method(definition.Module)
		end, definition.Path)

		if not wasSuccessful then
			log(`Module '{definition.Path}' failed lifecycle '{methodName}': {tostring(result)}`, true)
		end

		task.wait()
	end

	log(`Finished '{methodName}' lifecycle pass.`)
end

return function(moduleDirectory: Instance)
	local modules = requireModules(moduleDirectory)
	runLifecyclePass(modules, "Setup")
	runLifecyclePass(modules, "Start")
	log(`Loaded {#modules} modules from {moduleDirectory:GetFullName()}.`)
	return modules
end
