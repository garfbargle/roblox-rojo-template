--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModuleLoader = require(ReplicatedStorage.Utils.ModuleLoader)
local localPlayer = Players.LocalPlayer
local controllersFolder = localPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers")

ModuleLoader(controllersFolder)
