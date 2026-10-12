-- NightLoop (Server)
-- Put this Script in: ServerScriptService
--
-- Workspace setup:
--   workspace.Tasks        (Folder) - one part/model per task, named to match "task" in NIGHTS
--                          (e.g. "Sink", "Broom", "FrontDoor"). Optional attribute: HoldTime (number)
--                          Task objects are invisible and can't be touched until the first night
--                          they're used. Add a true "AlwaysVisible" attribute to keep one visible
--                          (use this for things that are part of the house, like the front door).
--   workspace["nice bed"]  (Part or Model) - the bed
--   workspace.WakeUpPoint  (Part, optional) - where you're placed each new night
--   workspace.HouseLights  (Folder, optional) - lamps with PointLights/SpotLights to dim and flicker
--
-- For the dishes:
--   workspace.Tasks.Sink   (Model) - contains "interactpart" (with the ProximityPrompt) and "DishStack"
--   DishStack              (Model inside Sink) - parts named exactly "Plate" get the dirty texture;
--                          everything else (the rack) is never touched
--   A Sound named "DishSound" in workspace or ServerStorage (washing/clinking sound from the Toolbox)
--
-- For sweeping:
--   workspace.Tasks.Broom  (Part or Model) - the broom you pick up (it hides while you sweep)
--   workspace.Tasks.Dirt1, Dirt2, Dirt3 (Parts) - the three dirt spots, same place every night.
--                          Thin, CanCollide off, with a dirt Decal on the Top face works best.
--   A Sound named "SweepSound" in workspace or ServerStorage
--
-- Going inside (start of EVERY night):
--   workspace.EntryZone    (Part or Model of parts, invisible, CanCollide off) - just INSIDE the front door.
--                          The door stays open until you walk into this box, then it closes behind you.
--                          (If it's missing, the door just stays open so you're never locked out.)
--
-- For setting the table (nights 4 and 5):
--   workspace.Tasks.Table  (Model) - an INVISIBLE interaction volume. The script hides every
--                          part in it automatically except "ProxHolder", which holds the
--                          ProximityPrompt. Nothing to set up by hand.
--                          (Edit INVISIBLE_TASKS below to change which part is kept.)
--   TableSettings          (Model) - the table and chairs. Always visible, wherever you put it.
--                          Parts named "Plate" inside Tasks.Table are the place settings:
--                          they start invisible and appear when the table is set.
--
-- For night 5's table scene (these can live anywhere, including inside Tasks.Table):
--   TableSeat              (Part) - where the player is put, facing the plate
--   PlateSpot              (Part, invisible, CanCollide off) - black bars flicker inside this space
--   BedLieSpot             (Part) - where the player lies down at the end. Put it at head height
--                          and point its FRONT toward the player's FEET. The camera looks at the
--                          ceiling and can only turn 90 degrees to each side from there.
--
-- For the door scene (night 3):
--   A door named "FrontDoor" somewhere in workspace (ANCHORED part or model).
--       Optional attributes: HingeSide (1 or -1), OpenAngle (degrees)
--   ServerStorage.Jeff     (Model, all parts anchored) - the character at the door
--   workspace.VisitorSpot  (Part, invisible, CanCollide off) - where the visitor stands
--   A Sound named "KnockSound" in workspace or ServerStorage
--   A Sound named "hospital beep" in workspace or ServerStorage (tick it Looped for a heart monitor)

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

-- This must run on the SERVER. If it's a LocalScript, or sitting in
-- StarterCharacterScripts / StarterPlayerScripts, stop with a clear message.
if game:GetService("RunService"):IsClient() then
	warn("[NightLoop] WRONG PLACE: this is the SERVER script. Delete it from " .. script:GetFullName()
		.. " and put it in a normal Script (not a LocalScript) inside ServerScriptService.")
	return
end

---------------------------------------------------------------------
-- THE NIGHTS
-- Tasks happen in order. Each step can have:
--   onStart    = actions that run when the task appears
--   onComplete = actions that run after the player holds E on it
--
-- Actions:
--   {"Wait", seconds}
--   {"FadeOut", seconds}          {"FadeIn", seconds}
--   {"Sound", "SoundName"}        {"SoundWait", "SoundName"}  (waits until the sound ends)
--   {"SoundEvery", "SoundName", seconds}     (repeats it forever; seconds = 0 stops it)
--   {"SoundLoop", "SoundName"}   {"SoundStop", "SoundName"}   (loops until stopped, cuts off instantly)
--   {"Flicker", seconds}
--   {"MoveTo", "ObjectName", "SpotName"}
--   {"SetDirty", "ObjectName", true/false}   (adds/removes the dirty texture on parts named "Plate")
--   {"OpenDoor", "DoorName"}      {"CloseDoor", "DoorName"}
--   {"Show", "ModelInServerStorage", "SpotName"}      {"Hide", "ModelName"}
--   {"Dialogue", { "A thought", {"Speaker", "A line"} }}
--   {"SetVisible", "ObjectName", true/false, fadeSeconds}   (puts it back how it was built)
--   {"Reveal", "ObjectName", fadeSeconds}     (forces it fully visible)
--   {"Conceal", "ObjectName", fadeSeconds}    (forces it fully invisible)
--   {"RevealParts", "ObjectName", "PartName", fadeSeconds}    (only the parts with that name)
--   {"ConcealParts", "ObjectName", "PartName", fadeSeconds}
--   {"EnterHouse", "DoorName", "ZoneName"}   (opens door, waits until you're inside, closes it)
--   {"TeleportTo", "SpotName"}                (moves the player to a part)
--   {"Cinematic", true/false}                 (hides the TV overlay + sticky note)
--   {"Zoom", fieldOfView, seconds}            (70 is normal, lower = zoomed in)
--   {"BlackFog", seeDistance, seconds}        (thick black fog; use 0 to clear it)
--   {"Censor", "SpotName", true/false}        (flickering black bars over whatever is at that part)
--   {"LieDown", "SpotName"}                   (camera locked lying down; {"LieDown"} releases it)
--   {"SoundsOff", seconds}  {"SoundsOn", seconds}   (fades the static/ambience/music out or back in)
--   {"MiniGame", "scrub", { rounds = 3, need = 2200, title = "Scrub the plate" }}
--   {"MiniGame", "timing", { rounds = 3, speed = 1.1, zone = 0.18, title = "Sweep" }}
--   {"Async", { ...actions... }}              (runs those actions WITHOUT waiting, e.g. during dialogue)
--
-- Group steps: use  tasks = {"A", "B", "C"}  instead of  task = "A"
--   All of them light up at once and can be done in any order.
--   eachText = prompt text on each one, onEach = actions after each one ("$task" = the one just done)
--
-- name = the title shown on the black wake-up screen, e.g. name = "The Smell".
--   Leave it out for the plain "Night 1". The sticky note always says "Night 1".
--
-- intro = dialogue shown when the player wakes up, before the first task appears.
--   Plain text = the player's own thoughts (shown in italics).
--   {"Name", "Text"} = someone speaking.
---------------------------------------------------------------------

local DIRTY_TEXTURE = "rbxassetid://5161635723"   -- dirty plate texture
local DIRT_TRANSPARENCY = 0               -- 0 = fully visible, higher = fainter dirt
local PLATE_NAME = "Plate"                -- only parts with exactly this name get dirty
local HOSPITAL_BEEP_INTERVAL = 5          -- seconds between hospital beeps

-- Added to EVERY night's saturation. Raise it for an even more vivid look,
-- drop it to 0 to use the per-night values on their own.
local SATURATION_BOOST = 0.55

-- Task objects that are ALWAYS invisible (they're just interaction volumes).
-- The listed part is left alone, because the ProximityPrompt lives on it.
local INVISIBLE_TASKS = {
	Table = "ProxHolder",
}

-- Objects the script must NEVER hide, even if they sit inside the Tasks folder
local NEVER_HIDE = {
	TableSettings = true,   -- the table and chairs
	TableSetting = true,
}

-- Runs at the start of every night (puts things back how they were)
-- (Task objects are shown/hidden automatically each night, so the broom and dirt reset on their own)
local NIGHT_START = {
	{"SetDirty", "DishStack", true},
	{"ConcealParts", "Table", "Plate"},   -- the table starts bare again
}

-- Reusable dishes step: black screen, sound, dirt texture is removed from the plates
local DO_DISHES = {
	task = "Sink",
	text = "Do the dishes",
	onComplete = {
		{"SoundLoop", "DishSound"},
		{"MiniGame", "scrub", { rounds = 3, need = 2200, title = "Scrub the plate" }},
		{"SoundStop", "DishSound"},   -- cut it off the moment the plates are done
		{"SetDirty", "DishStack", false},
	},
}

-- Sweeping: grab the broom, then sweep the three dirt spots (any order)
local GRAB_BROOM = {
	task = "Broom",
	text = "Grab the broom",
	onComplete = {
		{"SetVisible", "Broom", false},
	},
}

local SWEEP_DIRT = {
	tasks = {"Dirt1", "Dirt2", "Dirt3"},
	text = "Sweep up the dirt",
	eachText = "Sweep",
	onEach = {
		{"MiniGame", "timing", { rounds = 3, speed = 1.1, zone = 0.18, title = "Sweep" }},
		{"Sound", "SweepSound"},
		{"SetVisible", "$task", false, 0.6},
	},
	onComplete = {
		{"SetVisible", "Broom", true},  -- broom goes back where it was
	},
}

-- Setting the table (normal version, used on night 4)
-- This reveals the parts named "Plate" inside Tasks.Table - it does NOT hide the table.
local SET_TABLE = {
	task = "Table",
	text = "Set the table",
	onComplete = {
		{"RevealParts", "Table", "Plate", 0.4},
	},
}

-- Night 5: setting the table goes wrong
local NIGHT5_TABLE = {
	task = "Table",
	text = "Set the table",
	onComplete = {
		{"RevealParts", "Table", "Plate", 0.4},
		{"Dialogue", {
			"there, plates set agian, now to go to...wait...",
			{"You", "...Who's there?...."},
			"ME",
		}},
		-- halfway through the dialogue: the TV frame drops away and the room closes in
		{"Async", {
			{"Cinematic", true},
			{"Zoom", 42, 5},
			{"BlackFog", 14, 6},
		}},
		{"Dialogue", {
			"SIT AND FEAST",
			{"You", "I can't see the walls. Where are the walls?"},
			"...SIT YOU FOOL",
		}},

		-- at the table, with something on the plate
		{"FadeOut", 0.8},
		{"TeleportTo", "TableSeat"},
		{"Censor", "PlateSpot", true},
		{"FadeIn", 1.2},
		{"Wait", 5},
		{"Dialogue", {
			"FEAST ON YOUR FLESH",
			{"You", "please....it hurts"},
			"...I KNOW.....we are starving",
		}},

		-- and then, bed (the hospital scene below is added onto the end of this)
		{"FadeOut", 1.5},
		{"Censor", "PlateSpot", false},
	},
}

-- The hospital scene: lying in bed, only the heart monitor left.
-- Used at the end of night 5, and by START_AT_HOSPITAL for testing.
-- No dialogue in here, so nothing can get stuck waiting for a click.
-- The end screen starts by itself END_SCREEN.delay seconds after the last line.
local HOSPITAL_SCENE = {
	{"Cinematic", true},          -- no TV frame or sticky note
	{"Zoom", 42, 0},
	{"BlackFog", 14, 0},
	{"TeleportTo", "BedLieSpot"},
	{"SoundsOff", 1},             -- everything goes quiet
	{"LieDown", "BedLieSpot"},
	{"Wait", 0.5},
	{"SoundEvery", "hospital beep", HOSPITAL_BEEP_INTERVAL},  -- ...except this
	{"FadeIn", 2.5},
	{"EndGame"},                  -- waits END_SCREEN.delay, then shows the end screen
}

for _, action in ipairs(HOSPITAL_SCENE) do
	table.insert(NIGHT5_TABLE.onComplete, action)
end

-- Every night starts with going inside through the front door
local ENTER_HOUSE = {
	task = "FrontDoor",
	text = "Go inside",
	onComplete = {
		{"EnterHouse", "FrontDoor", "EntryZone"},
	},
}

-- The door scene (night 3)
local DOOR_SCENE = {
	task = "FrontDoor",
	text = "Answer the door",
	onStart = {
		{"Flicker", 0.8},
		{"Sound", "KnockSound"},
	},
	onComplete = {
		{"OpenDoor", "FrontDoor"},
		{"Show", "Jeff", "VisitorSpot"},
		{"Wait", 1},
		{"Dialogue", {
			{"???", "Its been forever man, are you ok? You havn't been answering any of my calls?"},
			{"You", "what do you mean? we just hanged out today?"},
			{"???", "Please man, I just want to know if your ok"},
			"Whats happening? Can't he hear me?",
			{"You", "Ya man, I have been doing -"},
		}},
		{"Hide", "Jeff"},
		{"Wait", 1},
		{"CloseDoor", "FrontDoor"},
		{"Dialogue", {
			{"You", "What is happening? WHY cant I sleep?"},
		}},
	},
}

---------------------------------------------------------------------
-- OPENING CUTSCENE
-- The camera physically flies from one part to another (no zoom trickery)
-- while short lines play by themselves. Nothing can be clicked through.
-- Needs two parts in Workspace: FlyStart (far away, aimed at the house)
-- and FlyEnd (just outside the front door, at eye height).
---------------------------------------------------------------------
local INTRO_CUTSCENE = {
	enabled = true,
	from = "FlyStart",
	to = "FlyEnd",
	duration = 11,          -- how long the flight takes
	landing = "FlyEnd",     -- where the player ends up (nil = leave them at spawn)
	lines = {
		"Another shift over.",
		"Clean up, then sleep.",
		"That's all tonight is.",
	},
}

---------------------------------------------------------------------
-- END SCREEN (shown after sleeping on the last night)
-- Change any of this text to whatever you want.
---------------------------------------------------------------------
local END_SCREEN = {
	delay = 5,                           -- seconds in the hospital bed before the end screen starts
	title = "there is no morning",        -- big text at the top ("" for none)
	lines = {                             -- typed out one at a time, each replaces the last
		"You never made it out of that bed.",
		"The dishes are still dirty.",
		"They always will be.",
	},
	footer = "Thank you for playing",     -- small text at the bottom ("" for none)
	fadeTime = 3,                         -- how long the fade to black takes
	lineHold = 2.5,                       -- how long each line stays after it finishes typing
}

---------------------------------------------------------------------
-- TESTING
---------------------------------------------------------------------
-- Which night the game begins on. 1 = normal. Set it to 4 (or 5) to jump
-- straight there while testing, then put it back to 1.
local START_NIGHT = 1
-- (Any START_NIGHT above 1 skips the flying intro and goes straight to that night's title card.)

-- Set to true to skip EVERYTHING and go straight to the hospital scene
-- (lying in bed, heart monitor, then the end screen). No dialogue, no tasks.
local START_AT_HOSPITAL = false
local HOSPITAL_LOAD_DELAY = 10   -- seconds to let the player load in first

-- Prints what the script is doing to the Output window, so you can see
-- where things stop. Set to false once everything works.
local DEBUG = true

-- Set to true to put a door scene with test dialogue at the very start
-- of night 1. Set back to false when you're done testing.
local TEST_DOOR_FIRST = false

local TEST_DOOR_SCENE = {
	task = "FrontDoor",
	text = "Answer the door (TEST)",
	onStart = {
		{"Flicker", 0.8},
		{"Sound", "KnockSound"},
	},
	onComplete = {
		{"OpenDoor", "FrontDoor"},
		{"Show", "Jeff", "VisitorSpot"},
		{"Wait", 1},
		{"Dialogue", {
			{"???", "This is a test line. Can you hear my voice?"},
			{"???", "Short one."},
			{"???", "And this is a much longer line, so you can hear how the voice sounds when someone keeps talking for a while."},
			"This is what the player's thoughts look like.",
			{"You", "And this is the player talking out loud."},
		}},
		{"Wait", 0.5},
		{"Hide", "Jeff"},
		{"Wait", 1},
		{"CloseDoor", "FrontDoor"},
	},
}

local NIGHTS = {
	{ -- Night 1
		name = "Night 1",
		intro = {
			"Finally home.",
			"I smell dirt, I should clean up before bed.",
		},
		DO_DISHES,
	},

	{ -- Night 2
		name = "Its still Night 1",
		intro = {
			"Wait, why am I outside? I smell the dirt as well again. Didn't I already do the dishes?",
			"...They're dirty again.",
			"...And its more dirty than it was just now...",
		},
		DO_DISHES,
		GRAB_BROOM,
		SWEEP_DIRT,
	},

	{ -- Night 3
		name = "Night 1....agian",
		intro = {
			"...I feel like I am going insane. Please, God, let me just rest for once...",
			"Why do I feel smaller tonight?",
		},
		DO_DISHES,
		GRAB_BROOM,
		SWEEP_DIRT,
		DOOR_SCENE,
	},

	{ -- Night 4
		name = "Will it ever end? this pain?",
		intro = {
			"Its all ok, I'm going to be ok.",
			"MAN I'm starving, but I'm more tired than starving",
			"I'll set the table tonight, but I really got to go to bed soon.",
		},
		DO_DISHES,
		GRAB_BROOM,
		SWEEP_DIRT,
		SET_TABLE,
	},

	{ -- Night 5  (task 5 is the table scene: "Go inside" counts as task 1)
		name = "there is no night",
		intro = {
			"I can't sleep....Oh my God.....",
			"...Its hopeless....maybe there is repreive in this nightmare....",
			"I need to reset the table first because OF COURSE the house reset, but...",
			"At least I will be able to eat.",
		},
		DO_DISHES,
		GRAB_BROOM,
		SWEEP_DIRT,
		NIGHT5_TABLE,
	},
}

-- Put "Go inside" first on every night, then the test scene (if turned on)
for n, steps in ipairs(NIGHTS) do
	table.insert(steps, 1, ENTER_HOUSE)
	if n == 1 and TEST_DOOR_FIRST then
		table.insert(steps, 2, TEST_DOOR_SCENE)
	end
end

local SLEEP_TIME = 2.5   -- black screen between nights
local WAKE_DELAY = 4     -- wait for the wake-up fade before the intro/first task

-- Lighting presets, one per night (spread automatically if you add more nights).
-- Night 1 is bright and colourful, then the colour drains out and it gets darker
-- and more realistic each night.
-- If a night is too dark for your house, raise its Ambient / Outdoor numbers.
local PRESETS = {
	{ -- Night 1: warm, bright, almost cheerful
		ClockTime = 18, Brightness = 2.5, Exposure = 0.15,
		Ambient = Color3.fromRGB(130, 120, 110), Outdoor = Color3.fromRGB(150, 140, 128),
		Saturation = 0.55, Contrast = 0, Tint = Color3.fromRGB(255, 246, 230),
		Blur = 0, Density = 0.15, Haze = 0.2, AtmoColor = Color3.fromRGB(230, 195, 150),
		Flicker = 0, LightScale = 1, RedShift = 0,
	},
	{ -- Night 2: evening, still colourful but calming down
		ClockTime = 19.5, Brightness = 2, Exposure = 0.05,
		Ambient = Color3.fromRGB(110, 102, 96), Outdoor = Color3.fromRGB(120, 112, 106),
		Saturation = 0.40, Contrast = 0.05, Tint = Color3.fromRGB(255, 242, 226),
		Blur = 0, Density = 0.2, Haze = 0.4, AtmoColor = Color3.fromRGB(200, 172, 145),
		Flicker = 0.002, LightScale = 1, RedShift = 0,
	},
	{ -- Night 3: plain and realistic, colour starting to drain
		ClockTime = 21, Brightness = 1.4, Exposure = 0,
		Ambient = Color3.fromRGB(80, 80, 86), Outdoor = Color3.fromRGB(80, 82, 92),
		Saturation = 0.20, Contrast = 0.1, Tint = Color3.fromRGB(240, 242, 250),
		Blur = 0, Density = 0.3, Haze = 0.7, AtmoColor = Color3.fromRGB(150, 155, 170),
		Flicker = 0.008, LightScale = 0.9, RedShift = 0,
	},
	{ -- Night 4: dark, grey, flickering
		ClockTime = 23, Brightness = 0.85, Exposure = -0.1,
		Ambient = Color3.fromRGB(52, 52, 58), Outdoor = Color3.fromRGB(48, 50, 58),
		Saturation = -0.05, Contrast = 0.2, Tint = Color3.fromRGB(230, 234, 245),
		Blur = 0, Density = 0.4, Haze = 1.1, AtmoColor = Color3.fromRGB(105, 110, 125),
		Flicker = 0.014, LightScale = 0.8, RedShift = 0.1,
	},
	{ -- Night 5: almost no colour left, lit only by what's still working
		ClockTime = 1, Brightness = 0.5, Exposure = -0.15,
		Ambient = Color3.fromRGB(34, 32, 36), Outdoor = Color3.fromRGB(30, 30, 36),
		Saturation = -0.35, Contrast = 0.3, Tint = Color3.fromRGB(235, 225, 225),
		Blur = 0, Density = 0.5, Haze = 1.6, AtmoColor = Color3.fromRGB(70, 68, 76),
		Flicker = 0.028, LightScale = 0.7, RedShift = 0.2,
	},
}
---------------------------------------------------------------------

local function dprint(...)
	if DEBUG then print("[NightLoop]", ...) end
end

print("[NightLoop] SERVER A. script started")
local tasksFolder = workspace:WaitForChild("Tasks")
local bed         = workspace:WaitForChild("nice bed")
local wakePoint   = workspace:FindFirstChild("WakeUpPoint")
local houseLights = workspace:FindFirstChild("HouseLights")

print("[NightLoop] SERVER B. found Tasks and bed")
-- Reuse the remote if one already exists (never make a second copy,
-- or the client might talk to the wrong one and the screen stays black)
local function getRemote(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = ReplicatedStorage
	return r
end

local remote = getRemote("NightEvent")

-- Separate remotes used by the Dialogue_Client and MiniGame_Client scripts
local dialogueRemote = getRemote("DialogueEvent")
local miniRemote = getRemote("MiniGameEvent")

local miniFinished = false
local miniAlive = 0
miniRemote.OnServerEvent:Connect(function(_, action)
	if action == "Done" then
		miniFinished = true
	elseif action == "Alive" then
		miniAlive = os.clock()
	end
end)

local dialogueFinished = false
local dialogueAlive = 0
dialogueRemote.OnServerEvent:Connect(function(_, action)
	if action == "Done" then
		dialogueFinished = true
	elseif action == "Alive" then
		-- the player still has the box open and is reading
		dialogueAlive = os.clock()
	end
end)

---------------------------------------------------------------------
-- Lighting
---------------------------------------------------------------------
local function getEffect(className, name)
	local e = Lighting:FindFirstChild(name) or Instance.new(className)
	e.Name = name
	e.Parent = Lighting
	return e
end
local cc   = getEffect("ColorCorrectionEffect", "NightColor")
local blur = getEffect("BlurEffect", "NightBlur")
local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or getEffect("Atmosphere", "NightAtmosphere")

local lights = {}
if houseLights then
	for _, d in ipairs(houseLights:GetDescendants()) do
		if d:IsA("Light") then
			table.insert(lights, { light = d, brightness = d.Brightness, color = d.Color })
		end
	end
end

local flickerChance = 0
local RED = Color3.fromRGB(255, 60, 50)

local function applyPreset(p)
	Lighting.ClockTime = p.ClockTime
	Lighting.Brightness = p.Brightness
	Lighting.ExposureCompensation = p.Exposure
	Lighting.Ambient = p.Ambient
	Lighting.OutdoorAmbient = p.Outdoor
	cc.Saturation = math.clamp(p.Saturation + SATURATION_BOOST, -1, 2)
	cc.Contrast = p.Contrast
	cc.TintColor = p.Tint
	blur.Size = p.Blur
	atmo.Density = p.Density
	atmo.Haze = p.Haze
	atmo.Color = p.AtmoColor
	atmo.Decay = p.AtmoColor:Lerp(Color3.new(0, 0, 0), 0.5)
	for _, info in ipairs(lights) do
		info.light.Brightness = info.brightness * p.LightScale
		info.light.Color = info.color:Lerp(RED, p.RedShift)
	end
	flickerChance = p.Flicker
end

local function presetFor(night)
	if #NIGHTS <= 1 then return PRESETS[1] end
	local i = 1 + math.floor((night - 1) / (#NIGHTS - 1) * (#PRESETS - 1) + 0.5)
	return PRESETS[i]
end

task.spawn(function()
	while true do
		task.wait(0.1)
		if flickerChance > 0 then
			for _, info in ipairs(lights) do
				if math.random() < flickerChance then
					task.spawn(function()
						for _ = 1, math.random(2, 5) do
							info.light.Enabled = false
							task.wait(0.03 + math.random() * 0.08)
							info.light.Enabled = true
							task.wait(0.03 + math.random() * 0.12)
						end
					end)
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------
-- Looks inside the Tasks folder first. Without this, a part named "Table"
-- inside your furniture model could be found instead of Tasks.Table.
local function findThing(name)
	return tasksFolder:FindFirstChild(name, true) or workspace:FindFirstChild(name, true)
end

local ACTIONS = {}
local doorStates = {}
local shown = {}

-- stopWhen (optional): a function checked while the door moves; if it returns true
-- the door stops right where it is
local function swingDoor(name, open, stopWhen)
	local door = findThing(name)
	if not door then warn("NightLoop: no door named " .. name) return end

	local state = doorStates[door]
	if not state then
		local cf, size
		if door:IsA("Model") then cf, size = door:GetBoundingBox() else cf, size = door.CFrame, door.Size end
		local side = door:GetAttribute("HingeSide") or 1
		state = {
			closed = door:GetPivot(),
			frame = cf,  -- the door's closed position, used to tell which side players are on
			side = side >= 0 and 1 or -1,
			hinge = cf * CFrame.new(side * size.X / 2, 0, 0),
			angle = 0,
		}
		doorStates[door] = state
	end

	local target = 0
	if open then
		-- find the closest player and swing the door AWAY from them
		local closestDist, closestPos = math.huge, nil
		for _, plr in ipairs(Players:GetPlayers()) do
			local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local dist = (hrp.Position - state.frame.Position).Magnitude
				if dist < closestDist then
					closestDist, closestPos = dist, hrp.Position
				end
			end
		end

		local dir = 1
		if closestPos then
			local playerSide = state.frame:PointToObjectSpace(closestPos).Z >= 0 and 1 or -1
			dir = -playerSide * state.side
		end
		target = math.rad(door:GetAttribute("OpenAngle") or 90) * dir
	end
	local value = Instance.new("NumberValue")
	value.Value = state.angle
	value.Changed:Connect(function(a)
		state.angle = a
		door:PivotTo(state.hinge * CFrame.Angles(0, a, 0) * state.hinge:Inverse() * state.closed)
	end)
	-- closing from halfway takes less time than closing from fully open
	local fullAngle = math.rad(door:GetAttribute("OpenAngle") or 90)
	local duration = open and 2.5 or math.max(0.3, 1 * math.abs(state.angle) / fullAngle)

	local tween = TweenService:Create(value, TweenInfo.new(duration, Enum.EasingStyle.Sine), { Value = target })
	tween:Play()
	if stopWhen then
		while tween.PlaybackState == Enum.PlaybackState.Playing do
			if stopWhen() then
				tween:Cancel()
				break
			end
			task.wait(0.05)
		end
	else
		tween.Completed:Wait()
	end
	value:Destroy()
end

ACTIONS.Wait = function(seconds)
	task.wait(seconds or 1)
end

local function findSound(name)
	local s = findThing(name) or ServerStorage:FindFirstChild(name, true)
	if not (s and s:IsA("Sound")) then
		warn("NightLoop: no sound named " .. name)
		return nil
	end
	if not s:IsDescendantOf(workspace) then
		s = s:Clone()
		s.Parent = workspace
		task.delay(30, function() s:Destroy() end)
	end
	return s
end

ACTIONS.Sound = function(name)
	local s = findSound(name)
	if s then s:Play() end
end

-- Loops a sound until it's stopped, cutting it off wherever it happens to be.
local looping = {}

ACTIONS.SoundLoop = function(name)
	if looping[name] then return end
	local s = findSound(name)
	if not s then return end
	s.Looped = true
	s.TimePosition = 0
	s:Play()
	looping[name] = s
end

ACTIONS.SoundStop = function(name)
	local s = looping[name]
	if s then
		s:Stop()          -- stops immediately, even mid-way through
		s.Looped = false
		looping[name] = nil
	end
end

local function stopAllLoopingSounds()
	for name, s in pairs(looping) do
		s:Stop()
		s.Looped = false
		looping[name] = nil
	end
end

-- Plays a sound over and over, every `seconds`. Pass 0 to stop it.
local soundLoops = {}

ACTIONS.SoundEvery = function(name, seconds)
	local existing = soundLoops[name]
	if existing then existing.stop = true end
	soundLoops[name] = nil
	if not seconds or seconds <= 0 then return end

	local running = { stop = false }
	soundLoops[name] = running
	task.spawn(function()
		while not running.stop do
			local s = findSound(name)
			if s then s:Play() else break end
			task.wait(seconds)
		end
	end)
end

local function stopAllSoundLoops()
	for name, running in pairs(soundLoops) do
		running.stop = true
		soundLoops[name] = nil
	end
end

ACTIONS.SoundWait = function(name)
	local s = findSound(name)
	if not s then task.wait(1.5) return end
	if not s.IsLoaded then
		local loaded = false
		task.delay(3, function() loaded = true end)
		s.Loaded:Once(function() loaded = true end)
		while not loaded do task.wait() end
	end
	s:Play()
	local length = s.TimeLength / math.max(s.PlaybackSpeed, 0.01)
	task.wait(length > 0 and length or 1.5)
end

ACTIONS.FadeOut = function(seconds)
	remote:FireAllClients("FadeOut", seconds or 0.8)
	task.wait((seconds or 0.8) + 0.1)
end

ACTIONS.FadeIn = function(seconds)
	remote:FireAllClients("FadeIn", seconds or 0.8)
	task.wait(seconds or 0.8)
end

ACTIONS.MoveTo = function(objName, spotName)
	local obj = findThing(objName)
	local spot = findThing(spotName)
	if not obj then warn("NightLoop: nothing named " .. objName) return end
	if not spot then warn("NightLoop: no spot named " .. spotName) return end
	obj:PivotTo(spot:GetPivot())
end

local originalMeshTextures = {}

ACTIONS.SetDirty = function(objName, dirty)
	local obj = findThing(objName)
	if not obj then warn("NightLoop: nothing named " .. objName) return end

	for _, part in ipairs(obj:GetDescendants()) do
		-- only parts named exactly "Plate"; anything else is skipped
		if part:IsA("BasePart") and part.Name == PLATE_NAME then
			if part:IsA("MeshPart") then
				-- mesh plates: swap the mesh's own texture
				if originalMeshTextures[part] == nil then
					originalMeshTextures[part] = part.TextureID
				end
				part.TextureID = dirty and DIRTY_TEXTURE or originalMeshTextures[part]
			else
				-- normal parts: put the dirt on every face, or remove it
				for _, d in ipairs(part:GetChildren()) do
					if d.Name == "DirtTexture" then d:Destroy() end
				end
				if dirty then
					for _, face in ipairs(Enum.NormalId:GetEnumItems()) do
						local decal = Instance.new("Decal")
						decal.Name = "DirtTexture"
						decal.Texture = DIRTY_TEXTURE
						decal.Transparency = DIRT_TRANSPARENCY
						decal.Face = face
						decal.Parent = part
					end
				end
			end
		end
	end
end

local originalTransparency = {}
local originalCollide = {}

-- Shows/hides an object. Hidden = fully transparent and can't be bumped into.
-- Anything in NEVER_HIDE stays visible no matter what is asked for.
local function setObjectVisible(obj, visible, fadeTime)
	if NEVER_HIDE[obj.Name] then visible = true end
	local things = obj:GetDescendants()
	table.insert(things, obj)
	for _, d in ipairs(things) do
		if (d:IsA("BasePart") or d:IsA("Decal")) and d.Name ~= "DirtTexture" then
			if originalTransparency[d] == nil then
				originalTransparency[d] = d.Transparency
			end
			local target = visible and originalTransparency[d] or 1
			if fadeTime and fadeTime > 0 then
				TweenService:Create(d, TweenInfo.new(fadeTime), { Transparency = target }):Play()
			else
				d.Transparency = target
			end
		end
		if d:IsA("BasePart") then
			if originalCollide[d] == nil then
				originalCollide[d] = d.CanCollide
			end
			d.CanCollide = visible and originalCollide[d] or false
		end
	end
	if fadeTime and fadeTime > 0 then task.wait(fadeTime) end
end

local warnedMissing = {}

ACTIONS.SetVisible = function(name, visible, fadeTime)
	local obj = findThing(name)
	if not obj then
		if not warnedMissing[name] then
			warnedMissing[name] = true
			warn("NightLoop: nothing named " .. name .. " (fine if you don't want one)")
		end
		return
	end
	setObjectVisible(obj, visible, fadeTime)
end

-- Reveal/Conceal: force an object fully visible or fully invisible.
-- Unlike SetVisible, these ignore how the object was built, so a model you left
-- at Transparency 1 in Studio still shows up properly.
local function forceTransparency(name, value, fadeTime, onlyPartsNamed)
	local obj = findThing(name)
	if not obj then
		if not warnedMissing[name] then
			warnedMissing[name] = true
			warn("NightLoop: nothing named " .. name .. " (fine if you don't want one)")
		end
		return
	end

	local things = obj:GetDescendants()
	table.insert(things, obj)
	local touched = 0
	for _, d in ipairs(things) do
		local wanted = true
		if onlyPartsNamed then
			-- only parts with this name (or things inside them)
			wanted = d.Name == onlyPartsNamed
				or (d.Parent and d.Parent.Name == onlyPartsNamed)
		end
		if wanted and (d:IsA("BasePart") or d:IsA("Decal")) then
			touched = touched + 1
			if fadeTime and fadeTime > 0 then
				TweenService:Create(d, TweenInfo.new(fadeTime), { Transparency = value }):Play()
			else
				d.Transparency = value
			end
		end
		if wanted and d:IsA("BasePart") then
			if originalCollide[d] == nil then
				originalCollide[d] = d.CanCollide
			end
			d.CanCollide = (value < 1) and originalCollide[d] or false
		end
	end
	if touched == 0 then
		warn(("NightLoop: found %s but nothing named %s inside it")
			:format(obj:GetFullName(), tostring(onlyPartsNamed)))
	end
	if fadeTime and fadeTime > 0 then task.wait(fadeTime) end
end

ACTIONS.Reveal = function(name, fadeTime)
	forceTransparency(name, 0, fadeTime)
end

ACTIONS.Conceal = function(name, fadeTime)
	forceTransparency(name, 1, fadeTime)
end

-- Same thing, but only the parts inside with a given name
-- e.g. {"RevealParts", "Table", "Plate", 0.4}
ACTIONS.RevealParts = function(name, partName, fadeTime)
	forceTransparency(name, 0, fadeTime, partName)
end

ACTIONS.ConcealParts = function(name, partName, fadeTime)
	forceTransparency(name, 1, fadeTime, partName)
end

-- Hides every part of an object except one named part (and whatever is inside it)
local function hideExcept(obj, keepName)
	local keep = obj:FindFirstChild(keepName, true)
	for _, d in ipairs(obj:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then
			local insideKeep = keep and (d == keep or d:IsDescendantOf(keep))
			if not insideKeep then
				if originalTransparency[d] == nil then
					originalTransparency[d] = d.Transparency
				end
				d.Transparency = 1
				if d:IsA("BasePart") then
					if originalCollide[d] == nil then
						originalCollide[d] = d.CanCollide
					end
					d.CanCollide = false
				end
			end
		end
	end
	if not keep then
		warn(("NightLoop: %s has no part called %s, so the prompt may not work"):format(obj.Name, keepName))
	end
end

ACTIONS.Flicker = function(seconds)
	local old = flickerChance
	flickerChance = 0.3
	task.wait(seconds or 1)
	flickerChance = old
end

ACTIONS.OpenDoor = function(name) swingDoor(name, true) end
ACTIONS.CloseDoor = function(name) swingDoor(name, false) end

-- The zone can be a single part or a model made of several parts
local function getZoneParts(zoneName)
	local zone = findThing(zoneName)
	if not zone then return {} end
	-- if we landed on a part inside a model with the same name, use the whole model
	if zone:IsA("BasePart") and zone.Parent:IsA("Model") and zone.Parent.Name == zoneName then
		zone = zone.Parent
	end
	if zone:IsA("BasePart") then return { zone } end
	local parts = {}
	for _, d in ipairs(zone:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	return parts
end

local function anyoneInside(zoneParts)
	for _, plr in ipairs(Players:GetPlayers()) do
		local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			for _, zone in ipairs(zoneParts) do
				local half = zone.Size / 2
				local rel = zone.CFrame:PointToObjectSpace(hrp.Position)
				if math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y + 3 and math.abs(rel.Z) <= half.Z then
					return true
				end
			end
		end
	end
	return false
end

ACTIONS.EnterHouse = function(doorName, zoneName)
	local door = findThing(doorName)
	local isOpen = door and doorStates[door] and math.abs(doorStates[door].angle) > 0.01
	local zoneParts = getZoneParts(zoneName)

	if #zoneParts == 0 then
		if not isOpen then swingDoor(doorName, true) end
		warn("NightLoop: no " .. zoneName .. " found, leaving the door open so you aren't locked out")
		return
	end

	-- open the door, but stop mid-swing if someone slips inside early
	if not isOpen then
		swingDoor(doorName, true, function()
			return anyoneInside(zoneParts)
		end)
	end

	-- wait (as long as it takes) until someone is inside any of the zone parts
	while not anyoneInside(zoneParts) do
		task.wait(0.15)
	end
	task.wait(0.4) -- brief pause so it doesn't slam instantly
	swingDoor(doorName, false)
end

ACTIONS.TeleportTo = function(spotName)
	local spot = findThing(spotName)
	if not spot then warn("NightLoop: no spot named " .. spotName) return end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then
			plr.Character:PivotTo(spot:GetPivot())
		end
	end
end

ACTIONS.Cinematic = function(on)
	-- the camera script, the TV overlay and the sticky note all watch this
	workspace:SetAttribute("CinematicMode", on and true or false)
	remote:FireAllClients("Cinematic", on and true or false)
end

ACTIONS.SoundsOff = function(seconds)
	remote:FireAllClients("SoundsOff", seconds or 1)
end

ACTIONS.SoundsOn = function(seconds)
	remote:FireAllClients("SoundsOn", seconds or 1)
end

ACTIONS.Zoom = function(fov, seconds)
	remote:FireAllClients("Zoom", fov or 70, seconds or 2)
end

ACTIONS.LieDown = function(spotName)
	if not spotName then
		remote:FireAllClients("LieDown", nil)
		return
	end
	-- send the position too, in case the client hasn't loaded the part yet
	local spot = findThing(spotName)
	if not spot then
		warn("NightLoop: LieDown can't find a part named " .. spotName .. " - the camera won't lie down")
	end
	local cf = spot and (spot:IsA("BasePart") and spot.CFrame or spot:GetPivot())
	remote:FireAllClients("LieDown", spotName, cf)
end

-- thick black fog closing in around the player
local fogTween
ACTIONS.BlackFog = function(seeDistance, seconds)
	if fogTween then fogTween:Cancel() end
	local distance = seeDistance or 15
	if distance <= 0 then
		-- clear it: put the atmosphere back
		Lighting.FogColor = Color3.new(0, 0, 0)
		fogTween = TweenService:Create(Lighting, TweenInfo.new(seconds or 2), {
			FogStart = 0, FogEnd = 100000,
		})
		fogTween:Play()
		atmo.Parent = Lighting
		return
	end
	-- an Atmosphere overrides fog, so it has to step aside
	atmo.Parent = nil
	Lighting.FogColor = Color3.new(0, 0, 0)
	if Lighting.FogEnd > 5000 then Lighting.FogEnd = 300 end
	fogTween = TweenService:Create(Lighting, TweenInfo.new(seconds or 4), {
		FogStart = 0, FogEnd = distance,
	})
	fogTween:Play()
end

-- flickering black bars over whatever sits at a spot (the food)
local censors = {}
ACTIONS.Censor = function(spotName, on)
	if not on then
		local running = censors[spotName]
		if running then
			running.stop = true
			for _, part in ipairs(running.parts) do part:Destroy() end
			censors[spotName] = nil
		end
		return
	end
	if censors[spotName] then return end

	local spot = findThing(spotName)
	if not (spot and spot:IsA("BasePart")) then
		warn("NightLoop: no part named " .. spotName)
		return
	end

	local running = { parts = {}, stop = false }
	censors[spotName] = running
	for _ = 1, 6 do
		local bar = Instance.new("Part")
		bar.Anchored = true
		bar.CanCollide = false
		bar.CanQuery = false
		bar.CastShadow = false
		bar.Material = Enum.Material.SmoothPlastic
		bar.Color = Color3.new(0, 0, 0)
		bar.Size = Vector3.new(spot.Size.X, 0.12, spot.Size.Z)
		bar.CFrame = spot.CFrame
		bar.Parent = workspace
		table.insert(running.parts, bar)
	end

	task.spawn(function()
		while not running.stop do
			for _, bar in ipairs(running.parts) do
				-- jitter each bar so the food is never actually visible
				bar.Size = Vector3.new(
					spot.Size.X * (0.5 + math.random() * 0.6),
					0.08 + math.random() * 0.14,
					spot.Size.Z * (0.5 + math.random() * 0.6)
				)
				bar.CFrame = spot.CFrame
					* CFrame.new(
						(math.random() - 0.5) * spot.Size.X * 0.5,
						(math.random() - 0.5) * spot.Size.Y,
						(math.random() - 0.5) * spot.Size.Z * 0.5)
					* CFrame.Angles(0, math.random() * math.pi, 0)
			end
			task.wait(0.05)
		end
	end)
end

ACTIONS.Show = function(name, spotName)
	local obj = ServerStorage:FindFirstChild(name, true)
	if not obj then warn("NightLoop: nothing named " .. name .. " in ServerStorage") return end
	shown[name] = { obj = obj, home = obj.Parent }
	local spot = spotName and findThing(spotName)
	if spot then obj:PivotTo(spot:GetPivot()) end
	obj.Parent = workspace
end

ACTIONS.Hide = function(name)
	local info = shown[name]
	if info then
		info.obj.Parent = info.home
		shown[name] = nil
	end
end

ACTIONS.Dialogue = function(lines)
	if not lines or #lines == 0 then return end
	dialogueFinished = false
	dialogueAlive = os.clock()
	dialogueRemote:FireAllClients(lines)

	-- Wait for the player to click through. There's no time limit while the
	-- dialogue box is still open (the client keeps checking in); the loop only
	-- gives up if it hears nothing at all for a minute.
	while not dialogueFinished do
		task.wait(0.2)
		if os.clock() - dialogueAlive > 60 then
			warn("NightLoop: gave up waiting for dialogue")
			break
		end
	end
end

-- Little interactions: "scrub" (rub it clean) or "timing" (stop the marker in the zone)
ACTIONS.MiniGame = function(kind, config)
	miniFinished = false
	miniAlive = os.clock()
	miniRemote:FireAllClients(kind or "scrub", config or {})

	-- no time limit while the player is still playing it
	while not miniFinished do
		task.wait(0.2)
		if os.clock() - miniAlive > 60 then
			warn("NightLoop: gave up waiting for the minigame")
			break
		end
	end
end

local function runActions(list)
	for _, action in ipairs(list) do
		dprint("action:", action[1], action[2] ~= nil and tostring(action[2]) or "")
		local fn = ACTIONS[action[1]]
		if fn then fn(action[2], action[3], action[4]) else warn("NightLoop: unknown action " .. tostring(action[1])) end
	end
end

-- runs a list of actions in the background, so the story keeps moving
ACTIONS.Async = function(list)
	task.spawn(runActions, list)
end

---------------------------------------------------------------------
-- Tasks & bed
---------------------------------------------------------------------
local function getPromptPart(obj)
	if obj:IsA("BasePart") then return obj end
	-- use a prompt you already placed, or a part called "interactpart"
	local existing = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
	if existing and existing.Parent:IsA("BasePart") then return existing.Parent end
	local interact = obj:FindFirstChild("interactpart", true)
	if interact and interact:IsA("BasePart") then return interact end
	if obj:IsA("Model") then return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true) end
end

local function makePrompt(part, actionText, holdTime)
	local prompt = part:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = ""
	prompt.HoldDuration = holdTime
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = part
	return prompt
end

local nightIndex = 1
local stepIndex = 0
local completedCount = 0
local groupDone = {}       -- which parts of a group step are done
local groupDoneCount = 0
local busy = false
local bedReady = false
local sleeping = false
local started = false
local ended = false
local cutscenePlaying = false

local function getState()
	local steps = NIGHTS[nightIndex]
	local list = {}
	for i = 1, math.min(stepIndex, #steps) do
		local step = steps[i]
		local name = step.text
		if step.tasks then
			local count = (i < stepIndex or i <= completedCount) and #step.tasks or groupDoneCount
			name = ("%s (%d/%d)"):format(step.text, count, #step.tasks)
		end
		table.insert(list, { name = name, done = i <= completedCount })
	end
	local night = NIGHTS[nightIndex]
	return {
		night = nightIndex,
		title = (night and night.name) or ("Night " .. nightIndex),
		nights = #NIGHTS,
		stepsTotal = #steps,
		stepsDone = completedCount,
		intensity = #NIGHTS > 1 and (nightIndex - 1) / (#NIGHTS - 1) or 0,
		tasks = list,
		bedReady = bedReady,
	}
end

-- what the wake-up screen says for a night
local function nightTitle(n)
	local night = NIGHTS[n]
	if night and night.name then return night.name end
	return "Night " .. n
end

local function broadcast()
	remote:FireAllClients("State", getState())
end

local taskPrompts = {}
local bedPrompt

-- Waits END_SCREEN.delay seconds, then ends the game with the end screen
ACTIONS.EndGame = function()
	local delay = END_SCREEN.delay or 15
	dprint(("EndGame: end screen in %s seconds"):format(tostring(delay)))
	task.wait(delay)
	ended = true
	bedReady = false
	if bedPrompt then bedPrompt.Enabled = false end
	for _, p in pairs(taskPrompts) do p.Enabled = false end
	dprint("EndGame: sending EndScreen to " .. #Players:GetPlayers() .. " player(s)")
	remote:FireAllClients("EndScreen", END_SCREEN)
end

local function advance()
	if ended then return end
	local steps = NIGHTS[nightIndex]
	stepIndex += 1
	if stepIndex > #steps then
		stepIndex = #steps
		bedReady = true
		bedPrompt.Enabled = true
		broadcast()
		return
	end

	local step = steps[stepIndex]
	broadcast()
	if step.onStart then
		busy = true
		runActions(step.onStart)
		busy = false
	end

	groupDone = {}
	groupDoneCount = 0
	local names = step.tasks or { step.task }
	for _, taskName in ipairs(names) do
		local prompt = taskPrompts[taskName]
		if prompt then
			prompt.ActionText = step.tasks and (step.eachText or step.text) or step.text
			prompt.Enabled = true
		else
			warn("NightLoop: no task object named " .. taskName .. " in workspace.Tasks")
		end
	end
end

local function withTaskName(actions, taskName)
	local out = {}
	for i, a in ipairs(actions) do
		local copy = table.clone(a)
		for k, v in pairs(copy) do
			if v == "$task" then copy[k] = taskName end
		end
		out[i] = copy
	end
	return out
end

local function finishStep(step)
	completedCount = stepIndex
	broadcast()
	if step.onComplete then
		busy = true
		runActions(step.onComplete)
		busy = false
	end
	advance()
end

-- Intro dialogue first, then the first task
local function beginNight()
	local intro = NIGHTS[nightIndex].intro
	if intro then
		busy = true
		ACTIONS.Dialogue(intro)
		busy = false
	end
	advance()
end

for _, obj in ipairs(tasksFolder:GetChildren()) do
	local part = getPromptPart(obj)
	if part then
		local name = obj.Name
		local prompt = makePrompt(part, name, obj:GetAttribute("HoldTime") or 1.5)
		taskPrompts[name] = prompt

		prompt.Triggered:Connect(function()
			local step = NIGHTS[nightIndex][stepIndex]
			if busy or sleeping or bedReady or not step or completedCount >= stepIndex then
				return
			end

			if step.tasks then
				-- group step: this must be one of its parts and not done yet
				if not table.find(step.tasks, name) or groupDone[name] then return end
				prompt.Enabled = false
				groupDone[name] = true
				groupDoneCount += 1
				local wasLast = groupDoneCount >= #step.tasks
				broadcast()
				if step.onEach then
					busy = true   -- no starting another one mid-minigame
					runActions(withTaskName(step.onEach, name))
					busy = false
				end
				if wasLast then finishStep(step) end
			else
				if step.task ~= name then return end
				prompt.Enabled = false
				finishStep(step)
			end
		end)
	end
end

bedPrompt = makePrompt(getPromptPart(bed), "Sleep", 2)

-- Work out the first night each task object is used
local firstNightFor = {}
for n, steps in ipairs(NIGHTS) do
	for _, step in ipairs(steps) do
		for _, taskName in ipairs(step.tasks or { step.task }) do
			if not firstNightFor[taskName] then
				firstNightFor[taskName] = n
			end
		end
	end
end

-- Hide task objects whose night hasn't come yet, show (and reset) the rest
local function updateTaskVisibility(n)
	for _, obj in ipairs(tasksFolder:GetChildren()) do
		local keepPart = INVISIBLE_TASKS[obj.Name]
		if NEVER_HIDE[obj.Name] then
			setObjectVisible(obj, true)          -- furniture: always there
		elseif keepPart then
			hideExcept(obj, keepPart)            -- invisible volume, prompt still works
		elseif not obj:GetAttribute("AlwaysVisible") then
			local first = firstNightFor[obj.Name] or math.huge
			setObjectVisible(obj, n >= first)
		end
	end
end

local function startNight(n)
	nightIndex = n
	stepIndex = 0
	completedCount = 0
	bedReady = false
	bedPrompt.Enabled = false
	for _, p in pairs(taskPrompts) do p.Enabled = false end
	for name in pairs(shown) do ACTIONS.Hide(name) end
	runActions(NIGHT_START)
	-- back to normal: TV overlay on, no fog, normal camera
	ACTIONS.Cinematic(false)
	ACTIONS.Zoom(70, 0.5)
	ACTIONS.LieDown(nil)
	ACTIONS.BlackFog(0, 0.5)
	ACTIONS.SoundsOn(1)
	stopAllSoundLoops()
	stopAllLoopingSounds()
	updateTaskVisibility(n)
	applyPreset(presetFor(n))
end

bedPrompt.Triggered:Connect(function()
	dprint("bed prompt pressed (bedReady=" .. tostring(bedReady) .. ", sleeping=" .. tostring(sleeping) .. ")")
	if ended or not bedReady or sleeping then return end
	sleeping = true
	bedPrompt.Enabled = false
	remote:FireAllClients("Sleep")
	task.wait(SLEEP_TIME)

	if nightIndex >= #NIGHTS then
		-- last night: go to the ending the same way the hospital scene does
		ACTIONS.EndGame()
		return
	end

	startNight(nightIndex + 1)
	if wakePoint then
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.Character then
				plr.Character:PivotTo(wakePoint.CFrame + Vector3.new(0, 3, 0))
			end
		end
	end
	broadcast()
	remote:FireAllClients("Wake", nightIndex, nightTitle(nightIndex))
	sleeping = false
	task.delay(WAKE_DELAY, beginNight)
end)

---------------------------------------------------------------------
-- Starting the game
-- Every time someone joins this place, it starts from the beginning:
-- the flying intro, then the first night. (Or wherever START_NIGHT /
-- START_AT_HOSPITAL say, while testing.)
---------------------------------------------------------------------
local function playIntroCutscene()
	-- Look the parts up HERE on the server and send their positions.
	-- The client may not have them at all if StreamingEnabled is on,
	-- because FlyStart is far away from the player.
	local fromPart = INTRO_CUTSCENE.enabled and findThing(INTRO_CUTSCENE.from)
	local toPart = INTRO_CUTSCENE.enabled and findThing(INTRO_CUTSCENE.to)
	if INTRO_CUTSCENE.enabled and not (fromPart and toPart) then
		warn(("NightLoop: cutscene needs parts named %s and %s in Workspace")
			:format(INTRO_CUTSCENE.from, INTRO_CUTSCENE.to))
	end
	if not (INTRO_CUTSCENE.enabled and fromPart and toPart) then return end

	-- hide the sticky note and TV overlay for the flight
	cutscenePlaying = true
	ACTIONS.Cinematic(true)
	-- lift the black screen, fly in, then start the night properly
	remote:FireAllClients("FadeIn", 1.2)
	remote:FireAllClients("Cutscene", {
		fromCF = fromPart:IsA("BasePart") and fromPart.CFrame or fromPart:GetPivot(),
		toCF = toPart:IsA("BasePart") and toPart.CFrame or toPart:GetPivot(),
		duration = INTRO_CUTSCENE.duration,
		lines = INTRO_CUTSCENE.lines,
	})

	local textTime = 0
	for _, line in ipairs(INTRO_CUTSCENE.lines) do
		textTime += 1.4 + #line * 0.035
	end
	task.wait(math.max(INTRO_CUTSCENE.duration, textTime) + 0.5)

	if INTRO_CUTSCENE.landing then
		ACTIONS.TeleportTo(INTRO_CUTSCENE.landing)
	end
	ACTIONS.Cinematic(false)   -- note and TV overlay come back
	cutscenePlaying = false
end

-- choice = a night number, or "hospital"
local function beginGame(choice)
	started = true
	dprint("starting the game at: " .. tostring(choice))

	-- the hospital: no cutscene, no title card, no dialogue
	if choice == "hospital" then
		startNight(#NIGHTS)
		cutscenePlaying = true      -- anyone else joining just gets "Hold"
		remote:FireAllClients("Hold")
		task.spawn(function()
			dprint(("hospital: waiting %s seconds for the player to load"):format(tostring(HOSPITAL_LOAD_DELAY)))
			task.wait(HOSPITAL_LOAD_DELAY)
			busy = true
			runActions(HOSPITAL_SCENE)
			busy = false
			cutscenePlaying = false
		end)
		return
	end

	local n = math.clamp(tonumber(choice) or 1, 1, #NIGHTS)
	startNight(n)
	broadcast()

	task.spawn(function()
		if n == 1 then
			playIntroCutscene()
		else
			-- a later night (testing): no flying intro, straight to the title card
			dprint("starting on night " .. n .. ", skipping the intro cutscene")
			if INTRO_CUTSCENE.landing then
				ACTIONS.TeleportTo(INTRO_CUTSCENE.landing)
			end
		end
		remote:FireAllClients("Wake", nightIndex, nightTitle(nightIndex))
		task.delay(WAKE_DELAY, beginNight)
	end)
end

remote.OnServerEvent:Connect(function(player, action)
	if action ~= "Ready" then return end
	print("[NightLoop] SERVER D. " .. player.Name .. " is ready")

	if ended then
		-- true = show it finished, no animation (for people joining late)
		remote:FireClient(player, "EndScreen", END_SCREEN, true)
		return
	end
	remote:FireClient(player, "State", getState())

	if cutscenePlaying then
		-- The client keeps saying "ready" every couple of seconds until it
		-- hears back. Answer with "Hold" so it stops asking WITHOUT showing
		-- the "Night 1" screen in the middle of the cutscene.
		remote:FireClient(player, "Hold")
		return
	end

	if started then
		-- someone joining later just wakes up normally
		remote:FireClient(player, "Wake", nightIndex, nightTitle(nightIndex))
		return
	end

	-- first player in: start from the beginning
	if START_AT_HOSPITAL then
		beginGame("hospital")
	else
		beginGame(math.clamp(START_NIGHT, 1, #NIGHTS))
	end
end)

---------------------------------------------------------------------
-- Setup check: lists anything missing so you know why a scene fails
---------------------------------------------------------------------
local function checkSetup()
	local parts = { "FrontDoor", "EntryZone", "Sink", "DishStack", "Broom", "Dirt1", "Dirt2", "Dirt3",
		"Table", "TableSeat", "PlateSpot", "BedLieSpot", "VisitorSpot" }
	if INTRO_CUTSCENE.enabled then
		table.insert(parts, INTRO_CUTSCENE.from)
		table.insert(parts, INTRO_CUTSCENE.to)
	end
	for _, name in ipairs(parts) do
		if not findThing(name) then
			warn("NightLoop SETUP: missing '" .. name .. "' in Workspace")
		end
	end
	for _, name in ipairs({ "DishSound", "SweepSound", "KnockSound", "hospital beep" }) do
		local s = findThing(name) or ServerStorage:FindFirstChild(name, true)
		if not (s and s:IsA("Sound")) then
			warn("NightLoop SETUP: missing Sound '" .. name .. "' (workspace or ServerStorage)")
		end
	end
	if not ServerStorage:FindFirstChild("Jeff", true) then
		warn("NightLoop SETUP: missing model 'Jeff' in ServerStorage")
	end
	dprint("setup check done (anything missing is listed above in orange)")
end
checkSetup()

local firstNight = START_AT_HOSPITAL and #NIGHTS or math.clamp(START_NIGHT, 1, #NIGHTS)
startNight(firstNight)
print(("[NightLoop] SERVER C. night %d set up, waiting for players"):format(firstNight))