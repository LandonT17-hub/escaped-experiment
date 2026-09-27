-- Server-authoritative stage objective logic: enemy spawns, clear tracking,
-- gate opening, reward pad payouts, checkpoints, and the "which stage am I
-- in" zone banner. Builds no geometry -- the stage's parts are hand-built in
-- Studio and handed in as StageParts. Also drives the boss arena (a one-enemy
-- stage with no Gate whose ClaimPad ends the run).
--
-- A stage is only live while a player is inside its Zone part: enemies spawn
-- when the first player enters. Once the zone has been empty for
-- RESET_GRACE seconds the stage fully resets -- survivors despawn, kills
-- are forgotten, the Gate closes -- so the next player through fights it
-- fresh instead of finding it permanently cleared.
--
-- Reward pads only pay once the stage is cleared, once per player per run
-- (see RunProgress).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MutationService = require(ServerScriptService.Server.Mutation.MutationService)
local DummyEnemy = require(ServerScriptService.Server.Enemies.DummyEnemy)
local GamepassData = require(ServerScriptService.Server.Mutation.GamepassData)
local GamepassService = require(ServerScriptService.Server.Mutation.GamepassService)
local RunProgress = require(script.Parent.RunProgress)
local EnemyDebug = require(ServerScriptService.Server.Enemies.EnemyDebug)

export type StageConfig = {
	Name: string,
	EnemyCount: number,
	EnemyHealth: number,
	EnemyScale: number,
	MutationPerKill: number,
	RecommendedDamage: number, -- tuning guideline only, surfaced on the gate label if it has one
}

export type RewardPad = {
	Part: BasePart,
	Wins: number,
	RequiresPremium: boolean, -- requires the "Premium Wins" gamepass (not Roblox Premium)
	RespawnToLobby: boolean, -- paying out also ends the player's run
}

-- The hand-built parts one stage's logic attaches to.
export type StageParts = {
	Model: Instance, -- enemies parent here
	-- Invisible box covering the stage. Drives enemy activation, reset and the
	-- objective banner, so stages' zones must not overlap.
	Zone: BasePart,
	Gate: BasePart?, -- solid until cleared; nil for the boss arena
	EnemySpawns: { BasePart }, -- cycled if EnemyCount exceeds the list
	RewardPads: { RewardPad },
	StartCFrame: CFrame?, -- respawn point for players who die in this stage
	Floor: BasePart?, -- enemies are stood on this, directly below their marker
	-- Position in the world's run (stages 1..N, boss N + 1), published to the
	-- HUD via RunProgress. Set by WorldWiring.
	Index: number?,
}

export type BuiltStage = {
	Model: Instance,
	Config: StageConfig,
	IsCleared: () -> boolean,
}

local ZONE_POLL_INTERVAL = 0.5
-- How long a zone must stay empty before the stage resets -- rides out a
-- player briefly stepping back over the boundary.
local RESET_GRACE = 5
local GATE_OPEN_TRANSPARENCY = 0.85
-- Touched fires constantly while standing on a pad; don't re-prompt every frame.
local PURCHASE_PROMPT_COOLDOWN = 5

local lastPurchasePromptAt: { [Player]: number } = {}

Players.PlayerRemoving:Connect(function(player: Player)
	lastPurchasePromptAt[player] = nil
end)

local StageObjective = {}

-- Returns the part's existing "Label" BillboardGui text, if it has one --
-- never creates UI (visuals are hand-authored).
local function findLabelText(onPart: BasePart): TextLabel?
	local billboard = onPart:FindFirstChild("Label")
	local textLabel = billboard and billboard:FindFirstChildWhichIsA("TextLabel", true)
	return textLabel
end

-- Horizontal footprint only: stages are laid out side by side, never
-- stacked, so a Zone part that's too thin or sits at the wrong height still
-- detects players standing in the stage.
local function isInsideZone(zone: BasePart, position: Vector3): boolean
	local offset = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(offset.X) <= half.X and math.abs(offset.Z) <= half.Z
end

-- Height of the floor surface directly below the marker, so an enemy never
-- spawns inside or under the floor however the marker was placed. Falls back
-- to the marker's bottom face if the ray misses.
local function groundYBelow(marker: BasePart, floor: BasePart?): number
	if floor then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { floor }
		local hit = workspace:Raycast(marker.Position + Vector3.new(0, 50, 0), Vector3.new(0, -200, 0), params)
		if hit then
			return hit.Position.Y
		end
	end
	return marker.Position.Y - marker.Size.Y / 2
end

-- Stands the enemy rig on the ground below its marker: the rig's torso
-- extends 1.5 * scale below its root.
local function enemySpawnCFrame(marker: BasePart, floor: BasePart?, scale: number): CFrame
	local groundY = groundYBelow(marker, floor)
	return CFrame.new(marker.Position.X, groundY + 1.5 * scale + 0.2, marker.Position.Z)
end

-- Whether the player may claim a RequiresPremium pad; prompts the "Premium
-- Wins" purchase (rate-limited) when they don't own it yet.
local function hasPremiumWins(player: Player): boolean
	local passId = GamepassData.PremiumWinsPassId
	if passId <= 0 then
		return false -- not created yet: nobody owns it, nothing to prompt
	end

	if GamepassService.OwnsGamePass(player, passId) then
		return true
	end

	local now = os.clock()
	local last = lastPurchasePromptAt[player]
	if not last or now - last >= PURCHASE_PROMPT_COOLDOWN then
		lastPurchasePromptAt[player] = now
		GamepassService.PromptPurchase(player, passId)
	end
	return false
end

local function playerFromHit(hit: BasePart): Player?
	local character = hit.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

function StageObjective.Wire(parts: StageParts, config: StageConfig): BuiltStage
	local stage = parts.Model
	local gate = parts.Gate
	local gateClosedTransparency = if gate then gate.Transparency else 0

	local remaining = config.EnemyCount
	local cleared = false

	local inZoneUpdated = Remotes.GetRemoteEvent("StageInZone")
	local progressUpdated = Remotes.GetRemoteEvent("StageProgress")

	local wasInZone: { [Player]: boolean } = {}

	-- Only players in this stage's zone -- the banner is showing some other
	-- stage's progress for everyone else.
	local function broadcastProgress()
		for player in wasInZone do
			progressUpdated:FireClient(player, config.EnemyCount - remaining, config.EnemyCount, cleared)
		end
	end

	local function setGateLocked(locked: boolean)
		if not gate then
			return
		end
		gate.CanCollide = locked
		gate.Transparency = if locked then gateClosedTransparency else GATE_OPEN_TRANSPARENCY
		gate:SetAttribute("Open", not locked)

		local gateText = findLabelText(gate)
		if gateText then
			gateText.Text = if locked
				then string.format(
					"%s\nLOCKED -- Defeat all enemies\nRecommended Damage: %d",
					config.Name,
					config.RecommendedDamage
				)
				else string.format("%s\nOPEN", config.Name)
		end
	end

	-- Visual state is left to the map: pads just get an Active attribute the
	-- hand-built visuals can react to.
	local function setPadsActive(active: boolean)
		for _, pad in parts.RewardPads do
			pad.Part:SetAttribute("Active", active)
		end
	end

	local function onEnemyDefeated()
		remaining -= 1
		if remaining <= 0 and not cleared then
			cleared = true
			-- Everyone in the stage when it clears has cleared it.
			if parts.Index then
				for player in wasInZone do
					RunProgress.MarkStageCleared(player, parts.Index)
				end
			end
			setPadsActive(true)
			setGateLocked(false)
		end
		broadcastProgress()
	end

	setGateLocked(true)
	setPadsActive(false)

	local spawns = parts.EnemySpawns
	if #spawns == 0 and config.EnemyCount > 0 then
		warn(`StageObjective: {stage:GetFullName()} has no EnemySpawns; its enemies won't spawn`)
	end

	-- One slot per enemy: a living handle, or Dead = true once it's been killed.
	local slots: { { Handle: DummyEnemy.EnemyHandle?, Dead: boolean } } = {}
	for i = 1, config.EnemyCount do
		slots[i] = { Handle = nil, Dead = false }
	end

	local function spawnEnemies()
		if #spawns == 0 then
			return
		end
		for i, slot in slots do
			if slot.Dead or slot.Handle then
				continue
			end
			local marker = spawns[((i - 1) % #spawns) + 1]
			slot.Handle = DummyEnemy.Spawn(stage, enemySpawnCFrame(marker, parts.Floor, config.EnemyScale), {
				Scale = config.EnemyScale,
				Health = config.EnemyHealth,
				MutationReward = config.MutationPerKill,
				-- Enemies only chase players standing in this stage.
				CanTarget = function(position: Vector3)
					return isInsideZone(parts.Zone, position)
				end,
				OnDeath = function()
					slot.Dead = true
					slot.Handle = nil
					onEnemyDefeated()
				end,
			})
		end
	end

	local function resetStage()
		for _, slot in slots do
			if slot.Handle then
				slot.Handle.Despawn()
			end
			slot.Handle = nil
			slot.Dead = false
		end
		remaining = config.EnemyCount
		cleared = false
		setPadsActive(false)
		setGateLocked(true)
	end

	for _, pad in parts.RewardPads do
		local claimKey = pad.Part:GetFullName()

		pad.Part.Touched:Connect(function(hit: BasePart)
			if not cleared then
				return
			end

			local player = playerFromHit(hit)
			if not player or RunProgress.HasClaimed(player, claimKey) then
				return
			end

			if pad.RequiresPremium and not hasPremiumWins(player) then
				return
			end

			RunProgress.MarkClaimed(player, claimKey)
			MutationService.GrantWins(player, pad.Wins)
			if parts.Index then
				RunProgress.MarkStageCleared(player, parts.Index)
			end

			if pad.RespawnToLobby then
				RunProgress.CompleteRun(player)
			end
		end)
	end

	-- Server-authoritative "who is in this stage's zone" check, driving enemy
	-- activation, reset, checkpoints and the objective banner.
	local active = false
	local emptyFor = 0

	local function pollZone()
		while stage.Parent and parts.Zone.Parent do
			task.wait(ZONE_POLL_INTERVAL)

			local anyInZone = false
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local rootPart = character and character:FindFirstChild("HumanoidRootPart")
				local inZone = rootPart ~= nil and isInsideZone(parts.Zone, (rootPart :: BasePart).Position)
				anyInZone = anyInZone or inZone

				if inZone ~= (wasInZone[player] == true) then
					wasInZone[player] = if inZone then true else nil
					inZoneUpdated:FireClient(player, inZone)
					if inZone then
						progressUpdated:FireClient(player, config.EnemyCount - remaining, config.EnemyCount, cleared)
						if parts.StartCFrame then
							RunProgress.SetCheckpoint(player, parts.StartCFrame)
						end
					end
					if parts.Index then
						if inZone then
							RunProgress.SetCurrentStage(player, parts.Index)
						else
							RunProgress.LeaveStage(player, parts.Index)
						end
					end
				end
			end

			if anyInZone then
				emptyFor = 0
				if not active then
					active = true
					EnemyDebug.Log(`{stage.Name} activated: player in Zone, spawning {config.EnemyCount} enemies at {#spawns} markers`)
					spawnEnemies()
				end
			elseif active then
				emptyFor += ZONE_POLL_INTERVAL
				if emptyFor >= RESET_GRACE then
					active = false
					EnemyDebug.Log(`{stage.Name} reset: Zone empty for {RESET_GRACE}s`)
					resetStage()
				end
			end
		end
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		wasInZone[player] = nil
	end)

	task.spawn(pollZone)

	return {
		Model = stage,
		Config = config,
		IsCleared = function()
			return cleared
		end,
	}
end

return StageObjective
