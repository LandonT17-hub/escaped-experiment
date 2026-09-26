local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MutationService = require(ServerScriptService.Server.Mutation.MutationService)
local WorldsData = require(script.Parent.Parent.Worlds.WorldsData)

-- Placeholder visuals: escalating size by form tier (1..6, same across every
-- world) tinted toward that world's ThemeColor -- a cheap "color swap" so a
-- Bio-Dome form doesn't look identical to a Cryo one. No final art.
local FORM_SCALES = { 1.0, 1.15, 1.3, 1.5, 1.75, 2.0 }
local UNTINTED_BASE = Color3.fromRGB(215, 215, 215)

-- Covers both rig types so the tint applies regardless of which one a given
-- character uses.
local BODY_PART_NAMES = {
	-- R6
	"Head",
	"Torso",
	"Left Arm",
	"Right Arm",
	"Left Leg",
	"Right Leg",
	-- R15
	"UpperTorso",
	"LowerTorso",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

-- R15-only; scaling silently no-ops on an R6 character (those NumberValues don't
-- exist there), so R6 characters escalate via tint only.
local BODY_SCALE_NAMES = { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" }

export type EquippedForm = {
	WorldId: number,
	FormIndex: number,
}

local EvolutionService = {}

-- Server-authoritative, never client-writable.
-- unlockedForms[player][worldId][formIndex] = true
local unlockedForms: { [Player]: { [number]: { [number]: boolean } } } = {}
-- The single form a player currently has equipped -- can be from any world
-- they've unlocked forms in; Mutation/Wins/forms are global progression, not
-- reset per world, so combat power should follow the player, not the room.
local equippedForm: { [Player]: EquippedForm } = {}

local formUpdated = Remotes.GetRemoteEvent("FormUpdated")

local function applyFormVisual(character: Model, worldConfig: WorldsData.WorldConfig, formIndex: number)
	local scale = FORM_SCALES[formIndex]
	if not scale then
		return
	end

	local tierRatio = (formIndex - 1) / (#FORM_SCALES - 1)
	local color = UNTINTED_BASE:Lerp(worldConfig.ThemeColor, tierRatio)

	for _, partName in BODY_PART_NAMES do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.Color = color
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		for _, scaleName in BODY_SCALE_NAMES do
			local scaleValue = humanoid:FindFirstChild(scaleName)
			if scaleValue and scaleValue:IsA("NumberValue") then
				scaleValue.Value = scale
			end
		end
	end
end

function EvolutionService.GetEquippedForm(player: Player): EquippedForm
	return equippedForm[player] or { WorldId = 1, FormIndex = 1 }
end

function EvolutionService.GetDamageMultiplier(player: Player): number
	local equipped = EvolutionService.GetEquippedForm(player)
	local worldConfig = WorldsData.Worlds[equipped.WorldId]
	local formDef = worldConfig and worldConfig.Forms[equipped.FormIndex]
	return formDef and formDef.DamageMultiplier or 1
end

function EvolutionService.HasUnlocked(player: Player, worldId: number, formIndex: number): boolean
	local unlocked = unlockedForms[player]
	return unlocked ~= nil and unlocked[worldId] ~= nil and unlocked[worldId][formIndex] == true
end

export type SaveData = {
	-- String-keyed (both levels) for safe DataStore round-tripping -- a
	-- numeric-keyed Lua table can serialize ambiguously (array vs. sparse
	-- object) depending on which indices are present; runtime state
	-- (unlockedForms above) still uses number keys, this is only the
	-- persisted shape.
	UnlockedForms: { [string]: { [string]: boolean } },
	EquippedForm: EquippedForm,
}

-- nil means "this player has no live state to save" (already cleared by
-- ClearPlayerData).
function EvolutionService.GetSaveData(player: Player): SaveData?
	local unlocked = unlockedForms[player]
	if not unlocked then
		return nil
	end

	local serializedUnlocks: { [string]: { [string]: boolean } } = {}
	for worldId, forms in unlocked do
		local serializedForms: { [string]: boolean } = {}
		for formIndex, isUnlocked in forms do
			if isUnlocked then
				serializedForms[tostring(formIndex)] = true
			end
		end
		serializedUnlocks[tostring(worldId)] = serializedForms
	end

	return {
		UnlockedForms = serializedUnlocks,
		EquippedForm = EvolutionService.GetEquippedForm(player),
	}
end

local function equipForm(player: Player, worldId: number, formIndex: number)
	local worldConfig = WorldsData.Worlds[worldId]
	local formDef = worldConfig and worldConfig.Forms[formIndex]
	if not worldConfig or not formDef then
		return
	end

	equippedForm[player] = { WorldId = worldId, FormIndex = formIndex }
	formUpdated:FireClient(player, formDef.Name)

	-- Server-driven character change -- replicates to every client automatically,
	-- so other players see the new form too.
	local character = player.Character
	if character then
		applyFormVisual(character, worldConfig, formIndex)
	end
end

-- Validates unlock order and Wins cost server-side; the client only ever
-- requests a (worldId, formIndex) via that world's pedestal ProximityPrompt,
-- nothing else.
function EvolutionService.TryUnlockForm(player: Player, worldId: number, formIndex: number): boolean
	local worldConfig = WorldsData.Worlds[worldId]
	if not worldConfig then
		return false
	end

	local formDef = worldConfig.Forms[formIndex]
	if not formDef then
		return false
	end

	local unlocked = unlockedForms[player]
	local unlockedInWorld = unlocked and unlocked[worldId]
	if not unlockedInWorld then
		return false
	end

	if unlockedInWorld[formIndex] then
		-- Already unlocked -- the pedestal just re-equips it, no cost.
		equipForm(player, worldId, formIndex)
		return true
	end

	if formIndex > 1 and not unlockedInWorld[formIndex - 1] then
		return false -- forms must be unlocked in order within their world
	end

	if not MutationService.SpendWins(player, formDef.WinsCost) then
		return false -- insufficient Wins
	end

	unlockedInWorld[formIndex] = true
	equipForm(player, worldId, formIndex)
	return true
end

-- Applies loaded DataStore values on top of this player's current (fresh
-- default) state. Called by PersistenceService once a load resolves --
-- always strictly after onPlayerAdded below has already run for this player
-- (that handler never yields, so it always finishes before this one, which
-- is only reached after an async DataStore round trip). Merges rather than
-- replaces each world's unlock set, and always keeps Form 1 granted, so a
-- save written before a world/form was added never regresses a player.
function EvolutionService.LoadSaveData(player: Player, data: SaveData)
	local unlocked = unlockedForms[player]
	if not unlocked then
		return
	end

	for _, worldConfig in WorldsData.Worlds do
		local savedWorldUnlocks = data.UnlockedForms[tostring(worldConfig.Id)]
		local worldUnlocked = unlocked[worldConfig.Id] or {}
		worldUnlocked[1] = true

		if savedWorldUnlocks then
			for formIndexString, isUnlocked in savedWorldUnlocks do
				if isUnlocked then
					local formIndex = tonumber(formIndexString)
					if formIndex then
						worldUnlocked[formIndex] = true
					end
				end
			end
		end

		unlocked[worldConfig.Id] = worldUnlocked
	end

	local equipped = data.EquippedForm
	local worldConfig = equipped and WorldsData.Worlds[equipped.WorldId]
	local formDef = worldConfig and worldConfig.Forms[equipped.FormIndex]
	if worldConfig and formDef then
		equipForm(player, equipped.WorldId, equipped.FormIndex)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	character:WaitForChild("Humanoid")
	-- Reapply the current form's visual on every spawn, not just the first --
	-- otherwise a respawn would silently reset a player back to Subject's look.
	local equipped = EvolutionService.GetEquippedForm(player)
	local worldConfig = WorldsData.Worlds[equipped.WorldId]
	if worldConfig then
		applyFormVisual(character, worldConfig, equipped.FormIndex)
	end
end

local function onPlayerAdded(player: Player)
	local unlocked: { [number]: { [number]: boolean } } = {}
	for _, worldConfig in WorldsData.Worlds do
		-- Every world's Form 1 ("Subject") is a free starting form, auto-granted
		-- so a player who reaches a new world always has a baseline look
		-- available without needing to spend Wins first.
		unlocked[worldConfig.Id] = { [1] = true }
	end
	unlockedForms[player] = unlocked

	equippedForm[player] = { WorldId = 1, FormIndex = 1 }
	formUpdated:FireClient(player, WorldsData.Worlds[1].Forms[1].Name)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

-- Called explicitly by PersistenceService, after it has read (and saved)
-- this player's final state -- deliberately NOT wired to PlayerRemoving
-- directly here; see MutationService.ClearPlayerData for why.
function EvolutionService.ClearPlayerData(player: Player)
	unlockedForms[player] = nil
	equippedForm[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

return EvolutionService
