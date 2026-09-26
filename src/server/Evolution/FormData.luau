-- Shared type only -- each world's actual 6-form ladder now lives in that
-- world's WorldConfig.Forms (Worlds/WorldsData.luau), since "6 forms" is one
-- of the per-world config fields the master build's data-driven system reads
-- (alongside theme color, stages, enemy stats), not a standalone table.

export type FormDefinition = {
	Name: string,
	WinsCost: number,
	DamageMultiplier: number,
}

local FormData = {}

return FormData
