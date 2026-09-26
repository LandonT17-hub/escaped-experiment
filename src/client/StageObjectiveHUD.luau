local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local StageObjectiveHUD = {}

function StageObjectiveHUD.Init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "StageObjectiveHUD"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local banner = Instance.new("TextLabel")
	banner.Name = "ObjectiveBanner"
	banner.Size = UDim2.fromOffset(420, 44)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 24)
	banner.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	banner.BackgroundTransparency = 0.35
	banner.BorderSizePixel = 0
	banner.Font = Enum.Font.GothamBold
	banner.TextScaled = true
	banner.TextColor3 = Color3.fromRGB(255, 255, 255)
	banner.TextStrokeTransparency = 0.4
	banner.Text = "Defeat all enemies (0/3)"
	banner.Visible = false
	banner.Parent = screenGui

	local inZone = false
	local defeated = 0
	local total = 3
	local cleared = false

	local function refresh()
		banner.Visible = inZone
		if cleared then
			banner.Text = "Stage Cleared! Head to the Win Pad"
		else
			banner.Text = string.format("Defeat all enemies (%d/%d)", defeated, total)
		end
	end

	local stageInZone = Remotes.GetRemoteEvent("StageInZone")
	stageInZone.OnClientEvent:Connect(function(value: boolean)
		inZone = value
		refresh()
	end)

	local stageProgress = Remotes.GetRemoteEvent("StageProgress")
	stageProgress.OnClientEvent:Connect(function(newDefeated: number, newTotal: number, newCleared: boolean)
		defeated = newDefeated
		total = newTotal
		cleared = newCleared
		refresh()
	end)
end

return StageObjectiveHUD
