local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CUTSCENE_NAME = "walkintoofstoretoregister"
local root = ReplicatedStorage:WaitForChild("MegMoCutscenes", 10)
if not root then
	warn("[MegMo Cutscene] Missing ReplicatedStorage.MegMoCutscenes. Keep the exported cutscene package in ReplicatedStorage.")
	return
end
local folder = root:WaitForChild(CUTSCENE_NAME, 10)
if not folder then
	warn("[MegMo Cutscene] Missing cutscene folder: ReplicatedStorage.MegMoCutscenes." .. CUTSCENE_NAME)
	return
end
local data = require(folder:WaitForChild("CutsceneData"))
local player = require(folder:WaitForChild("MegMoCutscenePlayer"))
local remote = folder:WaitForChild("PlayCutscene")
local hidePromptRemote = folder:FindFirstChild("HideCutscenePrompt")

local function resolvePath(path)
	if type(path) ~= "string" or path == "" then
		return nil
	end
	local parts = string.split(path, ".")
	local current = game
	local startIndex = 1
	if parts[1] == "game" then
		startIndex = 2
	elseif parts[1] == "Workspace" then
		current = workspace
		startIndex = 2
	elseif parts[1] == "ReplicatedStorage" then
		current = ReplicatedStorage
		startIndex = 2
	end
	for index = startIndex, #parts do
		current = current and current:FindFirstChild(parts[index])
	end
	return current
end

if hidePromptRemote and hidePromptRemote:IsA("RemoteEvent") then
	hidePromptRemote.OnClientEvent:Connect(function(promptOrPath)
		local target = typeof(promptOrPath) == "Instance" and promptOrPath or resolvePath(tostring(promptOrPath or ""))
		local prompt = target and (target:IsA("ProximityPrompt") and target or target:FindFirstChildWhichIsA("ProximityPrompt", true))
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = false
		end
	end)
end

-- Move this LocalScript into StarterPlayerScripts and make sure it is enabled.
remote.OnClientEvent:Connect(function(triggeringUserId)
	player.Play(data, {
		restoreCamera = (data.ExportOptions or {}).RestoreCamera ~= false,
		triggeringUserId = triggeringUserId,
	})
end)
