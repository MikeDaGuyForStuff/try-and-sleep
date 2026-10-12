local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CUTSCENE_NAME = "walkoutofstorefromregister"
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
local exportOptions = data.ExportOptions or {}

-- Simple local preview only.
-- For rig cutscenes, use PlayServerTriggerExample + PlayClientReceiver instead.
if exportOptions.Trigger == "Timed" or exportOptions.Trigger == "AutoStart" then
	task.wait(tonumber(exportOptions.DelaySeconds) or 0)
end

player.Play(data, {
	restoreCamera = exportOptions.RestoreCamera ~= false,
})
