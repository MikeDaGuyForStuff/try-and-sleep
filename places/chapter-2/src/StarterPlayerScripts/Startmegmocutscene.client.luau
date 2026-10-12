-- StartMegMoCutscene (LocalScript)
-- Put this in StarterPlayer > StarterPlayerScripts
-- Shows a loading screen, then plays the MegMo cutscene "cutscene1" exactly as exported.
-- Afterwards: moves the player to where the camera ended, gives the camera back,
-- and starts the monologue.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Settings
local MIN_LOADING_TIME = 4      -- seconds the loading screen shows at minimum
local PRELOAD_TIMEOUT = 10      -- max seconds spent preloading textures/meshes
local MAX_WAIT_FOR_START = 10   -- max seconds to wait for the cutscene to start moving
local FADE_OUT_TIME = 0.75      -- loading screen fade-out
local EYE_HEIGHT = 1.5          -- distance from HumanoidRootPart up to the eyes
local MOVE_PLAYER_TO_END = true

-- Monologue that plays after the cutscene.
-- Plain text = the character's thoughts. {"Name", "Text"} = someone speaking.
local MONOLOGUE_DELAY = 0.5
local MONOLOGUE = {
	"Made it before closing. Barely.",
	"...Where is everyone? The door was unlocked, but there's nobody at the counter.",
	"Whatever. Milk, soup, bread. Grab it and get home.",
}

local loadStart = os.clock()

---------------------------------------------------------------- Loading screen
local loadingGui = Instance.new("ScreenGui")
loadingGui.Name = "CutsceneLoadingScreen"
loadingGui.IgnoreGuiInset = true
loadingGui.ResetOnSpawn = false
loadingGui.DisplayOrder = 70000

local background = Instance.new("Frame")
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.new(0, 0, 0)
background.BorderSizePixel = 0
background.Parent = loadingGui

local loadingLabel = Instance.new("TextLabel")
loadingLabel.AnchorPoint = Vector2.new(0.5, 0.5)
loadingLabel.Position = UDim2.fromScale(0.5, 0.5)
loadingLabel.Size = UDim2.fromOffset(300, 50)
loadingLabel.BackgroundTransparency = 1
loadingLabel.Font = Enum.Font.GothamBold
loadingLabel.TextSize = 32
loadingLabel.TextColor3 = Color3.new(1, 1, 1)
loadingLabel.Text = "Loading"
loadingLabel.Parent = background

loadingGui.Parent = player:WaitForChild("PlayerGui")

task.spawn(function()
	local dots = 0
	while loadingGui.Parent do
		dots = dots % 3 + 1
		loadingLabel.Text = "Loading" .. string.rep(".", dots)
		task.wait(0.4)
	end
end)

local function fadeOutLoadingScreen()
	if not loadingGui.Parent then
		return
	end
	local info = TweenInfo.new(FADE_OUT_TIME)
	TweenService:Create(background, info, { BackgroundTransparency = 1 }):Play()
	local textTween = TweenService:Create(loadingLabel, info, { TextTransparency = 1 })
	textTween:Play()
	textTween.Completed:Wait()
	loadingGui:Destroy()
end

---------------------------------------------------------------- Load
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local folder = ReplicatedStorage:WaitForChild("MegMoCutscenes"):WaitForChild("cutscene1")
local CutscenePlayer = require(folder:WaitForChild("MegMoCutscenePlayer"))
local cutsceneData = require(folder:WaitForChild("CutsceneData"))
print("[Cutscene] Cutscene loaded")

---------------------------------------------------------------- Keyframe curves
-- MegMo's player ignores the curves you set in the Cutscene Manager and moves in
-- straight lines. This section only reads the curves MegMo exported and applies
-- them. Nothing in MegMo's files is changed, so re-exporting never undoes it.
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

-- MegMo stores each curve on the keyframe a movement ENDS at (the curve shapes
-- the motion leading into that keyframe), so this is true.
local EASING_USES_NEXT_KEY = true
-- Only used if MegMo saves a curve type without saying In/Out
local DEFAULT_EASING_DIRECTION = Enum.EasingDirection.Out

local STYLE_LOOKUP = {}
for _, item in ipairs(Enum.EasingStyle:GetEnumItems()) do
	STYLE_LOOKUP[string.lower(item.Name)] = item
end
STYLE_LOOKUP.expo = Enum.EasingStyle.Exponential
STYLE_LOOKUP.circ = Enum.EasingStyle.Circular
STYLE_LOOKUP.cubicv2 = Enum.EasingStyle.Cubic

local DIRECTION_LOOKUP = {
	["in"] = Enum.EasingDirection.In,
	["out"] = Enum.EasingDirection.Out,
	["inout"] = Enum.EasingDirection.InOut,
}

local function cleanName(text)
	local s = string.lower(tostring(text or ""))
	s = s:gsub("[%s_%.%-]", "")
	s = s:gsub("^enum", ""):gsub("^easingstyle", ""):gsub("^easingdirection", ""):gsub("^poseeasingstyle", ""):gsub("^ease", "")
	return s
end

local function parseStyleString(text)
	local s = cleanName(text)
	if s == "constant" or s == "step" or s == "hold" then
		return "constant", nil
	end
	if STYLE_LOOKUP[s] then
		return STYLE_LOOKUP[s], nil
	end
	for _, key in ipairs({ "inout", "in", "out" }) do
		local rest = s:sub(#key + 1)
		if s:sub(1, #key) == key and STYLE_LOOKUP[rest] then
			return STYLE_LOOKUP[rest], DIRECTION_LOOKUP[key]
		end
		rest = s:sub(1, -#key - 1)
		if s:sub(-#key) == key and STYLE_LOOKUP[rest] then
			return STYLE_LOOKUP[rest], DIRECTION_LOOKUP[key]
		end
	end
	return nil, nil
end

local function parseDirection(raw)
	if type(raw) == "table" and raw.name then
		raw = raw.name
	end
	if type(raw) == "string" then
		return DIRECTION_LOOKUP[cleanName(raw)]
	end
	return nil
end

local function cubicBezier(x1, y1, x2, y2, t)
	local function curve(a, b, s)
		local u = 1 - s
		return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s
	end
	local lo, hi = 0, 1
	for _ = 1, 24 do
		local mid = (lo + hi) / 2
		if curve(x1, x2, mid) < t then lo = mid else hi = mid end
	end
	return curve(y1, y2, (lo + hi) / 2)
end

local warnedEasing = {}
local function buildEasing(raw)
	local style, direction = nil, nil
	if type(raw) == "string" then
		style, direction = parseStyleString(raw)
	elseif type(raw) == "table" then
		-- custom graph curve saved as bezier handles
		local b = raw.bezier or raw.Bezier or raw.curve or raw
		if type(b) == "table" then
			local x1, y1 = b.x1 or b[1], b.y1 or b[2]
			local x2, y2 = b.x2 or b[3], b.y2 or b[4]
			if type(x1) == "number" and type(y1) == "number" and type(x2) == "number" and type(y2) == "number" then
				x1, x2 = math.clamp(x1, 0, 1), math.clamp(x2, 0, 1)
				return function(alpha)
					return cubicBezier(x1, y1, x2, y2, alpha)
				end
			end
		end
		if raw.type == "EnumItem" and raw.name then
			style, direction = parseStyleString(raw.name)
		else
			local styleRaw = raw.style or raw.Style or raw.easingStyle or raw.EasingStyle or raw.ease or raw.name
			if type(styleRaw) == "table" and styleRaw.name then
				styleRaw = styleRaw.name
			end
			if type(styleRaw) == "string" then
				style, direction = parseStyleString(styleRaw)
			end
			direction = parseDirection(raw.direction or raw.Direction or raw.easingDirection or raw.EasingDirection) or direction
		end
	end

	if style == "constant" then
		return function(alpha)
			return alpha >= 1 and 1 or 0
		end
	end
	if typeof(style) == "EnumItem" then
		if style == Enum.EasingStyle.Linear then
			return nil
		end
		local dir = direction or DEFAULT_EASING_DIRECTION
		return function(alpha)
			return TweenService:GetValue(alpha, style, dir)
		end
	end

	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, raw)
	local text = ok and encoded or tostring(raw)
	if not warnedEasing[text] then
		warnedEasing[text] = true
		warn("[Cutscene] Unknown curve format, playing it straight: " .. text)
	end
	return nil
end

local function entryValue(entry)
	if type(entry) == "table" then
		return entry.value
	end
	return entry
end

local function entryEasing(entry)
	return type(entry) == "table" and entry.easing or nil
end

---------------- 1. Camera, movement and other timeline curves
-- Blend two exported (still encoded) keyframe values
local function lerpRaw(a, b, alpha)
	if type(a) == "number" and type(b) == "number" then
		return a + (b - a) * alpha
	end
	if type(a) == "table" and type(b) == "table" then
		if a.type == "CFrame" and b.type == "CFrame" and type(a.components) == "table" and type(b.components) == "table" then
			local cf = CFrame.new(table.unpack(a.components)):Lerp(CFrame.new(table.unpack(b.components)), alpha)
			return { type = "CFrame", components = { cf:GetComponents() } }
		end
		local result = {}
		for key, value in pairs(a) do
			result[key] = value
		end
		for key, value in pairs(b) do
			result[key] = lerpRaw(a[key], value, alpha)
		end
		return result
	end
	if a == nil then
		return b
	end
	return alpha < 1 and a or b
end

-- One-off events (sounds, events, faces, particles) and body limbs (handled
-- below) are left alone.
local SKIP_TRACK_TYPES = { Rig = true, Sound = true, Event = true, Face = true, ["Particle Event"] = true }
local SKIP_VALUE_TYPES = { Sound = true, Event = true, Face = true, ParticleEvent = true }
local SKIP_SCOPES = { Sound = true, Face = true, ParticleEvent = true }

local function shouldBake(track)
	if type(track) ~= "table" or track.disabled == true or not track.path then
		return false
	end
	if SKIP_TRACK_TYPES[track.trackType] or SKIP_VALUE_TYPES[track.valueType] or SKIP_SCOPES[track.targetScope] then
		return false
	end
	local label = tostring(track.valueType or track.effectType or track.name or "")
	if track.trackType == "Screen Effect" and label == "Subtitle" then
		return false
	end
	return true
end

local function bakeCurves(data)
	local project = data.Project or data
	if type(project) ~= "table" or project.__curvesBaked or type(project.frames) ~= "table" then
		return
	end
	project.__curvesBaked = true
	local frames = project.frames

	local bakePaths = {}
	for _, track in ipairs(project.tracks or {}) do
		if shouldBake(track) then
			bakePaths[track.path] = true
		end
	end

	local keysByPath = {}
	for frameText, pose in pairs(frames) do
		local frame = tonumber(frameText)
		if frame and type(pose) == "table" then
			for path, entry in pairs(pose) do
				if bakePaths[path] then
					keysByPath[path] = keysByPath[path] or {}
					table.insert(keysByPath[path], { frame = frame, entry = entry })
				end
			end
		end
	end

	local easingCache = {}
	local added = 0
	for path, keys in pairs(keysByPath) do
		table.sort(keys, function(x, y)
			return x.frame < y.frame
		end)
		for i = 1, #keys - 1 do
			local k1, k2 = keys[i], keys[i + 1]
			local rawEasing
			if EASING_USES_NEXT_KEY then
				rawEasing = entryEasing(k2.entry)
			else
				rawEasing = entryEasing(k1.entry)
			end
			if rawEasing ~= nil then
				local easing = easingCache[rawEasing]
				if easing == nil then
					easing = buildEasing(rawEasing) or false
					easingCache[rawEasing] = easing
				end
				if easing then
					local v1, v2 = entryValue(k1.entry), entryValue(k2.entry)
					local span = k2.frame - k1.frame
					for f = math.floor(k1.frame) + 1, math.ceil(k2.frame) - 1 do
						local key = tostring(f)
						frames[key] = frames[key] or {}
						if frames[key][path] == nil then
							local alpha = math.clamp((f - k1.frame) / span, 0, 1)
							frames[key][path] = { value = lerpRaw(v1, v2, easing(alpha)) }
							added += 1
						end
					end
				end
			end
		end
	end
	print(("[Cutscene] Applied camera/movement curves (%d in-between frames)"):format(added))
end

bakeCurves(cutsceneData)

---------------- 2. Body (arms, legs, torso) curves
-- MegMo still plays your rig's animation as normal. Every frame, this corrects
-- the pose to follow MegMo's curves, timed from MegMo's own animation.
local fps = math.max(1, tonumber((cutsceneData.Project or cutsceneData).fps) or 60)

local function lastSegment(text)
	text = tostring(text or "")
	return text:match("([^%./]+)$") or text
end

-- Curves saved in MegMo for each body part: partName -> sorted { {frame, easing} }
local function collectBodyCurves(data, rigName, motorToPart)
	local project = data.Project or data
	local pathToPart = {}
	for _, track in ipairs(project.tracks or {}) do
		if type(track) == "table" and track.path and (track.part1 or track.trackType == "Rig") then
			local trackRig = track.rigName and tostring(track.rigName) or nil
			if not trackRig or trackRig == rigName then
				local jointName = lastSegment(track.name)
				pathToPart[track.path] = (track.part1 and lastSegment(track.part1))
					or motorToPart[jointName]
					or jointName
			end
		end
	end
	local curves = {}
	for frameText, pose in pairs(project.frames or {}) do
		local frame = tonumber(frameText)
		if frame and type(pose) == "table" then
			for path, entry in pairs(pose) do
				local partName = pathToPart[path]
				if partName then
					curves[partName] = curves[partName] or {}
					table.insert(curves[partName], { frame = frame, easing = entryEasing(entry) })
				end
			end
		end
	end
	return curves
end

-- partName -> sorted keys { time, cframe, easing } from MegMo's exported animation
local function buildBodyKeys(sequence, rigName, motorToPart)
	local keyframes = {}
	for _, keyframe in sequence:GetChildren() do
		if keyframe:IsA("Keyframe") then
			table.insert(keyframes, keyframe)
		end
	end
	table.sort(keyframes, function(a, b)
		return a.Time < b.Time
	end)

	local byPart = {}
	for _, keyframe in ipairs(keyframes) do
		for _, pose in keyframe:GetDescendants() do
			if pose:IsA("Pose") and pose.Weight > 0 then
				byPart[pose.Name] = byPart[pose.Name] or {}
				table.insert(byPart[pose.Name], { time = keyframe.Time, cframe = pose.CFrame, pose = pose })
			end
		end
	end

	local curves = collectBodyCurves(cutsceneData, rigName, motorToPart)
	local curved = 0
	for partName, keys in pairs(byPart) do
		for i = 1, #keys - 1 do
			local k1, k2 = keys[i], keys[i + 1]
			local easing = nil
			local foundInMegMo = false

			-- the curve from MegMo's Cutscene Manager (used exactly, even if Linear)
			local list = curves[partName]
			if list then
				local target = (EASING_USES_NEXT_KEY and k2.time or k1.time) * fps
				for _, curve in ipairs(list) do
					if math.abs(curve.frame - target) < 0.51 then
						foundInMegMo = true
						if curve.easing ~= nil then
							easing = buildEasing(curve.easing)
						end
						break
					end
				end
			end

			-- only if MegMo has nothing for this keyframe: the exported keyframe's curve
			if not foundInMegMo then
				local source = EASING_USES_NEXT_KEY and k2.pose or k1.pose
				local styleName = (source.EasingStyle.Name:gsub("V2$", ""))
				if styleName == "Constant" then
					easing = function(alpha)
						return alpha >= 1 and 1 or 0
					end
				elseif styleName ~= "Linear" then
					easing = buildEasing({ style = styleName, direction = source.EasingDirection.Name })
				end
			end

			k1.easing = easing
			if easing then
				curved += 1
			end
		end
	end
	return byPart, curved
end

local function sampleKeys(keys, t)
	if t <= keys[1].time then
		return keys[1].cframe
	end
	if t >= keys[#keys].time then
		return keys[#keys].cframe
	end
	for i = 1, #keys - 1 do
		local k1, k2 = keys[i], keys[i + 1]
		if t >= k1.time and t <= k2.time then
			local alpha = (t - k1.time) / math.max(k2.time - k1.time, 1e-4)
			if k1.easing then
				alpha = k1.easing(alpha)
			end
			return k1.cframe:Lerp(k2.cframe, alpha)
		end
	end
	return keys[#keys].cframe
end

local bodyAnimations = {}
local totalCurved = 0
local sequenceFolder = folder:FindFirstChild("RigAnimations")
-- MegMo names body tracks after joints ("Neck"); animations use body parts ("Head")
local R6_JOINTS = {
	Neck = "Head",
	RootJoint = "Torso",
	["Right Shoulder"] = "Right Arm",
	["Left Shoulder"] = "Left Arm",
	["Right Hip"] = "Right Leg",
	["Left Hip"] = "Left Leg",
}
for _, info in ipairs(cutsceneData.RigAnimations or {}) do
	local sequence = sequenceFolder and sequenceFolder:FindFirstChild(tostring(info.SequenceName or ""))
	if sequence and sequence:IsA("KeyframeSequence") then
		local motorToPart = table.clone(R6_JOINTS)
		local rig = workspace:FindFirstChild(tostring(info.RigName or ""), true)
		if rig then
			for _, motor in rig:GetDescendants() do
				if motor:IsA("Motor6D") and motor.Part1 then
					motorToPart[motor.Name] = motor.Part1.Name
				end
			end
		end
		local keys, curved = buildBodyKeys(sequence, tostring(info.RigName or ""), motorToPart)
		if next(keys) then
			table.insert(bodyAnimations, { info = info, keys = keys })
			totalCurved += curved
		end
	end
end
print(("[Cutscene] Applied body curves (%d curved segments)"):format(totalCurved))

-- The rig MegMo is animating (its own copy if it made one, otherwise your rig)
local function findPlaybackRig(info)
	local rigName = tostring(info.RigName or "")
	return workspace:FindFirstChild("MegMoCutscene_" .. rigName)
		or workspace:FindFirstChild(rigName, true)
end

local function findMegMoTrack(rig, sequenceName)
	local animator = rig:FindFirstChildWhichIsA("Animator", true)
	if not animator then
		return nil
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		if track.Animation and track.Animation.Name == sequenceName then
			return track
		end
	end
	return nil
end

local bodyConnection = nil
if #bodyAnimations > 0 then
	bodyConnection = RunService.Stepped:Connect(function()
		for _, body in ipairs(bodyAnimations) do
			if not (body.rig and body.rig.Parent and body.track and body.track.IsPlaying) then
				body.rig, body.track = nil, nil
				local rig = findPlaybackRig(body.info)
				local track = rig and findMegMoTrack(rig, tostring(body.info.SequenceName or ""))
				if track then
					body.rig, body.track = rig, track
					body.motors = {}
					for _, motor in rig:GetDescendants() do
						if motor:IsA("Motor6D") and motor.Part1 then
							body.motors[motor.Part1.Name] = motor
						end
					end
				end
			end
			if body.track then
				local t = body.track.TimePosition
				for partName, keys in pairs(body.keys) do
					local motor = body.motors[partName]
					if motor and motor.Parent then
						motor.Transform = sampleKeys(keys, t)
					end
				end
			end
		end
	end)
end

local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")
root.Anchored = true -- keep the player still during loading + cutscene

-- Preload textures/meshes (with a time limit)
local preloadDone = false
task.spawn(function()
	pcall(function()
		ContentProvider:PreloadAsync({ workspace })
	end)
	preloadDone = true
end)
local preloadStart = os.clock()
while not preloadDone and os.clock() - preloadStart < PRELOAD_TIMEOUT do
	task.wait(0.1)
end

local remaining = MIN_LOADING_TIME - (os.clock() - loadStart)
if remaining > 0 then
	task.wait(remaining)
end

---------------------------------------------------------------- Play
-- MegMo loads its animations after Play is called, then starts moving the
-- camera. The loading screen fades out as soon as the camera starts moving.
local cutsceneStarted = false
local cameraBeforeStart = nil
task.spawn(function()
	local deadline = os.clock() + MAX_WAIT_FOR_START
	while os.clock() < deadline do
		if cutsceneStarted and camera.CameraType == Enum.CameraType.Scriptable then
			local moved = (camera.CFrame.Position - cameraBeforeStart.Position).Magnitude > 0.01
				or camera.CFrame.LookVector:Dot(cameraBeforeStart.LookVector) < 0.9999
			if moved or not CutscenePlayer._isPlaying then
				break
			end
		end
		task.wait()
	end
	fadeOutLoadingScreen()
end)

print("[Cutscene] Starting cutscene")
cameraBeforeStart = camera.CFrame
cutsceneStarted = true
local ok = CutscenePlayer.Play(cutsceneData, { restoreCamera = false })
print("[Cutscene] Finished, success =", ok)

if bodyConnection then
	bodyConnection:Disconnect()
end

if loadingGui.Parent then
	loadingGui:Destroy()
end

---------------------------------------------------------------- After the cutscene
if MOVE_PLAYER_TO_END then
	local endCFrame = camera.CFrame
	local pos = endCFrame.Position - Vector3.new(0, EYE_HEIGHT, 0)
	local look = endCFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then
		look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	character:PivotTo(CFrame.lookAt(pos, pos + look.Unit))
end

root.AssemblyLinearVelocity = Vector3.zero
root.Anchored = false
task.wait()
camera.CameraSubject = humanoid
camera.CameraType = Enum.CameraType.Custom
print("[Cutscene] Camera and controls restored")

if #MONOLOGUE > 0 then
	task.wait(MONOLOGUE_DELAY)
	local localDialogue = ReplicatedStorage:WaitForChild("LocalDialogue", 10)
	if localDialogue then
		localDialogue:Fire(MONOLOGUE)
	end
end