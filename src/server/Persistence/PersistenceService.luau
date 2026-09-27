-- Orchestrates loading/saving each player's progress (Phase 6 of the master
-- build): Mutation, Wins, Rebirth count, unlocked/equipped Evolution forms,
-- and which world they've reached. Doesn't own any of that state itself --
-- MutationService and EvolutionService remain the source of truth for their
-- own runtime state; this module just reads it (GetSaveData), writes it back
-- on load (LoadSaveData), and is the sole owner of clearing it on leave
-- (ClearPlayerData), so there's exactly one read-then-clear sequence per
-- player instead of multiple independent PlayerRemoving listeners racing.
--
-- "Current world/stage": stage-clear progress is shared, ephemeral,
-- server-session state (see StageObjective.luau -- one shared instance of each
-- stage, not per-player; that's a pre-existing design decision, not
-- something this phase changes). What's meaningfully per-player and worth
-- persisting is which world a player has reached, so a returning player
-- resumes there instead of back at World1's spawn every time.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataStore = require(script.Parent.PlayerDataStore)
local MutationService = require(ServerScriptService.Server.Mutation.MutationService)
local EvolutionService = require(ServerScriptService.Server.Evolution.EvolutionService)
local CodesService = require(ServerScriptService.Server.Menus.CodesService)
local WorldsData = require(ServerScriptService.Server.Worlds.WorldsData)

local PersistenceService = {}

local currentWorldId: { [Player]: number } = {}

function PersistenceService.GetCurrentWorld(player: Player): number
	return currentWorldId[player] or 1
end

-- Called whenever a player moves into a new world (via a world gateway /
-- portal, once one is wired) -- keeps the persisted "where to resume" value
-- current without the gateway needing to know persistence exists.
function PersistenceService.SetCurrentWorld(player: Player, worldId: number)
	currentWorldId[player] = worldId
end

-- Only World1's lobby should have a real SpawnLocation (a neutral one in
-- every lobby would let a new player's first spawn land in any world). So
-- for any player whose current world isn't 1, reposition
-- them there explicitly on every spawn -- both the very first one after a
-- rejoin, and every respawn-after-death while adventuring in World2+.
local function repositionForCurrentWorld(player: Player, character: Model)
	local worldId = PersistenceService.GetCurrentWorld(player)
	if worldId <= 1 then
		return
	end

	local worldConfig = WorldsData.Worlds[worldId]
	if not worldConfig then
		return
	end

	if character:WaitForChild("HumanoidRootPart", 5) then
		character:PivotTo(WorldsData.SpawnCFrameFor(worldConfig))
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		repositionForCurrentWorld(player, character)
	end)

	-- MutationService/EvolutionService's own onPlayerAdded handlers run
	-- synchronously (no yields) in response to the same PlayerAdded event, so
	-- by the time this DataStore round trip resolves -- necessarily after at
	-- least one yield -- their fresh-default state for this player already
	-- exists, regardless of which script's PlayerAdded connection fired
	-- first. LoadSaveData on each service only applies on top of that.
	task.spawn(function()
		local saved = PlayerDataStore.Load(player)
		if not player.Parent then
			return -- left during the load
		end

		if saved then
			MutationService.LoadSaveData(player, saved)
			EvolutionService.LoadSaveData(player, saved)
			currentWorldId[player] = saved.CurrentWorldId or 1
		else
			currentWorldId[player] = 1
		end
		-- Always called, save or not: it also unlocks code redemption.
		CodesService.LoadSaveData(player, saved and saved.RedeemedCodes)

		if player.Character then
			repositionForCurrentWorld(player, player.Character)
		end
	end)
end

local function gatherSaveData(player: Player): PlayerDataStore.SavedData?
	local mutationData = MutationService.GetSaveData(player)
	local evolutionData = EvolutionService.GetSaveData(player)
	local redeemedCodes = CodesService.GetSaveData(player)
	if not mutationData or not evolutionData or not redeemedCodes then
		-- One of the services already tore this player's state down (or
		-- never set it up); nothing valid left to save.
		return nil
	end

	return {
		Mutation = mutationData.Mutation,
		Wins = mutationData.Wins,
		RebirthCount = mutationData.RebirthCount,
		CurrentWorldId = PersistenceService.GetCurrentWorld(player),
		UnlockedForms = evolutionData.UnlockedForms,
		EquippedForm = evolutionData.EquippedForm,
		RedeemedCodes = redeemedCodes,
	}
end

local function onPlayerRemoving(player: Player)
	local data = gatherSaveData(player)
	if data then
		-- Yielding here is expected and fine: PlayerRemoving handlers are
		-- allowed to yield, specifically to support finishing a save exactly
		-- like this before the Player instance is torn down.
		PlayerDataStore.Save(player, data)
	end

	-- Runs after the save attempt (success or failure) -- always clear so a
	-- departed player's entries don't linger in every service's tables.
	MutationService.ClearPlayerData(player)
	EvolutionService.ClearPlayerData(player)
	CodesService.ClearPlayerData(player)
	currentWorldId[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

-- Best-effort safety net: a full server shutdown doesn't reliably give every
-- connected player's PlayerRemoving handler time to finish its SetAsync
-- call otherwise. Doesn't clear per-player state afterward -- the server
-- process is ending anyway.
game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		local data = gatherSaveData(player)
		if data then
			PlayerDataStore.Save(player, data)
		end
	end
end)

return PersistenceService
