--!strict
-- ExampleModule.luau
--[[
    Demonstrates usage of the Logger utility in a basic module

    🧪 How to Use It

    1.  Place Logger.luau ReplicatedStorage/Utils/

    2.  Add ExampleModule.luau to either ServerScriptService/Services or
        StarterPlayerScripts/Controllers so it gets picked up by Loader (if using)

    3.  Run your game and observe the output — you’ll see debug and warning
        messages formatted with context
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage.Utils.Logger)

local logger = Logger.new({
	Debug = true,
	Prefix = "ExampleModule",
})

local ExampleModule = {}

function ExampleModule.Setup()
	logger.log("Running Setup phase")
	-- Simulate setup logic
end

function ExampleModule.Start()
	logger.log("Running Start phase")
	-- Simulate startup logic
	logger.log("Something went wrong during Start", true)
end

return ExampleModule
