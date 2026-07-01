--!nonstrict
-- TEMPLATE — per-game CLI shim adapter.
--
-- Copy this to the path your builder modules import, which is almost always:
--   src/ReplicatedStorage/Shared/RobloxCliShim.luau
-- Builders reach it via the gate:
--   local Roblox = if game then nil else require("@ReplicatedStorage/Shared/RobloxCliShim")
--
-- This file only declares the two things that are specific to YOUR game:
--   1. the fake ReplicatedStorage module tree (a mirror of your src/ folders), and
--   2. an OPTIONAL stand-in character rig (delete if you never render rigs).
-- All engine-level Roblox stubs live in @modelsnap/cli_shim_core.

local Core = require("@modelsnap/cli_shim_core")
local folder = Core.folder
local newInstance = Core.newInstance
local Vector3 = Core.Vector3
local CFrame = Core.CFrame
local Color3 = Core.Color3

-- BEGIN module tree
-- Replace this with the output of:
--   python3 tool/modelsnap/scaffold_module_tree.py
-- (a dir containing init.luau is emitted as a leaf; a plain dir as a folder).
local ReplicatedStorage = folder({
	Shared = folder({
		RobloxCliShim = "@ReplicatedStorage/Shared/RobloxCliShim",
		-- Foo = "@ReplicatedStorage/Shared/Foo",
	}),
	-- Builders = folder({ Bar = "@ReplicatedStorage/Builders/Bar" }),
	-- Data = folder({ Items = "@ReplicatedStorage/Data/Items" }),
})
-- END module tree

-- OPTIONAL character rig. Only needed if a builder calls
-- Players:CreateHumanoidModelFromDescription(desc). Delete `Players` (and pass
-- nothing for `players`) if you do not render character/NPC rigs.
local function part(name: string, size, cframe, color)
	local p = newInstance("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color or Color3.fromRGB(232, 196, 166)
	p.Anchored = false
	p.CanCollide = false
	return p
end

local Players = {
	GetPlayers = function()
		return {}
	end,
	GetPlayerFromCharacter = function(_self, _char)
		return nil
	end,
	CreateHumanoidModelFromDescription = function(_, desc)
		local model = newInstance("Model")
		model.Name = "HeroRig"
		local root = part("HumanoidRootPart", Vector3.new(2, 5.6, 1), CFrame.new(0, 0, 0), Color3.fromRGB(0, 0, 0))
		root.Transparency = 1
		root.Parent = model
		model.PrimaryPart = root
		part("UpperTorso", Vector3.new(1.8, 1.5, 0.8), CFrame.new(0, 0.8, 0), desc.TorsoColor).Parent = model
		part("Head", Vector3.new(1.1, 1.1, 1.1), CFrame.new(0, 2.05, 0), desc.HeadColor).Parent = model
		part("RightHand", Vector3.new(0.45, 0.45, 0.45), CFrame.new(-1.25, 0.15, -0.05), desc.RightArmColor).Parent = model
		part("LeftHand", Vector3.new(0.45, 0.45, 0.45), CFrame.new(1.25, 0.15, -0.05), desc.LeftArmColor).Parent = model
		newInstance("Humanoid").Parent = model
		return model
	end,
}

return Core.Compose({
	replicatedStorage = ReplicatedStorage,
	players = Players,
	-- services = { SomeService = { Method = function() end } }, -- add extra GetService targets if a builder needs them
})
