local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ServerScriptService = game:GetService("ServerScriptService")

local EnemyRegistry = require(script.Parent.EnemyRegistry)
local MutationService = require(ServerScriptService.Server.Mutation.MutationService)

local MAX_HEALTH = 100
local KILL_MUTATION_REWARD = 25
local DEFAULT_RESPAWN_DELAY = 5
local TINT_COLOR = Color3.fromRGB(200, 90, 90) -- placeholder dummy-target red

-- Placeholder attack-back tuning -- no design doc numbers for this exist either;
-- adjust freely.
local ATTACK_INTERVAL = 1.5 -- seconds between attack checks
local ATTACK_RANGE = 6 -- studs, matches the player's own melee range
local ATTACK_DAMAGE = 5

-- Pursuit tuning. Same anti-jitter shape as Warden.luau's chase loop: a cheap
-- waypoint-proximity check runs often, the expensive PathfindingService replan
-- runs rarely, and there is never more than one MoveTo command in flight.
local ENEMY_WALK_SPEED = 10
local DETECTION_RANGE = 40 -- start chasing once a player is this close
local LEASH_RANGE = 45 -- give up and head home if pulled this far from spawn
local RETARGET_INTERVAL = 0.75 -- full path replan cadence (spec: ~0.5s, not every frame)
local ADVANCE_CHECK_INTERVAL = 0.15 -- cheap proximity/advance check cadence
local WAYPOINT_ARRIVAL_DISTANCE = 3
local RETURN_HOME_DISTANCE = 2 -- close enough to spawn to stop and idle

export type SpawnOptions = {
	-- Called (with the killer, if any) after death/registry-cleanup/Mutation grant,
	-- instead of the default self-respawn loop. Stages use this: their enemies
	-- should stay dead and report the kill upward, not respawn forever like the
	-- Lobby's standalone test dummy does.
	OnDeath: ((killer: Player?) -> ())?,
	-- Uniform size multiplier. At Scale 1 the rig is ~4.4 studs tall (roughly
	-- player-sized); stages needing taller enemies (per spec) pass a bigger value.
	Scale: number?,
	-- Per-spawn overrides so stage configs can escalate difficulty/reward without
	-- touching this module. Both default to the flat placeholder constants below.
	Health: number?,
	MutationReward: number?,
}

-- Returned by Spawn so a caller (StageObjective) can remove a living enemy
-- when its stage goes idle. Despawning is not a death: no Mutation is
-- granted, OnDeath doesn't fire, and the default respawn loop doesn't run.
export type EnemyHandle = {
	Despawn: () -> (),
}

local DummyEnemy = {}

local function buildModel(spawnCFrame: CFrame, scale: number, maxHealth: number): Model
	local model = Instance.new("Model")
	model.Name = "DummyEnemy"

	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 1) * scale
	rootPart.Transparency = 1
	rootPart.CanCollide = false
	rootPart.Anchored = false
	rootPart.CFrame = spawnCFrame
	rootPart.Parent = model

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 3, 1) * scale
	torso.Color = TINT_COLOR
	torso.Material = Enum.Material.SmoothPlastic
	torso.CanCollide = true
	torso.CFrame = rootPart.CFrame
	torso.Parent = model

	local torsoWeld = Instance.new("WeldConstraint")
	torsoWeld.Part0 = rootPart
	torsoWeld.Part1 = torso
	torsoWeld.Parent = rootPart

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.4, 1.4, 1.4) * scale
	head.Color = TINT_COLOR
	head.Material = Enum.Material.SmoothPlastic
	head.CanCollide = false
	head.CFrame = rootPart.CFrame * CFrame.new(0, 2.2 * scale, 0)
	head.Parent = model

	local headWeld = Instance.new("WeldConstraint")
	headWeld.Part0 = rootPart
	headWeld.Part1 = head
	headWeld.Parent = rootPart

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = ENEMY_WALK_SPEED
	humanoid.Parent = model

	model.PrimaryPart = rootPart

	return model
end

local function buildHealthBar(parent: BasePart, humanoid: Humanoid, scale: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Size = UDim2.fromOffset(120, 20)
	-- Scales with the rig so it floats just above the head at any size, instead
	-- of sitting inside a taller enemy's head at a fixed offset.
	billboard.StudsOffset = Vector3.new(0, 3.2 * scale, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = parent

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	background.BorderSizePixel = 0
	background.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = background

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.TextStrokeTransparency = 0.4
	text.Text = string.format("%d / %d", humanoid.Health, humanoid.MaxHealth)
	text.Parent = background

	humanoid.HealthChanged:Connect(function(health: number)
		local ratio = math.clamp(health / humanoid.MaxHealth, 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		text.Text = string.format("%d / %d", math.max(0, math.floor(health)), humanoid.MaxHealth)
	end)
end

local function findNearestPlayerInRange(fromPosition: Vector3, range: number): Model?
	local nearestCharacter, nearestDistance = nil, math.huge

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local targetHumanoid = character and character:FindFirstChildOfClass("Humanoid")
		if hrp and targetHumanoid and targetHumanoid.Health > 0 then
			local distance = ((hrp :: BasePart).Position - fromPosition).Magnitude
			if distance <= range and distance < nearestDistance then
				nearestCharacter, nearestDistance = character, distance
			end
		end
	end

	return nearestCharacter
end

local function computePathTo(path: Path, rootPart: BasePart, targetPosition: Vector3): { PathWaypoint }?
	local computed = pcall(function()
		path:ComputeAsync(rootPart.Position, targetPosition)
	end)

	if computed and path.Status == Enum.PathStatus.Success then
		return path:GetWaypoints()
	end

	return nil
end

-- Same decoupled-rate shape as Warden.luau's chase loop: cheap waypoint-proximity
-- checks run every ADVANCE_CHECK_INTERVAL, the expensive PathfindingService
-- replan only runs every RETARGET_INTERVAL, and there's a single dedupe-guarded
-- MoveTo call site -- never more than one movement command in flight, and never
-- a naive straight-line fallback if a replan fails. While idle (nothing to
-- chase or return to) it sleeps for the full replan interval instead of
-- ticking the waypoint check.
local function pursuitLoop(model: Model, rootPart: BasePart, humanoid: Humanoid, scale: number, spawnPosition: Vector3)
	-- One Path object per enemy, reused for every replan.
	local path = PathfindingService:CreatePath({
		AgentRadius = 2 * scale,
		AgentHeight = 5 * scale,
		AgentCanJump = false,
	})

	local waypoints: { PathWaypoint } = {}
	local waypointIndex = 1
	local activeMoveTarget: Vector3? = nil
	local timeSinceReplan = 0

	while model.Parent do
		if timeSinceReplan >= RETARGET_INTERVAL then
			timeSinceReplan = 0

			local destination: Vector3? = nil

			if humanoid.Health > 0 then
				local distanceFromSpawn = (rootPart.Position - spawnPosition).Magnitude
				local targetCharacter = findNearestPlayerInRange(rootPart.Position, DETECTION_RANGE)

				if targetCharacter and distanceFromSpawn <= LEASH_RANGE then
					local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
					if targetRoot then
						local targetDistance = (targetRoot.Position - rootPart.Position).Magnitude
						if targetDistance > ATTACK_RANGE then
							destination = targetRoot.Position
						end
						-- else: already close enough to fight -- hold position, let attackLoop work.
					end
				elseif distanceFromSpawn > RETURN_HOME_DISTANCE then
					-- No target in range, or pulled too far from spawn -- head home.
					destination = spawnPosition
				end
			end

			if destination then
				local newWaypoints = computePathTo(path, rootPart, destination)
				-- If no valid route exists right now, keep following the last known
				-- good path instead of falling back to a straight line through walls.
				if newWaypoints then
					waypoints = newWaypoints
					waypointIndex = 1
				end
			else
				waypoints = {}
			end
		end

		local waypoint = waypoints[waypointIndex]
		if waypoint and (rootPart.Position - waypoint.Position).Magnitude <= WAYPOINT_ARRIVAL_DISTANCE then
			waypointIndex = math.min(waypointIndex + 1, #waypoints)
			waypoint = waypoints[waypointIndex]
		end

		if waypoint and waypoint.Position ~= activeMoveTarget then
			activeMoveTarget = waypoint.Position
			humanoid:MoveTo(waypoint.Position)
		elseif not waypoint and activeMoveTarget then
			-- Nothing to chase or return to -- stop cleanly instead of leaving a
			-- stale MoveTo command running.
			activeMoveTarget = nil
			humanoid:MoveTo(rootPart.Position)
		end

		local interval = if waypoint then ADVANCE_CHECK_INTERVAL else RETARGET_INTERVAL
		task.wait(interval)
		timeSinceReplan += interval
	end
end

-- Simple server-authoritative attack-back: every ATTACK_INTERVAL, hit any player
-- within range. Independent of pursuitLoop -- it only cares about current
-- distance, not who (if anyone) moved the enemy there. Damage is applied here,
-- server-side, to the player's own Humanoid -- the client has no say in it.
local function attackLoop(model: Model, rootPart: BasePart, humanoid: Humanoid)
	while model.Parent do
		task.wait(ATTACK_INTERVAL)

		if humanoid.Health <= 0 then
			continue
		end

		for _, player in Players:GetPlayers() do
			local character = player.Character
			local playerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
			local playerRoot = character and character:FindFirstChild("HumanoidRootPart")

			if playerHumanoid and playerRoot and playerHumanoid.Health > 0 then
				local distance = (playerRoot.Position - rootPart.Position).Magnitude
				if distance <= ATTACK_RANGE then
					playerHumanoid:TakeDamage(ATTACK_DAMAGE)
				end
			end
		end
	end
end

function DummyEnemy.Spawn(parent: Instance, spawnCFrame: CFrame, options: SpawnOptions?): EnemyHandle
	local scale = (options and options.Scale) or 1
	local maxHealth = (options and options.Health) or MAX_HEALTH
	local mutationReward = (options and options.MutationReward) or KILL_MUTATION_REWARD
	local model = buildModel(spawnCFrame, scale, maxHealth)
	local rootPart = model.HumanoidRootPart :: BasePart
	local humanoid = model.Humanoid :: Humanoid

	buildHealthBar(rootPart, humanoid, scale)

	local lastAttacker: Player? = nil
	local despawned = false

	EnemyRegistry.Register(model, {
		TakeDamage = function(amount: number, attacker: Player?)
			if humanoid.Health <= 0 then
				return
			end
			lastAttacker = attacker
			humanoid:TakeDamage(amount)
		end,
	})

	humanoid.Died:Connect(function()
		if despawned then
			return
		end
		EnemyRegistry.Unregister(model)

		if lastAttacker then
			MutationService.GrantMutation(lastAttacker, mutationReward)
		end

		model:Destroy()

		if options and options.OnDeath then
			options.OnDeath(lastAttacker)
		else
			task.delay(DEFAULT_RESPAWN_DELAY, function()
				DummyEnemy.Spawn(parent, spawnCFrame, options)
			end)
		end
	end)

	model.Parent = parent

	-- Both loops must be spawned after model.Parent is set -- task.spawn runs
	-- synchronously up to its first yield, and both loops' first line checks
	-- model.Parent. Spawning before parenting meant that check saw nil
	-- immediately and the loop exited on the spot, every time, silently (this
	-- bit attackLoop before; same fix applies to pursuitLoop).
	task.spawn(pursuitLoop, model, rootPart, humanoid, scale, spawnCFrame.Position)
	task.spawn(attackLoop, model, rootPart, humanoid)

	return {
		Despawn = function()
			if despawned or humanoid.Health <= 0 then
				return
			end
			despawned = true
			EnemyRegistry.Unregister(model)
			model:Destroy() -- both loops exit on their next model.Parent check
		end,
	}
end

return DummyEnemy
