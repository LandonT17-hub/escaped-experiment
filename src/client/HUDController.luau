local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

-- Wires the Studio-built HUD (StarterGui > MainHUD > DesktopHUD) to live game
-- data. Creates and restyles nothing beyond the state colours/visibility the
-- HUD spec defines -- the UI itself is authored in Studio. Display only: all
-- values come from the server (remotes / player attributes / the character's
-- Humanoid), never computed or trusted here.
--
-- Stage bar data: reads the Player attributes "CurrentStage" (0 or nil = not
-- in a stage) and "StagesCleared" (highest stage cleared this run). Until the
-- server sets those, the bar shows everything locked and the StagePill stays
-- hidden.
--
-- LevelBar is repurposed as rebirth progress (there's no Level/XP system).
--
-- Not wired yet (by design): MenuTiles, Offers, QuickBuys.

local STAGE_COUNT = 12
local DESIGN_HEIGHT = 1080

local STATE_COLORS = {
	done = {
		Top = Color3.fromHex("A8FF6E"),
		Base = Color3.fromHex("62D926"),
		Lip = Color3.fromHex("3AA316"),
	},
	current = {
		Top = Color3.fromHex("FFE27A"),
		Base = Color3.fromHex("FFBE2E"),
		Lip = Color3.fromHex("D98800"),
	},
	locked = {
		Top = Color3.fromHex("E8F4FA"),
		Base = Color3.fromHex("B9D3E0"),
		Lip = Color3.fromHex("8FB0C2"),
	},
}
local CONN_DONE_COLOR = Color3.fromHex("7CF03A")
local CONN_LOCKED_COLOR = Color3.fromHex("2B3E52")
local CURRENT_SCALE = 1.18

-- Rebirth is paid in Wins (MutationService.TryRebirth spends Wins, then
-- resets Mutation), so progress toward it is measured in Wins. Set to
-- "Mutation" to show Mutation against the cost instead.
local REBIRTH_PROGRESS_STAT = "Wins"

local LOBBY_OBJECTIVE = "Enter the Containment Wing"
local CLEARED_OBJECTIVE = "Step on the Win pad!"

local HUDController = {}

local warned: { [string]: boolean } = {}

-- Name lookup that warns once per missing path instead of erroring, so a
-- renamed element only disables its own piece of the HUD.
local function find(parent: Instance?, path: string, className: string?): any
	local current = parent
	for name in string.gmatch(path, "[^%.]+") do
		if not current then
			break
		end
		current = current:FindFirstChild(name)
	end

	if not current or (className and not current:IsA(className)) then
		local key = (if parent then parent:GetFullName() else "?") .. "." .. path
		if not warned[key] then
			warned[key] = true
			warn(`[HUD] missing {key}` .. (if className then ` ({className})` else ""))
		end
		return nil
	end
	return current
end

local function setText(label: Instance?, text: string)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

-- Sets only the X scale, keeping the Studio-authored offsets and Y size.
local function setFillX(fillHolder: GuiObject?, ratio: number)
	if fillHolder then
		local size = fillHolder.Size
		fillHolder.Size = UDim2.new(math.clamp(ratio, 0, 1), size.X.Offset, size.Y.Scale, size.Y.Offset)
	end
end

local function commaFormat(value: number): string
	local text = tostring(math.floor(value))
	local sign, digits = text:match("^(-?)(%d+)$")
	if not digits then
		return text
	end
	local formatted = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return sign .. formatted:gsub("^,", "")
end

local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi" }

local function abbreviate(value: number): string
	if math.abs(value) < 1000 then
		return tostring(math.floor(value))
	end
	local index = 0
	local scaled = value
	while math.abs(scaled) >= 1000 and index < #SUFFIXES do
		scaled /= 1000
		index += 1
	end
	-- One decimal, dropping a trailing ".0" (1.2K, 3K).
	local text = string.format("%.1f", math.floor(scaled * 10) / 10):gsub("%.0$", "")
	return text .. SUFFIXES[index]
end

-- HUDScale shrinks/grows DesktopHUD itself, so the frame is resized by the
-- inverse scale to keep it exactly filling the screen -- otherwise right- and
-- bottom-anchored elements get pulled toward the top-left.
local function wireScale(hud: Instance)
	local uiScale = find(hud, "HUDScale", "UIScale")
	if not uiScale then
		return
	end
	local frame = if hud:IsA("GuiObject") then hud else nil

	local cameraConnection: RBXScriptConnection? = nil

	local function bindCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local function apply()
			local scale = camera.ViewportSize.Y / DESIGN_HEIGHT
			if scale <= 0 then
				return
			end
			uiScale.Scale = scale
			if frame then
				frame.AnchorPoint = Vector2.zero
				frame.Position = UDim2.fromScale(0, 0)
				frame.Size = UDim2.fromScale(1 / scale, 1 / scale)
			end
		end
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
		apply()
	end

	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	bindCamera()
end

local function wireStageBar(hud: Instance, player: Player)
	local stageBar = find(hud, "StageBar")
	local pill = find(hud, "StagePill", "GuiObject")
	local pillLabel = find(pill, "Label", "TextLabel")

	local function styleStage(index: number, state: string)
		local stage = find(stageBar, "Stage" .. index, "GuiObject")
		if not stage then
			return
		end
		local colors = STATE_COLORS[state]
		local isCurrent = state == "current"

		stage.BackgroundColor3 = colors.Lip
		stage.ZIndex = if isCurrent then 2 else 1

		local gradient = find(stage, "Face.UIGradient", "UIGradient")
		if gradient then
			gradient.Color = ColorSequence.new(colors.Top, colors.Base)
		end

		local ring = find(stage, "Ring", "GuiObject")
		if ring then
			ring.Visible = isCurrent
		end

		local scale = find(stage, "CurrentScale", "UIScale")
		if scale then
			scale.Scale = if isCurrent then CURRENT_SCALE else 1
		end
	end

	local function refresh()
		local currentStage = player:GetAttribute("CurrentStage")
		local stagesCleared = player:GetAttribute("StagesCleared")
		currentStage = if typeof(currentStage) == "number" then currentStage else 0
		stagesCleared = if typeof(stagesCleared) == "number" then stagesCleared else 0

		for index = 1, STAGE_COUNT do
			local state = if index == currentStage
				then "current"
				elseif index <= stagesCleared then "done"
				else "locked"
			styleStage(index, state)

			local conn = find(stageBar, "Conn" .. index, "GuiObject")
			if conn then
				conn.BackgroundColor3 = if index <= stagesCleared then CONN_DONE_COLOR else CONN_LOCKED_COLOR
			end
		end

		local inStage = currentStage >= 1 and currentStage <= STAGE_COUNT
		if pill then
			pill.Visible = inStage
		end
		if inStage then
			setText(pillLabel, `STAGE {currentStage}`)
		end
	end

	player:GetAttributeChangedSignal("CurrentStage"):Connect(refresh)
	player:GetAttributeChangedSignal("StagesCleared"):Connect(refresh)
	refresh()
end

local function wireObjective(hud: Instance)
	local label = find(hud, "Objective.Label", "TextLabel")
	local drop = find(hud, "Objective.Drop", "TextLabel")

	local inZone = false
	local defeated, total, cleared = 0, 3, false

	local function refresh()
		local text = if not inZone
			then LOBBY_OBJECTIVE
			elseif cleared then CLEARED_OBJECTIVE
			else `Defeat all enemies ({defeated}/{total})`
		setText(label, text)
		setText(drop, text)
	end

	Remotes.GetRemoteEvent("StageInZone").OnClientEvent:Connect(function(value: boolean)
		inZone = value
		refresh()
	end)

	Remotes.GetRemoteEvent("StageProgress").OnClientEvent:Connect(
		function(newDefeated: number, newTotal: number, newCleared: boolean)
			defeated, total, cleared = newDefeated, newTotal, newCleared
			refresh()
		end
	)

	refresh()
end

local function wireHealth(hud: Instance, player: Player)
	local label = find(hud, "HPBar.Label", "TextLabel")
	local fill = find(hud, "HPBar.FillHolder", "GuiObject")

	local healthConnection: RBXScriptConnection? = nil

	local function bind(character: Model)
		if healthConnection then
			healthConnection:Disconnect()
		end
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid or not humanoid:IsA("Humanoid") then
			return
		end

		local function refresh()
			local current = math.max(0, math.floor(humanoid.Health))
			local max = math.floor(humanoid.MaxHealth)
			setText(label, `HP {current}/{max}`)
			setFillX(fill, if max > 0 then current / max else 0)
		end

		healthConnection = humanoid.HealthChanged:Connect(refresh)
		refresh()
	end

	player.CharacterAdded:Connect(bind)
	if player.Character then
		task.spawn(bind, player.Character)
	end
end

local function wireStats(hud: Instance)
	local winsValue = find(hud, "StatsRow.Wins.Value", "TextLabel")
	local mutationValue = find(hud, "StatsRow.Mutation.ValueBox.Value", "TextLabel")
	local mutationDrop = find(hud, "StatsRow.Mutation.ValueBox.Drop", "TextLabel")
	local rebirthLabel = find(hud, "StatsRow.RebirthReadout.Label", "TextLabel")

	-- Defaults until the server's first update arrives.
	setText(winsValue, "0")
	setText(mutationValue, "0")
	setText(mutationDrop, "0")
	setText(rebirthLabel, "Rebirth x1.00")

	Remotes.GetRemoteEvent("WinsUpdated").OnClientEvent:Connect(function(amount: number)
		setText(winsValue, abbreviate(amount))
	end)

	Remotes.GetRemoteEvent("MutationUpdated").OnClientEvent:Connect(function(amount: number)
		local text = commaFormat(amount)
		setText(mutationValue, text)
		setText(mutationDrop, text)
	end)

	Remotes.GetRemoteEvent("RebirthUpdated").OnClientEvent:Connect(function(multiplier: number)
		setText(rebirthLabel, string.format("Rebirth x%.2f", multiplier))
	end)
end

local function wireRebirthProgress(hud: Instance)
	local levelLabel = find(hud, "LevelBar.LevelLabel", "TextLabel")
	local xpLabel = find(hud, "LevelBar.XPLabel", "TextLabel")
	local fill = find(hud, "LevelBar.FillHolder", "GuiObject")

	setText(levelLabel, "Rebirth")

	local current = 0
	local cost: number? = nil

	local function refresh()
		if not cost then
			return
		end
		setText(xpLabel, `{commaFormat(current)} / {commaFormat(cost)}`)
		setFillX(fill, if cost > 0 then math.min(current / cost, 1) else 1)
	end

	-- The cost grows with every rebirth; re-read it whenever it changes.
	local getRebirthInfo = Remotes.GetRemoteFunction("GetRebirthInfo")
	local function refreshCost()
		local ok, info = pcall(getRebirthInfo.InvokeServer, getRebirthInfo)
		if ok and typeof(info) == "table" and typeof(info.Cost) == "number" then
			cost = info.Cost
			refresh()
		end
	end

	local statRemote = if REBIRTH_PROGRESS_STAT == "Mutation" then "MutationUpdated" else "WinsUpdated"
	Remotes.GetRemoteEvent(statRemote).OnClientEvent:Connect(function(amount: number)
		current = amount
		refresh()
	end)
	Remotes.GetRemoteEvent("RebirthUpdated").OnClientEvent:Connect(function()
		task.spawn(refreshCost)
	end)

	task.spawn(refreshCost)
end

function HUDController.Init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local mainHud = playerGui:WaitForChild("MainHUD", 15)
	if not mainHud then
		warn("[HUD] PlayerGui.MainHUD not found -- is StarterGui > MainHUD present?")
		return
	end

	local hud = find(mainHud, "DesktopHUD")
	if not hud then
		return
	end

	-- Roblox's built-in top-right health bar duplicates HPBar.
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Health, false)

	wireScale(hud)
	wireStageBar(hud, player)
	wireObjective(hud)
	wireHealth(hud, player)
	wireStats(hud)
	wireRebirthProgress(hud)
end

return HUDController
