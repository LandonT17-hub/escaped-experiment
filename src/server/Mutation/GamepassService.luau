local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local GamepassData = require(script.Parent.GamepassData)

local GamepassService = {}

-- Cached per player so a Mutation grant (on every enemy kill, the hottest
-- path in the game) never blocks on a MarketplaceService round trip.
-- Refreshed on join and again whenever a purchase completes; until the
-- first refresh lands, a player's multiplier reads as 1 (no owned tiers) --
-- a brief, harmless undercount right at join, never an overcount.
local ownedTiers: { [Player]: { [number]: boolean } } = {}

local function computeOwnedTiers(player: Player): { [number]: boolean }
	local owned = {}
	for i, tier in GamepassData.MutationMultiplierTiers do
		if tier.GamePassId > 0 then
			local ok, result =
				pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, tier.GamePassId)
			owned[i] = ok and result == true
		end
	end
	return owned
end

function GamepassService.RefreshPlayer(player: Player)
	local owned = computeOwnedTiers(player)
	-- The ownership check yields; re-check the player hasn't left in the
	-- meantime before writing back, so a departed player's slot doesn't get
	-- silently recreated.
	if player.Parent then
		ownedTiers[player] = owned
	end
end

function GamepassService.OwnsTier(player: Player, tierIndex: number): boolean
	local owned = ownedTiers[player]
	return owned ~= nil and owned[tierIndex] == true
end

-- All owned tiers stack multiplicatively.
function GamepassService.GetMutationMultiplier(player: Player): number
	local owned = ownedTiers[player]
	if not owned then
		return 1
	end

	local total = 1
	for i, tier in GamepassData.MutationMultiplierTiers do
		if owned[i] then
			total *= tier.Multiplier
		end
	end
	return total
end

function GamepassService.PromptPurchase(player: Player, gamePassId: number)
	if gamePassId <= 0 then
		return -- not yet created in the Creator Dashboard
	end
	MarketplaceService:PromptGamePassPurchase(player, gamePassId)
end

local function onPlayerAdded(player: Player)
	task.spawn(GamepassService.RefreshPlayer, player)
end

local function onPlayerRemoving(player: Player)
	ownedTiers[player] = nil
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, _gamePassId: number, wasPurchased: boolean)
	if wasPurchased then
		GamepassService.RefreshPlayer(player)
	end
end)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

return GamepassService
