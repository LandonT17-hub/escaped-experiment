-- Per-player progress through one run of a world (lobby -> stages -> boss
-- ClaimPad -> back to lobby). Session-only, server-owned:
--   * Checkpoint: the start of the last stage zone the player entered. They
--     respawn there on death instead of back at LobbySpawn.
--   * Claims: which reward pads they've already been paid by this run, so each
--     pays once per player per run. Finishing the run (a RespawnToLobby pad)
--     clears both, so the next run pays out again.

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
