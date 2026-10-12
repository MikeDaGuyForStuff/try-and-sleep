-- NightLoop (Client)
-- Put this LocalScript in: StarterPlayer > StarterPlayerScripts

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local player = Players.LocalPlayer
print("[NightLoop] 1. client script started")
local remote = ReplicatedStorage:WaitForChild("NightEvent")
print("[NightLoop] 2. found NightEvent")

local DEBUG = true   -- prints every message from the server to Output (except task list updates)

local TEXT_COLOR    = Color3.fromRGB(230, 225, 215)
local ACCENT_COLOR  = Color3.fromRGB(200, 170, 140)
local GLITCH_COLOR  = Color3.fromRGB(170, 30, 30)
local NOTE_WIDTH    = 430   -- design width of the sticky note
local NOTE_COLOR    = Color3.fromRGB(240, 226, 130)  -- sticky note paper
local INK_COLOR     = Color3.fromRGB(45, 42, 55)     -- pen
local DONE_COLOR    = Color3.fromRGB(120, 115, 105)  -- crossed-off tasks
local STRIKE_COLOR  = Color3.fromRGB(170, 40, 40)    -- the line through them
local TASK_FONT     = Enum.Font.PatrickHand          -- handwriting
local TITLE_FONT    = Enum.Font.PermanentMarker
local WRITE_SPEED   = 0.025  -- seconds per letter as a task is written down

-- (these used to be further down, after the note that uses them)
local MIN_NOTE_HEIGHT = 235
local LINE_GAP = 12
local TITLE_HEIGHT = 56     -- minimum; long titles make the note taller
local titleHeight = TITLE_HEIGHT

local CREEPY_LINES = {
	"don't sleep",
	"you did this yesterday",
	"turn around",
	"don't open it",
	"why are you still here",
	"it knows your routine",
}

---------------------------------------------------------------------
-- UI
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "NightGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 10
gui.Parent = player:WaitForChild("PlayerGui")

---------------------------------------------------------------------
-- Scaling. Sizes below are for a 1600x900 screen and get scaled to fit.
-- IMPORTANT: UIScale multiplies positions as well as sizes, so the scaled
-- container is pinned to a screen corner and has NO size of its own.
-- Everything inside it is placed in plain pixels from that corner.
---------------------------------------------------------------------
local DESIGN_W, DESIGN_H = 1600, 900

local function screenScale()
	local camera = workspace.CurrentCamera
	if not camera then return 1 end
	local v = camera.ViewportSize
	return math.clamp(math.min(v.X / DESIGN_W, v.Y / DESIGN_H), 0.35, 2.5)
end

-- pinned to the BOTTOM-LEFT corner, zero size
local root = Instance.new("Frame")
root.AnchorPoint = Vector2.new(0, 1)
root.Position = UDim2.new(0, 0, 1, 0)
root.Size = UDim2.new(0, 0, 0, 0)
root.BackgroundTransparency = 1
root.Parent = gui

local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local function updateScale()
	uiScale.Scale = screenScale()
end

updateScale()
task.spawn(function()
	local camera = workspace.CurrentCamera
	while not camera do
		task.wait(0.2)
		camera = workspace.CurrentCamera
	end
	updateScale()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end)

local function addCorner(obj, r)
	Instance.new("UICorner", obj).CornerRadius = UDim.new(0, r)
end

local function addPadding(obj, px)
	local p = Instance.new("UIPadding", obj)
	p.PaddingTop, p.PaddingBottom = UDim.new(0, px), UDim.new(0, px)
	p.PaddingLeft, p.PaddingRight = UDim.new(0, px + 2), UDim.new(0, px + 2)
end

-- Sticky note (bottom-left, inside the TV border). It grows as tasks are added.
local noteShadow = Instance.new("Frame")
noteShadow.AnchorPoint = Vector2.new(0, 1)
noteShadow.Position = UDim2.new(0, 64, 0, -64)
noteShadow.Size = UDim2.new(0, NOTE_WIDTH, 0, MIN_NOTE_HEIGHT)
noteShadow.BackgroundColor3 = Color3.new(0, 0, 0)
noteShadow.BackgroundTransparency = 0.55
noteShadow.BorderSizePixel = 0
noteShadow.Rotation = -2.5
noteShadow.Parent = root

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 60, 0, -70)   -- pixels up from the bottom-left corner
panel.Size = UDim2.new(0, NOTE_WIDTH, 0, MIN_NOTE_HEIGHT)   -- starting height; it grows upwards
panel.BackgroundColor3 = NOTE_COLOR
panel.BorderSizePixel = 0
panel.Rotation = -2.5
panel.Parent = root
addCorner(panel, 3)
addPadding(panel, 18)

-- a strip of tape across the top
local tape = Instance.new("Frame")
tape.AnchorPoint = Vector2.new(0.5, 0)
tape.Position = UDim2.new(0.5, 0, 0, -12)
tape.Size = UDim2.new(0, 115, 0, 32)
tape.BackgroundColor3 = Color3.fromRGB(235, 235, 225)
tape.BackgroundTransparency = 0.45
tape.BorderSizePixel = 0
tape.Rotation = 4
tape.ZIndex = 2
tape.Parent = panel

-- the written lines live in here, each one placed by hand so they can never stack up
local list = Instance.new("Frame")
list.Position = UDim2.new(0, 0, 0, TITLE_HEIGHT)
list.Size = UDim2.new(1, 0, 1, -TITLE_HEIGHT)
list.BackgroundTransparency = 1
list.Parent = panel

local function makeLabel(parent, text, size, order)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Font = TASK_FONT
	l.TextSize = size
	l.TextColor3 = INK_COLOR
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextWrapped = true
	l.RichText = true
	l.Text = text
	l.LayoutOrder = order or 0
	l.Parent = parent
	return l
end

local title = makeLabel(panel, "Night 1", 38, 0)
title.Font = TITLE_FONT
title.AutomaticSize = Enum.AutomaticSize.None
title.Size = UDim2.new(1, 0, 0, TITLE_HEIGHT)

-- Fade screen
local fade = Instance.new("Frame")
fade.Size = UDim2.fromScale(1, 1)
fade.BackgroundColor3 = Color3.new(0, 0, 0)
fade.BackgroundTransparency = 0
fade.BorderSizePixel = 0
fade.ZIndex = 50
fade.Parent = gui
print("[NightLoop] 3. black screen created")

local center = Instance.new("TextLabel")
center.Size = UDim2.fromScale(1, 1)
center.BackgroundTransparency = 1
center.Font = Enum.Font.SpecialElite
center.TextSize = 56
center.TextColor3 = TEXT_COLOR
center.TextTransparency = 1
center.ZIndex = 51
center.Parent = fade

-- keep the big "Night 1" text readable on any screen
task.spawn(function()
	while true do
		center.TextSize = math.clamp(math.floor(56 * screenScale()), 24, 120)
		task.wait(1)
	end
end)

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local gotResponse = false
local waking = false

-- Failsafe that starts right away: if the server hasn't answered in 12 seconds,
-- remove the black screen no matter what the rest of the script is doing
task.delay(12, function()
	if gotResponse then return end
	warn("[NightLoop] server never answered - removing black screen. Send the [NightLoop] lines from Output.")
	fade.BackgroundTransparency = 1
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.WalkSpeed == 0 then hum.WalkSpeed = 12 end
end)

local savedSpeed
local function setFrozen(frozen)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	if frozen then
		if hum.WalkSpeed > 0 then savedSpeed = hum.WalkSpeed end
		hum.WalkSpeed = 0
	else
		hum.WalkSpeed = savedSpeed or 12
	end
end

local function tween(obj, time, props)
	local t = TweenService:Create(obj, TweenInfo.new(time, Enum.EasingStyle.Sine), props)
	t:Play()
	return t
end

local function showText(text, hold)
	center.Text = text
	tween(center, 0.8, { TextTransparency = 0 }).Completed:Wait()
	task.wait(hold)
	tween(center, 0.8, { TextTransparency = 1 }).Completed:Wait()
end

---------------------------------------------------------------------
-- Task list (written onto the note as tasks appear)
---------------------------------------------------------------------
local rows = {}          -- one per task line currently on the note
local currentState
local shownNight = nil

-- writes text out letter by letter, like someone jotting it down
local function writeOn(label, text)
	label.Text = text
	label.MaxVisibleGraphemes = 0
	local total = utf8.len(text) or #text
	for i = 1, total do
		if not label.Parent then return end
		label.MaxVisibleGraphemes = i
		task.wait(WRITE_SPEED)
	end
	label.MaxVisibleGraphemes = -1
end

local TEXT_WIDTH = NOTE_WIDTH - 40   -- note width minus the padding
local cursorY = 0                    -- where the next line goes

local function updateNoteHeight()
	local height = math.max(MIN_NOTE_HEIGHT, titleHeight + cursorY + 32)
	panel.Size = UDim2.new(0, NOTE_WIDTH, 0, height)
	noteShadow.Size = UDim2.new(0, NOTE_WIDTH, 0, height)
end

local function makeRow(text, size, order, color)
	-- measure the line first, then place it below the previous one
	local measured = TextService:GetTextSize("- " .. text, size, TASK_FONT, Vector2.new(TEXT_WIDTH, 1e6))
	local height = math.max(measured.Y, size) + 4

	local row = Instance.new("Frame")
	row.Position = UDim2.new(0, 0, 0, cursorY)
	row.Size = UDim2.new(1, 0, 0, height)
	row.BackgroundTransparency = 1
	row.Rotation = (math.random() - 0.5) * 3.5   -- each line sits at its own slight angle
	row.Parent = list

	cursorY = cursorY + height + LINE_GAP
	updateNoteHeight()

	local indent = (order % 3) * 5               -- uneven left edge, like real handwriting
	local label = makeLabel(row, "", size, order)
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Position = UDim2.new(0, indent, 0, 0)
	label.Size = UDim2.new(1, -indent, 1, 0)
	label.TextColor3 = color or INK_COLOR

	-- the pen line drawn through a finished task
	local strike = Instance.new("Frame")
	strike.AnchorPoint = Vector2.new(0, 0.5)
	strike.Position = UDim2.new(0, 0, 0, math.floor(size * 0.62))
	strike.Size = UDim2.new(0, 0, 0, 3)
	strike.BackgroundColor3 = STRIKE_COLOR
	strike.BorderSizePixel = 0
	strike.ZIndex = 3
	strike.Parent = row

	local entry = { row = row, label = label, strike = strike, text = "", done = false }
	table.insert(rows, entry)
	return entry
end

local function clearNote()
	for _, entry in ipairs(rows) do entry.row:Destroy() end
	rows = {}
	cursorY = 0
	updateNoteHeight()
end

local function crossOff(entry)
	if entry.done then return end
	entry.done = true
	entry.label.TextColor3 = DONE_COLOR
	-- TextBounds is in real screen pixels, which already include the UI scale,
	-- while the strike's size is in design pixels that get scaled again.
	local scale = math.max(uiScale.Scale, 0.01)
	local width = math.max(entry.label.TextBounds.X / scale, 20)
	TweenService:Create(entry.strike, TweenInfo.new(0.35, Enum.EasingStyle.Sine), {
		Size = UDim2.new(0, width + 8, 0, 3),
	}):Play()
end

local function render(state)
	currentState = state

	-- new night: start a fresh note
	if shownNight ~= state.night then
		shownNight = state.night
		clearNote()

		-- the night's own title, e.g. "Its still Night 1"
		local text = state.title or ("Night " .. state.night)
		title.Text = text

		-- long titles need more room, and push the tasks further down
		local measured = TextService:GetTextSize(text, title.TextSize, TITLE_FONT,
			Vector2.new(NOTE_WIDTH - 40, 1e6))
		titleHeight = math.max(TITLE_HEIGHT, measured.Y + 10)
		title.Size = UDim2.new(1, 0, 0, titleHeight)
		list.Position = UDim2.new(0, 0, 0, titleHeight)
		list.Size = UDim2.new(1, 0, 1, -titleHeight)
		updateNoteHeight()
	end

	for i, t in ipairs(state.tasks) do
		local entry = rows[i]
		if not entry then
			entry = makeRow(t.name, 31, i)
			entry.text = t.name
			task.spawn(writeOn, entry.label, "- " .. t.name)
		elseif entry.text ~= t.name then
			-- e.g. the (1/3) counter going up
			entry.text = t.name
			entry.label.Text = "- " .. t.name
			entry.label.MaxVisibleGraphemes = -1
		end
		if t.done then crossOff(entry) end
	end

	if state.bedReady and not rows[#state.tasks + 1] then
		local entry = makeRow("Go to bed.", 33, 100, Color3.fromRGB(150, 60, 50))
		entry.text = "Go to bed."
		task.spawn(writeOn, entry.label, "- Go to bed.")
	end
end

-- Task lines sometimes flash creepy text on later nights
task.spawn(function()
	while true do
		task.wait(math.random(4, 9))
		local s = currentState
		if s and s.intensity >= 0.5 and #rows > 0 and math.random() < s.intensity * 0.7 then
			local entry = rows[math.random(#rows)]
			local label = entry.label
			local realText, realColor = label.Text, label.TextColor3
			label.Text = "- " .. CREEPY_LINES[math.random(#CREEPY_LINES)]
			label.MaxVisibleGraphemes = -1
			label.TextColor3 = GLITCH_COLOR
			task.wait(0.12 + math.random() * 0.12)
			if label.Parent then
				label.Text = realText
				label.TextColor3 = realColor
			end
		end
	end
end)

---------------------------------------------------------------------
-- Server events
---------------------------------------------------------------------
remote.OnClientEvent:Connect(function(action, data, titleText)
	if DEBUG and action ~= "State" then
		print("[NightLoop] got " .. tostring(action) .. " " .. tostring(data))
	end

	if action == "State" then
		render(data)

	elseif action == "Hold" then
		-- the server is mid-cutscene: stop asking, but don't show anything yet
		gotResponse = true

	elseif action == "Cinematic" then
		-- the sticky note and the TV frame get out of the way
		panel.Visible = not data
		noteShadow.Visible = not data

	elseif action == "FadeOut" then
		setFrozen(true)
		tween(fade, data, { BackgroundTransparency = 0 })

	elseif action == "FadeIn" then
		tween(fade, data, { BackgroundTransparency = 1 }).Completed:Wait()
		setFrozen(false)

	elseif action == "Sleep" then
		setFrozen(true)
		tween(fade, 1.5, { BackgroundTransparency = 0 })

	elseif action == "Wake" then
		print("[NightLoop] 6. server answered, waking up")
		gotResponse = true
		if waking then return end -- ignore duplicate wake messages
		waking = true
		fade.BackgroundTransparency = 0
		setFrozen(true)
		showText(titleText or ("Night " .. data), 1.2)
		tween(fade, 2, { BackgroundTransparency = 1 })
		setFrozen(false)
		waking = false

	elseif action == "EndScreen" then
		-- the Cinematic script draws the end screen itself; this one just
		-- stops asking the server and gets the note out of the way
		gotResponse = true
		setFrozen(true)
		panel.Visible = false
		noteShadow.Visible = false

	elseif action == "Ending" then
		-- old ending (the server no longer sends this, kept just in case)
		gotResponse = true
		setFrozen(true)
		panel.Visible = false
		noteShadow.Visible = false
		tween(fade, 1.5, { BackgroundTransparency = 0 }).Completed:Wait()
		showText(titleText or ("Night " .. data), 1.5)
		center.TextColor3 = GLITCH_COLOR
		showText("there are no more chores.", 2)
		center.TextColor3 = TEXT_COLOR
		center.Text = "you can wake up now."
		tween(center, 2, { TextTransparency = 0 })
	end
end)

---------------------------------------------------------------------
-- Joining: keep telling the server we're ready until it answers.
-- (If the first message gets missed while the game is still loading,
-- the screen would otherwise stay black forever.)
---------------------------------------------------------------------
print("[NightLoop] 4. waiting for character")
if not player.Character then player.CharacterAdded:Wait() end
print("[NightLoop] 5. character loaded, telling server we're ready")

task.spawn(function()
	while not gotResponse do
		remote:FireServer("Ready")
		task.wait(1.5)
	end
end)