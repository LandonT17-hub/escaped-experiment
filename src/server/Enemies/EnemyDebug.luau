-- TEMPORARY diagnostic logging for the stage-enemy bug. Every line is
-- prefixed [EnemyDebug]. Set ENABLED = false (or delete this module and its
-- call sites) once the bug is fixed.

local ENABLED = false

local EnemyDebug = {}

EnemyDebug.Enabled = ENABLED

function EnemyDebug.Log(message: string)
	if ENABLED then
		print("[EnemyDebug] " .. message)
	end
end

-- Readable id for an enemy model: "Stage3/DummyEnemy#7".
function EnemyDebug.Name(model: Instance): string
	local parent = model.Parent
	local id = model:GetAttribute("DebugId")
	return `{if parent then parent.Name else "?"}/{model.Name}#{id or "?"}`
end

function EnemyDebug.Vec(v: Vector3): string
	return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
end

-- "server", a player's name, or "error: ..." if ownership can't be read.
function EnemyDebug.Owner(part: BasePart): string
	local ok, owner = pcall(part.GetNetworkOwner, part)
	if not ok then
		return `error: {owner}`
	end
	return if owner then (owner :: Player).Name else "server"
end

return EnemyDebug
