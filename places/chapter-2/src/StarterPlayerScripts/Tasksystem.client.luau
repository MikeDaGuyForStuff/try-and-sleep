-- TaskSystem (LocalScript)
-- Put this in StarterPlayer > StarterPlayerScripts
--
-- Runs the nights (see NIGHTS below). Each night:
--   1. (Night 2+) the intro cutscene replays and the night's monologue plays
--   2. Tasks are written onto the sticky note one at a time. Using the task's
--      object crosses it out, then its dialogue plays (with an optional
--      "After X hours" time skip before it)
--   3. Customers come in one after another: their walk-in MegMo cutscene
--      plays, they stay where it ends, their dialogue plays (with the scanning
--      minigame if it has an items action), then their walk-out cutscene plays
--   4. The player says their lines, then "Leave for the day" is written on.
--      Walking into the leave area stops them and fades to black; the next
--      night's title shows and the next night starts. After the last night,
--      the ending text stays on the black screen.
--
-- Needs the Dialogue and Atmosphere scripts in StarterPlayerScripts, and the
-- CutsceneCurves ModuleScript in ReplicatedStorage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

---------------------------------------------------------------------
-- SETTINGS
---------------------------------------------------------------------
-- The game is a list of NIGHTS, played in order. Each night:
--   title          = text on the black screen when the night starts (not used
--                    for the first night, which starts with the game)
--   playIntro      = true to replay the intro cutscene (INTRO_CUTSCENE) first.
--                    Night 1's intro and monologue are played by StartMegMoCutscene.
--   introDialogue  = lines after the intro
--   tasks          = tasks to do before the customers come in
--   customers      = customers who come in after the tasks, one after another:
--                      walkIn / walkOut = MegMo cutscenes in ReplicatedStorage.MegMoCutscenes
--                      dialogue = what's said while they're at the register
--   afterCustomers = lines after the last customer has left
-- Then LEAVE_TASK starts: walking into its area ends the night.
--
-- Each task:
--   name       = what gets written on the sticky note
--   target     = name of the Part or Model in Workspace to interact with
--   prompt     = text on the "E" prompt
--   object     = small label above the prompt text (optional)
--   holdTime   = seconds to hold E (0 = just press it)
--   dialogue   = lines played after the task is done
--   timeSkip   = text shown on a black screen before the dialogue, e.g.
--                "After 4 hours" (leave it out for no black screen)
--   barriersOn = names of Parts/Models/Folders in Workspace that become solid
--                (CanCollide on) the moment the object is used. They go back
--                to not solid when the next night starts.
--   area       = name of a Part (or Model of Parts) the player must be standing
--                inside for the prompt to work (optional)
--   enterArea  = instead of a prompt, the task is done by walking into this
--                Part (or Model of Parts)
--   pickRandomIn = pick one of the models named `target` inside this model at
--                  random (copies nested inside a target are skipped)
--   minigame   = "restock": the target's stock starts hidden; using the prompt
--                starts a minigame where the player fills each empty spot
--
-- Dialogue lines:
--   plain text       = the player's thoughts (silent)
--   {"Name", "Text"} = someone speaking (gets voice blips; "You" stays silent)
--   { action = "items", items = { ... } } = put these items (models in
--     ReplicatedStorage) on the counter and start the scanning minigame.
--     Every line after it autoscrolls while the player scans.

-- Closing the register is the same task every night, apart from what's said
-- afterwards, so this makes one.
local function closeRegisterTask(dialogue)
	return {
		name = "Close the register",
		target = "CashRegister",
		prompt = "Close register",
		object = "Cash Register",
		holdTime = 0.5,
		dialogue = dialogue,
		timeSkip = "After 4 hours",
		barriersOn = { "BarriersCash" }, -- the folder of barrier parts
		area = "CashRegisterArea",
	}
end

local NIGHTS = {
	---------------------------------------------------------------- Night 1
	{
		tasks = {
			closeRegisterTask({
				"It's closing time.",
				"Finally. Drawer's counted, receipts are printed...",
				"Just gotta lock up and I can go home.",
			}),
		},
		customers = {
			{
				walkIn = "walkintoofstoretoregister",
				walkOut = "walkoutofstorefromregister",
				dialogue = {
					{ "Tim", "Hey... you're still open, right?" },
					{ "You", "...It's way past closing." },
					{ "Tim", "Please. I just need one thing. It won't take long." },
					{ action = "items", items = { "Milk" } },
					{ "Tim", "Just the milk. That's all." },
					{ "Tim", "...Sorry for coming in so late." },
					{ "You", "It's fine. Happens." },
				},
			},
		},
		afterCustomers = {
			"...Weird guy. Who needs milk that badly at this hour?",
			"Whatever. Shift's over. Time to go home.",
		},
	},

	---------------------------------------------------------------- Night 2
	{
		title = "Night 2",
		playIntro = true,
		introDialogue = {
			"Back for another night shift.",
			"Same store. Same silence.",
		},
		tasks = {
			{
				name = "Restock the shelf",
				target = "grocery store shelf",
				pickRandomIn = "Grocery Store",
				prompt = "Restock",
				object = "Shelf",
				holdTime = 0.5,
				minigame = "restock",
				dialogue = { "There. Looks almost full again." },
			},
			closeRegisterTask({
				"Closing time. Again.",
				"Let's hope nobody shows up this time.",
			}),
		},
		customers = {
			{
				walkIn = "walkintoofstoretoregister",
				walkOut = "walkoutofstorefromregister",
				dialogue = {
					{ "Tim", "...Hey." },
					{ "You", "You again?" },
					{ "Tim", "Same as last night. A little more this time." },
					{ action = "items", items = { "Milk", "Milk" } },
					{ "Tim", "You work here every night?" },
					{ "You", "...Pretty much." },
					{ "Tim", "Must get lonely." },
				},
			},
		},
		afterCustomers = {
			"He's... kind of creepy.",
			"I should get out of here.",
		},
	},

	-- Add more nights the same way.
}

-- The last task of every night: walk into the leave area to end the night
local LEAVE_TASK = { name = "Leave for the day", enterArea = "LeaveArea" }

local INTRO_CUTSCENE = "cutscene1"     -- MegMo cutscene replayed by nights with playIntro
local SHIFT_START = "ShiftStart"       -- Part on the floor where the player starts a
-- night that has no intro (optional)
local ENDING_TEXT = "To be continued..." -- stays on the black screen after the last night
local EYE_HEIGHT = 1.5                 -- after the intro, the player is put under the camera

local NOTE_TITLE = "Tonight:"
local WRITE_SPEED = 0.06      -- seconds per letter when writing a task on the note
local CROSS_OUT_SPEED = 0.025 -- seconds per letter when crossing a task out
local PAUSE_BEFORE_WRITING = 0.6

-- Time skip black screen
local BLACK_FADE_TIME = 1.5      -- seconds to fade into and out of black
local TEXT_FADE_TIME = 1         -- seconds for the text to fade in / out
local TEXT_HOLD_TIME = 2         -- seconds the text stays fully visible

-- Restock minigame
local RESTOCK_GHOST = 0.8             -- how see-through the empty spots are (1 = invisible)
local RESTOCK_MAX_SLOTS = 10          -- more stock pieces than this are grouped by shelf level
local RESTOCK_SOUND = "StockPlace"    -- optional Sound in ReplicatedStorage
local FOCUS_MARGIN = 8                -- degrees of look room around the shelf

-- Customers
local CUSTOMER_ENABLED = true
local CUSTOMER_DELAY = 2              -- seconds before each customer walks in

-- Scanning minigame
local ITEM_SPOT = "CounterItemSpot"   -- Part on the counter where items appear
local AUTOSCROLL_SECONDS = 2.5        -- pause after each autoscrolling line
local SCAN_DISTANCE = 15              -- how far away items can be scanned from
local SCAN_SOUND = "ScanBeep"         -- optional Sound in ReplicatedStorage
-- The minigame camera: at the player's eyes, centred on the register. They can
-- look around the register freely and over to the items; looking further away
-- than that is resisted and the view eases back.
local REGISTER_LOOK_YAW = 20          -- degrees of free look left/right of the register
local REGISTER_LOOK_PITCH = 15        -- degrees of free look up/down from the register
local ITEM_LOOK_MARGIN = 10           -- extra degrees allowed past the items on the counter
local LOOK_PULLBACK = 6               -- how quickly the view eases back past the limits
local LOOK_SMOOTHING = 14             -- camera smoothing (higher = snappier)
local SCAN_MOUSE_SENSITIVITY = 0.15   -- degrees per pixel of mouse movement
local SCAN_FOV = 60                   -- narrower than normal (70) for tension
local SCAN_BREATHING = true           -- faint up/down breathing sway

-- Where the player is moved to when scanning starts (Part on the floor behind
-- the counter). They're turned to face the items.
local CASHIER_STAND = "CashierStand"

-- The register side of the minigame: scan an item, then click the register to
-- ring it up. Sometimes the scanner errors and the item has to be scanned again.
local REGISTER_NAME = "CashRegister"
local ITEM_PRICES = { Milk = 3.49 }   -- items not listed get a random price
local SCAN_ERROR_CHANCE = 0.3         -- chance a scan fails (0 = never)
local FIRST_SCAN_ERRORS = true        -- the very first scan always fails
local ERROR_SOUND = "ScanError"       -- optional Sound in ReplicatedStorage
local RING_UP_SOUND = "RegisterDing"  -- optional Sound in ReplicatedStorage


local HIGHLIGHT_TARGET = true        -- outline the object for the current task
local WAIT_FOR_INTRO_DIALOGUE = true -- start after the monologue following the cutscene
local INTRO_TIMEOUT = 90             -- start anyway after this many seconds
local PROMPT_DISTANCE = 8            -- how close the player must be to use it
---------------------------------------------------------------------

local localDialogue = ReplicatedStorage:WaitForChild("LocalDialogue")

---------------------------------------------------------------------
-- Sticky note
---------------------------------------------------------------------
local noteLines = {} -- rich text for each task line already on the note

local function escape(text)
	text = text:gsub("&", "&amp;")
	text = text:gsub("<", "&lt;")
	text = text:gsub(">", "&gt;")
	return text
end

local function setNote(extraLine)
	local lines = { NOTE_TITLE }
	for _, line in ipairs(noteLines) do
		table.insert(lines, line)
	end
	if extraLine then
		table.insert(lines, extraLine)
	end
	player:SetAttribute("StickyNoteText", table.concat(lines, "\n"))
end

-- Writes a new task onto the note, letter by letter
local function writeLine(text)
	local full = "- " .. text
	for i = 1, #full do
		setNote(escape(full:sub(1, i)))
		task.wait(WRITE_SPEED)
	end
	table.insert(noteLines, escape(full))
	setNote()
	return #noteLines
end

-- Crosses a task out, left to right
local function crossOutLine(index, text)
	local full = "- " .. text
	for i = 1, #full do
		noteLines[index] = "<s>" .. escape(full:sub(1, i)) .. "</s>" .. escape(full:sub(i + 1))
		setNote()
		task.wait(CROSS_OUT_SPEED)
	end
end

-- Empty note (title only) right away, so it's blank during the cutscene
setNote()

---------------------------------------------------------------------
-- Dialogue
---------------------------------------------------------------------
local function inDialogue()
	return player:GetAttribute("InDialogue") == true
end

-- Plays lines and waits until the player has clicked through all of them
local function playDialogue(lines, options)
	if type(lines) ~= "table" or #lines == 0 then
		return
	end
	while inDialogue() do
		task.wait(0.1)
	end
	localDialogue:Fire(lines, options)
	local startDeadline = os.clock() + 2
	while not inDialogue() and os.clock() < startDeadline do
		task.wait()
	end
	while inDialogue() do
		task.wait(0.1)
	end
end

---------------------------------------------------------------------
-- Time skip black screen
---------------------------------------------------------------------
local function playTween(instance, seconds, goal)
	local tween = TweenService:Create(instance, TweenInfo.new(seconds, Enum.EasingStyle.Sine), goal)
	tween:Play()
	tween.Completed:Wait()
end

-- Holds the player in place (or lets them go)
local function setPlayerHeld(held)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = held
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

-- A black screen that covers everything (VHS effect, sticky note, dialogue)
local function newBlackScreen()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BlackScreen"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 200

	local black = Instance.new("Frame")
	black.Size = UDim2.fromScale(1, 1)
	black.BackgroundColor3 = Color3.new(0, 0, 0)
	black.BackgroundTransparency = 1
	black.BorderSizePixel = 0
	black.Parent = gui

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.8, 0.2)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.SpecialElite
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(230, 225, 215)
	label.TextTransparency = 1
	label.Parent = black
	local sizeLimit = Instance.new("UITextSizeConstraint")
	sizeLimit.MaxTextSize = 48
	sizeLimit.Parent = label

	gui.Parent = player:WaitForChild("PlayerGui")

	local screen = {}
	local fadingOut = false
	function screen.fadeIn()
		playTween(black, BLACK_FADE_TIME, { BackgroundTransparency = 0 })
	end
	function screen.showText(text)
		label.Text = text
		playTween(label, TEXT_FADE_TIME, { TextTransparency = 0 })
	end
	function screen.hideText()
		playTween(label, TEXT_FADE_TIME, { TextTransparency = 1 })
	end
	-- fade text in, hold it, fade it out
	function screen.flashText(text)
		screen.showText(text)
		task.wait(TEXT_HOLD_TIME)
		screen.hideText()
	end
	function screen.fadeOut()
		if fadingOut then
			return
		end
		fadingOut = true
		playTween(black, BLACK_FADE_TIME, { BackgroundTransparency = 1 })
		gui:Destroy()
	end
	return screen
end

-- Fade to black, "After X hours" fades in and out, then the black fades away
local function timeSkip(text)
	local screen = newBlackScreen()
	setPlayerHeld(true)
	screen.fadeIn()
	screen.flashText(text)
	screen.fadeOut()
	setPlayerHeld(false)
end

---------------------------------------------------------------------
-- Tasks
---------------------------------------------------------------------
local function findTarget(name)
	local deadline = os.clock() + 15
	repeat
		local found = workspace:FindFirstChild(name, true)
		if found then
			return found
		end
		task.wait(0.25)
	until os.clock() > deadline
	return nil
end

local function promptPart(target)
	if target:IsA("BasePart") then
		return target
	end
	if target:IsA("Model") and target.PrimaryPart then
		return target.PrimaryPart
	end
	return target:FindFirstChildWhichIsA("BasePart", true)
end

-- True if the player is standing inside the area Part (or any Part of an area Model)
local function isInArea(area)
	if not area then
		return true
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local parts = {}
	if area:IsA("BasePart") then
		parts = { area }
	else
		for _, part in area:GetDescendants() do
			if part:IsA("BasePart") then
				table.insert(parts, part)
			end
		end
	end
	for _, part in ipairs(parts) do
		local offset = part.CFrame:PointToObjectSpace(root.Position)
		local half = part.Size / 2
		if math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z then
			return true
		end
	end
	return false
end

-- Picks one of the models named targetName inside the container at random.
-- Models nested inside a model with the same name are skipped (those are the
-- shelf's own parts, not shelves).
local function pickRandomTarget(containerName, targetName)
	local container = findTarget(containerName)
	if not container then
		warn(('[Tasks] Can\'t find "%s" in Workspace to pick a "%s" from'):format(containerName, targetName))
		return nil
	end
	local candidates = {}
	for _, obj in container:GetDescendants() do
		if obj.Name == targetName and obj:IsA("Model") and obj.Parent.Name ~= targetName then
			table.insert(candidates, obj)
		end
	end
	if #candidates == 0 then
		warn(('[Tasks] No "%s" found inside "%s"'):format(targetName, containerName))
		return nil
	end
	return candidates[math.random(#candidates)]
end

local function setStockTransparency(parts, value)
	for _, part in ipairs(parts) do
		part.Transparency = value
		for _, child in part:GetChildren() do
			if child:IsA("Decal") or child:IsA("Texture") then
				child.Transparency = value
			end
		end
	end
end

-- The shelf's stock, in clickable groups ("slots"). Everything inside the shelf
-- except the copy of the shelf nested in it.
local function getStockSlots(shelf)
	local slots = {}
	local allParts = {}
	for _, child in shelf:GetChildren() do
		if child.Name ~= shelf.Name then
			local parts = {}
			if child:IsA("BasePart") then
				table.insert(parts, child)
			end
			for _, obj in child:GetDescendants() do
				if obj:IsA("BasePart") then
					table.insert(parts, obj)
				end
			end
			if #parts > 0 then
				table.insert(slots, { parts = parts })
				for _, part in ipairs(parts) do
					table.insert(allParts, part)
				end
			end
		end
	end

	-- lots of loose pieces: group them by shelf level instead
	if #slots > RESTOCK_MAX_SLOTS then
		table.sort(allParts, function(a, b)
			return a.Position.Y < b.Position.Y
		end)
		slots = {}
		local current, lastY = nil, nil
		for _, part in ipairs(allParts) do
			if not current or part.Position.Y - lastY > 0.75 then
				current = { parts = {} }
				table.insert(slots, current)
			end
			table.insert(current.parts, part)
			lastY = part.Position.Y
		end
	end
	return slots
end

local function hideStock(shelf)
	for _, slot in ipairs(getStockSlots(shelf)) do
		setStockTransparency(slot.parts, 1)
	end
end

-- Waits for the player to use the task's object. Returns false if it's missing.
local function waitForInteraction(taskInfo)
	-- "walk into this area" tasks (like Leave for the day)
	if taskInfo.enterArea then
		local area = findTarget(taskInfo.enterArea)
		if not area then
			warn(('[Tasks] Can\'t find an area named "%s" in Workspace; skipping "%s"'):format(
				tostring(taskInfo.enterArea), tostring(taskInfo.name)))
			return false
		end
		while not (isInArea(area) and not inDialogue()) do
			task.wait(0.1)
		end
		setPlayerHeld(true) -- stop them the moment they step in
		return true
	end

	local target
	if taskInfo.pickRandomIn then
		target = pickRandomTarget(taskInfo.pickRandomIn, taskInfo.target)
	else
		target = findTarget(taskInfo.target)
	end
	if target and taskInfo.minigame == "restock" then
		hideStock(target) -- empty shelf until it's restocked
	end
	local part = target and promptPart(target)
	if not part then
		warn(('[Tasks] Can\'t find a Part or Model named "%s" in Workspace; skipping "%s"'):format(
			tostring(taskInfo.target), tostring(taskInfo.name)))
		return false
	end

	local highlight = nil
	if HIGHLIGHT_TARGET then
		highlight = Instance.new("Highlight")
		highlight.Adornee = target
		highlight.FillTransparency = 1
		highlight.OutlineColor = Color3.new(1, 1, 1)
		highlight.OutlineTransparency = 0.3
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = target
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = taskInfo.prompt or "Interact"
	prompt.ObjectText = taskInfo.object or ""
	prompt.HoldDuration = taskInfo.holdTime or 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	-- randomly picked models: put the prompt in the middle of the model
	local promptAttachment = nil
	if taskInfo.pickRandomIn and target:IsA("Model") then
		promptAttachment = Instance.new("Attachment")
		promptAttachment.Parent = part
		promptAttachment.WorldPosition = target:GetBoundingBox().Position
		prompt.Parent = promptAttachment
	else
		prompt.Parent = part
	end

	-- the area the player has to stand in (if the task has one)
	local area = nil
	if taskInfo.area then
		area = workspace:FindFirstChild(taskInfo.area, true)
		if not area then
			warn(('[Tasks] Can\'t find an area named "%s" in Workspace; the prompt will work from anywhere'):format(
				tostring(taskInfo.area)))
		end
	end

	-- only usable inside the area, and not while dialogue is on screen
	local triggered = false
	local triggerConnection = prompt.Triggered:Connect(function()
		triggered = true
	end)
	while not triggered do
		prompt.Enabled = not inDialogue() and isInArea(area)
		task.wait(0.1)
	end

	triggerConnection:Disconnect()
	prompt:Destroy()
	if promptAttachment then
		promptAttachment:Destroy()
	end
	if highlight then
		highlight:Destroy()
	end
	return target
end

---------------------------------------------------------------------
-- Customer
---------------------------------------------------------------------
-- Roblox's default idle animations
local DEFAULT_IDLE = {
	[Enum.HumanoidRigType.R6] = "rbxassetid://180435571",
	[Enum.HumanoidRigType.R15] = "rbxassetid://507766666",
}

local function loadAnimation(humanoid, animationId)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	return ok and track or nil
end

local function flatLookAt(position, target)
	local direction = (target - position) * Vector3.new(1, 0, 1)
	if direction.Magnitude < 0.01 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, position + direction.Unit)
end

-- Stands a character's feet on the floor where a marker Part sits
local function standPosition(humanoid, root, marker)
	local standHeight = humanoid.RigType == Enum.HumanoidRigType.R6 and 3
		or (humanoid.HipHeight + root.Size.Y / 2)
	local floorY = marker.Position.Y - marker.Size.Y / 2
	return Vector3.new(marker.Position.X, floorY + standHeight, marker.Position.Z)
end

-- Makes the named Parts (or every part inside the named Models/Folders) solid
local solidBarriers = {}
local function turnOnBarriers(names)
	for _, name in ipairs(names or {}) do
		local barrier = workspace:FindFirstChild(name, true)
		if not barrier then
			warn(('[Tasks] Can\'t find a barrier named "%s" in Workspace'):format(name))
		else
			local parts = barrier:IsA("BasePart") and { barrier } or barrier:GetDescendants()
			for _, part in parts do
				if part:IsA("BasePart") and not part.CanCollide then
					part.CanCollide = true
					table.insert(solidBarriers, part)
				end
			end
		end
	end
end

-- Puts barriers back to not solid (at the start of a new night)
local function resetBarriers()
	for _, part in ipairs(solidBarriers) do
		if part.Parent then
			part.CanCollide = false
		end
	end
	table.clear(solidBarriers)
end

---------------------------------------------------------------------
-- Scanning minigame
---------------------------------------------------------------------
local function newScreenGui(name, displayOrder)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = displayOrder
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

local function itemParts(item)
	local parts = {}
	for _, part in item:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	return parts
end

-- Puts copies of the named models on the counter, spread along the spot Part
local function placeItems(names)
	local spot = findTarget(ITEM_SPOT)
	if not spot then
		warn(('[Tasks] Can\'t find a Part named "%s" in Workspace to put items on'):format(ITEM_SPOT))
		return {}
	end
	local items = {}
	for index, name in ipairs(names) do
		local template = ReplicatedStorage:FindFirstChild(name, true)
		if not template then
			warn(('[Tasks] Can\'t find an item named "%s" in ReplicatedStorage'):format(tostring(name)))
		else
			local item = template:Clone()
			if item:IsA("BasePart") then
				local holder = Instance.new("Model")
				holder.Name = item.Name
				item.Parent = holder
				holder.PrimaryPart = item
				item = holder
			end
			for _, obj in item:GetDescendants() do
				if obj:IsA("BaseScript") then
					obj:Destroy()
				elseif obj:IsA("BasePart") then
					obj.Anchored = true
					obj.CanCollide = false
					obj.CanQuery = true
				end
			end
			item.Name = "ScanItem_" .. tostring(name)

			-- spread several items across the spot, sitting on top of it
			local boxCFrame, size = item:GetBoundingBox()
			local spread = 0
			if #names > 1 then
				spread = ((index - 1) / (#names - 1) - 0.5) * math.max(spot.Size.X - size.X, 0)
			end
			local restPosition = spot.Position
				+ spot.CFrame.UpVector * (spot.Size.Y / 2)
				+ spot.CFrame.RightVector * spread
				+ Vector3.new(0, size.Y / 2, 0)
			local restPivot = item:GetPivot() + (restPosition - boxCFrame.Position)

			-- drop in from just above
			item:PivotTo(restPivot + Vector3.new(0, 1.5, 0))
			item.Parent = workspace
			local drop = Instance.new("CFrameValue")
			drop.Value = item:GetPivot()
			drop.Changed:Connect(function(value)
				if item.Parent then
					item:PivotTo(value)
				end
			end)
			local tween = TweenService:Create(drop, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = restPivot })
			tween:Play()
			tween.Completed:Connect(function()
				drop:Destroy()
			end)
			table.insert(items, item)
		end
	end
	return items
end

local function playSound(name)
	local template = ReplicatedStorage:FindFirstChild(name, true)
	if template and template:IsA("Sound") then
		local sound = template:Clone()
		sound.Parent = SoundService
		sound:Play()
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
	end
end

local function formatMoney(amount)
	return ("$%.2f"):format(amount)
end

-- Focused first person at the counter: scan each item, then ring it up on the
-- register. Some scans fail and have to be done again.
local function runScanMinigame(itemNames)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	-- move the player behind the counter, facing the register
	local stand = workspace:FindFirstChild(CASHIER_STAND, true)
	local spot = workspace:FindFirstChild(ITEM_SPOT, true)
	local register = workspace:FindFirstChild(REGISTER_NAME, true)
	local registerPart = register and promptPart(register)
	local registerPosition = register and (register:IsA("Model") and register:GetPivot().Position or registerPart.Position)
	if stand and root and humanoid then
		local standAt = standPosition(humanoid, root, stand)
		local faceAt = registerPosition or (spot and spot.Position) or (standAt + stand.CFrame.LookVector)
		character:PivotTo(flatLookAt(standAt, faceAt))
		root.AssemblyLinearVelocity = Vector3.zero
	elseif not stand then
		warn(('[Tasks] No Part named "%s" in Workspace; the player won\'t be moved for the minigame'):format(CASHIER_STAND))
	end

	local items = placeItems(itemNames)
	local total = #items
	if total == 0 then
		return
	end

	-- player held in place, their own body hidden (the camera is inside it)
	local wasAnchored = root and root.Anchored
	if root then
		root.Anchored = true
	end
	local hiddenParts = {}
	if character then
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				hiddenParts[part] = part.LocalTransparencyModifier
				part.LocalTransparencyModifier = 1
			end
		end
	end

	-- focused first-person camera: at the eyes, centred on the register
	local camera = workspace.CurrentCamera
	local previousFov = camera.FieldOfView
	local startCFrame = camera.CFrame
	local eye = head and (head.Position + Vector3.new(0, 0.2, 0)) or camera.CFrame.Position
	local lookTarget = registerPosition
		or (spot and spot.Position)
		or (eye + (root and root.CFrame.LookVector or Vector3.new(0, 0, -1)))
	local baseRotation = CFrame.lookAt(eye, lookTarget).Rotation

	-- angles (relative to looking at the register) of a point in the world
	local function anglesTo(point)
		local v = baseRotation:VectorToObjectSpace(point - eye)
		local flat = math.sqrt(v.X * v.X + v.Z * v.Z)
		return math.deg(math.atan2(-v.X, -v.Z)), math.deg(math.atan2(v.Y, flat))
	end

	-- free-look range: around the register, stretched to include both ends of the item spot
	local yawMin, yawMax = -REGISTER_LOOK_YAW, REGISTER_LOOK_YAW
	local pitchMin, pitchMax = -REGISTER_LOOK_PITCH, REGISTER_LOOK_PITCH
	if spot and registerPosition then
		local halfWidth = spot.CFrame.RightVector * (spot.Size.X / 2)
		for _, point in ipairs({ spot.Position - halfWidth, spot.Position, spot.Position + halfWidth }) do
			local itemYaw, itemPitch = anglesTo(point)
			yawMin = math.min(yawMin, itemYaw - ITEM_LOOK_MARGIN)
			yawMax = math.max(yawMax, itemYaw + ITEM_LOOK_MARGIN)
			pitchMin = math.min(pitchMin, itemPitch - ITEM_LOOK_MARGIN)
			pitchMax = math.max(pitchMax, itemPitch + ITEM_LOOK_MARGIN)
		end
	end

	-- past the limits, mouse movement is dampened and the view eases back
	local function applyLook(value, change, low, high, dt)
		if (value > high and change > 0) or (value < low and change < 0) then
			change *= 0.25
		end
		value += change
		local pull = 1 - math.exp(-LOOK_PULLBACK * dt)
		if value > high then
			value -= (value - high) * pull
		elseif value < low then
			value -= (value - low) * pull
		end
		return math.clamp(value, low - 15, high + 15)
	end

	local yaw, pitch = 0, 0           -- where the player is trying to look
	local shownYaw, shownPitch = 0, 0 -- smoothed, what the camera shows
	local blendIn = 0
	local clock = 0
	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseIconEnabled = false

	local touchDelta = Vector2.zero
	RunService:BindToRenderStep("ScanMinigameCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		local delta = UserInputService:GetMouseDelta() + touchDelta
		touchDelta = Vector2.zero
		yaw = applyLook(yaw, -delta.X * SCAN_MOUSE_SENSITIVITY, yawMin, yawMax, dt)
		pitch = applyLook(pitch, -delta.Y * SCAN_MOUSE_SENSITIVITY, pitchMin, pitchMax, dt)

		local smooth = 1 - math.exp(-LOOK_SMOOTHING * dt)
		shownYaw += (yaw - shownYaw) * smooth
		shownPitch += (pitch - shownPitch) * smooth

		clock += dt
		local sway = SCAN_BREATHING and Vector3.new(0, math.sin(clock * 1.6) * 0.03, 0) or Vector3.zero
		local target = CFrame.new(eye + sway) * baseRotation * CFrame.fromEulerAnglesYXZ(math.rad(shownPitch), math.rad(shownYaw), 0)

		-- ease smoothly into the view at the start
		blendIn = math.min(blendIn + dt / 0.6, 1)
		local alpha = TweenService:GetValue(blendIn, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		camera.CFrame = startCFrame:Lerp(target, alpha)
		camera.FieldOfView = previousFov + (SCAN_FOV - previousFov) * alpha
	end)

	-- touch screens: drag to look around
	local touchLookConnection = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			touchDelta += Vector2.new(input.Delta.X, input.Delta.Y)
		end
	end)

	-- UI: crosshair + counter + hint
	local gui = newScreenGui("ScanMinigame", 30)
	local crosshair = Instance.new("Frame")
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	crosshair.Size = UDim2.fromOffset(6, 6)
	crosshair.BackgroundColor3 = Color3.new(1, 1, 1)
	crosshair.BackgroundTransparency = 0.2
	crosshair.BorderSizePixel = 0
	crosshair.Parent = gui
	Instance.new("UICorner", crosshair).CornerRadius = UDim.new(1, 0)

	local counter = Instance.new("TextLabel")
	counter.AnchorPoint = Vector2.new(0.5, 0)
	counter.Position = UDim2.new(0.5, 0, 0.15, 0)
	counter.Size = UDim2.fromOffset(500, 40)
	counter.BackgroundTransparency = 1
	counter.Font = Enum.Font.SpecialElite
	counter.TextSize = 28
	counter.TextColor3 = Color3.fromRGB(230, 225, 215)
	counter.TextStrokeTransparency = 0.5
	counter.Parent = gui

	local hint = counter:Clone()
	hint.Position = UDim2.new(0.5, 0, 0.15, 36)
	hint.TextSize = 20
	hint.TextTransparency = 0.3
	hint.Parent = gui

	-- the register and its display (a little screen floating above it)
	local display = Instance.new("BillboardGui")
	display.Name = "RegisterDisplay"
	display.Size = UDim2.fromOffset(220, 56)
	display.StudsOffset = Vector3.new(0, 1.6, 0)
	display.LightInfluence = 0
	display.Adornee = registerPart
	display.Enabled = registerPart ~= nil
	display.Parent = gui
	local screen = Instance.new("TextLabel")
	screen.Size = UDim2.fromScale(1, 1)
	screen.BackgroundColor3 = Color3.fromRGB(10, 18, 10)
	screen.BackgroundTransparency = 0.1
	screen.BorderSizePixel = 0
	screen.Font = Enum.Font.Arcade
	screen.TextScaled = true
	screen.TextColor3 = Color3.fromRGB(120, 255, 140)
	screen.Parent = display
	Instance.new("UICorner", screen).CornerRadius = UDim.new(0, 6)
	local screenPadding = Instance.new("UIPadding", screen)
	screenPadding.PaddingLeft, screenPadding.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)

	local registerGlow = Instance.new("Highlight")
	registerGlow.Adornee = register
	registerGlow.FillColor = Color3.fromRGB(120, 255, 140)
	registerGlow.OutlineColor = Color3.fromRGB(120, 255, 140)
	registerGlow.DepthMode = Enum.HighlightDepthMode.Occluded
	registerGlow.Enabled = false
	registerGlow.Parent = gui

	local hover = Instance.new("Highlight")
	hover.FillColor = Color3.new(1, 1, 1)
	hover.FillTransparency = 0.8
	hover.OutlineColor = Color3.new(1, 1, 1)
	hover.DepthMode = Enum.HighlightDepthMode.Occluded
	hover.Enabled = false
	hover.Parent = gui

	-- game state
	local state = "scan"          -- "scan" an item, or "ringUp" on the register
	local busy = false            -- short pause while an effect plays
	local rungUp = 0
	local runningTotal = 0
	local pendingPrice = 0
	local scansDone = 0

	local function showScreen(text, color)
		screen.Text = text
		screen.TextColor3 = color or Color3.fromRGB(120, 255, 140)
	end

	local function updateUI()
		counter.Text = ("Scan the items (%d/%d)"):format(rungUp, total)
		if state == "scan" then
			hint.Text = "Click an item to scan it"
		else
			hint.Text = "Click the register to ring it up"
		end
	end
	showScreen("TOTAL " .. formatMoney(0))
	updateUI()

	local function priceOf(item)
		local name = item.Name:gsub("^ScanItem_", "")
		return ITEM_PRICES[name] or (math.random(199, 999) / 100)
	end

	local function flashItem(item, color)
		local flash = Instance.new("Highlight")
		flash.FillColor = color
		flash.FillTransparency = 0.4
		flash.OutlineColor = color
		flash.Adornee = item
		flash.Parent = item
		task.delay(0.35, function()
			flash:Destroy()
		end)
	end

	local function joltItem(item)
		local rest = item:GetPivot()
		for i = 1, 4 do
			if not item.Parent then
				return
			end
			local offset = Vector3.new((i % 2 == 0 and 1 or -1) * 0.08, 0, 0)
			item:PivotTo(rest + offset)
			task.wait(0.04)
		end
		if item.Parent then
			item:PivotTo(rest)
		end
	end

	local function removeItem(item)
		local lift = Instance.new("CFrameValue")
		lift.Value = item:GetPivot()
		lift.Changed:Connect(function(value)
			if item.Parent then
				item:PivotTo(value)
			end
		end)
		local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(lift, info, { Value = lift.Value + Vector3.new(0, 1.2, 0) }):Play()
		for _, part in ipairs(itemParts(item)) do
			TweenService:Create(part, info, { Transparency = 1 }):Play()
		end
		task.delay(0.5, function()
			lift:Destroy()
			item:Destroy()
		end)
	end

	-- register blinks while it's waiting to be clicked
	local blinkConnection = RunService.Heartbeat:Connect(function()
		if state == "ringUp" and not busy then
			local wave = (math.sin(os.clock() * 8) + 1) / 2
			registerGlow.Enabled = true
			registerGlow.FillTransparency = 0.5 + wave * 0.4
			registerGlow.OutlineTransparency = wave * 0.6
		else
			registerGlow.Enabled = false
		end
	end)

	local function scanItem(item)
		busy = true
		scansDone += 1
		local failed = (FIRST_SCAN_ERRORS and scansDone == 1) or math.random() < SCAN_ERROR_CHANCE
		if failed then
			playSound(ERROR_SOUND)
			flashItem(item, Color3.fromRGB(255, 70, 70))
			showScreen("ERROR - RESCAN", Color3.fromRGB(255, 80, 80))
			hint.Text = "Scan error! Try again"
			joltItem(item)
			task.wait(0.8)
			showScreen("TOTAL " .. formatMoney(runningTotal))
			updateUI()
		else
			playSound(SCAN_SOUND)
			flashItem(item, Color3.fromRGB(90, 255, 120))
			local index = table.find(items, item)
			if index then
				table.remove(items, index)
			end
			pendingPrice = priceOf(item)
			local name = item.Name:gsub("^ScanItem_", "")
			showScreen(string.upper(name) .. " " .. formatMoney(pendingPrice))
			removeItem(item)
			state = "ringUp"
			updateUI()
		end
		busy = false
	end

	local function ringUp()
		busy = true
		playSound(RING_UP_SOUND)
		runningTotal += pendingPrice
		rungUp += 1
		showScreen("TOTAL " .. formatMoney(runningTotal))
		if register then
			flashItem(register, Color3.fromRGB(120, 255, 140))
		end
		state = "scan"
		updateUI()
		busy = false
	end

	-- what the player is aiming at: an item (scan) or the register (ring up)
	local function targetAt(ray)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		local filter = table.clone(items)
		if register then
			table.insert(filter, register)
		end
		params.FilterDescendantsInstances = filter
		local result = workspace:Raycast(ray.Origin, ray.Direction * SCAN_DISTANCE, params)
		if not result then
			return nil
		end
		if register and result.Instance:IsDescendantOf(register) or result.Instance == register then
			return register
		end
		for _, item in ipairs(items) do
			if result.Instance:IsDescendantOf(item) then
				return item
			end
		end
		return nil
	end

	local function centerRay()
		local center = camera.ViewportSize / 2
		return camera:ViewportPointToRay(center.X, center.Y)
	end

	local function isValidTarget(target)
		if not target or busy then
			return false
		end
		if state == "scan" then
			return target ~= register
		end
		return target == register
	end

	local hoverConnection = RunService.RenderStepped:Connect(function()
		local target = targetAt(centerRay())
		local valid = isValidTarget(target) and target ~= register -- register has its own blink
		hover.Adornee = valid and target or nil
		hover.Enabled = valid
	end)

	local inputConnection = UserInputService.InputBegan:Connect(function(input)
		local ray = nil
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			ray = centerRay()
		elseif input.UserInputType == Enum.UserInputType.Touch then
			ray = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
		end
		if not ray then
			return
		end
		local target = targetAt(ray)
		if not isValidTarget(target) then
			return
		end
		if state == "scan" then
			task.spawn(scanItem, target)
		else
			task.spawn(ringUp)
		end
	end)

	-- if there's no register to click, ring items up automatically
	if not register then
		warn(('[Tasks] No "%s" found for the minigame; items will ring up automatically'):format(REGISTER_NAME))
	end

	while rungUp < total do
		if state == "ringUp" and not register and not busy then
			ringUp()
		end
		task.wait(0.1)
	end
	task.wait(0.8)

	blinkConnection:Disconnect()
	hoverConnection:Disconnect()
	inputConnection:Disconnect()
	touchLookConnection:Disconnect()
	gui:Destroy()

	-- give the camera, mouse and body back
	RunService:UnbindFromRenderStep("ScanMinigameCamera")
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	camera.FieldOfView = previousFov
	if humanoid then
		camera.CameraSubject = humanoid
	end
	camera.CameraType = Enum.CameraType.Custom
	for part, value in pairs(hiddenParts) do
		if part.Parent then
			part.LocalTransparencyModifier = value
		end
	end
	if root and root.Parent then
		root.Anchored = wasAnchored == true
	end
end

-- Plays a dialogue list, handling { action = "items", ... } entries:
-- lines before it play normally, lines after it autoscroll during the minigame.
local function runDialogueScript(lines)
	local before, action, after = {}, nil, {}
	for _, entry in ipairs(lines) do
		if type(entry) == "table" and entry.action ~= nil then
			if action then
				warn("[Tasks] Only one action per dialogue is supported; ignoring the extra one")
			else
				action = entry
			end
		elseif action then
			table.insert(after, entry)
		else
			table.insert(before, entry)
		end
	end

	playDialogue(before)
	if not action then
		return
	end

	if action.action == "items" then
		local minigameDone = false
		player:SetAttribute("DialogueClicksBlocked", true) -- clicks are for scanning now
		task.spawn(function()
			runScanMinigame(action.items or {})
			player:SetAttribute("DialogueClicksBlocked", false) -- finished early? clicks work again
			minigameDone = true
		end)
		playDialogue(after, { autoAdvance = action.autoScroll or AUTOSCROLL_SECONDS })
		while not minigameDone do
			task.wait(0.1)
		end
	else
		warn(('[Tasks] Unknown dialogue action "%s"'):format(tostring(action.action)))
		playDialogue(after)
	end
end

---------------------------------------------------------------------
-- Customer cutscenes (walk in / walk out)
---------------------------------------------------------------------
local hiddenRigs = {} -- rig name -> { rig = Model, parent = Instance }

local function getCutscene(name)
	local cutscenes = ReplicatedStorage:FindFirstChild("MegMoCutscenes")
	if not cutscenes then
		return nil, nil
	end
	local folder = cutscenes:FindFirstChild(name)
	if not folder then
		for _, child in cutscenes:GetChildren() do
			if string.lower(child.Name) == string.lower(name) then
				folder = child
			end
		end
	end
	if not folder then
		return nil, nil
	end
	return folder, require(folder:WaitForChild("CutsceneData"))
end

-- Takes the customer cutscenes' rigs out of the world (on this player's screen)
-- until their cutscene plays, so they're not standing around beforehand
local function hideCutsceneRigs(names)
	for _, name in ipairs(names) do
		local folder, data = getCutscene(name)
		if folder then
			for _, info in ipairs(data.RigAnimations or {}) do
				local rigName = tostring(info.RigName or "")
				if not hiddenRigs[rigName] then
					local rig = workspace:FindFirstChild(rigName, true)
					if rig and rig:IsA("Model") then
						hiddenRigs[rigName] = { rig = rig, parent = rig.Parent }
						rig.Parent = nil
					end
				end
			end
		end
	end
end

local function restoreCamera()
	local camera = workspace.CurrentCamera
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	camera.CameraType = Enum.CameraType.Custom
end

-- Plays a MegMo cutscene as exported (with its curves). endMode:
--   "stay"   = its characters stay where the cutscene leaves them
--   "remove" = its characters are taken out of the world afterwards
--   "leave"  = nothing special (MegMo puts them back where they started)
-- Returns true and where the camera was when the cutscene ended.
local function playMegMoCutscene(name, endMode)
	local folder, data = getCutscene(name)
	if not folder then
		warn(('[Tasks] Can\'t find the "%s" cutscene in ReplicatedStorage.MegMoCutscenes'):format(name))
		return false
	end
	local settingsFolder = folder:FindFirstChild("CutsceneSettings")
	local mode = settingsFolder and settingsFolder:FindFirstChild("RigTargetMode")
	if mode and mode.Value == "TriggeringPlayerClone" then
		warn(('[Tasks] "%s" has RigTargetMode set to TriggeringPlayerClone, so MegMo will use a copy of the player. Set it to WorkspaceRig.'):format(name))
	end
	local CutscenePlayer = require(folder:WaitForChild("MegMoCutscenePlayer"))
	local CutsceneCurves = require(ReplicatedStorage:WaitForChild("CutsceneCurves"))

	-- bring the cutscene's rigs into the world
	local rigs = {}
	for _, info in ipairs(data.RigAnimations or {}) do
		local rigName = tostring(info.RigName or "")
		local hidden = hiddenRigs[rigName]
		if hidden then
			hidden.rig.Parent = hidden.parent
		end
		local rig = (hidden and hidden.rig) or workspace:FindFirstChild(rigName, true)
		if rig and rig:IsA("Model") and not table.find(rigs, rig) then
			table.insert(rigs, rig)
		end
	end

	-- keep track of where each character's body is while the cutscene plays,
	-- because MegMo puts rigs back where they started when it finishes
	local lastTorso = {}
	local function torsoOf(rig)
		return rig:FindFirstChild("Torso") or rig:FindFirstChild("LowerTorso") or rig.PrimaryPart
	end
	local tracker = RunService.Heartbeat:Connect(function()
		if not CutscenePlayer._isPlaying then
			return
		end
		for _, rig in ipairs(rigs) do
			local torso = torsoOf(rig)
			if torso and rig.Parent then
				lastTorso[rig] = torso.CFrame
			end
		end
	end)

	local stopCurves = CutsceneCurves.apply(folder, data)
	CutscenePlayer.Play(data, { restoreCamera = false })
	stopCurves()
	tracker:Disconnect()

	for _, rig in ipairs(rigs) do
		local hidden = hiddenRigs[rig.Name]
		if endMode == "stay" then
			-- put them back where the cutscene ended, standing upright
			local torso = torsoOf(rig)
			local finalTorso = lastTorso[rig]
			if torso and finalTorso then
				local torsoInRig = rig:GetPivot():ToObjectSpace(torso.CFrame)
				local target = finalTorso * torsoInRig:Inverse()
				local look = target.LookVector * Vector3.new(1, 0, 1)
				if look.Magnitude < 0.01 then
					look = Vector3.new(0, 0, -1)
				end
				rig:PivotTo(CFrame.lookAt(target.Position, target.Position + look.Unit))
			end
			local root = rig:FindFirstChild("HumanoidRootPart") or rig.PrimaryPart
			if root then
				root.Anchored = true -- stay exactly in place
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
			local humanoid = rig:FindFirstChildOfClass("Humanoid")
			if humanoid then
				local idle = loadAnimation(humanoid, DEFAULT_IDLE[humanoid.RigType] or DEFAULT_IDLE[Enum.HumanoidRigType.R6])
				if idle then
					idle.Looped = true
					idle:Play(0.2)
				end
			end
		elseif endMode == "remove" then
			-- they've left: take them out of the world again
			if not hidden then
				hiddenRigs[rig.Name] = { rig = rig, parent = rig.Parent }
			end
			rig.Parent = nil
		end
	end

	local endCamera = workspace.CurrentCamera.CFrame
	restoreCamera()
	return true, endCamera
end

---------------------------------------------------------------------
-- Restock minigame
---------------------------------------------------------------------
-- Focused first-person camera at the player's eyes, looking at lookAt, with
-- soft limits that include the given points. Returns a function that ends it.
local function startFocusCamera(lookAt, includePoints)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and root then
		character:PivotTo(flatLookAt(root.Position, lookAt))
	end

	local camera = workspace.CurrentCamera
	local previousFov = camera.FieldOfView
	local startCFrame = camera.CFrame
	local eye = head and (head.Position + Vector3.new(0, 0.2, 0)) or camera.CFrame.Position
	local baseRotation = CFrame.lookAt(eye, lookAt).Rotation

	local yawMin, yawMax, pitchMin, pitchMax = -FOCUS_MARGIN, FOCUS_MARGIN, -FOCUS_MARGIN, FOCUS_MARGIN
	for _, point in ipairs(includePoints or {}) do
		local v = baseRotation:VectorToObjectSpace(point - eye)
		local flat = math.sqrt(v.X * v.X + v.Z * v.Z)
		local yaw = math.deg(math.atan2(-v.X, -v.Z))
		local pitch = math.deg(math.atan2(v.Y, flat))
		yawMin, yawMax = math.min(yawMin, yaw - FOCUS_MARGIN), math.max(yawMax, yaw + FOCUS_MARGIN)
		pitchMin, pitchMax = math.min(pitchMin, pitch - FOCUS_MARGIN), math.max(pitchMax, pitch + FOCUS_MARGIN)
	end
	yawMin, yawMax = math.max(yawMin, -80), math.min(yawMax, 80)
	pitchMin, pitchMax = math.max(pitchMin, -75), math.min(pitchMax, 75)

	local function applyLook(value, change, low, high, dt)
		if (value > high and change > 0) or (value < low and change < 0) then
			change *= 0.25
		end
		value += change
		local pull = 1 - math.exp(-LOOK_PULLBACK * dt)
		if value > high then
			value -= (value - high) * pull
		elseif value < low then
			value -= (value - low) * pull
		end
		return math.clamp(value, low - 15, high + 15)
	end

	local yaw, pitch, shownYaw, shownPitch = 0, 0, 0, 0
	local blendIn, clock = 0, 0
	local touchDelta = Vector2.zero
	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseIconEnabled = false

	RunService:BindToRenderStep("FocusCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		local delta = UserInputService:GetMouseDelta() + touchDelta
		touchDelta = Vector2.zero
		yaw = applyLook(yaw, -delta.X * SCAN_MOUSE_SENSITIVITY, yawMin, yawMax, dt)
		pitch = applyLook(pitch, -delta.Y * SCAN_MOUSE_SENSITIVITY, pitchMin, pitchMax, dt)

		local smooth = 1 - math.exp(-LOOK_SMOOTHING * dt)
		shownYaw += (yaw - shownYaw) * smooth
		shownPitch += (pitch - shownPitch) * smooth

		clock += dt
		local sway = SCAN_BREATHING and Vector3.new(0, math.sin(clock * 1.6) * 0.03, 0) or Vector3.zero
		local target = CFrame.new(eye + sway) * baseRotation * CFrame.fromEulerAnglesYXZ(math.rad(shownPitch), math.rad(shownYaw), 0)
		blendIn = math.min(blendIn + dt / 0.6, 1)
		local alpha = TweenService:GetValue(blendIn, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		camera.CFrame = startCFrame:Lerp(target, alpha)
		camera.FieldOfView = previousFov + (SCAN_FOV - previousFov) * alpha
	end)

	local touchConnection = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			touchDelta += Vector2.new(input.Delta.X, input.Delta.Y)
		end
	end)

	return function()
		RunService:UnbindFromRenderStep("FocusCamera")
		touchConnection:Disconnect()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		camera.FieldOfView = previousFov
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
		camera.CameraType = Enum.CameraType.Custom
	end
end

-- Click each see-through empty spot on the shelf to fill it
local function runRestockMinigame(shelf)
	local slots = getStockSlots(shelf)
	if #slots == 0 then
		warn(('[Tasks] "%s" has no stock parts to restock'):format(shelf:GetFullName()))
		return
	end
	local total = #slots

	-- hold the player still and hide their body (the camera is inside it)
	setPlayerHeld(true)
	local character = player.Character
	local hiddenBody = {}
	if character then
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				hiddenBody[part] = part.LocalTransparencyModifier
				part.LocalTransparencyModifier = 1
			end
		end
	end

	-- empty spots show as see-through ghosts that can be clicked
	local savedQuery = {}
	local remaining = {}
	local slotOfPart = {}
	local allParts = {}
	for _, slot in ipairs(slots) do
		setStockTransparency(slot.parts, RESTOCK_GHOST)
		for _, part in ipairs(slot.parts) do
			savedQuery[part] = part.CanQuery
			part.CanQuery = true
			slotOfPart[part] = slot
			table.insert(allParts, part)
		end
		table.insert(remaining, slot)
	end

	local boxCFrame, boxSize = shelf:GetBoundingBox()
	local corners = {}
	for _, x in ipairs({ -0.5, 0.5 }) do
		for _, y in ipairs({ -0.5, 0.5 }) do
			for _, z in ipairs({ -0.5, 0.5 }) do
				table.insert(corners, boxCFrame:PointToWorldSpace(boxSize * Vector3.new(x, y, z)))
			end
		end
	end
	local stopCamera = startFocusCamera(boxCFrame.Position, corners)
	local camera = workspace.CurrentCamera

	-- UI: crosshair + counter + hint
	local gui = newScreenGui("RestockMinigame", 30)
	local crosshair = Instance.new("Frame")
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	crosshair.Size = UDim2.fromOffset(6, 6)
	crosshair.BackgroundColor3 = Color3.new(1, 1, 1)
	crosshair.BackgroundTransparency = 0.2
	crosshair.BorderSizePixel = 0
	crosshair.Parent = gui
	Instance.new("UICorner", crosshair).CornerRadius = UDim.new(1, 0)

	local counter = Instance.new("TextLabel")
	counter.AnchorPoint = Vector2.new(0.5, 0)
	counter.Position = UDim2.new(0.5, 0, 0.15, 0)
	counter.Size = UDim2.fromOffset(500, 40)
	counter.BackgroundTransparency = 1
	counter.Font = Enum.Font.SpecialElite
	counter.TextSize = 28
	counter.TextColor3 = Color3.fromRGB(230, 225, 215)
	counter.TextStrokeTransparency = 0.5
	counter.Parent = gui
	local hint = counter:Clone()
	hint.Position = UDim2.new(0.5, 0, 0.15, 36)
	hint.TextSize = 20
	hint.TextTransparency = 0.3
	hint.Text = "Click the empty spots to fill them"
	hint.Parent = gui

	local filled = 0
	local function updateCounter()
		counter.Text = ("Restock the shelf (%d/%d)"):format(filled, total)
	end
	updateCounter()

	local function slotAt(ray)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		local filter = {}
		for _, slot in ipairs(remaining) do
			for _, part in ipairs(slot.parts) do
				table.insert(filter, part)
			end
		end
		params.FilterDescendantsInstances = filter
		local result = workspace:Raycast(ray.Origin, ray.Direction * 25, params)
		return result and slotOfPart[result.Instance] or nil
	end

	local function centerRay()
		local center = camera.ViewportSize / 2
		return camera:ViewportPointToRay(center.X, center.Y)
	end

	-- hovering a spot makes it a little more visible
	local hovered = nil
	local hoverConnection = RunService.RenderStepped:Connect(function()
		local slot = slotAt(centerRay())
		if slot ~= hovered then
			if hovered and table.find(remaining, hovered) then
				setStockTransparency(hovered.parts, RESTOCK_GHOST)
			end
			if slot then
				setStockTransparency(slot.parts, math.max(RESTOCK_GHOST - 0.3, 0))
			end
			hovered = slot
		end
	end)

	local function fill(slot)
		local index = table.find(remaining, slot)
		if not index then
			return
		end
		table.remove(remaining, index)
		if hovered == slot then
			hovered = nil
		end
		filled += 1
		updateCounter()
		playSound(RESTOCK_SOUND)
		for _, part in ipairs(slot.parts) do
			TweenService:Create(part, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Transparency = 0 }):Play()
		end
		task.delay(0.25, function()
			setStockTransparency(slot.parts, 0)
		end)
	end

	local inputConnection = UserInputService.InputBegan:Connect(function(input)
		local ray = nil
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			ray = centerRay()
		elseif input.UserInputType == Enum.UserInputType.Touch then
			ray = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
		end
		local slot = ray and slotAt(ray)
		if slot then
			fill(slot)
		end
	end)

	while #remaining > 0 do
		task.wait(0.1)
	end
	task.wait(0.6)

	hoverConnection:Disconnect()
	inputConnection:Disconnect()
	gui:Destroy()
	stopCamera()
	for part, value in pairs(savedQuery) do
		if part.Parent then
			part.CanQuery = value
		end
	end
	for part, value in pairs(hiddenBody) do
		if part.Parent then
			part.LocalTransparencyModifier = value
		end
	end
	setPlayerHeld(false)
end

---------------------------------------------------------------------
-- Nights
---------------------------------------------------------------------
local function allCustomerCutscenes()
	local names = {}
	for _, night in ipairs(NIGHTS) do
		for _, customer in ipairs(night.customers or {}) do
			for _, name in ipairs({ customer.walkIn, customer.walkOut }) do
				if name and not table.find(names, name) then
					table.insert(names, name)
				end
			end
		end
	end
	return names
end

local function runTasks(tasks)
	for _, taskInfo in ipairs(tasks or {}) do
		task.wait(PAUSE_BEFORE_WRITING)
		local lineIndex = writeLine(taskInfo.name)

		local target = waitForInteraction(taskInfo)
		if taskInfo.minigame == "restock" and typeof(target) == "Instance" then
			runRestockMinigame(target)
		end
		turnOnBarriers(taskInfo.barriersOn)
		crossOutLine(lineIndex, taskInfo.name)

		if type(taskInfo.timeSkip) == "string" and taskInfo.timeSkip ~= "" then
			timeSkip(taskInfo.timeSkip)
		end

		runDialogueScript(taskInfo.dialogue or {})
	end
end

-- Puts the player's body under a camera position, facing the same way
local function placePlayerUnder(cameraCFrame)
	local character = player.Character
	if not (character and cameraCFrame) then
		return
	end
	local position = cameraCFrame.Position - Vector3.new(0, EYE_HEIGHT, 0)
	local look = cameraCFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	character:PivotTo(CFrame.lookAt(position, position + look.Unit))
end

-- Replays the intro cutscene under the black screen; the black fades away
-- as soon as the cutscene camera starts moving
local function playIntroCutscene(screen)
	local camera = workspace.CurrentCamera
	local cameraBefore = camera.CFrame
	task.spawn(function()
		local deadline = os.clock() + 10
		while os.clock() < deadline do
			if camera.CameraType == Enum.CameraType.Scriptable
				and (camera.CFrame.Position - cameraBefore.Position).Magnitude > 0.01 then
				break
			end
			task.wait()
		end
		screen.fadeOut()
	end)
	local ok, endCamera = playMegMoCutscene(INTRO_CUTSCENE, "leave")
	screen.fadeOut() -- in case the cutscene was missing
	if ok then
		placePlayerUnder(endCamera)
	end
end

-- Starts a night that isn't the first: intro (or the shift start spot), then its monologue
local function beginNight(night, screen)
	resetBarriers()
	if night.playIntro then
		playIntroCutscene(screen)
	else
		local start = workspace:FindFirstChild(SHIFT_START, true)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if start and humanoid and root then
			local position = standPosition(humanoid, root, start)
			character:PivotTo(flatLookAt(position, position + start.CFrame.LookVector))
		end
		screen.fadeOut()
	end
	setPlayerHeld(false)
	runDialogueScript(night.introDialogue or {})
end

---------------------------------------------------------------------
-- Run
---------------------------------------------------------------------
-- Night 1 starts with the game: wait for the monologue after the intro cutscene
if WAIT_FOR_INTRO_DIALOGUE then
	local deadline = os.clock() + INTRO_TIMEOUT
	while not inDialogue() and os.clock() < deadline do
		task.wait(0.1)
	end
	while inDialogue() do
		task.wait(0.1)
	end
end

-- customers aren't standing around before they come in
hideCutsceneRigs(allCustomerCutscenes())

local nightIndex = 1
local screen = nil -- the black screen carried over from the end of the last night
while NIGHTS[nightIndex] do
	local night = NIGHTS[nightIndex]
	print(("[Tasks] Starting night %d"):format(nightIndex))
	table.clear(noteLines)
	setNote()

	if nightIndex > 1 then
		beginNight(night, screen)
	end

	runTasks(night.tasks)

	if CUSTOMER_ENABLED then
		for _, customer in ipairs(night.customers or {}) do
			task.wait(CUSTOMER_DELAY)
			if customer.walkIn and playMegMoCutscene(customer.walkIn, "stay") then
				runDialogueScript(customer.dialogue or {})
				if customer.walkOut then
					playMegMoCutscene(customer.walkOut, "remove")
				end
			end
		end
	end

	runDialogueScript(night.afterCustomers or {})

	-- Leave for the day: barriers come down so they can get out, then walking
	-- into the area stops the player and fades to black
	resetBarriers()
	runTasks({ LEAVE_TASK })
	setPlayerHeld(true)
	screen = newBlackScreen()
	screen.fadeIn()

	local nextNight = NIGHTS[nightIndex + 1]
	if not nextNight then
		screen.showText(ENDING_TEXT) -- the end: stays on the black screen
		print("[Tasks] All nights done")
		break
	end
	screen.flashText(nextNight.title or ("Night " .. (nightIndex + 1)))
	nightIndex += 1
end