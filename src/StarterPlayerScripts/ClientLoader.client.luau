--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local playerScripts = localPlayer:WaitForChild("PlayerScripts")

local Loader = require(ReplicatedStorage.Utils.Loader)

-- Load all controllers
local controllersFolder = playerScripts:WaitForChild("Controllers")
Loader.Load(controllersFolder)

print("Client bootstrapped via Loader")
