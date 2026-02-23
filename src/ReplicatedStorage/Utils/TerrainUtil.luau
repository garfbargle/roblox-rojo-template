--!strict
local TerrainUtil = {}

function TerrainUtil.GetSeafloorHeight(x: number, z: number, radius: number): number
	local raycastParams = RaycastParams.new()
	local terrain = workspace:FindFirstChild("Terrain")
	if terrain then
		raycastParams.FilterType = Enum.RaycastFilterType.Include
		raycastParams.FilterDescendantsInstances = { terrain }
	else
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	end
	raycastParams.IgnoreWater = true

	local offsets = {
		Vector3.new(0, 0, 0), -- Center
		Vector3.new(radius, 0, radius), -- Corner 1
		Vector3.new(radius, 0, -radius), -- Corner 2
		Vector3.new(-radius, 0, radius), -- Corner 3
		Vector3.new(-radius, 0, -radius), -- Corner 4
	}

	local totalY = 0
	local hitCount = 0

	for _, offset in ipairs(offsets) do
		local rayOrigin = Vector3.new(x + offset.X, 500, z + offset.Z)
		local rayDirection = Vector3.new(0, -1000, 0)

		local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		if result then
			totalY += result.Position.Y
			hitCount += 1
		end
	end

	if hitCount > 0 then
		local avgY = totalY / hitCount
		return avgY
	end

	warn("TerrainUtil: No terrain found for height check at " .. x .. ", " .. z)
	return -100 -- Fallback depth
end

function TerrainUtil.CreateTunnel(p1: Vector3, p2: Vector3, radius: number)
	local dist = (p2 - p1).Magnitude
	if dist < 1 then
		return
	end

	local cframe = CFrame.lookAt(p1, p2) * CFrame.new(0, 0, -dist / 2)
	-- Rotate 90 deg X to align cylinder (Y-axis) with Path (Z-axis)
	local cylinderCF = cframe * CFrame.Angles(math.rad(90), 0, 0)

	-- 1. Clear with Air (Ensure empty space)
	workspace.Terrain:FillCylinder(cylinderCF, dist, radius, Enum.Material.Air)

	-- 2. Fill with Water
	workspace.Terrain:FillCylinder(cylinderCF, dist, radius, Enum.Material.Water)
end

return TerrainUtil
