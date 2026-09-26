local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local EnemyRegistry = require(ServerScriptService.Server.Enemies.EnemyRegistry)
local EvolutionService = require(ServerScriptService.Server.Evolution.EvolutionService)

-- Base before the current form's multiplier is applied.
local BASE_DAMAGE = 10
local ATTACK_COOLDOWN = 0.5
local MELEE_RANGE = 6
local FACING_DOT_THRESHOLD = 0.5 -- roughly a 120-degree cone in front of the player

local CombatService = {}

local lastAttackTimes: { [Player]: number } = {}

-- Derived live from the player's current form, not stored -- a single source of
-- truth (EvolutionService) instead of a value that could drift out of sync.
function CombatService.GetDamage(player: Player): number
	return BASE_DAMAGE * EvolutionService.GetDamageMultiplier(player)
end

local function findTarget(player: Player): (Model?, EnemyRegistry.EnemyApi?)
	local character = player.Character
	if not character then
		return nil, nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return nil, nil
	end

	local originPosition = (rootPart :: BasePart).Position
	local lookVector = (rootPart :: BasePart).CFrame.LookVector

	local nearestModel: Model? = nil
	local nearestApi: EnemyRegistry.EnemyApi? = nil
	local nearestDistance = math.huge

	for model, api in EnemyRegistry.GetAll() do
		local enemyRoot = model.PrimaryPart
		if enemyRoot then
			local offset = enemyRoot.Position - originPosition
			local distance = offset.Magnitude
			if distance <= MELEE_RANGE and distance < nearestDistance then
				local direction = if distance > 0 then offset.Unit else lookVector
				if lookVector:Dot(direction) >= FACING_DOT_THRESHOLD then
					nearestModel, nearestApi, nearestDistance = model, api, distance
				end
			end
		end
	end

	return nearestModel, nearestApi
end

function CombatService.RequestAttack(player: Player)
	local now = os.clock()
	local lastAttack = lastAttackTimes[player]
	if lastAttack and now - lastAttack < ATTACK_COOLDOWN then
		return
	end
	lastAttackTimes[player] = now

	local _, targetApi = findTarget(player)
	if targetApi then
		targetApi.TakeDamage(CombatService.GetDamage(player), player)
	end
end

local function onPlayerRemoving(player: Player)
	lastAttackTimes[player] = nil
end

Players.PlayerRemoving:Connect(onPlayerRemoving)

local attackRequest = Remotes.GetRemoteEvent("AttackRequest")
attackRequest.OnServerEvent:Connect(function(player: Player)
	CombatService.RequestAttack(player)
end)

return CombatService
