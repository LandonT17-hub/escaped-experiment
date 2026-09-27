local MapResolver = require(script.MapResolver)
local WorldWiring = require(script.WorldWiring)
local WorldsData = require(script.WorldsData)

-- The map is hand-built in Studio (workspace.World<N>); nothing here creates
-- geometry. Wires every world whose map exists -- Worlds 2-4 are skipped
-- until they're built.
MapResolver.WarnStrayEnemies()

for _, config in WorldsData.Worlds do
	local worldFolder = workspace:FindFirstChild("World" .. config.Id)
	if worldFolder then
		WorldWiring.Wire(config, MapResolver.Resolve(worldFolder, config))
	end
end
