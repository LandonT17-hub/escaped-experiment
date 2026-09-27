local ServerScriptService = game:GetService("ServerScriptService")

local FormData = require(script.Parent.FormData)
local EvolutionService = require(script.Parent.EvolutionService)
local MapLookup = require(ServerScriptService.Server.Worlds.MapLookup)

-- Wires the hand-built pedestals (Lobby.Pedestals > Pedestal1..N, each a
-- Model with a Base part) for one world. Each pedestal's FormName/WinsCost
-- attributes are the source of truth for that form's name and price and
-- overwrite the placeholders in WorldsData; damage stays code-defined.
-- Adds a ProximityPrompt to Base that buys (in order) or re-equips the form
-- -- EvolutionService validates everything server-side. Leaves the
-- pedestal's own Label alone: it's shared by every viewer, so it can't show
-- per-player owned/equipped state.

local FormPedestals = {}

function FormPedestals.WireUp(pedestalsFolder: Instance, worldId: number, forms: { FormData.FormDefinition })
	for i = 1, #forms do
		local pedestal = MapLookup.Find(pedestalsFolder, "Pedestal" .. i, "Model")
		if not pedestal then
			continue
		end

		local formIndex = MapLookup.Attr(pedestal, "FormIndex", "number") or i
		local formDef = forms[formIndex]
		if not formDef then
			warn(`[Map] {pedestal:GetFullName()} FormIndex {formIndex} has no form in WorldsData`)
			continue
		end

		local formName = MapLookup.Attr(pedestal, "FormName", "string")
		if formName then
			formDef.Name = formName
		end

		local winsCost = MapLookup.Attr(pedestal, "WinsCost", "number")
		if winsCost then
			formDef.WinsCost = winsCost
		end

		local base = MapLookup.Find(pedestal, "Base", "BasePart")
		if not base then
			continue
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "UnlockPrompt"
		-- Shared by every viewer, so it can't say "Unlock" vs "Equip" per player.
		prompt.ActionText = if formDef.WinsCost <= 0 then "Equip" else `Unlock / Equip ({formDef.WinsCost} Wins)`
		prompt.ObjectText = formDef.Name
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = base

		prompt.Triggered:Connect(function(player: Player)
			EvolutionService.TryUnlockForm(player, worldId, formIndex)
		end)
	end
end

return FormPedestals
