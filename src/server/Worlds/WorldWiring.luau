-- Attaches one world's gameplay systems (Form Pedestals, Multiplier Pads,
-- Rebirth station, stage objectives, gateway to the next world) to that
-- world's hand-built parts. Builds no geometry -- the map lives in the place
-- file. Called once per entry in WorldsData.Worlds.

local ServerScriptService = game:GetService("ServerScriptService")

local StageObjective = require(script.Parent.StageObjective)
local WorldGateway = require(script.Parent.WorldGateway)
local WorldsData = require(script.Parent.WorldsData)
local FormPedestals = require(ServerScriptService.Server.Evolution.FormPedestals)
local MultiplierPads = require(ServerScriptService.Server.Mutation.MultiplierPads)
local RebirthStation = require(ServerScriptService.Server.Mutation.RebirthStation)
local PersistenceService = require(ServerScriptService.Server.Persistence.PersistenceService)

-- The hand-built parts one world's systems attach to. Any station left nil
-- is skipped.
export type WorldParts = {
	FormPedestals: Instance?, -- contains "FormPedestal1".."FormPedestal6"
	MultiplierPads: Instance?, -- contains "MultiplierPad1".."MultiplierPad4"
	RebirthZone: BasePart?,
	Stages: { StageObjective.StageParts }, -- in order, one per config.Stages entry
	Gateway: BasePart?, -- walk-through screen at the end of the final stage
}

local WorldWiring = {}

function WorldWiring.Wire(
	config: WorldsData.WorldConfig,
	nextWorldConfig: WorldsData.WorldConfig?,
	parts: WorldParts
): { StageObjective.BuiltStage }
	local stages: { StageObjective.BuiltStage } = {}
	for i, stageConfig in config.Stages do
		local stageParts = parts.Stages[i]
		if not stageParts then
			warn(`WorldWiring: World {config.Id} has no parts for {stageConfig.Name}`)
			break
		end
		table.insert(stages, StageObjective.Wire(stageParts, stageConfig))
	end

	local finalStage = stages[#config.Stages]
	if parts.Gateway and nextWorldConfig and finalStage then
		WorldGateway.Wire(parts.Gateway, finalStage.IsCleared, {
			Destination = WorldsData.SpawnCFrameFor(nextWorldConfig),
			DestinationName = string.format("World %d: %s", nextWorldConfig.Id, nextWorldConfig.Name),
			LockedLabel = string.format("LOCKED -- clear World %d to proceed", config.Id),
			OnEnter = function(player: Player)
				PersistenceService.SetCurrentWorld(player, nextWorldConfig.Id)
			end,
		})
	end

	if parts.FormPedestals then
		FormPedestals.WireUp(parts.FormPedestals, config.Id, config.Name, config.Forms)
	end

	if parts.MultiplierPads then
		MultiplierPads.WireUp(parts.MultiplierPads)
	end

	if parts.RebirthZone then
		RebirthStation.WireUp(parts.RebirthZone)
	end

	return stages
end

return WorldWiring
