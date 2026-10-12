-- MiniGame (Client)
-- Put this LocalScript in: StarterPlayer > StarterPlayerScripts
--
-- Two little interactions the server can ask for:
--   {"MiniGame", "scrub",  { rounds = 3, need = 2200, title = "Scrub the plate" }}
--       rub the mouse back and forth to clean something, a few times over
--   {"MiniGame", "timing", { rounds = 3, speed = 1.1, zone = 0.18, title = "Sweep" }}
--       stop the moving marker inside the zone, a few times over

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("MiniGameEvent")

---------------------------------------------------------------------
-- SETTINGS
---------------------------------------------------------------------
local DESIGN_W, DESIGN_H = 1600, 900
local PANEL_W, PANEL_H = 760, 190

local INK       = Color3.fromRGB(235, 232, 225)
local GOOD      = Color3.fromRGB(120, 200, 130)
local BAD       = Color3.fromRGB(200, 90, 80)
local BAR_BG    = Color3.fromRGB(35, 35, 38)
local FILL      = Color3.fromRGB(210, 205, 190)
---------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "MiniGameGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 25
gui.Parent = player:WaitForChild("PlayerGui")

-- pinned to the bottom centre with no size, so UIScale only affects pixels
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

---------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0, 0, 0, -90)
panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
panel.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
panel.BackgroundTransparency = 0.2
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = root
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
local stroke = Instance.new("UIStroke", panel)
stroke.Color = Color3.fromRGB(60, 55, 50)

local pad = Instance.new("UIPadding", panel)
pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 18), UDim.new(0, 18)
pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 24), UDim.new(0, 24)

local function makeLabel(size, position, textSize, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = Enum.Font.SpecialElite
	l.TextSize = textSize
	l.TextColor3 = INK
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.Text = ""
	l.Parent = panel
	return l
end

local title = makeLabel(UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 0, 0), 30)
local counter = makeLabel(UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 0, 0), 26, Enum.TextXAlignment.Right)
local hint = makeLabel(UDim2.new(1, 0, 0, 24), UDim2.new(0, 0, 1, -24), 19)
hint.TextTransparency = 0.35

-- the bar both games use
local track = Instance.new("Frame")
track.Position = UDim2.new(0, 0, 0, 62)
track.Size = UDim2.new(1, 0, 0, 40)
track.BackgroundColor3 = BAR_BG
track.BorderSizePixel = 0
track.Parent = panel
Instance.new("UICorner", track).CornerRadius = UDim.new(0, 4)

local zone = Instance.new("Frame")           -- timing game: the target
zone.BackgroundColor3 = GOOD
zone.BackgroundTransparency = 0.55
zone.BorderSizePixel = 0
zone.Size = UDim2.new(0.2, 0, 1, 0)
zone.Visible = false
zone.Parent = track

local marker = Instance.new("Frame")         -- timing game: the moving line
marker.BackgroundColor3 = INK
marker.BorderSizePixel = 0
marker.Size = UDim2.new(0, 6, 1, 0)
marker.Visible = false
marker.ZIndex = 3
marker.Parent = track

local fill = Instance.new("Frame")           -- scrub game: how clean it is
fill.BackgroundColor3 = FILL
fill.BorderSizePixel = 0
fill.Size = UDim2.new(0, 0, 1, 0)
fill.Visible = false
fill.Parent = track
Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)

---------------------------------------------------------------------
-- Input
---------------------------------------------------------------------
local pressed = Instance.new("BindableEvent")
local rubAmount = 0
local active = false

UserInputService.InputBegan:Connect(function(input)
	if not active then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.Space
		or input.KeyCode == Enum.KeyCode.E then
		pressed:Fire()
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not active then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		rubAmount = rubAmount + math.abs(input.Delta.X) + math.abs(input.Delta.Y) * 0.5
	end
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

local function flash(color)
	local old = track.BackgroundColor3
	track.BackgroundColor3 = color
	TweenService:Create(track, TweenInfo.new(0.4), { BackgroundColor3 = old }):Play()
end

---------------------------------------------------------------------
-- The games
---------------------------------------------------------------------
local function playScrub(cfg)
	local rounds = cfg.rounds or 3
	local need = cfg.need or 2200

	title.Text = cfg.title or "Scrub it clean"
	hint.Text = "move the mouse back and forth"
	fill.Visible = true
	zone.Visible = false
	marker.Visible = false

	for round = 1, rounds do
		counter.Text = round .. " / " .. rounds
		rubAmount = 0
		fill.Size = UDim2.new(0, 0, 1, 0)

		while rubAmount < need do
			fill.Size = UDim2.new(math.clamp(rubAmount / need, 0, 1), 0, 1, 0)
			task.wait(1 / 30)
		end

		fill.Size = UDim2.new(1, 0, 1, 0)
		flash(GOOD)
		task.wait(0.35)
	end
	fill.Visible = false
end

local function playTiming(cfg)
	local rounds = cfg.rounds or 3
	local speed = cfg.speed or 1.1        -- sweeps per second
	local zoneWidth = cfg.zone or 0.18

	title.Text = cfg.title or "Time it right"
	hint.Text = "click or press SPACE inside the light patch"
	zone.Visible = true
	marker.Visible = true
	fill.Visible = false

	for round = 1, rounds do
		counter.Text = round .. " / " .. rounds
		local zoneStart = math.random() * (1 - zoneWidth)
		zone.Position = UDim2.new(zoneStart, 0, 0, 0)
		zone.Size = UDim2.new(zoneWidth, 0, 1, 0)

		local pos, dir = 0, 1
		local moving = RunService.RenderStepped:Connect(function(dt)
			pos = pos + dir * speed * dt
			if pos >= 1 then pos, dir = 1, -1 elseif pos <= 0 then pos, dir = 0, 1 end
			marker.Position = UDim2.new(pos, -3, 0, 0)
		end)

		-- keep going until they land it
		while true do
			pressed.Event:Wait()
			if pos >= zoneStart and pos <= zoneStart + zoneWidth then
				break
			end
			flash(BAD)
			task.wait(0.2)
		end

		moving:Disconnect()
		flash(GOOD)
		task.wait(0.35)
	end

	zone.Visible = false
	marker.Visible = false
end

---------------------------------------------------------------------
-- Server messages
---------------------------------------------------------------------
local running = false

remote.OnClientEvent:Connect(function(kind, cfg)
	if running then return end
	running = true
	active = true
	cfg = cfg or {}

	setFrozen(true)
	panel.Visible = true

	-- let the server know we're still playing
	task.spawn(function()
		while running do
			remote:FireServer("Alive")
			task.wait(2)
		end
	end)

	if kind == "timing" then
		playTiming(cfg)
	else
		playScrub(cfg)
	end

	panel.Visible = false
	active = false
	setFrozen(false)
	running = false
	remote:FireServer("Done")
end)