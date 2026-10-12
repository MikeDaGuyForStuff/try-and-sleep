-- Atmosphere (Client)
-- Put this LocalScript in: StarterPlayer > StarterPlayerScripts
--
-- 1. Nighttime outside, with light fog that keeps the store clear
-- 2. VHS overlay: scanlines, noise, rolling band, glitches, REC + timecode
-- 3. A rounded black border around the screen. All the effects stay inside it.
-- 4. A sticky note stuck on the corner of the screen
--
-- Optional sounds: put Sounds with these names in ReplicatedStorage:
--   "RadioStatic", "Ambience", "Music"  - any that are missing are just skipped

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer

---------------------------------------------------------------------
-- SETTINGS
---------------------------------------------------------------------
-- Sticky note text (use \n for a new line)
local STICKY_NOTE_TEXT = "Tonight:"  -- starts empty; TaskSystem writes the tasks on
local STICKY_NOTE_ROTATION = -4   -- degrees of tilt

-- Night
local CLOCK_TIME      = 0                          -- 0 = midnight, 21 = late evening
local BRIGHTNESS      = 1
local AMBIENT         = Color3.fromRGB(70, 70, 80)  -- indoor light level (raise if the store is too dark)
local OUTDOOR_AMBIENT = Color3.fromRGB(45, 50, 70)  -- outdoor light level

-- Fog (uses an Atmosphere). 0.25 = light haze, 0.35 = foggy, 0.5+ = thick
local FOG_DENSITY = 0.32
local FOG_COLOR   = Color3.fromRGB(70, 78, 95)
local FOG_DECAY   = Color3.fromRGB(40, 44, 58)

-- How strong the VHS effect is: 0 = subtle, 1 = heavy
local VHS_STRENGTH = 0.35

-- Sound volumes
local SOUNDS = {
	{ name = "RadioStatic", volume = 0.08 },
	{ name = "Ambience",    volume = 0.15 },
	{ name = "Music",       volume = 0.30 },
}

-- Border sizes are a PERCENTAGE of the screen height, so they look identical
-- on every monitor.
local BORDER_PERCENT = 0.111   -- thickness of the black border
local CORNER_PERCENT = 0.100   -- how rounded the corners are

local NOISE_DOTS  = 170    -- fine picture noise
local ROLL_TIME   = 7      -- seconds for the bright band to travel down

-- Effect strength ranges (lower number = stronger); VHS_STRENGTH picks a point between them
local SCANLINE_ALPHA = { 0.90, 0.72 }
local TINT_ALPHA     = { 0.94, 0.80 }
local NOISE_ALPHA    = { 0.93, 0.80 }
local GLITCH_CHANCE  = { 0.10, 0.75 }
---------------------------------------------------------------------

local function lerp(a, b, t) return a + (b - a) * t end
local strength = math.clamp(VHS_STRENGTH, 0, 1)

---------------------------------------------------------------------
-- Night + fog
---------------------------------------------------------------------
Lighting.ClockTime = CLOCK_TIME
Lighting.Brightness = BRIGHTNESS
Lighting.Ambient = AMBIENT
Lighting.OutdoorAmbient = OUTDOOR_AMBIENT

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if not atmosphere then
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
end
atmosphere.Density = FOG_DENSITY
atmosphere.Offset = 0.1
atmosphere.Color = FOG_COLOR
atmosphere.Decay = FOG_DECAY
atmosphere.Glare = 0
atmosphere.Haze = 1.5

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

for _, info in ipairs(SOUNDS) do
	local source = findSound(info.name)
	if source then
		-- stop the original so it isn't heard twice
		source:Stop()
		source.Playing = false

		local sound = source:Clone()
		sound:SetAttribute("AtmosphereTrack", true)
		sound.Looped = true
		sound.Volume = info.volume
		sound.Parent = SoundService
		sound:Play()
	end
end

---------------------------------------------------------------------
-- GUI
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "AtmosphereGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

local BLACK = Color3.new(0, 0, 0)
local DESIGN_HEIGHT = 900   -- sizes are tuned for a 1600x900 screen

local function newFrame(parent, color, transparency, zindex)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f.BorderSizePixel = 0
	f.ZIndex = zindex or 1
	f.Parent = parent
	return f
end

-- Filled in by build(), which reruns whenever the window changes size
local shaker, tint, band
local stickyLabel
local screenArea
local scanlines, noise, glitchBars = {}, {}, {}
local recLabel, timeLabel

local function tvText(parent, text, anchor, position, size)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AnchorPoint = anchor
	l.Position = position
	l.Size = UDim2.new(0, 260, 0, 24)
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

local function buildStickyNote(border, scale)
	local width = math.floor(190 * scale)
	local height = math.floor(170 * scale)
	local position = UDim2.new(0, math.floor(border * 0.45), 1, -math.floor(border * 0.45))

	-- soft shadow behind the note
	local shadow = newFrame(gui, BLACK, 0.6, 9)
	shadow.AnchorPoint = Vector2.new(0, 1)
	shadow.Size = UDim2.new(0, width, 0, height)
	shadow.Position = position + UDim2.new(0, math.floor(4 * scale), 0, math.floor(4 * scale))
	shadow.Rotation = STICKY_NOTE_ROTATION

	local note = newFrame(gui, Color3.fromRGB(255, 232, 110), 0, 10)
	note.Name = "StickyNote"
	note.AnchorPoint = Vector2.new(0, 1)
	note.Size = UDim2.new(0, width, 0, height)
	note.Position = position
	note.Rotation = STICKY_NOTE_ROTATION

	-- slightly darker sticky strip along the top
	local strip = newFrame(note, Color3.fromRGB(240, 212, 88), 0, 11)
	strip.Size = UDim2.new(1, 0, 0.16, 0)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0.1, 0, 0.2, 0)
	label.Size = UDim2.new(0.85, 0, 0.75, 0)
	label.Font = Enum.Font.PermanentMarker
	label.TextSize = math.floor(20 * scale)
	label.TextColor3 = Color3.fromRGB(40, 40, 60)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.RichText = true -- lets finished tasks be crossed out
	-- other scripts (like TaskSystem) can change the note with the StickyNoteText attribute
	label.Text = player:GetAttribute("StickyNoteText") or STICKY_NOTE_TEXT
	label.ZIndex = 12
	label.Parent = note
	stickyLabel = label
end

player:GetAttributeChangedSignal("StickyNoteText"):Connect(function()
	if stickyLabel then
		stickyLabel.Text = player:GetAttribute("StickyNoteText") or STICKY_NOTE_TEXT
	end
end)

local function build()
	-- clear the old layout
	for _, child in ipairs(gui:GetChildren()) do child:Destroy() end
	scanlines, noise, glitchBars = {}, {}, {}

	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1600, DESIGN_HEIGHT)
	local scale = math.clamp(math.min(viewport.X / 1600, viewport.Y / DESIGN_HEIGHT), 0.35, 2.5)

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
	tint = newFrame(shaker, BLACK, lerp(TINT_ALPHA[1], TINT_ALPHA[2], strength), 1)
	tint.Size = UDim2.fromScale(1, 1)

	-- 2. scanlines
	local lineAlpha = lerp(SCANLINE_ALPHA[1], SCANLINE_ALPHA[2], strength)
	local lineCount = math.clamp(math.floor(viewport.Y / 7), 40, 220)
	local lineThickness = math.max(1, math.floor(2 * scale))
	for i = 0, lineCount - 1 do
		local line = newFrame(shaker, BLACK, lineAlpha, 2)
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

	timeLabel = tvText(screenArea, "00:00:00", Vector2.new(1, 1),
		UDim2.new(1, -inset, 1, -inset), math.floor(23 * scale))
	timeLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- 8. sticky note on the bottom-left corner, on top of the border
	buildStickyNote(border, scale)
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
-- Update loops
---------------------------------------------------------------------
-- the tint wobbles a little, like an unsteady signal
local baseTint = lerp(TINT_ALPHA[1], TINT_ALPHA[2], strength)
RunService.Heartbeat:Connect(function()
	if tint then
		local wobble = (math.random() - 0.5) * 0.015
		tint.BackgroundTransparency = math.clamp(baseTint + wobble, 0, 1)
	end
end)

-- rolling band
task.spawn(function()
	while true do
		local t = (os.clock() % ROLL_TIME) / ROLL_TIME
		if band then
			band.Position = UDim2.new(0, 0, t * 1.2 - 0.1, 0)
		end
		task.wait(1 / 30)
	end
end)

-- picture noise
task.spawn(function()
	local alpha = lerp(NOISE_ALPHA[1], NOISE_ALPHA[2], strength)
	while true do
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
	local start = os.clock()
	while true do
		local elapsed = os.clock() - start
		if timeLabel then
			timeLabel.Text = ("%02d:%02d:%02d"):format(elapsed / 3600, elapsed / 60 % 60, elapsed % 60)
		end
		task.wait(0.5)
	end
end)

-- glitches
task.spawn(function()
	local chance = lerp(GLITCH_CHANCE[1], GLITCH_CHANCE[2], strength)
	while true do
		task.wait(math.random(3, 8))
		if math.random() < chance then
			for _, glitchBar in ipairs(glitchBars) do
				glitchBar.Position = UDim2.fromScale(0, math.random())
				glitchBar.Visible = true
			end
			for _ = 1, math.random(2, 5) do
				if shaker then
					shaker.Position = UDim2.new(0, math.random(-6, 6), 0, math.random(-4, 4))
				end
				task.wait(0.04)
			end
			if shaker then shaker.Position = UDim2.new() end
			for _, glitchBar in ipairs(glitchBars) do
				glitchBar.Visible = false
			end
		end
	end
end)