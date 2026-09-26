-- The master per-world config table (master build Phase 3): all 4 worlds --
-- Cryo, Bio-Dome, Thermal, Flood -- defined here as data. WorldWiring reads
-- this to attach every world's gameplay systems to its hand-built map parts.
--
-- No design doc with real balance numbers exists in this repo (same caveat
-- as the old FormData.luau/StageData.luau placeholders they replace). Stage
-- and Form ladders are generated from one shared escalation curve (the exact
-- shape World1 originally used, worldScale = 1) so retuning one knob per
-- world keeps every world internally consistent instead of 4 hand-typed
-- tables drifting out of sync.

local ServerScriptService = game:GetService("ServerScriptService")

local StageObjective = require(script.Parent.StageObjective)
local FormData = require(ServerScriptService.Server.Evolution.FormData)

export type WorldConfig = {
	Id: number,
	Name: string,
	LobbyOrigin: Vector3,
	ThemeColor: Color3,
	Forms: { FormData.FormDefinition },
	Stages: { StageObjective.StageConfig },
}

local WorldsData = {}

-- Shared per-stage escalation shape (World1's original placeholder numbers,
-- reproduced exactly at worldScale = 1). RecommendedDamage is base 10 *
-- DamageMult, matching CombatService's BASE_DAMAGE constant.
local STAGE_CURVE = {
	{ HealthMult = 1.00, MutationMult = 1.00, WinsReward = 1, DamageMult = 1.00 },
	{ HealthMult = 1.80, MutationMult = 1.60, WinsReward = 2, DamageMult = 1.50 },
	{ HealthMult = 2.80, MutationMult = 2.40, WinsReward = 3, DamageMult = 2.20 },
	{ HealthMult = 4.00, MutationMult = 3.40, WinsReward = 4, DamageMult = 3.20 },
	{ HealthMult = 5.50, MutationMult = 4.80, WinsReward = 6, DamageMult = 4.50 },
}

local STAGE_BASE_HEALTH = 100
local STAGE_BASE_MUTATION = 25
local STAGE_BASE_DAMAGE = 10

local function generateStages(worldScale: number): { StageObjective.StageConfig }
	local stages = {}
	for i, curve in STAGE_CURVE do
		table.insert(stages, {
			Name = string.format("Stage %d", i),
			EnemyCount = 3,
			EnemyHealth = math.floor(STAGE_BASE_HEALTH * curve.HealthMult * worldScale),
			EnemyScale = 1.8 + (i - 1) * 0.1,
			MutationPerKill = math.floor(STAGE_BASE_MUTATION * curve.MutationMult * worldScale),
			WinsReward = curve.WinsReward,
			RecommendedDamage = math.floor(STAGE_BASE_DAMAGE * curve.DamageMult * worldScale),
		})
	end
	return stages
end

-- Shared per-form escalation shape (World1's original FormData.World1Forms
-- ladder, reproduced exactly at worldScale = 1). Names are per-world flavor
-- text only -- no custom art, just strings.
local FORM_CURVE = {
	{ WinsCostMult = 0, DamageMult = 1.00 },
	{ WinsCostMult = 5, DamageMult = 1.50 },
	{ WinsCostMult = 15, DamageMult = 2.25 },
	{ WinsCostMult = 40, DamageMult = 3.50 },
	{ WinsCostMult = 100, DamageMult = 5.50 },
	{ WinsCostMult = 250, DamageMult = 9.00 },
}

local function generateForms(names: { string }, worldScale: number): { FormData.FormDefinition }
	local forms = {}
	for i, curve in FORM_CURVE do
		table.insert(forms, {
			Name = names[i],
			WinsCost = math.floor(curve.WinsCostMult * worldScale),
			DamageMultiplier = curve.DamageMult * worldScale,
		})
	end
	return forms
end

-- Worlds are placed far apart along +X so they never overlap.
local WORLD_X_SPACING = 2000

-- Per-world theme colors.
local CRYO_COLOR = Color3.fromRGB(90, 180, 230)
local BIO_DOME_COLOR = Color3.fromRGB(90, 200, 110)
local THERMAL_COLOR = Color3.fromRGB(230, 120, 60)
local FLOOD_COLOR = Color3.fromRGB(50, 130, 180)

-- Invariant callers rely on (EvolutionService, WorldWiring): Worlds[i].Id == i,
-- i.e. this array is in ascending Id order with no gaps, so a worldId can be
-- used directly as an index into it.
local Worlds: { WorldConfig } = {
	{
		Id = 1,
		Name = "Cryo",
		LobbyOrigin = Vector3.new(0, 0, -300),
		ThemeColor = CRYO_COLOR,
		Forms = generateForms(
			{ "Subject", "Frostbitten", "Rimed", "Glacial", "Cryo-Aberrant", "Absolute Zero" },
			1
		),
		Stages = generateStages(1),
	},
	{
		Id = 2,
		Name = "Bio-Dome",
		LobbyOrigin = Vector3.new(WORLD_X_SPACING, 0, -300),
		ThemeColor = BIO_DOME_COLOR,
		Forms = generateForms(
			{ "Subject", "Spore-Touched", "Chlorotic", "Photosynthetic", "Verdant Horror", "Bloom Apex" },
			2.5
		),
		Stages = generateStages(2.5),
	},
	{
		Id = 3,
		Name = "Thermal",
		LobbyOrigin = Vector3.new(WORLD_X_SPACING * 2, 0, -300),
		ThemeColor = THERMAL_COLOR,
		Forms = generateForms(
			{ "Subject", "Scorched", "Magma-Veined", "Pyroclastic", "Ember Colossus", "Solar Flare" },
			6
		),
		Stages = generateStages(6),
	},
	{
		Id = 4,
		Name = "Flood",
		LobbyOrigin = Vector3.new(WORLD_X_SPACING * 3, 0, -300),
		ThemeColor = FLOOD_COLOR,
		Forms = generateForms(
			{ "Subject", "Waterlogged", "Brackish", "Abyssal", "Leviathan Spawn", "Tidal Sovereign" },
			14
		),
		Stages = generateStages(14),
	},
}

WorldsData.Worlds = Worlds

-- Shared so WorldWiring (gateway destinations) and PersistenceService
-- (repositioning a returning/respawning player) compute the identical point
-- instead of two copies of this formula silently drifting apart. A few studs
-- up so a teleported player lands cleanly above the floor.
function WorldsData.SpawnCFrameFor(config: WorldConfig): CFrame
	return CFrame.new(config.LobbyOrigin + Vector3.new(0, 3, -50))
end

return WorldsData
