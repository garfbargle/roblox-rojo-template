--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ModuleLoader = require(ReplicatedStorage.Utils.ModuleLoader)
local servicesFolder = ServerScriptService:WaitForChild("Services")

ModuleLoader(servicesFolder)
