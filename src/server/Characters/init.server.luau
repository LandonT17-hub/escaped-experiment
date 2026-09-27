local Players = game:GetService("Players")

-- Player characters show no overhead name or health bar -- a player's own HP
-- lives on their HUD (HUDController -> MainHUD HPBar). Enemies keep their overhead
-- health bars (DummyEnemy builds those on the enemy, not here).

local function stripHealthBillboard(instance: Instance)
	if instance:IsA("BillboardGui") and string.find(string.lower(instance.Name), "health") then
		instance:Destroy()
	end
end

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	-- None of our code adds one, but catch any health-bar BillboardGui from
	-- elsewhere (e.g. a StarterCharacterScripts script), now or later.
	for _, descendant in character:GetDescendants() do
		stripHealthBillboard(descendant)
	end
	character.DescendantAdded:Connect(stripHealthBillboard)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
