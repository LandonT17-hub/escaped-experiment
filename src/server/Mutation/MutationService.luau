local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GamepassService = require(script.Parent.GamepassService)

local MutationService = {}

local mutationValues: { [Player]: number } = {}
local winsValues: { [Player]: number } = {}
local rebirthCounts: { [Player]: number } = {}

local mutationUpdated = Remotes.GetRemoteEvent("MutationUpdated")
local winsUpdated = Remotes.GetRemoteEvent("WinsUpdated")
local rebirthUpdated = Remotes.GetRemoteEvent("RebirthUpdated")

-- No design doc with real numbers exists for Rebirth either -- placeholder,
-- adjust freely. Per CLAUDE.md ("Wins ... fuel Rebirth"), the cost is paid in
-- Wins, not Mutation; Mutation is the thing that gets reset as the trade-off
-- for a permanent gain multiplier, escalating cost per rebirth so each one is
-- a bigger commitment than the last.
local BASE_REBIRTH_WINS_COST = 50
local REBIRTH_COST_GROWTH = 2.5
local REBIRTH_MULTIPLIER_STEP = 0.5 -- +50% Mutation gain per rebirth, stacking additively

function MutationService.GetMutation(player: Player): number
	return mutationValues[player] or 0
end

function MutationService.GetWins(player: Player): number
	return winsValues[player] or 0
end

function MutationService.GetRebirthCount(player: Player): number
	return rebirthCounts[player] or 0
end

export type SaveData = {
	Mutation: number,
	Wins: number,
	RebirthCount: number,
}

-- nil means "this player has no live state to save" (already cleared by
-- ClearPlayerData) -- distinct from a legitimate all-zeros save, so callers
-- never write a wiped-out save over real progress by mistake.
function MutationService.GetSaveData(player: Player): SaveData?
	if mutationValues[player] == nil then
		return nil
	end

	return {
		Mutation = mutationValues[player],
		Wins = winsValues[player] or 0,
		RebirthCount = rebirthCounts[player] or 0,
	}
end

-- Applies loaded DataStore values on top of this player's current (fresh
-- default) state. Called by PersistenceService once a load resolves --
-- always strictly after onPlayerAdded below has already run for this player
-- (that handler never yields, so it always finishes before this one, which
-- is only reached after an async DataStore round trip).
function MutationService.LoadSaveData(player: Player, data: SaveData)
	if mutationValues[player] == nil then
		return
	end

	mutationValues[player] = data.Mutation
	winsValues[player] = data.Wins
	rebirthCounts[player] = data.RebirthCount

	mutationUpdated:FireClient(player, mutationValues[player])
	winsUpdated:FireClient(player, winsValues[player])
	rebirthUpdated:FireClient(player, MutationService.GetRebirthMultiplier(player))
end

function MutationService.GetRebirthMultiplier(player: Player): number
	return 1 + MutationService.GetRebirthCount(player) * REBIRTH_MULTIPLIER_STEP
end

-- Wins cost of this player's *next* rebirth -- escalates with how many
-- they've already done.
function MutationService.GetRebirthCost(player: Player): number
	return math.floor(BASE_REBIRTH_WINS_COST * REBIRTH_COST_GROWTH ^ MutationService.GetRebirthCount(player))
end

-- Only source of Mutation now: combat kills (see DummyEnemy.luau). No more
-- passive walk-to-gain -- removed entirely per design change.
--
-- Applies the player's owned Multiplier Pad gamepasses (Phase 4) and their
-- permanent Rebirth multiplier (Phase 5) here, at the single point Mutation
-- ever gets granted, so every source of Mutation benefits automatically
-- instead of each caller needing to remember to.
function MutationService.GrantMutation(player: Player, amount: number?)
	if mutationValues[player] == nil then
		return
	end

	local multiplier = GamepassService.GetMutationMultiplier(player) * MutationService.GetRebirthMultiplier(player)
	amount = math.floor((amount or 1) * multiplier)
	mutationValues[player] += amount
	mutationUpdated:FireClient(player, mutationValues[player])
end

function MutationService.GrantWins(player: Player, amount: number?)
	if winsValues[player] == nil then
		return
	end

	amount = amount or 1
	winsValues[player] += amount
	winsUpdated:FireClient(player, winsValues[player])
end

-- Atomic check-and-deduct: returns false (and changes nothing) if the player can't
-- afford it, so callers never need a separate balance check that could race.
function MutationService.SpendWins(player: Player, amount: number): boolean
	local current = winsValues[player]
	if not current or current < amount then
		return false
	end

	winsValues[player] = current - amount
	winsUpdated:FireClient(player, winsValues[player])
	return true
end

-- Server-authoritative Rebirth: atomically spends this player's current
-- Rebirth-cost in Wins (SpendWins already guards against affording it),
-- resets their Mutation to 0, and permanently increases their Mutation-gain
-- multiplier. Returns false (no state changed) if they can't afford it.
--
-- Deliberately does not reset unlocked Evolution forms or the equipped form
-- -- those are Wins-gated progression, not Mutation, and Rebirth already
-- spends Wins as its own cost; resetting them too would double-punish the
-- same currency. Mutation is the only thing traded away here.
function MutationService.TryRebirth(player: Player): boolean
	if mutationValues[player] == nil then
		return false
	end

	local cost = MutationService.GetRebirthCost(player)
	if not MutationService.SpendWins(player, cost) then
		return false
	end

	mutationValues[player] = 0
	mutationUpdated:FireClient(player, 0)

	rebirthCounts[player] = MutationService.GetRebirthCount(player) + 1
	rebirthUpdated:FireClient(player, MutationService.GetRebirthMultiplier(player))

	return true
end

local function onPlayerAdded(player: Player)
	mutationValues[player] = 0
	winsValues[player] = 0
	rebirthCounts[player] = 0
	mutationUpdated:FireClient(player, 0)
	winsUpdated:FireClient(player, 0)
	rebirthUpdated:FireClient(player, MutationService.GetRebirthMultiplier(player))
end

-- Called explicitly by PersistenceService, after it has read (and saved)
-- this player's final state -- deliberately NOT wired to PlayerRemoving
-- directly here. Two independent PlayerRemoving listeners racing (one
-- reading state to save, one clearing it) can't be ordered against each
-- other reliably; PersistenceService owns the full read-then-clear sequence
-- itself instead, as straight-line code.
function MutationService.ClearPlayerData(player: Player)
	mutationValues[player] = nil
	winsValues[player] = nil
	rebirthCounts[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

return MutationService
