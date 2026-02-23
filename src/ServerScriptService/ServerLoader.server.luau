local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Loader = require(ReplicatedStorage.Utils.Loader)

-- Load all services
local servicesFolder = ServerScriptService:WaitForChild("Services")
Loader.Load(servicesFolder)

print("Server Bootstrapped via Loader")
