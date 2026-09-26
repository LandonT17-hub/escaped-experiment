-- Thin, pcall-guarded wrapper around the one DataStore this game uses for
-- player progress. Doesn't know anything about Mutation/Evolution/Worlds --
-- PersistenceService assembles the SavedData shape and hands it here; this
-- module's only job is "get/set this key, never let a DataStore error
-- propagate as an uncaught exception."

local DataStoreService = game:GetService("DataStoreService")

-- Versioned name: bumping this starts everyone fresh under a new key space
-- instead of silently misreading old-shape data if the schema ever changes
-- incompatibly.
local store = DataStoreService:GetDataStore("PlayerData_v1")

export type SavedData = {
	Mutation: number,
	Wins: number,
	RebirthCount: number,
	CurrentWorldId: number,
	UnlockedForms: { [string]: { [string]: boolean } },
	EquippedForm: { WorldId: number, FormIndex: number },
}

local PlayerDataStore = {}

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

-- Returns nil both when there's genuinely no save yet (a brand-new player)
-- and when the load call itself failed -- callers can't tell those apart
-- from the return value, which is intentional: either way, the caller falls
-- through to fresh default state rather than ever guessing at a player's
-- progress.
function PlayerDataStore.Load(player: Player): SavedData?
	local ok, result = pcall(function()
		return store:GetAsync(keyFor(player))
	end)

	if not ok then
		warn(string.format("[PlayerDataStore] Load failed for %s: %s", player.Name, tostring(result)))
		return nil
	end

	return result :: SavedData?
end

function PlayerDataStore.Save(player: Player, data: SavedData): boolean
	local ok, err = pcall(function()
		store:SetAsync(keyFor(player), data)
	end)

	if not ok then
		warn(string.format("[PlayerDataStore] Save failed for %s: %s", player.Name, tostring(err)))
	end

	return ok
end

return PlayerDataStore
