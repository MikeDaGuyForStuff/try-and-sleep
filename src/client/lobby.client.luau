-- LobbyMenu (Client)
-- Put this LocalScript in the LOBBY place: StarterPlayer > StarterPlayerScripts
--
-- Draws the chapter menu ON A PHYSICAL SCREEN in the world, styled like an
-- old VHS tape: scan lines, colour bleeding, static, tracking glitches and
-- the PLAY / date / tape counter overlay in the corners.
--
-- Workspace setup:
--   LobbyScreen  (Part, anchored) - the TV glass. The menu is drawn on its
--                FRONT face (change SCREEN_FACE below if it's another side).
--                Any size works; the menu fits itself to the shape.
--   LobbyCamera  (Part, optional, invisible, anchored) - where the camera
--                sits, with its FRONT face pointed at the screen. Leave it
--                out and the camera is placed in front of the screen for you.
--
-- The chapters and gamepasses are set in the Lobby script (ServerScriptService).
-- Players can click a row, or use W/S or the arrow keys and press Enter.
-- "Support the game" at the bottom switches to the gamepass screen
-- (Backspace also goes back).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")

-- This must run on the PLAYER'S side, once. Stop with a clear message if
-- it's a server Script, or if it's in StarterCharacterScripts (it would
-- run again every time the player respawns).
if game:GetService("RunService"):IsServer() then
	warn("[LobbyMenu] WRONG PLACE: this is a CLIENT script. Delete it from " .. script:GetFullName()
		.. " and put it in a LocalScript inside StarterPlayer > StarterPlayerScripts.")
	return
end
if script:FindFirstAncestorOfClass("Model") and script:FindFirstAncestorOfClass("Model"):FindFirstChildOfClass("Humanoid") then
	warn("[LobbyMenu] WRONG PLACE: this script is inside the character. Move it to "
		.. "StarterPlayer > StarterPlayerScripts (not StarterCharacterScripts).")
	return
end

local player = Players.LocalPlayer

---------------------------------------------------------------------
-- SETTINGS
---------------------------------------------------------------------
local SCREEN_PART_NAME = "LobbyScreen"
local SCREEN_FACE      = Enum.NormalId.Front
local SCREEN_BRIGHTNESS = 1.6          -- how strongly the screen glows

local LOCK_CAMERA      = true          -- point the camera at the screen
local CAMERA_PART_NAME = "LobbyCamera" -- optional part to put the camera at
local CAMERA_FILL      = 0.85          -- how much of the view the screen fills (no camera part)
local CAMERA_SWAY      = true          -- slight handheld drift

local FREEZE_PLAYER    = true          -- stop the character walking around
local UPPERCASE        = true          -- VHS menus were all capitals

-- VHS look
local OSD_DATE         = "OCT. 31 1997"   -- the date in the bottom-left corner
local SCANLINE_GAP     = 4                -- pixels between scan lines
local SCANLINE_DARKNESS = 0.72            -- 0 = solid black lines, 1 = invisible
local COLOR_SPLIT      = 3                -- red/blue edge offset on text (pixels)
local GLITCH_MIN, GLITCH_MAX = 4, 9       -- seconds between tracking glitches

local BG_COLOR        = Color3.fromRGB(10, 12, 26)
local TEXT_COLOR      = Color3.fromRGB(232, 234, 245)
local SELECTED_TEXT   = Color3.fromRGB(12, 12, 24)
local HIGHLIGHT_COLOR = Color3.fromRGB(232, 234, 245)
local FINAL_COLOR     = Color3.fromRGB(235, 90, 90)   -- the hospital chapter
local ERROR_COLOR     = Color3.fromRGB(255, 110, 100)
local FONT_OSD        = Enum.Font.Arcade
local FONT_MENU       = Enum.Font.Code

-- Support screen (the gamepasses themselves are set in the Lobby script)
local SHOW_SUPPORT        = true
local SUPPORT_BUTTON_TEXT = "Support the game"     -- the row at the bottom of the chapter list
local SUPPORT_TITLE       = "Support"
local SUPPORT_MESSAGE     = "Thank you for playing!"
local OWNED_TEXT          = "[OWNED]"
local OWNED_MESSAGE       = "You already own this one. Thank you!"
local THANKS_MESSAGE      = "Thank you so much for your support!"
local SUPPORT_COLOR       = Color3.fromRGB(255, 210, 110)
local OWNED_COLOR         = Color3.fromRGB(120, 235, 140)
local DIM_COLOR           = Color3.fromRGB(140, 140, 155)

-- Dark room: everything goes black except the light from the TV
local DARK_ROOM        = true
local GLOW_COLOR       = Color3.fromRGB(150, 170, 255)  -- the TV's cold blue glow
local GLOW_BRIGHTNESS  = 6         -- the light thrown out into the room
local GLOW_RANGE       = 32        -- studs the glow reaches (max 60)
local GLOW_SHADOWS     = true
local DARK_FOG_DENSITY = 0.55      -- how quickly things far away vanish into black
-- Your own lights (like a small lamp above the TV) stay ON and light the
-- room normally. Set this to true to switch off every other light instead;
-- a light with a true "KeepOn" attribute is still left on.
local TURN_OFF_OTHER_LIGHTS = false
local BLOOM            = true      -- soft glow around the bright screen
---------------------------------------------------------------------

print("[LobbyMenu] started")
local listFunction = ReplicatedStorage:WaitForChild("LobbyChapters")
local lobbyEvent = ReplicatedStorage:WaitForChild("LobbyEvent")
print("[LobbyMenu] found the lobby remotes")

local playerGui = player:WaitForChild("PlayerGui")
local function caps(s) return UPPERCASE and string.upper(s or "") or (s or "") end

---------------------------------------------------------------------
-- Freeze the character while in the lobby
---------------------------------------------------------------------
local function freeze()
	if not FREEZE_PLAYER then return end
	local char = player.Character or player.CharacterAdded:Wait()
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.JumpHeight = 0
	end
end
task.spawn(freeze)
player.CharacterAdded:Connect(function() task.spawn(freeze) end)

-- an invisible "modal" button frees the mouse even in first person
local mouseGui = Instance.new("ScreenGui")
mouseGui.Name = "LobbyMouseFree"
mouseGui.ResetOnSpawn = false
mouseGui.Parent = playerGui
local modal = Instance.new("TextButton")
modal.Size = UDim2.new(0, 0, 0, 0)
modal.BackgroundTransparency = 1
modal.Text = ""
modal.Modal = true
modal.Parent = mouseGui

---------------------------------------------------------------------
-- Find the screen part
---------------------------------------------------------------------
local function findScreen()
	local deadline = os.clock() + 10
	repeat
		local p = workspace:FindFirstChild(SCREEN_PART_NAME, true)
		if p and p:IsA("BasePart") then return p end
		task.wait(0.25)
	until os.clock() > deadline
	return nil
end

-- width, height, outward direction and centre of one face of a part
local function faceInfo(part, face)
	local s = part.Size
	local w, h, depth
	if face == Enum.NormalId.Front or face == Enum.NormalId.Back then
		w, h, depth = s.X, s.Y, s.Z
	elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		w, h, depth = s.Z, s.Y, s.X
	else
		w, h, depth = s.X, s.Z, s.Y
	end
	local normal = part.CFrame:VectorToWorldSpace(Vector3.FromNormalId(face))
	local center = part.Position + normal * (depth / 2)
	return w, h, normal, center
end

local screenPart = findScreen()
local CANVAS_H = 900
local canvasW = 1600

if screenPart then
	local w, h = faceInfo(screenPart, SCREEN_FACE)
	canvasW = math.floor(CANVAS_H * w / math.max(h, 0.01) + 0.5)
	print(("[LobbyMenu] drawing on %s (%s face, %dx%d canvas)"):format(
		screenPart:GetFullName(), SCREEN_FACE.Name, canvasW, CANVAS_H))
else
	warn("[LobbyMenu] no part named '" .. SCREEN_PART_NAME .. "' found in Workspace - showing the menu flat on the screen instead")
end

---------------------------------------------------------------------
-- The canvas (on the TV, or flat on the screen as a backup)
---------------------------------------------------------------------
local canvas = Instance.new("Frame")
canvas.Name = "VHSCanvas"
canvas.BackgroundColor3 = BG_COLOR
canvas.BorderSizePixel = 0
canvas.ClipsDescendants = true

if screenPart then
	local surface = Instance.new("SurfaceGui")
	surface.Name = "LobbyScreenGui"
	surface.Adornee = screenPart
	surface.Face = SCREEN_FACE
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.CanvasSize = Vector2.new(canvasW, CANVAS_H)
	surface.LightInfluence = 0
	surface.Brightness = SCREEN_BRIGHTNESS
	surface.MaxDistance = 1000
	surface.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	surface.ResetOnSpawn = false
	surface.Parent = playerGui      -- must live in PlayerGui for the buttons to be clickable
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.Parent = surface
else
	local flat = Instance.new("ScreenGui")
	flat.Name = "LobbyScreenGui"
	flat.IgnoreGuiInset = true
	flat.ResetOnSpawn = false
	flat.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	flat.Parent = playerGui
	local black = Instance.new("Frame")
	black.Size = UDim2.fromScale(1, 1)
	black.BackgroundColor3 = Color3.new(0, 0, 0)
	black.BorderSizePixel = 0
	black.Parent = flat
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.new(0, canvasW, 0, CANVAS_H)
	canvas.Parent = black
	local scale = Instance.new("UIScale")
	scale.Parent = canvas
	local function fit()
		local cam = workspace.CurrentCamera
		if cam then
			local v = cam.ViewportSize
			scale.Scale = math.min(v.X / canvasW, v.Y / CANVAS_H) * 0.95
		end
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end

---------------------------------------------------------------------
-- Dark room (only changes things for this player)
---------------------------------------------------------------------
local glowLight = nil

if DARK_ROOM then
	-- no sun, no sky light, no ambient light
	Lighting.ClockTime = 0
	Lighting.Brightness = 0
	Lighting.Ambient = Color3.new(0, 0, 0)
	Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0
	Lighting.ExposureCompensation = 0
	Lighting.FogColor = Color3.new(0, 0, 0)
	Lighting.FogStart = 0
	Lighting.FogEnd = 120

	-- a black sky with no stars, sun or moon
	local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	sky.StarCount = 0
	sky.CelestialBodiesShown = false
	sky.Parent = Lighting

	-- thick black air: the sky and anything far away fade to nothing
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmo.Density = DARK_FOG_DENSITY
	atmo.Offset = 0
	atmo.Color = Color3.new(0, 0, 0)
	atmo.Decay = Color3.new(0, 0, 0)
	atmo.Glare = 0
	atmo.Haze = 0
	atmo.Parent = Lighting

	-- clouds would still show up grey
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then clouds.Enabled = false end

	if TURN_OFF_OTHER_LIGHTS then
		local count = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("Light") and not d:GetAttribute("KeepOn")
				and not (screenPart and d:IsDescendantOf(screenPart)) then
				d.Enabled = false
				count += 1
			end
		end
		print("[LobbyMenu] dark room: turned off " .. count .. " other light(s)")
	end

	-- the TV's own glow, shining out of the screen
	if screenPart then
		glowLight = Instance.new("SurfaceLight")
		glowLight.Name = "TVGlow"
		glowLight.Face = SCREEN_FACE
		glowLight.Color = GLOW_COLOR
		glowLight.Brightness = GLOW_BRIGHTNESS
		glowLight.Range = math.clamp(GLOW_RANGE, 0, 60)
		glowLight.Angle = 150
		glowLight.Shadows = GLOW_SHADOWS
		glowLight.Parent = screenPart

	end

	if BLOOM then
		local bloom = Lighting:FindFirstChild("TVBloom") or Instance.new("BloomEffect")
		bloom.Name = "TVBloom"
		bloom.Intensity = 0.9
		bloom.Size = 36
		bloom.Threshold = 0.75
		bloom.Parent = Lighting
	end

	-- a little more contrast and a colder picture
	local cc = Lighting:FindFirstChild("TVColor") or Instance.new("ColorCorrectionEffect")
	cc.Name = "TVColor"
	cc.Contrast = 0.15
	cc.Saturation = -0.15
	cc.TintColor = Color3.fromRGB(225, 232, 255)
	cc.Parent = Lighting

	print("[LobbyMenu] dark room on")
end

-- everything that jitters sideways during a glitch lives in here
local content = Instance.new("Frame")
content.Size = UDim2.fromScale(1, 1)
content.BackgroundTransparency = 1
content.ZIndex = 2
content.Parent = canvas

---------------------------------------------------------------------
-- VHS text: a white label with red and blue copies slightly offset,
-- like the colours bleeding on an old tape
---------------------------------------------------------------------
local vhsTexts = {}

local function vhsText(parent, props)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	holder.Position = props.Position
	holder.Size = props.Size
	holder.ZIndex = props.ZIndex or 3
	holder.Parent = parent

	local function layer(color, transparency, z)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Font = props.Font or FONT_MENU
		l.TextSize = props.TextSize or 32
		l.TextColor3 = color
		l.TextTransparency = transparency
		l.TextXAlignment = props.XAlign or Enum.TextXAlignment.Center
		l.TextYAlignment = Enum.TextYAlignment.Center
		l.TextWrapped = props.Wrap == true
		l.Text = props.Text or ""
		l.ZIndex = z
		l.Parent = holder
		return l
	end

	local red  = layer(Color3.fromRGB(255, 40, 70), 0.45, 1)
	local blue = layer(Color3.fromRGB(40, 210, 255), 0.45, 1)
	local main = layer(props.Color or TEXT_COLOR, 0, 2)
	main.TextStrokeColor3 = props.Color or TEXT_COLOR
	main.TextStrokeTransparency = 0.85      -- soft glow

	local t = { holder = holder, main = main, red = red, blue = blue }
	function t.set(text)
		main.Text, red.Text, blue.Text = text, text, text
	end
	function t.color(c)
		main.TextColor3 = c
		main.TextStrokeColor3 = c
	end
	table.insert(vhsTexts, t)
	return t
end

---------------------------------------------------------------------
-- The on-screen display in the corners
---------------------------------------------------------------------
local PAD = 60
local osdPlay = vhsText(content, {
	Position = UDim2.new(0, PAD, 0, PAD - 10), Size = UDim2.new(0, 400, 0, 50),
	Font = FONT_OSD, TextSize = 44, XAlign = Enum.TextXAlignment.Left, Text = "PLAY  >",
})
vhsText(content, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -PAD, 0, PAD - 10), Size = UDim2.new(0, 200, 0, 50),
	Font = FONT_OSD, TextSize = 44, XAlign = Enum.TextXAlignment.Right, Text = "SP",
})
local osdCounter = vhsText(content, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, PAD, 1, -PAD - 44), Size = UDim2.new(0, 500, 0, 44),
	Font = FONT_OSD, TextSize = 36, XAlign = Enum.TextXAlignment.Left, Text = "0:00:00",
})
vhsText(content, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, PAD, 1, -PAD + 4), Size = UDim2.new(0, 600, 0, 44),
	Font = FONT_OSD, TextSize = 36, XAlign = Enum.TextXAlignment.Left, Text = OSD_DATE,
})

---------------------------------------------------------------------
-- Effects layered on top: scan lines, static, a rolling bright band,
-- dark edges and a faint flicker
---------------------------------------------------------------------
local scan = Instance.new("Frame")
scan.Size = UDim2.fromScale(1, 1)
scan.BackgroundTransparency = 1
scan.ZIndex = 20
scan.Parent = canvas
for y = 0, CANVAS_H, SCANLINE_GAP do
	local line = Instance.new("Frame")
	line.Position = UDim2.new(0, 0, 0, y)
	line.Size = UDim2.new(1, 0, 0, math.max(1, math.floor(SCANLINE_GAP / 2)))
	line.BackgroundColor3 = Color3.new(0, 0, 0)
	line.BackgroundTransparency = SCANLINE_DARKNESS
	line.BorderSizePixel = 0
	line.ZIndex = 20
	line.Parent = scan
end

-- the slow bright band that rolls down the picture
local band = Instance.new("Frame")
band.Size = UDim2.new(1, 0, 0, 140)
band.BackgroundColor3 = Color3.new(1, 1, 1)
band.BackgroundTransparency = 0
band.BorderSizePixel = 0
band.ZIndex = 21
band.Parent = canvas
local bandGradient = Instance.new("UIGradient")
bandGradient.Rotation = 90
bandGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 0.93),
	NumberSequenceKeypoint.new(1, 1),
})
bandGradient.Parent = band

-- static: little white streaks that pop in and out
local noise = {}
for i = 1, 40 do
	local n = Instance.new("Frame")
	n.BackgroundColor3 = Color3.new(1, 1, 1)
	n.BorderSizePixel = 0
	n.ZIndex = 22
	n.Visible = false
	n.Parent = canvas
	noise[i] = n
end

-- dark edges, like the curve of an old CRT
local function edgeShade(rotation)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.ZIndex = 23
	f.Parent = canvas
	local g = Instance.new("UIGradient")
	g.Rotation = rotation
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.12, 1),
		NumberSequenceKeypoint.new(0.88, 1),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	g.Parent = f
end
edgeShade(0)
edgeShade(90)

local flash = Instance.new("Frame")
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.new(1, 1, 1)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.ZIndex = 24
flash.Parent = canvas

---------------------------------------------------------------------
-- Black loading screen shown while the teleport happens
---------------------------------------------------------------------
local loadingGui = Instance.new("ScreenGui")
loadingGui.Name = "ChapterLoading"
loadingGui.IgnoreGuiInset = true
local loadingBg = Instance.new("Frame")
loadingBg.Size = UDim2.fromScale(1, 1)
loadingBg.BackgroundColor3 = Color3.new(0, 0, 0)
loadingBg.BorderSizePixel = 0
loadingBg.Parent = loadingGui
local loadingText = Instance.new("TextLabel")
loadingText.Size = UDim2.fromScale(1, 1)
loadingText.BackgroundTransparency = 1
loadingText.Font = FONT_OSD
loadingText.TextSize = 36
loadingText.TextColor3 = TEXT_COLOR
loadingText.Text = "..."
loadingText.Parent = loadingBg
pcall(function() TeleportService:SetTeleportGui(loadingGui) end)

---------------------------------------------------------------------
-- Get the chapter list from the server
---------------------------------------------------------------------
local info
for attempt = 1, 10 do
	local ok, result = pcall(function() return listFunction:InvokeServer() end)
	if ok and type(result) == "table" then
		info = result
		break
	end
	warn("[LobbyMenu] couldn't get the chapter list (attempt " .. attempt .. "): " .. tostring(result))
	task.wait(1)
end
if not info then
	warn("[LobbyMenu] gave up getting the chapter list - is the Lobby script in ServerScriptService?")
	info = { title = "NO SIGNAL", chapters = {} }
end
local chapters = info.chapters or {}
print("[LobbyMenu] got " .. #chapters .. " chapter(s)")

---------------------------------------------------------------------
-- The menu
-- Two screens on the same TV: the chapter list, and the support screen
-- with the gamepasses. Everything sits in the space BETWEEN the corner
-- overlays (PLAY/SP at the top, counter/date at the bottom), so nothing
-- ever overlaps them. With lots of rows they get a bit shorter, and the
-- gamepass list splits into pages if it still doesn't fit.
---------------------------------------------------------------------
local SAFE_TOP = PAD + 50                           -- just below PLAY / SP
local SAFE_BOTTOM = CANVAS_H - (PAD + 88) - 16      -- just above the counter and date
local safeH = SAFE_BOTTOM - SAFE_TOP

local TITLE_H, STATUS_H, BLOCK_GAP = 80, 70, 24
local ROW_GAP = 10
local MIN_ROW_H, MAX_ROW_H = 40, 66
local MENU_W = math.min(1150, canvasW - 2 * PAD - 40)
local rowSpace = safeH - TITLE_H - STATUS_H - 2 * BLOCK_GAP
local MAX_ROWS = math.max(3, math.floor((rowSpace + ROW_GAP) / (MIN_ROW_H + ROW_GAP)))

local screenFrame = nil   -- the screen being shown right now
local status = nil        -- that screen's message line
local rows = {}
local selected = 1
local waiting = false     -- true while teleporting to a chapter
local loadingScreen = false
local currentScreen = "chapters"
local passes = nil        -- the gamepass list from the server
local passPage = 1

-- set by the effects section below
local triggerGlitch = function(_seconds, _power) end

local function setStatus(text, isError)
	if not status then return end
	status.set(caps(text or ""))
	status.color(isError and ERROR_COLOR or TEXT_COLOR)
end

local function refreshRows()
	for i, row in ipairs(rows) do
		local on = i == selected
		row.bar.Visible = on
		row.text.set((on and "> " or "  ") .. row.baseText)
		row.text.color(on and SELECTED_TEXT or row.color)
		if row.right then
			row.right.color(on and SELECTED_TEXT or row.rightColor)
		end
	end
end

local function selectRow(i)
	if #rows == 0 then return end
	i = math.clamp(i, 1, #rows)
	if i ~= selected then
		selected = i
		refreshRows()
		triggerGlitch(0.08, 0.4)
	end
end

local function pick(i)
	if waiting or loadingScreen or not rows[i] then return end
	selected = i
	refreshRows()
	rows[i].action()
end

-- Builds a screen: a title, a list of rows and a message line.
-- Each row: { text =, right = (optional text on the right), color =,
--             rightColor =, action = function() ... end }
local function buildScreen(titleText, specs)
	if screenFrame then screenFrame:Destroy() end
	rows = {}

	screenFrame = Instance.new("Frame")
	screenFrame.Size = UDim2.fromScale(1, 1)
	screenFrame.BackgroundTransparency = 1
	screenFrame.ZIndex = 3
	screenFrame.Parent = content

	local n = #specs
	local rowH = MAX_ROW_H
	if n > 0 then
		rowH = math.clamp(math.floor((rowSpace + ROW_GAP) / n) - ROW_GAP, MIN_ROW_H, MAX_ROW_H)
	end
	local rowText = math.floor(34 * rowH / 66)
	local listHeight = math.max(n * (rowH + ROW_GAP) - ROW_GAP, 0)
	local stackH = TITLE_H + BLOCK_GAP + listHeight + BLOCK_GAP + STATUS_H
	local stackTop = SAFE_TOP + math.max(0, (safeH - stackH) / 2)
	local listTop = stackTop + TITLE_H + BLOCK_GAP

	vhsText(screenFrame, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, stackTop), Size = UDim2.new(0, MENU_W, 0, TITLE_H),
		Font = FONT_OSD, TextSize = 62, Text = caps(titleText),
	})

	-- the message line has its own box under the list; long messages
	-- wrap onto a second line and shrink if they still don't fit
	status = vhsText(screenFrame, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, listTop + listHeight + BLOCK_GAP), Size = UDim2.new(0, MENU_W, 0, STATUS_H),
		Font = FONT_MENU, TextSize = 26, Wrap = true, Text = "",
	})
	for _, l in ipairs({ status.main, status.red, status.blue }) do
		l.TextScaled = true
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 26
		limit.MinTextSize = 14
		limit.Parent = l
	end

	for i, spec in ipairs(specs) do
		local button = Instance.new("TextButton")
		button.AnchorPoint = Vector2.new(0.5, 0)
		button.Position = UDim2.new(0.5, 0, 0, listTop + (i - 1) * (rowH + ROW_GAP))
		button.Size = UDim2.new(0, MENU_W, 0, rowH)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.AutoButtonColor = false
		button.ZIndex = 3
		button.Parent = screenFrame

		local bar = Instance.new("Frame")
		bar.Size = UDim2.fromScale(1, 1)
		bar.BackgroundColor3 = HIGHLIGHT_COLOR
		bar.BackgroundTransparency = 0.08
		bar.BorderSizePixel = 0
		bar.ZIndex = 1
		bar.Visible = false
		bar.Parent = button

		local RIGHT_W = 300
		local text = vhsText(button, {
			Position = UDim2.new(0, 24, 0, 0),
			Size = UDim2.new(1, spec.right and -(48 + RIGHT_W) or -48, 1, 0),
			Font = FONT_MENU, TextSize = rowText, XAlign = Enum.TextXAlignment.Left, ZIndex = 2,
		})
		for _, l in ipairs({ text.main, text.red, text.blue }) do
			l.TextTruncate = Enum.TextTruncate.AtEnd
		end

		local right = nil
		if spec.right then
			right = vhsText(button, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -24, 0, 0), Size = UDim2.new(0, RIGHT_W, 1, 0),
				Font = FONT_MENU, TextSize = rowText, XAlign = Enum.TextXAlignment.Right, ZIndex = 2,
				Text = spec.right,
			})
		end

		rows[i] = {
			bar = bar, text = text, right = right,
			baseText = spec.text,
			color = spec.color or TEXT_COLOR,
			rightColor = spec.rightColor or TEXT_COLOR,
			action = spec.action or function() end,
		}

		button.MouseEnter:Connect(function()
			if not waiting then selectRow(i) end
		end)
		button.Activated:Connect(function()
			pick(i)
		end)
	end

	selected = math.clamp(selected, 1, math.max(n, 1))
	refreshRows()
end

---------------------------------------------------------------------
-- Chapters screen
---------------------------------------------------------------------
local showChapters, showSupport, renderSupport

local function goToChapter(ch)
	waiting = true
	print("[LobbyMenu] picked " .. tostring(ch.id))
	osdPlay.set("LOADING")
	setStatus("Please wait...")
	loadingText.Text = ("%s\n%s"):format(caps(ch.label), caps(ch.name))
	triggerGlitch(0.6, 1)
	lobbyEvent:FireServer("Pick", ch.id)
end

showChapters = function()
	currentScreen = "chapters"
	local specs = {}
	for _, ch in ipairs(chapters) do
		table.insert(specs, {
			text = ("%s   %s"):format(caps(ch.label), caps(ch.name)),
			color = ch.id == "hospital" and FINAL_COLOR or nil,
			action = function() goToChapter(ch) end,
		})
	end
	if SHOW_SUPPORT then
		table.insert(specs, {
			text = caps(SUPPORT_BUTTON_TEXT),
			color = SUPPORT_COLOR,
			action = function()
				selected = 1
				passPage = 1
				showSupport()
			end,
		})
	end
	buildScreen(info.title or "Choose a chapter", specs)
	if #chapters == 0 then
		setStatus("No chapters - check the Lobby script", true)
	end
end

---------------------------------------------------------------------
-- Support screen (gamepasses)
---------------------------------------------------------------------
local passFunction = ReplicatedStorage:WaitForChild("LobbyGamepasses", 10)
if not passFunction then
	warn("[LobbyMenu] no LobbyGamepasses remote - is the NEW Lobby script in ServerScriptService?")
end

local function backToChapters()
	-- land back on the support row
	selected = #chapters + 1
	triggerGlitch(0.4, 1)
	showChapters()
end

local function buyPass(p)
	if p.owned then
		setStatus(OWNED_MESSAGE)
		triggerGlitch(0.1, 0.5)
		return
	end
	if not p.price then
		setStatus("That one isn't for sale right now.", true)
		return
	end
	print("[LobbyMenu] opening purchase for gamepass " .. tostring(p.id))
	setStatus("Opening the purchase...")
	local ok, err = pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, p.id)
	end)
	if not ok then
		setStatus("Couldn't open the purchase: " .. tostring(err), true)
	end
end

renderSupport = function()
	local list = passes or {}
	local perPage = math.max(1, MAX_ROWS - 3)   -- leave room for next / previous / back
	local pageCount = math.max(1, math.ceil(#list / perPage))
	passPage = math.clamp(passPage, 1, pageCount)

	local specs = {}
	local first = (passPage - 1) * perPage + 1
	for i = first, math.min(#list, first + perPage - 1) do
		local p = list[i]
		local right, rightColor
		if p.owned then
			right, rightColor = OWNED_TEXT, OWNED_COLOR
		elseif p.price then
			right, rightColor = ("R$ %d"):format(p.price), TEXT_COLOR
		else
			right, rightColor = "OFFSALE", DIM_COLOR
		end
		table.insert(specs, {
			text = caps(p.name),
			right = right,
			rightColor = rightColor,
			color = p.owned and OWNED_COLOR or nil,
			action = function() buyPass(p) end,
		})
	end
	if passPage < pageCount then
		table.insert(specs, { text = "NEXT PAGE  >", action = function()
			passPage += 1
			selected = 1
			triggerGlitch(0.3, 0.8)
			renderSupport()
		end })
	end
	if passPage > 1 then
		table.insert(specs, { text = "<  PREVIOUS PAGE", action = function()
			passPage -= 1
			selected = 1
			triggerGlitch(0.3, 0.8)
			renderSupport()
		end })
	end
	table.insert(specs, { text = "<  BACK", action = backToChapters })

	local title = SUPPORT_TITLE
	if pageCount > 1 then title = ("%s  %d/%d"):format(SUPPORT_TITLE, passPage, pageCount) end
	buildScreen(title, specs)

	if passes == nil then
		setStatus("Couldn't load the gamepasses. Try again in a moment.", true)
	elseif #list == 0 then
		setStatus("Nothing here yet.")
	else
		setStatus(SUPPORT_MESSAGE)
	end
end

showSupport = function()
	currentScreen = "support"
	loadingScreen = true
	buildScreen(SUPPORT_TITLE, {})
	setStatus("Loading...")
	triggerGlitch(0.5, 1)

	task.spawn(function()
		local list = nil
		if passFunction then
			local ok, result = pcall(function() return passFunction:InvokeServer() end)
			if ok and type(result) == "table" then
				list = result
			else
				warn("[LobbyMenu] couldn't get the gamepasses: " .. tostring(result))
			end
		end
		print("[LobbyMenu] got " .. (list and #list or 0) .. " gamepass(es)")
		loadingScreen = false
		if currentScreen ~= "support" then return end
		passes = list
		renderSupport()
	end)
end

showChapters()

-- the purchase window closed without buying: put the normal message back
pcall(function()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, _id, purchased)
		if plr == player and not purchased and currentScreen == "support" then
			setStatus(SUPPORT_MESSAGE)
		end
	end)
end)

-- keyboard / controller
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or waiting or loadingScreen then return end
	local k = input.KeyCode
	if k == Enum.KeyCode.Up or k == Enum.KeyCode.W or k == Enum.KeyCode.DPadUp then
		selectRow(selected - 1)
	elseif k == Enum.KeyCode.Down or k == Enum.KeyCode.S or k == Enum.KeyCode.DPadDown then
		selectRow(selected + 1)
	elseif k == Enum.KeyCode.Return or k == Enum.KeyCode.KeypadEnter or k == Enum.KeyCode.ButtonA then
		pick(selected)
	elseif (k == Enum.KeyCode.Backspace or k == Enum.KeyCode.ButtonB) and currentScreen == "support" then
		backToChapters()
	end
end)

---------------------------------------------------------------------
-- Messages from the server
---------------------------------------------------------------------
lobbyEvent.OnClientEvent:Connect(function(action, a, b)
	if action == "Status" then
		local text, isError = a, b
		print("[LobbyMenu] status: " .. tostring(text))
		setStatus(text, isError)
		if isError then
			waiting = false      -- let them pick again
			osdPlay.set("PLAY  >")
			triggerGlitch(0.3, 1)
		end

	elseif action == "PassOwned" then
		-- a purchase went through: mark it owned right away
		print("[LobbyMenu] now own gamepass " .. tostring(a))
		if passes then
			for _, p in ipairs(passes) do
				if p.id == a then p.owned = true end
			end
		end
		if currentScreen == "support" and not loadingScreen then
			local keep = selected
			renderSupport()
			selected = keep
			refreshRows()
			setStatus(THANKS_MESSAGE)
			triggerGlitch(0.4, 1)
		end
	end
end)

---------------------------------------------------------------------
-- Animating the effects
---------------------------------------------------------------------
local startTime = os.clock()
local glitchUntil = 0
local glitchPower = 0
local nextGlitch = os.clock() + math.random(GLITCH_MIN, GLITCH_MAX)

triggerGlitch = function(seconds, power)
	glitchUntil = math.max(glitchUntil, os.clock() + seconds)
	glitchPower = math.max(glitchPower, power or 1)
end

local accum = 0
RunService.RenderStepped:Connect(function(dt)
	accum += dt
	if accum < 1 / 30 then return end   -- old tapes run at about 30 frames a second
	accum = 0

	local now = os.clock()
	if now > nextGlitch then
		triggerGlitch(0.2 + math.random() * 0.35, 0.6 + math.random() * 0.6)
		nextGlitch = now + math.random(GLITCH_MIN, GLITCH_MAX)
	end
	local glitching = now < glitchUntil
	if not glitching then glitchPower = 0 end

	-- sideways jitter
	local jx = 0
	if glitching then
		jx = (math.random() - 0.5) * 24 * glitchPower
	elseif math.random() < 0.03 then
		jx = (math.random() - 0.5) * 4
	end
	content.Position = UDim2.new(0, jx, 0, 0)

	-- colour bleeding on every piece of text
	local split = COLOR_SPLIT * (glitching and (1 + 3 * glitchPower) or 1)
	for i = #vhsTexts, 1, -1 do
		if not vhsTexts[i].holder.Parent then table.remove(vhsTexts, i) end   -- from a screen that was closed
	end
	for _, t in ipairs(vhsTexts) do
		local wobble = (math.random() - 0.5) * (glitching and 4 or 0.8)
		t.red.Position = UDim2.new(0, -split + wobble, 0, 0)
		t.blue.Position = UDim2.new(0, split + wobble, 0, 0)
	end

	-- rolling bright band
	local period = 7
	local y = ((now - startTime) % period) / period * (CANVAS_H + 280) - 140
	band.Position = UDim2.new(0, 0, 0, y)

	-- static: always a little near the bottom of the tape, lots during a glitch
	local glitchY = math.random() * CANVAS_H
	for _, n in ipairs(noise) do
		local chance = glitching and 0.6 or 0.12
		if math.random() < chance then
			n.Visible = true
			local ny
			if glitching and math.random() < 0.6 then
				ny = glitchY + (math.random() - 0.5) * 120      -- a torn strip
			else
				ny = CANVAS_H - math.random() * 45                -- the noisy bottom edge
			end
			n.Position = UDim2.new(0, math.random() * canvasW, 0, ny)
			n.Size = UDim2.new(0, 20 + math.random() * (glitching and 400 or 160), 0, 1 + math.random(0, 2))
			n.BackgroundTransparency = 0.2 + math.random() * 0.6
		else
			n.Visible = false
		end
	end

	-- faint flicker (the light in the room flickers with the picture)
	flash.BackgroundTransparency = glitching and (0.85 + math.random() * 0.15) or (0.97 + math.random() * 0.03)
	if glowLight then
		local wobble = glitching and (0.55 + math.random() * 0.7) or (0.93 + math.random() * 0.1)
		glowLight.Brightness = GLOW_BRIGHTNESS * wobble
	end

	-- tape counter and a blinking PLAY while loading
	local e = math.floor(now - startTime)
	osdCounter.set(("%d:%02d:%02d"):format(e // 3600, (e // 60) % 60, e % 60))
	if waiting then
		osdPlay.holder.Visible = math.floor(now * 2) % 2 == 0
	else
		osdPlay.holder.Visible = true
	end
end)

---------------------------------------------------------------------
-- Camera: look at the screen
---------------------------------------------------------------------
if LOCK_CAMERA and screenPart then
	local function baseCameraCFrame()
		local camPart = workspace:FindFirstChild(CAMERA_PART_NAME, true)
		if camPart and camPart:IsA("BasePart") then
			return camPart.CFrame
		end
		local cam = workspace.CurrentCamera
		local w, h, normal, center = faceInfo(screenPart, SCREEN_FACE)
		local v = cam.ViewportSize
		local aspect = v.X / math.max(v.Y, 1)
		local needH = math.max(h, w / aspect) / CAMERA_FILL
		local dist = (needH / 2) / math.tan(math.rad(cam.FieldOfView) / 2)
		local up = screenPart.CFrame.UpVector
		if SCREEN_FACE == Enum.NormalId.Top or SCREEN_FACE == Enum.NormalId.Bottom then
			up = screenPart.CFrame.LookVector
		end
		return CFrame.lookAt(center + normal * dist, center, up)
	end

	if workspace:FindFirstChild(CAMERA_PART_NAME, true) then
		print("[LobbyMenu] camera using the part " .. CAMERA_PART_NAME)
	else
		print("[LobbyMenu] no " .. CAMERA_PART_NAME .. " part, placing the camera in front of the screen")
	end

	RunService:BindToRenderStep("LobbyCamera", Enum.RenderPriority.Camera.Value + 1, function()
		local cam = workspace.CurrentCamera
		if not cam then return end
		cam.CameraType = Enum.CameraType.Scriptable
		local cf = baseCameraCFrame()
		if CAMERA_SWAY then
			local t = os.clock()
			cf = cf * CFrame.Angles(math.sin(t * 0.5) * 0.004, math.sin(t * 0.37) * 0.006, 0)
		end
		cam.CFrame = cf
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end)
end

print("[LobbyMenu] menu ready")