--[[
    NetworkController.luau (Client)

    Client-side networking layer. Mirrors the server's NetworkManager.
    Provides clean API for sending events and listening to server events.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkController = {}
NetworkController.__index = NetworkController

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local remoteEvents: { [string]: RemoteEvent } = {}
local remoteFunctions: { [string]: RemoteFunction } = {}
local eventCallbacks: { [string]: { (any) -> () } } = {}

----------------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------------

--- Send an event to the server.
function NetworkController:FireServer(eventName: string, data: any)
    local remote = remoteEvents[eventName]
    if not remote then
        warn(`[NetworkController] Unknown event: {eventName}`)
        return
    end
    remote:FireServer(data)
end

--- Invoke a server function and wait for the response.
function NetworkController:InvokeServer(funcName: string, ...): any
    local remote = remoteFunctions[funcName]
    if not remote then
        warn(`[NetworkController] Unknown function: {funcName}`)
        return nil
    end
    return remote:InvokeServer(...)
end

--- Listen for a server event.
function NetworkController:OnServerEvent(eventName: string, callback: (any) -> ())
    if not eventCallbacks[eventName] then
        eventCallbacks[eventName] = {}
    end
    table.insert(eventCallbacks[eventName], callback)
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------

function NetworkController:Init(gameRemotes: Folder)
    -- Discover all remotes
    for _, child in gameRemotes:GetChildren() do
        if child:IsA("RemoteEvent") then
            remoteEvents[child.Name] = child

            child.OnClientEvent:Connect(function(data)
                local callbacks = eventCallbacks[child.Name]
                if callbacks then
                    for _, cb in callbacks do
                        task.spawn(cb, data)
                    end
                end
            end)
        elseif child:IsA("RemoteFunction") then
            remoteFunctions[child.Name] = child
        end
    end

    print(`[NetworkController] Initialized with {#gameRemotes:GetChildren()} remotes`)
end

return NetworkController
