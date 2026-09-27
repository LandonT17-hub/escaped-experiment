-- The game's own Game Pass ids. 0 / missing = not created in the Creator
-- Dashboard yet ("coming soon"): no purchase prompt and nobody owns it, so
-- nothing breaks before these are filled in.

local GamepassData = {}

-- "Premium Wins": required to claim a stage's PremiumWinPad (pads with
-- RequiresPremium = true). Not Roblox Premium membership.
GamepassData.PremiumWinsPassId = 0

-- Multiplier Pads whose RequirementType is "Gamepass", keyed by the pad's
-- PadIndex attribute. Example once created: [5] = 123456789,
GamepassData.MultiplierPadPasses = {} :: { [number]: number }

function GamepassData.AllPassIds(): { number }
	local ids = {}
	if GamepassData.PremiumWinsPassId > 0 then
		table.insert(ids, GamepassData.PremiumWinsPassId)
	end
	for _, id in GamepassData.MultiplierPadPasses do
		if id > 0 then
			table.insert(ids, id)
		end
	end
	return ids
end

return GamepassData
