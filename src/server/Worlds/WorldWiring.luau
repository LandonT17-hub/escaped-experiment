-- Attaches one world's gameplay systems to its hand-built parts (resolved by
-- MapResolver): stage objectives, the boss arena, Form Pedestals, Multiplier
-- Pads, leaderboards and training dummies. Builds no geometry -- the map
-- lives in the place file. (Rebirth, Store and Codes are HUD menus, not
-- stations -- see Menus/.)

local ServerScriptService = game:GetService("ServerScriptService")

local MapResolver = require(script.Parent.MapResolver)
local StageObjective = require(script.Parent.StageObjective)
local WorldsData = require(script.Parent.WorldsData)
local FormPedestals = require(ServerScriptService.Server.Evolution.FormPedestals)
local MultiplierPads = require(ServerScriptService.Server.Mutation.MultiplierPads)
local Leaderboards = require(ServerScriptService.Server.Lobby.Leaderboards)
local TrainingDummies = require(ServerScriptService.Server.Lobby.TrainingDummies)

local WorldWiring = {}

function WorldWiring.Wire(config: WorldsData.WorldConfig, parts: MapResolver.WorldParts)
	for i, stageConfig in config.Stages do
		local stageParts = parts.Stages[i]
		if stageParts then
			StageObjective.Wire(stageParts, stageConfig)
		end
	end

	if parts.Boss then
		StageObjective.Wire(parts.Boss, config.Boss)
	end

	-- Before anything reads form names/costs: the pedestals' attributes
	-- overwrite WorldsData's placeholders.
	if parts.Pedestals then
		FormPedestals.WireUp(parts.Pedestals, config.Id, config.Forms)
	end

	if parts.MultiplierPads then
		MultiplierPads.WireUp(parts.MultiplierPads)
	end

	if parts.Leaderboards then
		Leaderboards.WireUp(parts.Leaderboards)
	end

	if parts.TrainingArea then
		TrainingDummies.WireUp(parts.TrainingArea)
	end
end

return WorldWiring
