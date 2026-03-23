--[[
    init.client.luau
    Client bootstrap script. Initializes all client controllers.
    This is the entry point for the client (placed in StarterPlayerScripts).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer

----------------------------------------------------------------------
-- Wait for game to load
----------------------------------------------------------------------
if not game:IsLoaded() then
    game.Loaded:Wait()
end

----------------------------------------------------------------------
-- Wait for GameRemotes folder (created by NetworkManager on server)
----------------------------------------------------------------------
local gameRemotes = ReplicatedStorage:WaitForChild("GameRemotes", 30)
if not gameRemotes then
    warn("[Client] GameRemotes not found! Server may not have initialized.")
    return
end

----------------------------------------------------------------------
-- Load controllers
----------------------------------------------------------------------
local UIManager = require(script.Controllers.UIManager)
local InputManager = require(script.Controllers.InputManager)
local CameraManager = require(script.Controllers.CameraManager)
local EffectsManager = require(script.Controllers.EffectsManager)

----------------------------------------------------------------------
-- Initialize in dependency order
----------------------------------------------------------------------
print("=== Rescue Squad Simulator: Client Boot ===")

-- Layer 0: Core systems (no dependencies on other controllers)
CameraManager:Init()
EffectsManager:Init()

-- Layer 1: UI and Input (may reference effects/camera)
UIManager:Init()
InputManager:Init()

----------------------------------------------------------------------
-- Request initial state from server
----------------------------------------------------------------------
local getPlayerData = gameRemotes:FindFirstChild("GetPlayerData")
if getPlayerData then
    local data = getPlayerData:InvokeServer()
    if data then
        UIManager:UpdateCurrency(data.coins or 0, data.rescueTokens or 0)
        print(`[Client] Data loaded: Level {data.globalLevel}, Prestige {data.prestigeLevel}`)
    end
end

----------------------------------------------------------------------
-- Cross-controller wiring
----------------------------------------------------------------------

-- Camera mode follows game phase
UIManager.ScreenChanged:Connect(function(screen)
    if screen == "Lobby" then
        CameraManager:Reset()
    elseif screen == "Briefing" then
        CameraManager:SetMode("Cinematic")
    elseif screen == "HUD" then
        CameraManager:SetMode("Default")
    elseif screen == "Scoreboard" then
        CameraManager:SetMode("Default")
    end
end)

-- Ability activation triggers VFX
InputManager.AbilityActivated:Connect(function(abilityId)
    if abilityId == "K9Search" or abilityId == "SearchCommand" then
        -- K9 search pulse VFX would go here
    end
end)

-- Interaction feedback
InputManager.InteractionRequested:Connect(function(targetId, actionType)
    if actionType == "RescueCivilian" then
        -- Play rescue start sound
    elseif actionType == "NeutralizeHazard" then
        -- Play hazard interaction sound
    end
end)

print("=== Rescue Squad Simulator: Client Ready ===")
