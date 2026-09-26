-- Turns a world's hand-built end-of-final-stage screen part into a "walk-through screen"
-- gateway to the next world (CLAUDE.md: "worlds connect to each other via
-- walk-through screen gateways" -- no central hub, no branching portals).
-- World-agnostic and reusable: WorldWiring wires one per world, pointing at
-- the next world's spawn.
--
-- Locked (world not yet cleared): looks like a translucent screen but still
-- solid -- CanCollide stays true, so it reads as "there but not open yet"
-- rather than an invisible wall. Once the gated stage reports cleared, it
-- turns green/active and CanCollide flips off so players can walk straight
-- through into the next world; touching it server-side teleports them to
-- the configured spawn.

local Players = game:GetService("Players")

local POLL_INTERVAL = 0.5
local TELEPORT_COOLDOWN = 2 -- seconds; guards against re-triggering mid-teleport

local LOCKED_COLOR = Color3.fromRGB(200, 70, 60)
local ACTIVE_COLOR = Color3.fromRGB(90, 200, 210)

export type GatewayConfig = {
	Destination: CFrame,
	DestinationName: string,
	LockedLabel: string,
	-- Optional: called with the player right after a successful teleport, so
	-- a caller (WorldWiring wires this to PersistenceService.SetCurrentWorld)
	-- can track "which world is this player in now" without WorldGateway
	-- needing to know persistence exists.
	OnEnter: ((player: Player) -> ())?,
}

local WorldGateway = {}

local function findOrCreateLabel(capPart: BasePart): TextLabel
	local billboard = capPart:FindFirstChild("Label")
	if not billboard then
		billboard = Instance.new("BillboardGui")
		billboard.Name = "Label"
		billboard.Size = UDim2.fromOffset(280, 70)
		billboard.StudsOffset = Vector3.new(0, 4, 0)
		billboard.AlwaysOnTop = true
		billboard.Parent = capPart
	end

	local textLabel = billboard:FindFirstChild("TextLabel")
	if not textLabel then
		textLabel = Instance.new("TextLabel")
		textLabel.Name = "TextLabel"
		textLabel.Size = UDim2.fromScale(1, 1)
		textLabel.BackgroundTransparency = 1
		textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		textLabel.TextStrokeTransparency = 0.3
		textLabel.Font = Enum.Font.GothamBold
		textLabel.TextScaled = true
		textLabel.Parent = billboard
	end

	return textLabel :: TextLabel
end

-- capPart: the hand-built screen part at the end of the final stage.
-- isCleared: returns whether the stage gating this gateway is fully cleared.
function WorldGateway.Wire(capPart: BasePart, isCleared: () -> boolean, config: GatewayConfig)
	capPart.Material = Enum.Material.Glass
	capPart.Color = LOCKED_COLOR
	capPart.Transparency = 0.5
	capPart.CanCollide = true

	local textLabel = findOrCreateLabel(capPart)
	textLabel.Text = string.format("%s\n%s", config.DestinationName, config.LockedLabel)

	local lastTeleportAt: { [Player]: number } = {}
	local opened = false

	capPart.Touched:Connect(function(hit: BasePart)
		if not opened then
			return
		end

		local character = hit.Parent
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end

		local now = os.clock()
		local last = lastTeleportAt[player]
		if last and now - last < TELEPORT_COOLDOWN then
			return
		end
		lastTeleportAt[player] = now

		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			rootPart.AssemblyLinearVelocity = Vector3.zero
		end

		(character :: Model):PivotTo(config.Destination)

		if config.OnEnter then
			config.OnEnter(player)
		end
	end)

	local function pollCleared()
		-- Stops once opened -- nothing ever re-locks a gateway.
		while capPart.Parent and not opened do
			task.wait(POLL_INTERVAL)

			if isCleared() then
				opened = true
				capPart.Color = ACTIVE_COLOR
				capPart.CanCollide = false
				capPart.Transparency = 0.7
				textLabel.Text = string.format("-> %s", config.DestinationName)
			end
		end
	end

	task.spawn(pollCleared)
end

return WorldGateway
