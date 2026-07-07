--!nonstrict
-- Generic Roblox API surface for local Luau CLI tools (game-agnostic).
--
-- Runtime game code should use the real Roblox globals; builder modules only
-- require a shim when those globals are absent (the `if game then nil else
-- require(...)` pattern). This core provides the engine-level stubs (Vector3,
-- CFrame, Color3, Enum, Instance, ...) with NO knowledge of any particular
-- game. A per-game adapter requires this, declares its own ReplicatedStorage
-- module tree + any character rig, and calls `Core.Compose{...}` to produce the
-- table its builders consume. See modelsnap/README.md.
--
-- This is a PARTIAL emulation: only the APIs builders actually touch are
-- stubbed. When a builder hits an un-stubbed API it fails loudly with
-- `attempt to call/index nil` — add the stub here and every game benefits.

local Core = {}

-- Real RGB->HSV so builders that recolor via Color3:ToHSV() (e.g. the foliage
-- `vary()` helper) preview in true color instead of collapsing to gray.
local function rgbToHsv(r: number, g: number, b: number)
	local maxC = math.max(r, g, b)
	local minC = math.min(r, g, b)
	local delta = maxC - minC
	local h = 0
	if delta > 0 then
		if maxC == r then
			h = ((g - b) / delta) % 6
		elseif maxC == g then
			h = (b - r) / delta + 2
		else
			h = (r - g) / delta + 4
		end
		h /= 6
	end
	local s = if maxC > 0 then delta / maxC else 0
	return h, s, maxC
end

local function hsvToRgb(h: number, s: number, v: number)
	if s <= 0 then
		return v, v, v
	end
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p = v * (1 - s)
	local q = v * (1 - s * f)
	local t = v * (1 - s * (1 - f))
	local seg = i % 6
	if seg == 0 then
		return v, t, p
	elseif seg == 1 then
		return q, v, p
	elseif seg == 2 then
		return p, v, t
	elseif seg == 3 then
		return p, q, v
	elseif seg == 4 then
		return t, p, v
	else
		return v, p, q
	end
end

local function color(r: number, g: number, b: number)
	return {
		R = r,
		G = g,
		B = b,
		ToHSV = function()
			return rgbToHsv(r, g, b)
		end,
	}
end

Core.Color3 = {
	new = color,
	fromRGB = function(r: number, g: number, b: number)
		return color(r / 255, g / 255, b / 255)
	end,
	fromHSV = function(h: number, s: number, v: number)
		return color(hsvToRgb(h, s, v))
	end,
}

local vector3Meta = {}
vector3Meta.__index = function(t, key)
	if key == "Magnitude" then
		return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
	elseif key == "Unit" then
		local mag = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
		if mag <= 0 then
			return setmetatable({ X = 0, Y = 0, Z = 0 }, vector3Meta)
		end
		return setmetatable({ X = t.X / mag, Y = t.Y / mag, Z = t.Z / mag }, vector3Meta)
	elseif key == "Lerp" then
		return function(self, other, alpha)
			return setmetatable({
				X = self.X + (other.X - self.X) * alpha,
				Y = self.Y + (other.Y - self.Y) * alpha,
				Z = self.Z + (other.Z - self.Z) * alpha,
			}, vector3Meta)
		end
	elseif key == "Dot" then
		return function(self, other)
			return self.X * other.X + self.Y * other.Y + self.Z * other.Z
		end
	end
	return nil
end
vector3Meta.__add = function(a, b)
	return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }, vector3Meta)
end
vector3Meta.__sub = function(a, b)
	return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, vector3Meta)
end
vector3Meta.__mul = function(a, b)
	if type(a) == "number" then
		return setmetatable({ X = b.X * a, Y = b.Y * a, Z = b.Z * a }, vector3Meta)
	end
	return setmetatable({ X = a.X * b, Y = a.Y * b, Z = a.Z * b }, vector3Meta)
end
vector3Meta.__div = function(a, b)
	return setmetatable({ X = a.X / b, Y = a.Y / b, Z = a.Z / b }, vector3Meta)
end

Core.Vector2 = {
	new = function(x: number, y: number)
		return { X = x, Y = y }
	end,
	zero = { X = 0, Y = 0 },
}

Core.Vector3 = {
	new = function(x: number, y: number, z: number)
		return setmetatable({ X = x, Y = y, Z = z }, vector3Meta)
	end,
	zero = setmetatable({ X = 0, Y = 0, Z = 0 }, vector3Meta),
}
Core.Vector3.xAxis = Core.Vector3.new(1, 0, 0)
Core.Vector3.yAxis = Core.Vector3.new(0, 1, 0)
Core.Vector3.zAxis = Core.Vector3.new(0, 0, 1)

local function vec3Cross(a, b)
	return Core.Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end

local function identityRotation()
	return {
		{ 1, 0, 0 },
		{ 0, 1, 0 },
		{ 0, 0, 1 },
	}
end

local function matMul(a, b)
	local r = {}
	for row = 1, 3 do
		r[row] = {}
		for col = 1, 3 do
			r[row][col] = a[row][1] * b[1][col] + a[row][2] * b[2][col] + a[row][3] * b[3][col]
		end
	end
	return r
end

local function matTranspose(a)
	return {
		{ a[1][1], a[2][1], a[3][1] },
		{ a[1][2], a[2][2], a[3][2] },
		{ a[1][3], a[2][3], a[3][3] },
	}
end

local function matVec(m, v)
	return Core.Vector3.new(
		m[1][1] * v.X + m[1][2] * v.Y + m[1][3] * v.Z,
		m[2][1] * v.X + m[2][2] * v.Y + m[2][3] * v.Z,
		m[3][1] * v.X + m[3][2] * v.Y + m[3][3] * v.Z
	)
end

local cframeFrom
local cframeMeta = {}
cframeMeta.__index = function(t, key)
	if key == "X" then
		return t.Position.X
	elseif key == "Y" then
		return t.Position.Y
	elseif key == "Z" then
		return t.Position.Z
	elseif key == "Inverse" then
		return function(self)
			local invRot = matTranspose(self.Rotation)
			return cframeFrom(
				matVec(invRot, Core.Vector3.new(-self.Position.X, -self.Position.Y, -self.Position.Z)),
				invRot
			)
		end
	elseif key == "ToObjectSpace" then
		return function(self, cf)
			return self:Inverse() * cf
		end
	elseif key == "ToWorldSpace" then
		return function(self, cf)
			return self * cf
		end
	elseif key == "PointToObjectSpace" then
		return function(self, point)
			return self:Inverse() * point
		end
	elseif key == "PointToWorldSpace" then
		return function(self, point)
			return self * point
		end
	elseif key == "VectorToObjectSpace" then
		return function(self, vector)
			return matVec(matTranspose(self.Rotation), vector)
		end
	elseif key == "VectorToWorldSpace" then
		return function(self, vector)
			return matVec(self.Rotation, vector)
		end
	elseif key == "Lerp" then
		-- Position lerps linearly; rotation just holds at `self` (good enough for the
		-- top-down footprints these tools emit — no slerp needed).
		return function(self, other, alpha)
			return setmetatable({
				Position = self.Position + (other.Position - self.Position) * alpha,
				Rotation = self.Rotation,
			}, cframeMeta)
		end
	end
	return nil
end
cframeMeta.__mul = function(a, b)
	if getmetatable(b) == vector3Meta then
		return a.Position + matVec(a.Rotation, b)
	end
	if type(b) == "table" and b.Position and b.Rotation then
		return setmetatable({
			Position = a.Position + matVec(a.Rotation, b.Position),
			Rotation = matMul(a.Rotation, b.Rotation),
		}, cframeMeta)
	end
	return setmetatable({ Position = a.Position, Rotation = a.Rotation }, cframeMeta)
end
cframeMeta.__add = function(a, b)
	return setmetatable({ Position = a.Position + b, Rotation = a.Rotation }, cframeMeta)
end
-- CFrame - Vector3 translates the frame, preserving rotation (matches Roblox).
-- Builders use `cf - cf.Position` to extract a rotation-only frame.
cframeMeta.__sub = function(a, b)
	return setmetatable({ Position = a.Position - b, Rotation = a.Rotation }, cframeMeta)
end

cframeFrom = function(pos, rot)
	return setmetatable({ Position = pos, Rotation = rot or identityRotation() }, cframeMeta)
end

Core.CFrame = {
	new = function(x: any?, y: number?, z: number?)
		if type(x) == "table" and x.X then
			return cframeFrom(x, identityRotation())
		end
		return cframeFrom(Core.Vector3.new(x or 0, y or 0, z or 0), identityRotation())
	end,
	Angles = function(rx: number, ry: number, rz: number)
		local cx, sx = math.cos(rx), math.sin(rx)
		local cy, sy = math.cos(ry), math.sin(ry)
		local cz, sz = math.cos(rz), math.sin(rz)
		local mx = { { 1, 0, 0 }, { 0, cx, -sx }, { 0, sx, cx } }
		local my = { { cy, 0, sy }, { 0, 1, 0 }, { -sy, 0, cy } }
		local mz = { { cz, -sz, 0 }, { sz, cz, 0 }, { 0, 0, 1 } }
		return cframeFrom(Core.Vector3.zero, matMul(matMul(mx, my), mz))
	end,
	-- Real lookAt: LookVector (-Z) points from eye toward target, matching Roblox.
	-- Needed so builders that orient via CFrame.lookAt render with correct rotation
	-- (the previous stub returned identity, leaving such parts unrotated).
	lookAt = function(eye, target, up)
		up = up or Core.Vector3.new(0, 1, 0)
		local zAxis = (eye - target).Unit
		local xAxis = vec3Cross(up, zAxis).Unit
		local yAxis = vec3Cross(zAxis, xAxis)
		local rot = {
			{ xAxis.X, yAxis.X, zAxis.X },
			{ xAxis.Y, yAxis.Y, zAxis.Y },
			{ xAxis.Z, yAxis.Z, zAxis.Z },
		}
		return cframeFrom(eye, rot)
	end,
}

local function enumFamily(prefix: string)
	return setmetatable({}, {
		__index = function(_, key)
			return `{prefix}.{key}`
		end,
	})
end

Core.Enum = setmetatable({}, {
	__index = function(_, key)
		return enumFamily(key)
	end,
})

local function isA(className: string, query: string): boolean
	if className == query then
		return true
	end
	if query == "BasePart" then
		return className == "Part" or className == "WedgePart" or className == "MeshPart"
	end
	return false
end

local instanceMethods = {}

function instanceMethods:IsA(query: string): boolean
	return isA(self.ClassName, query)
end

function instanceMethods:GetChildren()
	local result = {}
	for _, child in self._children do
		table.insert(result, child)
	end
	return result
end

function instanceMethods:GetDescendants()
	local result = {}
	local function walk(node)
		for _, child in node._children do
			table.insert(result, child)
			walk(child)
		end
	end
	walk(self)
	return result
end

-- Axis-aligned bounding box of a node's BaseParts (part centres; good enough for
-- pivot/centre math the builders need offline). Returns nil if it has no parts.
local function partAABB(node)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local any = false
	local function consider(p)
		if isA(p.ClassName, "BasePart") then
			any = true
			local pos = p.CFrame.Position
			minX, maxX = math.min(minX, pos.X), math.max(maxX, pos.X)
			minY, maxY = math.min(minY, pos.Y), math.max(maxY, pos.Y)
			minZ, maxZ = math.min(minZ, pos.Z), math.max(maxZ, pos.Z)
		end
	end
	consider(node)
	for _, d in node:GetDescendants() do
		consider(d)
	end
	if not any then
		return nil
	end
	return minX, minY, minZ, maxX, maxY, maxZ
end

-- Roblox parity: a BasePart pivot is CFrame * PivotOffset; a Model pivot is its
-- PrimaryPart's pivot, else the centre of its bounding box.
function instanceMethods:GetPivot()
	if isA(self.ClassName, "BasePart") then
		local offset = rawget(self, "PivotOffset")
		return if offset then self.CFrame * offset else self.CFrame
	end
	local primary = rawget(self, "PrimaryPart")
	if primary then
		return primary:GetPivot()
	end
	local minX, minY, minZ, maxX, maxY, maxZ = partAABB(self)
	if not minX then
		return Core.CFrame.new()
	end
	return Core.CFrame.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
end

-- Move so the node's pivot lands on `target`, carrying every descendant part.
function instanceMethods:PivotTo(target)
	local delta = target * self:GetPivot():Inverse()
	if isA(self.ClassName, "BasePart") then
		self.CFrame = delta * self.CFrame
		return
	end
	if rawget(self, "CFrame") then
		self.CFrame = delta * self.CFrame
	end
	for _, d in self:GetDescendants() do
		if isA(d.ClassName, "BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
end

function instanceMethods:GetBoundingBox()
	local minX, minY, minZ, maxX, maxY, maxZ = partAABB(self)
	if not minX then
		return Core.CFrame.new(), Core.Vector3.new(0, 0, 0)
	end
	local center = Core.CFrame.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
	return center, Core.Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
end

function instanceMethods:FindFirstChild(name: string)
	for _, child in self._children do
		if child.Name == name then
			return child
		end
	end
	return nil
end

function instanceMethods:FindFirstChildOfClass(className: string)
	for _, child in self._children do
		if child:IsA(className) then
			return child
		end
	end
	return nil
end

function instanceMethods:WaitForChild(name: string)
	return self:FindFirstChild(name) or rawget(self, name)
end

function instanceMethods:SetAttribute(name: string, value: any)
	self._attributes[name] = value
end

function instanceMethods:GetAttribute(name: string): any
	return self._attributes[name]
end

function instanceMethods:SetStateEnabled(_state: any, _enabled: boolean) end

-- Playback/animation no-ops: builders that wire up Sound/Tween/ParticleEmitter at
-- build time call these immediately; offline they just need to not error.
function instanceMethods:Play() end
function instanceMethods:Pause() end
function instanceMethods:Stop() end
function instanceMethods:Resume() end
function instanceMethods:Emit(_count: number?) end

-- Pivot/scale: builders place prefab models with model:PivotTo(model:GetPivot())
-- and size them with model:ScaleTo(...). Implemented faithfully (real CFrame math)
-- so the world-map part exporter gets correct footprints from baked-in transforms.
local function instancePivot(self)
	if self:IsA("BasePart") then
		local off = rawget(self, "PivotOffset")
		local cf = rawget(self, "CFrame") or cframeFrom(Core.Vector3.zero)
		return if off then cf * off else cf
	end
	local primary = rawget(self, "PrimaryPart")
	if primary then
		local off = rawget(primary, "PivotOffset")
		local cf = rawget(primary, "CFrame") or cframeFrom(Core.Vector3.zero)
		return if off then cf * off else cf
	end
	-- No PrimaryPart: pivot at the AABB centre of the descendant parts.
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local any = false
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then
			any = true
			local p = rawget(d, "CFrame").Position
			minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
			minY, maxY = math.min(minY, p.Y), math.max(maxY, p.Y)
			minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
		end
	end
	if not any then
		return cframeFrom(Core.Vector3.zero)
	end
	return cframeFrom(Core.Vector3.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2))
end

function instanceMethods:GetPivot()
	return instancePivot(self)
end

function instanceMethods:PivotTo(target)
	if self:IsA("BasePart") then
		local off = rawget(self, "PivotOffset")
		rawset(self, "CFrame", if off then target * off:Inverse() else target)
		return
	end
	local delta = target * instancePivot(self):Inverse()
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then
			rawset(d, "CFrame", delta * rawget(d, "CFrame"))
		end
	end
end

function instanceMethods:GetScale()
	return rawget(self, "_scale") or 1
end

function instanceMethods:ScaleTo(scale: number)
	local cur = rawget(self, "_scale") or 1
	if cur <= 0 then
		cur = 1
	end
	local factor = scale / cur
	rawset(self, "_scale", scale)
	if factor == 1 then
		return
	end
	local pivot = instancePivot(self)
	local invPivot = pivot:Inverse()
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then
			d.Size = d.Size * factor
			local rel = invPivot * rawget(d, "CFrame")
			rel = setmetatable({ Position = rel.Position * factor, Rotation = rel.Rotation }, cframeMeta)
			rawset(d, "CFrame", pivot * rel)
		end
	end
end

function instanceMethods:Destroy()
	self.Parent = nil
	for _, child in self:GetChildren() do
		child:Destroy()
	end
end

local instanceMeta = {}
instanceMeta.__index = function(t, key)
	-- BasePart.Position mirrors CFrame.Position (core only stores CFrame).
	if key == "Position" and rawget(t, "CFrame") then
		return rawget(t, "CFrame").Position
	end
	return instanceMethods[key] or rawget(t, key)
end
instanceMeta.__newindex = function(t, key, value)
	if key == "Position" and rawget(t, "CFrame") then
		-- Setting Position translates the part, keeping its current rotation.
		local cf = rawget(t, "CFrame")
		rawset(t, "CFrame", setmetatable({ Position = value, Rotation = cf.Rotation }, getmetatable(cf)))
		return
	end
	if key == "Parent" then
		local old = rawget(t, "Parent")
		if old and old._children then
			for i = #old._children, 1, -1 do
				if old._children[i] == t then
					table.remove(old._children, i)
					break
				end
			end
		end
		rawset(t, "Parent", value)
		if value and value._children then
			table.insert(value._children, t)
		end
	else
		rawset(t, key, value)
	end
end

Core.UDim = {
	new = function(scale: number?, offset: number?)
		return { Scale = scale or 0, Offset = offset or 0 }
	end,
}

Core.UDim2 = {
	new = function(sx: number?, ox: number?, sy: number?, oy: number?)
		return { X = { Scale = sx or 0, Offset = ox or 0 }, Y = { Scale = sy or 0, Offset = oy or 0 } }
	end,
	fromScale = function(x: number, y: number)
		return { X = { Scale = x, Offset = 0 }, Y = { Scale = y, Offset = 0 } }
	end,
	fromOffset = function(x: number, y: number)
		return { X = { Scale = 0, Offset = x }, Y = { Scale = 0, Offset = y } }
	end,
}

-- Cosmetic-only constructors (tweens never play, Rect is UI/texture data); the
-- builders just need `.new` to exist so a SurfaceGui/decal call doesn't abort.
Core.TweenInfo = {
	new = function(...)
		return { ... }
	end,
}
Core.Rect = {
	new = function(minX: any?, minY: number?, maxX: number?, maxY: number?)
		if type(minX) == "table" then
			return { Min = minX, Max = minY }
		end
		return {
			Min = { X = minX or 0, Y = minY or 0 },
			Max = { X = maxX or 0, Y = maxY or 0 },
		}
	end,
}

local function noopSignal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
end

local function bindEvents(inst)
	inst.ChildAdded = noopSignal()
	inst.MouseClick = noopSignal()
	-- Interaction events builders wire up at build time (ProximityPrompt.Triggered,
	-- pad.Touched, ClickDetector.Activated, ...). The callbacks never fire offline,
	-- but the :Connect call must not abort the build.
	inst.Triggered = noopSignal()
	inst.Touched = noopSignal()
	inst.TouchEnded = noopSignal()
	inst.Activated = noopSignal()
end

local function newInstance(className: string)
	local inst = setmetatable({
		ClassName = className,
		Name = className,
		_children = {},
		_attributes = {},
	}, instanceMeta)
	if isA(className, "BasePart") then
		inst.Size = Core.Vector3.new(1, 1, 1)
		inst.CFrame = Core.CFrame.new()
		inst.Color = Core.Color3.fromRGB(160, 160, 160)
		inst.Transparency = 0
		inst.Material = Core.Enum.Material.SmoothPlastic
		inst.Shape = Core.Enum.PartType.Block
	end
	bindEvents(inst)
	return inst
end

Core.Instance = {
	new = newInstance,
}
Core.newInstance = newInstance

-- Deep clone: copy own properties (skip the internal bookkeeping + Parent) and
-- recurse children, so builders that stamp a prefab with :Clone() work offline.
function instanceMethods:Clone()
	local copy = newInstance(self.ClassName)
	for key, value in pairs(self) do
		if key ~= "_children" and key ~= "_attributes" and key ~= "Parent" then
			rawset(copy, key, value)
		end
	end
	for name, value in pairs(self._attributes) do
		copy._attributes[name] = value
	end
	for _, child in self:GetChildren() do
		child:Clone().Parent = copy
	end
	-- Re-point PrimaryPart at the cloned child of the same name, not the original.
	local primary = rawget(self, "PrimaryPart")
	if primary then
		rawset(copy, "PrimaryPart", copy:FindFirstChild(primary.Name))
	end
	return copy
end

-- Terrain/workspace stub: builders that sculpt terrain (Terrain:FillCylinder, ...)
-- or raycast the ground need these to exist offline. Terrain voxel ops are no-ops
-- (the offline map reads the Heightmap, not voxels); any other workspace method
-- returns nil.
local terrainStub = setmetatable({ ClassName = "Terrain", Name = "Terrain" }, {
	__index = function(_, key)
		if key == "IsA" then
			return function(_, query: string)
				return query == "Terrain"
			end
		end
		return function() end -- FillCylinder/FillBlock/ReplaceMaterial/...
	end,
})
Core.workspace = setmetatable({ Terrain = terrainStub }, {
	__index = function(_, _key)
		return function()
			return nil
		end -- Raycast and friends
	end,
})

Core.NumberRange = {
	new = function(min: number?, max: number?)
		return { Min = min or 0, Max = max or min or 0 }
	end,
}
Core.NumberSequenceKeypoint = {
	new = function(time: number, value: number)
		return { Time = time, Value = value }
	end,
}
Core.NumberSequence = {
	new = function(value: any)
		return value
	end,
}
Core.ColorSequenceKeypoint = {
	new = function(time: number, value: any)
		return { Time = time, Value = value }
	end,
}
Core.ColorSequence = {
	new = function(a: any, b: any?)
		return { a, b }
	end,
}

Core.Random = {
	new = function(seed: number?)
		local state = (seed or 1) % 2147483646
		if state <= 0 then
			state += 2147483645
		end
		local function nextUnit(): number
			state = (state * 48271) % 2147483647
			return state / 2147483647
		end
		return {
			NextNumber = function(_, min: number?, max: number?)
				local unit = nextUnit()
				if min == nil and max == nil then
					return unit
				end
				if max == nil then
					return unit * (min :: number)
				end
				local lo = min :: number
				return lo + unit * ((max :: number) - lo)
			end,
			NextInteger = function(_, min: number, max: number)
				return math.floor(min + nextUnit() * (max - min + 1))
			end,
		}
	end,
}

-- Folder helper for declaring a fake ReplicatedStorage tree. Leaf values are
-- `@Alias/Path` strings that luau's require() resolves via .luaurc aliases.
local function folder(children)
	children.WaitForChild = function(self, name: string)
		return self[name]
	end
	return children
end
Core.folder = folder

-- Generic CollectionService (tag store is a no-op; HasTag is always false).
Core.CollectionService = {
	AddTag = function(_self, _instance, _tag) end,
	RemoveTag = function(_self, _instance, _tag) end,
	HasTag = function(_self, _instance, _tag)
		return false
	end,
}

Core.task = {
	spawn = function() end,
	wait = function() end,
}

-- Constructors copied into every Composed shim table.
local API_FIELDS = {
	"Color3",
	"Vector2",
	"Vector3",
	"CFrame",
	"Enum",
	"Instance",
	"UDim",
	"UDim2",
	"NumberRange",
	"NumberSequenceKeypoint",
	"NumberSequence",
	"ColorSequenceKeypoint",
	"ColorSequence",
	"TweenInfo",
	"Rect",
	"Random",
	"workspace",
	"folder",
	"newInstance",
}

-- Compose a full per-game shim table from this core plus game-specific pieces:
--   replicatedStorage : a `Core.folder{...}` tree (required)
--   players           : a table with the Players methods the game's builders use
--   services          : { [serviceName] = impl } for any extra GetService targets
-- The result exposes the same fields builder modules expect (CFrame, Color3,
-- Enum, Instance, Vector3, ..., game, task), so builders need no change.
function Core.Compose(opts)
	opts = opts or {}
	local shim = {}
	for _, key in API_FIELDS do
		shim[key] = Core[key]
	end
	shim.task = Core.task

	local services = opts.services or {}
	local replicatedStorage = opts.replicatedStorage
	local players = opts.players
		or {
			GetPlayers = function()
				return {}
			end,
			GetPlayerFromCharacter = function()
				return nil
			end,
		}

	shim.game = {
		GetService = function(_, name: string)
			if name == "ReplicatedStorage" then
				return replicatedStorage
			elseif name == "Players" then
				return players
			elseif name == "CollectionService" then
				return Core.CollectionService
			elseif services[name] then
				return services[name]
			end
			return {}
		end,
	}

	return shim
end

return Core
