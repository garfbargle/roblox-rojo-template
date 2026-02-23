local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")

local Loader = require(ReplicatedStorage.Utils.Loader)

-- Load all controllers
local controllersFolder = StarterPlayerScripts:WaitForChild("Controllers")
Loader.Load(controllersFolder)

print("Client Bootstrapped via Loader")
