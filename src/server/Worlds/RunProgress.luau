-- Per-player progress through one run of a world (lobby -> stages -> boss
-- ClaimPad -> back to lobby). Session-only, server-owned:
--   * Checkpoint: the start of the last stage zone the player entered. They
--     respawn there on death instead of back at LobbySpawn.
--   * Claims: which reward pads they've already been paid by this run, so each
--     pays once per player per run. Finishing the run (a RespawnToLobby pad)
--     clears both, so the next run pays out again.
--   * HUD progress, published as Player attributes the client HUD reads:
--     "CurrentStage" (stage the player is standing in, 0 = none; the boss
--     arena is stage count + 1) and "StagesCleared" (highest stage cleared
--     this run). Both reset when the run completes.

local Players = game:GetService("Players")

local RunProgress = {}

local checkpoints: { [Player]: CFrame } = {}
local claims: { [Player]: { [string]: boolean } } = {}

function RunProgress.SetCheckpoint(player: Player, cframe: CFrame)
	checkpoints[player] = cframe
end

function RunProgress.HasClaimed(player: Player, key: string): boolean
	local playerClaims = claims[player]
	return playerClaims ~= nil and playerClaims[key] == true
end

function RunProgress.SetCurrentStage(player: Player, stageIndex: number)
	player:SetAttribute("CurrentStage", stageIndex)
end

-- Only clears it if the player is still marked in this stage -- when walking
-- from stage N into N+1, N+1's zone check may run first.
function RunProgress.LeaveStage(player: Player, stageIndex: number)
	if player:GetAttribute("CurrentStage") == stageIndex then
		player:SetAttribute("CurrentStage", 0)
	end
end

function RunProgress.MarkStageCleared(player: Player, stageIndex: number)
	local cleared = player:GetAttribute("StagesCleared")
	if typeof(cleared) ~= "number" or stageIndex > cleared then
		player:SetAttribute("StagesCleared", stageIndex)
	end
end

function RunProgress.MarkClaimed(player: Player, key: string)
	local playerClaims = claims[player]
	if not playerClaims then
		playerClaims = {}
		claims[player] = playerClaims
	end
	playerClaims[key] = true
end

-- Ends the player's run: clears checkpoint + claims and respawns them, which
-- lands them on the lobby's SpawnLocation.
function RunProgress.CompleteRun(player: Player)
	checkpoints[player] = nil
	claims[player] = nil
	player:SetAttribute("CurrentStage", 0)
	player:SetAttribute("StagesCleared", 0)
	-- Deferred: callers are mid-Touched on the old character.
	task.defer(function()
		if player.Parent then
			player:LoadCharacter()
		end
	end)
end

local function onCharacterAdded(player: Player, character: Model)
	local checkpoint = checkpoints[player]
	if checkpoint and character:WaitForChild("HumanoidRootPart", 5) then
		character:PivotTo(checkpoint)
	end
end

local function onPlayerAdded(player: Player)
	player:SetAttribute("CurrentStage", 0)
	player:SetAttribute("StagesCleared", 0)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player: Player)
	checkpoints[player] = nil
	claims[player] = nil
end)

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

return RunProgress
