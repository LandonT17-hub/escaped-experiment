-- Server-authoritative stage objective logic: enemy spawns, clear tracking,
-- gate opening, Win pad payout, and the "which stage am I in" zone banner.
-- Builds no geometry -- the stage's floor/walls/gate/Win pad are hand-built
-- in Studio and handed in as StageParts. Nothing here is world-specific.
--
-- Each non-final stage ends in a Gate that is solid (locked) until that
-- stage's enemies are all defeated, at which point it opens and the Win pad
-- activates and pays Wins once per player. The final stage has no Gate --
-- its world's walk-through gateway (WorldGateway) gates on IsCleared instead.
--
-- Enemies only exist while a player is inside the stage's Zone part: they
-- spawn when the first player enters, and living ones are despawned once the
-- zone has been empty for DESPAWN_GRACE seconds. Kills persist across that --
-- a defeated enemy never comes back -- but a despawned survivor returns at
-- full health.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MutationService = require(ServerScriptService.Server.Mutation.MutationService)
local DummyEnemy = require(ServerScriptService.Server.Enemies.DummyEnemy)

export type StageConfig = {
	Name: string,
	EnemyCount: number,
	EnemyHealth: number,
	EnemyScale: number,
	MutationPerKill: number,
	WinsReward: number, -- paid once per player when they reach the cleared Win pad
	RecommendedDamage: number, -- tuning guideline only, surfaced on the gate sign
}

-- The hand-built parts one stage's logic attaches to.
export type StageParts = {
	Model: Instance, -- container; enemies parent here, zone polling stops when it's removed
	WinPad: BasePart,
	Gate: BasePart?, -- nil on the final stage
	EnemySpawns: { CFrame }, -- cycled if EnemyCount exceeds the list
	-- Box covering the stage's playable area. Drives enemy activation and the
	-- objective banner, so stages' zones must not overlap.
	Zone: BasePart,
}

export type BuiltStage = {
	Model: Instance,
	Config: StageConfig,
	IsCleared: () -> boolean,
}

local GATE_OPEN_COLOR = Color3.fromRGB(90, 200, 110)
local WIN_PAD_ACTIVE_COLOR = Color3.fromRGB(255, 210, 80)

local ZONE_POLL_INTERVAL = 0.5
-- How long a zone must stay empty before its enemies despawn -- rides out a
-- player briefly stepping back over the boundary or respawning.
local DESPAWN_GRACE = 5

local StageObjective = {}

-- Returns the part's existing "Label" BillboardGui text, if it has one --
-- never creates UI (visuals are hand-authored).
local function findLabelText(onPart: BasePart): TextLabel?
	local billboard = onPart:FindFirstChild("Label")
	local textLabel = billboard and billboard:FindFirstChild("TextLabel")
	if textLabel and textLabel:IsA("TextLabel") then
		return textLabel
	end
	return nil
end

local function isInsideZone(zone: BasePart, position: Vector3): boolean
	local offset = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z
end

function StageObjective.Wire(parts: StageParts, config: StageConfig): BuiltStage
	local stage = parts.Model
	local winPad = parts.WinPad
	local gate = parts.Gate

	local remaining = config.EnemyCount
	local cleared = false

	if gate then
		gate.CanCollide = true
		local gateText = findLabelText(gate)
		if gateText then
			gateText.Text = string.format(
				"%s\nLOCKED -- Defeat all enemies (0/%d)\nRecommended Damage: %d",
				config.Name,
				config.EnemyCount,
				config.RecommendedDamage
			)
		end
	end

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

	local function onEnemyDefeated()
		remaining -= 1
		if remaining <= 0 and not cleared then
			cleared = true
			winPad.Color = WIN_PAD_ACTIVE_COLOR
			winPad.Material = Enum.Material.Neon

			if gate then
				gate.CanCollide = false
				gate.Transparency = 0.85
				gate.Color = GATE_OPEN_COLOR
				local gateText = findLabelText(gate)
				if gateText then
					gateText.Text = string.format("%s\nOPEN", config.Name)
				end
			end
		end
		broadcastProgress()
	end

	local spawns = parts.EnemySpawns
	if #spawns == 0 and config.EnemyCount > 0 then
		warn(`StageObjective: {config.Name} has no EnemySpawns; its enemies won't spawn`)
	end

	-- One slot per enemy: a living handle, or dead = true once it's been killed.
	local slots: { { Handle: DummyEnemy.EnemyHandle?, Dead: boolean } } = {}
	for i = 1, config.EnemyCount do
		slots[i] = { Handle = nil, Dead = false }
	end

	local function activate()
		if #spawns == 0 then
			return
		end
		for i, slot in slots do
			if slot.Dead or slot.Handle then
				continue
			end
			slot.Handle = DummyEnemy.Spawn(stage, spawns[((i - 1) % #spawns) + 1], {
				Scale = config.EnemyScale,
				Health = config.EnemyHealth,
				MutationReward = config.MutationPerKill,
				OnDeath = function()
					slot.Dead = true
					slot.Handle = nil
					onEnemyDefeated()
				end,
			})
		end
	end

	local function deactivate()
		for _, slot in slots do
			if slot.Handle then
				slot.Handle.Despawn()
				slot.Handle = nil
			end
		end
	end

	local claimedBy: { [Player]: boolean } = {}
	winPad.Touched:Connect(function(hit: BasePart)
		if not cleared then
			return
		end

		local character = hit.Parent
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		local player = Players:GetPlayerFromCharacter(character)
		if not player or claimedBy[player] then
			return
		end

		claimedBy[player] = true
		MutationService.GrantWins(player, config.WinsReward)
	end)

	-- Server-authoritative "who is in this stage's zone" check, driving both
	-- enemy activation and the shared objective banner.
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
					end
				end
			end

			if anyInZone then
				emptyFor = 0
				if not active and not cleared then
					active = true
					activate()
				end
			elseif active then
				emptyFor += ZONE_POLL_INTERVAL
				if emptyFor >= DESPAWN_GRACE then
					active = false
					deactivate()
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
