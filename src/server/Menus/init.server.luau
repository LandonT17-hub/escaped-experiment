local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MutationService = require(ServerScriptService.Server.Mutation.MutationService)
local GamepassData = require(ServerScriptService.Server.Mutation.GamepassData)
local GamepassService = require(ServerScriptService.Server.Mutation.GamepassService)
local CodesService = require(script.CodesService)

-- Server side of the HUD menu buttons (Rebirth, Store, Codes) that replaced
-- the physical lobby stations. The client only asks; every decision --
-- affordability, which passes exist, code validity -- is made here.

local REBIRTH_COOLDOWN = 1 -- seconds; one click shouldn't double-fire a rebirth

local lastRebirthAt: { [Player]: number } = {}

Players.PlayerRemoving:Connect(function(player: Player)
	lastRebirthAt[player] = nil
end)

-- Rebirth ------------------------------------------------------------------

local function rebirthInfo(player: Player)
	return {
		Cost = MutationService.GetRebirthCost(player),
		Count = MutationService.GetRebirthCount(player),
		Multiplier = MutationService.GetRebirthMultiplier(player),
	}
end

Remotes.GetRemoteFunction("GetRebirthInfo").OnServerInvoke = function(player: Player)
	return rebirthInfo(player)
end

-- Returns (success, info after the attempt).
Remotes.GetRemoteFunction("RequestRebirth").OnServerInvoke = function(player: Player)
	local now = os.clock()
	local last = lastRebirthAt[player]
	if last and now - last < REBIRTH_COOLDOWN then
		return false, rebirthInfo(player)
	end
	lastRebirthAt[player] = now

	local success = MutationService.TryRebirth(player)
	return success, rebirthInfo(player)
end

-- Store --------------------------------------------------------------------

type StoreItem = { Name: string, GamePassId: number, Owned: boolean }

-- Only passes that exist (id > 0); empty until they're created.
local function storeCatalog(player: Player): { StoreItem }
	local items = {}

	local premiumWinsId = GamepassData.PremiumWinsPassId
	if premiumWinsId > 0 then
		table.insert(items, {
			Name = "Premium Wins",
			GamePassId = premiumWinsId,
			Owned = GamepassService.OwnsGamePass(player, premiumWinsId),
		})
	end

	local plotPassId = GamepassData.TrainingPlotPassId
	if plotPassId > 0 then
		table.insert(items, {
			Name = "x10 Training Plot",
			GamePassId = plotPassId,
			Owned = GamepassService.OwnsGamePass(player, plotPassId),
		})
	end

	return items
end

Remotes.GetRemoteFunction("GetStoreCatalog").OnServerInvoke = function(player: Player)
	return storeCatalog(player)
end

-- Only prompts for a pass that's actually in the catalog, so a client can't
-- use this to prompt arbitrary passes.
Remotes.GetRemoteEvent("StorePurchaseRequest").OnServerEvent:Connect(function(player: Player, gamePassId: unknown)
	if typeof(gamePassId) ~= "number" then
		return
	end
	for _, item in storeCatalog(player) do
		if item.GamePassId == gamePassId and not item.Owned then
			GamepassService.PromptPurchase(player, gamePassId)
			return
		end
	end
end)

-- Codes --------------------------------------------------------------------

-- Returns (success, message to show).
Remotes.GetRemoteFunction("RedeemCode").OnServerInvoke = function(player: Player, code: unknown)
	return CodesService.Redeem(player, code)
end
