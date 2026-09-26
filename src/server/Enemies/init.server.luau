local DummyEnemy = require(script.DummyEnemy)

-- Lobby is built by a separate script, so wait rather than assume ordering.
local lobby = workspace:WaitForChild("World1"):WaitForChild("Lobby")

-- Open floor in the Lobby's north buffer zone, clear of the Multiplier Pad row
-- (x 30..40, z -24..24) and the entrance opening (x -22.5..22.5).
local spawnCFrame = CFrame.new(50, 1.5, -260)

DummyEnemy.Spawn(lobby, spawnCFrame)
