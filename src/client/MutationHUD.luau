local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local MutationHUD = {}

function MutationHUD.Init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MutationHUD"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	-- Player health bar, top-right corner -- readable mid-combat without
	-- covering the stage objective banner (top-center). Reads the player's own Humanoid.Health directly; that's a
	-- normal replicated property, so no remote round-trip is needed for display
	-- -- the server is still the only thing that ever writes it.
	local healthBar = Instance.new("Frame")
	healthBar.Name = "HealthBar"
	healthBar.Size = UDim2.fromOffset(300, 28)
	healthBar.AnchorPoint = Vector2.new(1, 0)
	healthBar.Position = UDim2.new(1, -20, 0, 20)
	healthBar.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
	healthBar.BorderSizePixel = 0
	healthBar.Parent = screenGui

	local healthFill = Instance.new("Frame")
	healthFill.Name = "Fill"
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthBar

	local healthText = Instance.new("TextLabel")
	healthText.Name = "Text"
	healthText.Size = UDim2.fromScale(1, 1)
	healthText.BackgroundTransparency = 1
	healthText.Font = Enum.Font.GothamBold
	healthText.TextScaled = true
	healthText.TextColor3 = Color3.fromRGB(255, 255, 255)
	healthText.TextStrokeTransparency = 0.3
	healthText.Text = "HP: 100 / 100"
	healthText.Parent = healthBar

	local function bindHealthBar(character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid

		local function refresh()
			local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
			healthFill.Size = UDim2.fromScale(ratio, 1)
			healthText.Text =
				string.format("HP: %d / %d", math.max(0, math.floor(humanoid.Health)), math.floor(humanoid.MaxHealth))
		end

		humanoid.HealthChanged:Connect(refresh)
		refresh()
	end

	player.CharacterAdded:Connect(bindHealthBar)
	if player.Character then
		bindHealthBar(player.Character)
	end

	local container = Instance.new("Frame")
	container.Name = "BottomCenter"
	container.Size = UDim2.fromOffset(320, 134)
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 1, -20)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	local mutationLabel = Instance.new("TextLabel")
	mutationLabel.Name = "Mutation"
	mutationLabel.Size = UDim2.new(1, 0, 0, 56)
	mutationLabel.Position = UDim2.fromOffset(0, 0)
	mutationLabel.BackgroundTransparency = 1
	mutationLabel.Font = Enum.Font.GothamBold
	mutationLabel.TextScaled = true
	mutationLabel.TextColor3 = Color3.fromRGB(150, 255, 120)
	mutationLabel.TextStrokeTransparency = 0.3
	mutationLabel.Text = "Mutation: 0"
	mutationLabel.Parent = container

	local winsLabel = Instance.new("TextLabel")
	winsLabel.Name = "Wins"
	winsLabel.Size = UDim2.new(1, 0, 0, 28)
	winsLabel.Position = UDim2.fromOffset(0, 58)
	winsLabel.BackgroundTransparency = 1
	winsLabel.Font = Enum.Font.GothamBold
	winsLabel.TextScaled = true
	winsLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
	winsLabel.TextStrokeTransparency = 0.4
	winsLabel.Text = "Wins: 0"
	winsLabel.Parent = container

	local rebirthLabel = Instance.new("TextLabel")
	rebirthLabel.Name = "Rebirth"
	rebirthLabel.Size = UDim2.new(1, 0, 0, 24)
	rebirthLabel.Position = UDim2.fromOffset(0, 86)
	rebirthLabel.BackgroundTransparency = 1
	rebirthLabel.Font = Enum.Font.Gotham
	rebirthLabel.TextScaled = true
	rebirthLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
	rebirthLabel.TextStrokeTransparency = 0.5
	rebirthLabel.Text = "Rebirth: x1.00"
	rebirthLabel.Parent = container

	local formLabel = Instance.new("TextLabel")
	formLabel.Name = "Form"
	formLabel.Size = UDim2.new(1, 0, 0, 24)
	formLabel.Position = UDim2.fromOffset(0, 110)
	formLabel.BackgroundTransparency = 1
	formLabel.Font = Enum.Font.Gotham
	formLabel.TextScaled = true
	formLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
	formLabel.TextStrokeTransparency = 0.4
	formLabel.Text = "Form: Subject"
	formLabel.Parent = container

	local mutationUpdated = Remotes.GetRemoteEvent("MutationUpdated")
	mutationUpdated.OnClientEvent:Connect(function(amount: number)
		mutationLabel.Text = string.format("Mutation: %d", amount)
	end)

	local winsUpdated = Remotes.GetRemoteEvent("WinsUpdated")
	winsUpdated.OnClientEvent:Connect(function(amount: number)
		winsLabel.Text = string.format("Wins: %d", amount)
	end)

	local formUpdated = Remotes.GetRemoteEvent("FormUpdated")
	formUpdated.OnClientEvent:Connect(function(formName: string)
		formLabel.Text = string.format("Form: %s", formName)
	end)

	local rebirthUpdated = Remotes.GetRemoteEvent("RebirthUpdated")
	rebirthUpdated.OnClientEvent:Connect(function(multiplier: number)
		rebirthLabel.Text = string.format("Rebirth: x%.2f", multiplier)
	end)
end

return MutationHUD
