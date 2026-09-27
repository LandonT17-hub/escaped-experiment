-- Redeemable codes. Keys are matched case-insensitively (write them in
-- UPPERCASE here). Each reward field is optional. Delete an entry to retire a
-- code; players who already redeemed it keep what they got.
--
-- WELCOME is a placeholder for testing -- replace or remove before launch.

export type CodeReward = {
	Wins: number?,
	Mutation: number?, -- granted through GrantMutation, so multipliers apply
}

local CodesData: { [string]: CodeReward } = {
	WELCOME = { Wins = 5 },
}

return CodesData
