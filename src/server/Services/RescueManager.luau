--[[
    RescueManager.luau (Server)

    Manages active rescue mission logic: objective tracking, scoring,
    civilian state, interaction processing, and mission evaluation.

    Architecture:
      - One active session per squad. Stateless between sessions.
      - Objective progress is authoritative server-side.
      - Client sends InteractionRequest; server validates and applies.
      - Scoring uses a multiplicative system:
          base_score * speed_bonus * no_casualty_bonus * role_bonus

    Interaction model:
      Client presses interact -> sends InteractionRequest(targetId, actionType)
      Server validates: distance check, cooldown, role permission, target state
      Server applies: updates objective, heals civilian, etc.
      Server fires ObjectiveUpdated to all squad members.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Types = require(ReplicatedStorage.Shared.Modules.Types)
local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local RescueManager = {}
RescueManager.__index = RescueManager

----------------------------------------------------------------------
-- SIGNALS
----------------------------------------------------------------------
RescueManager.ObjectiveCompleted = Signal.new()   -- (sessionId, objectiveId)
RescueManager.CivilianRescued = Signal.new()      -- (sessionId, civilianId, rescuerId)
RescueManager.CivilianLost = Signal.new()         -- (sessionId, civilianId)
RescueManager.MissionComplete = Signal.new()      -- (sessionId, success)

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local activeSessions: { [string]: Types.RescueSession } = {}
local interactionCooldowns: { [string]: number } = {}  -- "playerId_action" -> os.clock()

local NetworkManager = nil
local DisasterManager = nil

----------------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------------
local INTERACTION_RANGE = 10          -- studs
local INTERACTION_COOLDOWN = 1.5      -- seconds
local CIVILIAN_BLEEDOUT_RATE = 2      -- health per second if not stabilized

----------------------------------------------------------------------
-- PRIVATE
----------------------------------------------------------------------

local function getPlayerPosition(playerId: number): Vector3?
    local player = Players:GetPlayerByUserId(playerId)
    if player and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        return player.Character.HumanoidRootPart.Position
    end
    return nil
end

local function isOnCooldown(playerId: number, action: string): boolean
    local key = `{playerId}_{action}`
    local lastUse = interactionCooldowns[key]
    if lastUse and (os.clock() - lastUse) < INTERACTION_COOLDOWN then
        return true
    end
    return false
end

local function setCooldown(playerId: number, action: string)
    local key = `{playerId}_{action}`
    interactionCooldowns[key] = os.clock()
end

local function getMemberFromSession(session: Types.RescueSession, playerId: number): Types.SquadMember?
    for _, member in session.squad.members do
        if member.playerId == playerId then
            return member
        end
    end
    return nil
end

local function broadcastToSquad(session: Types.RescueSession, eventName: string, data: any)
    if not NetworkManager then return end
    for _, member in session.squad.members do
        local player = Players:GetPlayerByUserId(member.playerId)
        if player then
            NetworkManager:FireClient(player, eventName, data)
        end
    end
end

----------------------------------------------------------------------
-- INTERACTION HANDLERS
----------------------------------------------------------------------

local interactionHandlers: { [string]: (session: Types.RescueSession, member: Types.SquadMember, targetId: string) -> boolean } = {}

--- Rescue a civilian.
interactionHandlers.RescueCivilian = function(session, member, targetId)
    -- Find civilian in the disaster map
    local folder = workspace:FindFirstChild(`DisasterMap_{session.sessionId}`)
    if not folder then return false end

    local civilian = nil
    for _, child in folder:GetChildren() do
        if child:GetAttribute("CivilianId") == targetId then
            civilian = child
            break
        end
    end

    if not civilian then return false end
    if civilian:GetAttribute("IsRescued") then return false end

    -- Distance check
    local playerPos = getPlayerPosition(member.playerId)
    if not playerPos then return false end
    local civPos = civilian.PrimaryPart and civilian.PrimaryPart.Position
    if not civPos then return false end
    if (playerPos - civPos).Magnitude > INTERACTION_RANGE then return false end

    -- Execute rescue
    civilian:SetAttribute("IsRescued", true)
    civilian:SetAttribute("RescuedBy", member.playerId)
    session.civiliansRescued += 1
    member.score += Constants.XP_REWARDS.CivilianRescued

    -- Update rescue objectives
    for _, obj in session.disasterConfig.objectives do
        if obj.objectiveType == "Rescue" and obj.status ~= "Completed" then
            obj.currentCount += 1
            if obj.currentCount >= obj.targetCount then
                obj.status = "Completed"
                session.objectivesCompleted += 1
                RescueManager.ObjectiveCompleted:Fire(session.sessionId, obj.id)
            end
            broadcastToSquad(session, "ObjectiveUpdated", {
                objectiveId = obj.id,
                currentCount = obj.currentCount,
                targetCount = obj.targetCount,
                status = obj.status,
            })
            break
        end
    end

    -- Notify squad
    broadcastToSquad(session, "CivilianStateChanged", {
        civilianId = targetId,
        isRescued = true,
        rescuedBy = member.displayName,
    })

    RescueManager.CivilianRescued:Fire(session.sessionId, targetId, member.playerId)
    return true
end

--- Neutralize a hazard zone.
interactionHandlers.NeutralizeHazard = function(session, member, targetId)
    -- Only Engineers can neutralize most hazards
    local isEngineer = member.role == "Engineer"
    local isDiver = member.role == "Diver"

    local zone = nil
    for _, hz in session.disasterConfig.hazardZones do
        if hz.id == targetId then
            zone = hz
            break
        end
    end

    if not zone then return false end
    if not zone.canBeNeutralized then return false end

    -- Role-specific checks
    if zone.hazardType == "Water" and not isDiver then return false end
    if zone.hazardType ~= "Water" and not isEngineer then return false end

    -- Distance check
    local playerPos = getPlayerPosition(member.playerId)
    if not playerPos then return false end
    if (playerPos - zone.position).Magnitude > zone.radius + INTERACTION_RANGE then
        return false
    end

    -- Neutralize
    zone.canBeNeutralized = false
    zone.damagePerSecond = 0

    if DisasterManager then
        DisasterManager:UpdateHazardZone(session.sessionId, targetId, { neutralized = true })
    end

    member.score += Constants.XP_REWARDS.HazardNeutralized

    -- Check if this completes a Contain objective
    for _, obj in session.disasterConfig.objectives do
        if obj.objectiveType == "Contain" and obj.status ~= "Completed" then
            obj.currentCount += 1
            if obj.currentCount >= obj.targetCount then
                obj.status = "Completed"
                session.objectivesCompleted += 1
                RescueManager.ObjectiveCompleted:Fire(session.sessionId, obj.id)
            end
            broadcastToSquad(session, "ObjectiveUpdated", {
                objectiveId = obj.id,
                currentCount = obj.currentCount,
                targetCount = obj.targetCount,
                status = obj.status,
            })
            break
        end
    end

    broadcastToSquad(session, "HazardZoneUpdated", {
        hazardId = targetId,
        neutralized = true,
    })

    return true
end

--- Repair / stabilize structure.
interactionHandlers.RepairStructure = function(session, member, targetId)
    if member.role ~= "Engineer" and member.role ~= "Commander" then
        return false
    end

    member.score += 15

    for _, obj in session.disasterConfig.objectives do
        if obj.objectiveType == "Repair" and obj.status ~= "Completed" then
            obj.currentCount += 1
            if obj.currentCount >= obj.targetCount then
                obj.status = "Completed"
                session.objectivesCompleted += 1
                RescueManager.ObjectiveCompleted:Fire(session.sessionId, obj.id)
            end
            broadcastToSquad(session, "ObjectiveUpdated", {
                objectiveId = obj.id,
                currentCount = obj.currentCount,
                targetCount = obj.targetCount,
                status = obj.status,
            })
            break
        end
    end

    return true
end

--- Heal teammate.
interactionHandlers.HealTeammate = function(session, member, targetId)
    if member.role ~= "Medic" then return false end

    local targetPlayerId = tonumber(targetId)
    if not targetPlayerId then return false end

    local targetMember = getMemberFromSession(session, targetPlayerId)
    if not targetMember then return false end

    -- Distance check
    local healerPos = getPlayerPosition(member.playerId)
    local targetPos = getPlayerPosition(targetPlayerId)
    if not healerPos or not targetPos then return false end
    if (healerPos - targetPos).Magnitude > INTERACTION_RANGE then return false end

    local healAmount = 40
    targetMember.health = math.min(Constants.BASE_HEALTH, targetMember.health + healAmount)
    member.score += Constants.XP_REWARDS.TeamRevive

    broadcastToSquad(session, "PlayerHealthChanged", {
        playerId = targetPlayerId,
        health = targetMember.health,
    })

    return true
end

--- K9 search command.
interactionHandlers.K9Search = function(session, member, _targetId)
    if member.role ~= "K9Handler" then return false end

    -- Reveal nearest unrescued civilian within detection radius
    local playerPos = getPlayerPosition(member.playerId)
    if not playerPos then return false end

    local detectionRadius = 50 * (Constants.ROLES.K9Handler.passiveMagnitude or 1)
    local folder = workspace:FindFirstChild(`DisasterMap_{session.sessionId}`)
    if not folder then return false end

    local nearestCivilian = nil
    local nearestDist = math.huge

    for _, child in folder:GetChildren() do
        if child:GetAttribute("CivilianId") and not child:GetAttribute("IsRescued") then
            local civPos = child.PrimaryPart and child.PrimaryPart.Position
            if civPos then
                local dist = (playerPos - civPos).Magnitude
                if dist < detectionRadius and dist < nearestDist then
                    nearestDist = dist
                    nearestCivilian = child
                end
            end
        end
    end

    if nearestCivilian then
        -- Broadcast ping to squad
        broadcastToSquad(session, "EffectTrigger", {
            effectType = "K9Ping",
            position = nearestCivilian.PrimaryPart.Position,
            civilianId = nearestCivilian:GetAttribute("CivilianId"),
        })
        -- Progress Search objectives
        for _, obj in session.disasterConfig.objectives do
            if obj.objectiveType == "Search" and obj.status ~= "Completed" then
                obj.currentCount += 1
                if obj.currentCount >= obj.targetCount then
                    obj.status = "Completed"
                    session.objectivesCompleted += 1
                end
                broadcastToSquad(session, "ObjectiveUpdated", {
                    objectiveId = obj.id,
                    currentCount = obj.currentCount,
                    targetCount = obj.targetCount,
                    status = obj.status,
                })
                break
            end
        end
        return true
    end

    return false
end

----------------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------------

--- Initialize a rescue session (called after map is built).
function RescueManager:InitSession(session: Types.RescueSession)
    activeSessions[session.sessionId] = session

    -- Activate all objectives
    for _, obj in session.disasterConfig.objectives do
        obj.status = "Active"
    end

    print(`[RescueManager] Session initialized: {session.sessionId}`)
end

--- Process an interaction request from a client.
function RescueManager:HandleInteraction(player: Player, actionType: string, targetId: string): boolean
    -- Find which session this player is in
    local session = nil
    for _, s in activeSessions do
        for _, member in s.squad.members do
            if member.playerId == player.UserId then
                session = s
                break
            end
        end
        if session then break end
    end

    if not session then
        warn(`[RescueManager] Player {player.Name} not in any active session`)
        return false
    end

    if session.phase ~= "Active" then return false end

    -- Cooldown check
    if isOnCooldown(player.UserId, actionType) then return false end

    local member = getMemberFromSession(session, player.UserId)
    if not member then return false end
    if not member.isAlive then return false end

    local handler = interactionHandlers[actionType]
    if not handler then
        warn(`[RescueManager] Unknown action type: {actionType}`)
        return false
    end

    local success = handler(session, member, targetId)
    if success then
        setCooldown(player.UserId, actionType)
    end

    return success
end

--- Check if mission should end. Returns true if mission is complete.
function RescueManager:CheckMissionStatus(session: Types.RescueSession): boolean
    -- All objectives completed = success
    if session.objectivesCompleted >= session.objectivesTotal then
        return true
    end

    -- All players down = fail
    local anyAlive = false
    for _, member in session.squad.members do
        if member.isAlive then
            anyAlive = true
            break
        end
    end
    if not anyAlive then return true end

    return false
end

--- Evaluate final result and compute scores.
function RescueManager:EvaluateResult(session: Types.RescueSession): boolean
    local allObjectivesComplete = session.objectivesCompleted >= session.objectivesTotal
    local timeUsedRatio = 1 - (session.timeRemaining / session.disasterConfig.timeLimitSeconds)

    -- Calculate team score
    local baseScore = 0
    for _, obj in session.disasterConfig.objectives do
        if obj.status == "Completed" then
            baseScore += obj.scoreValue
        end
    end

    -- Speed bonus: up to 1.5x for finishing with >50% time remaining
    local speedMultiplier = 1.0
    if timeUsedRatio < 0.5 then
        speedMultiplier = 1.5
    elseif timeUsedRatio < 0.75 then
        speedMultiplier = 1.25
    end

    -- Casualty penalty
    local totalCivilians = 0
    for _, obj in session.disasterConfig.objectives do
        if obj.objectiveType == "Rescue" then
            totalCivilians += obj.targetCount
        end
    end
    local rescueRatio = if totalCivilians > 0
        then session.civiliansRescued / totalCivilians
        else 1

    local casualtyMultiplier = math.clamp(rescueRatio, 0.5, 1.0)

    -- Severity bonus
    local severityMultiplier = ({
        Minor = 1.0,
        Major = 1.5,
        Catastrophic = 2.0,
    })[session.disasterConfig.severity]

    session.teamScore = math.floor(baseScore * speedMultiplier * casualtyMultiplier * severityMultiplier)

    -- Distribute team score proportionally to individual contributions
    local totalIndividualScore = 0
    for _, member in session.squad.members do
        totalIndividualScore += member.score
    end
    if totalIndividualScore > 0 then
        for _, member in session.squad.members do
            local proportion = member.score / totalIndividualScore
            member.score = math.floor(session.teamScore * proportion)
        end
    end

    return allObjectivesComplete and rescueRatio > 0.5
end

--- Build the result payload to send to clients.
function RescueManager:BuildResultPayload(
    session: Types.RescueSession,
    success: boolean
): Types.MissionResultPayload
    local playerScores: { Types.ScoreboardEntry } = {}
    for _, member in session.squad.members do
        table.insert(playerScores, {
            playerId = member.playerId,
            displayName = member.displayName,
            role = member.role,
            score = member.score,
            rescues = session.civiliansRescued,      -- simplified; per-player tracking in production
            objectivesCompleted = session.objectivesCompleted,
        })
    end

    -- Sort by score descending
    table.sort(playerScores, function(a, b) return a.score > b.score end)

    -- Calculate rating
    local scoreRatio = session.teamScore / math.max(1, session.objectivesTotal * 100)
    local rating: Types.MissionResultPayload["rating"]
    if scoreRatio >= 1.5 then rating = "S"
    elseif scoreRatio >= 1.2 then rating = "A"
    elseif scoreRatio >= 0.9 then rating = "B"
    elseif scoreRatio >= 0.6 then rating = "C"
    elseif scoreRatio >= 0.3 then rating = "D"
    else rating = "F"
    end

    local timeElapsed = session.disasterConfig.timeLimitSeconds - session.timeRemaining

    return {
        sessionId = session.sessionId,
        success = success,
        teamScore = session.teamScore,
        playerScores = playerScores,
        rewards = {
            coins = success and Constants.COIN_REWARDS.MissionComplete or math.floor(Constants.COIN_REWARDS.MissionComplete * 0.3),
            rescueTokens = success and Constants.RESCUE_TOKEN_REWARDS.MissionComplete or 1,
            xp = session.teamScore,
        },
        xpGained = session.teamScore,
        leveledUp = false, -- ProgressionManager handles this
        newLevel = nil,
        timeElapsed = timeElapsed,
        rating = rating,
    }
end

--- Clean up session state.
function RescueManager:CleanupSession(session: Types.RescueSession)
    activeSessions[session.sessionId] = nil
    -- Clear cooldowns for this session's players
    for _, member in session.squad.members do
        for key, _ in interactionCooldowns do
            if string.find(key, tostring(member.playerId)) then
                interactionCooldowns[key] = nil
            end
        end
    end
    print(`[RescueManager] Session cleaned up: {session.sessionId}`)
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------

function RescueManager:Init(dependencies: { NetworkManager: any, DisasterManager: any })
    NetworkManager = dependencies.NetworkManager
    DisasterManager = dependencies.DisasterManager

    print("[RescueManager] Initialized")
end

return RescueManager
