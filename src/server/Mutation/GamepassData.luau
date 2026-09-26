-- Config for the 4 Mutation multiplier gamepasses (x3/x9/x25/x100) sold from
-- the lobby's Multiplier Pad row. These are GLOBAL passes: every world's
-- lobby has its own copy of the same 4 pads (a convenience so players don't
-- have to backtrack to World1), but touching any world's "x3" pad checks the
-- same gamepass and grants the same account-wide multiplier. Owned tiers
-- stack multiplicatively (all 4 = x67,500 Mutation).
--
-- GamePassId is 0 (placeholder) until you create the real Game Pass in the
-- Creator Dashboard and paste its id in here -- see the master build's
-- Phase 4 report for exact setup steps. A tier with GamePassId = 0 shows
-- "(coming soon)" on its pad and has no purchase prompt, so nothing breaks
-- before you fill these in.

export type GamepassTier = {
	Name: string,
	Multiplier: number,
	GamePassId: number,
}

local GamepassData = {}

local MutationMultiplierTiers: { GamepassTier } = {
	{ Name = "x3 Mutation", Multiplier = 3, GamePassId = 0 },
	{ Name = "x9 Mutation", Multiplier = 9, GamePassId = 0 },
	{ Name = "x25 Mutation", Multiplier = 25, GamePassId = 0 },
	{ Name = "x100 Mutation", Multiplier = 100, GamePassId = 0 },
}

GamepassData.MutationMultiplierTiers = MutationMultiplierTiers

return GamepassData
