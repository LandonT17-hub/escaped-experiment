-- Finds one world's hand-built parts by name (workspace.World<N>) and packages
-- them as the WorldParts that WorldWiring attaches gameplay to. Missing or
-- mistyped parts warn via MapLookup and are left out; whatever did resolve
-- still gets wired.

local Players = game:GetService("Players")

local MapLookup = require(script.Parent.MapLookup)
local StageObjective = require(script.Parent.StageObjective)
local WorldsData = require(script.Parent.WorldsData)

local find = MapLookup.Find

-- How far in from the floor's entrance edge a respawning player lands.
local START_INSET = 6

export type WorldParts = {
	Stages: { [number]: StageObjective.StageParts }, -- by stage index; holes where a stage failed to resolve
	Boss: StageObjective.StageParts?,
	Pedestals: Instance?, -- contains "Pedestal1".."PedestalN"
	Leaderboards: Instance?,
	TrainingPlots: Instance?, -- contains "Plot1".."Plot8"
}

local MapResolver = {}

-- Respawn point on the floor edge nearest the lobby spawn (the side players
-- walk in from), inset a few studs and facing into the stage.
local function startCFrameFor(floor: BasePart, lobbyPosition: Vector3): CFrame
	local half = floor.Size / 2
	local edges = {
		floor.CFrame * Vector3.new(0, 0, half.Z),
		floor.CFrame * Vector3.new(0, 0, -half.Z),
		floor.CFrame * Vector3.new(half.X, 0, 0),
		floor.CFrame * Vector3.new(-half.X, 0, 0),
	}

	local flat = Vector3.new(1, 0, 1)
	local nearest, nearestDistance = edges[1], math.huge
	for _, edge in edges do
		local distance = ((edge - lobbyPosition) * flat).Magnitude
		if distance < nearestDistance then
			nearest, nearestDistance = edge, distance
		end
	end

	local center = floor.Position
	local inward = ((center - nearest) * flat).Unit
	local topY = center.Y + half.Y + 3
	local position = Vector3.new(nearest.X, topY, nearest.Z) + inward * START_INSET
	return CFrame.lookAt(position, Vector3.new(center.X, topY, center.Z))
end

local function rewardPad(part: BasePart?): StageObjective.RewardPad?
	if not part then
		return nil
	end

	local wins = MapLookup.Attr(part, "Wins", "number")
	if not wins then
		return nil
	end

	return {
		Part = part,
		Wins = wins,
		RequiresPremium = part:GetAttribute("RequiresPremium") == true,
		RespawnToLobby = part:GetAttribute("RespawnToLobby") == true,
	}
end

local function resolveStage(
	model: Instance,
	enemyCount: number,
	lobbyPosition: Vector3
): StageObjective.StageParts?
	local zone = find(model, "Zone", "BasePart")
	if not zone then
		return nil -- nothing to drive activation; skip the whole stage
	end

	local spawns = {}
	local spawnsFolder = find(model, "EnemySpawns")
	for i = 1, enemyCount do
		local marker = find(spawnsFolder, "EnemySpawn" .. i, "BasePart")
		if marker then
			table.insert(spawns, marker)
		end
	end

	local pads = {}
	table.insert(pads, rewardPad(find(model, "WinPad", "BasePart")))
	table.insert(pads, rewardPad(find(find(model, "EndZone"), "PremiumWinPad", "BasePart")))

	local floor = find(model, "Floor", "BasePart")

	return {
		Model = model,
		Zone = zone,
		Gate = find(model, "Gate", "BasePart"),
		EnemySpawns = spawns,
		RewardPads = pads,
		StartCFrame = floor and startCFrameFor(floor, lobbyPosition),
		Floor = floor,
	}
end

local function resolveBoss(arena: Instance, lobbyPosition: Vector3): StageObjective.StageParts?
	local zone = find(arena, "Zone", "BasePart")
	if not zone then
		return nil
	end

	local bossSpawn = find(arena, "BossSpawn", "BasePart")
	local floor = find(arena, "Floor", "BasePart")

	return {
		Model = arena,
		Zone = zone,
		Gate = nil,
		EnemySpawns = if bossSpawn then { bossSpawn } else {},
		RewardPads = { rewardPad(find(arena, "ClaimPad", "BasePart")) },
		StartCFrame = floor and startCFrameFor(floor, lobbyPosition),
		Floor = floor,
	}
end

-- Enemies only work when spawned by code (StageObjective -> DummyEnemy),
-- which gives them AI, registers them as Bite targets and starts their
-- attacks. A Humanoid model saved into the place file -- e.g. copied out of a
-- Play session -- has none of that: it stands still, can't be hit and deals
-- no damage. Call once at startup, before any enemies spawn.
function MapResolver.WarnStrayEnemies()
	local seen: { [Instance]: boolean } = {}
	for _, descendant in workspace:GetDescendants() do
		if not descendant:IsA("Humanoid") then
			continue
		end
		local model = descendant.Parent
		-- Training plot dummies are meant to be static (TrainingPlots wires them).
		if not model or seen[model] or Players:GetPlayerFromCharacter(model) or model:FindFirstAncestor("TrainingPlots") then
			continue
		end
		seen[model] = true
		warn(
			`[Map] {model:GetFullName()} is an enemy/Humanoid saved in the place file -- it has no AI, `
				.. "can't be Bitten and deals no damage. Delete it; stage enemies are spawned by code at the EnemySpawn markers."
		)
	end
end

function MapResolver.Resolve(worldFolder: Instance, config: WorldsData.WorldConfig): WorldParts
	local lobby = find(worldFolder, "Lobby")

	local lobbySpawn = find(lobby, "LobbySpawn", "SpawnLocation")
	local lobbyPosition = if lobbySpawn then lobbySpawn.Position else config.LobbyOrigin

	local stages = {}
	local stagesFolder = find(worldFolder, "Stages")
	for i, stageConfig in config.Stages do
		local model = find(stagesFolder, "Stage" .. i)
		if not model then
			continue
		end

		local stageIndex = model:GetAttribute("StageIndex")
		if stageIndex ~= i then
			warn(`[Map] {model:GetFullName()} has StageIndex {stageIndex}, expected {i}`)
		end

		stages[i] = resolveStage(model, stageConfig.EnemyCount, lobbyPosition)
	end

	local arena = find(worldFolder, "BossArena")

	return {
		Stages = stages,
		Boss = arena and resolveBoss(arena, lobbyPosition),
		Pedestals = find(lobby, "Pedestals"),
		Leaderboards = find(lobby, "Leaderboards"),
		TrainingPlots = find(lobby, "TrainingPlots"),
	}
end

return MapResolver
