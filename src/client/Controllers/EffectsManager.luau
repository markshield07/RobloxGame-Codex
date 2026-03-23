--[[
    EffectsManager.luau (Client)

    Handles all visual effects: particles, screen effects, sound cues,
    weather, and hazard zone visualization.

    Architecture:
      - Effect pool: pre-instantiated particle emitters recycled to avoid GC spikes.
      - Performance budget: respects Constants.MAX_ACTIVE_PARTICLES.
      - Reduced effects mode: players on low-end devices can opt into simplified VFX.
      - CollectionService tags drive hazard zone effects automatically.

    Effect types:
      - Fire, Smoke, Sparks, Water splash, Toxic gas, Electric arcs
      - Screen overlays: damage vignette, underwater tint, low-visibility fog
      - K9 ping indicator (world-space billboard)
      - Rescue success celebration
]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local EffectsManager = {}
EffectsManager.__index = EffectsManager

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local activeEffects: { [string]: Instance } = {}
local particleCount: number = 0
local reducedEffects: boolean = false
local updateConnection: RBXScriptConnection? = nil

-- Screen effects
local damageVignette: Frame? = nil
local underwaterTint: ColorCorrectionEffect? = nil
local fogEffect: Atmosphere? = nil

----------------------------------------------------------------------
-- PARTICLE EFFECT TEMPLATES
----------------------------------------------------------------------

local function createFireEmitter(): ParticleEmitter
    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "FireEffect"
    emitter.Texture = "rbxassetid://0" -- placeholder fire texture
    emitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 50)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 100, 20)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 20, 0)),
    })
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 2),
        NumberSequenceKeypoint.new(0.5, 4),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Lifetime = NumberRange.new(0.5, 1.5)
    emitter.Rate = reducedEffects and 10 or 30
    emitter.Speed = NumberRange.new(3, 8)
    emitter.SpreadAngle = Vector2.new(20, 20)
    emitter.Acceleration = Vector3.new(0, 5, 0)
    emitter.LightEmission = 1
    emitter.Enabled = true
    return emitter
end

local function createSmokeEmitter(): ParticleEmitter
    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "SmokeEffect"
    emitter.Color = ColorSequence.new(Color3.fromRGB(80, 80, 80))
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 8),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Lifetime = NumberRange.new(2, 4)
    emitter.Rate = reducedEffects and 5 or 15
    emitter.Speed = NumberRange.new(1, 3)
    emitter.Acceleration = Vector3.new(0, 2, 0)
    emitter.Enabled = true
    return emitter
end

local function createToxicEmitter(): ParticleEmitter
    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "ToxicEffect"
    emitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 255, 50)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 100, 20)),
    })
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 3),
        NumberSequenceKeypoint.new(1, 10),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Lifetime = NumberRange.new(3, 6)
    emitter.Rate = reducedEffects and 3 or 10
    emitter.Speed = NumberRange.new(0.5, 2)
    emitter.Enabled = true
    return emitter
end

local function createElectricEmitter(): ParticleEmitter
    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "ElectricEffect"
    emitter.Color = ColorSequence.new(Color3.fromRGB(100, 150, 255))
    emitter.Size = NumberSequence.new(0.5, 2)
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.1, 0.8),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Lifetime = NumberRange.new(0.1, 0.3)
    emitter.Rate = reducedEffects and 5 or 20
    emitter.Speed = NumberRange.new(5, 15)
    emitter.SpreadAngle = Vector2.new(180, 180)
    emitter.LightEmission = 1
    emitter.Enabled = true
    return emitter
end

local HAZARD_EMITTER_FACTORIES = {
    Fire = createFireEmitter,
    Toxic = createToxicEmitter,
    Structural = createSmokeEmitter,
    Water = nil, -- water uses mesh deformation, not particles
    Electric = createElectricEmitter,
}

----------------------------------------------------------------------
-- HAZARD ZONE EFFECTS
----------------------------------------------------------------------

local function attachHazardEffects(part: BasePart)
    local hazardType = part:GetAttribute("HazardType")
    if not hazardType then return end

    local factory = HAZARD_EMITTER_FACTORIES[hazardType]
    if not factory then return end

    if particleCount >= Constants.MAX_ACTIVE_PARTICLES then return end

    local emitter = factory()
    emitter.Parent = part
    particleCount += 1
    activeEffects[part:GetFullName()] = emitter

    -- Fire hazards also get a PointLight
    if hazardType == "Fire" then
        local light = Instance.new("PointLight")
        light.Name = "FireLight"
        light.Color = Color3.fromRGB(255, 150, 50)
        light.Brightness = 2
        light.Range = 20
        light.Parent = part
    end
end

local function detachHazardEffects(part: BasePart)
    local key = part:GetFullName()
    local effect = activeEffects[key]
    if effect then
        effect:Destroy()
        activeEffects[key] = nil
        particleCount -= 1
    end
    -- Also remove point lights
    local light = part:FindFirstChild("FireLight")
    if light then light:Destroy() end
end

----------------------------------------------------------------------
-- SCREEN EFFECTS
----------------------------------------------------------------------

--- Show damage vignette (red flash on screen edges).
function EffectsManager:ShowDamageVignette(intensity: number)
    if not damageVignette then return end
    damageVignette.Visible = true
    damageVignette.BackgroundTransparency = 1 - (intensity * 0.4)

    -- Fade out
    local tween = TweenService:Create(damageVignette, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
        BackgroundTransparency = 1,
    })
    tween:Play()
    tween.Completed:Connect(function()
        damageVignette.Visible = false
    end)
end

--- Apply underwater tint.
function EffectsManager:SetUnderwaterMode(enabled: boolean)
    if not underwaterTint then
        underwaterTint = Instance.new("ColorCorrectionEffect")
        underwaterTint.Name = "UnderwaterTint"
        underwaterTint.Parent = Lighting
    end

    if enabled then
        underwaterTint.TintColor = Color3.fromRGB(80, 120, 180)
        underwaterTint.Brightness = -0.1
        underwaterTint.Contrast = 0.1
        underwaterTint.Saturation = -0.2
        underwaterTint.Enabled = true
    else
        underwaterTint.Enabled = false
    end
end

--- Set visibility fog based on disaster environment.
function EffectsManager:SetVisibility(level: number)
    if not fogEffect then
        fogEffect = Lighting:FindFirstChildOfClass("Atmosphere")
        if not fogEffect then
            fogEffect = Instance.new("Atmosphere")
            fogEffect.Parent = Lighting
        end
    end

    -- level 0 = zero visibility, 1 = clear
    local density = (1 - level) * 0.8
    fogEffect.Density = density
    fogEffect.Color = Color3.fromRGB(150, 150, 150)
    fogEffect.Decay = Color3.fromRGB(100, 100, 100)
end

--- Show K9 ping indicator at a world position.
function EffectsManager:ShowK9Ping(position: Vector3)
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 60, 0, 60)
    billboard.StudsOffset = Vector3.new(0, 5, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = nil

    local marker = Instance.new("Part")
    marker.Name = "K9PingMarker"
    marker.Size = Vector3.one
    marker.Position = position
    marker.Anchored = true
    marker.Transparency = 1
    marker.CanCollide = false
    marker.Parent = workspace

    billboard.Adornee = marker

    local icon = Instance.new("ImageLabel")
    icon.Size = UDim2.new(1, 0, 1, 0)
    icon.BackgroundTransparency = 1
    icon.ImageColor3 = Color3.fromRGB(255, 200, 50)
    icon.Image = "rbxassetid://0" -- placeholder ping icon
    icon.Parent = billboard

    local ring = Instance.new("Frame")
    ring.Size = UDim2.new(1, 0, 1, 0)
    ring.BackgroundTransparency = 1
    ring.Parent = billboard

    billboard.Parent = marker

    -- Animate and auto-remove after 5 seconds
    task.delay(5, function()
        marker:Destroy()
    end)
end

--- Celebration effect for successful rescue.
function EffectsManager:PlayRescueSuccess(position: Vector3)
    -- Spawn a brief particle burst
    local part = Instance.new("Part")
    part.Size = Vector3.one
    part.Position = position + Vector3.new(0, 3, 0)
    part.Anchored = true
    part.Transparency = 1
    part.CanCollide = false
    part.Parent = workspace

    local emitter = Instance.new("ParticleEmitter")
    emitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(46, 204, 113)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(241, 196, 15)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(52, 152, 219)),
    })
    emitter.Size = NumberSequence.new(1, 0)
    emitter.Lifetime = NumberRange.new(0.5, 1)
    emitter.Speed = NumberRange.new(10, 20)
    emitter.SpreadAngle = Vector2.new(180, 180)
    emitter.Rate = 0
    emitter.Parent = part

    emitter:Emit(30)

    task.delay(2, function()
        part:Destroy()
    end)
end

----------------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------------

function EffectsManager:SetReducedEffects(enabled: boolean)
    reducedEffects = enabled
    -- Re-create hazard effects with new settings
    for _, part in CollectionService:GetTagged("HazardZone") do
        detachHazardEffects(part)
        if part.Transparency < 1 then -- still active
            attachHazardEffects(part)
        end
    end
end

function EffectsManager:GetActiveParticleCount(): number
    return particleCount
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------

function EffectsManager:Init()
    -- Create screen overlay for damage vignette
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "EffectsOverlay"
    screenGui.IgnoreGuiInset = true
    screenGui.DisplayOrder = 100
    screenGui.Parent = playerGui

    damageVignette = Instance.new("Frame")
    damageVignette.Name = "DamageVignette"
    damageVignette.Size = UDim2.new(1, 0, 1, 0)
    damageVignette.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    damageVignette.BackgroundTransparency = 1
    damageVignette.Visible = false
    damageVignette.Parent = screenGui

    -- Auto-attach effects to hazard zones
    CollectionService:GetInstanceAddedSignal("HazardZone"):Connect(function(instance)
        if instance:IsA("BasePart") then
            attachHazardEffects(instance)
        end
    end)

    CollectionService:GetInstanceRemovedSignal("HazardZone"):Connect(function(instance)
        if instance:IsA("BasePart") then
            detachHazardEffects(instance)
        end
    end)

    -- Process existing hazard zones
    for _, part in CollectionService:GetTagged("HazardZone") do
        if part:IsA("BasePart") then
            attachHazardEffects(part)
        end
    end

    -- Listen for server effect triggers
    local remotes = ReplicatedStorage:WaitForChild("GameRemotes", 10)
    if remotes then
        local effectEvent = remotes:FindFirstChild("EffectTrigger")
        if effectEvent then
            effectEvent.OnClientEvent:Connect(function(data)
                if data.effectType == "K9Ping" then
                    self:ShowK9Ping(data.position)
                elseif data.effectType == "RescueSuccess" then
                    self:PlayRescueSuccess(data.position)
                elseif data.effectType == "DamageHit" then
                    self:ShowDamageVignette(data.intensity or 0.5)
                end
            end)
        end

        local envEvent = remotes:FindFirstChild("EnvironmentUpdate")
        if envEvent then
            envEvent.OnClientEvent:Connect(function(data)
                if data.visibility then
                    self:SetVisibility(data.visibility)
                end
            end)
        end
    end

    print("[EffectsManager] Initialized")
end

return EffectsManager
