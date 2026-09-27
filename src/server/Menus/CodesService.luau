local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local CodesData = require(script.Parent.CodesData)
local MutationService = require(ServerScriptService.Server.Mutation.MutationService)

-- Server-authoritative code redemption: the client only sends the typed
-- string. Each code pays once per player, ever -- the redeemed set is
-- persisted by PersistenceService.

local MAX_CODE_LENGTH = 32
local REDEEM_COOLDOWN = 1 -- seconds; slows brute-force guessing

local CodesService = {}

local redeemed: { [Player]: { [string]: boolean } } = {}
-- Redemption waits for the player's save to load; otherwise a reward granted
-- first would be overwritten by the loaded Wins/Mutation.
local loaded: { [Player]: boolean } = {}
local lastAttemptAt: { [Player]: number } = {}

-- Returns (success, message for the player).
function CodesService.Redeem(player: Player, rawCode: unknown): (boolean, string)
	if typeof(rawCode) ~= "string" or #rawCode == 0 or #rawCode > MAX_CODE_LENGTH then
		return false, "Invalid code"
	end

	local now = os.clock()
	local last = lastAttemptAt[player]
	if last and now - last < REDEEM_COOLDOWN then
		return false, "Slow down"
	end
	lastAttemptAt[player] = now

	local playerRedeemed = redeemed[player]
	if not loaded[player] or not playerRedeemed then
		return false, "Still loading, try again"
	end

	local code = string.upper((rawCode :: string):match("^%s*(.-)%s*$") or "")
	local reward = CodesData[code]
	if not reward then
		return false, "Invalid code"
	end

	if playerRedeemed[code] then
		return false, "Already redeemed"
	end

	playerRedeemed[code] = true

	local parts = {}
	if reward.Wins then
		MutationService.GrantWins(player, reward.Wins)
		table.insert(parts, `+{reward.Wins} Wins`)
	end
	if reward.Mutation then
		MutationService.GrantMutation(player, reward.Mutation)
		table.insert(parts, `+{reward.Mutation} Mutation`)
	end

	return true, "Redeemed! " .. table.concat(parts, ", ")
end

export type SaveData = { [string]: boolean }

-- nil means "no live state to save" (already cleared).
function CodesService.GetSaveData(player: Player): SaveData?
	return redeemed[player]
end

-- Always called by PersistenceService once the load resolves (data is nil
-- for a brand-new player or an old save without codes). Merges, never
-- replaces, so nothing redeemed this session is lost.
function CodesService.LoadSaveData(player: Player, data: SaveData?)
	local playerRedeemed = redeemed[player]
	if not playerRedeemed then
		return
	end

	if data then
		for code, isRedeemed in data do
			if isRedeemed then
				playerRedeemed[code] = true
			end
		end
	end
	loaded[player] = true
end

-- Called explicitly by PersistenceService after saving; see
-- MutationService.ClearPlayerData for why this isn't a PlayerRemoving handler.
function CodesService.ClearPlayerData(player: Player)
	redeemed[player] = nil
	loaded[player] = nil
	lastAttemptAt[player] = nil
end

local function onPlayerAdded(player: Player)
	redeemed[player] = {}
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

return CodesService
