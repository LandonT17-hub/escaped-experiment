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
	Boss: StageObjective.StageConfig,
}

local WorldsData = {}

-- Per-stage escalation: each stage multiplies the previous one. Placeholder
-- numbers (no design doc exists); tune freely. RecommendedDamage is in the
-- same units as CombatService's BASE_DAMAGE (10). Wins payouts are not here --
-- they come from each reward pad's Wins attribute in the map.
local STAGE_BASE_HEALTH = 100
local STAGE_BASE_MUTATION = 25
local STAGE_BASE_DAMAGE = 10
local STAGE_HEALTH_GROWTH = 1.5
local STAGE_MUTATION_GROWTH = 1.4
local STAGE_DAMAGE_GROWTH = 1.45

local function generateStages(count: number, worldScale: number): { StageObjective.StageConfig }
	local stages = {}
	for i = 1, count do
		table.insert(stages, {
			Name = string.format("Stage %d", i),
			EnemyCount = 3,
			EnemyHealth = math.floor(STAGE_BASE_HEALTH * STAGE_HEALTH_GROWTH ^ (i - 1) * worldScale),
			EnemyScale = 1.8 + (i - 1) * 0.1,
			MutationPerKill = math.floor(STAGE_BASE_MUTATION * STAGE_MUTATION_GROWTH ^ (i - 1) * worldScale),
			RecommendedDamage = math.floor(STAGE_BASE_DAMAGE * STAGE_DAMAGE_GROWTH ^ (i - 1) * worldScale),
		})
	end
	return stages
end

-- The boss is one big enemy, a step up from the world's final stage.
local BOSS_HEALTH_MULT = 6
local BOSS_MUTATION_MULT = 10

local function generateBoss(stageCount: number, worldScale: number): StageObjective.StageConfig
	return {
		Name = "Boss",
		EnemyCount = 1,
		EnemyHealth = math.floor(
			STAGE_BASE_HEALTH * STAGE_HEALTH_GROWTH ^ (stageCount - 1) * BOSS_HEALTH_MULT * worldScale
		),
		EnemyScale = 3.5,
		MutationPerKill = math.floor(
			STAGE_BASE_MUTATION * STAGE_MUTATION_GROWTH ^ (stageCount - 1) * BOSS_MUTATION_MULT * worldScale
		),
		RecommendedDamage = math.floor(STAGE_BASE_DAMAGE * STAGE_DAMAGE_GROWTH ^ stageCount * worldScale),
	}
end

-- Per-form escalation (the first 6 are World1's original ladder at
-- worldScale = 1). Every world has 12 forms, one per name. Names and
-- WinsCosts are placeholders where a world's map has pedestals --
-- FormPedestals overwrites them from each pedestal's FormName/WinsCost
-- attributes; DamageMultiplier always comes from here.
local FORM_CURVE = {
	{ WinsCostMult = 0, DamageMult = 1.00 },
	{ WinsCostMult = 5, DamageMult = 1.50 },
	{ WinsCostMult = 15, DamageMult = 2.25 },
	{ WinsCostMult = 40, DamageMult = 3.50 },
	{ WinsCostMult = 100, DamageMult = 5.50 },
	{ WinsCostMult = 250, DamageMult = 9.00 },
	{ WinsCostMult = 500, DamageMult = 14.0 },
	{ WinsCostMult = 900, DamageMult = 22.0 },
	{ WinsCostMult = 1500, DamageMult = 35.0 },
	{ WinsCostMult = 2500, DamageMult = 55.0 },
	{ WinsCostMult = 4000, DamageMult = 85.0 },
	{ WinsCostMult = 6000, DamageMult = 130.0 },
}

local function generateForms(names: { string }, worldScale: number): { FormData.FormDefinition }
	local forms = {}
	for i, name in names do
		local curve = FORM_CURVE[i]
		table.insert(forms, {
			Name = name,
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
-- Form names/costs past the 6th are placeholders; a world's 12 pedestal
-- attributes (FormName/WinsCost) replace them once its map is wired.
local Worlds: { WorldConfig } = {
	{
		Id = 1,
		Name = "Cryo",
		LobbyOrigin = Vector3.new(0, 0, -300),
		ThemeColor = CRYO_COLOR,
		Forms = generateForms({
			"Subject",
			"Frostbitten",
			"Rimed",
			"Glacial",
			"Cryo-Aberrant",
			"Absolute Zero",
			"Form 7",
			"Form 8",
			"Form 9",
			"Form 10",
			"Form 11",
			"Form 12",
		}, 1),
		Stages = generateStages(12, 1),
		Boss = generateBoss(12, 1),
	},
	{
		Id = 2,
		Name = "Bio-Dome",
		LobbyOrigin = Vector3.new(WORLD_X_SPACING, 0, -300),
		ThemeColor = BIO_DOME_COLOR,
		Forms = generateForms({
			"Subject",
			"Spore-Touched",
			"Chlorotic",
			"Photosynthetic",
			"Verdant Horror",
			"Bloom Apex",
			"Form 7",
			"Form 8",
			"Form 9",
			"Form 10",
			"Form 11",
			"Form 12",
		}, 2.5),
		Stages = generateStages(5, 2.5),
		Boss = generateBoss(5, 2.5),
	},
	{
		Id = 3,
		Name = "Thermal",
		LobbyOrigin = Vector3.new(WORLD_X_SPACING * 2, 0, -300),
		ThemeColor = THERMAL_COLOR,
		Forms = generateForms({
			"Subject",
			"Scorched",
			"Magma-Veined",
			"Pyroclastic",
			"Ember Colossus",
			"Solar Flare",
			"Form 7",
			"Form 8",
			"Form 9",
			"Form 10",
			"Form 11",
			"Form 12",
		}, 6),
		Stages = generateStages(5, 6),
		Boss = generateBoss(5, 6),
	},
	{
		Id = 4,
		Name = "Flood",
		LobbyOrigin = Vector3.new(WORLD_X_SPACING * 3, 0, -300),
		ThemeColor = FLOOD_COLOR,
		Forms = generateForms({
			"Subject",
			"Waterlogged",
			"Brackish",
			"Abyssal",
			"Leviathan Spawn",
			"Tidal Sovereign",
			"Form 7",
			"Form 8",
			"Form 9",
			"Form 10",
			"Form 11",
			"Form 12",
		}, 14),
		Stages = generateStages(5, 14),
		Boss = generateBoss(5, 14),
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
