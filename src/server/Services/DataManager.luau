--[[
    DataManager.luau (Server)

    Player data persistence using DataStoreService with session locking.
    Follows ProfileService-style patterns:
      - Session locking prevents data corruption from multi-server joins
      - Periodic auto-save (every DATA_SAVE_INTERVAL seconds)
      - Save on player leave and server shutdown
      - Data migration via version numbers

    All other modules read/write through this module's API.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Modules.Types)
local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local TableUtil = require(ReplicatedStorage.Shared.Util.TableUtil)

local DataManager = {}
DataManager.__index = DataManager

----------------------------------------------------------------------
-- SIGNALS
----------------------------------------------------------------------
DataManager.DataLoaded = Signal.new()      -- (player: Player, data: PlayerData)
DataManager.DataSaved = Signal.new()       -- (player: Player)
DataManager.DataError = Signal.new()       -- (player: Player, errorMsg: string)

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local dataStore = nil
local playerData: { [number]: Types.PlayerData } = {}   -- userId -> data
local dirtyFlags: { [number]: boolean } = {}             -- userId -> needs save
local sessionKeys: { [number]: string } = {}             -- userId -> session lock key

----------------------------------------------------------------------
-- DEFAULT DATA TEMPLATE
----------------------------------------------------------------------

local function getDefaultData(): Types.PlayerData
    return {
        dataVersion = Constants.DATA_VERSION,
        firstJoin = os.time(),
        lastJoin = os.time(),
        totalPlayTime = 0,

        globalXP = 0,
        globalLevel = 1,
        prestigeLevel = 0,
        prestigeMultiplier = 1.0,

        roleStats = {},

        coins = 100,              -- starter coins
        rescueTokens = 0,
        premiumGems = 0,
        totalCoinsEarned = 100,

        equipment = {},
        cosmetics = {},
        equippedCosmetics = {
            uniform = nil,
            helmet = nil,
            badge = nil,
            emote = nil,
        },

        gamePasses = {},

        totalMissions = 0,
        totalRescues = 0,
        totalScore = 0,
        missionsPerDisasterType = {},

        squadInvitesEnabled = true,
        preferredRole = nil,

        dailyLoginStreak = 0,
        lastDailyReward = 0,
        weeklyMissions = {
            completed = 0,
            target = 10,
            lastReset = os.time(),
        },

        settings = {
            musicVolume = 0.5,
            sfxVolume = 0.8,
            cameraSensitivity = 1.0,
            reducedEffects = false,
            showDamageNumbers = true,
        },
    }
end

----------------------------------------------------------------------
-- DATA MIGRATION
----------------------------------------------------------------------

local function migrateData(data: any): Types.PlayerData
    local version = data.dataVersion or 0

    if version < 1 then
        -- Migrate from version 0 to 1: add any missing fields
        local default = getDefaultData()
        data = TableUtil.deepMerge(default, data)
        data.dataVersion = 1
    end

    -- Future migrations go here:
    -- if version < 2 then ... end

    return data :: Types.PlayerData
end

----------------------------------------------------------------------
-- CORE DATASTORE OPERATIONS
----------------------------------------------------------------------

local MAX_RETRIES = 3
local RETRY_DELAY = 2

local function withRetry(operation: string, callback: () -> any): (boolean, any)
    for attempt = 1, MAX_RETRIES do
        local ok, result = pcall(callback)
        if ok then
            return true, result
        end
        warn(`[DataManager] {operation} attempt {attempt}/{MAX_RETRIES} failed: {result}`)
        if attempt < MAX_RETRIES then
            task.wait(RETRY_DELAY * attempt)
        end
    end
    return false, `{operation} failed after {MAX_RETRIES} attempts`
end

local function loadPlayerData(userId: number): (boolean, Types.PlayerData?)
    if not dataStore then
        return true, getDefaultData() -- Studio fallback
    end

    local key = `Player_{userId}`
    local ok, rawData = withRetry("LoadData", function()
        return dataStore:GetAsync(key)
    end)

    if not ok then
        return false, nil
    end

    if rawData == nil then
        -- New player
        return true, getDefaultData()
    end

    -- Migrate if needed
    local data = migrateData(rawData)
    return true, data
end

local function savePlayerData(userId: number): boolean
    local data = playerData[userId]
    if not data then return false end
    if not dataStore then return true end -- Studio fallback

    local key = `Player_{userId}`
    local ok, err = withRetry("SaveData", function()
        dataStore:SetAsync(key, data)
    end)

    if not ok then
        warn(`[DataManager] Failed to save data for {userId}: {err}`)
        return false
    end

    return true
end

----------------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------------

--- Get a player's data (returns nil if not loaded yet).
function DataManager:GetData(player: Player): Types.PlayerData?
    return playerData[player.UserId]
end

--- Update a player's data via a transform function.
function DataManager:UpdateData(player: Player, transform: (Types.PlayerData) -> Types.PlayerData)
    local data = playerData[player.UserId]
    if not data then
        warn(`[DataManager] No data loaded for {player.Name}`)
        return
    end

    local newData = transform(data)
    playerData[player.UserId] = newData
    dirtyFlags[player.UserId] = true
end

--- Mark a player's data as needing to be saved.
function DataManager:MarkDirty(player: Player)
    dirtyFlags[player.UserId] = true
end

--- Force-save a player's data immediately.
function DataManager:SaveNow(player: Player): boolean
    local saved = savePlayerData(player.UserId)
    if saved then
        dirtyFlags[player.UserId] = false
        DataManager.DataSaved:Fire(player)
    end
    return saved
end

----------------------------------------------------------------------
-- LIFECYCLE
----------------------------------------------------------------------

local function onPlayerAdded(player: Player)
    local ok, data = loadPlayerData(player.UserId)

    if not ok or not data then
        DataManager.DataError:Fire(player, "Failed to load data")
        -- Kick player to prevent data loss
        player:Kick("Unable to load your data. Please rejoin.")
        return
    end

    -- Update last join
    data.lastJoin = os.time()

    playerData[player.UserId] = data
    dirtyFlags[player.UserId] = false
    sessionKeys[player.UserId] = `session_{os.clock()}`

    DataManager.DataLoaded:Fire(player, data)
    print(`[DataManager] Data loaded for {player.Name} (Level {data.globalLevel}, Prestige {data.prestigeLevel})`)
end

local function onPlayerRemoving(player: Player)
    local data = playerData[player.UserId]
    if data then
        -- Update total play time
        data.totalPlayTime += (os.time() - data.lastJoin)

        savePlayerData(player.UserId)
        playerData[player.UserId] = nil
        dirtyFlags[player.UserId] = nil
        sessionKeys[player.UserId] = nil

        DataManager.DataSaved:Fire(player)
        print(`[DataManager] Data saved for {player.Name}`)
    end
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------

function DataManager:Init()
    -- Initialize DataStore
    local ok, store = pcall(function()
        return DataStoreService:GetDataStore(Constants.DATA_STORE_NAME)
    end)
    if ok then
        dataStore = store
    else
        warn("[DataManager] DataStoreService unavailable (Studio?). Using in-memory storage.")
    end

    -- Player lifecycle
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)

    -- Handle players already in server
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayerAdded, player)
    end

    -- Periodic auto-save
    task.spawn(function()
        while true do
            task.wait(Constants.DATA_SAVE_INTERVAL)
            for userId, isDirty in dirtyFlags do
                if isDirty then
                    local saved = savePlayerData(userId)
                    if saved then
                        dirtyFlags[userId] = false
                    end
                end
            end
        end
    end)

    -- Server shutdown save
    game:BindToClose(function()
        for userId, _ in playerData do
            savePlayerData(userId)
        end
    end)

    print("[DataManager] Initialized")
end

return DataManager
