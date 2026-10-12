-- Doors-style first person camera
-- Put this LocalScript in: StarterPlayer > StarterCharacterScripts

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local head = character:WaitForChild("Head")
local camera = workspace.CurrentCamera

-- The joint that connects the body to the HumanoidRootPart (works for R15 and R6)
local rootJoint
if humanoid.RigType == Enum.HumanoidRigType.R15 then
	rootJoint = character:WaitForChild("LowerTorso"):WaitForChild("Root")
else
	rootJoint = rootPart:WaitForChild("RootJoint")
end
local originalC0 = rootJoint.C0

---------------------------------------------------------------------
-- SETTINGS (tweak these to taste)
---------------------------------------------------------------------
local WALK_SPEED    = 12                      -- Doors-ish slow walk
local HEAD_OFFSET   = Vector3.new(0, 0, -1)   -- pushes camera forward so you can see your body

local BOB_SPEED     = 9      -- how fast the steps are
local BOB_Y         = 0.12   -- up/down bob amount
local BOB_X         = 0.07   -- side-to-side bob amount
local BOB_ROLL      = 1.0    -- degrees of roll per step

local STRAFE_TILT   = 3.5    -- degrees of tilt when moving sideways
local MOUSE_SWAY    = 0.05   -- tilt from turning the mouse
local MAX_SWAY      = 4      -- max degrees of mouse sway

local BREATH_SPEED  = 1.4    -- idle breathing speed
local BREATH_AMOUNT = 0.025  -- idle breathing amount

local SMOOTHING     = 10     -- higher = snappier, lower = floatier
---------------------------------------------------------------------

player.CameraMode = Enum.CameraMode.LockFirstPerson
humanoid.WalkSpeed = WALK_SPEED
humanoid.CameraOffset = HEAD_OFFSET

-- Figure out which parts should stay hidden (head + anything worn on the head)
local function isHeadPart(part)
	if part == head then
		return true
	end
	local accessory = part:FindFirstAncestorOfClass("Accessory")
	if accessory then
		local weld = part:FindFirstChildWhichIsA("Weld") or part:FindFirstChildWhichIsA("WeldConstraint")
		if weld and (weld.Part0 == head or weld.Part1 == head) then
			return true
		end
	end
	return false
end

local visibleParts = {}

local function register(part)
	if part:IsA("BasePart") and not isHeadPart(part) then
		visibleParts[part] = true
	end
end

for _, d in ipairs(character:GetDescendants()) do
	register(d)
end
character.DescendantAdded:Connect(function(d)
	task.wait() -- let accessory welds get created first
	register(d)
end)
character.DescendantRemoving:Connect(function(d)
	visibleParts[d] = nil
end)

-- State
local stepTime = 0
local breathTime = 0
local bobIntensity = 0
local currentTilt = 0
local currentSway = 0

local function lerp(a, b, t)
	return a + (b - a) * t
end

local BIND_NAME = "DoorsCamera"
RunService:UnbindFromRenderStep(BIND_NAME)

RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
	-- during a cinematic (night 5), leave the camera and body alone
	if workspace:GetAttribute("CinematicMode") then
		if rootJoint and rootJoint.Parent then
			rootJoint.C0 = originalC0
		end
		return
	end

	local alpha = 1 - math.exp(-SMOOTHING * dt)

	-- Show the body (Roblox hides it in first person)
	for part in pairs(visibleParts) do
		part.LocalTransparencyModifier = 0
	end

	-- Movement info
	local velocity = rootPart.AssemblyLinearVelocity
	local flatVel = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = flatVel.Magnitude
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local moving = speed > 0.5 and grounded

	-- Walk bob
	bobIntensity = lerp(bobIntensity, moving and math.clamp(speed / WALK_SPEED, 0, 1.5) or 0, alpha)
	if moving then
		stepTime += dt * BOB_SPEED * math.clamp(speed / WALK_SPEED, 0.5, 1.5)
	end

	local bobX = math.sin(stepTime) * BOB_X * bobIntensity
	local bobY = -math.abs(math.sin(stepTime)) * BOB_Y * bobIntensity
	local bobRoll = math.sin(stepTime) * BOB_ROLL * bobIntensity

	-- Idle breathing (fades out while walking)
	breathTime += dt * BREATH_SPEED
	local breathY = math.sin(breathTime) * BREATH_AMOUNT * (1 - math.clamp(bobIntensity, 0, 1))

	-- Tilt when strafing (A/D)
	local localVel = camera.CFrame:VectorToObjectSpace(flatVel)
	local targetTilt = -(localVel.X / WALK_SPEED) * STRAFE_TILT
	currentTilt = lerp(currentTilt, targetTilt, alpha)

	-- Sway when turning the mouse
	local mouseDelta = UserInputService:GetMouseDelta()
	local targetSway = math.clamp(-mouseDelta.X * MOUSE_SWAY, -MAX_SWAY, MAX_SWAY)
	currentSway = lerp(currentSway, targetSway, alpha * 0.6)

	-- Apply on top of the default camera (roll + position only, so it never drifts)
	local totalRoll = math.rad(bobRoll + currentTilt + currentSway)
	local offset = CFrame.new(bobX, bobY + breathY, 0) * CFrame.Angles(0, 0, totalRoll)
	local baseCF = camera.CFrame
	camera.CFrame = baseCF * offset

	-- Move the body with the camera so it stays steady on screen
	-- (C0 changes on the client don't replicate, so only you see this)
	local worldShift = baseCF * offset * baseCF:Inverse()
	local rootCF = rootPart.CFrame
	rootJoint.C0 = rootCF:Inverse() * worldShift * rootCF * originalC0
end)

local function cleanup()
	RunService:UnbindFromRenderStep(BIND_NAME)
	if rootJoint and rootJoint.Parent then
		rootJoint.C0 = originalC0
	end
end

humanoid.Died:Connect(cleanup)
script.Destroying:Connect(cleanup)