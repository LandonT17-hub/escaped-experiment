local FormData = require(script.Parent.FormData)
local EvolutionService = require(script.Parent.EvolutionService)

-- Wires functionality onto the hand-built pedestal Parts
-- (named "FormPedestal1".."FormPedestalN") for one specific world -- doesn't
-- rebuild the geometry, just attaches a ProximityPrompt and updates the
-- label each one has (if any). Called once per world by WorldWiring, so the
-- same code wires all 4 worlds' pedestals instead of each being hand-built.

local FormPedestals = {}

function FormPedestals.WireUp(
	pedestalsFolder: Instance,
	worldId: number,
	worldName: string,
	forms: { FormData.FormDefinition }
)
	for i, formDef in forms do
		local pedestal = pedestalsFolder:FindFirstChild("FormPedestal" .. i)
		if not pedestal or not pedestal:IsA("BasePart") then
			continue
		end

		local billboard = pedestal:FindFirstChild("Label")
		local textLabel = billboard and billboard:FindFirstChild("TextLabel")
		if textLabel and textLabel:IsA("TextLabel") then
			local costText = if formDef.WinsCost <= 0 then "Starting Form" else `Cost: {formDef.WinsCost} Wins`
			textLabel.Text = `World {worldId}: {worldName}\n{formDef.Name}\n{costText}`
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "UnlockPrompt"
		prompt.ActionText = if i == 1 then "Equip" else "Unlock"
		prompt.ObjectText = formDef.Name
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 10
		prompt.Parent = pedestal

		prompt.Triggered:Connect(function(player: Player)
			EvolutionService.TryUnlockForm(player, worldId, i)
		end)
	end
end

return FormPedestals
