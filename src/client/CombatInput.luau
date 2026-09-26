local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

-- Bite: press F or click. Sends a bare request -- the server independently decides
-- range, facing, cooldown, target, and damage. This client never reports any of that.
local ATTACK_KEY = Enum.KeyCode.F

local CombatInput = {}

function CombatInput.Init()
	local attackRequest = Remotes.GetRemoteEvent("AttackRequest")

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
		if gameProcessedEvent then
			return
		end

		if input.KeyCode == ATTACK_KEY or input.UserInputType == Enum.UserInputType.MouseButton1 then
			attackRequest:FireServer()
		end
	end)
end

return CombatInput
