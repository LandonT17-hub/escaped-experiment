local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local GamepassData = require(script.Parent.GamepassData)

local GamepassService = {}

-- Cached per player so a Mutation grant (on every enemy kill, the hottest
-- path in the game) never blocks on a MarketplaceService round trip.
-- Refreshed on join and again whenever a purchase completes; until the
-- first refresh lands, a player owns nothing -- a brief, harmless undercount
-- right at join, never an overcount.
local ownedPasses: { [Player]: { [number]: boolean } } = {}

local function computeOwnedPasses(player: Player): { [number]: boolean }
	local owned = {}
	for _, id in GamepassData.AllPassIds() do
		local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
		owned[id] = ok and result == true
	end
	return owned
end

function GamepassService.RefreshPlayer(player: Player)
	local owned = computeOwnedPasses(player)
	-- The ownership check yields; re-check the player hasn't left in the
	-- meantime before writing back, so a departed player's slot doesn't get
	-- silently recreated.
	if player.Parent then
		ownedPasses[player] = owned
	end
end

function GamepassService.OwnsGamePass(player: Player, gamePassId: number): boolean
	local owned = ownedPasses[player]
	return owned ~= nil and owned[gamePassId] == true
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
	ownedPasses[player] = nil
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
