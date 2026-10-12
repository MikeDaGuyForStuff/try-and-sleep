local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local CUTSCENE_NAME = "cutscene1"
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
local remote = folder:WaitForChild("PlayCutscene")
local hidePromptRemote = folder:FindFirstChild("HideCutscenePrompt")
local options = data.ExportOptions or {}
local settingsFolder = folder:FindFirstChild("CutsceneSettings")

-- Move this Script into ServerScriptService and make sure it is enabled.
-- Also move PlayClientReceiver into StarterPlayerScripts and make sure it is enabled.

local hasPlayedForEveryone = false
local playedLocalUserIds = {}
local CUTSCENE_ORIGINAL_ANCHORED_ATTRIBUTE = "MegMoCutsceneOriginalAnchored"
local CUTSCENE_ORIGINAL_CAN_COLLIDE_ATTRIBUTE = "MegMoCutsceneOriginalCanCollide"
local CUTSCENE_ORIGINAL_CAN_TOUCH_ATTRIBUTE = "MegMoCutsceneOriginalCanTouch"
local CUTSCENE_ORIGINAL_CAN_QUERY_ATTRIBUTE = "MegMoCutsceneOriginalCanQuery"
local CUTSCENE_ORIGINAL_MASSLESS_ATTRIBUTE = "MegMoCutsceneOriginalMassless"

local function settingValue(name, fallback)
	local valueObject = settingsFolder and settingsFolder:FindFirstChild(name)
	if valueObject and valueObject:IsA("ValueBase") then
		return valueObject.Value
	end
	if options[name] ~= nil then
		return options[name]
	end
	return fallback
end

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

local function decodeCFrame(value)
	if type(value) == "table" and value.type == "CFrame" and type(value.components) == "table" then
		return CFrame.new(table.unpack(value.components))
	end
	return nil
end

local function getProjectLastKeyframe()
	local project = data.Project or data
	local lastFrame = 0
	for frameText, pose in pairs(project.frames or {}) do
		if type(pose) == "table" then
			for _ in pairs(pose) do
				lastFrame = math.max(lastFrame, tonumber(frameText) or 0)
				break
			end
		end
	end
	return lastFrame
end

local function getCutsceneDurationSeconds()
	local project = data.Project or data
	local fps = math.max(1, tonumber(project.fps) or 60)
	local lastFrame = getProjectLastKeyframe()
	local durationFrames = lastFrame > 0 and lastFrame or (tonumber(project.durationFrames) or 0)
	return durationFrames / fps
end

local function getCutsceneCompletionDelay()
	return getCutsceneDurationSeconds() + math.max(0, tonumber(settingValue("FadeInSeconds", 0)) or 0)
end

local function scheduleTeleportAfterCutscene(triggeringPlayer)
	if settingValue("AfterCutsceneAction", "StayHere") ~= "Teleport" then
		return
	end
	local placeId = math.floor(tonumber(settingValue("TeleportPlaceId", 0)) or 0)
	if placeId <= 0 then
		warn("[MegMo Cutscene] Teleport is enabled, but TeleportPlaceId is not valid.")
		return
	end

	local recipients = {}
	if settingValue("Playback", "LocalPlayer") == "Everyone" then
		for _, player in ipairs(Players:GetPlayers()) do
			table.insert(recipients, player)
		end
	elseif triggeringPlayer then
		table.insert(recipients, triggeringPlayer)
	end
	if #recipients == 0 then
		warn("[MegMo Cutscene] No player was available to teleport after the cutscene.")
		return
	end

	task.delay(getCutsceneCompletionDelay(), function()
		local activeRecipients = {}
		for _, player in ipairs(recipients) do
			if player and player.Parent == Players then
				table.insert(activeRecipients, player)
			end
		end
		if #activeRecipients == 0 then
			return
		end
		if RunService:IsStudio() then
			warn("[MegMo Cutscene] Teleports cannot run in Studio playtests. Publish the experience and test it in the Roblox app.")
			return
		end
		local success, err = pcall(function()
			TeleportService:TeleportAsync(placeId, activeRecipients)
		end)
		if not success then
			warn("[MegMo Cutscene] Teleport failed: " .. tostring(err))
		end
	end)
end

local function getPlayerRigTemplateName()
	local configuredName = tostring(settingValue("PlayerRigName", ""))
	if configuredName ~= "" then
		return configuredName
	end
	local firstRig = data.RigAnimations and data.RigAnimations[1]
	return firstRig and tostring(firstRig.RigName or "") or ""
end

local function isRigCFrameTrack(track, rigName)
	if not track or track.targetScope ~= "RigProperty" then
		return false
	end
	if track.propertyName ~= "CFrame" and track.valueType ~= "CFrame" and track.name ~= "CFrame" then
		return false
	end
	if rigName == "" then
		return true
	end
	return track.rigName == rigName or track.part0 == rigName or track.parentTrackName == rigName
end

local function getFinalRigCFrame()
	local project = data.Project or data
	local rigName = getPlayerRigTemplateName()
	local paths = {}
	for _, track in ipairs(project.tracks or {}) do
		if isRigCFrameTrack(track, rigName) then
			paths[track.path] = true
		end
	end

	local bestFrame = -1
	local bestCFrame = nil
	for frameText, pose in pairs(project.frames or {}) do
		local frame = tonumber(frameText)
		if frame and type(pose) == "table" then
			for path in pairs(paths) do
				local entry = pose[path]
				local value = type(entry) == "table" and entry.value or entry
				local cframe = decodeCFrame(value)
				if cframe and frame >= bestFrame then
					bestFrame = frame
					bestCFrame = cframe
				end
			end
		end
	end
	return bestCFrame
end

local function movePlayerToCutsceneEnd(player)
	if not player or settingValue("PlayerEndMode", "ReturnToStart") ~= "MoveToCutsceneEnd" then
		return
	end
	local targetCFrame = getFinalRigCFrame()
	local character = player.Character
	if not targetCFrame or not character or not character:IsA("Model") then
		return
	end
	character:PivotTo(targetCFrame)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function getRigRootPart(rig)
	if not rig then
		return nil
	end
	local root = rig:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	if rig.PrimaryPart and rig.PrimaryPart:IsA("BasePart") then
		return rig.PrimaryPart
	end
	for _, descendant in ipairs(rig:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function findRig(info)
	local rig = resolvePath(info.TargetPath or "")
	if rig then
		return rig
	end
	local rigName = tostring(info.RigName or "")
	if rigName ~= "" then
		return workspace:FindFirstChild(rigName, true)
	end
	return nil
end

local function stabilizeCutsceneRigs()
	for _, info in ipairs(data.RigAnimations or {}) do
		local rig = findRig(info)
		local rootPart = getRigRootPart(rig)
		if rig and rootPart then
			rootPart.Anchored = true
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
			local humanoid = rig:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.AutoRotate = false
				humanoid.PlatformStand = true
			end
			for _, descendant in ipairs(rig:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant.CanCollide = false
				end
			end
		elseif info.RigName then
			warn("[MegMo Cutscene] Could not stabilize rig before trigger: " .. tostring(info.RigName))
		end
	end
end

stabilizeCutsceneRigs()

local function getInstanceCFrame(instance)
	if not instance or not instance.Parent then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance.CFrame
	end
	if instance:IsA("Model") then
		return instance:GetPivot()
	end
	if instance:IsA("Attachment") then
		return instance.WorldCFrame
	end
	return nil
end

local function setInstanceCFrame(instance, cframe)
	if not instance or not instance.Parent or typeof(cframe) ~= "CFrame" then
		return false
	end
	if instance:IsA("BasePart") then
		instance.CFrame = cframe
		return true
	end
	if instance:IsA("Model") then
		instance:PivotTo(cframe)
		return true
	end
	if instance:IsA("Attachment") then
		local parent = instance.Parent
		if parent and parent:IsA("BasePart") then
			parent.CFrame = cframe * instance.CFrame:Inverse()
			return true
		end
	end
	return false
end

local function collectBaseParts(target)
	local parts = {}
	if not target then
		return parts
	end
	if target:IsA("BasePart") then
		table.insert(parts, target)
	elseif target:IsA("Model") or target:IsA("Folder") then
		for _, descendant in ipairs(target:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
	end
	return parts
end

local function stabilizeCutsceneProp(target, cframe)
	if not target or settingValue("FreezeCutsceneProps", true) ~= true then
		return
	end
	if typeof(cframe) == "CFrame" then
		setInstanceCFrame(target, cframe)
	end
	for _, part in ipairs(collectBaseParts(target)) do
		if part:GetAttribute(CUTSCENE_ORIGINAL_ANCHORED_ATTRIBUTE) == nil then
			part:SetAttribute(CUTSCENE_ORIGINAL_ANCHORED_ATTRIBUTE, part.Anchored)
		end
		if part:GetAttribute(CUTSCENE_ORIGINAL_CAN_COLLIDE_ATTRIBUTE) == nil then
			part:SetAttribute(CUTSCENE_ORIGINAL_CAN_COLLIDE_ATTRIBUTE, part.CanCollide)
		end
		if part:GetAttribute(CUTSCENE_ORIGINAL_CAN_TOUCH_ATTRIBUTE) == nil then
			part:SetAttribute(CUTSCENE_ORIGINAL_CAN_TOUCH_ATTRIBUTE, part.CanTouch)
		end
		if part:GetAttribute(CUTSCENE_ORIGINAL_CAN_QUERY_ATTRIBUTE) == nil then
			part:SetAttribute(CUTSCENE_ORIGINAL_CAN_QUERY_ATTRIBUTE, part.CanQuery)
		end
		if part:GetAttribute(CUTSCENE_ORIGINAL_MASSLESS_ATTRIBUTE) == nil then
			part:SetAttribute(CUTSCENE_ORIGINAL_MASSLESS_ATTRIBUTE, part.Massless)
		end
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
	end
end

local function stabilizeCutsceneProps()
	-- Attachment props are now held by generated CFrame keys during playback.
	-- Do not anchor them on the server at game start, because that makes the
	-- prop permanently locked before the attach/detach timeline can take over.
end

stabilizeCutsceneProps()

local function findTriggerPart()
	local path = tostring(settingValue("TriggerPartPath", "Workspace.CutsceneTrigger"))
	return resolvePath(path) or workspace:FindFirstChild(path, true)
end

local function findTriggerPrompt()
	local path = tostring(settingValue("TriggerPromptPath", "Workspace.CutscenePrompt.ProximityPrompt"))
	local target = resolvePath(path) or workspace:FindFirstChild(path, true)
	if target and target:IsA("ProximityPrompt") then
		return target
	end
	if target then
		return target:FindFirstChildWhichIsA("ProximityPrompt", true)
	end
	return nil
end

local function playerFromTouchedPart(hit)
	local character = hit and hit:FindFirstAncestorOfClass("Model")
	return character and Players:GetPlayerFromCharacter(character) or nil
end

local function playFor(player)
	local playbackMode = settingValue("Playback", "LocalPlayer")
	if playbackMode ~= "Everyone" and not player then
		warn("[MegMo Cutscene] Local-player playback needs a player. Use PartTouched or call playFor(player).")
		return
	end
	if settingValue("Replay", "Once") ~= "EveryTime" then
		if playbackMode == "Everyone" then
			if hasPlayedForEveryone then
				return
			end
			hasPlayedForEveryone = true
		else
			local userId = player.UserId
			if playedLocalUserIds[userId] then
				return
			end
			playedLocalUserIds[userId] = true
		end
	end
	local triggeringUserId = player and player.UserId or 0
	if playbackMode == "Everyone" then
		remote:FireAllClients(triggeringUserId)
	else
		remote:FireClient(player, triggeringUserId)
	end
	if player
		and hidePromptRemote
		and hidePromptRemote:IsA("RemoteEvent")
		and settingValue("HidePromptAfterTrigger", true) == true
		and settingValue("Trigger", "Manual") == "ProximityPrompt"
		and settingValue("Replay", "Once") ~= "EveryTime" then
		local prompt = findTriggerPrompt()
		if prompt then
			hidePromptRemote:FireClient(player, prompt)
		end
	end
	if player
		and settingValue("RigTargetMode", "WorkspaceRig") == "TriggeringPlayerClone"
		and settingValue("AfterCutsceneAction", "StayHere") ~= "Teleport" then
		task.delay(getCutsceneCompletionDelay(), function()
			movePlayerToCutsceneEnd(player)
		end)
	end
	scheduleTeleportAfterCutscene(player)
end

local triggerType = settingValue("Trigger", "Manual")
if triggerType == "PartTouched" then
	local triggerPart = findTriggerPart()
	if triggerPart and triggerPart:IsA("BasePart") then
		triggerPart.Touched:Connect(function(hit)
			local player = playerFromTouchedPart(hit)
			if player then
				playFor(player)
			end
		end)
	else
		warn("[MegMo Cutscene] Could not find trigger part: " .. tostring(settingValue("TriggerPartPath", "Workspace.CutsceneTrigger")))
	end
elseif triggerType == "ProximityPrompt" then
	local prompt = findTriggerPrompt()
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function(player)
			playFor(player)
		end)
	else
		warn("[MegMo Cutscene] Could not find proximity prompt: " .. tostring(settingValue("TriggerPromptPath", "Workspace.CutscenePrompt.ProximityPrompt")))
	end
elseif triggerType == "Timed" or triggerType == "AutoStart" then
	task.delay(tonumber(settingValue("DelaySeconds", 0)) or 0, function()
		if settingValue("Playback", "LocalPlayer") == "Everyone" then
			playFor(nil)
			return
		end
		local currentPlayers = Players:GetPlayers()
		if #currentPlayers == 0 then
			playFor(Players.PlayerAdded:Wait())
			return
		end
		for _, player in ipairs(currentPlayers) do
			playFor(player)
		end
	end)
else
	print("[MegMo Cutscene] Manual trigger ready. Call playFor(player) from this script.")
end
