-- Cinematic (Client)
-- Put this LocalScript in: StarterPlayer > StarterPlayerScripts
--
-- Handles the camera side of the night 5 scene:
--   {"Zoom", fov, seconds}   from the server zooms the view in or out
--   {"LieDown", "SpotName", cf} locks the camera lying down, looking at the ceiling.
--                            You can only turn 90 degrees to each side.
--   {"LieDown"}              (no name) releases it
--   {"Cutscene", info}       flies the camera from one part to another while
--                            short lines of text play by themselves (no clicking)
--   {"EndScreen", info}      the final black screen with the text set in NightLoop

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("NightEvent")

local DESIGN_HEIGHT = 900          -- cutscene text is sized for a 1600x900 screen
local YAW_LIMIT   = math.rad(90)   -- how far the head can turn each way
local SENSITIVITY = 0.005          -- mouse speed while lying down
local BIND_NAME   = "LieDownCamera"
local DEBUG       = true           -- prints what the camera script is doing to Output

local function dprint(...)
	if DEBUG then print("[Cinematic]", ...) end
end

local lying = false
local yaw = 0
local savedSpeed

local function getHumanoid()
	return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
end

---------------------------------------------------------------------
-- Cutscene text (scales with the screen)
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "CutsceneGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 30
gui.Parent = player:WaitForChild("PlayerGui")

-- pinned to the bottom centre with no size of its own, because UIScale
-- would otherwise drag percentage-based positions around
local root = Instance.new("Frame")
root.AnchorPoint = Vector2.new(0.5, 1)
root.Position = UDim2.new(0.5, 0, 1, 0)
root.Size = UDim2.new(0, 0, 0, 0)
root.BackgroundTransparency = 1
root.Parent = gui

local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local function updateScale()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local v = camera.ViewportSize
	uiScale.Scale = math.clamp(math.min(v.X / 1600, v.Y / DESIGN_HEIGHT), 0.35, 2.5)
end
updateScale()
task.spawn(function()
	local camera = workspace.CurrentCamera
	while not camera do task.wait(0.2) camera = workspace.CurrentCamera end
	updateScale()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end)

local cutsceneLabel = Instance.new("TextLabel")
cutsceneLabel.AnchorPoint = Vector2.new(0.5, 1)
cutsceneLabel.Position = UDim2.new(0, 0, 0, -120)   -- pixels up from the bottom centre
cutsceneLabel.Size = UDim2.new(0, 950, 0, 95)
cutsceneLabel.BackgroundTransparency = 1
cutsceneLabel.Font = Enum.Font.SpecialElite
cutsceneLabel.TextSize = 34
cutsceneLabel.TextColor3 = Color3.fromRGB(235, 232, 225)
cutsceneLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
cutsceneLabel.TextStrokeTransparency = 0.3
cutsceneLabel.TextWrapped = true
cutsceneLabel.Text = ""
cutsceneLabel.Visible = false
cutsceneLabel.Parent = root

---------------------------------------------------------------------
-- Zoom
---------------------------------------------------------------------
local function zoomTo(fov, seconds)
	local camera = workspace.CurrentCamera
	if not camera then return end
	if (seconds or 0) <= 0 then
		camera.FieldOfView = fov
		return
	end
	TweenService:Create(camera, TweenInfo.new(seconds, Enum.EasingStyle.Sine), {
		FieldOfView = fov,
	}):Play()
end

---------------------------------------------------------------------
-- Lying down
---------------------------------------------------------------------
local function stopLying()
	if not lying then return end
	lying = false
	RunService:UnbindFromRenderStep(BIND_NAME)

	local camera = workspace.CurrentCamera
	if camera then camera.CameraType = Enum.CameraType.Custom end
	player.CameraMode = Enum.CameraMode.LockFirstPerson

	local hum = getHumanoid()
	if hum then
		hum.WalkSpeed = savedSpeed or 12
		hum.AutoRotate = true
	end
end

local function startLying(spotName, spotCF)
	-- use the part if it's loaded, otherwise the position the server sent
	local spot = workspace:FindFirstChild(spotName, true)
	if spot and not spot:IsA("BasePart") then spot = nil end
	if not spot and not spotCF then
		warn("Cinematic: no part named " .. tostring(spotName) .. " and no position from the server - can't lie down")
		return
	end
	dprint("lying down at " .. tostring(spotName) .. (spot and " (part)" or " (position from server)"))
	local function spotFrame()
		if spot and spot.Parent then return spot.CFrame end
		return spotCF
	end

	local camera = workspace.CurrentCamera
	if not camera then return end

	lying = true
	yaw = 0

	local hum = getHumanoid()
	if hum then
		if hum.WalkSpeed > 0 then savedSpeed = hum.WalkSpeed end
		hum.WalkSpeed = 0
		hum.AutoRotate = false
	end

	-- take the camera off the character entirely
	player.CameraMode = Enum.CameraMode.Classic
	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 10, function()
		local cam = workspace.CurrentCamera
		if not cam then return end

		-- the spot's UP is the ceiling, its FRONT points at the player's feet,
		-- so turning the head sweeps from the ceiling toward either wall
		-- read the mouse directly; this works even if something else resets MouseBehavior
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		local delta = UserInputService:GetMouseDelta()
		if delta.X ~= 0 then
			yaw = math.clamp(yaw - delta.X * SENSITIVITY, -YAW_LIMIT, YAW_LIMIT)
		end
		-- arrow keys / A and D also turn the head
		local keyTurn = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
			keyTurn = keyTurn - 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
			keyTurn = keyTurn + 1
		end
		if keyTurn ~= 0 then
			yaw = math.clamp(yaw + keyTurn * 0.02, -YAW_LIMIT, YAW_LIMIT)
		end

		local base = spotFrame()
		local pos = base.Position
		local look = base.UpVector * math.cos(yaw) + base.RightVector * math.sin(yaw)
		local up = -base.LookVector
		cam.CFrame = CFrame.lookAt(pos, pos + look, up)

		-- stay put: other scripts turn walking back on after a fade,
		-- and A/D are used to turn the head here
		local h = getHumanoid()
		if h and h.WalkSpeed ~= 0 then h.WalkSpeed = 0 end

		-- keep the body out of the shot
		local char = player.Character
		if char then
			for _, d in ipairs(char:GetDescendants()) do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = 1
				end
			end
		end
	end)
end

---------------------------------------------------------------------
-- Opening cutscene: the camera physically flies toward the house
---------------------------------------------------------------------
local CUT_BIND = "CutsceneCamera"
local playingCutscene = false

local function playCutscene(info)
	if playingCutscene then return end

	-- The server sends the two positions directly, so this works even when
	-- StreamingEnabled means the client can't see those parts.
	local startCF, endCF = info.fromCF, info.toCF
	if not (startCF and endCF) then
		-- fallback: look them up by name if they happen to be loaded
		local fromPart = info.from and workspace:FindFirstChild(info.from, true)
		local toPart = info.to and workspace:FindFirstChild(info.to, true)
		if not (fromPart and toPart) then
			warn("Cinematic: no cutscene positions were sent, skipping the flight")
			return
		end
		startCF, endCF = fromPart.CFrame, toPart.CFrame
	end

	playingCutscene = true
	local camera = workspace.CurrentCamera

	local hum = getHumanoid()
	if hum then
		if hum.WalkSpeed > 0 then savedSpeed = hum.WalkSpeed end
		hum.WalkSpeed = 0
	end

	player.CameraMode = Enum.CameraMode.Classic
	camera.CameraType = Enum.CameraType.Scriptable

	local duration = info.duration or 10
	local startTime = tick()

	RunService:BindToRenderStep(CUT_BIND, Enum.RenderPriority.Camera.Value + 10, function()
		local cam = workspace.CurrentCamera
		if not cam then return end
		local t = math.clamp((tick() - startTime) / duration, 0, 1)
		-- ease in and out so the flight doesn't start or stop abruptly
		local eased = t * t * (3 - 2 * t)
		cam.CFrame = startCF:Lerp(endCF, eased)
	end)

	-- lines play by themselves and can't be skipped
	cutsceneLabel.Visible = true
	for _, line in ipairs(info.lines or {}) do
		cutsceneLabel.Text = line
		cutsceneLabel.MaxVisibleGraphemes = 0
		local total = utf8.len(line) or #line
		for i = 1, total do
			cutsceneLabel.MaxVisibleGraphemes = i
			task.wait(0.035)
		end
		cutsceneLabel.MaxVisibleGraphemes = -1
		task.wait(1.4)
	end
	cutsceneLabel.Visible = false

	-- hold on the last frame until the flight finishes
	while tick() - startTime < duration do
		task.wait(0.1)
	end

	RunService:UnbindFromRenderStep(CUT_BIND)
	camera.CameraType = Enum.CameraType.Custom
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	if hum then hum.WalkSpeed = savedSpeed or 12 end
	playingCutscene = false
end

UserInputService.InputChanged:Connect(function(input)
	if not lying then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		yaw = math.clamp(yaw - input.Delta.X * SENSITIVITY, -YAW_LIMIT, YAW_LIMIT)
	elseif input.UserInputType == Enum.UserInputType.Touch then
		yaw = math.clamp(yaw - input.Delta.X * SENSITIVITY * 2, -YAW_LIMIT, YAW_LIMIT)
	end
end)

---------------------------------------------------------------------
-- End screen
-- (the text itself is set in END_SCREEN at the top of NightLoop)
---------------------------------------------------------------------
local endGui = Instance.new("ScreenGui")
endGui.Name = "EndScreenGui"
endGui.ResetOnSpawn = false
endGui.IgnoreGuiInset = true
endGui.DisplayOrder = 100            -- above everything else, including the fade
endGui.Enabled = false
endGui.Parent = player:WaitForChild("PlayerGui")

local endBg = Instance.new("Frame")
endBg.Size = UDim2.fromScale(1, 1)
endBg.BackgroundColor3 = Color3.new(0, 0, 0)
endBg.BackgroundTransparency = 1
endBg.BorderSizePixel = 0
endBg.Parent = endGui

-- centred holder that scales with the screen, like the cutscene text
local endRoot = Instance.new("Frame")
endRoot.AnchorPoint = Vector2.new(0.5, 0.5)
endRoot.Position = UDim2.fromScale(0.5, 0.5)
endRoot.Size = UDim2.new(0, 0, 0, 0)
endRoot.BackgroundTransparency = 1
endRoot.Parent = endBg

local endScale = Instance.new("UIScale")
endScale.Scale = uiScale.Scale
endScale.Parent = endRoot
uiScale:GetPropertyChangedSignal("Scale"):Connect(function()
	endScale.Scale = uiScale.Scale
end)

-- The title, line and footer are stacked in a column in the middle of the
-- screen. Each one is measured, so long text wraps onto extra lines and
-- pushes the ones below it down. Nothing gets cut off or overlaps.
local END_WIDTH = 1100    -- how wide the text can get before it wraps (design pixels)
local END_GAP = 40        -- space between the title, line and footer
local END_FONT = Enum.Font.SpecialElite

local function makeEndLabel(minHeight, size, color)
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Size = UDim2.new(0, END_WIDTH, 0, minHeight)
	l.BackgroundTransparency = 1
	l.Font = END_FONT
	l.TextSize = size
	l.TextColor3 = color
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextTransparency = 1
	l.Text = ""
	l.Parent = endRoot
	l:SetAttribute("MinHeight", minHeight)
	return l
end

local endTitle  = makeEndLabel(70, 60, Color3.fromRGB(235, 232, 225))
local endLine   = makeEndLabel(130, 34, Color3.fromRGB(220, 216, 208))
local endFooter = makeEndLabel(30, 24, Color3.fromRGB(140, 136, 130))

-- how tall a label needs to be to fit its text on as many lines as it takes
local function neededHeight(label)
	if label.Text == "" then return label:GetAttribute("MinHeight") end
	local size = TextService:GetTextSize(label.Text, label.TextSize, END_FONT,
		Vector2.new(END_WIDTH, 1e6))
	return math.max(label:GetAttribute("MinHeight"), size.Y + 8)
end

-- stacks the visible labels top to bottom, centred on the screen
local function layoutEnd()
	local labels = {}
	for _, l in ipairs({ endTitle, endLine, endFooter }) do
		if l.Visible then table.insert(labels, l) end
	end
	local total = 0
	local heights = {}
	for i, l in ipairs(labels) do
		heights[i] = neededHeight(l)
		total += heights[i]
	end
	total += END_GAP * math.max(#labels - 1, 0)

	local y = -total / 2
	for i, l in ipairs(labels) do
		l.Size = UDim2.new(0, END_WIDTH, 0, heights[i])
		l.Position = UDim2.new(0, 0, 0, y)
		y += heights[i] + END_GAP
	end
end

local function fadeText(label, seconds)
	TweenService:Create(label, TweenInfo.new(seconds), { TextTransparency = 0 }):Play()
	task.wait(seconds)
end

local showingEnd = false

local function showEndScreen(info, instant)
	dprint("EndScreen received (instant=" .. tostring(instant) .. ", already showing=" .. tostring(showingEnd) .. ")")
	if showingEnd then return end
	showingEnd = true
	info = info or {}
	local lines = info.lines or {}

	-- let go of the lying-down camera so the mouse is free, but leave the view frozen
	if lying then
		lying = false
		RunService:UnbindFromRenderStep(BIND_NAME)
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	local hum = getHumanoid()
	if hum then hum.WalkSpeed = 0 end

	endTitle.Text = info.title or ""
	endTitle.Visible = endTitle.Text ~= ""
	endFooter.Text = info.footer or ""
	endFooter.Visible = endFooter.Text ~= ""
	endGui.Enabled = true

	-- hide the chat box and other Roblox buttons so they don't cover the text
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
	pcall(function()
		local window = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
		local bar = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
		if window then window.Enabled = false end
		if bar then bar.Enabled = false end
	end)

	dprint("end screen title: " .. endTitle.Text .. ", " .. #lines .. " line(s)")

	-- make the middle line tall enough for the LONGEST line, so nothing
	-- jumps around while the lines are typed out
	local longest = ""
	for _, line in ipairs(lines) do
		if #line > #longest then longest = line end
	end
	endLine.Text = longest
	endLine:SetAttribute("MinHeight", neededHeight(endLine))
	endLine.Text = ""
	endLine.Visible = #lines > 0
	layoutEnd()

	if instant then
		endBg.BackgroundTransparency = 0
		endTitle.TextTransparency = 0
		endLine.Text = lines[#lines] or ""
		endLine.TextTransparency = 0
		endFooter.TextTransparency = 0
		return
	end

	-- fade to black
	local fade = info.fadeTime or 3
	TweenService:Create(endBg, TweenInfo.new(fade), { BackgroundTransparency = 0 }):Play()
	task.wait(fade + 0.5)

	-- title
	if endTitle.Text ~= "" then
		fadeText(endTitle, 2)
		task.wait(1)
	end

	-- lines, typed out one at a time (the last one stays on screen)
	endLine.TextTransparency = 0
	for _, line in ipairs(lines) do
		endLine.Text = line
		endLine.MaxVisibleGraphemes = 0
		for i = 1, (utf8.len(line) or #line) do
			endLine.MaxVisibleGraphemes = i
			task.wait(0.045)
		end
		endLine.MaxVisibleGraphemes = -1
		task.wait(info.lineHold or 2.5)
	end

	-- footer
	if endFooter.Text ~= "" then
		fadeText(endFooter, 2)
	end
	dprint("end screen finished")
end

---------------------------------------------------------------------
-- Server messages
---------------------------------------------------------------------
remote.OnClientEvent:Connect(function(action, data, extra)
	if action == "Zoom" or action == "Cutscene" or action == "EndScreen" or action == "LieDown" then
		dprint("got " .. tostring(action) .. " " .. tostring(data))
	end

	if action == "Zoom" then
		zoomTo(data, extra)

	elseif action == "Cutscene" then
		playCutscene(data)

	elseif action == "EndScreen" then
		showEndScreen(data, extra)

	elseif action == "LieDown" then
		if data then
			startLying(data, extra)
		else
			stopLying()
		end
	end
end)

player.CharacterAdded:Connect(function()
	-- a respawn cancels the lying-down camera
	task.wait(0.2)
	stopLying()
end)