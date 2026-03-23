--[[
    CameraController.luau (Client)

    Manages dynamic camera effects during gameplay:
      - Camera shake during disasters (earthquake, explosions)
      - Smooth transitions between gameplay phases
      - Briefing camera (overview of disaster zone)
      - Cinematic extraction camera
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local CameraController = {}
CameraController.__index = CameraController

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local shakeIntensity: number = 0
local shakeDuration: number = 0
local shakeStartTime: number = 0
local isShaking: boolean = false

----------------------------------------------------------------------
-- CAMERA SHAKE
----------------------------------------------------------------------

--- Start camera shake with given intensity and duration.
function CameraController:Shake(intensity: number, duration: number)
    shakeIntensity = intensity
    shakeDuration = duration
    shakeStartTime = os.clock()
    isShaking = true
end

--- Stop all camera shake.
function CameraController:StopShake()
    isShaking = false
    shakeIntensity = 0
end

local function updateShake()
    if not isShaking then return end

    local elapsed = os.clock() - shakeStartTime
    if elapsed > shakeDuration then
        isShaking = false
        return
    end

    -- Fade out intensity over duration
    local progress = elapsed / shakeDuration
    local currentIntensity = shakeIntensity * (1 - progress)

    local offsetX = (math.random() - 0.5) * 2 * currentIntensity
    local offsetY = (math.random() - 0.5) * 2 * currentIntensity
    local offsetZ = (math.random() - 0.5) * 2 * currentIntensity * 0.5

    camera.CFrame = camera.CFrame * CFrame.new(offsetX, offsetY, offsetZ)
end

----------------------------------------------------------------------
-- CINEMATIC TRANSITIONS
----------------------------------------------------------------------

--- Pan camera to overview a position (used during briefing).
function CameraController:PanToOverview(targetPosition: Vector3, duration: number?)
    local dur = duration or 2

    camera.CameraType = Enum.CameraType.Scriptable

    local overviewCFrame = CFrame.lookAt(
        targetPosition + Vector3.new(0, 80, 60),
        targetPosition
    )

    local tween = TweenService:Create(camera, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
        CFrame = overviewCFrame,
    })
    tween:Play()
    tween.Completed:Wait()
end

--- Return camera to default player follow mode.
function CameraController:ReturnToPlayer()
    camera.CameraType = Enum.CameraType.Custom
    camera.CameraSubject = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------

function CameraController:Init()
    -- Apply camera shake each frame
    RunService.RenderStepped:Connect(updateShake)

    print("[CameraController] Initialized")
end

return CameraController
