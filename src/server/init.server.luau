--[[
    init.server.luau
    Server bootstrap script. Initializes all server-side systems in dependency order.

    Boot sequence:
      1. NetworkManager (creates remotes first so other systems can register handlers)
      2. PlayerDataManager (data layer must be ready before gameplay systems)
      3. EconomyManager, InventoryManager (depend on data layer)
      4. ProgressionManager (depends on data + economy)
      5. SquadManager (depends on network)
      6. DisasterManager (standalone)
      7. RescueManager (depends on network + disaster)
      8. GameManager (orchestrator, depends on everything)
      9. Wire up client->server event handlers
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------------------------------------------------------------
-- REQUIRE ALL MODULES
----------------------------------------------------------------------
local NetworkManager = require(script.Services.NetworkManager)
local PlayerDataManager = require(script.Data.PlayerDataManager)
local EconomyManager = require(script.Services.EconomyManager)
local InventoryManager = require(script.Services.InventoryManager)
local ProgressionManager = require(script.Services.ProgressionManager)
local SquadManager = require(script.Services.SquadManager)
local DisasterManager = require(script.Services.DisasterManager)
local RescueManager = require(script.Services.RescueManager)
local GameManager = require(script.Services.GameManager)

----------------------------------------------------------------------
-- INITIALIZE IN DEPENDENCY ORDER
----------------------------------------------------------------------
print("=== Rescue Squad Simulator: Server Boot ===")

-- Layer 0: Networking
NetworkManager:Init()

-- Layer 1: Data
PlayerDataManager:Init()

-- Layer 2: Economy / Inventory
EconomyManager:Init({
    PlayerDataManager = PlayerDataManager,
    NetworkManager = NetworkManager,
})

InventoryManager:Init({
    PlayerDataManager = PlayerDataManager,
    EconomyManager = EconomyManager,
})

-- Layer 3: Progression
ProgressionManager:Init({
    PlayerDataManager = PlayerDataManager,
    EconomyManager = EconomyManager,
    NetworkManager = NetworkManager,
})

-- Layer 4: Squad, Disaster
SquadManager:Init({
    NetworkManager = NetworkManager,
})

DisasterManager:Init()

-- Layer 5: Rescue (active gameplay)
RescueManager:Init({
    NetworkManager = NetworkManager,
    DisasterManager = DisasterManager,
})

-- Layer 6: Game orchestrator
GameManager:Init({
    SquadManager = SquadManager,
    DisasterManager = DisasterManager,
    RescueManager = RescueManager,
    ProgressionManager = ProgressionManager,
    NetworkManager = NetworkManager,
})

----------------------------------------------------------------------
-- WIRE UP CLIENT -> SERVER EVENT HANDLERS
----------------------------------------------------------------------

-- Player ready toggle
NetworkManager:OnClientEvent("PlayerReady", function(player, isReady)
    if type(isReady) ~= "boolean" then
        -- Support legacy payload format { ready = true }
        if type(isReady) == "table" then
            isReady = true
        else
            return
        end
    end
    SquadManager:SetPlayerReady(player, isReady)
end)

-- Role selection
NetworkManager:OnClientEvent("RoleSelected", function(player, data)
    local roleName = data
    if type(data) == "table" and data.role then
        roleName = data.role
    end
    local valid = NetworkManager.ValidateEnum(roleName, {
        "Medic", "Engineer", "K9Handler", "Pilot", "Diver", "Commander",
    })
    if not valid then return end
    SquadManager:SetPreferredRole(player, valid)
end)

-- Ability activation
NetworkManager:OnClientEvent("AbilityActivated", function(player, abilityId)
    if type(abilityId) ~= "string" then return end
    -- Route to RescueManager; abilities map to specialized interactions
    RescueManager:HandleInteraction(player, abilityId, "")
end)

-- Interaction requests (rescue, repair, heal, neutralize)
NetworkManager:OnClientEvent("InteractionRequest", function(player, actionTypeOrData, targetId)
    -- Support both (player, actionType, targetId) and (player, {actionType, targetId}) formats
    local actionType, target
    if type(actionTypeOrData) == "table" then
        actionType = actionTypeOrData.actionType
        target = actionTypeOrData.targetId
    else
        actionType = actionTypeOrData
        target = targetId
    end

    local validAction = NetworkManager.ValidateString(actionType, 50)
    local validTarget = NetworkManager.ValidateString(target, 100)
    if not validAction or not validTarget then return end
    RescueManager:HandleInteraction(player, validAction, validTarget)
end)

-- Squad invites
NetworkManager:OnClientEvent("SquadInviteSent", function(player, data)
    local targetPlayerId
    if type(data) == "table" and data.targetPlayerId then
        targetPlayerId = data.targetPlayerId
    elseif type(data) == "number" then
        targetPlayerId = data
    else
        return
    end

    local targetId = NetworkManager.ValidateNumber(targetPlayerId, 1, 2^53)
    if not targetId then return end
    local targetPlayer = game:GetService("Players"):GetPlayerByUserId(targetId)
    if not targetPlayer then return end
    local squad = SquadManager:GetPlayerSquad(player)
    if not squad then return end
    SquadManager:InviteToSquad(squad.squadId, targetPlayer)
end)

-- Squad invite response
NetworkManager:OnClientEvent("SquadInviteResponse", function(player, squadId, accepted)
    if type(squadId) ~= "string" or type(accepted) ~= "boolean" then return end
    if accepted then
        SquadManager:InviteToSquad(squadId, player)
    end
end)

-- Equipment changes
NetworkManager:OnClientEvent("EquipmentChanged", function(player, itemId, equipped)
    if type(itemId) ~= "string" or type(equipped) ~= "boolean" then return end
    InventoryManager:SetEquipped(player, itemId, equipped)
end)

-- Purchase requests
NetworkManager:OnClientEvent("PurchaseRequest", function(player, data)
    local itemId = data
    if type(data) == "table" and data.itemId then
        itemId = data.itemId
    end
    if type(itemId) ~= "string" then return end

    local success, err = EconomyManager:PurchaseItem(player, itemId)
    NetworkManager:FireClient(player, "NotificationPush", {
        title = success and "Purchase Complete!" or "Purchase Failed",
        message = success and `You bought {itemId}!` or (err or "Unknown error"),
        type = success and "Success" or "Error",
    })
end)

-- Settings changes
NetworkManager:OnClientEvent("SettingsChanged", function(player, settings)
    if type(settings) ~= "table" then return end
    PlayerDataManager:UpdateData(player, function(d)
        for key, value in settings do
            if d.settings[key] ~= nil and type(value) == type(d.settings[key]) then
                d.settings[key] = value
            end
        end
        return d
    end)
end)

----------------------------------------------------------------------
-- WIRE UP REMOTE FUNCTIONS (Client queries)
----------------------------------------------------------------------

NetworkManager:OnClientInvoke("GetPlayerData", function(player)
    local data = PlayerDataManager:GetData(player)
    if not data then return nil end
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

NetworkManager:OnClientInvoke("GetShopCatalog", function(_player)
    return EconomyManager:GetShopCatalog()
end)

NetworkManager:OnClientInvoke("GetSquadInfo", function(player)
    local squad = SquadManager:GetPlayerSquad(player)
    if not squad then return nil end
    return {
        squadId = squad.squadId,
        members = squad.members,
        leaderId = squad.leaderId,
    }
end)

----------------------------------------------------------------------
-- POST-BOOT: Handle player lifecycle
----------------------------------------------------------------------
game:GetService("Players").PlayerAdded:Connect(function(player)
    -- Wait for data to load, then process daily login and game passes
    PlayerDataManager.DataLoaded:Connect(function(p, _data)
        if p == player then
            ProgressionManager:AwardDailyLogin(player)
            EconomyManager:LoadGamePasses(player)
            -- Auto-enqueue for matchmaking after brief delay
            task.delay(2, function()
                if player.Parent then
                    SquadManager:EnqueuePlayer(player)
                end
            end)
        end
    end)
end)

print("=== Rescue Squad Simulator: Server Ready ===")
