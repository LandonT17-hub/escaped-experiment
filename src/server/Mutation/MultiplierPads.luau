local GamepassData = require(script.Parent.GamepassData)
local GamepassService = require(script.Parent.GamepassService)

-- Wires functionality onto the hand-built pad Parts (named
-- "MultiplierPad1".."MultiplierPad4") for one world's lobby -- doesn't
-- rebuild the geometry, just attaches a ProximityPrompt that prompts the
-- real Roblox purchase dialog. Called once per world by WorldWiring, same
-- as FormPedestals.WireUp, so all 4 worlds' copies of these pads work
-- identically.
--
-- Deliberately does not try to show per-player "Owned" state on the pad's
-- label or prompt -- those are shared Instance properties visible to every
-- player standing nearby at once, not per-viewer UI, so they can't correctly
-- reflect "owned for you, not owned for them" at the same time. Roblox's own
-- purchase dialog already tells a player if they already own the pass.
local MultiplierPads = {}

function MultiplierPads.WireUp(padsFolder: Instance)
	for i, tier in GamepassData.MutationMultiplierTiers do
		local pad = padsFolder:FindFirstChild("MultiplierPad" .. i)
		if not pad or not pad:IsA("BasePart") then
			continue
		end

		local billboard = pad:FindFirstChild("Label")
		local textLabel = billboard and billboard:FindFirstChild("TextLabel")
		if textLabel and textLabel:IsA("TextLabel") then
			textLabel.Text = if tier.GamePassId > 0
				then `{tier.Name}\nBuy Now`
				else `{tier.Name}\n(coming soon)`
		end

		if tier.GamePassId <= 0 then
			continue -- not created in the Creator Dashboard yet -- see GamepassData.luau
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PurchasePrompt"
		prompt.ActionText = "Buy"
		prompt.ObjectText = tier.Name
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 10
		prompt.Parent = pad

		prompt.Triggered:Connect(function(player: Player)
			GamepassService.PromptPurchase(player, tier.GamePassId)
		end)
	end
end

return MultiplierPads
