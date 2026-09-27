-- The game's own Game Pass ids. 0 / missing = not created in the Creator
-- Dashboard yet ("coming soon"): no purchase prompt and nobody owns it, so
-- nothing breaks before these are filled in.

local GamepassData = {}

-- "Premium Wins": required to claim a stage's PremiumWinPad (pads with
-- RequiresPremium = true). Not Roblox Premium membership.
GamepassData.PremiumWinsPassId = 0

-- Unlocks the gamepass training plot (Plot5, x10). Replaces the old
-- per-pad multiplier passes, none of which had been created yet.
GamepassData.TrainingPlotPassId = 0

function GamepassData.AllPassIds(): { number }
	local ids = {}
	if GamepassData.PremiumWinsPassId > 0 then
		table.insert(ids, GamepassData.PremiumWinsPassId)
	end
	if GamepassData.TrainingPlotPassId > 0 then
		table.insert(ids, GamepassData.TrainingPlotPassId)
	end
	return ids
end

return GamepassData
