--[[
    EconomyManager.luau (Server)

    Manages all currency transactions, shop purchases, game pass validation,
    and reward distribution.

    Design:
      - All currency changes route through this module (single write path).
      - Purchase validation: check balance, level requirements, ownership.
      - Game pass ownership cached on join, re-checked via MarketplaceService.
      - Dev products (consumables) handled via ProcessReceipt callback.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Types = require(ReplicatedStorage.Shared.Modules.Types)
local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local EconomyManager = {}
EconomyManager.__index = EconomyManager

----------------------------------------------------------------------
-- SIGNALS
----------------------------------------------------------------------
EconomyManager.CurrencyChanged = Signal.new()    -- (player, currencyType, newBalance, delta)
EconomyManager.ItemPurchased = Signal.new()       -- (player, itemId)
EconomyManager.GamePassOwned = Signal.new()       -- (player, passId)

----------------------------------------------------------------------
-- REFERENCES
----------------------------------------------------------------------
local PlayerDataManager = nil
local NetworkManager = nil

----------------------------------------------------------------------
-- SHOP CATALOG
----------------------------------------------------------------------
-- In production, this would be loaded from a ModuleScript or DataStore for live-ops updates.

local shopCatalog: { Types.ShopItem } = {
    -- Equipment upgrades
    {
        itemId = "AdvancedMedKit",
        displayName = "Advanced Med Kit",
        description = "Heals 60% more per use",
        category = "Equipment",
        currencyType = "Coins",
        price = 500,
        requiredLevel = 5,
        requiredPrestige = nil,
        isLimitedTime = false,
        expiresAt = nil,
    },
    {
        itemId = "TitaniumBraces",
        displayName = "Titanium Braces",
        description = "Reinforcements last 2x longer",
        category = "Equipment",
        currencyType = "Coins",
        price = 750,
        requiredLevel = 8,
        requiredPrestige = nil,
        isLimitedTime = false,
        expiresAt = nil,
    },
    {
        itemId = "EliteK9Vest",
        displayName = "Elite K9 Vest",
        description = "Doubles K9 detection range",
        category = "Equipment",
        currencyType = "RescueTokens",
        price = 50,
        requiredLevel = 10,
        requiredPrestige = nil,
        isLimitedTime = false,
        expiresAt = nil,
    },
    -- Cosmetics
    {
        itemId = "GoldHelmet",
        displayName = "Gold Rescue Helmet",
        description = "A gleaming gold helmet for elite rescuers",
        category = "Cosmetic",
        currencyType = "RescueTokens",
        price = 100,
        requiredLevel = 15,
        requiredPrestige = 1,
        isLimitedTime = false,
        expiresAt = nil,
    },
    {
        itemId = "NeonUniform",
        displayName = "Neon Response Uniform",
        description = "High-visibility neon suit",
        category = "Cosmetic",
        currencyType = "Coins",
        price = 2000,
        requiredLevel = 20,
        requiredPrestige = nil,
        isLimitedTime = false,
        expiresAt = nil,
    },
    -- Boosts (consumable dev products)
    {
        itemId = "DoubleCoinsBoost",
        displayName = "2x Coins (1 Mission)",
        description = "Double coin rewards for your next mission",
        category = "Boost",
        currencyType = "PremiumGems",
        price = 25,
        requiredLevel = nil,
        requiredPrestige = nil,
        isLimitedTime = false,
        expiresAt = nil,
    },
}

----------------------------------------------------------------------
-- CURRENCY OPERATIONS
----------------------------------------------------------------------

--- Add currency to a player. Returns new balance.
function EconomyManager:AddCurrency(player: Player, currencyType: Types.CurrencyType, amount: number): number?
    if amount <= 0 then return nil end

    local newBalance = nil
    PlayerDataManager:UpdateData(player, function(d: Types.PlayerData)
        if currencyType == "Coins" then
            d.coins += amount
            d.totalCoinsEarned += amount
            newBalance = d.coins
        elseif currencyType == "RescueTokens" then
            d.rescueTokens += amount
            newBalance = d.rescueTokens
        elseif currencyType == "PremiumGems" then
            d.premiumGems += amount
            newBalance = d.premiumGems
        end
        return d
    end)

    if newBalance then
        EconomyManager.CurrencyChanged:Fire(player, currencyType, newBalance, amount)
    end
    return newBalance
end

--- Remove currency from a player. Returns true if successful (had enough).
function EconomyManager:RemoveCurrency(player: Player, currencyType: Types.CurrencyType, amount: number): boolean
    if amount <= 0 then return false end

    local success = false
    PlayerDataManager:UpdateData(player, function(d: Types.PlayerData)
        local balance
        if currencyType == "Coins" then balance = d.coins
        elseif currencyType == "RescueTokens" then balance = d.rescueTokens
        elseif currencyType == "PremiumGems" then balance = d.premiumGems
        else return d end

        if balance >= amount then
            if currencyType == "Coins" then d.coins -= amount
            elseif currencyType == "RescueTokens" then d.rescueTokens -= amount
            elseif currencyType == "PremiumGems" then d.premiumGems -= amount
            end
            success = true
        end
        return d
    end)

    if success then
        local data = PlayerDataManager:GetData(player)
        local newBalance = 0
        if data then
            if currencyType == "Coins" then newBalance = data.coins
            elseif currencyType == "RescueTokens" then newBalance = data.rescueTokens
            elseif currencyType == "PremiumGems" then newBalance = data.premiumGems
            end
        end
        EconomyManager.CurrencyChanged:Fire(player, currencyType, newBalance, -amount)
    end

    return success
end

--- Get a player's balance for a currency type.
function EconomyManager:GetBalance(player: Player, currencyType: Types.CurrencyType): number
    local data = PlayerDataManager:GetData(player)
    if not data then return 0 end
    if currencyType == "Coins" then return data.coins end
    if currencyType == "RescueTokens" then return data.rescueTokens end
    if currencyType == "PremiumGems" then return data.premiumGems end
    return 0
end

----------------------------------------------------------------------
-- SHOP PURCHASES
----------------------------------------------------------------------

--- Attempt to purchase a shop item. Returns success, error message.
function EconomyManager:PurchaseItem(player: Player, itemId: string): (boolean, string?)
    -- Find item
    local item = nil
    for _, shopItem in shopCatalog do
        if shopItem.itemId == itemId then
            item = shopItem
            break
        end
    end
    if not item then return false, "Item not found" end

    local data = PlayerDataManager:GetData(player)
    if not data then return false, "Data not loaded" end

    -- Check level requirement
    if item.requiredLevel and data.globalLevel < item.requiredLevel then
        return false, `Requires level {item.requiredLevel}`
    end

    -- Check prestige requirement
    if item.requiredPrestige and data.prestigeLevel < item.requiredPrestige then
        return false, `Requires prestige {item.requiredPrestige}`
    end

    -- Check limited time
    if item.isLimitedTime and item.expiresAt and os.time() > item.expiresAt then
        return false, "Item expired"
    end

    -- Check ownership (for non-consumables)
    if item.category ~= "Boost" then
        for _, eq in data.equipment do
            if eq.itemId == itemId then
                return false, "Already owned"
            end
        end
        if table.find(data.cosmetics, itemId) then
            return false, "Already owned"
        end
    end

    -- Deduct currency
    local deducted = self:RemoveCurrency(player, item.currencyType, item.price)
    if not deducted then
        return false, "Insufficient funds"
    end

    -- Grant item
    PlayerDataManager:UpdateData(player, function(d: Types.PlayerData)
        if item.category == "Equipment" then
            table.insert(d.equipment, {
                itemId = itemId,
                level = 1,
                equipped = false,
            })
        elseif item.category == "Cosmetic" then
            table.insert(d.cosmetics, itemId)
        elseif item.category == "Boost" then
            -- Boosts are session-based; store in a temporary list
            -- (simplified: just grant bonus coins next mission)
        end
        return d
    end)

    EconomyManager.ItemPurchased:Fire(player, itemId)
    print(`[EconomyManager] {player.Name} purchased {itemId}`)
    return true, nil
end

--- Get the shop catalog.
function EconomyManager:GetShopCatalog(): { Types.ShopItem }
    return shopCatalog
end

----------------------------------------------------------------------
-- GAME PASS HANDLING
----------------------------------------------------------------------

--- Check and cache game pass ownership for a player.
function EconomyManager:LoadGamePasses(player: Player)
    PlayerDataManager:UpdateData(player, function(d: Types.PlayerData)
        for passName, passConfig in Constants.GAME_PASSES do
            if passConfig.id > 0 then
                local ok, owns = pcall(function()
                    return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passConfig.id)
                end)
                if ok and owns and not table.find(d.gamePasses, passName) then
                    table.insert(d.gamePasses, passName)
                    EconomyManager.GamePassOwned:Fire(player, passName)
                end
            end
        end
        return d
    end)
end

--- Check if player owns a specific game pass.
function EconomyManager:HasGamePass(player: Player, passName: string): boolean
    local data = PlayerDataManager:GetData(player)
    if not data then return false end
    return table.find(data.gamePasses, passName) ~= nil
end

----------------------------------------------------------------------
-- DEV PRODUCT RECEIPT (Robux purchases)
----------------------------------------------------------------------

--- Set up MarketplaceService.ProcessReceipt callback.
local function setupProcessReceipt()
    MarketplaceService.ProcessReceipt = function(receiptInfo)
        local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
        if not player then
            return Enum.ProductPurchaseDecision.NotProcessedYet
        end

        -- Map product IDs to gem grants
        -- In production, use a lookup table of dev product IDs
        local productId = receiptInfo.ProductId
        local gemAmounts = {
            -- [PRODUCT_ID] = gems
            -- Fill in with real product IDs
        }

        local gems = gemAmounts[productId]
        if gems then
            EconomyManager:AddCurrency(player, "PremiumGems", gems)
            return Enum.ProductPurchaseDecision.PurchaseGranted
        end

        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------

function EconomyManager:Init(dependencies: {
    PlayerDataManager: any,
    NetworkManager: any,
})
    PlayerDataManager = dependencies.PlayerDataManager
    NetworkManager = dependencies.NetworkManager

    setupProcessReceipt()

    print("[EconomyManager] Initialized")
end

return EconomyManager
