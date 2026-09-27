local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local EnemyRegistry = require(ServerScriptService.Server.Enemies.EnemyRegistry)
local MutationService = require(ServerScriptService.Server.Mutation.MutationService)
local GamepassData = require(ServerScriptService.Server.Mutation.GamepassData)
local GamepassService = require(ServerScriptService.Server.Mutation.GamepassService)
local MapLookup = require(ServerScriptService.Server.Worlds.MapLookup)

-- Lobby training plots (Lobby.TrainingPlots > Plot1..Plot8), replacing the
-- old Multiplier Pads and training dummies. Each plot's Dummy > Target is a
-- Bite target registered in EnemyRegistry, so hits go through
-- CombatService's server-side range, facing and cooldown checks like
-- enemies (the per-player Bite cooldown caps farming speed).
--
-- A hit on an unlocked plot grants BASE_MUTATION_PER_HIT * that plot's
-- multiplier, through GrantMutation (which applies the rebirth multiplier).
-- A hit on a locked plot grants nothing; on the gamepass plot it prompts the
-- purchase instead (rate-limited). Unlock rules live only in PLOTS below --
-- never read from the plot's sign.

export type Plot = {
	Requirement: "Free" | "Rebirths" | "Gamepass",
	Rebirths: number?, -- for Requirement = "Rebirths"
	Multiplier: number,
}

-- Index = PlotN in the map.
local PLOTS: { Plot } = {
	{ Requirement = "Free", Multiplier = 1 },
	{ Requirement = "Rebirths", Rebirths = 1, Multiplier = 2 },
	{ Requirement = "Rebirths", Rebirths = 2, Multiplier = 4 },
	{ Requirement = "Rebirths", Rebirths = 4, Multiplier = 8 },
	{ Requirement = "Gamepass", Multiplier = 10 }, -- GamepassData.TrainingPlotPassId
	{ Requirement = "Rebirths", Rebirths = 6, Multiplier = 18 },
	{ Requirement = "Rebirths", Rebirths = 9, Multiplier = 45 },
	{ Requirement = "Rebirths", Rebirths = 12, Multiplier = 70 },
}

-- Placeholder tuning: Mutation per Bite on an x1 plot, before multipliers.
local BASE_MUTATION_PER_HIT = 1
local PURCHASE_PROMPT_COOLDOWN = 5 -- seconds between gamepass prompts per player

local TrainingPlots = {}

TrainingPlots.Plots = PLOTS

local lastPromptAt: { [Player]: number } = {}

function TrainingPlots.IsUnlocked(player: Player, plotIndex: number): boolean
	local plot = PLOTS[plotIndex]
	if not plot then
		return false
	end

	if plot.Requirement == "Free" then
		return true
	elseif plot.Requirement == "Rebirths" then
		return MutationService.GetRebirthCount(player) >= (plot.Rebirths or 0)
	elseif plot.Requirement == "Gamepass" then
		local passId = GamepassData.TrainingPlotPassId
		return passId > 0 and GamepassService.OwnsGamePass(player, passId)
	end
	return false
end

local function promptPurchase(player: Player)
	local passId = GamepassData.TrainingPlotPassId
	if passId <= 0 then
		return -- not created yet
	end

	local now = os.clock()
	local last = lastPromptAt[player]
	if last and now - last < PURCHASE_PROMPT_COOLDOWN then
		return
	end
	lastPromptAt[player] = now
	GamepassService.PromptPurchase(player, passId)
end

local function onHit(player: Player, plotIndex: number)
	if not TrainingPlots.IsUnlocked(player, plotIndex) then
		if PLOTS[plotIndex].Requirement == "Gamepass" then
			promptPurchase(player)
		end
		return
	end

	MutationService.GrantMutation(player, BASE_MUTATION_PER_HIT * PLOTS[plotIndex].Multiplier)
end

function TrainingPlots.WireUp(plotsFolder: Instance)
	for plotIndex = 1, #PLOTS do
		local plot = MapLookup.Find(plotsFolder, "Plot" .. plotIndex)
		local dummy = MapLookup.Find(plot, "Dummy", "Model")
		local target = MapLookup.Find(dummy, "Target", "BasePart")
		if not dummy or not target then
			continue
		end

		EnemyRegistry.Register(dummy, {
			TargetPart = target,
			-- Dummies take no damage and never die; a hit is a training rep.
			TakeDamage = function(_amount: number, attacker: Player?)
				if attacker then
					onHit(attacker, plotIndex)
				end
			end,
		})
	end
end

Players.PlayerRemoving:Connect(function(player: Player)
	lastPromptAt[player] = nil
end)

return TrainingPlots
