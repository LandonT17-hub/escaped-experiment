-- Attaches one world's gameplay systems to its hand-built parts (resolved by
-- MapResolver): stage objectives, the boss arena, Form Pedestals,
-- leaderboards and training plots. Builds no geometry -- the map
-- lives in the place file. (Rebirth, Store and Codes are HUD menus, not
-- stations -- see Menus/.)

local ServerScriptService = game:GetService("ServerScriptService")

local MapResolver = require(script.Parent.MapResolver)
local StageObjective = require(script.Parent.StageObjective)
local WorldsData = require(script.Parent.WorldsData)
local FormPedestals = require(ServerScriptService.Server.Evolution.FormPedestals)
local Leaderboards = require(ServerScriptService.Server.Lobby.Leaderboards)
local TrainingPlots = require(ServerScriptService.Server.Lobby.TrainingPlots)

local WorldWiring = {}

function WorldWiring.Wire(config: WorldsData.WorldConfig, parts: MapResolver.WorldParts)
	for i, stageConfig in config.Stages do
		local stageParts = parts.Stages[i]
		if stageParts then
			stageParts.Index = i
			StageObjective.Wire(stageParts, stageConfig)
		end
	end

	if parts.Boss then
		parts.Boss.Index = #config.Stages + 1
		StageObjective.Wire(parts.Boss, config.Boss)
	end

	-- Before anything reads form names/costs: the pedestals' attributes
	-- overwrite WorldsData's placeholders.
	if parts.Pedestals then
		FormPedestals.WireUp(parts.Pedestals, config.Id, config.Forms)
	end

	if parts.Leaderboards then
		Leaderboards.WireUp(parts.Leaderboards)
	end

	if parts.TrainingPlots then
		TrainingPlots.WireUp(parts.TrainingPlots)
	end
end

return WorldWiring
