local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local EnemyRegistry = require(ServerScriptService.Server.Enemies.EnemyRegistry)
local EvolutionService = require(ServerScriptService.Server.Evolution.EvolutionService)
local EnemyDebug = require(ServerScriptService.Server.Enemies.EnemyDebug)

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

	local candidateCount = 0
	for model, api in EnemyRegistry.GetAll() do
		candidateCount += 1
		local enemyRoot = api.TargetPart or model.PrimaryPart
		if enemyRoot then
			local offset = enemyRoot.Position - originPosition
			local distance = offset.Magnitude
			local direction = if distance > 0 then offset.Unit else lookVector
			local dot = lookVector:Dot(direction)
			local enemyHumanoid = model:FindFirstChildOfClass("Humanoid")

			local verdict
			if enemyHumanoid and enemyHumanoid.Health <= 0 then
				verdict = "rejected: dead"
			elseif distance > MELEE_RANGE then
				verdict = `rejected: range (>{MELEE_RANGE})`
			elseif dot < FACING_DOT_THRESHOLD then
				verdict = string.format("rejected: facing (dot %.2f < %.2f)", dot, FACING_DOT_THRESHOLD)
			elseif distance >= nearestDistance then
				verdict = "rejected: a closer target was found"
			else
				verdict = "candidate"
				nearestModel, nearestApi, nearestDistance = model, api, distance
			end

			if distance <= 60 then
				EnemyDebug.Log(`  Bite {player.Name}: {EnemyDebug.Name(model)} dist={string.format("%.1f", distance)} {verdict}`)
			end
		else
			EnemyDebug.Log(`  Bite {player.Name}: {model:GetFullName()} rejected: no TargetPart/PrimaryPart`)
		end
	end
	EnemyDebug.Log(`  Bite {player.Name}: {candidateCount} registered targets checked (only those within 60 studs listed)`)

	return nearestModel, nearestApi
end

function CombatService.RequestAttack(player: Player)
	local now = os.clock()
	local lastAttack = lastAttackTimes[player]
	if lastAttack and now - lastAttack < ATTACK_COOLDOWN then
		EnemyDebug.Log(`Bite {player.Name}: rejected: cooldown ({string.format("%.2f", now - lastAttack)}s < {ATTACK_COOLDOWN}s)`)
		return
	end
	lastAttackTimes[player] = now

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	EnemyDebug.Log(`Bite {player.Name}: request at {if rootPart then EnemyDebug.Vec(rootPart.Position) else "(no HumanoidRootPart)"}`)

	local targetModel, targetApi = findTarget(player)
	if targetModel and targetApi then
		local damage = CombatService.GetDamage(player)
		local enemyHumanoid = targetModel:FindFirstChildOfClass("Humanoid")
		local before = if enemyHumanoid then enemyHumanoid.Health else nil
		targetApi.TakeDamage(damage, player)
		local hpText = if enemyHumanoid then `, hp {before} -> {enemyHumanoid.Health}` else " (no Humanoid, e.g. training dummy)"
		EnemyDebug.Log(`Bite {player.Name}: ACCEPTED {EnemyDebug.Name(targetModel)} damage={damage}{hpText}`)
	else
		EnemyDebug.Log(`Bite {player.Name}: no target hit`)
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
