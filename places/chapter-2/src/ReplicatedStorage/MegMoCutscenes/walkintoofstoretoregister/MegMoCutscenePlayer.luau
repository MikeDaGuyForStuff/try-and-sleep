local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local TextService = game:GetService("TextService")
local ContentProvider = game:GetService("ContentProvider")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local MegMoCutscenePlayer = {}
local eventSignal = Instance.new("BindableEvent")
local namedEventCallbacks = {}
local activeCutsceneData = nil
local ATTACH_ATTRIBUTE = "MegMoAttachment"
local ATTACH_LIMB_PATH_ATTRIBUTE = "MegMoLimbPath"
local ATTACH_OBJECT_PATH_ATTRIBUTE = "MegMoAttachedObjectPath"
local ATTACH_WAS_ANCHORED_ATTRIBUTE = "MegMoPart1WasAnchored"
local ATTACH_WELD_ATTRIBUTE = "MegMoAttachmentWeld"
local ATTACH_OBJECT_VALUE_NAME = "MegMoAttachedObject"
local ATTACH_EVENT_KIND = "MegMoAttachmentEvent"
local CUTSCENE_ORIGINAL_ANCHORED_ATTRIBUTE = "MegMoCutsceneOriginalAnchored"
local CUTSCENE_ORIGINAL_CAN_COLLIDE_ATTRIBUTE = "MegMoCutsceneOriginalCanCollide"
local CUTSCENE_ORIGINAL_CAN_TOUCH_ATTRIBUTE = "MegMoCutsceneOriginalCanTouch"
local CUTSCENE_ORIGINAL_CAN_QUERY_ATTRIBUTE = "MegMoCutsceneOriginalCanQuery"
local CUTSCENE_ORIGINAL_MASSLESS_ATTRIBUTE = "MegMoCutsceneOriginalMassless"

local function ensureEventsFolder()
	local folder = script.Parent:FindFirstChild("CutsceneEvents")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CutsceneEvents"
		folder.Parent = script.Parent
	end
	if not folder:FindFirstChild("Event") then
		local genericEvent = Instance.new("BindableEvent")
		genericEvent.Name = "Event"
		genericEvent.Parent = folder
	end
	return folder
end

function MegMoCutscenePlayer.OnEvent(callback)
	if type(callback) ~= "function" then
		return nil
	end
	return eventSignal.Event:Connect(callback)
end

function MegMoCutscenePlayer.BindEvent(eventName, callback)
	if type(callback) ~= "function" then
		return nil
	end
	local key = tostring(eventName or "Event")
	namedEventCallbacks[key] = namedEventCallbacks[key] or {}
	table.insert(namedEventCallbacks[key], callback)
	return {
		Disconnect = function()
			local callbacks = namedEventCallbacks[key]
			if not callbacks then
				return
			end
			for index = #callbacks, 1, -1 do
				if callbacks[index] == callback then
					table.remove(callbacks, index)
					break
				end
			end
		end,
	}
end

local function settingValue(name, fallback)
	local settingsFolder = script.Parent:FindFirstChild("CutsceneSettings")
	local valueObject = settingsFolder and settingsFolder:FindFirstChild(name)
	if valueObject and valueObject:IsA("ValueBase") then
		return valueObject.Value
	end
	return fallback
end

local function createPlaybackOverlay(allowSkip, skipState)
	if not RunService:IsClient() then
		return nil, nil
	end
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil, nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MegMoCutsceneOverlay"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	local fade = Instance.new("Frame")
	fade.Name = "Fade"
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BackgroundTransparency = 1
	fade.BorderSizePixel = 0
	fade.Size = UDim2.fromScale(1, 1)
	fade.ZIndex = 1
	fade.Parent = gui
	if allowSkip then
		local skip = Instance.new("TextButton")
		skip.Name = "SkipButton"
		skip.Active = true
		skip.AnchorPoint = Vector2.new(1, 0)
		skip.AutoButtonColor = true
		skip.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
		skip.BackgroundTransparency = 0.05
		skip.BorderSizePixel = 0
		skip.Font = Enum.Font.GothamSemibold
		skip.Position = UDim2.new(1, -24, 1, -72)
		skip.Size = UDim2.fromOffset(112, 38)
		skip.Text = "Skip"
		skip.TextColor3 = Color3.fromRGB(255, 255, 255)
		skip.TextSize = 18
		skip.TextTransparency = 0
		skip.Visible = true
		skip.ZIndex = 100000
		skip.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = skip
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(134, 96, 255)
		stroke.Thickness = 1
		stroke.Transparency = 0.15
		stroke.Parent = skip
		skip.Activated:Connect(function()
			skipState.requested = true
		end)
	end
	return gui, fade
end

local function runFade(frame, fromTransparency, toTransparency, seconds, skipState)
	seconds = math.max(0, tonumber(seconds) or 0)
	if not frame then
		return
	end
	if seconds <= 0 then
		frame.BackgroundTransparency = toTransparency
		return
	end
	local stepEvent = RunService:IsClient() and RunService.RenderStepped or RunService.Heartbeat
	local startClock = os.clock()
	while true do
		local alpha = math.clamp((os.clock() - startClock) / seconds, 0, 1)
		frame.BackgroundTransparency = fromTransparency + (toTransparency - fromTransparency) * alpha
		if alpha >= 1 or (skipState and skipState.requested) then
			break
		end
		stepEvent:Wait()
	end
end

local function decodeValue(value)
	if type(value) ~= "table" then
		return value
	end
	if value.type == "CFrame" and type(value.components) == "table" then
		return CFrame.new(table.unpack(value.components))
	end
	if value.type == "Color3" then
		return Color3.new(value.r or 1, value.g or 1, value.b or 1)
	end
	if value.type == "Vector3" then
		return Vector3.new(value.x or 0, value.y or 0, value.z or 0)
	end
	if value.type == "Vector2" then
		return Vector2.new(value.x or 0, value.y or 0)
	end
	if value.type == "NumberRange" then
		return NumberRange.new(value.min or 0, value.max or value.min or 0)
	end
	if value.type == "NumberSequence" and type(value.keypoints) == "table" then
		local keypoints = {}
		for _, keypoint in ipairs(value.keypoints) do
			table.insert(keypoints, NumberSequenceKeypoint.new(
				keypoint.time or 0,
				keypoint.value or 0,
				keypoint.envelope or 0
			))
		end
		return #keypoints > 0 and NumberSequence.new(keypoints) or NumberSequence.new(0)
	end
	if value.type == "ColorSequence" and type(value.keypoints) == "table" then
		local keypoints = {}
		for _, keypoint in ipairs(value.keypoints) do
			local color = decodeValue(keypoint.value)
			if typeof(color) ~= "Color3" then
				color = Color3.new(1, 1, 1)
			end
			table.insert(keypoints, ColorSequenceKeypoint.new(keypoint.time or 0, color))
		end
		return #keypoints > 0 and ColorSequence.new(keypoints) or ColorSequence.new(Color3.new(1, 1, 1))
	end
	if value.type == "EnumItem" and type(value.enumType) == "string" and type(value.name) == "string" then
		local enumName = value.enumType:match("^Enum%.(.+)$") or value.enumType
		local enum = Enum[enumName]
		if enum and enum[value.name] then
			return enum[value.name]
		end
	end
	local result = {}
	for key, child in pairs(value) do
		result[key] = decodeValue(child)
	end
	return result
end

local function resolvePath(path)
	if type(path) ~= "string" or path == "" or path == "Missing" then
		return nil
	end
	local parts = string.split(path, ".")
	local current
	local index = 1
	if parts[1] == "game" then
		current = game
		index = 2
	elseif parts[1] == "Workspace" then
		current = workspace
		index = 2
	elseif parts[1] == "ReplicatedStorage" then
		current = ReplicatedStorage
		index = 2
	elseif parts[1] == "SoundService" then
		current = SoundService
		index = 2
	elseif parts[1] == "Lighting" then
		current = Lighting
		index = 2
	elseif parts[1] == "workspace" then
		current = workspace
		index = 2
	else
		current = game
	end
	for i = index, #parts do
		current = current and current:FindFirstChild(parts[i])
	end
	return current
end

local function collectTrackKeys(project, predicate)
	local buckets = {}
	for _, track in ipairs(project.tracks or {}) do
		if predicate(track) then
			buckets[track.path] = {
				track = track,
				keys = {},
			}
		end
	end
	for frameText, pose in pairs(project.frames or {}) do
		local frame = tonumber(frameText)
		if frame then
			for path, entry in pairs(pose) do
				local bucket = buckets[path]
				if bucket then
					table.insert(bucket.keys, {
						frame = frame,
						value = decodeValue(type(entry) == "table" and entry.value or entry),
						easing = type(entry) == "table" and entry.easing or nil,
					})
				end
			end
		end
	end
	for _, bucket in pairs(buckets) do
		table.sort(bucket.keys, function(a, b)
			return a.frame < b.frame
		end)
	end
	return buckets
end

local function getProjectLastKeyframe(project)
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

local function lerpValue(a, b, alpha)
	if typeof(a) == "CFrame" and typeof(b) == "CFrame" then
		return a:Lerp(b, alpha)
	end
	if typeof(a) == "Color3" and typeof(b) == "Color3" then
		return a:Lerp(b, alpha)
	end
	if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
		return a:Lerp(b, alpha)
	end
	if typeof(a) == "Vector2" and typeof(b) == "Vector2" then
		return a:Lerp(b, alpha)
	end
	if typeof(a) == "NumberRange" and typeof(b) == "NumberRange" then
		return NumberRange.new(
			a.Min + (b.Min - a.Min) * alpha,
			a.Max + (b.Max - a.Max) * alpha
		)
	end
	if type(a) == "number" and type(b) == "number" then
		return a + (b - a) * alpha
	end
	if type(a) == "table" and type(b) == "table" then
		local result = {}
		for key, value in pairs(a) do
			result[key] = value
		end
		for key, value in pairs(b) do
			result[key] = lerpValue(a[key], value, alpha)
		end
		return result
	end
	return alpha < 1 and a or b
end

local function evaluate(keys, frame)
	if #keys == 0 then
		return nil
	end
	if frame <= keys[1].frame then
		return keys[1].value
	end
	for index = 1, #keys - 1 do
		local current = keys[index]
		local nextKey = keys[index + 1]
		if frame >= current.frame and frame <= nextKey.frame then
			local span = math.max(1, nextKey.frame - current.frame)
			return lerpValue(current.value, nextKey.value, math.clamp((frame - current.frame) / span, 0, 1))
		end
	end
	return keys[#keys].value
end

local function evaluateHeld(keys, frame)
	if type(keys) ~= "table" or #keys == 0 or frame < keys[1].frame then
		return nil
	end
	local value = keys[1].value
	for _, key in ipairs(keys) do
		if key.frame <= frame then
			value = key.value
		else
			break
		end
	end
	return value
end

local function applyCameraValue(camera, value)
	if not camera or value == nil then
		return
	end
	if typeof(value) == "CFrame" then
		camera.CFrame = value
		return
	end
	if type(value) ~= "table" then
		return
	end
	local cframe = value.cframe or value.CFrame
	if typeof(cframe) == "CFrame" then
		camera.CFrame = cframe
	end
	local focus = value.focus or value.Focus
	if typeof(focus) == "CFrame" then
		camera.Focus = focus
	end
	local fov = value.fieldOfView or value.FieldOfView
	if type(fov) == "number" then
		camera.FieldOfView = math.clamp(fov, 1, 120)
	end
end

local CUTSCENE_SOUND_PREFIX = "MegMoCutsceneSound_"

local function playSound(track, value, context)
	if type(value) ~= "table" then
		return
	end

	local sourceSound = resolvePath(track.targetPath or "")
	if sourceSound and not sourceSound:IsA("Sound") then
		sourceSound = nil
	end

	local soundId = type(value.soundId) == "string" and value.soundId or ""
	if soundId == "" and sourceSound then
		soundId = sourceSound.SoundId
	end
	if soundId == "" then
		warn("[MegMoCutscenePlayer] Sound key has no SoundId: " .. tostring(track.name or track.path or "Sound"))
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = CUTSCENE_SOUND_PREFIX .. tostring(track.name or "Sound")
	sound.SoundId = soundId
	sound.Volume = sourceSound and sourceSound.Volume or 1
	sound.PlaybackSpeed = sourceSound and sourceSound.PlaybackSpeed or 1
	sound.RollOffMinDistance = sourceSound and sourceSound.RollOffMinDistance or sound.RollOffMinDistance
	sound.RollOffMaxDistance = sourceSound and sourceSound.RollOffMaxDistance or sound.RollOffMaxDistance
	sound.RollOffMode = sourceSound and sourceSound.RollOffMode or sound.RollOffMode

	if type(value.volume) == "number" then
		sound.Volume = math.clamp(value.volume, 0, 10)
	end
	if type(value.playbackSpeed) == "number" then
		sound.PlaybackSpeed = math.clamp(value.playbackSpeed, 0.05, 20)
	end
	if type(value.rollOffMinDistance) == "number" then
		sound.RollOffMinDistance = math.max(0, value.rollOffMinDistance)
	end
	if type(value.rollOffMaxDistance) == "number" then
		sound.RollOffMaxDistance = math.max(sound.RollOffMinDistance, value.rollOffMaxDistance)
	end
	if typeof(value.rollOffMode) == "EnumItem" and value.rollOffMode.EnumType == Enum.RollOffMode then
		sound.RollOffMode = value.rollOffMode
	elseif type(value.rollOffMode) == "string" and Enum.RollOffMode[value.rollOffMode] then
		sound.RollOffMode = Enum.RollOffMode[value.rollOffMode]
	end
	if context then
		context.activeSounds = context.activeSounds or {}
		table.insert(context.activeSounds, sound)
	end

	local baseVolume = math.clamp(tonumber(sound.Volume) or 1, 0, 10)
	local startOffsetSeconds = math.max(0, tonumber(value.startOffsetSeconds or value.startOffset or value.trimStartSeconds) or 0)
	local endTrimSeconds = math.max(0, tonumber(value.endTrimSeconds or value.endTrim or value.trimEndSeconds) or 0)
	local fadeInSeconds = math.max(0, tonumber(value.fadeInSeconds or value.fadeIn or value.audioFadeInSeconds) or 0)
	local fadeOutSeconds = math.max(0, tonumber(value.fadeOutSeconds or value.fadeOut or value.audioFadeOutSeconds) or 0)
	local explicitClipDurationSeconds = math.max(0, tonumber(value.clipDurationSeconds or value.timelineClipDurationSeconds or value.stopDurationSeconds) or 0)
	local playbackSpeed = math.max(0.05, tonumber(sound.PlaybackSpeed) or 1)
	local trimStopScheduled = false
	local fadeStartClock = os.clock()
	local fadeConnection = nil
	local function stopVolumeFade()
		if fadeConnection then
			fadeConnection:Disconnect()
			fadeConnection = nil
		end
	end
	local function getClipDurationSeconds()
		if explicitClipDurationSeconds > 0 then
			local duration = tonumber(sound.TimeLength) or 0
			if duration > 0 then
				local sourceClipDuration = math.max(0, (duration - startOffsetSeconds - endTrimSeconds) / playbackSpeed)
				return math.min(explicitClipDurationSeconds, sourceClipDuration)
			end
			return explicitClipDurationSeconds
		end
		local duration = tonumber(sound.TimeLength) or 0
		if duration <= 0 then
			return nil
		end
		return math.max(0, (duration - startOffsetSeconds - endTrimSeconds) / playbackSpeed)
	end
	local function updateVolumeFade()
		if not sound.Parent then
			stopVolumeFade()
			return
		end
		local elapsedSeconds = math.max(0, os.clock() - fadeStartClock)
		local scale = 1
		if fadeInSeconds > 0 then
			scale = math.min(scale, math.clamp(elapsedSeconds / fadeInSeconds, 0, 1))
		end
		local clipDurationSeconds = getClipDurationSeconds()
		if fadeOutSeconds > 0 and clipDurationSeconds and clipDurationSeconds > 0 then
			scale = math.min(scale, math.clamp((clipDurationSeconds - elapsedSeconds) / fadeOutSeconds, 0, 1))
		end
		sound.Volume = baseVolume * math.clamp(scale, 0, 1)
	end
	local function startVolumeFade()
		updateVolumeFade()
		if fadeInSeconds > 0 or fadeOutSeconds > 0 then
			stopVolumeFade()
			fadeConnection = RunService.Heartbeat:Connect(updateVolumeFade)
		end
	end
	local function applyStartOffset()
		if startOffsetSeconds <= 0 or not sound.Parent then
			return
		end
		pcall(function()
			sound.TimePosition = startOffsetSeconds
		end)
	end
	local function scheduleTrimStop()
		if trimStopScheduled or not sound.Parent then
			return
		end
		local clipDurationSeconds = getClipDurationSeconds()
		if clipDurationSeconds then
			if clipDurationSeconds <= 0 then
				stopVolumeFade()
				sound:Destroy()
				return
			end
			trimStopScheduled = true
			task.delay(clipDurationSeconds, function()
				if sound.Parent then
					stopVolumeFade()
					sound:Destroy()
				end
			end)
			return
		end
		local duration = tonumber(sound.TimeLength) or 0
		if duration <= 0 then
			return
		end
		local endPosition = math.max(0, duration - endTrimSeconds)
		local remainingSeconds = math.max(0, (endPosition - startOffsetSeconds) / playbackSpeed)
		if remainingSeconds <= 0 then
			stopVolumeFade()
			sound:Destroy()
			return
		end
		trimStopScheduled = true
		task.delay(remainingSeconds, function()
			if sound.Parent then
				stopVolumeFade()
				sound:Destroy()
			end
		end)
	end
	pcall(function()
		sound.Loaded:Connect(function()
			applyStartOffset()
			scheduleTrimStop()
		end)
	end)

	sound.Parent = SoundService
	startVolumeFade()
	sound:Play()
	applyStartOffset()
	scheduleTrimStop()

	task.delay(0.1, function()
		if sound.Parent and not sound.IsPlaying then
			applyStartOffset()
			scheduleTrimStop()
			pcall(function()
				SoundService:PlayLocalSound(sound)
			end)
			applyStartOffset()
			scheduleTrimStop()
		end
	end)

	local endedConnection
	endedConnection = sound.Ended:Connect(function()
		if endedConnection then
			endedConnection:Disconnect()
		end
		stopVolumeFade()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	task.delay(math.max(120, (sound.TimeLength > 0 and sound.TimeLength or 0) + 2), function()
		if endedConnection then
			endedConnection:Disconnect()
			endedConnection = nil
		end
		if sound.Parent then
			stopVolumeFade()
			sound:Destroy()
		end
	end)
end

local function stopActiveCutsceneSounds(context)
	for _, sound in ipairs((context and context.activeSounds) or {}) do
		if sound and sound.Parent then
			pcall(function()
				sound:Stop()
			end)
			pcall(function()
				sound:Destroy()
			end)
		end
	end
	if context then
		context.activeSounds = {}
	end
	for _, child in ipairs(SoundService:GetChildren()) do
		if child:IsA("Sound") and string.sub(child.Name, 1, #CUTSCENE_SOUND_PREFIX) == CUTSCENE_SOUND_PREFIX then
			pcall(function()
				child:Stop()
			end)
			pcall(function()
				child:Destroy()
			end)
		end
	end
end

local SCREEN_EFFECT_TYPE = "Screen Effect"
local VIGNETTE_IMAGE = "rbxassetid://4576475446"
local GRAIN_LIGHT_IMAGE = "rbxassetid://460107958"
local GRAIN_DARK_IMAGE = "rbxassetid://460200108"

local SCREEN_EFFECT_DEFAULTS = {
	CameraFlash = {
		enabled = true,
		color = Color3.fromRGB(255, 255, 255),
		transparency = 0.15,
	},
	Letterbox = {
		enabled = true,
		barSize = 0.12,
		color = Color3.fromRGB(0, 0, 0),
		transparency = 0,
	},
	Vignette = {
		enabled = true,
		tone = "Dark",
		transparency = 0.18,
	},
	FilmGrain = {
		enabled = true,
		intensity = 0.35,
		transparency = 0.2,
	},
	Subtitle = {
		enabled = true,
		text = "Your subtitle goes here",
		font = "GothamSemibold",
		textSize = 28,
		textColor = Color3.fromRGB(245, 248, 255),
		backgroundColor = Color3.fromRGB(0, 0, 0),
		textTransparency = 0,
		backgroundTransparency = 0.28,
		textEnabled = true,
		backgroundEnabled = true,
		enterTransition = "Fade",
		exitTransition = "Fade",
		enterDuration = 0.15,
		exitDuration = 0.15,
		positionPreset = "Bottom",
		positionX = 0.5,
		positionY = 0.88,
		width = 0.62,
		autoFit = true,
	},
	ColorWash = {
		enabled = true,
		color = Color3.fromRGB(129, 80, 255),
		transparency = 0.72,
	},
	DepthOfField = {
		enabled = true,
		focusDistance = 10,
		inFocusRadius = 1.25,
		nearIntensity = 0.15,
		farIntensity = 0.9,
	},
	Fade = {
		enabled = true,
		color = Color3.fromRGB(0, 0, 0),
		transparency = 0.5,
	},
}

local function cloneTable(value)
	local clone = {}
	for key, child in pairs(value or {}) do
		if type(child) == "table" then
			clone[key] = cloneTable(child)
		else
			clone[key] = child
		end
	end
	return clone
end

local function normalizeScreenEffectType(effectType)
	local raw = tostring(effectType or "")
	if raw == "Film Grain" then
		raw = "FilmGrain"
	elseif raw == "Camera Flash" then
		raw = "CameraFlash"
	elseif raw == "Color Wash" then
		raw = "ColorWash"
	elseif raw == "Depth Of Field" or raw == "Depth of Field" then
		raw = "DepthOfField"
	end
	return SCREEN_EFFECT_DEFAULTS[raw] and raw or "Fade"
end

local function numberValue(value, fallback, minValue, maxValue)
	local number = tonumber(value)
	if not number then
		number = fallback
	end
	if minValue ~= nil or maxValue ~= nil then
		number = math.clamp(number, minValue or -math.huge, maxValue or math.huge)
	end
	return number
end

local function boolValue(value, fallback)
	if type(value) == "boolean" then
		return value
	end
	if value == nil then
		return fallback
	end
	local text = string.lower(tostring(value))
	return text == "true" or text == "1" or text == "yes" or text == "on" or text == "enabled"
end

local function colorValue(value, fallback)
	if typeof(value) == "Color3" then
		return value
	end
	return fallback
end

local function normalizeScreenEffectValue(effectType, value)
	local effectId = normalizeScreenEffectType(effectType)
	local normalized = cloneTable(SCREEN_EFFECT_DEFAULTS[effectId])
	if type(value) ~= "table" then
		return normalized
	end

	normalized.enabled = boolValue(value.enabled, normalized.enabled)
	if effectId == "CameraFlash" or effectId == "ColorWash" or effectId == "Fade" then
		normalized.color = colorValue(value.color, normalized.color)
		normalized.transparency = numberValue(value.transparency, normalized.transparency, 0, 1)
	elseif effectId == "Letterbox" then
		normalized.barSize = numberValue(value.barSize, normalized.barSize, 0, 0.4)
		normalized.color = colorValue(value.color, normalized.color)
		normalized.transparency = numberValue(value.transparency, normalized.transparency, 0, 1)
	elseif effectId == "Vignette" then
		normalized.tone = tostring(value.tone or normalized.tone) == "Light" and "Light" or "Dark"
		normalized.transparency = numberValue(value.transparency, normalized.transparency, 0, 1)
	elseif effectId == "FilmGrain" then
		normalized.intensity = numberValue(value.intensity, normalized.intensity, 0, 1)
		normalized.transparency = numberValue(value.transparency, normalized.transparency, 0, 1)
	elseif effectId == "DepthOfField" then
		normalized.focusDistance = numberValue(value.focusDistance, normalized.focusDistance, 0, 1000)
		normalized.inFocusRadius = numberValue(value.inFocusRadius, normalized.inFocusRadius, 0, 1000)
		normalized.nearIntensity = numberValue(value.nearIntensity, normalized.nearIntensity, 0, 1)
		normalized.farIntensity = numberValue(value.farIntensity, normalized.farIntensity, 0, 1)
	elseif effectId == "Subtitle" then
		normalized.text = string.sub(tostring(value.text or normalized.text), 1, 240)
		normalized.font = tostring(value.font or normalized.font)
		normalized.textSize = numberValue(value.textSize, normalized.textSize, 8, 80)
		normalized.textColor = colorValue(value.textColor, normalized.textColor)
		normalized.backgroundColor = colorValue(value.backgroundColor, normalized.backgroundColor)
		normalized.textTransparency = numberValue(value.textTransparency, normalized.textTransparency, 0, 1)
		normalized.backgroundTransparency = numberValue(value.backgroundTransparency, normalized.backgroundTransparency, 0, 1)
		normalized.textEnabled = boolValue(value.textEnabled, normalized.textEnabled)
		normalized.backgroundEnabled = boolValue(value.backgroundEnabled, normalized.backgroundEnabled)
		normalized.enterTransition = tostring(value.enterTransition or normalized.enterTransition)
		normalized.exitTransition = tostring(value.exitTransition or normalized.exitTransition)
		normalized.enterDuration = numberValue(value.enterDuration, normalized.enterDuration, 0, 5)
		normalized.exitDuration = numberValue(value.exitDuration, normalized.exitDuration, 0, 5)
		normalized.positionPreset = tostring(value.positionPreset or normalized.positionPreset)
		normalized.positionX = numberValue(value.positionX, normalized.positionX, 0, 1)
		normalized.positionY = numberValue(value.positionY, normalized.positionY, 0, 1)
		normalized.width = numberValue(value.width, normalized.width, 0.2, 1)
		normalized.autoFit = boolValue(value.autoFit, normalized.autoFit)
		normalized._transitionAlpha = numberValue(value._transitionAlpha, 1, 0, 1)
		normalized._transitionPreset = tostring(value._transitionPreset or "None")
	end

	return normalized
end

local function enumFont(fontName)
	local ok, font = pcall(function()
		return Enum.Font[tostring(fontName or "GothamSemibold")]
	end)
	return ok and font or Enum.Font.GothamSemibold
end

local function getSubtitleViewportWidth(label)
	local parent = label and label.Parent
	if parent and parent.AbsoluteSize.X > 0 then
		return parent.AbsoluteSize.X
	end
	local camera = workspace.CurrentCamera
	if camera then
		return math.max(320, camera.ViewportSize.X)
	end
	return 1280
end

local function getSubtitleHeight(label, text, font, textSize, widthScale, scale, autoFit)
	local displayTextSize = math.max(1, textSize)
	local baseHeight = math.max(34, displayTextSize + 18)
	if autoFit == false then
		return baseHeight
	end
	local viewportWidth = getSubtitleViewportWidth(label)
	local pixelWidth = math.max(120, viewportWidth * math.clamp(widthScale * scale, 0.1, 1.2))
	local bounds = nil
	local ok = pcall(function()
		bounds = TextService:GetTextSize(tostring(text or ""), displayTextSize, font, Vector2.new(math.max(24, pixelWidth - 24), math.huge))
	end)
	if not ok or typeof(bounds) ~= "Vector2" then
		return baseHeight
	end
	return math.ceil(math.max(baseHeight, bounds.Y + math.max(18, displayTextSize * 0.45)))
end

local function createGuiObject(className, properties)
	local instance = Instance.new(className)
	for property, value in pairs(properties or {}) do
		instance[property] = value
	end
	return instance
end

local function createCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 0)
	corner.Parent = parent
end

local function ensureScreenEffectsGui(context)
	if not RunService:IsClient() then
		return nil
	end
	if context.screenGui and context.screenGui.Parent then
		return context.screenGui
	end
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer and (localPlayer:FindFirstChildOfClass("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5))
	if not playerGui then
		return nil
	end

	local gui = createGuiObject("ScreenGui", {
		Name = "MegMoCutsceneScreenEffects",
		DisplayOrder = 50000,
		Enabled = true,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local root = createGuiObject("Frame", {
		Name = "Root",
		Parent = gui,
		Active = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50000,
	})
	gui.Parent = playerGui
	context.screenGui = gui
	context.screenRoot = root
	context.screenRefs = {}
	return gui
end

local function getScreenRoot(context)
	ensureScreenEffectsGui(context)
	return context.screenRoot
end

local function getFrameRef(context, name, zIndex)
	local refs = context.screenRefs or {}
	local ref = refs[name]
	if ref and ref.Parent then
		return ref
	end
	local root = getScreenRoot(context)
	if not root then
		return nil
	end
	ref = createGuiObject("Frame", {
		Name = name,
		Parent = root,
		Active = false,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = zIndex,
	})
	refs[name] = ref
	context.screenRefs = refs
	return ref
end

local function getImageRef(context, name, image, zIndex)
	local refs = context.screenRefs or {}
	local ref = refs[name]
	if ref and ref.Parent then
		return ref
	end
	local root = getScreenRoot(context)
	if not root then
		return nil
	end
	ref = createGuiObject("ImageLabel", {
		Name = name,
		Parent = root,
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = image,
		ImageTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		ScaleType = Enum.ScaleType.Stretch,
		Size = UDim2.fromScale(1.08, 1.08),
		Visible = false,
		ZIndex = zIndex,
	})
	refs[name] = ref
	context.screenRefs = refs
	return ref
end

local function setFullscreenFrame(context, name, value, zIndex)
	local frame = getFrameRef(context, name, zIndex)
	if not frame then
		return
	end
	frame.Visible = value ~= nil and value.enabled ~= false
	if frame.Visible then
		frame.BackgroundColor3 = colorValue(value.color, Color3.fromRGB(255, 255, 255))
		frame.BackgroundTransparency = numberValue(value.transparency, 1, 0, 1)
	end
end

local function subtitlePosition(value)
	local preset = tostring(value.positionPreset or "Bottom")
	local x = numberValue(value.positionX, 0.5, 0, 1)
	local y = numberValue(value.positionY, 0.88, 0, 1)
	local anchor = Vector2.new(0.5, 1)
	if preset == "Top" then
		x, y, anchor = 0.5, 0.14, Vector2.new(0.5, 0)
	elseif preset == "Center" then
		x, y, anchor = 0.5, 0.5, Vector2.new(0.5, 0.5)
	elseif preset == "Bottom" then
		x, y, anchor = 0.5, 0.88, Vector2.new(0.5, 1)
	else
		anchor = y < 0.34 and Vector2.new(0.5, 0) or (y > 0.66 and Vector2.new(0.5, 1) or Vector2.new(0.5, 0.5))
	end

	local alpha = numberValue(value._transitionAlpha, 1, 0, 1)
	local transition = tostring(value._transitionPreset or "None")
	if transition == "Slide Bottom" and alpha < 1 then
		y = math.clamp(y + ((1 - alpha) * 0.2), 0, 1)
	end
	return x, y, anchor, alpha, transition
end

local function easeTransitionAlpha(alpha, transition)
	alpha = math.clamp(tonumber(alpha) or 1, 0, 1)
	if transition == "Popup" or transition == "Slide Bottom" then
		return 1 - ((1 - alpha) ^ 3)
	end
	return alpha
end

local function blendTransparency(baseTransparency, alpha)
	baseTransparency = math.clamp(tonumber(baseTransparency) or 0, 0, 1)
	alpha = math.clamp(tonumber(alpha) or 1, 0, 1)
	return math.clamp(1 - alpha + (baseTransparency * alpha), 0, 1)
end

local function getSubtitleRuntimeValue(bucket, frame, fps)
	local previousKey = nil
	local nextKey = nil
	for _, key in ipairs(bucket.keys or {}) do
		if key.frame <= frame then
			previousKey = key
		elseif not nextKey then
			nextKey = key
			break
		end
	end
	if not previousKey then
		return nil
	end
	local value = normalizeScreenEffectValue("Subtitle", previousKey.value)
	if value.enabled == false then
		value._transitionAlpha = 0
		return value
	end
	local transitionAlpha = 1
	local transitionPreset = "None"
	local enterFrames = math.max(0, (tonumber(value.enterDuration) or 0) * fps)
	if enterFrames > 0 and frame <= previousKey.frame + enterFrames then
		transitionAlpha = math.min(transitionAlpha, math.clamp((frame - previousKey.frame) / enterFrames, 0, 1))
		transitionPreset = value.enterTransition or "Fade"
	end
	if nextKey and nextKey.frame > previousKey.frame then
		local nextValue = normalizeScreenEffectValue("Subtitle", nextKey.value)
		local exitFrames = math.max(0, (tonumber(value.exitDuration) or 0) * fps)
		if nextValue.enabled == false and exitFrames > 0 and frame >= nextKey.frame - exitFrames then
			transitionAlpha = math.min(transitionAlpha, math.clamp((nextKey.frame - frame) / exitFrames, 0, 1))
			transitionPreset = value.exitTransition or "Fade"
		end
	end
	value._transitionAlpha = transitionAlpha
	value._transitionPreset = transitionPreset
	return value
end

local function evaluateScreenEffectKeys(keys, frame)
	if type(keys) ~= "table" or #keys == 0 or frame < keys[1].frame then
		return nil
	end
	return evaluate(keys, frame)
end

local function applySubtitle(context, value)
	local refs = context.screenRefs or {}
	local label = refs.Subtitle
	if not label or not label.Parent then
		local root = getScreenRoot(context)
		if not root then
			return
		end
		label = createGuiObject("TextLabel", {
			Name = "Subtitle",
			Parent = root,
			Active = false,
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.28,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamSemibold,
			TextColor3 = Color3.fromRGB(245, 248, 255),
			TextScaled = false,
			TextWrapped = true,
			Visible = false,
			ZIndex = 50008,
		})
		createCorner(label, 10)
		refs.Subtitle = label
		context.screenRefs = refs
	end
	label.Visible = value ~= nil and value.enabled ~= false
	if not label.Visible then
		return
	end
	local x, y, anchor, transitionAlpha, transitionPreset = subtitlePosition(value)
	local visualAlpha = easeTransitionAlpha(transitionAlpha, transitionPreset)
	local scale = transitionPreset == "Popup" and (0.72 + (0.28 * visualAlpha)) or 1
	local opacityAlpha = transitionPreset == "Popup" and 1 or visualAlpha
	local textSize = numberValue(value.textSize, 28, 8, 80)
	local width = numberValue(value.width, 0.62, 0.2, 1)
	local text = tostring(value.text or "")
	local font = enumFont(value.font)
	local height = getSubtitleHeight(label, text, font, textSize, width, scale, value.autoFit ~= false)
	label.AnchorPoint = anchor
	label.Position = UDim2.fromScale(x, y)
	label.Size = UDim2.new(width * scale, 0, 0, height)
	label.Text = text
	label.Font = font
	label.TextWrapped = value.autoFit ~= false
	label.TextSize = textSize
	label.TextColor3 = colorValue(value.textColor, Color3.fromRGB(245, 248, 255))
	label.BackgroundColor3 = colorValue(value.backgroundColor, Color3.fromRGB(0, 0, 0))
	label.TextTransparency = value.textEnabled == false and 1 or blendTransparency(value.textTransparency, opacityAlpha)
	label.BackgroundTransparency = value.backgroundEnabled == false and 1 or blendTransparency(value.backgroundTransparency, opacityAlpha)
end

local function applyLetterbox(context, value)
	local top = getFrameRef(context, "LetterboxTop", 50007)
	local bottom = getFrameRef(context, "LetterboxBottom", 50007)
	if not top or not bottom then
		return
	end
	local visible = value ~= nil and value.enabled ~= false
	local barSize = value and numberValue(value.barSize, 0.12, 0, 0.4) or 0.12
	top.Visible = visible
	bottom.Visible = visible
	if visible then
		top.Size = UDim2.new(1, 0, barSize, 0)
		bottom.AnchorPoint = Vector2.new(0, 1)
		bottom.Position = UDim2.fromScale(0, 1)
		bottom.Size = UDim2.new(1, 0, barSize, 0)
		top.BackgroundColor3 = colorValue(value.color, Color3.fromRGB(0, 0, 0))
		bottom.BackgroundColor3 = top.BackgroundColor3
		top.BackgroundTransparency = numberValue(value.transparency, 0, 0, 1)
		bottom.BackgroundTransparency = top.BackgroundTransparency
	end
end

local function applyVignette(context, value)
	local dark = getImageRef(context, "VignetteDark", VIGNETTE_IMAGE, 50003)
	local light = getImageRef(context, "VignetteLight", VIGNETTE_IMAGE, 50003)
	if not dark or not light then
		return
	end
	local visible = value ~= nil and value.enabled ~= false
	local tone = value and value.tone == "Light" and "Light" or "Dark"
	dark.Visible = visible and tone == "Dark"
	light.Visible = visible and tone == "Light"
	dark.ImageColor3 = Color3.fromRGB(255, 255, 255)
	light.ImageColor3 = Color3.fromRGB(255, 255, 255)
	dark.ImageTransparency = value and numberValue(value.transparency, 0.18, 0, 1) or 1
	light.ImageTransparency = value and numberValue(value.transparency, 0.18, 0, 1) or 1
end

local function applyFilmGrain(context, value)
	local light = getImageRef(context, "GrainLight", GRAIN_LIGHT_IMAGE, 50004)
	local dark = getImageRef(context, "GrainDark", GRAIN_DARK_IMAGE, 50005)
	if not light or not dark then
		return
	end
	local visible = value ~= nil and value.enabled ~= false
	light.Visible = visible
	dark.Visible = visible
	if visible then
		light.Position = UDim2.fromScale(-0.1, -0.1)
		dark.Position = UDim2.fromScale(-0.1, -0.1)
		light.AnchorPoint = Vector2.new(0, 0)
		dark.AnchorPoint = Vector2.new(0, 0)
		light.Size = UDim2.fromScale(1.2, 1.2)
		dark.Size = UDim2.fromScale(1.2, 1.2)
		local transparency = numberValue(value.transparency, 1 - numberValue(value.intensity, 0.35, 0, 1), 0, 1)
		light.ImageTransparency = transparency
		dark.ImageTransparency = math.clamp(transparency - 0.04, 0, 1)
	end
end

local function applyDepthOfField(context, value)
	if not value or value.enabled == false then
		if context.depthOfField then
			context.depthOfField.Enabled = false
		end
		return
	end
	local effect = context.depthOfField
	if not effect or not effect.Parent then
		effect = Instance.new("DepthOfFieldEffect")
		effect.Name = "MegMoCutsceneDepthOfField"
		effect.Parent = Lighting
		context.depthOfField = effect
	end
	effect.Enabled = true
	effect.FocusDistance = numberValue(value.focusDistance, 10, 0, 1000)
	effect.InFocusRadius = numberValue(value.inFocusRadius, 1.25, 0, 1000)
	effect.NearIntensity = numberValue(value.nearIntensity, 0.15, 0, 1)
	effect.FarIntensity = numberValue(value.farIntensity, 0.9, 0, 1)
end

local function renderScreenEffects(context, screenEffectTracks, frame, fps)
	local values = {}
	for _, bucket in pairs(screenEffectTracks or {}) do
		local effectId = normalizeScreenEffectType(bucket.track.valueType or bucket.track.effectType or bucket.track.name)
		local rawValue = effectId == "Subtitle" and getSubtitleRuntimeValue(bucket, frame, fps) or evaluateScreenEffectKeys(bucket.keys, frame)
		if rawValue ~= nil then
			values[effectId] = normalizeScreenEffectValue(effectId, rawValue)
		end
	end

	local hasAny = next(values) ~= nil
	if hasAny then
		ensureScreenEffectsGui(context)
	end
	if context.screenGui then
		context.screenGui.Enabled = hasAny
	end

	applyLetterbox(context, values.Letterbox)
	applyVignette(context, values.Vignette)
	setFullscreenFrame(context, "Fade", values.Fade, 50001)
	setFullscreenFrame(context, "ColorWash", values.ColorWash, 50002)
	applyFilmGrain(context, values.FilmGrain)
	setFullscreenFrame(context, "CameraFlash", values.CameraFlash, 50006)
	applySubtitle(context, values.Subtitle)
	applyDepthOfField(context, values.DepthOfField)
end

local function cleanupScreenEffects(context)
	if context.depthOfField then
		context.depthOfField:Destroy()
		context.depthOfField = nil
	end
	if context.screenGui then
		context.screenGui:Destroy()
		context.screenGui = nil
	end
	context.screenRoot = nil
	context.screenRefs = nil
end

local function getPlayerForCutscene(options)
	options = options or {}
	local userId = tonumber(options.triggeringUserId)
	if userId and userId > 0 then
		local player = Players:GetPlayerByUserId(userId)
		if player then
			return player
		end
	end
	return Players.LocalPlayer
end

local function getPlayerCharacter(options)
	local player = getPlayerForCutscene(options)
	return player and player.Character or nil
end

local function shouldUsePlayerClone(infoOrRigName)
	local mode = tostring(settingValue("RigTargetMode", "WorkspaceRig"))
	if mode ~= "TriggeringPlayerClone" then
		return false
	end
	local selectedRigName = tostring(settingValue("PlayerRigName", ""))
	if selectedRigName == "" then
		local firstRig = activeCutsceneData and activeCutsceneData.RigAnimations and activeCutsceneData.RigAnimations[1]
		selectedRigName = firstRig and tostring(firstRig.RigName or "") or ""
		if selectedRigName == "" then
			return true
		end
	end
	local rigName = type(infoOrRigName) == "table" and tostring(infoOrRigName.RigName or "") or tostring(infoOrRigName or "")
	return rigName == selectedRigName
end

local function hideSourceCharacter(context, character)
	if not character or context.hiddenCharacter == character or settingValue("HidePlayerDuringCutscene", true) ~= true then
		return
	end
	context.hiddenCharacter = character
	context.hiddenParts = {}
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(context.hiddenParts, {
				part = descendant,
				transparency = descendant.LocalTransparencyModifier,
			})
			descendant.LocalTransparencyModifier = 1
		end
	end
end

local function restoreSourceCharacter(context)
	for _, item in ipairs(context.hiddenParts or {}) do
		if item.part and item.part.Parent then
			item.part.LocalTransparencyModifier = item.transparency or 0
		end
	end
	context.hiddenParts = {}
	context.hiddenCharacter = nil
end

local function removeScriptsFromClone(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end
end

local function resolveCFrameTarget(track, context)
	if context and track and track.targetScope == "RigProperty" and shouldUsePlayerClone(track.rigName or track.part0 or track.name) then
		return context.rigTargets[track.rigName or track.part0 or track.name]
	end
	local targetPath = track and tostring(track.targetPath or "") or ""
	if context and context.cutscenePropTargetsByPath and context.cutscenePropTargetsByPath[targetPath] then
		return context.cutscenePropTargetsByPath[targetPath]
	end
	return resolvePath(track.targetPath or "")
end

local function applyCFrameValue(track, value, context)
	local target = resolveCFrameTarget(track, context)
	if not target then
		return
	end
	local cframe = nil
	if typeof(value) == "CFrame" then
		cframe = value
	elseif type(value) == "table" then
		cframe = value.cframe or value.CFrame
	end
	if typeof(cframe) ~= "CFrame" then
		return
	end
	if target:IsA("Model") then
		target:PivotTo(cframe)
	elseif target:IsA("BasePart") then
		target.CFrame = cframe
	end
end

local function isCFrameLikeTrack(track)
	return track
		and (track.propertyName == "CFrame" or track.valueType == "CFrame" or track.name == "CFrame")
end

local function isDirectCFramePlaybackTrack(track)
	if not isCFrameLikeTrack(track) then
		return false
	end
	if track.trackType == "Camera" or track.targetScope == "CameraProperty" then
		return false
	end
	if track.trackType == "Rig" then
		return false
	end
	if track.trackType == "Object" or track.trackType == "Model" or track.trackType == "Rig CFrame" then
		return true
	end
	if track.targetScope == "RigProperty" or track.targetScope == "ObjectProperty" then
		return true
	end
	return not track.part0 and not track.part1
end

local FACE_LAYER_NAMES = {
	"BothEyes",
	"LeftEye",
	"RightEye",
	"Mouth",
	"LeftEyebrow",
	"RightEyebrow",
}
local FACE_LAYER_GUI_NAME = "MegMoLayeredFaceGui"
local FACE_LAYER_SHELL_ATTRIBUTE = "MegMoGeneratedFaceShell"
local FACE_LAYER_SHELL_PREFIX = "MegMoFaceShell_"
local FACE_LAYER_MOTOR_PREFIX = "MegMoFaceShellMotor_"
local FACE_LAYER_FRONT_OFFSET = 0.012
local FACE_LAYER_DEPTH_STEP = 0.003
local FACE_LAYER_OFFSET_LIMIT = 0.35
local FACE_LAYER_SCALE_MIN = 0.35
local FACE_LAYER_SCALE_MAX = 1.75
local FACE_LAYER_TRANSFORM_EPSILON = 0.001

local LIGHTING_EFFECT_MAP = {
	Lighting = {
		properties = {
			brightness = "Brightness",
			clockTime = "ClockTime",
			exposureCompensation = "ExposureCompensation",
			ambient = "Ambient",
			outdoorAmbient = "OutdoorAmbient",
			colorShiftTop = "ColorShift_Top",
			colorShiftBottom = "ColorShift_Bottom",
			fogColor = "FogColor",
			fogStart = "FogStart",
			fogEnd = "FogEnd",
			globalShadows = "GlobalShadows",
		},
	},
	Atmosphere = {
		className = "Atmosphere",
		instanceName = "MegMoAnimatorAtmosphere",
		properties = {
			density = "Density",
			offset = "Offset",
			color = "Color",
			decay = "Decay",
			glare = "Glare",
			haze = "Haze",
		},
	},
	Sky = {
		className = "Sky",
		instanceName = "MegMoAnimatorSky",
		properties = {
			skyboxBk = "SkyboxBk",
			skyboxDn = "SkyboxDn",
			skyboxFt = "SkyboxFt",
			skyboxLf = "SkyboxLf",
			skyboxRt = "SkyboxRt",
			skyboxUp = "SkyboxUp",
			sunAngularSize = "SunAngularSize",
			moonAngularSize = "MoonAngularSize",
			starCount = "StarCount",
		},
	},
	Bloom = {
		className = "BloomEffect",
		instanceName = "MegMoAnimatorBloom",
		properties = {
			enabled = "Enabled",
			intensity = "Intensity",
			size = "Size",
			threshold = "Threshold",
		},
	},
	DepthOfField = {
		className = "DepthOfFieldEffect",
		instanceName = "MegMoAnimatorLightingDepthOfField",
		properties = {
			enabled = "Enabled",
			focusDistance = "FocusDistance",
			inFocusRadius = "InFocusRadius",
			nearIntensity = "NearIntensity",
			farIntensity = "FarIntensity",
		},
	},
	SunRays = {
		className = "SunRaysEffect",
		instanceName = "MegMoAnimatorSunRays",
		properties = {
			enabled = "Enabled",
			intensity = "Intensity",
			spread = "Spread",
		},
	},
	ColorCorrection = {
		className = "ColorCorrectionEffect",
		instanceName = "MegMoAnimatorColorCorrection",
		properties = {
			enabled = "Enabled",
			brightness = "Brightness",
			contrast = "Contrast",
			saturation = "Saturation",
			tintColor = "TintColor",
		},
	},
	Blur = {
		className = "BlurEffect",
		instanceName = "MegMoAnimatorBlur",
		properties = {
			enabled = "Enabled",
			size = "Size",
		},
	},
	Highlight = {
		className = "Highlight",
		instanceName = "MegMoAnimatorHighlight",
		properties = {
			enabled = "Enabled",
			fillColor = "FillColor",
			outlineColor = "OutlineColor",
			fillTransparency = "FillTransparency",
			outlineTransparency = "OutlineTransparency",
		},
	},
}

local LIGHTING_ALIASES = {
	["Depth Of Field"] = "DepthOfField",
	["Depth of Field"] = "DepthOfField",
	DepthOfFieldEffect = "DepthOfField",
	Sunrays = "SunRays",
	SunRaysEffect = "SunRays",
	["Color Correction"] = "ColorCorrection",
	ColorCorrectionEffect = "ColorCorrection",
	BlurEffect = "Blur",
	BloomEffect = "Bloom",
}

local function safeWrite(instance, propertyName, value)
	if not instance or propertyName == nil or value == nil then
		return false
	end
	local ok = pcall(function()
		instance[propertyName] = value
	end)
	return ok == true
end

local function safeRead(instance, propertyName)
	local ok, value = pcall(function()
		return instance[propertyName]
	end)
	return ok and value or nil
end

local function normalizeLightingEffectType(effectType)
	local raw = tostring(effectType or "")
	raw = LIGHTING_ALIASES[raw] or raw:gsub("%s+", "")
	return LIGHTING_EFFECT_MAP[raw] and raw or "Lighting"
end

local function getLightingEffectInstance(effectId)
	local definition = LIGHTING_EFFECT_MAP[effectId]
	if not definition then
		return nil
	end
	if effectId == "Lighting" then
		return Lighting
	end
	if effectId == "Highlight" then
		local existing = workspace:FindFirstChild(definition.instanceName)
		if existing and existing:IsA("Highlight") then
			return existing
		end
		local highlight = Instance.new("Highlight")
		highlight.Name = definition.instanceName
		highlight.Parent = workspace
		return highlight
	end
	local existing = Lighting:FindFirstChild(definition.instanceName)
	if existing and existing.ClassName == definition.className then
		return existing
	end
	for _, child in ipairs(Lighting:GetChildren()) do
		if child.ClassName == definition.className and (child.Name == definition.instanceName or child.Name == effectId) then
			return child
		end
	end
	local created = Instance.new(definition.className)
	created.Name = definition.instanceName
	created.Parent = Lighting
	return created
end

local function applyLightingEffectValue(track, value)
	if type(value) ~= "table" then
		return false
	end
	local effectId = normalizeLightingEffectType(track.valueType or track.effectType or track.name)
	local definition = LIGHTING_EFFECT_MAP[effectId]
	local instance = getLightingEffectInstance(effectId)
	if not definition or not instance then
		return false
	end
	local changed = false
	for key, propertyName in pairs(definition.properties or {}) do
		if value[key] ~= nil and safeWrite(instance, propertyName, value[key]) then
			changed = true
		end
	end
	if effectId == "Highlight" then
		if value.depthMode ~= nil then
			local depthMode = tostring(value.depthMode) == "Occluded" and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
			changed = safeWrite(instance, "DepthMode", depthMode) or changed
		end
		if value.adorneePath ~= nil then
			changed = safeWrite(instance, "Adornee", resolvePath(value.adorneePath)) or changed
		end
	end
	return changed
end

local function findDescendantByRelativePath(root, fullPath)
	if not root or type(fullPath) ~= "string" then
		return nil
	end
	local parts = string.split(fullPath, ".")
	local startIndex = nil
	for index, partName in ipairs(parts) do
		if partName == root.Name then
			startIndex = index + 1
			break
		end
	end
	if not startIndex then
		return nil
	end
	local current = root
	for index = startIndex, #parts do
		current = current and current:FindFirstChild(parts[index])
	end
	return current
end

local function findDescendantFromOriginalRigPath(playbackRig, originalRigName, fullPath)
	if not playbackRig or type(fullPath) ~= "string" then
		return nil
	end
	originalRigName = tostring(originalRigName or "")
	if originalRigName == "" then
		return nil
	end
	local parts = string.split(fullPath, ".")
	local startIndex = nil
	for index, partName in ipairs(parts) do
		if partName == originalRigName then
			startIndex = index + 1
			break
		end
	end
	if not startIndex then
		return nil
	end
	local current = playbackRig
	for index = startIndex, #parts do
		current = current and current:FindFirstChild(parts[index])
	end
	return current
end

local function findRigMotorFromLimbPath(playbackRig, originalRigName, limbPath)
	if not playbackRig or type(limbPath) ~= "string" then
		return nil
	end
	originalRigName = tostring(originalRigName or "")
	if originalRigName == "" then
		return nil
	end
	local parts = string.split(limbPath, "/")
	if parts[1] ~= originalRigName then
		return nil
	end
	local current = playbackRig
	for index = 2, #parts do
		current = current and current:FindFirstChild(parts[index])
	end
	return current and current:IsA("Motor6D") and current or nil
end

local function resolvePlaybackRigAttachmentPart(context, value)
	if not context or not context.rigTargets or type(value) ~= "table" then
		return nil
	end
	local limbPath = tostring(value.limbPath or "")
	local handPartPath = tostring(value.handPartPath or "")
	for rigName, playbackRig in pairs(context.rigTargets) do
		local fromPath = findDescendantFromOriginalRigPath(playbackRig, rigName, handPartPath)
		if fromPath and fromPath:IsA("BasePart") then
			return fromPath
		end
		local motor = findRigMotorFromLimbPath(playbackRig, rigName, limbPath)
		local part = motor and motor.Part1
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function resolveRigByName(rigName, context)
	rigName = tostring(rigName or "")
	if rigName == "" then
		return nil
	end
	if context and context.rigTargets and context.rigTargets[rigName] then
		return context.rigTargets[rigName]
	end
	return workspace:FindFirstChild(rigName, true)
end

local function resolveTrackTarget(track, context)
	if not track then
		return nil
	end
	local rigName = tostring(track.rigName or "")
	if rigName ~= "" and context and shouldUsePlayerClone(rigName) then
		local rig = context.rigTargets[rigName]
		if rig then
			if track.targetScope == "RigProperty" or track.trackType == "Rig CFrame" then
				return rig
			end
			local relative = findDescendantByRelativePath(rig, track.targetPath or "")
			if relative then
				return relative
			end
			local parentName = tostring(track.parentTrackName or "")
			if parentName ~= "" then
				return rig:FindFirstChild(parentName, true)
			end
		end
	end
	local targetPath = tostring(track.targetPath or "")
	if context and context.cutscenePropTargetsByPath and context.cutscenePropTargetsByPath[targetPath] then
		return context.cutscenePropTargetsByPath[targetPath]
	end
	return resolvePath(track.targetPath or "")
end

local function collectBaseParts(target)
	local parts = {}
	if not target then
		return parts
	end
	if target:IsA("BasePart") then
		table.insert(parts, target)
	elseif target:IsA("Motor6D") then
		local part = target.Part1
		if part and part.Parent and part:IsA("BasePart") then
			table.insert(parts, part)
		end
	elseif target:IsA("Model") or target:IsA("Folder") then
		for _, descendant in ipairs(target:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
	end
	return parts
end

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

local function snapshotCFramePlaybackTargets(context, cframeTracks)
	if not context then
		return
	end
	context.cframeTargetSnapshots = {}
	for _, bucket in pairs(cframeTracks or {}) do
		local track = bucket and bucket.track
		local target = track and resolveCFrameTarget(track, context)
		if target and not context.cframeTargetSnapshots[target] then
			context.cframeTargetSnapshots[target] = getInstanceCFrame(target)
		end
	end
end

local function restoreCFramePlaybackTargets(context)
	for target, cframe in pairs((context and context.cframeTargetSnapshots) or {}) do
		if target and target.Parent and typeof(cframe) == "CFrame" then
			setInstanceCFrame(target, cframe)
			for _, part in ipairs(collectBaseParts(target)) do
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
	if context then
		context.cframeTargetSnapshots = {}
	end
end

local function getRelativePath(root, descendant)
	if not root or not descendant then
		return nil
	end
	if root == descendant then
		return ""
	end
	local names = {}
	local current = descendant
	while current and current ~= root do
		table.insert(names, 1, current.Name)
		current = current.Parent
	end
	if current ~= root then
		return nil
	end
	return table.concat(names, "/")
end

local function findRelativeByPath(root, relativePath)
	if not root or relativePath == nil then
		return nil
	end
	relativePath = tostring(relativePath)
	if relativePath == "" then
		return root
	end
	local current = root
	for name in string.gmatch(relativePath, "[^/]+") do
		current = current and current:FindFirstChild(name)
	end
	return current
end

local function configureCutscenePlaybackProp(target)
	for _, part in ipairs(collectBaseParts(target)) do
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		part.LocalTransparencyModifier = 0
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
	end
end

local function hideCutscenePropSource(context, sourceTarget)
	if not context or not sourceTarget then
		return
	end
	context.hiddenCutscenePropParts = context.hiddenCutscenePropParts or {}
	context.hiddenCutscenePropSources = context.hiddenCutscenePropSources or {}
	if context.hiddenCutscenePropSources[sourceTarget] then
		return
	end
	context.hiddenCutscenePropSources[sourceTarget] = true
	for _, part in ipairs(collectBaseParts(sourceTarget)) do
		table.insert(context.hiddenCutscenePropParts, {
			part = part,
			transparency = part.LocalTransparencyModifier,
		})
		part.LocalTransparencyModifier = 1
	end
end

local function restoreCutscenePropSources(context)
	for _, item in ipairs((context and context.hiddenCutscenePropParts) or {}) do
		if item.part and item.part.Parent then
			item.part.LocalTransparencyModifier = item.transparency or 0
		end
	end
	if context then
		context.hiddenCutscenePropParts = {}
		context.hiddenCutscenePropSources = {}
	end
end

local function hideCutscenePropTarget(target)
	for _, part in ipairs(collectBaseParts(target)) do
		if part and part.Parent then
			part.LocalTransparencyModifier = 1
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
		end
	end
end

local function setCutscenePropTargetCFrame(state, cframe)
	if state and state.sourceTarget and typeof(cframe) == "CFrame" then
		setInstanceCFrame(state.sourceTarget, cframe)
		return true
	end
	return false
end

local function createCutscenePlaybackProp(context, sourceTarget, objectPath, attachPartPath)
	if not context or not sourceTarget then
		return nil, nil
	end
	context.cutscenePropTargetsByPath = context.cutscenePropTargetsByPath or {}
	objectPath = tostring(objectPath or "")
	attachPartPath = tostring(attachPartPath or "")
	if objectPath ~= "" and context.cutscenePropTargetsByPath[objectPath] then
		return context.cutscenePropTargetsByPath[objectPath], context.cutscenePropTargetsByPath[attachPartPath]
	end

	local oldArchivable = sourceTarget.Archivable
	sourceTarget.Archivable = true
	local ok, cloneOrError = pcall(function()
		return sourceTarget:Clone()
	end)
	sourceTarget.Archivable = oldArchivable
	local clone = ok and cloneOrError or nil
	if not clone then
		warn("[MegMoCutscenePlayer] Could not create playback prop for " .. tostring(objectPath ~= "" and objectPath or sourceTarget.Name) .. ".")
		return nil, nil
	end

	clone.Name = "MegMoCutsceneProp_" .. tostring(sourceTarget.Name)
	removeScriptsFromClone(clone)
	clone.Parent = workspace
	local sourceCFrame = getInstanceCFrame(sourceTarget)
	if sourceCFrame then
		setInstanceCFrame(clone, sourceCFrame)
	end
	configureCutscenePlaybackProp(clone)
	hideCutscenePropSource(context, sourceTarget)
	table.insert(context.clones, clone)

	local playbackAttachPart = nil
	local sourceAttachPart = attachPartPath ~= "" and resolvePath(attachPartPath) or nil
	if sourceAttachPart then
		playbackAttachPart = findRelativeByPath(clone, getRelativePath(sourceTarget, sourceAttachPart)) or clone
	end

	if objectPath ~= "" then
		context.cutscenePropTargetsByPath[objectPath] = clone
	end
	if attachPartPath ~= "" and playbackAttachPart then
		context.cutscenePropTargetsByPath[attachPartPath] = playbackAttachPart
	end
	return clone, playbackAttachPart
end

local function isAttachmentEventValue(value)
	return type(value) == "table" and value.kind == ATTACH_EVENT_KIND
end

local function collectAttachmentEvents(attachmentTracks)
	local events = {}
	for _, bucket in pairs(attachmentTracks or {}) do
		for _, key in ipairs(bucket.keys or {}) do
			if isAttachmentEventValue(key.value) then
				table.insert(events, {
					frame = key.frame,
					track = bucket.track,
					value = key.value,
				})
			end
		end
	end
	table.sort(events, function(a, b)
		return a.frame < b.frame
	end)
	return events
end

local function snapshotCutsceneProp(target, fallbackCFrame)
	local state = {
		target = target,
		originalCFrame = getInstanceCFrame(target) or fallbackCFrame,
		parts = {},
		attachmentMode = "original",
	}
	for _, part in ipairs(collectBaseParts(target)) do
		local originalAnchored = part:GetAttribute(CUTSCENE_ORIGINAL_ANCHORED_ATTRIBUTE)
		local originalCanCollide = part:GetAttribute(CUTSCENE_ORIGINAL_CAN_COLLIDE_ATTRIBUTE)
		local originalCanTouch = part:GetAttribute(CUTSCENE_ORIGINAL_CAN_TOUCH_ATTRIBUTE)
		local originalCanQuery = part:GetAttribute(CUTSCENE_ORIGINAL_CAN_QUERY_ATTRIBUTE)
		local originalMassless = part:GetAttribute(CUTSCENE_ORIGINAL_MASSLESS_ATTRIBUTE)
		table.insert(state.parts, {
			part = part,
			anchored = type(originalAnchored) == "boolean" and originalAnchored or part.Anchored,
			canCollide = type(originalCanCollide) == "boolean" and originalCanCollide or part.CanCollide,
			canTouch = type(originalCanTouch) == "boolean" and originalCanTouch or part.CanTouch,
			canQuery = type(originalCanQuery) == "boolean" and originalCanQuery or part.CanQuery,
			massless = type(originalMassless) == "boolean" and originalMassless or part.Massless,
		})
	end
	return state
end

local function freezeCutsceneProp(state, cframe)
	if not state or not state.target then
		return
	end
	local anchoredDuringPlayback = state.playbackTarget ~= nil
	if typeof(cframe) == "CFrame" then
		setInstanceCFrame(state.target, cframe)
	end
	for _, item in ipairs(state.parts or {}) do
		local part = item.part
		if part and part.Parent then
			part.Anchored = anchoredDuringPlayback
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	state.attachmentMode = "preAttach"
end

local function setCutscenePropAttachedPhysics(state)
	if not state then
		return
	end
	local anchoredDuringPlayback = state.playbackTarget ~= nil
	for _, item in ipairs(state.parts or {}) do
		local part = item.part
		if part and part.Parent then
			part.Anchored = anchoredDuringPlayback
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	state.attachmentMode = "attached"
end

local function setCutscenePropDetachedPlaybackPhysics(state)
	if not state then
		return
	end
	local anchoredDuringPlayback = state.playbackTarget ~= nil
	for _, item in ipairs(state.parts or {}) do
		local part = item.part
		if part and part.Parent then
			part.Anchored = anchoredDuringPlayback
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	state.attachmentMode = "detached"
end

local function restoreCutscenePropPhysics(state)
	if not state then
		return
	end
	for _, item in ipairs(state.parts or {}) do
		local part = item.part
		if part and part.Parent then
			part.Anchored = item.anchored == true
			part.CanCollide = item.canCollide == true
			part.CanTouch = item.canTouch ~= false
			part.CanQuery = item.canQuery ~= false
			part.Massless = item.massless == true
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	state.attachmentMode = "detached"
end

local function restoreCutsceneProps(context, endStateOverride)
	local endState = tostring(endStateOverride or settingValue("AttachedPropEndState", "Restore"))
	for objectPath, state in pairs((context and context.cutsceneProps) or {}) do
		local finalCFrame = getInstanceCFrame(state.target)
		for _, descendant in ipairs(workspace:GetDescendants()) do
			if descendant:IsA("WeldConstraint")
				and descendant:GetAttribute(ATTACH_WELD_ATTRIBUTE) == true
				and descendant:GetAttribute(ATTACH_OBJECT_PATH_ATTRIBUTE) == objectPath then
				descendant:Destroy()
			end
		end
		if endState == "HideLocally" then
			restoreCutscenePropPhysics(state)
			hideCutscenePropTarget(state.sourceTarget or state.target)
		elseif endState == "KeepFinal" then
			restoreCutscenePropPhysics(state)
			if finalCFrame then
				setCutscenePropTargetCFrame(state, finalCFrame)
			end
		else
			restoreCutscenePropPhysics(state)
			if state.target and state.target.Parent and typeof(state.originalCFrame) == "CFrame" then
				setInstanceCFrame(state.target, state.originalCFrame)
			end
		end
	end
	if context then
		context.cutsceneProps = {}
		context.cutscenePropTargetsByPath = {}
	end
	if endState == "Restore" or endState == "KeepFinal" then
		restoreCutscenePropSources(context)
	end
end

local function findRuntimeAttachmentMotor(objectPath)
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("Motor6D")
			and descendant:GetAttribute(ATTACH_ATTRIBUTE) == true
			and descendant:GetAttribute(ATTACH_OBJECT_PATH_ATTRIBUTE) == objectPath then
			return descendant
		end
	end
	return nil
end

local function removeRuntimeAttachmentMotor(objectPath)
	local motor = findRuntimeAttachmentMotor(objectPath)
	if motor then
		motor:Destroy()
		return true
	end
	return false
end

local function findRuntimeAttachmentWeld(rootPart, part, objectPath)
	if not rootPart or not part then
		return nil
	end
	for _, child in ipairs(rootPart:GetChildren()) do
		if child:IsA("WeldConstraint")
			and child:GetAttribute(ATTACH_WELD_ATTRIBUTE) == true
			and child:GetAttribute(ATTACH_OBJECT_PATH_ATTRIBUTE) == objectPath
			and ((child.Part0 == rootPart and child.Part1 == part) or (child.Part1 == rootPart and child.Part0 == part)) then
			return child
		end
	end
	return nil
end

local function ensureRuntimeAttachmentAssembly(target, attachPart, objectPath)
	if not target or not attachPart or not attachPart:IsA("BasePart") then
		return
	end
	for _, part in ipairs(collectBaseParts(target)) do
		if part ~= attachPart and part.Parent and not findRuntimeAttachmentWeld(attachPart, part, objectPath) then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "MegMoCutsceneAttachWeld_" .. part.Name
			weld.Part0 = attachPart
			weld.Part1 = part
			weld:SetAttribute(ATTACH_WELD_ATTRIBUTE, true)
			weld:SetAttribute(ATTACH_OBJECT_PATH_ATTRIBUTE, objectPath)
			weld.Parent = attachPart
		end
	end
end

local function pivotAttachedTargetToPart(target, attachPart, desiredAttachCFrame)
	if not target or not attachPart or not attachPart.Parent or typeof(desiredAttachCFrame) ~= "CFrame" then
		return false
	end
	if target:IsA("Model") then
		local pivot = target:GetPivot()
		local attachRelativeToPivot = pivot:ToObjectSpace(attachPart.CFrame)
		target:PivotTo(desiredAttachCFrame * attachRelativeToPivot:Inverse())
		return true
	end
	if target:IsA("BasePart") then
		local targetRelativeToAttach = attachPart.CFrame:ToObjectSpace(target.CFrame)
		target.CFrame = desiredAttachCFrame * targetRelativeToAttach
		return true
	end
	local parts = collectBaseParts(target)
	if #parts > 0 then
		local delta = desiredAttachCFrame * attachPart.CFrame:Inverse()
		for _, part in ipairs(parts) do
			if part and part.Parent then
				part.CFrame = delta * part.CFrame
			end
		end
		return true
	end
	return false
end

local function prepareCutsceneProps(context, attachmentTracks)
	context.cutsceneProps = context.cutsceneProps or {}
	context.attachmentEvents = collectAttachmentEvents(attachmentTracks)
	context.firstAttachmentByObjectPath = {}
	context.latestAttachmentByObjectPath = {}
	context.suppressedCFrameTrackPaths = {}
	local shouldFreezeProps = settingValue("FreezeCutsceneProps", true) == true
	for _, event in ipairs(context.attachmentEvents) do
		local value = event.value
		local objectPath = tostring(value.objectPath or "")
		if objectPath ~= "" and not context.firstAttachmentByObjectPath[objectPath] then
			context.firstAttachmentByObjectPath[objectPath] = event
		end
		if shouldFreezeProps and objectPath ~= "" and not context.cutsceneProps[objectPath] then
			local sourceTarget = resolvePath(objectPath) or resolvePath(value.attachPartPath or "")
			local preAttachCFrame = value.preAttachCFrame
			if sourceTarget then
				local playbackTarget, playbackAttachPart = createCutscenePlaybackProp(context, sourceTarget, objectPath, value.attachPartPath)
				local target = playbackTarget or sourceTarget
				local state = snapshotCutsceneProp(target, preAttachCFrame)
				state.sourceTarget = sourceTarget
				state.playbackTarget = playbackTarget
				state.playbackAttachPart = playbackAttachPart
				state.preAttachCFrame = preAttachCFrame or state.originalCFrame
				context.cutsceneProps[objectPath] = state
				local attachPart = playbackAttachPart or resolvePath(value.attachPartPath or "")
				if attachPart and attachPart:IsA("BasePart") then
					ensureRuntimeAttachmentAssembly(target, attachPart, objectPath)
				end
				freezeCutsceneProp(state, state.preAttachCFrame)
			end
		end
	end
end

local function indexCFrameTracksForAttachments(context, cframeTracks)
	context.cframeTrackPaths = {}
	context.attachmentObjectTrackPathsByObjectPath = {}
	for _, bucket in pairs(cframeTracks or {}) do
		local track = bucket.track
		if track then
			local trackPath = tostring(track.path or "")
			local targetPath = tostring(track.targetPath or "")
			if trackPath ~= "" then
				context.cframeTrackPaths[trackPath] = true
			end
			if targetPath ~= "" and trackPath ~= "" then
				context.attachmentObjectTrackPathsByObjectPath[targetPath] = trackPath
			end
		end
	end
end

local function getAttachmentObjectTrackPath(context, objectPath, value)
	local savedPath = tostring(value and value.objectTrackPath or "")
	if savedPath ~= "" and context and context.cframeTrackPaths and context.cframeTrackPaths[savedPath] then
		return savedPath
	end
	objectPath = tostring(objectPath or "")
	local inferredPath = context
		and context.attachmentObjectTrackPathsByObjectPath
		and context.attachmentObjectTrackPathsByObjectPath[objectPath]
	if inferredPath and inferredPath ~= "" then
		return inferredPath
	end
	return savedPath
end

local function applyAttachmentValue(context, value)
	if not isAttachmentEventValue(value) or value.action ~= "Attach" then
		return false
	end
	local objectPath = tostring(value.objectPath or "")
	local state = context and context.cutsceneProps and context.cutsceneProps[objectPath]
	local handPart = resolvePlaybackRigAttachmentPart(context, value) or resolvePath(value.handPartPath or "")
	local attachPart = (state and state.playbackAttachPart) or resolvePath(value.attachPartPath or "")
	local target = (state and state.playbackTarget) or resolvePath(objectPath) or attachPart
	if not handPart or not attachPart or not handPart:IsA("BasePart") or not attachPart:IsA("BasePart") then
		return false
	end
	removeRuntimeAttachmentMotor(objectPath)
	local offsetC0 = typeof(value.offsetC0) == "CFrame" and value.offsetC0 or handPart.CFrame:ToObjectSpace(attachPart.CFrame)
	if state then
		if state.attachmentMode ~= "attached" then
			setCutscenePropAttachedPhysics(state)
		end
	else
		for _, part in ipairs(collectBaseParts(target)) do
			part.Anchored = false
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	pivotAttachedTargetToPart(target, attachPart, handPart.CFrame * offsetC0)
	return true
end

local function applyAttachmentFrameState(context, frame)
	context.suppressedCFrameTrackPaths = {}
	context.activeAttachedObjectPaths = {}
	for _, event in ipairs(context.attachmentEvents or {}) do
		if event.frame <= frame then
			local value = event.value
			local objectPath = tostring(value and value.objectPath or "")
			if objectPath ~= "" then
				context.latestAttachmentByObjectPath[objectPath] = event
			end
		else
			break
		end
	end
	for objectPath, firstEvent in pairs(context.firstAttachmentByObjectPath or {}) do
		local latest = context.latestAttachmentByObjectPath[objectPath]
		local value = latest and latest.value
		if value and value.action == "Attach" then
			context.activeAttachedObjectPaths[objectPath] = true
			local objectTrackPath = getAttachmentObjectTrackPath(context, objectPath, value)
			if objectTrackPath ~= "" then
				context.suppressedCFrameTrackPaths[objectTrackPath] = true
			end
			applyAttachmentValue(context, value)
		elseif value and value.action == "Detach" then
			removeRuntimeAttachmentMotor(objectPath)
			local state = context.cutsceneProps and context.cutsceneProps[objectPath]
			if state and state.attachmentMode == "attached" then
				setCutscenePropDetachedPlaybackPhysics(state)
			end
		else
			removeRuntimeAttachmentMotor(objectPath)
			local state = context.cutsceneProps and context.cutsceneProps[objectPath]
			if state then
				freezeCutsceneProp(state, state.preAttachCFrame)
			end
		end
	end
end

local function isDecalLike(instance)
	return instance and (instance:IsA("Decal") or instance:IsA("Texture"))
end

local function setVisualTransparency(instance, value)
	if isDecalLike(instance) then
		return safeWrite(instance, "Transparency", math.clamp(tonumber(value) or 0, 0, 1))
	end
	if instance and (instance:IsA("ImageLabel") or instance:IsA("ImageButton")) then
		return safeWrite(instance, "ImageTransparency", math.clamp(tonumber(value) or 0, 0, 1))
	end
	return false
end

local function applyImage(instance, imageId)
	if not instance or type(imageId) ~= "string" then
		return false
	end
	if instance:IsA("Decal") or instance:IsA("Texture") then
		return safeWrite(instance, "Texture", imageId)
	end
	if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		return safeWrite(instance, "Image", imageId)
	end
	return false
end

local function getHead(rig)
	local head = rig and rig:FindFirstChild("Head", true)
	return head and head:IsA("BasePart") and head or nil
end

local function normalizeFaceLayerName(name)
	return string.lower(tostring(name or "")):gsub("[%s_%-%./]", "")
end

local function getFaceLayerTransform(layerTransforms, layerName)
	local raw = type(layerTransforms) == "table" and layerTransforms[layerName] or nil
	if type(raw) ~= "table" then
		return 0, 0, 1
	end
	local x = math.clamp(tonumber(raw.X or raw.x) or 0, -FACE_LAYER_OFFSET_LIMIT, FACE_LAYER_OFFSET_LIMIT)
	local y = math.clamp(tonumber(raw.Y or raw.y) or 0, -FACE_LAYER_OFFSET_LIMIT, FACE_LAYER_OFFSET_LIMIT)
	local scale = math.clamp(tonumber(raw.Scale or raw.scale) or 1, FACE_LAYER_SCALE_MIN, FACE_LAYER_SCALE_MAX)
	return x, y, scale
end

local function hasFaceLayerTransformOverrides(layerTransforms)
	if type(layerTransforms) ~= "table" then
		return false
	end
	for _, layerName in ipairs(FACE_LAYER_NAMES) do
		local x, y, scale = getFaceLayerTransform(layerTransforms, layerName)
		if math.abs(x) > FACE_LAYER_TRANSFORM_EPSILON
			or math.abs(y) > FACE_LAYER_TRANSFORM_EPSILON
			or math.abs(scale - 1) > FACE_LAYER_TRANSFORM_EPSILON then
			return true
		end
	end
	return false
end

local function hasFaceLayerTransformOverride(layerTransforms, layerName)
	local x, y, scale = getFaceLayerTransform(layerTransforms, layerName)
	return math.abs(x) > FACE_LAYER_TRANSFORM_EPSILON
		or math.abs(y) > FACE_LAYER_TRANSFORM_EPSILON
		or math.abs(scale - 1) > FACE_LAYER_TRANSFORM_EPSILON
end

local function getFaceLayerIndex(layerName)
	for index, name in ipairs(FACE_LAYER_NAMES) do
		if name == layerName then
			return index
		end
	end
	return 1
end

local function getSafeFaceLayerSuffix(layerName)
	local suffix = normalizeFaceLayerName(layerName)
	suffix = suffix:gsub("[^%w]", "_")
	return suffix ~= "" and suffix or "layer"
end

local function isGeneratedFaceShell(instance)
	return instance and instance:IsA("BasePart") and instance:GetAttribute(FACE_LAYER_SHELL_ATTRIBUTE) == true
end

local function isInsideGeneratedFaceShell(instance, head)
	local current = instance and instance.Parent or nil
	while current and current ~= head do
		if isGeneratedFaceShell(current) then
			return true
		end
		current = current.Parent
	end
	return false
end

local function clearFaceShellChildren(shell)
	for _, child in ipairs(shell:GetChildren()) do
		if not child:IsA("SpecialMesh") then
			child:Destroy()
		end
	end
end

local function configureFaceShell(shell)
	shell:SetAttribute(FACE_LAYER_SHELL_ATTRIBUTE, true)
	shell:SetAttribute("MegMoGeneratedFaceLayer", true)
	pcall(function()
		shell.Transparency = 1
	end)
	pcall(function()
		shell.CanCollide = false
		shell.CanTouch = false
		shell.CanQuery = false
		shell.CastShadow = false
		shell.Massless = true
		shell.Anchored = false
	end)
end

local function ensureFaceLayerShell(head, layerName)
	if not (head and head:IsA("BasePart")) then
		return nil
	end
	local shellName = FACE_LAYER_SHELL_PREFIX .. getSafeFaceLayerSuffix(layerName)
	local existing = head:FindFirstChild(shellName)
	if existing and existing:IsA("BasePart") then
		configureFaceShell(existing)
		return existing
	end
	local wasArchivable = head.Archivable
	pcall(function()
		head.Archivable = true
	end)
	local ok, shell = pcall(function()
		return head:Clone()
	end)
	pcall(function()
		head.Archivable = wasArchivable
	end)
	if not ok or not shell or not shell:IsA("BasePart") then
		return nil
	end
	shell.Name = shellName
	clearFaceShellChildren(shell)
	configureFaceShell(shell)
	shell.Parent = head
	return shell
end

local function ensureFaceLayerShellMotor(head, shell, layerName)
	if not (head and shell) then
		return nil
	end
	local motorName = FACE_LAYER_MOTOR_PREFIX .. getSafeFaceLayerSuffix(layerName)
	local existing = head:FindFirstChild(motorName)
	if existing and existing:IsA("Motor6D") then
		existing.Part0 = head
		existing.Part1 = shell
		return existing
	end
	local motor = Instance.new("Motor6D")
	motor.Name = motorName
	motor.Part0 = head
	motor.Part1 = shell
	motor.Parent = head
	return motor
end

local function applyFaceShellTransform(layer, layerTransforms, layerName, head)
	local shell = layer and layer.Parent
	if not isGeneratedFaceShell(shell) then
		return false
	end
	head = head or shell.Parent
	if not (head and head:IsA("BasePart")) then
		return false
	end
	local x, y, scale = getFaceLayerTransform(layerTransforms, layerName)
	local baseSize = head.Size
	local shellSize = Vector3.new(
		math.max(0.05, baseSize.X * scale),
		math.max(0.05, baseSize.Y * scale),
		math.max(0.05, baseSize.Z * scale)
	)
	pcall(function()
		shell.Size = shellSize
	end)

	local layerDepth = getFaceLayerIndex(layerName) * FACE_LAYER_DEPTH_STEP
	local scaleDepth = math.max(0, shellSize.Z - baseSize.Z) * 0.5
	local offset = CFrame.new(x * baseSize.X, -y * baseSize.Y, -(FACE_LAYER_FRONT_OFFSET + layerDepth + scaleDepth))
	local motor = ensureFaceLayerShellMotor(head, shell, layerName)
	if motor then
		motor.C0 = offset
		motor.C1 = CFrame.identity
		motor.Transform = CFrame.identity
	end
	return true
end

local function applyFaceLayerTransform(layer, layerTransforms, layerName, head)
	if layer and isDecalLike(layer) then
		return applyFaceShellTransform(layer, layerTransforms, layerName, head)
	end
	if not (layer and (layer:IsA("ImageLabel") or layer:IsA("ImageButton"))) then
		return false
	end
	local x, y, scale = getFaceLayerTransform(layerTransforms, layerName)
	layer.AnchorPoint = Vector2.new(0.5, 0.5)
	layer.BackgroundTransparency = 1
	layer.Position = UDim2.fromScale(0.5 + x, 0.5 + y)
	layer.Size = UDim2.fromScale(scale, scale)
	layer.ScaleType = Enum.ScaleType.Fit
	return true
end

local function ensureFaceLayerGui(head)
	if not (head and head:IsA("BasePart")) then
		return nil
	end
	local gui = head:FindFirstChild(FACE_LAYER_GUI_NAME)
	if gui and gui:IsA("SurfaceGui") then
		return gui
	end
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = FACE_LAYER_GUI_NAME
	surfaceGui.Face = Enum.NormalId.Front
	surfaceGui.LightInfluence = 0
	pcall(function()
		surfaceGui.CanvasSize = Vector2.new(512, 512)
	end)
	pcall(function()
		surfaceGui.PixelsPerStud = 256
	end)
	surfaceGui:SetAttribute("MegMoGeneratedFaceLayer", true)
	surfaceGui.Parent = head
	return surfaceGui
end

local function findFaceLayer(head, layerName)
	if not head then
		return nil
	end
	local wanted = normalizeFaceLayerName(layerName)
	local fallback = nil
	for _, descendant in ipairs(head:GetDescendants()) do
		if isDecalLike(descendant) or descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
			local normalized = normalizeFaceLayerName(descendant.Name)
			if normalized == wanted or normalized == wanted .. "decal" or normalized == wanted .. "image" or normalized == wanted .. "texture" then
				if not isInsideGeneratedFaceShell(descendant, head) then
					if isDecalLike(descendant) then
						return descendant
					end
					fallback = fallback or descendant
				end
			end
		end
	end
	return fallback
end

local function findCurvedFaceLayer(head, layerName)
	if not head then
		return nil
	end
	local wanted = normalizeFaceLayerName(layerName)
	for _, descendant in ipairs(head:GetDescendants()) do
		if isDecalLike(descendant) then
			local normalized = normalizeFaceLayerName(descendant.Name)
			if (normalized == wanted or normalized == wanted .. "decal" or normalized == wanted .. "texture")
				and not isInsideGeneratedFaceShell(descendant, head) then
				return descendant
			end
		end
	end
	return nil
end

local function ensureMovableFaceLayer(head, layerName)
	local shell = ensureFaceLayerShell(head, layerName)
	if not shell then
		return nil
	end
	local existing = shell:FindFirstChild(tostring(layerName or "FaceLayer"))
	if existing and isDecalLike(existing) then
		return existing
	end
	local decal = Instance.new("Decal")
	decal.Name = tostring(layerName or "FaceLayer")
	decal.Face = Enum.NormalId.Front
	decal.Transparency = 1
	decal:SetAttribute("MegMoGeneratedFaceLayer", true)
	decal.Parent = shell
	return decal
end

local function ensureFaceLayer(head, layerName)
	local layer = findCurvedFaceLayer(head, layerName)
	if layer then
		return layer
	end
	if not head then
		return nil
	end
	local decal = Instance.new("Decal")
	decal.Name = tostring(layerName or "FaceLayer")
	decal.Face = Enum.NormalId.Front
	decal.Transparency = 1
	decal:SetAttribute("MegMoGeneratedFaceLayer", true)
	decal.Parent = head
	return decal
end

local function findStandardFace(head)
	if not head then
		return nil
	end
	local named = head:FindFirstChild("face")
	if named and isDecalLike(named) then
		return named
	end
	for _, child in ipairs(head:GetChildren()) do
		if isDecalLike(child) and string.lower(child.Name) == "face" then
			return child
		end
	end
	return nil
end

local function ensureStandardFace(head)
	local face = findStandardFace(head)
	if face then
		return face
	end
	if not head then
		return nil
	end
	local decal = Instance.new("Decal")
	decal.Name = "face"
	decal.Face = Enum.NormalId.Front
	decal.Transparency = 1
	decal:SetAttribute("MegMoGeneratedStandardFace", true)
	decal.Parent = head
	return decal
end

local function hideLayeredFaces(head)
	for _, layerName in ipairs(FACE_LAYER_NAMES) do
		local wanted = normalizeFaceLayerName(layerName)
		for _, descendant in ipairs(head:GetDescendants()) do
			if isDecalLike(descendant) or descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
				local normalized = normalizeFaceLayerName(descendant.Name)
				if normalized == wanted or normalized == wanted .. "decal" or normalized == wanted .. "image" or normalized == wanted .. "texture" then
					setVisualTransparency(descendant, 1)
				end
			end
		end
	end
end

local function applyFaceValue(track, value, context)
	if type(value) ~= "table" then
		return false
	end
	local rig = resolveRigByName(value.rigName or value.character or value.Character or track.rigName, context)
	local head = getHead(rig)
	if not head then
		return false
	end
	if value.type == "FaceSnapshot" then
		local face = findStandardFace(head)
		if face and type(value.standard) == "table" then
			applyImage(face, value.standard.imageId or "")
			if type(value.standard.transparency) == "number" then
				setVisualTransparency(face, value.standard.transparency)
			end
		end
		for _, layerName in ipairs(FACE_LAYER_NAMES) do
			local layer = findFaceLayer(head, layerName)
			local saved = type(value.layers) == "table" and value.layers[layerName] or nil
			if layer and type(saved) == "table" then
				applyImage(layer, saved.imageId or "")
				if type(saved.transparency) == "number" then
					setVisualTransparency(layer, saved.transparency)
				end
			elseif layer then
				setVisualTransparency(layer, 1)
			end
		end
		return true
	end
	if value.faceType == "Layered" then
		local standard = findStandardFace(head)
		if standard then
			setVisualTransparency(standard, 1)
		end
		hideLayeredFaces(head)
		local layerTransforms = value.layerTransforms or value.LayerTransforms
		local useMovableLayers = hasFaceLayerTransformOverrides(layerTransforms)
		for _, layerName in ipairs(FACE_LAYER_NAMES) do
			local imageId = type(value.layers) == "table" and value.layers[layerName] or nil
			if type(imageId) == "string" and imageId ~= "" then
				local useMovableLayer = useMovableLayers and hasFaceLayerTransformOverride(layerTransforms, layerName)
				local layer = useMovableLayer and ensureMovableFaceLayer(head, layerName) or ensureFaceLayer(head, layerName)
				if layer then
					if useMovableLayer then
						applyFaceLayerTransform(layer, layerTransforms, layerName, head)
					end
					applyImage(layer, imageId)
					setVisualTransparency(layer, 0)
				end
			end
		end
		return true
	end
	local imageId = value.imageId or value.ImageId
	if type(imageId) == "string" and imageId ~= "" then
		hideLayeredFaces(head)
		local face = ensureStandardFace(head)
		if face then
			applyImage(face, imageId)
			setVisualTransparency(face, 0)
			return true
		end
	end
	return false
end

local function collectEmitters(target)
	local emitters = {}
	if target and target:IsA("ParticleEmitter") then
		table.insert(emitters, target)
	end
	if target then
		for _, descendant in ipairs(target:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") then
				table.insert(emitters, descendant)
			end
		end
	end
	table.sort(emitters, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	return emitters
end

local function addUniqueEmitter(emitters, seen, emitter)
	if not (emitter and emitter.Parent and emitter:IsA("ParticleEmitter")) then
		return
	end
	if seen[emitter] then
		return
	end
	seen[emitter] = true
	table.insert(emitters, emitter)
end

local function emitterMatchesEntry(emitter, entry)
	if not (emitter and entry) then
		return false
	end
	local wantedPath = tostring(entry.path or "")
	local wantedName = tostring(entry.name or "")
	if wantedName ~= "" and emitter.Name == wantedName then
		return true
	end
	if wantedPath == "" then
		return false
	end
	local currentPath = emitter:GetFullName()
	if currentPath == wantedPath then
		return true
	end
	local suffix = wantedPath:match("[^.]+%.(.+)$")
	return suffix ~= nil and currentPath:sub(-#suffix) == suffix
end

local function findEmitterFromPlaybackTargets(entry, context)
	local wantedPath = tostring(entry and entry.path or "")
	if wantedPath == "" or not context then
		return nil
	end
	for _, rig in pairs(context.rigTargets or {}) do
		local relative = findDescendantByRelativePath(rig, wantedPath)
		if relative and relative:IsA("ParticleEmitter") then
			return relative
		end
		for _, emitter in ipairs(collectEmitters(rig)) do
			if emitterMatchesEntry(emitter, entry) then
				return emitter
			end
		end
	end
	for _, target in pairs(context.cutscenePropTargetsByPath or {}) do
		if target and target.Parent then
			local relative = findDescendantByRelativePath(target, wantedPath)
			if relative and relative:IsA("ParticleEmitter") then
				return relative
			end
			for _, emitter in ipairs(collectEmitters(target)) do
				if emitterMatchesEntry(emitter, entry) then
					return emitter
				end
			end
		end
	end
	return nil
end

local function collectTrackEmitters(track, context)
	local emitters = {}
	local seen = {}
	for _, emitter in ipairs(collectEmitters(resolveTrackTarget(track, context))) do
		addUniqueEmitter(emitters, seen, emitter)
	end
	for _, entry in ipairs(type(track.emitterTargets) == "table" and track.emitterTargets or {}) do
		local emitter = resolvePath(tostring(entry.path or ""))
		if not (emitter and emitter:IsA("ParticleEmitter")) then
			emitter = findEmitterFromPlaybackTargets(entry, context)
		end
		addUniqueEmitter(emitters, seen, emitter)
	end
	table.sort(emitters, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	return emitters
end

local function applyParticleProperty(track, value, context)
	local propertyName = tostring(track.propertyName or track.name or "")
	if propertyName == "" then
		return false
	end
	local emitters = collectTrackEmitters(track, context)
	if #emitters == 0 then
		return false
	end
	local changed = 0
	if type(value) == "table" and value.type == "EmitterGroupPropertySnapshot" and type(value.values) == "table" then
		for _, entry in ipairs(value.values) do
			local emitter = nil
			for _, candidate in ipairs(emitters) do
				if emitterMatchesEntry(candidate, entry) then
					emitter = candidate
					break
				end
			end
			if emitter and safeWrite(emitter, propertyName, entry.value) then
				changed += 1
			end
		end
	else
		for _, emitter in ipairs(emitters) do
			if safeWrite(emitter, propertyName, value) then
				changed += 1
			end
		end
	end
	return changed > 0
end

local function runParticleEvent(track, value, context)
	local emitters = collectTrackEmitters(track, context)
	if #emitters == 0 then
		return false
	end
	local payload = type(value) == "table" and value or {}
	local actionName = tostring(payload.actionName or payload.eventName or track.eventName or track.propertyName or track.name or "Emit")
	local changed = 0
	if actionName == "Clear" then
		for _, emitter in ipairs(emitters) do
			if pcall(function()
				emitter:Clear()
			end) then
				changed += 1
			end
		end
	else
		local emitCount = math.max(1, math.floor(tonumber(payload.emitCount or payload.count) or 10))
		for _, emitter in ipairs(emitters) do
			local wasEnabled = emitter.Enabled == true
			if pcall(function()
				emitter:Emit(emitCount)
			end) then
				changed += 1
			end
			pcall(function()
				emitter.Enabled = wasEnabled
			end)
		end
	end
	return changed > 0
end

local function setDecalProperty(instance, propertyName, value)
	if propertyName == "Transparency" then
		return safeWrite(instance, "Transparency", math.clamp(tonumber(value) or 0, 0, 1))
	elseif propertyName == "Color3" or propertyName == "Color" then
		return typeof(value) == "Color3" and safeWrite(instance, "Color3", value)
	elseif propertyName == "Texture" then
		return type(value) == "string" and safeWrite(instance, "Texture", value)
	elseif propertyName == "Face" then
		return typeof(value) == "EnumItem" and safeWrite(instance, "Face", value)
	end
	return false
end

local RUNTIME_PART_SCALE_MIN_SIZE = 0.001

local function getRuntimeScalePart(target)
	if not target then
		return nil
	end
	if target:IsA("Motor6D") then
		local part = target.Part1
		return part and part.Parent and part:IsA("BasePart") and part or nil
	end
	return target:IsA("BasePart") and target or nil
end

local function applyRuntimeScaleValue(track, target, value)
	if target:IsA("Model") and type(value) == "number" then
		return pcall(function()
			target:ScaleTo(value)
		end)
	end

	local part = getRuntimeScalePart(target)
	if not part then
		return false
	end

	if typeof(value) == "Vector3" then
		return safeWrite(part, "Size", Vector3.new(
			math.max(value.X, RUNTIME_PART_SCALE_MIN_SIZE),
			math.max(value.Y, RUNTIME_PART_SCALE_MIN_SIZE),
			math.max(value.Z, RUNTIME_PART_SCALE_MIN_SIZE)
		))
	end

	if type(value) ~= "number" then
		return false
	end

	local originalSize = decodeValue(track.originalValue)
	if typeof(originalSize) ~= "Vector3" then
		originalSize = part.Size
	end

	local scale = math.max(value, RUNTIME_PART_SCALE_MIN_SIZE)
	return safeWrite(part, "Size", Vector3.new(
		math.max(originalSize.X * scale, RUNTIME_PART_SCALE_MIN_SIZE),
		math.max(originalSize.Y * scale, RUNTIME_PART_SCALE_MIN_SIZE),
		math.max(originalSize.Z * scale, RUNTIME_PART_SCALE_MIN_SIZE)
	))
end

local function applyRuntimePropertyValue(track, value, context)
	if not track or value == nil then
		return false
	end
	if track.trackType == "Lighting Effect" then
		return applyLightingEffectValue(track, value)
	end
	if track.targetScope == "EmitterGroupProperty"
		or track.trackType == "Emitter Group Property"
		or (track.targetScope == "ObjectProperty" and track.valueType ~= "CFrame" and track.valueType ~= "Transparency" and tostring(track.propertyName or "") ~= "CFrame") then
		local target = resolveTrackTarget(track, context)
		if target and target:IsA("ParticleEmitter") then
			return safeWrite(target, tostring(track.propertyName or track.name), value)
		end
		if target and #collectEmitters(target) > 0 and tostring(track.propertyName or "") ~= "Color" then
			return applyParticleProperty(track, value, context)
		end
	end
	local target = resolveTrackTarget(track, context)
	if not target then
		return false
	end
	local propertyName = tostring(track.propertyName or track.name or track.valueType or "")
	if target:IsA("ParticleEmitter") and propertyName ~= "" then
		return safeWrite(target, propertyName, value)
	end
	if propertyName == "CFrame" then
		applyCFrameValue(track, value, context)
		return true
	elseif propertyName == "Scale" then
		return applyRuntimeScaleValue(track, target, value)
	elseif isDecalLike(target) then
		return setDecalProperty(target, propertyName, value)
	elseif propertyName == "Transparency" then
		local changed = 0
		for _, part in ipairs(collectBaseParts(target)) do
			if safeWrite(part, "Transparency", math.clamp(tonumber(value) or 0, 0, 1)) then
				changed += 1
			end
		end
		return changed > 0
	elseif propertyName == "Color" or propertyName == "Color3" then
		local changed = 0
		for _, part in ipairs(collectBaseParts(target)) do
			if typeof(value) == "Color3" and safeWrite(part, "Color", value) then
				changed += 1
			end
		end
		return changed > 0
	elseif propertyName == "Reflectance" then
		local changed = 0
		for _, part in ipairs(collectBaseParts(target)) do
			if safeWrite(part, "Reflectance", math.clamp(tonumber(value) or 0, 0, 1)) then
				changed += 1
			end
		end
		return changed > 0
	elseif track.valueType == "Emitter" and target:IsA("ParticleEmitter") and type(value) == "table" then
		local changed = safeWrite(target, "Enabled", value.enabled == true)
		if type(value.rate) == "number" then
			changed = safeWrite(target, "Rate", value.rate) or changed
		end
		return changed
	end
	if propertyName ~= "" then
		return safeWrite(target, propertyName, value)
	end
	return false
end

local function isRuntimePropertyTrack(track)
	if not track or track.disabled == true or isDirectCFramePlaybackTrack(track) then
		return false
	end
	if track.trackType == "Camera"
		or track.trackType == "Sound"
		or track.trackType == SCREEN_EFFECT_TYPE
		or track.trackType == "Lighting Effect"
		or track.trackType == "Face"
		or track.trackType == "Event"
		or track.targetScope == "CameraProperty"
		or track.targetScope == "ParticleEvent" then
		return false
	end
	return track.targetScope == "RigProperty"
		or track.targetScope == "ObjectProperty"
		or track.targetScope == "EmitterGroupProperty"
		or track.trackType == "Rig Property"
		or track.trackType == "Object Property"
		or track.trackType == "Emitter Group Property"
		or track.valueType == "Emitter"
		or track.valueType == "Transparency"
end

local function isParticleEventTrack(track)
	return track ~= nil and (track.trackType == "Particle Event" or track.valueType == "ParticleEvent" or track.targetScope == "ParticleEvent")
end

local function fireCutsceneEvent(track, value, frame)
	local eventName = tostring((type(value) == "table" and (value.name or value.eventName or value.action)) or track.eventName or track.name or "Event")
	if eventName == "" then
		eventName = "Event"
	end
	local payload = type(value) == "table" and (value.payload ~= nil and value.payload or value) or value
	local info = {
		frame = frame,
		trackPath = track.path,
		trackName = track.name,
		eventName = eventName,
	}
	eventSignal:Fire(eventName, payload, info)
	for _, callback in ipairs(namedEventCallbacks[eventName] or {}) do
		task.spawn(callback, payload, info)
	end
	local folder = ensureEventsFolder()
	local bindable = folder:FindFirstChild(eventName) or folder:FindFirstChild("Event")
	if bindable and bindable:IsA("BindableEvent") then
		bindable:Fire(payload, info)
	end
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

local function createPlayerRigClone(info, options, context)
	local rigName = tostring(info.RigName or "CutsceneRig")
	if context.rigTargets[rigName] then
		return context.rigTargets[rigName]
	end
	local sourceCharacter = getPlayerCharacter(options)
	if not sourceCharacter then
		warn("[MegMoCutscenePlayer] Could not find triggering player character for " .. rigName .. ".")
		return findRig(info)
	end
	local oldArchivable = sourceCharacter.Archivable
	sourceCharacter.Archivable = true
	local clone = sourceCharacter:Clone()
	sourceCharacter.Archivable = oldArchivable
	if not clone then
		warn("[MegMoCutscenePlayer] Could not clone triggering player character for " .. rigName .. ".")
		return findRig(info)
	end
	clone.Name = "MegMoCutscene_" .. rigName
	removeScriptsFromClone(clone)
	clone.Parent = workspace
	local referenceRig = findRig(info)
	if referenceRig and referenceRig:IsA("Model") then
		clone:PivotTo(referenceRig:GetPivot())
	elseif sourceCharacter:IsA("Model") then
		clone:PivotTo(sourceCharacter:GetPivot())
	end
	hideSourceCharacter(context, sourceCharacter)
	table.insert(context.clones, clone)
	context.rigTargets[rigName] = clone
	return clone
end

local function resolveRigForPlayback(info, options, context)
	if shouldUsePlayerClone(info) then
		return createPlayerRigClone(info, options, context)
	end
	local rig = findRig(info)
	if rig and info.RigName then
		context.rigTargets[tostring(info.RigName)] = rig
	end
	return rig
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
	for _, child in ipairs(rig:GetDescendants()) do
		if child:IsA("BasePart") then
			return child
		end
	end
	return nil
end

local function stabilizeRigPhysics(rig)
	local root = getRigRootPart(rig)
	if not root then
		return nil
	end
	local state = {
		rig = rig,
		root = root,
		originalPivot = rig and rig:IsA("Model") and rig:GetPivot() or root.CFrame,
		parts = {},
		humanoid = rig:FindFirstChildOfClass("Humanoid"),
	}
	if state.humanoid then
		state.autoRotate = state.humanoid.AutoRotate
		state.platformStand = state.humanoid.PlatformStand
		state.humanoid.AutoRotate = false
		state.humanoid.PlatformStand = true
	end
	for _, descendant in ipairs(rig:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(state.parts, {
				part = descendant,
				anchored = descendant.Anchored,
				canCollide = descendant.CanCollide,
			})
			descendant.CanCollide = false
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
	root.Anchored = true
	return state
end

local function restoreRigPhysics(state)
	if not state then
		return
	end
	for _, item in ipairs(state.parts or {}) do
		if item.part and item.part.Parent then
			item.part.Anchored = item.anchored == true
			item.part.CanCollide = item.canCollide == true
		end
	end
	if state.humanoid and state.humanoid.Parent then
		state.humanoid.AutoRotate = state.autoRotate ~= false
		state.humanoid.PlatformStand = state.platformStand == true
	end
	if state.rig and state.rig.Parent and typeof(state.originalPivot) == "CFrame" then
		state.rig:PivotTo(state.originalPivot)
	elseif state.root and state.root.Parent and typeof(state.originalPivot) == "CFrame" then
		state.root.CFrame = state.originalPivot
	end
	for _, item in ipairs(state.parts or {}) do
		if item.part and item.part.Parent then
			item.part.AssemblyLinearVelocity = Vector3.zero
			item.part.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function stabilizeRigForCutscene(rig)
	return stabilizeRigPhysics(rig)
end

local function restoreRigStabilizer(state)
	restoreRigPhysics(state)
end

local function getAnimator(rig)
	if not rig then
		return nil
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		return animator
	end
	local controller = rig:FindFirstChildOfClass("AnimationController")
	if not controller then
		controller = Instance.new("AnimationController")
		controller.Parent = rig
	end
	local animator = controller:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end
	return animator
end

local function buildMotorPath(motor, rig)
	local parts = {}
	local cursor = motor
	while cursor and cursor ~= rig do
		table.insert(parts, 1, cursor.Name)
		cursor = cursor.Parent
	end
	return rig.Name .. "/" .. table.concat(parts, "/")
end

local function collectRigMotors(rig)
	local byPath = {}
	local byName = {}
	local byPart1 = {}
	if not rig then
		return byPath, byName, byPart1
	end
	for _, descendant in ipairs(rig:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			byPath[buildMotorPath(descendant, rig)] = descendant
			byName[descendant.Name] = byName[descendant.Name] or descendant
			if descendant.Part1 then
				byPart1[descendant.Part1.Name] = byPart1[descendant.Part1.Name] or descendant
			end
		end
	end
	return byPath, byName, byPart1
end

local function isRigReadyForAnimation(rig, info)
	if not (rig and rig.Parent) then
		return false
	end
	local originalPose = info and info.OriginalMotorPose
	if type(originalPose) == "table" and #originalPose > 0 then
		local byPath, byName, byPart1 = collectRigMotors(rig)
		for _, item in ipairs(originalPose) do
			local motor = byPath[tostring(item.Path or "")]
				or byName[tostring(item.Name or "")]
				or byPart1[tostring(item.Part1 or "")]
			if not motor then
				return false
			end
		end
	end
	return true
end

local function waitForRigAnimationTarget(info, options, context, deadline)
	local rig = nil
	repeat
		if not shouldUsePlayerClone(info) or getPlayerCharacter(options) then
			rig = resolveRigForPlayback(info, options, context)
			if isRigReadyForAnimation(rig, info) then
				return rig
			end
		end
		if os.clock() >= deadline then
			break
		end
		RunService.Heartbeat:Wait()
	until false
	warn("[MegMoCutscenePlayer] Timed out waiting for rig animation target " .. tostring(info and info.RigName or "unknown") .. ".")
	return rig
end

local function restoreRigBasePose(rig, info)
	local originalPose = info and info.OriginalMotorPose
	if not rig then
		return
	end
	if type(originalPose) == "table" then
		local byPath, byName, byPart1 = collectRigMotors(rig)
		for _, item in ipairs(originalPose) do
			local motor = byPath[tostring(item.Path or "")]
				or byName[tostring(item.Name or "")]
				or byPart1[tostring(item.Part1 or "")]
			local c0 = decodeValue(item.C0)
			if motor and typeof(c0) == "CFrame" then
				motor.C0 = c0
			end
		end
	end

	local originalBonePose = info and info.OriginalBonePose
	if type(originalBonePose) == "table" then
		local byPath = {}
		local byName = {}
		local byParentAndName = {}
		for _, descendant in ipairs(rig:GetDescendants()) do
			if descendant:IsA("Bone") then
				byPath[buildMotorPath(descendant, rig)] = descendant
				byName[descendant.Name] = byName[descendant.Name] or descendant
				local parentName = descendant.Parent and descendant.Parent.Name or ""
				byParentAndName[parentName .. "/" .. descendant.Name] = descendant
			end
		end
		for _, item in ipairs(originalBonePose) do
			local parentAndName = tostring(item.Parent or "") .. "/" .. tostring(item.Name or "")
			local bone = byPath[tostring(item.Path or "")]
				or byParentAndName[parentAndName]
				or byName[tostring(item.Name or "")]
			local transform = decodeValue(item.Transform)
			if bone and typeof(transform) == "CFrame" then
				pcall(function()
					bone.Transform = transform
				end)
			end
		end
	end
end

local function getAnimationPriority(name)
	local ok, priority = pcall(function()
		return Enum.AnimationPriority[tostring(name or "Action")]
	end)
	return ok and priority or Enum.AnimationPriority.Action
end

local function normalizeAnimationId(value)
	value = tostring(value or "")
	local digits = string.match(value, "%d+")
	if not digits then
		return ""
	end
	return "rbxassetid://" .. digits
end

local function getMappedAnimationId(packageFolder, info)
	local directId = normalizeAnimationId(info.AnimationId or info.PermanentAnimationId)
	if directId ~= "" then
		return directId
	end

	local idFolder = packageFolder:FindFirstChild("RigAnimationIds")
	if not idFolder then
		return ""
	end

	local slot = nil
	if info.AnimationIdSlot then
		slot = idFolder:FindFirstChild(tostring(info.AnimationIdSlot))
	end
	if not slot and info.SequenceName then
		for _, child in ipairs(idFolder:GetChildren()) do
			if child:IsA("StringValue") and child:GetAttribute("SequenceName") == info.SequenceName then
				slot = child
				break
			end
		end
	end
	if not slot and info.RigName then
		for _, child in ipairs(idFolder:GetChildren()) do
			if child:IsA("StringValue") and child:GetAttribute("RigName") == info.RigName then
				slot = child
				break
			end
		end
	end

	if slot and slot:IsA("StringValue") then
		return normalizeAnimationId(slot.Value)
	end

	return ""
end

local function waitForPreparedRigAnimations(prepared, deadline)
	while os.clock() < deadline do
		local allReady = true
		for _, entry in ipairs(prepared) do
			if (tonumber(entry.info and entry.info.FrameCount) or 0) > 1 and entry.track.Length <= 0 then
				allReady = false
				break
			end
		end
		if allReady then
			return true
		end
		RunService.Heartbeat:Wait()
	end

	local pending = {}
	for _, entry in ipairs(prepared) do
		if (tonumber(entry.info and entry.info.FrameCount) or 0) > 1 and entry.track.Length <= 0 then
			table.insert(pending, tostring(entry.info and entry.info.RigName or "unknown"))
		end
	end
	if #pending > 0 then
		warn("[MegMoCutscenePlayer] Timed out loading rig animation tracks: " .. table.concat(pending, ", ") .. ". Playback will continue.")
		return false
	end
	return true
end

local function prepareRigAnimationTracks(cutsceneData, options, context)
	local packageFolder = script.Parent
	local sequenceFolder = packageFolder:FindFirstChild("RigAnimations")
	local prepared = {}
	if not sequenceFolder then
		return prepared
	end

	local targetDeadline = os.clock() + 10
	for _, info in ipairs(cutsceneData.RigAnimations or {}) do
		local rig = waitForRigAnimationTarget(info, options, context, targetDeadline)
		restoreRigBasePose(rig, info)
		local animator = getAnimator(rig)
		local sequence = sequenceFolder:FindFirstChild(tostring(info.SequenceName or ""))
		if animator and sequence and sequence:IsA("KeyframeSequence") then
			local animationId = getMappedAnimationId(packageFolder, info)
			if animationId == "" then
				if RunService:IsStudio() then
					local ok, registeredId = pcall(function()
						return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
					end)
					if ok then
						animationId = tostring(registeredId)
					else
						warn("[MegMoCutscenePlayer] Could not register rig animation for " .. tostring(info.RigName) .. ": " .. tostring(registeredId))
					end
				else
					warn("[MegMoCutscenePlayer] Missing permanent AnimationId for " .. tostring(info.RigName) .. ". Fill ReplicatedStorage.MegMoCutscenes.<Cutscene>.RigAnimationIds before publishing.")
				end
			end
			if animationId ~= "" then
				local animation = Instance.new("Animation")
				animation.Name = tostring(info.SequenceName or "MegMoCutsceneAnimation")
				animation.AnimationId = animationId
				pcall(function()
					ContentProvider:PreloadAsync({ animation })
				end)
				local ok, trackOrError = pcall(function()
					return animator:LoadAnimation(animation)
				end)
				if ok and trackOrError then
					trackOrError.Priority = getAnimationPriority(info.Priority)
					trackOrError.Looped = info.Looped == true
					table.insert(prepared, {
						track = trackOrError,
						animation = animation,
						rig = rig,
						info = info,
						stabilizer = stabilizeRigForCutscene(rig),
					})
				else
					animation:Destroy()
					warn("[MegMoCutscenePlayer] Could not load rig animation for " .. tostring(info.RigName) .. ": " .. tostring(trackOrError))
				end
			end
		elseif info.RigName then
			warn("[MegMoCutscenePlayer] Missing rig or sequence for " .. tostring(info.RigName))
		end
	end
	waitForPreparedRigAnimations(prepared, os.clock() + 10)

	return prepared
end

function MegMoCutscenePlayer.Play(cutsceneData, options)
	if MegMoCutscenePlayer._isPlaying then
		warn("[MegMoCutscenePlayer] A cutscene is already playing.")
		return false
	end
	MegMoCutscenePlayer._isPlaying = true
	options = options or {}
	activeCutsceneData = cutsceneData
	local project = cutsceneData.Project or cutsceneData
	local fps = math.max(1, tonumber(project.fps) or 60)
	local contentEndFrame = getProjectLastKeyframe(project)
	local durationFrames = contentEndFrame > 0 and contentEndFrame or (tonumber(project.durationFrames) or 0)
	local durationSeconds = durationFrames / fps
	local camera = workspace.CurrentCamera
	local context = {
		activeSounds = {},
		clones = {},
		hiddenParts = {},
		rigTargets = {},
	}
	local skipState = { requested = false }
	local overlayGui, fadeFrame = createPlaybackOverlay(settingValue("AllowSkip", true) ~= false, skipState)
	local fadeInSeconds = math.max(0, tonumber(settingValue("FadeInSeconds", 0)) or 0)
	local fadeOutSeconds = math.max(0, tonumber(settingValue("FadeOutSeconds", 0)) or 0)

	local cameraTracks = collectTrackKeys(project, function(track)
		return track.trackType == "Camera"
	end)
	local fovTracks = collectTrackKeys(project, function(track)
		return track.targetScope == "CameraProperty" and (track.propertyName == "FieldOfView" or track.valueType == "FieldOfView")
	end)
	local soundTracks = collectTrackKeys(project, function(track)
		return track.disabled ~= true and (track.trackType == "Sound" or track.targetScope == "Sound" or track.valueType == "Sound")
	end)
	local screenEffectTracks = collectTrackKeys(project, function(track)
		return track.trackType == SCREEN_EFFECT_TYPE and track.disabled ~= true
	end)
	local lightingEffectTracks = collectTrackKeys(project, function(track)
		return track.trackType == "Lighting Effect" and track.disabled ~= true
	end)
	local cframeTracks = collectTrackKeys(project, function(track)
		return track.disabled ~= true and isDirectCFramePlaybackTrack(track)
	end)
	indexCFrameTracksForAttachments(context, cframeTracks)
	local runtimePropertyTracks = collectTrackKeys(project, function(track)
		return isRuntimePropertyTrack(track)
	end)
	local faceTracks = collectTrackKeys(project, function(track)
		return track.disabled ~= true and (track.trackType == "Face" or track.targetScope == "Face" or track.valueType == "Face")
	end)
	local particleEventTracks = collectTrackKeys(project, function(track)
		return track.disabled ~= true and isParticleEventTrack(track)
	end)
	local eventTracks = collectTrackKeys(project, function(track)
		return track.disabled ~= true and (track.trackType == "Event" or track.valueType == "Event")
	end)
	local attachmentTracks = collectTrackKeys(project, function(track)
		return track.disabled ~= true and (track.trackType == "Event" or track.valueType == "Event")
	end)
	prepareCutsceneProps(context, attachmentTracks)
	snapshotCFramePlaybackTargets(context, cframeTracks)

	local originalCameraType = camera and camera.CameraType
	if camera and next(cameraTracks) ~= nil then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local rigTracks = prepareRigAnimationTracks(cutsceneData, options, context)

	local function cleanup()
		stopActiveCutsceneSounds(context)
		if camera and options.restoreCamera ~= false and originalCameraType then
			camera.CameraType = originalCameraType
		end
		for _, entry in ipairs(rigTracks) do
			pcall(function()
				entry.track:Stop(0)
			end)
			pcall(function()
				entry.animation:Destroy()
			end)
			pcall(function()
				restoreRigBasePose(entry.rig, entry.info)
			end)
			restoreRigStabilizer(entry.stabilizer)
		end
		for objectPath in pairs(context.firstAttachmentByObjectPath or {}) do
			removeRuntimeAttachmentMotor(objectPath)
		end
		if skipState.requested then
			restoreCFramePlaybackTargets(context)
		end
		restoreCutsceneProps(context, skipState.requested and "Restore" or nil)
		for _, clone in ipairs(context.clones) do
			if clone and clone.Parent then
				clone:Destroy()
			end
		end
		cleanupScreenEffects(context)
		restoreSourceCharacter(context)
		if overlayGui and overlayGui.Parent then
			overlayGui:Destroy()
		end
		activeCutsceneData = nil
		MegMoCutscenePlayer._isPlaying = false
	end

	local ok, err = pcall(function()
		runFade(fadeFrame, 0, 1, fadeInSeconds, skipState)
		if skipState.requested then
			return
		end
		for _, entry in ipairs(rigTracks) do
			entry.track:Play(0, 1, 1)
			entry.track.TimePosition = 0
		end

		local stepEvent = RunService:IsClient() and RunService.RenderStepped or RunService.Heartbeat
		local lastFrame = -1
		local playedSoundKeys = {}
		local startClock = os.clock()
		while true do
			local elapsed = os.clock() - startClock
			local frame = math.min(durationFrames, elapsed * fps)
			for _, bucket in pairs(cameraTracks) do
				applyCameraValue(camera, evaluate(bucket.keys, frame))
			end
			for _, bucket in pairs(fovTracks) do
				local value = evaluate(bucket.keys, frame)
				if camera and type(value) == "number" then
					camera.FieldOfView = math.clamp(value, 1, 120)
				end
			end
			applyAttachmentFrameState(context, frame)
			for _, bucket in pairs(cframeTracks) do
				if not context.suppressedCFrameTrackPaths[tostring(bucket.track.path or "")] then
					applyCFrameValue(bucket.track, evaluate(bucket.keys, frame), context)
				end
			end
			if next(screenEffectTracks) ~= nil then
				renderScreenEffects(context, screenEffectTracks, frame, fps)
			end
			for _, bucket in pairs(lightingEffectTracks) do
				applyLightingEffectValue(bucket.track, evaluate(bucket.keys, frame))
			end
			for _, bucket in pairs(runtimePropertyTracks) do
				applyRuntimePropertyValue(bucket.track, evaluate(bucket.keys, frame), context)
			end
			for _, bucket in pairs(faceTracks) do
				for _, key in ipairs(bucket.keys) do
					local faceKeyId = tostring(bucket.track.path or bucket.track.name) .. ":" .. tostring(key.frame)
					if not playedSoundKeys[faceKeyId] and key.frame > lastFrame and key.frame <= frame then
						playedSoundKeys[faceKeyId] = true
						applyFaceValue(bucket.track, key.value, context)
					end
				end
			end
			for _, bucket in pairs(particleEventTracks) do
				for _, key in ipairs(bucket.keys) do
					local particleKeyId = tostring(bucket.track.path or bucket.track.name) .. ":" .. tostring(key.frame)
					if not playedSoundKeys[particleKeyId] and key.frame > lastFrame and key.frame <= frame then
						playedSoundKeys[particleKeyId] = true
						runParticleEvent(bucket.track, key.value, context)
					end
				end
			end
			for _, bucket in pairs(eventTracks) do
				for _, key in ipairs(bucket.keys) do
					local eventKeyId = tostring(bucket.track.path or bucket.track.name) .. ":" .. tostring(key.frame)
					if not isAttachmentEventValue(key.value) and not playedSoundKeys[eventKeyId] and key.frame > lastFrame and key.frame <= frame then
						playedSoundKeys[eventKeyId] = true
						fireCutsceneEvent(bucket.track, key.value, key.frame)
					end
				end
			end
			for _, bucket in pairs(soundTracks) do
				for _, key in ipairs(bucket.keys) do
					local soundKeyId = tostring(bucket.track.path or bucket.track.targetPath or bucket.track.name) .. ":" .. tostring(key.frame)
					if not playedSoundKeys[soundKeyId] and key.frame > lastFrame and key.frame <= frame then
						playedSoundKeys[soundKeyId] = true
						playSound(bucket.track, key.value, context)
					end
				end
			end
			if fadeFrame and fadeOutSeconds > 0 and durationSeconds > 0 then
				local remaining = durationSeconds - elapsed
				if remaining <= fadeOutSeconds then
					fadeFrame.BackgroundTransparency = math.clamp(remaining / fadeOutSeconds, 0, 1)
				end
			end
			lastFrame = frame
			if elapsed >= durationSeconds or skipState.requested then
				break
			end
			stepEvent:Wait()
		end
	end)

	cleanup()
	if not ok then
		warn("[MegMoCutscenePlayer] Playback failed: " .. tostring(err))
	end
	return ok
end

return MegMoCutscenePlayer
