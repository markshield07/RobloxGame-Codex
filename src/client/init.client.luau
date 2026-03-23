--[[
    init.client.luau
    Client bootstrap script. Initializes all client controllers.
    This is the entry point for the client (placed in StarterPlayerScripts).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

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
local Controllers = script.Controllers
local NetworkController = require(Controllers.NetworkController)
local HUDController = require(Controllers.HUDController)
local InteractionController = require(Controllers.InteractionController)
local CameraController = require(Controllers.CameraController)

----------------------------------------------------------------------
-- Initialize in dependency order
----------------------------------------------------------------------
print("=== Rescue Squad Simulator Client Starting ===")

NetworkController:Init(gameRemotes)
HUDController:Init(NetworkController)
InteractionController:Init(NetworkController)
CameraController:Init()

print("=== Rescue Squad Simulator Client Ready ===")
