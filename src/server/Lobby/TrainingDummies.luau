local ServerScriptService = game:GetService("ServerScriptService")

local EnemyRegistry = require(ServerScriptService.Server.Enemies.EnemyRegistry)
local MutationService = require(ServerScriptService.Server.Mutation.MutationService)
local MapLookup = require(ServerScriptService.Server.Worlds.MapLookup)

-- Lobby training dummies (Lobby.TrainingArea > Dummy1..6), each a Model with
-- Tier / MutationPerHit / WinsRequired attributes. Registered as Bite targets
-- in EnemyRegistry, so they go through CombatService's server-side range,
-- facing and cooldown checks exactly like enemies -- CombatService's
-- per-player ATTACK_COOLDOWN already caps hits at normal Bite speed, so an
-- auto-clicker can't farm faster. A hit grants MutationPerHit (through
-- GrantMutation, so pad/rebirth multipliers apply) if the attacker has at
-- least WinsRequired Wins. Dummies take no damage and never die.

local TrainingDummies = {}

function TrainingDummies.WireUp(trainingArea: Instance)
	for i = 1, 6 do
		local model = MapLookup.Find(trainingArea, "Dummy" .. i, "Model")
		if not model then
			continue
		end

		local target = MapLookup.Find(model, "Target", "BasePart")
		local mutationPerHit = MapLookup.Attr(model, "MutationPerHit", "number")
		local winsRequired = MapLookup.Attr(model, "WinsRequired", "number")
		if not target or not mutationPerHit or not winsRequired then
			continue
		end

		EnemyRegistry.Register(model, {
			TargetPart = target,
			TakeDamage = function(_amount: number, attacker: Player?)
				if attacker and MutationService.GetWins(attacker) >= winsRequired then
					MutationService.GrantMutation(attacker, mutationPerHit)
				end
			end,
		})
	end
end

return TrainingDummies
