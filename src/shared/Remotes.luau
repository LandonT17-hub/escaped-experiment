local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local Remotes = {}

local function getFolder()
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder
	end

	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

function Remotes.GetRemoteEvent(name: string): RemoteEvent
	local folder = getFolder()

	if RunService:IsServer() then
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		return remote
	end

	return folder:WaitForChild(name)
end

-- Server-side handlers only (OnServerInvoke). Never invoke a client from the
-- server -- a client can hang or error that call.
function Remotes.GetRemoteFunction(name: string): RemoteFunction
	local folder = getFolder()

	if RunService:IsServer() then
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
		return remote
	end

	return folder:WaitForChild(name)
end

return Remotes
