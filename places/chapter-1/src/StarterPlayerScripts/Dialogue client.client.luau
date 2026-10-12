-- Dialogue (Client)
-- Put this LocalScript in: StarterPlayer > StarterPlayerScripts
-- Shows dialogue sent by the NightLoop server script.
--   Plain text lines   = the player's thoughts (italic, no name)
--   {"Name", "Text"}   = someone speaking
--
-- VOICE BLIPS (Deltarune-style talking sounds):
--   Make a Folder in ReplicatedStorage called "Voices" and put Sounds in it:
--     "talk1" (or whatever DEFAULT_VOICE is set to) - used for anyone without their own voice
--     A Sound named after a speaker, e.g. "???", gives them their own voice
--   The player ("You") and the player's thoughts never make blip sounds.
--   Optional attributes on each Sound:
--     BasePitch  (number, default 1)    - higher = squeakier, lower = deeper
--     PitchRange (number, default 0.12) - how much each blip randomly goes up/down

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")

local SoundService = game:GetService("SoundService")
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("DialogueEvent")

---------------------------------------------------------------------
-- SETTINGS
---------------------------------------------------------------------
local TYPE_SPEED    = 0.035  -- seconds per letter
local TEXT_COLOR    = Color3.fromRGB(230, 225, 215)
local THOUGHT_COLOR = Color3.fromRGB(190, 185, 175)
local NAME_COLOR    = Color3.fromRGB(200, 170, 140)
local FONT          = Enum.Font.SpecialElite

local DEFAULT_VOICE = "talk1" -- name of the Sound everyone uses unless they have their own voice
local PLAYER_NAMES  = { "You" } -- speakers that count as the player (always silent, like thoughts)
local BLIP_EVERY    = 2      -- play a blip every N letters (1 = every letter)
local BLIP_LENGTH   = 0.08   -- seconds each blip plays before being cut off
local SILENT_CHARS  = " .,!?-'\"…" -- characters that never make a sound
---------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "DialogueGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.Parent = player:WaitForChild("PlayerGui")

---------------------------------------------------------------------
-- Scaling (designed for 1600x900, scaled to the player's screen)
---------------------------------------------------------------------
-- UIScale multiplies positions too, so the container is pinned to the bottom
-- centre with no size, and the box is placed in plain pixels from there.
local DESIGN_W, DESIGN_H = 1600, 900

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
	uiScale.Scale = math.clamp(math.min(v.X / DESIGN_W, v.Y / DESIGN_H), 0.35, 2.5)
end
updateScale()
task.spawn(function()
	local camera = workspace.CurrentCamera
	while not camera do task.wait(0.2) camera = workspace.CurrentCamera end
	updateScale()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end)

local box = Instance.new("Frame")
box.AnchorPoint = Vector2.new(0.5, 1)
box.Position = UDim2.new(0, 0, 0, -80)     -- pixels up from the bottom centre
box.Size = UDim2.new(0, 1000, 0, 180)
box.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
box.BackgroundTransparency = 0.2
box.BorderSizePixel = 0
box.Visible = false
box.Parent = root
Instance.new("UICorner", box).CornerRadius = UDim.new(0, 8)
local stroke = Instance.new("UIStroke", box)
stroke.Color = Color3.fromRGB(60, 55, 50)

local pad = Instance.new("UIPadding", box)
pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 18), UDim.new(0, 18)
pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 22), UDim.new(0, 22)

local function makeLabel(size, pos, textSize)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Font = FONT
	l.TextSize = textSize
	l.TextColor3 = TEXT_COLOR
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextWrapped = true
	l.RichText = true
	l.Text = ""
	l.Parent = box
	return l
end

local nameLabel = makeLabel(UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 0, 0), 31)
nameLabel.TextColor3 = NAME_COLOR
local lineLabel = makeLabel(UDim2.new(1, 0, 1, -68), UDim2.new(0, 0, 0, 42), 29)
local hint = makeLabel(UDim2.new(0, 260, 0, 22), UDim2.new(1, 0, 1, 0), 19)
hint.AnchorPoint = Vector2.new(1, 1)
hint.TextXAlignment = Enum.TextXAlignment.Right
hint.TextTransparency = 0.5
hint.Text = "click to continue"

---------------------------------------------------------------------
-- Input
---------------------------------------------------------------------
local advance = Instance.new("BindableEvent")

UserInputService.InputBegan:Connect(function(input)
	if not box.Visible then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.E
		or input.KeyCode == Enum.KeyCode.Space
		or input.KeyCode == Enum.KeyCode.Return then
		advance:Fire()
	end
end)

-- Keep the player still while dialogue is open
local freezeConn, savedSpeed
local function setFrozen(frozen)
	if frozen then
		freezeConn = RunService.Heartbeat:Connect(function()
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				if hum.WalkSpeed > 0 then savedSpeed = hum.WalkSpeed end
				hum.WalkSpeed = 0
			end
		end)
	else
		if freezeConn then freezeConn:Disconnect() freezeConn = nil end
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = savedSpeed or 12 end
	end
end

---------------------------------------------------------------------
-- Voice blips
---------------------------------------------------------------------
local voiceCache = {}
local warned = {}

-- Looks for a voice Sound in ReplicatedStorage.Voices first, then anywhere the
-- player's side can see (ReplicatedStorage, SoundService, Workspace).
-- NOTE: sounds in ServerStorage can NOT be heard by this script.
local function findVoiceSound(key)
	local voices = ReplicatedStorage:FindFirstChild("Voices")
	local found = voices and voices:FindFirstChild(key)
	if found and found:IsA("Sound") then return found end
	for _, place in ipairs({ ReplicatedStorage, SoundService, workspace }) do
		found = place:FindFirstChild(key, true)
		if found and found:IsA("Sound") then return found end
	end
	return nil
end

local function getVoice(key)
	if voiceCache[key] then return voiceCache[key] end
	local source = findVoiceSound(key)
	if not source then return nil end -- try again next time (it may not have loaded yet)
	local sound = source:Clone()
	sound.Looped = false
	sound.Parent = SoundService
	voiceCache[key] = sound
	return sound
end

local function voiceFor(speaker)
	-- the player's thoughts and the player talking are always silent
	if not speaker or table.find(PLAYER_NAMES, speaker) then
		return nil
	end
	local sound = getVoice(speaker) or getVoice(DEFAULT_VOICE)
	if not sound and not warned[DEFAULT_VOICE] then
		warned[DEFAULT_VOICE] = true
		warn(('Dialogue: can\'t find a Sound named "%s". Put it in ReplicatedStorage (not ServerStorage).'):format(DEFAULT_VOICE))
	end
	return sound
end

local blipToken = 0
local function playBlip(sound)
	local base = sound:GetAttribute("BasePitch") or 1
	local range = sound:GetAttribute("PitchRange") or 0.12
	sound:Stop()
	sound.TimePosition = 0
	sound.PlaybackSpeed = base + (math.random() * 2 - 1) * range
	sound:Play()
	-- cut it short so long sounds still feel like quick blips
	blipToken += 1
	local myToken = blipToken
	task.delay(BLIP_LENGTH, function()
		if blipToken == myToken then sound:Stop() end
	end)
end

---------------------------------------------------------------------
-- Splitting long lines so nothing overflows the box
---------------------------------------------------------------------
local function fits(text, width, height)
	local size = TextService:GetTextSize(text, lineLabel.TextSize, FONT, Vector2.new(width, 1e6))
	return size.Y <= height
end

local function splitIntoPages(text)
	-- AbsoluteSize already includes the UI scale, but TextSize doesn't, so undo it
	local scale = math.max(uiScale.Scale, 0.01)
	local width = lineLabel.AbsoluteSize.X / scale
	local height = lineLabel.AbsoluteSize.Y / scale
	if width < 50 or height < 20 then return { text } end -- not measured yet, don't risk it
	if fits(text, width, height) then return { text } end

	local pages, current = {}, ""
	for word in text:gmatch("%S+") do
		local attempt = current == "" and word or (current .. " " .. word)
		if fits(attempt, width, height) then
			current = attempt
		else
			if current ~= "" then table.insert(pages, current) end
			current = word
		end
	end
	if current ~= "" then table.insert(pages, current) end
	return pages
end

---------------------------------------------------------------------
-- Playing dialogue
---------------------------------------------------------------------
local playing = false

local function play(lines)
	if playing then return end
	playing = true
	setFrozen(true)
	box.Visible = true

	-- tell the server we're still reading, so it never cuts the scene short
	task.spawn(function()
		while playing do
			remote:FireServer("Alive")
			task.wait(2)
		end
	end)

	-- expand each line into one or more pages that fit the box
	local pages = {}
	for _, line in ipairs(lines) do
		local speaker, full
		if type(line) == "table" then
			speaker, full = line[1], line[2]
		else
			full = line
		end
		for _, chunk in ipairs(splitIntoPages(full)) do
			table.insert(pages, { speaker = speaker, text = chunk })
		end
	end

	for _, page in ipairs(pages) do
		local speaker, text = page.speaker, page.text

		if speaker then
			nameLabel.Visible = true
			nameLabel.Text = speaker
			lineLabel.Position = UDim2.new(0, 0, 0, 30)
			lineLabel.TextColor3 = TEXT_COLOR
			lineLabel.Text = text
		else
			-- the player's own thoughts
			nameLabel.Visible = false
			lineLabel.Position = UDim2.new(0, 0, 0, 0)
			lineLabel.TextColor3 = THOUGHT_COLOR
			lineLabel.Text = "<i>" .. text .. "</i>"
		end

		-- typewriter, click to skip
		hint.Visible = false
		lineLabel.MaxVisibleGraphemes = 0
		local skipped = false
		local conn = advance.Event:Connect(function() skipped = true end)
		local voice = voiceFor(speaker)
		local letterCount = 0
		local i = 0
		for _, code in utf8.codes(text) do
			if skipped then break end
			i += 1
			lineLabel.MaxVisibleGraphemes = i
			local char = utf8.char(code)
			if voice and not string.find(SILENT_CHARS, char, 1, true) then
				letterCount += 1
				if (letterCount - 1) % BLIP_EVERY == 0 then
					playBlip(voice)
				end
			end
			task.wait(TYPE_SPEED)
		end
		conn:Disconnect()
		lineLabel.MaxVisibleGraphemes = -1

		task.wait(0.15)
		hint.Visible = true
		advance.Event:Wait()
	end

	box.Visible = false
	setFrozen(false)
	playing = false
	remote:FireServer("Done")
end

remote.OnClientEvent:Connect(play)