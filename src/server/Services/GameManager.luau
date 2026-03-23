--[[
    GameManager.luau (Server)

    Top-level orchestrator for game state and round lifecycle.
    Owns the state machine: Lobby -> Matchmaking -> Briefing -> Deploying -> Active -> Extraction -> Scoring -> Intermission -> loop

    Delegates to:
      - SquadManager for team formation
      - DisasterManager for scenario generation
      - RescueManager for active-mission logic
      - ProgressionManager for post-mission rewards

    Design rationale:
      Single authority for phase transitions prevents race conditions.
      All phase changes fire a Signal so other systems react without polling.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Types = require(ReplicatedStorage.Shared.Modules.Types)
local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

type GamePhase = Types.GamePhase

local GameManager = {}
GameManager.__index = GameManager

----------------------------------------------------------------------
-- SIGNALS (other server modules connect to these)
----------------------------------------------------------------------
GameManager.PhaseChanged = Signal.new()         -- (newPhase: GamePhase, oldPhase: GamePhase)
GameManager.RoundStarted = Signal.new()         -- (sessionId: string)
GameManager.RoundEnded = Signal.new()           -- (sessionId: string, success: boolean)

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local currentPhase: GamePhase = "Lobby"
local activeSessions: { [string]: Types.RescueSession } = {}
local roundCount: number = 0

-- Module references (set during Init via dependency injection)
local SquadManager = nil
local DisasterManager = nil
local RescueManager = nil
local ProgressionManager = nil
local NetworkManager = nil

----------------------------------------------------------------------
-- PRIVATE
----------------------------------------------------------------------

local function setPhase(newPhase: GamePhase)
    local old = currentPhase
    currentPhase = newPhase
    GameManager.PhaseChanged:Fire(newPhase, old)

    -- Replicate to all clients
    if NetworkManager then
        NetworkManager:FireAllClients("GamePhaseChanged", {
            phase = newPhase,
            timestamp = workspace:GetServerTimeNow(),
        })
    end
end

local function runRoundLoop()
    while true do
        ---------------------------------------------------------
        -- LOBBY / MATCHMAKING
        ---------------------------------------------------------
        setPhase("Lobby")

        -- Wait until we have enough ready players
        while true do
            local readySquads = SquadManager:GetReadySquads()
            if #readySquads > 0 then
                break
            end
            task.wait(1)
        end

        setPhase("Matchmaking")
        local squad = SquadManager:FormNextSquad()
        if not squad then
            task.wait(3)
            continue
        end

        ---------------------------------------------------------
        -- BRIEFING
        ---------------------------------------------------------
        setPhase("Briefing")
        local disasterConfig = DisasterManager:GenerateDisaster(squad)
        local sessionId = `session_{roundCount}_{os.clock()}`
        roundCount += 1

        local session: Types.RescueSession = {
            sessionId = sessionId,
            disasterConfig = disasterConfig,
            squad = squad,
            startTime = os.clock(),
            timeRemaining = disasterConfig.timeLimitSeconds,
            objectivesCompleted = 0,
            objectivesTotal = #disasterConfig.objectives,
            civiliansRescued = 0,
            civiliansLost = 0,
            teamScore = 0,
            phase = "Briefing",
        }
        activeSessions[sessionId] = session

        -- Send briefing to squad members
        local briefingPayload: Types.DisasterBriefingPayload = {
            sessionId = sessionId,
            disasterType = disasterConfig.disasterType,
            severity = disasterConfig.severity,
            displayName = disasterConfig.displayName,
            description = disasterConfig.description,
            objectives = {},
            timeLimit = disasterConfig.timeLimitSeconds,
            environment = disasterConfig.environmentModifiers,
        }
        for _, obj in disasterConfig.objectives do
            table.insert(briefingPayload.objectives, {
                label = obj.label,
                description = obj.description,
                targetCount = obj.targetCount,
            })
        end
        for _, member in squad.members do
            local player = Players:GetPlayerByUserId(member.playerId)
            if player then
                NetworkManager:FireClient(player, "DisasterBriefing", briefingPayload)
            end
        end

        task.wait(Constants.BRIEFING_DURATION)

        ---------------------------------------------------------
        -- DEPLOYING
        ---------------------------------------------------------
        setPhase("Deploying")
        DisasterManager:BuildDisasterMap(session)
        RescueManager:InitSession(session)

        -- Teleport squad to spawn points
        for i, member in squad.members do
            local player = Players:GetPlayerByUserId(member.playerId)
            if player and player.Character then
                local spawnIdx = ((i - 1) % #disasterConfig.spawnPoints) + 1
                local spawnPos = disasterConfig.spawnPoints[spawnIdx]
                player.Character:PivotTo(CFrame.new(spawnPos + Vector3.new(0, 5, 0)))
            end
        end

        task.wait(3) -- brief deploy animation time

        ---------------------------------------------------------
        -- ACTIVE MISSION
        ---------------------------------------------------------
        setPhase("Active")
        session.phase = "Active"
        session.startTime = os.clock()
        GameManager.RoundStarted:Fire(sessionId)

        -- Tick loop: update timer, check win/loss
        local missionComplete = false
        while not missionComplete do
            local elapsed = os.clock() - session.startTime
            session.timeRemaining = math.max(0, disasterConfig.timeLimitSeconds - elapsed)

            missionComplete = RescueManager:CheckMissionStatus(session)

            if session.timeRemaining <= 0 then
                missionComplete = true
            end

            task.wait(0.5)
        end

        ---------------------------------------------------------
        -- EXTRACTION
        ---------------------------------------------------------
        setPhase("Extraction")
        session.phase = "Extraction"
        task.wait(5) -- extraction cinematic time

        ---------------------------------------------------------
        -- SCORING
        ---------------------------------------------------------
        setPhase("Scoring")
        session.phase = "Scoring"

        local missionSuccess = RescueManager:EvaluateResult(session)
        local results = RescueManager:BuildResultPayload(session, missionSuccess)

        -- Award XP and currency
        for _, member in squad.members do
            local player = Players:GetPlayerByUserId(member.playerId)
            if player then
                ProgressionManager:AwardMissionRewards(player, session, results)
                NetworkManager:FireClient(player, "MissionResult", results)
            end
        end

        GameManager.RoundEnded:Fire(sessionId, missionSuccess)

        -- Clean up disaster map
        DisasterManager:CleanupDisaster(session)
        RescueManager:CleanupSession(session)
        activeSessions[sessionId] = nil

        task.wait(10) -- let players view scoreboard

        ---------------------------------------------------------
        -- INTERMISSION
        ---------------------------------------------------------
        setPhase("Intermission")
        task.wait(Constants.INTERMISSION_DURATION)
    end
end

----------------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------------

function GameManager:GetCurrentPhase(): GamePhase
    return currentPhase
end

function GameManager:GetActiveSession(sessionId: string): Types.RescueSession?
    return activeSessions[sessionId]
end

function GameManager:GetAllActiveSessions(): { [string]: Types.RescueSession }
    return activeSessions
end

function GameManager:GetRoundCount(): number
    return roundCount
end

--- Force-end a session (admin / error recovery).
function GameManager:ForceEndSession(sessionId: string)
    local session = activeSessions[sessionId]
    if session then
        session.timeRemaining = 0
    end
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------

function GameManager:Init(dependencies: {
    SquadManager: any,
    DisasterManager: any,
    RescueManager: any,
    ProgressionManager: any,
    NetworkManager: any,
})
    SquadManager = dependencies.SquadManager
    DisasterManager = dependencies.DisasterManager
    RescueManager = dependencies.RescueManager
    ProgressionManager = dependencies.ProgressionManager
    NetworkManager = dependencies.NetworkManager

    -- Start the main round loop on a separate thread
    task.spawn(runRoundLoop)

    print("[GameManager] Initialized")
end

return GameManager
