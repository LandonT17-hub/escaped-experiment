local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local MutationService = require(ServerScriptService.Server.Mutation.MutationService)
local MapLookup = require(ServerScriptService.Server.Worlds.MapLookup)

-- Lobby leaderboards (Lobby.Leaderboards > Leaderboard<Stat>, attr Stat).
-- Fills each board's Board > BoardGui > Entries frame with the top players in
-- THIS server, refreshed every REFRESH_INTERVAL. Server-only for now; moves to
-- a global OrderedDataStore with the DataStore task.
--
-- Rows: if Entries has a child named "Template" (a TextLabel, or a GuiObject
-- containing one), it's cloned per row so the rows match your design;
-- otherwise plain TextLabels styled after the board's Title are created.

local REFRESH_INTERVAL = 30
local TOP_COUNT = 10
local ROW_NAME = "Entry"

local STAT_GETTERS: { [string]: (Player) -> number } = {
	Mutation = MutationService.GetMutation,
	Wins = MutationService.GetWins,
	Rebirths = MutationService.GetRebirthCount,
}

type Board = {
	Stat: string,
	Entries: GuiObject,
	Title: TextLabel?,
	Template: GuiObject?,
}

local Leaderboards = {}

local boards: { Board } = {}
local refreshing = false

local function formatNumber(value: number): string
	local text = tostring(math.floor(value))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

local function textLabelOf(row: GuiObject): TextLabel?
	if row:IsA("TextLabel") then
		return row
	end
	return row:FindFirstChildWhichIsA("TextLabel", true)
end

local function makeRow(board: Board, rank: number): GuiObject
	if board.Template then
		local row = board.Template:Clone()
		row.Visible = true
		return row
	end

	local row = Instance.new("TextLabel")
	row.Size = UDim2.fromScale(1, 1 / TOP_COUNT)
	row.Position = UDim2.fromScale(0, (rank - 1) / TOP_COUNT)
	row.BackgroundTransparency = 1
	row.TextScaled = true
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextColor3 = if board.Title then board.Title.TextColor3 else Color3.new(1, 1, 1)
	row.Font = if board.Title then board.Title.Font else Enum.Font.GothamBold
	return row
end

local function refreshBoard(board: Board)
	local getter = STAT_GETTERS[board.Stat]

	local ranked = {}
	for _, player in Players:GetPlayers() do
		table.insert(ranked, { Name = player.DisplayName, Value = getter(player) })
	end
	table.sort(ranked, function(a, b)
		return a.Value > b.Value
	end)

	for _, child in board.Entries:GetChildren() do
		if child.Name == ROW_NAME then
			child:Destroy()
		end
	end

	for rank = 1, math.min(TOP_COUNT, #ranked) do
		local entry = ranked[rank]
		local row = makeRow(board, rank)
		row.Name = ROW_NAME
		row.LayoutOrder = rank

		local label = textLabelOf(row)
		if label then
			label.Text = `#{rank}  {entry.Name}  {formatNumber(entry.Value)}`
		end

		row.Parent = board.Entries
	end
end

local function refreshLoop()
	while true do
		for _, board in boards do
			refreshBoard(board)
		end
		task.wait(REFRESH_INTERVAL)
	end
end

function Leaderboards.WireUp(leaderboardsFolder: Instance)
	for _, name in { "LeaderboardMutation", "LeaderboardWins", "LeaderboardRebirths" } do
		local model = MapLookup.Find(leaderboardsFolder, name)
		local stat = MapLookup.Attr(model, "Stat", "string")
		if not stat then
			continue
		end

		if not STAT_GETTERS[stat] then
			warn(`[Map] {model:GetFullName()} has unknown Stat "{stat}"`)
			continue
		end

		local boardGui = MapLookup.Find(MapLookup.Find(model, "Board", "BasePart"), "BoardGui", "SurfaceGui")
		local entries = MapLookup.Find(boardGui, "Entries", "GuiObject")
		if not entries then
			continue
		end

		local template = entries:FindFirstChild("Template")
		if template and template:IsA("GuiObject") then
			template.Visible = false
		else
			template = nil
		end

		table.insert(boards, {
			Stat = stat,
			Entries = entries,
			Title = MapLookup.Find(boardGui, "Title", "TextLabel"),
			Template = template,
		})
	end

	if not refreshing and #boards > 0 then
		refreshing = true
		task.spawn(refreshLoop)
	end
end

return Leaderboards
