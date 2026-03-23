--[[
    InventoryManager.luau (Server)

    Manages player equipment loadouts, cosmetic equipping, and upgrade paths.

    Architecture:
      - Equipment: items with levels (upgradeable). Each role has 3 equipment slots.
      - Cosmetics: uniform, helmet, badge, emote slots.
      - Upgrades: spend coins to level up equipment (increases effectiveness).
      - Loadout validation: ensures equipped items match the player's role.

    All state is persisted via PlayerDataManager. This module provides
    the business logic layer.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Modules.Types)
local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local InventoryManager = {}
InventoryManager.__index = InventoryManager

----------------------------------------------------------------------
-- SIGNALS
----------------------------------------------------------------------
InventoryManager.EquipmentChanged = Signal.new()     -- (player, itemId, equipped)
InventoryManager.EquipmentUpgraded = Signal.new()    -- (player, itemId, newLevel)
InventoryManager.CosmeticEquipped = Signal.new()     -- (player, slot, itemId)

----------------------------------------------------------------------
-- REFERENCES
----------------------------------------------------------------------
local PlayerDataManager = nil
local EconomyManager = nil

----------------------------------------------------------------------
-- EQUIPMENT DEFINITIONS
----------------------------------------------------------------------

-- Max level and upgrade costs per item tier
local UPGRADE_COSTS = {
    -- level -> coin cost
    [1] = 0,       -- base (already owned)
    [2] = 200,
    [3] = 500,
    [4] = 1000,
    [5] = 2000,
    [6] = 4000,
    [7] = 7500,
    [8] = 12000,
    [9] = 18000,
    [10] = 30000,
}

local MAX_EQUIPMENT_LEVEL = 10

-- Which items are valid for which roles
local ROLE_EQUIPMENT: { [Types.Role]: { string } } = {
    Medic = { "MedKit", "Defibrillator", "Stretcher", "AdvancedMedKit", "SurgicalKit" },
    Engineer = { "JacksAndBraces", "CuttingTorch", "StructuralScanner", "TitaniumBraces", "PlasmaCutter" },
    K9Handler = { "K9Companion", "TrackingDevice", "ExtractionHarness", "EliteK9Vest", "SonarPinger" },
    Pilot = { "Helicopter", "WinchSystem", "WaterBucket", "JetEngine", "ThermalCamera" },
    Diver = { "DivingSuit", "UnderwaterCutter", "InflatableRaft", "RebreatherPro", "AquaJet" },
    Commander = { "TacticalRadio", "FlareGun", "SupplyDrop", "DroneRecon", "FieldHQ" },
}

----------------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------------

--- Get a player's inventory (equipment + cosmetics).
function InventoryManager:GetInventory(player: Player): { equipment: { Types.EquipmentData }, cosmetics: { string } }?
    local data = PlayerDataManager:GetData(player)
    if not data then return nil end
    return {
        equipment = data.equipment,
        cosmetics = data.cosmetics,
    }
end

--- Equip or unequip an equipment item.
function InventoryManager:SetEquipped(player: Player, itemId: string, equipped: boolean): (boolean, string?)
    local data = PlayerDataManager:GetData(player)
    if not data then return false, "Data not loaded" end

    -- Find the item in inventory
    local found = false
    for _, eq in data.equipment do
        if eq.itemId == itemId then
            found = true
            break
        end
    end
    if not found then return false, "Item not owned" end

    PlayerDataManager:UpdateData(player, function(d: Types.PlayerData)
        for _, eq in d.equipment do
            if eq.itemId == itemId then
                eq.equipped = equipped
                break
            end
        end
        return d
    end)

    InventoryManager.EquipmentChanged:Fire(player, itemId, equipped)
    return true, nil
end

--- Upgrade an equipment item to next level.
function InventoryManager:UpgradeEquipment(player: Player, itemId: string): (boolean, string?)
    local data = PlayerDataManager:GetData(player)
    if not data then return false, "Data not loaded" end

    local item = nil
    for _, eq in data.equipment do
        if eq.itemId == itemId then
            item = eq
            break
        end
    end
    if not item then return false, "Item not owned" end

    local nextLevel = item.level + 1
    if nextLevel > MAX_EQUIPMENT_LEVEL then
        return false, "Already max level"
    end

    local cost = UPGRADE_COSTS[nextLevel]
    if not cost then return false, "Invalid level" end

    -- Check and deduct cost
    local deducted = EconomyManager:RemoveCurrency(player, "Coins", cost)
    if not deducted then
        return false, `Insufficient coins (need {cost})`
    end

    PlayerDataManager:UpdateData(player, function(d: Types.PlayerData)
        for _, eq in d.equipment do
            if eq.itemId == itemId then
                eq.level = nextLevel
                break
            end
        end
        return d
    end)

    InventoryManager.EquipmentUpgraded:Fire(player, itemId, nextLevel)
    print(`[InventoryManager] {player.Name} upgraded {itemId} to level {nextLevel}`)
    return true, nil
end

--- Equip a cosmetic to a slot.
function InventoryManager:EquipCosmetic(
    player: Player,
    slot: "uniform" | "helmet" | "badge" | "emote",
    itemId: string?
): (boolean, string?)
    local data = PlayerDataManager:GetData(player)
    if not data then return false, "Data not loaded" end

    -- If equipping (not unequipping), verify ownership
    if itemId and not table.find(data.cosmetics, itemId) then
        return false, "Cosmetic not owned"
    end

    PlayerDataManager:UpdateData(player, function(d: Types.PlayerData)
        d.equippedCosmetics[slot] = itemId
        return d
    end)

    InventoryManager.CosmeticEquipped:Fire(player, slot, itemId)
    return true, nil
end

--- Get the list of equipped items for a player's current role.
function InventoryManager:GetLoadout(player: Player, role: Types.Role): { Types.EquipmentData }
    local data = PlayerDataManager:GetData(player)
    if not data then return {} end

    local validItems = ROLE_EQUIPMENT[role] or {}
    local loadout = {}

    for _, eq in data.equipment do
        if eq.equipped and table.find(validItems, eq.itemId) then
            table.insert(loadout, eq)
        end
    end

    return loadout
end

--- Validate that a player's loadout is legal for their role.
function InventoryManager:ValidateLoadout(player: Player, role: Types.Role): boolean
    local loadout = self:GetLoadout(player, role)
    -- Basic validation: max 3 equipment items per role
    return #loadout <= 3
end

--- Get upgrade cost for an item at a given level.
function InventoryManager:GetUpgradeCost(currentLevel: number): number?
    local nextLevel = currentLevel + 1
    return UPGRADE_COSTS[nextLevel]
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------

function InventoryManager:Init(dependencies: {
    PlayerDataManager: any,
    EconomyManager: any,
})
    PlayerDataManager = dependencies.PlayerDataManager
    EconomyManager = dependencies.EconomyManager

    print("[InventoryManager] Initialized")
end

return InventoryManager
