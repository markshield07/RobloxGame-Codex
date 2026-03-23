--[[
    init.server.luau
    Server bootstrap script. Initializes all server modules in dependency order.
    This is the entry point for the server (placed in ServerScriptService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------------------------------------------------------------
-- Load all services
----------------------------------------------------------------------
local Services = script.Services
local DataManager = require(Services.DataManager)
local NetworkManager = require(Services.NetworkManager)
local SquadManager = require(Services.SquadManager)
local DisasterManager = require(Services.DisasterManager)
local RescueManager = require(Services.RescueManager)
local EconomyManager = require(Services.EconomyManager)
local ProgressionManager = require(Services.ProgressionManager)
local GameManager = require(Services.GameManager)

----------------------------------------------------------------------
-- Initialize in dependency order
----------------------------------------------------------------------
print("=== Rescue Squad Simulator Server Starting ===")

-- Layer 0: No dependencies
DataManager:Init()
NetworkManager:Init()
DisasterManager:Init()

-- Layer 1: Depends on NetworkManager
SquadManager:Init({ NetworkManager = NetworkManager })

-- Layer 2: Depends on NetworkManager + DisasterManager
RescueManager:Init({
    NetworkManager = NetworkManager,
    DisasterManager = DisasterManager,
})

-- Layer 3: Depends on DataManager + NetworkManager
EconomyManager:Init({
    PlayerDataManager = DataManager,
    NetworkManager = NetworkManager,
})

ProgressionManager:Init({
    PlayerDataManager = DataManager,
    EconomyManager = EconomyManager,
    NetworkManager = NetworkManager,
})

-- Layer 4: Top-level orchestrator
GameManager:Init({
    SquadManager = SquadManager,
    DisasterManager = DisasterManager,
    RescueManager = RescueManager,
    ProgressionManager = ProgressionManager,
    NetworkManager = NetworkManager,
})

----------------------------------------------------------------------
-- Register client-to-server event handlers
----------------------------------------------------------------------

NetworkManager:OnClientEvent("PlayerReady", function(player, data)
    SquadManager:SetPlayerReady(player, true)
end)

NetworkManager:OnClientEvent("RoleSelected", function(player, data)
    if data and data.role then
        SquadManager:SetPreferredRole(player, data.role)
    end
end)

NetworkManager:OnClientEvent("InteractionRequest", function(player, data)
    if data and data.actionType and data.targetId then
        RescueManager:HandleInteraction(player, data.actionType, data.targetId)
    end
end)

NetworkManager:OnClientEvent("SquadInviteSent", function(player, data)
    if data and data.targetPlayerId then
        local squad = SquadManager:GetPlayerSquad(player)
        if squad then
            local targetPlayer = game:GetService("Players"):GetPlayerByUserId(data.targetPlayerId)
            if targetPlayer then
                SquadManager:InviteToSquad(squad.squadId, targetPlayer)
            end
        end
    end
end)

NetworkManager:OnClientEvent("PurchaseRequest", function(player, data)
    if data and data.itemId then
        local success, err = EconomyManager:PurchaseItem(player, data.itemId)
        if not success then
            NetworkManager:FireClient(player, "NotificationPush", {
                type = "Error",
                message = err or "Purchase failed",
            })
        end
    end
end)

----------------------------------------------------------------------
-- Register RemoteFunction handlers
----------------------------------------------------------------------

NetworkManager:OnClientInvoke("GetPlayerData", function(player)
    local data = DataManager:GetData(player)
    if not data then return nil end
    -- Return a sanitized copy (exclude internal fields)
    return {
        globalLevel = data.globalLevel,
        globalXP = data.globalXP,
        prestigeLevel = data.prestigeLevel,
        coins = data.coins,
        rescueTokens = data.rescueTokens,
        premiumGems = data.premiumGems,
        roleStats = data.roleStats,
        equipment = data.equipment,
        cosmetics = data.cosmetics,
        equippedCosmetics = data.equippedCosmetics,
        totalMissions = data.totalMissions,
        totalRescues = data.totalRescues,
        dailyLoginStreak = data.dailyLoginStreak,
        settings = data.settings,
    }
end)

NetworkManager:OnClientInvoke("GetShopCatalog", function(player)
    return EconomyManager:GetShopCatalog()
end)

NetworkManager:OnClientInvoke("GetSquadInfo", function(player)
    local squad = SquadManager:GetPlayerSquad(player)
    if squad then
        return {
            squadId = squad.squadId,
            members = squad.members,
            leaderId = squad.leaderId,
        }
    end
    return nil
end)

----------------------------------------------------------------------
-- Auto-enqueue players when they join (for quick matchmaking demo)
----------------------------------------------------------------------
game:GetService("Players").PlayerAdded:Connect(function(player)
    -- Give DataManager time to load
    task.wait(2)
    -- Auto-claim daily reward
    ProgressionManager:AwardDailyLogin(player)
    -- Auto-enqueue for matchmaking
    SquadManager:EnqueuePlayer(player)
end)

print("=== Rescue Squad Simulator Server Ready ===")
