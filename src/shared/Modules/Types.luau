--[[
    Types.luau
    Central type definitions for Rescue Squad Simulator.
    All cross-boundary types live here so server and client share one source of truth.
]]

local Types = {}

----------------------------------------------------------------------
-- ENUMS / LITERALS
----------------------------------------------------------------------

export type Role = "Medic" | "Engineer" | "K9Handler" | "Pilot" | "Diver" | "Commander"

export type DisasterType =
    "BuildingCollapse"
    | "Wildfire"
    | "Flood"
    | "Earthquake"
    | "Hurricane"
    | "ChemicalSpill"
    | "Avalanche"
    | "Shipwreck"

export type DisasterSeverity = "Minor" | "Major" | "Catastrophic"

export type GamePhase =
    "Lobby"
    | "Matchmaking"
    | "Briefing"
    | "Deploying"
    | "Active"
    | "Extraction"
    | "Scoring"
    | "Intermission"

export type ObjectiveStatus = "Pending" | "Active" | "Completed" | "Failed" | "Expired"

export type CurrencyType = "Coins" | "RescueTokens" | "PremiumGems"

----------------------------------------------------------------------
-- DISASTER CONFIGURATION
----------------------------------------------------------------------

export type DisasterObjective = {
    id: string,
    label: string,
    description: string,
    objectiveType: "Rescue" | "Extinguish" | "Repair" | "Evacuate" | "Contain" | "Search",
    requiredRoles: { Role }?,          -- nil means any role can do it
    targetCount: number,               -- e.g. rescue 5 civilians
    currentCount: number,
    scoreValue: number,
    timeLimit: number?,                -- seconds; nil = no per-objective limit
    status: ObjectiveStatus,
    position: Vector3?,                -- world position hint
}

export type DisasterConfig = {
    disasterType: DisasterType,
    severity: DisasterSeverity,
    displayName: string,
    description: string,
    minPlayers: number,
    maxPlayers: number,
    timeLimitSeconds: number,
    objectives: { DisasterObjective },
    hazardZones: { HazardZone },
    spawnPoints: { Vector3 },
    environmentModifiers: EnvironmentModifiers,
}

export type HazardZone = {
    id: string,
    position: Vector3,
    radius: number,
    damagePerSecond: number,
    hazardType: "Fire" | "Toxic" | "Structural" | "Water" | "Electric",
    canBeNeutralized: boolean,
}

export type EnvironmentModifiers = {
    visibility: number,        -- 0-1 multiplier
    windSpeed: number,         -- studs/sec
    windDirection: Vector3,
    precipitation: "None" | "Rain" | "Snow" | "Ash",
    timeOfDay: number,         -- ClockTime 0-24
    shakeMagnitude: number,    -- camera shake
}

----------------------------------------------------------------------
-- SQUAD / PLAYER
----------------------------------------------------------------------

export type SquadMember = {
    playerId: number,
    displayName: string,
    role: Role,
    isReady: boolean,
    isAlive: boolean,
    health: number,
    stamina: number,
    equipment: { string },     -- equipped item IDs
    score: number,
}

export type Squad = {
    squadId: string,
    members: { SquadMember },
    leaderId: number,
    isMatchmaking: boolean,
    currentDisasterId: string?,
    totalScore: number,
}

----------------------------------------------------------------------
-- RESCUE SESSION (live state during active disaster)
----------------------------------------------------------------------

export type RescueSession = {
    sessionId: string,
    disasterConfig: DisasterConfig,
    squad: Squad,
    startTime: number,              -- os.clock()
    timeRemaining: number,
    objectivesCompleted: number,
    objectivesTotal: number,
    civiliansRescued: number,
    civiliansLost: number,
    teamScore: number,
    phase: GamePhase,
}

----------------------------------------------------------------------
-- PLAYER PERSISTENT DATA (DataStore schema)
----------------------------------------------------------------------

export type EquipmentData = {
    itemId: string,
    level: number,
    equipped: boolean,
}

export type RoleStats = {
    missionsCompleted: number,
    totalScore: number,
    bestScore: number,
    timePlayed: number,      -- seconds
    xp: number,
    level: number,
}

export type PlayerData = {
    -- meta
    dataVersion: number,
    firstJoin: number,
    lastJoin: number,
    totalPlayTime: number,

    -- progression
    globalXP: number,
    globalLevel: number,
    prestigeLevel: number,
    prestigeMultiplier: number,

    -- per-role progression
    roleStats: { [Role]: RoleStats },

    -- economy
    coins: number,
    rescueTokens: number,
    premiumGems: number,
    totalCoinsEarned: number,

    -- inventory
    equipment: { EquipmentData },
    cosmetics: { string },        -- owned cosmetic IDs
    equippedCosmetics: {
        uniform: string?,
        helmet: string?,
        badge: string?,
        emote: string?,
    },

    -- game passes / purchases
    gamePasses: { string },       -- owned pass IDs

    -- stats
    totalMissions: number,
    totalRescues: number,
    totalScore: number,
    missionsPerDisasterType: { [string]: number },

    -- social
    squadInvitesEnabled: boolean,
    preferredRole: Role?,

    -- streaks / dailies
    dailyLoginStreak: number,
    lastDailyReward: number,      -- UTC timestamp
    weeklyMissions: {
        completed: number,
        target: number,
        lastReset: number,
    },

    -- settings
    settings: {
        musicVolume: number,
        sfxVolume: number,
        cameraSensitivity: number,
        reducedEffects: boolean,
        showDamageNumbers: boolean,
    },
}

----------------------------------------------------------------------
-- ECONOMY
----------------------------------------------------------------------

export type ShopItem = {
    itemId: string,
    displayName: string,
    description: string,
    category: "Equipment" | "Cosmetic" | "Boost" | "GamePass",
    currencyType: CurrencyType,
    price: number,
    requiredLevel: number?,
    requiredPrestige: number?,
    isLimitedTime: boolean,
    expiresAt: number?,            -- UTC timestamp
}

export type RewardPackage = {
    coins: number?,
    rescueTokens: number?,
    premiumGems: number?,
    xp: number?,
    items: { string }?,            -- item IDs
    cosmetics: { string }?,
}

----------------------------------------------------------------------
-- NETWORK PAYLOADS
----------------------------------------------------------------------

export type DisasterBriefingPayload = {
    sessionId: string,
    disasterType: DisasterType,
    severity: DisasterSeverity,
    displayName: string,
    description: string,
    objectives: { { label: string, description: string, targetCount: number } },
    timeLimit: number,
    environment: EnvironmentModifiers,
}

export type ScoreboardEntry = {
    playerId: number,
    displayName: string,
    role: Role,
    score: number,
    rescues: number,
    objectivesCompleted: number,
}

export type MissionResultPayload = {
    sessionId: string,
    success: boolean,
    teamScore: number,
    playerScores: { ScoreboardEntry },
    rewards: RewardPackage,
    xpGained: number,
    leveledUp: boolean,
    newLevel: number?,
    timeElapsed: number,
    rating: "S" | "A" | "B" | "C" | "D" | "F",
}

return Types
