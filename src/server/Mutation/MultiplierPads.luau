local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local GamepassData = require(script.Parent.GamepassData)
local GamepassService = require(script.Parent.GamepassService)
local MapLookup = require(ServerScriptService.Server.Worlds.MapLookup)

-- The lobby's Multiplier Pads (Lobby.MultiplierPads > Pad1..6), each a Model
-- with Multiplier / RequirementType / RequirementAmount attributes. A player
-- qualifies for a pad when its requirement is met:
--   Free     -- always
--   Rebirths -- RebirthCount >= RequirementAmount
--   Gamepass -- owns the pass mapped to the pad's PadIndex in GamepassData
-- Their Mutation multiplier is the highest Multiplier among the pads they
-- qualify for (not stacked). Derived live, never stored, so there's nothing
-- to persist and it can't drift. Touching a Gamepass pad's Plate prompts the
-- purchase.

export type Pad = {
	Multiplier: number,
	RequirementType: string,
	RequirementAmount: number,
	GamePassId: number,
}

local PURCHASE_PROMPT_COOLDOWN = 5 -- seconds; Touched fires constantly while standing

local MultiplierPads = {}

local pads: { Pad } = {}
local lastPromptAt: { [Player]: number } = {}

local function qualifies(player: Player, pad: Pad, rebirthCount: number): boolean
	if pad.RequirementType == "Free" then
		return true
	elseif pad.RequirementType == "Rebirths" then
		return rebirthCount >= pad.RequirementAmount
	elseif pad.RequirementType == "Gamepass" then
		return pad.GamePassId > 0 and GamepassService.OwnsGamePass(player, pad.GamePassId)
	end
	return false
end

-- rebirthCount is passed in (rather than read from MutationService) because
-- MutationService calls this -- avoids a require cycle.
function MultiplierPads.GetMultiplier(player: Player, rebirthCount: number): number
	local best = 1
	for _, pad in pads do
		if pad.Multiplier > best and qualifies(player, pad, rebirthCount) then
			best = pad.Multiplier
		end
	end
	return best
end

-- Pads sold as game passes that exist in the Creator Dashboard (id > 0),
-- for the Store menu.
function MultiplierPads.GetGamepassPads(): { Pad }
	local result = {}
	for _, pad in pads do
		if pad.RequirementType == "Gamepass" and pad.GamePassId > 0 then
			table.insert(result, pad)
		end
	end
	return result
end

local function labelText(pad: Pad): string
	local requirement = if pad.RequirementType == "Free"
		then "Free"
		elseif pad.RequirementType == "Rebirths" then `Requires {pad.RequirementAmount} Rebirths`
		elseif pad.GamePassId > 0 then "Game Pass"
		else "Game Pass (coming soon)"
	return `x{pad.Multiplier} Mutation\n{requirement}`
end

function MultiplierPads.WireUp(padsFolder: Instance)
	for i = 1, 6 do
		local model = MapLookup.Find(padsFolder, "Pad" .. i, "Model")
		if not model then
			continue
		end

		local multiplier = MapLookup.Attr(model, "Multiplier", "number")
		local requirementType = MapLookup.Attr(model, "RequirementType", "string")
		if not multiplier or not requirementType then
			continue
		end

		if requirementType ~= "Free" and requirementType ~= "Rebirths" and requirementType ~= "Gamepass" then
			warn(`[Map] {model:GetFullName()} has unknown RequirementType "{requirementType}"`)
			continue
		end

		local padIndex = model:GetAttribute("PadIndex") or i
		local pad: Pad = {
			Multiplier = multiplier,
			RequirementType = requirementType,
			RequirementAmount = model:GetAttribute("RequirementAmount") or 0,
			GamePassId = GamepassData.MultiplierPadPasses[padIndex] or 0,
		}
		table.insert(pads, pad)

		local text = MapLookup.Find(MapLookup.Find(model, "Label"), "Text", "TextLabel")
		if text then
			text.Text = labelText(pad)
		end

		if pad.RequirementType == "Gamepass" and pad.GamePassId > 0 then
			local plate = MapLookup.Find(model, "Plate", "BasePart")
			if plate then
				plate.Touched:Connect(function(hit: BasePart)
					local character = hit.Parent
					local player = character and Players:GetPlayerFromCharacter(character)
					if not player or GamepassService.OwnsGamePass(player, pad.GamePassId) then
						return
					end

					local now = os.clock()
					local last = lastPromptAt[player]
					if last and now - last < PURCHASE_PROMPT_COOLDOWN then
						return
					end
					lastPromptAt[player] = now

					GamepassService.PromptPurchase(player, pad.GamePassId)
				end)
			end
		end
	end
end

Players.PlayerRemoving:Connect(function(player: Player)
	lastPromptAt[player] = nil
end)

return MultiplierPads
