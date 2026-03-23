--[[
    CameraManager.luau (Client)

    Dynamic camera system with mode switching for different gameplay phases.

    Modes:
      - Default: Standard Roblox third-person follow camera.
      - Cinematic: Smooth dolly for briefing/extraction sequences.
      - Overhead: Top-down tactical view for Commander role.
      - FirstPerson: Forced first-person for tight spaces (diver underwater).
      - Shake: Earthquake/explosion camera shake overlay.

    Camera shake uses a spring-damper model for natural feel.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local CameraManager = {}
CameraManager.__index = CameraManager

----------------------------------------------------------------------
-- SIGNALS
----------------------------------------------------------------------
CameraManager.ModeChanged = Signal.new()     -- (newMode: string)

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local camera: Camera = nil
local currentMode: string = "Default"
local shakeIntensity: number = 0
local shakeDecay: number = 5            -- how fast shake dies out
local shakeOffset: CFrame = CFrame.new()
local updateConnection: RBXScriptConnection? = nil

-- Cinematic path
local cinematicWaypoints: { CFrame } = {}
local cinematicProgress: number = 0
local cinematicSpeed: number = 0.5

-- Overhead mode
local overheadHeight: number = 80
local overheadTarget: Vector3 = Vector3.zero

----------------------------------------------------------------------
-- CAMERA SHAKE (Spring-Damper Model)
----------------------------------------------------------------------

local shakeVelocity = Vector3.zero
local shakePosition = Vector3.zero
local SHAKE_STIFFNESS = 200
local SHAKE_DAMPING = 10

local function updateShake(dt: number)
    if shakeIntensity <= 0.001 then
        shakeOffset = CFrame.new()
        shakePosition = Vector3.zero
        shakeVelocity = Vector3.zero
        return
    end

    -- Random impulse based on intensity
    local impulse = Vector3.new(
        (math.random() - 0.5) * 2,
        (math.random() - 0.5) * 2,
        (math.random() - 0.5) * 2
    ) * shakeIntensity

    -- Spring physics
    local springForce = -SHAKE_STIFFNESS * shakePosition
    local dampingForce = -SHAKE_DAMPING * shakeVelocity
    local acceleration = springForce + dampingForce + impulse * SHAKE_STIFFNESS

    shakeVelocity += acceleration * dt
    shakePosition += shakeVelocity * dt

    shakeOffset = CFrame.new(shakePosition * 0.1)

    -- Decay intensity
    shakeIntensity = math.max(0, shakeIntensity - shakeDecay * dt)
end

----------------------------------------------------------------------
-- MODE IMPLEMENTATIONS
----------------------------------------------------------------------

local function updateDefault(dt: number)
    updateShake(dt)
    -- Apply shake on top of default camera
    if shakeIntensity > 0.001 then
        camera.CFrame = camera.CFrame * shakeOffset
    end
end

local function updateCinematic(dt: number)
    if #cinematicWaypoints < 2 then return end

    cinematicProgress += cinematicSpeed * dt

    local totalWaypoints = #cinematicWaypoints
    local t = math.clamp(cinematicProgress, 0, totalWaypoints - 1)
    local index = math.floor(t) + 1
    local alpha = t - math.floor(t)

    if index >= totalWaypoints then
        camera.CFrame = cinematicWaypoints[totalWaypoints]
        return
    end

    -- Smooth interpolation between waypoints
    camera.CameraType = Enum.CameraType.Scriptable
    camera.CFrame = cinematicWaypoints[index]:Lerp(cinematicWaypoints[index + 1], alpha)
end

local function updateOverhead(dt: number)
    camera.CameraType = Enum.CameraType.Scriptable

    local character = Players.LocalPlayer.Character
    if character and character:FindFirstChild("HumanoidRootPart") then
        overheadTarget = character.HumanoidRootPart.Position
    end

    local targetCF = CFrame.new(
        overheadTarget + Vector3.new(0, overheadHeight, 0),
        overheadTarget
    )

    camera.CFrame = camera.CFrame:Lerp(targetCF, math.min(1, 5 * dt))
    updateShake(dt)
    if shakeIntensity > 0.001 then
        camera.CFrame = camera.CFrame * shakeOffset
    end
end

----------------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------------

--- Switch camera mode.
function CameraManager:SetMode(mode: string)
    local old = currentMode
    currentMode = mode

    if mode == "Default" then
        camera.CameraType = Enum.CameraType.Custom
    elseif mode == "Cinematic" then
        camera.CameraType = Enum.CameraType.Scriptable
        cinematicProgress = 0
    elseif mode == "Overhead" then
        camera.CameraType = Enum.CameraType.Scriptable
    elseif mode == "FirstPerson" then
        camera.CameraType = Enum.CameraType.Custom
        Players.LocalPlayer.CameraMinZoomDistance = 0.5
        Players.LocalPlayer.CameraMaxZoomDistance = 0.5
    end

    CameraManager.ModeChanged:Fire(mode)
end

--- Add camera shake. Intensity is additive.
function CameraManager:Shake(intensity: number, decay: number?)
    shakeIntensity += intensity
    if decay then
        shakeDecay = decay
    end
end

--- Set cinematic waypoints for a camera fly-through.
function CameraManager:SetCinematicPath(waypoints: { CFrame }, speed: number?)
    cinematicWaypoints = waypoints
    cinematicProgress = 0
    cinematicSpeed = speed or 0.5
end

--- Set overhead camera height.
function CameraManager:SetOverheadHeight(height: number)
    overheadHeight = height
end

--- Reset to default camera.
function CameraManager:Reset()
    self:SetMode("Default")
    shakeIntensity = 0
    Players.LocalPlayer.CameraMinZoomDistance = 6
    Players.LocalPlayer.CameraMaxZoomDistance = 30
end

function CameraManager:GetMode(): string
    return currentMode
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------

function CameraManager:Init()
    camera = workspace.CurrentCamera

    -- Main update loop
    updateConnection = RunService.RenderStepped:Connect(function(dt)
        if currentMode == "Default" then
            updateDefault(dt)
        elseif currentMode == "Cinematic" then
            updateCinematic(dt)
        elseif currentMode == "Overhead" then
            updateOverhead(dt)
        end
    end)

    -- Listen for environment updates (earthquake shake)
    local remotes = ReplicatedStorage:WaitForChild("GameRemotes", 10)
    if remotes then
        local envEvent = remotes:FindFirstChild("EnvironmentUpdate")
        if envEvent then
            envEvent.OnClientEvent:Connect(function(data)
                if data.shakeMagnitude and data.shakeMagnitude > 0 then
                    self:Shake(data.shakeMagnitude, 3)
                end
            end)
        end

        local effectEvent = remotes:FindFirstChild("EffectTrigger")
        if effectEvent then
            effectEvent.OnClientEvent:Connect(function(data)
                if data.effectType == "Explosion" then
                    self:Shake(2, 4)
                end
            end)
        end
    end

    print("[CameraManager] Initialized")
end

function CameraManager:Destroy()
    if updateConnection then
        updateConnection:Disconnect()
    end
end

return CameraManager
