--!nonstrict
-- Generic Model -> snapshot-JSON serializer (game-agnostic).
--
-- Walks any Model built under the CLI shim and emits the parts-snapshot JSON
-- contract consumed by render_core.py (see modelsnap/README.md). Knows nothing
-- about any particular game's builders; a per-game exporter constructs a Model
-- and calls Snapshot.Encode(Snapshot.FromModel(model, label, source)).

local Core = require("@modelsnap/cli_shim_core")
local CFrame = Core.CFrame
local Color3 = Core.Color3
local Vector3 = Core.Vector3

local Snapshot = {}

local function jsonString(value: string): string
	local escaped = value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
	return `"{escaped}"`
end

local function isArray(value): boolean
	local count = 0
	for key in value do
		if type(key) ~= "number" then
			return false
		end
		count += 1
	end
	for index = 1, count do
		if value[index] == nil then
			return false
		end
	end
	return true
end

local function jsonEncode(value): string
	local kind = type(value)
	if kind == "nil" then
		return "null"
	elseif kind == "boolean" then
		return if value then "true" else "false"
	elseif kind == "number" then
		return tostring(value)
	elseif kind == "string" then
		return jsonString(value)
	elseif kind == "table" then
		local parts = {}
		if isArray(value) then
			for _, item in value do
				table.insert(parts, jsonEncode(item))
			end
			return `[{table.concat(parts, ",")}]`
		end
		for key, item in value do
			if type(item) ~= "function" then
				table.insert(parts, `{jsonString(tostring(key))}:{jsonEncode(item)}`)
			end
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

local function colorOut(c)
	return {
		r = math.floor((c.R or 0) * 255 + 0.5),
		g = math.floor((c.G or 0) * 255 + 0.5),
		b = math.floor((c.B or 0) * 255 + 0.5),
	}
end

local function vectorOut(v)
	return { x = v.X or 0, y = v.Y or 0, z = v.Z or 0 }
end

local function cframeOut(cf)
	return {
		position = vectorOut(cf.Position or Vector3.zero),
		rotation = cf.Rotation or {
			{ 1, 0, 0 },
			{ 0, 1, 0 },
			{ 0, 0, 1 },
		},
	}
end

local function partOut(part)
	local shape = tostring(part.Shape or "")
	if part.ClassName == "WedgePart" then
		shape = "Wedge"
	elseif shape == "" or shape == "nil" then
		shape = "Block"
	end
	return {
		name = part.Name,
		className = part.ClassName,
		shape = shape,
		material = tostring(part.Material or ""),
		size = vectorOut(part.Size or Vector3.new(1, 1, 1)),
		cframe = cframeOut(part.CFrame or CFrame.new()),
		color = colorOut(part.Color or Color3.fromRGB(160, 160, 160)),
		transparency = part.Transparency or 0,
	}
end

-- Build the snapshot table from a Model (or single BasePart). Parts at or above
-- 0.98 transparency are dropped (effectively invisible).
function Snapshot.FromModel(model, label: string, source: string)
	local parts = {}
	if model:IsA("BasePart") and (model.Transparency or 0) < 0.98 then
		table.insert(parts, partOut(model))
	end
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") and (desc.Transparency or 0) < 0.98 then
			table.insert(parts, partOut(desc))
		end
	end
	return {
		label = label,
		source = source,
		partCount = #parts,
		parts = parts,
	}
end

Snapshot.Encode = jsonEncode

return Snapshot
