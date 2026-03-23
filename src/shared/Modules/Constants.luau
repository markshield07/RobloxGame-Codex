--[[
    Constants.luau
    All game-wide constants. Tuning numbers, limits, and configuration.
    NEVER put instance references here -- only pure data.
]]

local Constants = {}

----------------------------------------------------------------------
-- GAME SETTINGS
----------------------------------------------------------------------

Constants.GAME_VERSION = "0.1.0-alpha"
Constants.MAX_PLAYERS_PER_SERVER = 30
Constants.MIN_SQUAD_SIZE = 4
Constants.MAX_SQUAD_SIZE = 6
Constants.MATCHMAKING_TIMEOUT = 60          -- seconds
Constants.LOBBY_COUNTDOWN = 15              -- seconds before deploy
Constants.INTERMISSION_DURATION = 20        -- seconds between rounds
Constants.BRIEFING_DURATION = 10            -- seconds to read briefing

----------------------------------------------------------------------
-- GAMEPLAY TUNING
----------------------------------------------------------------------

Constants.BASE_HEALTH = 100
Constants.BASE_STAMINA = 100
Constants.STAMINA_REGEN_RATE = 5            -- per second
Constants.SPRINT_STAMINA_COST = 15          -- per second
Constants.REVIVE_TIME = 5                   -- seconds to revive downed player
Constants.BLEEDOUT_TIME = 30                -- seconds until player is out
Constants.RESPAWN_PENALTY_SECONDS = 10

----------------------------------------------------------------------
-- DISASTER GENERATION
----------------------------------------------------------------------

Constants.DISASTER_CONFIGS = {
    BuildingCollapse = {
        displayName = "Building Collapse",
        minSeverity = 1,
        maxSeverity = 3,
        baseTimeLimit = 300,
        baseObjectives = 4,
        baseCivilians = 8,
        hazardTypes = { "Structural", "Fire" },
        requiredRolesWeight = { Engineer = 2, Medic = 1.5, K9Handler = 1.5 },
    },
    Wildfire = {
        displayName = "Wildfire",
        minSeverity = 1,
        maxSeverity = 3,
        baseTimeLimit = 360,
        baseObjectives = 5,
        baseCivilians = 6,
        hazardTypes = { "Fire" },
        requiredRolesWeight = { Pilot = 2, Commander = 1.5, Medic = 1 },
    },
    Flood = {
        displayName = "Flash Flood",
        minSeverity = 1,
        maxSeverity = 3,
        baseTimeLimit = 300,
        baseObjectives = 4,
        baseCivilians = 10,
        hazardTypes = { "Water" },
        requiredRolesWeight = { Diver = 2, Pilot = 1.5, Medic = 1 },
    },
    Earthquake = {
        displayName = "Earthquake",
        minSeverity = 2,
        maxSeverity = 3,
        baseTimeLimit = 360,
        baseObjectives = 6,
        baseCivilians = 12,
        hazardTypes = { "Structural", "Fire", "Electric" },
        requiredRolesWeight = { Engineer = 2, K9Handler = 1.5, Medic = 1.5 },
    },
    Hurricane = {
        displayName = "Hurricane",
        minSeverity = 2,
        maxSeverity = 3,
        baseTimeLimit = 420,
        baseObjectives = 6,
        baseCivilians = 15,
        hazardTypes = { "Water", "Structural" },
        requiredRolesWeight = { Commander = 2, Pilot = 1.5, Engineer = 1 },
    },
    ChemicalSpill = {
        displayName = "Chemical Spill",
        minSeverity = 1,
        maxSeverity = 3,
        baseTimeLimit = 240,
        baseObjectives = 3,
        baseCivilians = 5,
        hazardTypes = { "Toxic" },
        requiredRolesWeight = { Engineer = 2, Medic = 2, Commander = 1 },
    },
    Avalanche = {
        displayName = "Avalanche",
        minSeverity = 1,
        maxSeverity = 3,
        baseTimeLimit = 300,
        baseObjectives = 4,
        baseCivilians = 6,
        hazardTypes = { "Structural" },
        requiredRolesWeight = { K9Handler = 2, Medic = 1.5, Pilot = 1 },
    },
    Shipwreck = {
        displayName = "Shipwreck",
        minSeverity = 1,
        maxSeverity = 3,
        baseTimeLimit = 360,
        baseObjectives = 5,
        baseCivilians = 8,
        hazardTypes = { "Water", "Fire" },
        requiredRolesWeight = { Diver = 2, Pilot = 1.5, Medic = 1 },
    },
}

----------------------------------------------------------------------
-- ROLE DEFINITIONS
----------------------------------------------------------------------

Constants.ROLES = {
    Medic = {
        displayName = "Medic",
        description = "Heals teammates and stabilizes wounded civilians",
        color = Color3.fromRGB(46, 204, 113),
        icon = "rbxassetid://0", -- placeholder
        baseEquipment = { "MedKit", "Defibrillator", "Stretcher" },
        abilities = {
            { id = "HealBurst", cooldown = 15, staminaCost = 25 },
            { id = "Triage", cooldown = 30, staminaCost = 40 },
        },
        passiveBonus = "ReviveSpeed",
        passiveMagnitude = 0.5, -- 50% faster revives
        unlockLevel = 1,
    },
    Engineer = {
        displayName = "Engineer",
        description = "Stabilizes structures, clears debris, disables hazards",
        color = Color3.fromRGB(241, 196, 15),
        icon = "rbxassetid://0",
        baseEquipment = { "JacksAndBraces", "CuttingTorch", "StructuralScanner" },
        abilities = {
            { id = "Reinforce", cooldown = 20, staminaCost = 30 },
            { id = "ControlledDemolition", cooldown = 45, staminaCost = 50 },
        },
        passiveBonus = "HazardResistance",
        passiveMagnitude = 0.3,
        unlockLevel = 1,
    },
    K9Handler = {
        displayName = "K9 Handler",
        description = "Uses trained dog to locate buried survivors",
        color = Color3.fromRGB(155, 89, 182),
        icon = "rbxassetid://0",
        baseEquipment = { "K9Companion", "TrackingDevice", "ExtractionHarness" },
        abilities = {
            { id = "SearchCommand", cooldown = 12, staminaCost = 20 },
            { id = "AlertBark", cooldown = 25, staminaCost = 15 },
        },
        passiveBonus = "DetectionRadius",
        passiveMagnitude = 1.5, -- 50% larger detection
        unlockLevel = 3,
    },
    Pilot = {
        displayName = "Pilot",
        description = "Operates helicopters for aerial rescue and water drops",
        color = Color3.fromRGB(52, 152, 219),
        icon = "rbxassetid://0",
        baseEquipment = { "Helicopter", "WinchSystem", "WaterBucket" },
        abilities = {
            { id = "AerialDrop", cooldown = 30, staminaCost = 35 },
            { id = "Spotlight", cooldown = 10, staminaCost = 10 },
        },
        passiveBonus = "MovementSpeed",
        passiveMagnitude = 0.2,
        unlockLevel = 5,
    },
    Diver = {
        displayName = "Diver",
        description = "Specializes in underwater rescue and flood navigation",
        color = Color3.fromRGB(26, 188, 156),
        icon = "rbxassetid://0",
        baseEquipment = { "DivingSuit", "UnderwaterCutter", "InflatableRaft" },
        abilities = {
            { id = "SwiftSwim", cooldown = 15, staminaCost = 20 },
            { id = "AirPocket", cooldown = 40, staminaCost = 45 },
        },
        passiveBonus = "WaterMovement",
        passiveMagnitude = 2.0, -- 2x underwater speed
        unlockLevel = 5,
    },
    Commander = {
        displayName = "Commander",
        description = "Coordinates team, provides buffs, and manages resources",
        color = Color3.fromRGB(231, 76, 60),
        icon = "rbxassetid://0",
        baseEquipment = { "TacticalRadio", "FlareGun", "SupplyDrop" },
        abilities = {
            { id = "RallyingCry", cooldown = 30, staminaCost = 30 },
            { id = "SupplyAirdrop", cooldown = 60, staminaCost = 50 },
        },
        passiveBonus = "TeamBuffRadius",
        passiveMagnitude = 1.25,
        unlockLevel = 8,
    },
}

----------------------------------------------------------------------
-- PROGRESSION
----------------------------------------------------------------------

Constants.XP_PER_LEVEL_BASE = 100
Constants.XP_LEVEL_EXPONENT = 1.15          -- xp = base * level^exponent
Constants.MAX_LEVEL = 100
Constants.PRESTIGE_LEVELS = 10
Constants.PRESTIGE_MULTIPLIER_PER_LEVEL = 0.10 -- +10% rewards per prestige

Constants.XP_REWARDS = {
    ObjectiveComplete = 50,
    CivilianRescued = 30,
    MissionComplete = 100,
    MissionPerfect = 250,       -- all objectives, no casualties
    TeamRevive = 20,
    HazardNeutralized = 15,
    FastCompletion = 75,        -- under 50% time used
}

----------------------------------------------------------------------
-- ECONOMY
----------------------------------------------------------------------

Constants.COIN_REWARDS = {
    MissionComplete = 150,
    PerObjective = 40,
    PerCivilianRescued = 25,
    PerfectBonus = 300,
    DailyLogin = 50,
    StreakBonus = 25,           -- per streak day
}

Constants.RESCUE_TOKEN_REWARDS = {
    MissionComplete = 5,
    PerfectMission = 15,
    WeeklyComplete = 30,
}

Constants.GAME_PASSES = {
    VIP = { id = 0, price = 499, multiplier = 1.5 },
    DoubleXP = { id = 0, price = 299, multiplier = 2.0 },
    ExtraLoadout = { id = 0, price = 199 },
    AutoCollect = { id = 0, price = 149 },
    PremiumCosmetics = { id = 0, price = 399 },
}

----------------------------------------------------------------------
-- DATA STORE
----------------------------------------------------------------------

Constants.DATA_STORE_NAME = "RescueSquad_PlayerData"
Constants.DATA_VERSION = 1
Constants.DATA_SAVE_INTERVAL = 300          -- seconds (5 min auto-save)
Constants.SESSION_LOCK_DURATION = 1800      -- 30 min lock

----------------------------------------------------------------------
-- NETWORKING
----------------------------------------------------------------------

Constants.REMOTE_EVENTS = {
    -- Server -> Client
    "GamePhaseChanged",
    "DisasterBriefing",
    "ObjectiveUpdated",
    "HazardZoneUpdated",
    "PlayerHealthChanged",
    "PlayerStaminaChanged",
    "ScoreUpdated",
    "MissionResult",
    "EffectTrigger",
    "SquadUpdated",
    "NotificationPush",
    "EnvironmentUpdate",
    "CivilianStateChanged",

    -- Client -> Server
    "PlayerReady",
    "RoleSelected",
    "AbilityActivated",
    "InteractionRequest",
    "SquadInviteSent",
    "SquadInviteResponse",
    "EquipmentChanged",
    "PurchaseRequest",
    "SettingsChanged",
}

Constants.REMOTE_FUNCTIONS = {
    "GetPlayerData",
    "GetShopCatalog",
    "GetLeaderboard",
    "GetSquadInfo",
    "GetMissionHistory",
}

----------------------------------------------------------------------
-- PERFORMANCE
----------------------------------------------------------------------

Constants.TARGET_FPS = 60
Constants.MAX_ACTIVE_PARTICLES = 200
Constants.MAX_DEBRIS_PARTS = 500
Constants.CIVILIAN_NPC_LIMIT = 20
Constants.LOD_DISTANCES = {
    High = 100,
    Medium = 250,
    Low = 500,
}
Constants.PHYSICS_STEP_BUDGET_MS = 4        -- max ms for custom physics per frame
Constants.NETWORK_UPDATE_RATE = 10          -- Hz for non-critical updates
Constants.CRITICAL_UPDATE_RATE = 30         -- Hz for health/position

return Constants
