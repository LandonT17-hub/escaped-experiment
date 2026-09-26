-- Lets CombatService find valid attack targets without knowing anything about how a
-- given enemy tracks its own health/death/respawn. Enemies register on spawn and
-- unregister on death; scales to "3 enemies per stage" later with no Combat changes.

export type EnemyApi = {
	TakeDamage: (amount: number, attacker: Player?) -> (),
}

local EnemyRegistry = {}

local enemies: { [Model]: EnemyApi } = {}

function EnemyRegistry.Register(model: Model, api: EnemyApi)
	enemies[model] = api
end

function EnemyRegistry.Unregister(model: Model)
	enemies[model] = nil
end

function EnemyRegistry.GetAll(): { [Model]: EnemyApi }
	return enemies
end

return EnemyRegistry
