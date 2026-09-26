local MutationService = require(script.Parent.MutationService)

-- Wires functionality onto the hand-built "RebirthZone" part for one
-- world's lobby -- doesn't rebuild the geometry, just attaches
-- a ProximityPrompt. Called once per world by WorldWiring, same as
-- FormPedestals/MultiplierPads, so all 4 worlds' copies work identically.
--
-- The label stays generic/static rather than showing this player's specific
-- cost or multiplier -- like the other lobby stations, it's a shared
-- Instance visible to every nearby player at once, so it can't correctly
-- reflect one player's numbers. The player's own current multiplier lives on
-- their HUD (MutationHUD.luau, driven by the RebirthUpdated remote).
local RebirthStation = {}

-- Longer hold than the pedestal/pad prompts (0.5s) -- Rebirth spends a
-- meaningful chunk of Wins and wipes Mutation, so it warrants a more
-- deliberate confirmation gesture than swapping a form or buying a pad.
local HOLD_DURATION = 1.5

function RebirthStation.WireUp(rebirthZone: Instance)
	if not rebirthZone:IsA("BasePart") then
		return
	end

	local billboard = rebirthZone:FindFirstChild("Label")
	local textLabel = billboard and billboard:FindFirstChild("TextLabel")
	if textLabel and textLabel:IsA("TextLabel") then
		textLabel.Text = "REBIRTH\nHold: reset Mutation for a permanent gain multiplier"
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RebirthPrompt"
	prompt.ActionText = "Rebirth"
	prompt.ObjectText = "Reset Mutation"
	prompt.HoldDuration = HOLD_DURATION
	prompt.MaxActivationDistance = 12
	prompt.Parent = rebirthZone

	prompt.Triggered:Connect(function(player: Player)
		MutationService.TryRebirth(player)
	end)
end

return RebirthStation
