-- Atmosphere (Client)
-- Put this LocalScript in: StarterPlayer > StarterPlayerScripts
--
-- 1. Radio static and ambience get louder while the music fades, as tasks get done
-- 2. VHS overlay: scanlines, noise, rolling band, glitches
-- 3. A rounded black border around the screen. All the effects stay inside it.
--
-- Sounds: put Sounds named below in ReplicatedStorage (NOT ServerStorage).
--   "RadioStatic", "Ambience", "Music"  - any that are missing are just skipped

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("NightEvent")

---------------------------------------------------------------------
-- SETTINGS
---------------------------------------------------------------------
-- from = volume at the very start, to = volume by the last task of the last night
local SOUNDS = {
	{ name = "RadioStatic", from = 0.00, to = 0.40 },
	{ name = "Ambience",    from = 0.06, to = 0.22 },  -- rises, but not as much
	{ name = "Music",       from = 0.50, to = 0.05 },  -- fades away
}

-- The music slows down and drops in pitch near the end:
-- half of the way there on the second-to-last night, the rest on the last night.
local MUSIC_PITCH = 0.5   -- 1 = normal, 0.5 = an octave down
local MUSIC_NAME  = "Music"

-- Border sizes are a PERCENTAGE of the screen height, so they look identical
-- on every monitor. (0.111 = the 100px border you set, on a 900px-tall screen.)
local BORDER_PERCENT = 0.111   -- thickness of the black border
local CORNER_PERCENT = 0.100   -- how rounded the corners are

local SCANLINES   = 140
local NOISE_DOTS  = 170    -- fine picture noise
local ROLL_TIME   = 7      -- seconds for the bright band to travel down

-- How strong things are at the start vs. the end (lower number = stronger)
local SCANLINE_ALPHA = { 0.90, 0.72 }
local TINT_ALPHA     = { 0.94, 0.80 }
local NOISE_ALPHA    = { 0.93, 0.80 }
local GLITCH_CHANCE  = { 0.10, 0.75 }
---------------------------------------------------------------------

local function lerp(a, b, t) return a + (b - a) * t end

---------------------------------------------------------------------
-- Sounds
---------------------------------------------------------------------
local function findSound(name)
	for _, place in ipairs({ ReplicatedStorage, SoundService, workspace }) do
		local found = place:FindFirstChild(name, true)
		if found and found:IsA("Sound") then return found end
	end
	return nil
end

-- Clear out any copy left over from an earlier run of this script
for _, old in ipairs(SoundService:GetChildren()) do
	if old:IsA("Sound") and old:GetAttribute("AtmosphereTrack") then
		old:Destroy()
	end
end

local tracks = {}
for _, info in ipairs(SOUNDS) do
	local source = findSound(info.name)
	if source then
		-- the original must not play as well, or you hear it twice
		-- (once at normal pitch, once pitched down)
		source:Stop()
		source.Playing = false
		source.Looped = false

		local sound = source:Clone()
		sound:SetAttribute("AtmosphereTrack", true)
		sound.Playing = false
		sound.Looped = true
		sound.Volume = info.from
		sound.Parent = SoundService
		sound:Play()
		table.insert(tracks, { name = info.name, sound = sound, from = info.from, to = info.to })
	else
		warn(("Atmosphere: no Sound named %q found (put it in ReplicatedStorage)"):format(info.name))
	end
end

---------------------------------------------------------------------
-- GUI
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "AtmosphereGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5      -- under the task list and the fade screen
gui.Parent = player:WaitForChild("PlayerGui")

local BLACK = Color3.new(0, 0, 0)
local DESIGN_HEIGHT = 900   -- the sizes above are tuned for a 1600x900 screen

local function newFrame(parent, color, transparency, zindex)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f.BorderSizePixel = 0
	f.ZIndex = zindex or 1
	f.Parent = parent
	return f
end

-- These are filled in by build() and rebuilt whenever the window changes size,
-- so the border and scanlines always fit the screen properly.
local shaker, tint, band
local screenArea
local scanlines, noise, glitchBars = {}, {}, {}
local recLabel, timeLabel

local function tvText(parent, text, anchor, position, size)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AnchorPoint = anchor
	l.Position = position
	l.Size = UDim2.new(0, 260 , 0, 24)
	l.Font = Enum.Font.Arcade
	l.TextSize = size
	l.TextColor3 = Color3.fromRGB(235, 232, 225)
	l.TextStrokeColor3 = BLACK
	l.TextStrokeTransparency = 0.4
	l.TextTransparency = 0.25
	l.Text = text
	l.ZIndex = 9
	l.Parent = parent
	return l
end

local function build()
	-- clear the old layout
	for _, child in ipairs(gui:GetChildren()) do child:Destroy() end
	scanlines, noise, glitchBars = {}, {}, {}

	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1600, DESIGN_HEIGHT)
	-- use whichever axis is tighter, so a short or narrow window still fits
	local scale = math.clamp(math.min(viewport.X / 1600, viewport.Y / DESIGN_HEIGHT), 0.35, 2.5)

	-- taken straight off the screen height, so the border always matches
	local border = math.floor(viewport.Y * BORDER_PERCENT)
	local radius = math.floor(viewport.Y * CORNER_PERCENT)

	-- the picture area: everything inside the border, clipped to it
	screenArea = Instance.new("Frame")
	screenArea.Position = UDim2.new(0, border, 0, border)
	screenArea.Size = UDim2.new(1, -border * 2, 1, -border * 2)
	screenArea.BackgroundTransparency = 1
	screenArea.BorderSizePixel = 0
	screenArea.ClipsDescendants = true
	screenArea.ZIndex = 1
	screenArea.Parent = gui
	Instance.new("UICorner", screenArea).CornerRadius = UDim.new(0, math.max(radius - border, 0))

	shaker = Instance.new("Frame")
	shaker.Size = UDim2.fromScale(1, 1)
	shaker.BackgroundTransparency = 1
	shaker.Parent = screenArea

	-- 1. dark wash
	tint = newFrame(shaker, BLACK, TINT_ALPHA[1], 1)
	tint.Size = UDim2.fromScale(1, 1)

	-- 2. scanlines (one every few real pixels, so they look the same on any screen)
	local lineCount = math.clamp(math.floor(viewport.Y / 7), 40, 220)
	local lineThickness = math.max(1, math.floor(2 * scale))
	for i = 0, lineCount - 1 do
		local line = newFrame(shaker, BLACK, SCANLINE_ALPHA[1], 2)
		line.Size = UDim2.new(1, 0, 0, lineThickness)
		line.Position = UDim2.new(0, 0, i / lineCount, 0)
		table.insert(scanlines, line)
	end

	-- 3. picture noise
	local dotSize = math.max(2, math.floor(2 * scale))
	for _ = 1, NOISE_DOTS do
		local dot = newFrame(shaker, Color3.new(1, 1, 1), NOISE_ALPHA[1], 3)
		dot.Size = UDim2.new(0, dotSize, 0, dotSize)
		table.insert(noise, dot)
	end

	-- 4. rolling bright band
	band = newFrame(shaker, Color3.fromRGB(255, 255, 255), 0.94, 4)
	band.Size = UDim2.new(1, 0, 0, math.floor(70 * scale))

	-- 5. glitch bars
	for _ = 1, 3 do
		local bar = newFrame(shaker, Color3.new(1, 1, 1), 0.75, 5)
		bar.Size = UDim2.new(1, 0, 0, math.max(3, math.floor(6 * scale)))
		bar.Visible = false
		table.insert(glitchBars, bar)
	end

	-- 6. the rounded black border: straight bars plus stepped corners
	local borderHolder = Instance.new("Frame")
	borderHolder.Size = UDim2.fromScale(1, 1)
	borderHolder.BackgroundTransparency = 1
	borderHolder.ZIndex = 8
	borderHolder.Parent = gui

	local function bar(size, position)
		local f = newFrame(borderHolder, BLACK, 0, 8)
		f.Size = size
		f.Position = position
	end
	bar(UDim2.new(1, 0, 0, border), UDim2.new(0, 0, 0, 0))
	bar(UDim2.new(1, 0, 0, border), UDim2.new(0, 0, 1, -border))
	bar(UDim2.new(0, border, 1, 0), UDim2.new(0, 0, 0, 0))
	bar(UDim2.new(0, border, 1, 0), UDim2.new(1, -border, 0, 0))

	local STEPS = 24
	for _, corner in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
		local sx, sy = corner[1], corner[2]
		for i = 0, STEPS - 1 do
			local x0 = radius * i / STEPS
			local x1 = radius * (i + 1) / STEPS
			local height = radius - math.sqrt(math.max(radius ^ 2 - x0 ^ 2, 0))
			local piece = newFrame(borderHolder, BLACK, 0, 8)
			piece.Size = UDim2.new(0, math.ceil(x1 - x0) + 1, 0, math.ceil(height) + 1)
			piece.Position = UDim2.new(
				sx, sx == 0 and x0 or -x1,
				sy, sy == 0 and 0 or -height
			)
		end
	end

	-- 7. old TV text, inside the picture area
	local inset = math.floor(24 * scale)
	recLabel = tvText(screenArea, "REC  \u{25CF}", Vector2.new(1, 0),
		UDim2.new(1, -inset, 0, inset), math.floor(26 * scale))
	recLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- bottom-right, out of the sticky note's way
	timeLabel = tvText(screenArea, "00:00:00", Vector2.new(1, 1),
		UDim2.new(1, -inset, 1, -inset), math.floor(23 * scale))
	timeLabel.TextXAlignment = Enum.TextXAlignment.Right
end

build()

-- rebuild when the window is resized or the player moves to another monitor
task.spawn(function()
	local camera = workspace.CurrentCamera
	while not camera do
		task.wait(0.2)
		camera = workspace.CurrentCamera
	end
	build()
	local queued = false
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if queued then return end
		queued = true
		task.delay(0.3, function()   -- wait for dragging to finish
			queued = false
			build()
		end)
	end)
end)

---------------------------------------------------------------------
-- Progress from the server (night + how many tasks are done)
---------------------------------------------------------------------
local target, current = 0, 0
local pitchTarget, pitchNow = 1, 1
local muteTarget, muteNow = 1, 1   -- 1 = audible, 0 = silent
local muteSpeed = 1

remote.OnClientEvent:Connect(function(action, data)
	if action == "SoundsOff" then
		muteTarget = 0
		muteSpeed = 1 / math.max(data or 1, 0.05)
		return
	end
	if action == "SoundsOn" then
		muteTarget = 1
		muteSpeed = 1 / math.max(data or 1, 0.05)
		return
	end
	if action == "Cinematic" then
		gui.Enabled = not data   -- border, scanlines, noise, REC text all off
		return
	end
	if action ~= "State" or type(data) ~= "table" then return end
	local nights = math.max(data.nights or 1, 1)
	local total = math.max(data.stepsTotal or 1, 1)
	local done = data.stepsDone or 0
	target = math.clamp(((data.night - 1) + done / total) / nights, 0, 1)

	-- music pitch: normal until the second-to-last night, then halfway, then all the way
	if data.night >= nights then
		pitchTarget = MUSIC_PITCH
	elseif data.night == nights - 1 then
		pitchTarget = (1 + MUSIC_PITCH) / 2
	else
		pitchTarget = 1
	end
end)

---------------------------------------------------------------------
-- Update loops
---------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
	current = lerp(current, target, 1 - math.exp(-0.6 * dt))

	-- fade everything out or back in
	muteNow = muteNow + math.clamp(muteTarget - muteNow, -muteSpeed * dt, muteSpeed * dt)
	-- the pitch slides down slowly rather than jumping
	pitchNow = lerp(pitchNow, pitchTarget, 1 - math.exp(-0.5 * dt))

	for _, t in ipairs(tracks) do
		t.sound.Volume = lerp(t.from, t.to, current) * muteNow
		if t.name == MUSIC_NAME then
			t.sound.PlaybackSpeed = pitchNow
		end
	end

	-- the tint wobbles a little, like an unsteady signal
	local wobble = (math.random() - 0.5) * 0.015
	if tint then
		tint.BackgroundTransparency = math.clamp(lerp(TINT_ALPHA[1], TINT_ALPHA[2], current) + wobble, 0, 1)
	end

	local lineAlpha = lerp(SCANLINE_ALPHA[1], SCANLINE_ALPHA[2], current)
	for _, line in ipairs(scanlines) do
		line.BackgroundTransparency = lineAlpha
	end
end)

-- rolling band
task.spawn(function()
	while true do
		local t = (tick() % ROLL_TIME) / ROLL_TIME
		if band then
			band.Position = UDim2.new(0, 0, t * 1.2 - 0.1, 0)
		end
		task.wait(1 / 30)
	end
end)

-- picture noise
task.spawn(function()
	while true do
		local alpha = lerp(NOISE_ALPHA[1], NOISE_ALPHA[2], current)
		for _, dot in ipairs(noise) do
			dot.Position = UDim2.fromScale(math.random(), math.random())
			dot.BackgroundTransparency = alpha + math.random() * 0.06
		end
		task.wait(0.04)
	end
end)

-- blinking REC dot
task.spawn(function()
	while true do
		if recLabel then recLabel.TextTransparency = 0.2 end
		task.wait(0.8)
		if recLabel then recLabel.TextTransparency = 0.8 end
		task.wait(0.5)
	end
end)

-- running timecode
task.spawn(function()
	local start = tick()
	while true do
		local elapsed = tick() - start
		if timeLabel then timeLabel.Text = ("%02d:%02d:%02d"):format(elapsed / 3600, elapsed / 60 % 60, elapsed % 60) end
		task.wait(0.5)
	end
end)

-- glitches
task.spawn(function()
	while true do
		task.wait(math.random(3, 8))
		if math.random() < lerp(GLITCH_CHANCE[1], GLITCH_CHANCE[2], current) then
			for _, bar in ipairs(glitchBars) do
				bar.Position = UDim2.fromScale(0, math.random())
				bar.Visible = true
			end
			for _ = 1, math.random(2, 5) do
				if shaker then
					shaker.Position = UDim2.new(0, math.random(-6, 6), 0, math.random(-4, 4))
				end
				task.wait(0.04)
			end
			if shaker then shaker.Position = UDim2.new() end
			for _, bar in ipairs(glitchBars) do
				bar.Visible = false
			end
		end
	end
end)