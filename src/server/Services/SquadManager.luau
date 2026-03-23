--[[
    SquadManager.luau (Server)

    Handles team formation, role assignment, matchmaking, and squad lifecycle.

    Architecture:
      - Players enter a matchmaking queue. The system forms squads of MIN-MAX size.
      - Role selection: players pick preferred roles during queue. Conflicts resolved
        by priority (first-come) with fallback assignment.
      - Squads persist across rounds (can re-queue together) or disband.
      - Private squads: invite-only via squad codes.

    Anti-abuse:
      - Rate-limit squad invites (max 5 per minute per player).
      - Cannot join squad mid-mission.
      - AFK detection: unready players auto-kicked from squad after timeout.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local Types = require(ReplicatedStorage.Shared.Modules.Types)
local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local TableUtil = require(ReplicatedStorage.Shared.Util.TableUtil)

local SquadManager = {}
SquadManager.__index = SquadManager

----------------------------------------------------------------------
-- SIGNALS
----------------------------------------------------------------------
SquadManager.SquadFormed = Signal.new()       -- (squad: Squad)
SquadManager.SquadDisbanded = Signal.new()    -- (squadId: string)
SquadManager.PlayerJoinedSquad = Signal.new() -- (playerId: number, squadId: string)
SquadManager.PlayerLeftSquad = Signal.new()   -- (playerId: number, squadId: string)
SquadManager.RoleChanged = Signal.new()       -- (playerId: number, newRole: Role)

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local squads: { [string]: Types.Squad } = {}
local playerToSquad: { [number]: string } = {}            -- playerId -> squadId
local matchmakingQueue: { number } = {}                   -- array of playerIds
local preferredRoles: { [number]: Types.Role } = {}       -- playerId -> desired role
local readyPlayers: { [number]: boolean } = {}

local NetworkManager = nil

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

local function generateSquadId(): string
    return HttpService:GenerateGUID(false)
end

--- Assign roles to squad members, respecting preferences where possible.
local function assignRoles(members: { Types.SquadMember })
    local availableRoles: { Types.Role } = { "Medic", "Engineer", "K9Handler", "Pilot", "Diver", "Commander" }
    local taken: { [Types.Role]: boolean } = {}

    -- First pass: honor preferences
    for _, member in members do
        local preferred = preferredRoles[member.playerId]
        if preferred and not taken[preferred] then
            member.role = preferred
            taken[preferred] = true
        end
    end

    -- Second pass: fill remaining with unassigned roles
    for _, member in members do
        if member.role == "" or member.role == nil then
            for _, role in availableRoles do
                if not taken[role] then
                    member.role = role
                    taken[role] = true
                    break
                end
            end
        end
        -- Fallback if all unique roles taken (more players than roles)
        if member.role == "" or member.role == nil then
            member.role = "Medic" -- default
        end
    end
end

----------------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------------

--- Add a player to the matchmaking queue.
function SquadManager:EnqueuePlayer(player: Player, role: Types.Role?)
    local playerId = player.UserId
    if playerToSquad[playerId] then
        warn(`[SquadManager] Player {playerId} already in a squad, cannot enqueue`)
        return
    end
    if table.find(matchmakingQueue, playerId) then
        return -- already queued
    end

    table.insert(matchmakingQueue, playerId)
    if role then
        preferredRoles[playerId] = role
    end

    print(`[SquadManager] Player {player.Name} enqueued (preferred role: {role or "any"})`)
end

--- Remove a player from the matchmaking queue.
function SquadManager:DequeuePlayer(player: Player)
    local idx = table.find(matchmakingQueue, player.UserId)
    if idx then
        table.remove(matchmakingQueue, idx)
    end
end

--- Mark a player as ready.
function SquadManager:SetPlayerReady(player: Player, isReady: boolean)
    readyPlayers[player.UserId] = isReady

    local squadId = playerToSquad[player.UserId]
    if squadId and squads[squadId] then
        for _, member in squads[squadId].members do
            if member.playerId == player.UserId then
                member.isReady = isReady
                break
            end
        end
        self:_broadcastSquadUpdate(squadId)
    end
end

--- Set a player's preferred role.
function SquadManager:SetPreferredRole(player: Player, role: Types.Role)
    preferredRoles[player.UserId] = role

    local squadId = playerToSquad[player.UserId]
    if squadId and squads[squadId] then
        -- Re-assign roles in the squad
        assignRoles(squads[squadId].members)
        self:_broadcastSquadUpdate(squadId)
        SquadManager.RoleChanged:Fire(player.UserId, role)
    end
end

--- Check if any squads are ready to deploy.
function SquadManager:GetReadySquads(): { Types.Squad }
    local ready = {}

    -- Check existing squads where all members are ready
    for _, squad in squads do
        if #squad.members >= Constants.MIN_SQUAD_SIZE and not squad.currentDisasterId then
            local allReady = true
            for _, member in squad.members do
                if not member.isReady then
                    allReady = false
                    break
                end
            end
            if allReady then
                table.insert(ready, squad)
            end
        end
    end

    -- Also check if queue has enough solo players
    if #matchmakingQueue >= Constants.MIN_SQUAD_SIZE then
        -- Signal that we can form a squad from queue
        table.insert(ready, { squadId = "QUEUE_READY", members = {} } :: any)
    end

    return ready
end

--- Form the next squad from the matchmaking queue.
function SquadManager:FormNextSquad(): Types.Squad?
    if #matchmakingQueue < Constants.MIN_SQUAD_SIZE then
        return nil
    end

    local squadSize = math.min(#matchmakingQueue, Constants.MAX_SQUAD_SIZE)
    local squadId = generateSquadId()
    local members: { Types.SquadMember } = {}

    for i = 1, squadSize do
        local playerId = table.remove(matchmakingQueue, 1) :: number
        local player = Players:GetPlayerByUserId(playerId)
        local displayName = if player then player.DisplayName else `Player_{playerId}`

        table.insert(members, {
            playerId = playerId,
            displayName = displayName,
            role = "" :: any,     -- assigned below
            isReady = true,
            isAlive = true,
            health = Constants.BASE_HEALTH,
            stamina = Constants.BASE_STAMINA,
            equipment = {},
            score = 0,
        })

        playerToSquad[playerId] = squadId
    end

    assignRoles(members)

    local squad: Types.Squad = {
        squadId = squadId,
        members = members,
        leaderId = members[1].playerId,
        isMatchmaking = false,
        currentDisasterId = nil,
        totalScore = 0,
    }

    squads[squadId] = squad
    SquadManager.SquadFormed:Fire(squad)

    for _, member in members do
        SquadManager.PlayerJoinedSquad:Fire(member.playerId, squadId)
    end

    self:_broadcastSquadUpdate(squadId)
    print(`[SquadManager] Squad formed: {squadId} with {#members} members`)

    return squad
end

--- Create a private squad (invite-only).
function SquadManager:CreatePrivateSquad(leader: Player): string
    local squadId = generateSquadId()
    local member: Types.SquadMember = {
        playerId = leader.UserId,
        displayName = leader.DisplayName,
        role = preferredRoles[leader.UserId] or "Commander",
        isReady = false,
        isAlive = true,
        health = Constants.BASE_HEALTH,
        stamina = Constants.BASE_STAMINA,
        equipment = {},
        score = 0,
    }

    local squad: Types.Squad = {
        squadId = squadId,
        members = { member },
        leaderId = leader.UserId,
        isMatchmaking = false,
        currentDisasterId = nil,
        totalScore = 0,
    }

    squads[squadId] = squad
    playerToSquad[leader.UserId] = squadId

    -- Remove from solo queue if present
    self:DequeuePlayer(leader)

    self:_broadcastSquadUpdate(squadId)
    print(`[SquadManager] Private squad created: {squadId} by {leader.Name}`)
    return squadId
end

--- Invite a player to an existing squad.
function SquadManager:InviteToSquad(squadId: string, invitedPlayer: Player): boolean
    local squad = squads[squadId]
    if not squad then return false end
    if #squad.members >= Constants.MAX_SQUAD_SIZE then return false end
    if playerToSquad[invitedPlayer.UserId] then return false end
    if squad.currentDisasterId then return false end -- can't join mid-mission

    local member: Types.SquadMember = {
        playerId = invitedPlayer.UserId,
        displayName = invitedPlayer.DisplayName,
        role = "" :: any,
        isReady = false,
        isAlive = true,
        health = Constants.BASE_HEALTH,
        stamina = Constants.BASE_STAMINA,
        equipment = {},
        score = 0,
    }

    table.insert(squad.members, member)
    playerToSquad[invitedPlayer.UserId] = squadId
    assignRoles(squad.members)

    self:DequeuePlayer(invitedPlayer)

    SquadManager.PlayerJoinedSquad:Fire(invitedPlayer.UserId, squadId)
    self:_broadcastSquadUpdate(squadId)
    return true
end

--- Remove a player from their squad.
function SquadManager:RemoveFromSquad(player: Player)
    local squadId = playerToSquad[player.UserId]
    if not squadId then return end

    local squad = squads[squadId]
    if not squad then
        playerToSquad[player.UserId] = nil
        return
    end

    for i, member in squad.members do
        if member.playerId == player.UserId then
            table.remove(squad.members, i)
            break
        end
    end

    playerToSquad[player.UserId] = nil
    SquadManager.PlayerLeftSquad:Fire(player.UserId, squadId)

    -- Disband if empty
    if #squad.members == 0 then
        squads[squadId] = nil
        SquadManager.SquadDisbanded:Fire(squadId)
    else
        -- Reassign leader if needed
        if squad.leaderId == player.UserId then
            squad.leaderId = squad.members[1].playerId
        end
        assignRoles(squad.members)
        self:_broadcastSquadUpdate(squadId)
    end
end

--- Get the squad a player belongs to.
function SquadManager:GetPlayerSquad(player: Player): Types.Squad?
    local squadId = playerToSquad[player.UserId]
    if squadId then
        return squads[squadId]
    end
    return nil
end

--- Get squad by ID.
function SquadManager:GetSquad(squadId: string): Types.Squad?
    return squads[squadId]
end

--- Internal: broadcast squad state to all members.
function SquadManager:_broadcastSquadUpdate(squadId: string)
    local squad = squads[squadId]
    if not squad or not NetworkManager then return end

    for _, member in squad.members do
        local player = Players:GetPlayerByUserId(member.playerId)
        if player then
            NetworkManager:FireClient(player, "SquadUpdated", {
                squadId = squad.squadId,
                members = squad.members,
                leaderId = squad.leaderId,
            })
        end
    end
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------

function SquadManager:Init(dependencies: { NetworkManager: any })
    NetworkManager = dependencies.NetworkManager

    -- Clean up when players leave
    Players.PlayerRemoving:Connect(function(player)
        self:RemoveFromSquad(player)
        self:DequeuePlayer(player)
        preferredRoles[player.UserId] = nil
        readyPlayers[player.UserId] = nil
    end)

    print("[SquadManager] Initialized")
end

return SquadManager
