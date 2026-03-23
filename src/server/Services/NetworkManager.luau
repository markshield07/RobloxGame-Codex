--[[
    NetworkManager.luau (Server)

    Centralized networking layer. Creates all RemoteEvents and RemoteFunctions
    from the Constants catalog. Other modules never touch Remotes directly.

    Architecture:
      - All remotes live under ReplicatedStorage.GameRemotes folder.
      - Server modules call NetworkManager:FireClient / FireAllClients.
      - Client requests validated with rate limiting before forwarding.
      - Anti-cheat: per-player burst rate limiters on all incoming events.

    Bandwidth optimization:
      - Non-critical updates (score, objectives) throttled to 10 Hz.
      - Critical updates (health, position) at 30 Hz.
      - Payloads kept minimal (IDs instead of full objects where possible).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Types = require(ReplicatedStorage.Shared.Modules.Types)
local Constants = require(ReplicatedStorage.Shared.Modules.Constants)

local NetworkManager = {}
NetworkManager.__index = NetworkManager

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local remoteEvents: { [string]: RemoteEvent } = {}
local remoteFunctions: { [string]: RemoteFunction } = {}
local networkFolder: Folder = nil

-- Client-to-server event handlers: eventName -> callback(player, ...data)
local eventHandlers: { [string]: (Player, ...any) -> () } = {}
-- Remote function handlers: funcName -> callback(player, ...data) -> any
local functionHandlers: { [string]: (Player, ...any) -> any } = {}

-- Rate limiting state
local RATE_LIMIT_BURST = 10 -- max fires per player per event per second
local rateLimitCounters: { [string]: { [number]: { count: number, resetTime: number } } } = {}

local function checkRateLimit(eventName: string, player: Player): boolean
    local userId = player.UserId
    if not rateLimitCounters[eventName] then
        rateLimitCounters[eventName] = {}
    end
    local playerLimits = rateLimitCounters[eventName]
    if not playerLimits[userId] then
        playerLimits[userId] = { count = 0, resetTime = os.clock() + 1 }
    end
    local limiter = playerLimits[userId]
    local now = os.clock()
    if now > limiter.resetTime then
        limiter.count = 0
        limiter.resetTime = now + 1
    end
    limiter.count += 1
    if limiter.count > RATE_LIMIT_BURST then
        warn(`[NetworkManager] Rate limit exceeded: {player.Name} on {eventName}`)
        return false
    end
    return true
end

----------------------------------------------------------------------
-- VALIDATION UTILITIES
----------------------------------------------------------------------

function NetworkManager.ValidateNumber(value: any, min: number, max: number): number?
    if type(value) ~= "number" then return nil end
    if value ~= value then return nil end -- NaN
    if value < min or value > max then return nil end
    return value
end

function NetworkManager.ValidateString(value: any, maxLength: number): string?
    if type(value) ~= "string" then return nil end
    if #value > maxLength then return nil end
    return value
end

function NetworkManager.ValidateEnum(value: any, allowed: { string }): string?
    if type(value) ~= "string" then return nil end
    if not table.find(allowed, value) then return nil end
    return value
end

----------------------------------------------------------------------
-- SETUP
----------------------------------------------------------------------

local function createRemotes()
    networkFolder = Instance.new("Folder")
    networkFolder.Name = "GameRemotes"
    networkFolder.Parent = ReplicatedStorage

    -- Create RemoteEvents
    for _, eventName in Constants.REMOTE_EVENTS do
        local remote = Instance.new("RemoteEvent")
        remote.Name = eventName
        remote.Parent = networkFolder
        remoteEvents[eventName] = remote

        -- Listen for client-to-server events with rate limiting
        remote.OnServerEvent:Connect(function(player: Player, ...)
            if not checkRateLimit(eventName, player) then return end
            local handler = eventHandlers[eventName]
            if handler then
                handler(player, ...)
            end
        end)
    end

    -- Create RemoteFunctions
    for _, funcName in Constants.REMOTE_FUNCTIONS do
        local remote = Instance.new("RemoteFunction")
        remote.Name = funcName
        remote.Parent = networkFolder
        remoteFunctions[funcName] = remote

        -- Listen for client invocations with rate limiting
        remote.OnServerInvoke = function(player: Player, ...)
            if not checkRateLimit(funcName, player) then
                return nil, "Rate limited"
            end
            local handler = functionHandlers[funcName]
            if handler then
                return handler(player, ...)
            end
            return nil
        end
    end
end

----------------------------------------------------------------------
-- PUBLIC API: Server -> Client
----------------------------------------------------------------------

--- Fire an event to a specific client.
function NetworkManager:FireClient(player: Player, eventName: string, data: any)
    local remote = remoteEvents[eventName]
    if not remote then
        warn(`[NetworkManager] Unknown event: {eventName}`)
        return
    end
    remote:FireClient(player, data)
end

--- Fire an event to all clients.
function NetworkManager:FireAllClients(eventName: string, data: any)
    local remote = remoteEvents[eventName]
    if not remote then
        warn(`[NetworkManager] Unknown event: {eventName}`)
        return
    end
    remote:FireAllClients(data)
end

--- Fire an event to all members of a squad.
function NetworkManager:FireAllClientsInSquad(squad: Types.Squad, eventName: string, data: any)
    local remote = remoteEvents[eventName]
    if not remote then
        warn(`[NetworkManager] Unknown event: {eventName}`)
        return
    end

    for _, member in squad.members do
        local player = Players:GetPlayerByUserId(member.playerId)
        if player then
            remote:FireClient(player, data)
        end
    end
end

----------------------------------------------------------------------
-- PUBLIC API: Client -> Server Handler Registration
----------------------------------------------------------------------

--- Register a handler for a client-to-server event.
function NetworkManager:OnClientEvent(eventName: string, handler: (Player, ...any) -> ())
    if not remoteEvents[eventName] then
        warn(`[NetworkManager] Cannot register handler for unknown event: {eventName}`)
        return
    end
    eventHandlers[eventName] = handler
end

--- Register a handler for a client-invoked function.
function NetworkManager:OnClientInvoke(funcName: string, handler: (Player, ...any) -> any)
    if not remoteFunctions[funcName] then
        warn(`[NetworkManager] Cannot register handler for unknown function: {funcName}`)
        return
    end
    functionHandlers[funcName] = handler
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------

function NetworkManager:Init()
    createRemotes()

    -- Clean up rate limit state when players leave
    Players.PlayerRemoving:Connect(function(player)
        local userId = player.UserId
        for _, counters in rateLimitCounters do
            counters[userId] = nil
        end
    end)

    print(`[NetworkManager] Initialized with {#Constants.REMOTE_EVENTS} events and {#Constants.REMOTE_FUNCTIONS} functions`)
end

return NetworkManager
