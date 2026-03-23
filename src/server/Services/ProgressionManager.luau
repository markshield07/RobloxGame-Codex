--[[
    ProgressionManager.luau (Server)

    Handles XP, leveling, prestige, per-role stats, and post-mission rewards.

    Level formula: XP_required = BASE * level^EXPONENT
    Prestige: at max level, player can reset to level 1 for permanent multiplier.

    All mutations go through PlayerDataManager (the single write path to DataStore).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Types = require(ReplicatedStorage.Shared.Modules.Types)
local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local ProgressionManager = {}
ProgressionManager.__index = ProgressionManager

----------------------------------------------------------------------
-- SIGNALS
----------------------------------------------------------------------
ProgressionManager.PlayerLeveledUp = Signal.new()    -- (player, newLevel)
ProgressionManager.PlayerPrestiged = Signal.new()    -- (player, newPrestige)
ProgressionManager.XPAwarded = Signal.new()          -- (player, amount, source)

----------------------------------------------------------------------
-- REFERENCES
----------------------------------------------------------------------
local PlayerDataManager = nil
local EconomyManager = nil
local NetworkManager = nil

----------------------------------------------------------------------
-- XP / LEVEL MATH
----------------------------------------------------------------------

--- Calculate XP required for a given level.
function ProgressionManager:GetXPForLevel(level: number): number
    return math.floor(Constants.XP_PER_LEVEL_BASE * (level ^ Constants.XP_LEVEL_EXPONENT))
end

--- Calculate total cumulative XP needed to reach a level from 1.
function ProgressionManager:GetCumulativeXP(level: number): number
    local total = 0
    for i = 1, level do
        total += self:GetXPForLevel(i)
    end
    return total
end

--- Determine level from total XP.
function ProgressionManager:GetLevelFromXP(totalXP: number): (number, number)
    local level = 1
    local remaining = totalXP
    while level < Constants.MAX_LEVEL do
        local needed = self:GetXPForLevel(level)
        if remaining < needed then
            break
        end
        remaining -= needed
        level += 1
    end
    return level, remaining -- level, xp into current level
end

----------------------------------------------------------------------
-- CORE REWARD LOGIC
----------------------------------------------------------------------

--- Award post-mission rewards to a player.
function ProgressionManager:AwardMissionRewards(
    player: Player,
    session: Types.RescueSession,
    result: Types.MissionResultPayload
)
    local data = PlayerDataManager:GetData(player)
    if not data then return end

    -- Find this player's score from the result
    local playerScore = 0
    local playerRole: Types.Role = "Medic"
    for _, entry in result.playerScores do
        if entry.playerId == player.UserId then
            playerScore = entry.score
            playerRole = entry.role
            break
        end
    end

    -- Prestige multiplier
    local prestigeMultiplier = 1 + (data.prestigeLevel * Constants.PRESTIGE_MULTIPLIER_PER_LEVEL)

    -- VIP multiplier
    local vipMultiplier = 1.0
    if table.find(data.gamePasses, "VIP") then
        vipMultiplier = Constants.GAME_PASSES.VIP.multiplier
    end

    -- Double XP pass
    local xpMultiplier = 1.0
    if table.find(data.gamePasses, "DoubleXP") then
        xpMultiplier = Constants.GAME_PASSES.DoubleXP.multiplier
    end

    -- Calculate XP
    local baseXP = playerScore
    if result.success then
        baseXP += Constants.XP_REWARDS.MissionComplete
    end
    if result.rating == "S" then
        baseXP += Constants.XP_REWARDS.MissionPerfect
    end
    if session.timeRemaining > session.disasterConfig.timeLimitSeconds * 0.5 then
        baseXP += Constants.XP_REWARDS.FastCompletion
    end

    local totalXP = math.floor(baseXP * prestigeMultiplier * xpMultiplier)

    -- Calculate coins
    local baseCoins = result.rewards.coins or 0
    baseCoins += session.civiliansRescued * Constants.COIN_REWARDS.PerCivilianRescued
    baseCoins += session.objectivesCompleted * Constants.COIN_REWARDS.PerObjective
    if result.rating == "S" then
        baseCoins += Constants.COIN_REWARDS.PerfectBonus
    end
    local totalCoins = math.floor(baseCoins * prestigeMultiplier * vipMultiplier)

    local rescueTokens = result.rewards.rescueTokens or 0

    -- Apply to player data
    PlayerDataManager:UpdateData(player, function(d: Types.PlayerData)
        -- Global XP and level
        d.globalXP += totalXP
        local newLevel, _xpIntoLevel = ProgressionManager:GetLevelFromXP(d.globalXP)
        local leveledUp = newLevel > d.globalLevel
        d.globalLevel = newLevel

        -- Role-specific stats
        if not d.roleStats[playerRole] then
            d.roleStats[playerRole] = {
                missionsCompleted = 0,
                totalScore = 0,
                bestScore = 0,
                timePlayed = 0,
                xp = 0,
                level = 1,
            }
        end
        local rs = d.roleStats[playerRole]
        rs.missionsCompleted += 1
        rs.totalScore += playerScore
        rs.bestScore = math.max(rs.bestScore, playerScore)
        rs.xp += totalXP
        rs.level = ProgressionManager:GetLevelFromXP(rs.xp)

        -- Economy
        d.coins += totalCoins
        d.totalCoinsEarned += totalCoins
        d.rescueTokens += rescueTokens

        -- Stats
        d.totalMissions += 1
        d.totalRescues += session.civiliansRescued
        d.totalScore += playerScore

        local dtKey = session.disasterConfig.disasterType
        d.missionsPerDisasterType[dtKey] = (d.missionsPerDisasterType[dtKey] or 0) + 1

        if leveledUp then
            ProgressionManager.PlayerLeveledUp:Fire(player, newLevel)
        end

        return d
    end)

    ProgressionManager.XPAwarded:Fire(player, totalXP, "MissionReward")
    print(`[ProgressionManager] Awarded {player.Name}: {totalXP} XP, {totalCoins} coins, {rescueTokens} tokens`)
end

--- Handle prestige request.
function ProgressionManager:Prestige(player: Player): boolean
    local data = PlayerDataManager:GetData(player)
    if not data then return false end
    if data.globalLevel < Constants.MAX_LEVEL then return false end
    if data.prestigeLevel >= Constants.PRESTIGE_LEVELS then return false end

    PlayerDataManager:UpdateData(player, function(d: Types.PlayerData)
        d.prestigeLevel += 1
        d.prestigeMultiplier = 1 + (d.prestigeLevel * Constants.PRESTIGE_MULTIPLIER_PER_LEVEL)
        d.globalXP = 0
        d.globalLevel = 1

        -- Reset role levels but keep stats
        for role, rs in d.roleStats do
            rs.xp = 0
            rs.level = 1
            -- Keep: missionsCompleted, totalScore, bestScore, timePlayed
        end

        return d
    end)

    ProgressionManager.PlayerPrestiged:Fire(player, data.prestigeLevel + 1)
    print(`[ProgressionManager] {player.Name} prestiged to level {data.prestigeLevel + 1}`)
    return true
end

--- Award daily login reward.
function ProgressionManager:AwardDailyLogin(player: Player)
    local data = PlayerDataManager:GetData(player)
    if not data then return end

    local now = os.time()
    local lastReward = data.lastDailyReward or 0
    local daysSinceLast = math.floor((now - lastReward) / 86400)

    if daysSinceLast < 1 then return end -- already claimed today

    PlayerDataManager:UpdateData(player, function(d: Types.PlayerData)
        if daysSinceLast == 1 then
            d.dailyLoginStreak += 1
        else
            d.dailyLoginStreak = 1  -- streak broken
        end

        local reward = Constants.COIN_REWARDS.DailyLogin
            + (d.dailyLoginStreak * Constants.COIN_REWARDS.StreakBonus)

        d.coins += reward
        d.totalCoinsEarned += reward
        d.lastDailyReward = now

        return d
    end)

    if NetworkManager then
        NetworkManager:FireClient(player, "NotificationPush", {
            title = "Daily Login!",
            message = `Day {data.dailyLoginStreak + 1} streak! +{Constants.COIN_REWARDS.DailyLogin} coins`,
            type = "Reward",
        })
    end
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------

function ProgressionManager:Init(dependencies: {
    PlayerDataManager: any,
    EconomyManager: any,
    NetworkManager: any,
})
    PlayerDataManager = dependencies.PlayerDataManager
    EconomyManager = dependencies.EconomyManager
    NetworkManager = dependencies.NetworkManager

    print("[ProgressionManager] Initialized")
end

return ProgressionManager
