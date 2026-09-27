local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ServerScriptService = game:GetService("ServerScriptService")

local EnemyRegistry = require(script.Parent.EnemyRegistry)
local EnemyDebug = require(script.Parent.EnemyDebug)
local MutationService = require(ServerScriptService.Server.Mutation.MutationService)

local MAX_HEALTH = 100
local KILL_MUTATION_REWARD = 25
local DEFAULT_RESPAWN_DELAY = 5
local TINT_COLOR = Color3.fromRGB(200, 90, 90) -- placeholder dummy-target red

-- Placeholder combat tuning -- no design doc numbers exist; adjust freely.
local ATTACK_INTERVAL = 1.5 -- seconds between attacks
local ATTACK_RANGE = 6 -- studs (root to root); a little past STOP_RANGE so a shuffling player still gets hit
local ATTACK_DAMAGE = 5

-- Movement tuning. One AI tick every THINK_INTERVAL; MoveTo is only
-- re-issued when the destination actually moved, never every frame.
local ENEMY_WALK_SPEED = 10 -- players are 16, so they can outrun enemies
local THINK_INTERVAL = 0.3
local STOP_RANGE = 5 -- stop and fight once this close to the target
local DETECTION_RANGE = 40 -- only used when the enemy has no Zone (e.g. a standalone test dummy)
local LEASH_RANGE = 45 -- past this from spawn: drop the target and walk home
local RETURN_HOME_DISTANCE = 2 -- close enough to spawn to stop and idle
local MOVE_RETARGET_DISTANCE = 1 -- re-issue MoveTo once the destination drifts this far
local MOVE_REFRESH_TIME = 6 -- re-issue anyway before Humanoid's 8s MoveTo timeout
local REPATH_INTERVAL = 1 -- min seconds between PathfindingService computes
local REPATH_DISTANCE = 4 -- ...unless the destination moved this far
local WAYPOINT_ARRIVAL_DISTANCE = 3
local FACE_ANGLE_THRESHOLD = math.rad(15)

export type SpawnOptions = {
	-- Called (with the killer, if any) after death/registry-cleanup/Mutation grant,
	-- instead of the default self-respawn loop. Stages use this: their enemies
	-- should stay dead and report the kill upward.
	OnDeath: ((killer: Player?) -> ())?,
	-- Uniform size multiplier. At Scale 1 the rig is ~4.4 studs tall (roughly
	-- player-sized); stages needing taller enemies (per spec) pass a bigger value.
	Scale: number?,
	-- Per-spawn overrides so stage configs can escalate difficulty/reward without
	-- touching this module. Both default to the flat placeholder constants above.
	Health: number?,
	MutationReward: number?,
	-- Which player positions this enemy may target (its stage's Zone). Without
	-- it, any player within DETECTION_RANGE is fair game.
	CanTarget: ((position: Vector3) -> boolean)?,
}

-- Returned by Spawn so a caller (StageObjective) can remove a living enemy
-- when its stage goes idle. Despawning is not a death: no Mutation is
-- granted, OnDeath doesn't fire, and the default respawn loop doesn't run.
export type EnemyHandle = {
	Despawn: () -> (),
}

local DummyEnemy = {}

local FLAT = Vector3.new(1, 0, 1)

local function flatDistance(a: Vector3, b: Vector3): number
	return ((a - b) * FLAT).Magnitude
end

-- Every body part is welded to the HumanoidRootPart, so the rig is one rigid
-- assembly the Humanoid drives. The Humanoid uses the R15 model: it holds the
-- root HipHeight above the ground itself instead of dragging a legless torso
-- along the floor, and the torso's bottom sits just clear of the ground.
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
	torso.Anchored = false
	torso.CFrame = rootPart.CFrame
	torso.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.4, 1.4, 1.4) * scale
	head.Color = TINT_COLOR
	head.Material = Enum.Material.SmoothPlastic
	head.CanCollide = false
	head.Anchored = false
	head.CFrame = rootPart.CFrame * CFrame.new(0, 2.2 * scale, 0)
	head.Parent = model

	for _, part in { torso, head } do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = rootPart
		weld.Part1 = part
		weld.Parent = rootPart
	end

	-- Keeps the root's up axis pointing world-up (yaw stays free for turning)
	-- so the enemy can't tip over.
	local uprightAttachment = Instance.new("Attachment")
	uprightAttachment.Name = "UprightAttachment"
	uprightAttachment.Axis = Vector3.yAxis
	uprightAttachment.SecondaryAxis = Vector3.xAxis
	uprightAttachment.Parent = rootPart

	local upright = Instance.new("AlignOrientation")
	upright.Name = "Upright"
	upright.Mode = Enum.OrientationAlignmentMode.OneAttachment
	upright.AlignType = Enum.AlignType.PrimaryAxisParallel
	upright.PrimaryAxis = Vector3.yAxis
	upright.Attachment0 = uprightAttachment
	upright.MaxTorque = math.huge
	upright.Responsiveness = 200
	upright.Parent = rootPart

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	-- Ground to the root's bottom face: the torso reaches 1.5 * scale below
	-- the root's center and the root is 1 * scale half-tall; +0.1 keeps the
	-- torso from scraping the floor.
	humanoid.HipHeight = 0.5 * scale + 0.1
	humanoid.RequiresNeck = false -- custom rig has no Neck joint
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- health bar only, no name
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = ENEMY_WALK_SPEED
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
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

local function livingRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 then
		return root :: BasePart
	end
	return nil
end

-- Nearest living player this enemy is allowed to chase: inside its Zone (or
-- within DETECTION_RANGE if it has none) and within leash reach of its spawn --
-- a player it could never reach without being leashed isn't worth chasing,
-- which is what stops the chase-leash-return-chase loop.
local function pickTarget(position: Vector3, spawnPosition: Vector3, canTarget: ((Vector3) -> boolean)?): Player?
	local best: Player? = nil
	local bestDistance = math.huge

	for _, player in Players:GetPlayers() do
		local root = livingRoot(player)
		if not root then
			continue
		end

		local targetPosition = root.Position
		local eligible = if canTarget
			then canTarget(targetPosition)
			else flatDistance(targetPosition, position) <= DETECTION_RANGE
		if not eligible or flatDistance(targetPosition, spawnPosition) > LEASH_RANGE + STOP_RANGE then
			continue
		end

		local distance = flatDistance(targetPosition, position)
		if distance < bestDistance then
			best, bestDistance = player, distance
		end
	end

	return best
end

-- The enemy's AI: one tick every THINK_INTERVAL. Straight-line MoveTo when the
-- way is clear; PathfindingService only when something blocks it.
local function aiLoop(
	model: Model,
	rootPart: BasePart,
	humanoid: Humanoid,
	scale: number,
	spawnPosition: Vector3,
	canTarget: ((Vector3) -> boolean)?
)
	local path = PathfindingService:CreatePath({
		AgentRadius = 1.1 * scale,
		AgentHeight = 4.4 * scale,
		AgentCanJump = false,
	})

	-- Ignores the enemy itself, players, and anything non-collidable (Zone
	-- volumes, spawn markers) when checking for a clear straight line.
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.RespectCanCollide = true

	local lastMoveTarget: Vector3? = nil
	local lastMoveAt = 0
	local waypoints: { PathWaypoint } = {}
	local waypointIndex = 1
	local pathDestination: Vector3? = nil
	local lastPathAt = -math.huge
	local returningHome = false
	local mode = "idle"
	local timeSinceDebugLog = math.huge

	local function moveTo(destination: Vector3)
		local now = os.clock()
		if
			lastMoveTarget
			and (lastMoveTarget - destination).Magnitude < MOVE_RETARGET_DISTANCE
			and now - lastMoveAt < MOVE_REFRESH_TIME
		then
			return
		end
		lastMoveTarget, lastMoveAt = destination, now
		humanoid:MoveTo(destination)
	end

	local function stop()
		waypoints, pathDestination = {}, nil
		if lastMoveTarget then
			lastMoveTarget = nil
			humanoid:MoveTo(rootPart.Position)
		end
	end

	local function isClearLine(destination: Vector3): boolean
		local exclude: { Instance } = { model }
		for _, player in Players:GetPlayers() do
			if player.Character then
				table.insert(exclude, player.Character)
			end
		end
		rayParams.FilterDescendantsInstances = exclude

		-- Two rays: at root height and near the feet, so low walls count too.
		for _, heightOffset in { 0, -1.2 * scale } do
			local from = rootPart.Position + Vector3.new(0, heightOffset, 0)
			local to = Vector3.new(destination.X, from.Y, destination.Z)
			if workspace:Raycast(from, to - from, rayParams) then
				return false
			end
		end
		return true
	end

	local function moveToward(destination: Vector3)
		if isClearLine(destination) then
			mode = "direct"
			waypoints, pathDestination = {}, nil
			moveTo(destination)
			return
		end

		mode = "path"
		local now = os.clock()
		local needsPath = not pathDestination
			or (pathDestination - destination).Magnitude > REPATH_DISTANCE
			or #waypoints == 0
		if needsPath and now - lastPathAt >= REPATH_INTERVAL then
			lastPathAt = now
			pathDestination = destination
			local ok, err = pcall(function()
				path:ComputeAsync(rootPart.Position, destination)
			end)
			if ok and path.Status == Enum.PathStatus.Success then
				waypoints, waypointIndex = path:GetWaypoints(), 2 -- waypoint 1 is where we stand
			else
				waypoints = {}
				EnemyDebug.Log(
					`{EnemyDebug.Name(model)} path FAILED from {EnemyDebug.Vec(rootPart.Position)} to {EnemyDebug.Vec(destination)}: `
						.. (if ok then `status {path.Status.Name}` else `error {err}`)
				)
			end
		end

		local waypoint = waypoints[waypointIndex]
		while waypoint and flatDistance(rootPart.Position, waypoint.Position) <= WAYPOINT_ARRIVAL_DISTANCE do
			waypointIndex += 1
			waypoint = waypoints[waypointIndex]
		end

		if waypoint then
			moveTo(waypoint.Position)
		else
			-- No route (yet): stand still rather than walk into the wall.
			stop()
		end
	end

	local function face(targetPosition: Vector3)
		local look = (targetPosition - rootPart.Position) * FLAT
		if look.Magnitude < 0.01 then
			return
		end
		local current = rootPart.CFrame.LookVector * FLAT
		local angle = math.acos(math.clamp(current.Unit:Dot(look.Unit), -1, 1))
		if angle > FACE_ANGLE_THRESHOLD then
			rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + look)
		end
	end

	while model.Parent and humanoid.Health > 0 do
		local position = rootPart.Position
		local fromSpawn = flatDistance(position, spawnPosition)
		local target: Player? = nil

		if fromSpawn > LEASH_RANGE then
			returningHome = true
		end

		if returningHome then
			if fromSpawn <= RETURN_HOME_DISTANCE then
				returningHome = false
				mode = "idle"
				stop()
			else
				moveToward(spawnPosition)
				mode = "leash:" .. mode
			end
		else
			target = pickTarget(position, spawnPosition, canTarget)
			local targetRoot = target and livingRoot(target)
			if targetRoot then
				if flatDistance(targetRoot.Position, position) <= STOP_RANGE then
					mode = "melee"
					stop()
					face(targetRoot.Position)
				else
					moveToward(targetRoot.Position)
				end
			elseif fromSpawn > RETURN_HOME_DISTANCE then
				moveToward(spawnPosition)
				mode = "home:" .. mode
			else
				mode = "idle"
				stop()
			end
		end

		if EnemyDebug.Enabled and timeSinceDebugLog >= 2 then
			timeSinceDebugLog = 0
			local targetRoot = target and livingRoot(target)
			local targetText = if target and targetRoot
				then `{target.Name} dist={string.format("%.1f", flatDistance(targetRoot.Position, position))}`
				else "none"
			local owner = EnemyDebug.Owner(rootPart)
			local up = rootPart.CFrame.UpVector.Y
			EnemyDebug.Log(
				`{EnemyDebug.Name(model)} ai: mode={mode} target={targetText} at {EnemyDebug.Vec(position)}`
					.. ` fromSpawn={string.format("%.1f", fromSpawn)} speed={string.format("%.1f", (rootPart.AssemblyLinearVelocity * FLAT).Magnitude)}`
					.. ` upY={string.format("%.2f", up)} state={humanoid:GetState().Name} owner={owner}`
					.. (if owner ~= "server" then "  <-- NOT SERVER-OWNED" else "")
					.. (if up < 0.9 then "  <-- TILTED" else "")
			)
		end

		task.wait(THINK_INTERVAL)
		timeSinceDebugLog += THINK_INTERVAL
	end
end

-- Server-authoritative attack-back: every ATTACK_INTERVAL, hit any living
-- player within ATTACK_RANGE. Damage is applied here, server-side, to the
-- player's own Humanoid -- the client has no say in it.
local function attackLoop(model: Model, rootPart: BasePart, humanoid: Humanoid)
	while model.Parent do
		task.wait(ATTACK_INTERVAL)

		if humanoid.Health <= 0 then
			return
		end

		for _, player in Players:GetPlayers() do
			local playerRoot = livingRoot(player)
			if not playerRoot then
				continue
			end

			local playerHumanoid = (playerRoot.Parent :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
			local distance = (playerRoot.Position - rootPart.Position).Magnitude
			if distance <= ATTACK_RANGE then
				local before = playerHumanoid.Health
				playerHumanoid:TakeDamage(ATTACK_DAMAGE)
				EnemyDebug.Log(
					`{EnemyDebug.Name(model)} attack: {player.Name} dist={string.format("%.1f", distance)} HIT, hp {before} -> {playerHumanoid.Health}`
				)
			end
		end
	end
end

local nextDebugId = 0

function DummyEnemy.Spawn(parent: Instance, spawnCFrame: CFrame, options: SpawnOptions?): EnemyHandle
	local scale = (options and options.Scale) or 1
	local maxHealth = (options and options.Health) or MAX_HEALTH
	local mutationReward = (options and options.MutationReward) or KILL_MUTATION_REWARD
	local canTarget = options and options.CanTarget
	local model = buildModel(spawnCFrame, scale, maxHealth)
	local rootPart = model.HumanoidRootPart :: BasePart
	local humanoid = model.Humanoid :: Humanoid

	nextDebugId += 1
	model:SetAttribute("DebugId", nextDebugId)

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

	-- Server owns the enemy's physics, so a nearby player's client can't take
	-- over its movement (without this, damage and movement broke). Needs to be
	-- in the workspace.
	local ownerOk, ownerErr = pcall(rootPart.SetNetworkOwner, rootPart, nil)
	if not ownerOk then
		EnemyDebug.Log(`{EnemyDebug.Name(model)} SetNetworkOwner(nil) FAILED: {ownerErr}`)
	end

	EnemyDebug.Log(
		`{EnemyDebug.Name(model)} spawned at {EnemyDebug.Vec(rootPart.Position)}, scale={scale}, `
			.. `hp={humanoid.Health}/{humanoid.MaxHealth}, registered={EnemyRegistry.GetAll()[model] ~= nil}, `
			.. `zoneBound={canTarget ~= nil}, owner={EnemyDebug.Owner(rootPart)}`
	)

	-- Both loops must be spawned after model.Parent is set -- they exit as
	-- soon as they see model.Parent == nil.
	task.spawn(aiLoop, model, rootPart, humanoid, scale, spawnCFrame.Position, canTarget)
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
