--[[
    UIManager.luau (Client)

    Central UI orchestrator. Manages screen states, HUD updates, menu transitions,
    and role-specific UI elements.

    Architecture:
      - Screen stack: only one "screen" active at a time (Lobby, Briefing, HUD, Scoreboard).
      - HUD is layered on top during Active phase.
      - All UI elements are created in StarterGui; this module shows/hides them.
      - Listens to server events (via Remotes) to update UI state.

    Role-specific UI:
      - Each role has unique ability buttons and info panels.
      - UIManager swaps ability bar contents based on assigned role.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Types = require(ReplicatedStorage.Shared.Modules.Types)
local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local UIManager = {}
UIManager.__index = UIManager

----------------------------------------------------------------------
-- SIGNALS (other client modules listen to these)
----------------------------------------------------------------------
UIManager.ScreenChanged = Signal.new()        -- (newScreen: string)
UIManager.RoleUILoaded = Signal.new()         -- (role: Role)

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local currentScreen: string = "Lobby"
local playerGui: PlayerGui = nil
local guiFolder = nil

-- Cached references to UI elements (populated on init)
local screens: { [string]: GuiObject } = {}
local hudElements: { [string]: GuiObject } = {}

----------------------------------------------------------------------
-- SCREEN MANAGEMENT
----------------------------------------------------------------------

--- Switch to a named screen. Hides all others.
function UIManager:SetScreen(screenName: string)
    for name, screen in screens do
        screen.Visible = (name == screenName)
    end
    local old = currentScreen
    currentScreen = screenName
    UIManager.ScreenChanged:Fire(screenName)
end

function UIManager:GetCurrentScreen(): string
    return currentScreen
end

----------------------------------------------------------------------
-- HUD UPDATES
----------------------------------------------------------------------

--- Update the health bar display.
function UIManager:UpdateHealth(current: number, max: number)
    local bar = hudElements.HealthBar
    if not bar then return end

    local fill = bar:FindFirstChild("Fill")
    if fill then
        local ratio = math.clamp(current / max, 0, 1)
        fill.Size = UDim2.new(ratio, 0, 1, 0)

        -- Color gradient: green -> yellow -> red
        if ratio > 0.5 then
            fill.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
        elseif ratio > 0.25 then
            fill.BackgroundColor3 = Color3.fromRGB(241, 196, 15)
        else
            fill.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
        end
    end

    local label = bar:FindFirstChild("Label")
    if label then
        label.Text = `{math.floor(current)}/{max}`
    end
end

--- Update the stamina bar display.
function UIManager:UpdateStamina(current: number, max: number)
    local bar = hudElements.StaminaBar
    if not bar then return end

    local fill = bar:FindFirstChild("Fill")
    if fill then
        fill.Size = UDim2.new(math.clamp(current / max, 0, 1), 0, 1, 0)
    end
end

--- Update the mission timer display.
function UIManager:UpdateTimer(timeRemaining: number)
    local timerLabel = hudElements.TimerLabel
    if not timerLabel then return end

    local minutes = math.floor(timeRemaining / 60)
    local seconds = math.floor(timeRemaining % 60)
    timerLabel.Text = string.format("%02d:%02d", minutes, seconds)

    -- Flash red when time is low
    if timeRemaining < 30 then
        timerLabel.TextColor3 = Color3.fromRGB(231, 76, 60)
    elseif timeRemaining < 60 then
        timerLabel.TextColor3 = Color3.fromRGB(241, 196, 15)
    else
        timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    end
end

--- Update the objectives panel.
function UIManager:UpdateObjectives(objectives: { { label: string, current: number, target: number, status: string } })
    local panel = hudElements.ObjectivesPanel
    if not panel then return end

    -- Clear existing entries
    for _, child in panel:GetChildren() do
        if child:IsA("Frame") and child.Name:match("^Objective_") then
            child:Destroy()
        end
    end

    -- Create entries
    for i, obj in objectives do
        local entry = Instance.new("Frame")
        entry.Name = `Objective_{i}`
        entry.Size = UDim2.new(1, 0, 0, 30)
        entry.Position = UDim2.new(0, 0, 0, (i - 1) * 35)
        entry.BackgroundTransparency = 0.8
        entry.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        entry.Parent = panel

        local label = Instance.new("TextLabel")
        label.Name = "Label"
        label.Size = UDim2.new(0.7, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.TextColor3 = obj.status == "Completed"
            and Color3.fromRGB(46, 204, 113)
            or Color3.fromRGB(255, 255, 255)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Font = Enum.Font.GothamBold
        label.TextSize = 14
        label.Text = obj.label
        label.Parent = entry

        local counter = Instance.new("TextLabel")
        counter.Name = "Counter"
        counter.Size = UDim2.new(0.3, 0, 1, 0)
        counter.Position = UDim2.new(0.7, 0, 0, 0)
        counter.BackgroundTransparency = 1
        counter.TextColor3 = Color3.fromRGB(200, 200, 200)
        counter.Font = Enum.Font.GothamMedium
        counter.TextSize = 14
        counter.Text = `{obj.current}/{obj.target}`
        counter.Parent = entry
    end
end

--- Update currency display in HUD.
function UIManager:UpdateCurrency(coins: number, rescueTokens: number)
    if hudElements.CoinsLabel then
        hudElements.CoinsLabel.Text = tostring(coins)
    end
    if hudElements.TokensLabel then
        hudElements.TokensLabel.Text = tostring(rescueTokens)
    end
end

--- Show a notification toast.
function UIManager:ShowNotification(title: string, message: string, duration: number?)
    local container = hudElements.NotificationContainer
    if not container then return end

    local toast = Instance.new("Frame")
    toast.Size = UDim2.new(0.3, 0, 0, 60)
    toast.Position = UDim2.new(0.35, 0, 0, -70)
    toast.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    toast.BackgroundTransparency = 0.1
    toast.Parent = container

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = toast

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -10, 0.4, 0)
    titleLabel.Position = UDim2.new(0, 5, 0, 5)
    titleLabel.BackgroundTransparency = 1
    titleLabel.TextColor3 = Color3.fromRGB(241, 196, 15)
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 16
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Text = title
    titleLabel.Parent = toast

    local msgLabel = Instance.new("TextLabel")
    msgLabel.Size = UDim2.new(1, -10, 0.5, 0)
    msgLabel.Position = UDim2.new(0, 5, 0.45, 0)
    msgLabel.BackgroundTransparency = 1
    msgLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    msgLabel.Font = Enum.Font.Gotham
    msgLabel.TextSize = 13
    msgLabel.TextXAlignment = Enum.TextXAlignment.Left
    msgLabel.Text = message
    msgLabel.Parent = toast

    -- Animate in
    toast:TweenPosition(UDim2.new(0.35, 0, 0, 10), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3)
    task.delay(duration or 4, function()
        toast:TweenPosition(UDim2.new(0.35, 0, 0, -70), Enum.EasingDirection.In, Enum.EasingStyle.Quad, 0.3)
        task.delay(0.4, function()
            toast:Destroy()
        end)
    end)
end

--- Load role-specific ability buttons into the HUD.
function UIManager:LoadRoleUI(role: Types.Role)
    local roleConfig = Constants.ROLES[role]
    if not roleConfig then return end

    local abilityBar = hudElements.AbilityBar
    if not abilityBar then return end

    -- Clear existing ability buttons
    for _, child in abilityBar:GetChildren() do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end

    -- Create ability buttons
    for i, ability in roleConfig.abilities do
        local button = Instance.new("TextButton")
        button.Name = `Ability_{ability.id}`
        button.Size = UDim2.new(0, 80, 0, 80)
        button.Position = UDim2.new(0, (i - 1) * 90, 0, 0)
        button.BackgroundColor3 = roleConfig.color
        button.TextColor3 = Color3.fromRGB(255, 255, 255)
        button.Font = Enum.Font.GothamBold
        button.TextSize = 12
        button.Text = ability.id
        button.Parent = abilityBar

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = button

        local cooldownOverlay = Instance.new("Frame")
        cooldownOverlay.Name = "CooldownOverlay"
        cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
        cooldownOverlay.Position = UDim2.new(0, 0, 1, 0)
        cooldownOverlay.AnchorPoint = Vector2.new(0, 1)
        cooldownOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        cooldownOverlay.BackgroundTransparency = 0.5
        cooldownOverlay.ZIndex = 2
        cooldownOverlay.Parent = button

        -- Button click fires ability event
        button.Activated:Connect(function()
            -- Client controller handles this
        end)
    end

    -- Update role indicator
    if hudElements.RoleIndicator then
        hudElements.RoleIndicator.Text = roleConfig.displayName
        hudElements.RoleIndicator.TextColor3 = roleConfig.color
    end

    UIManager.RoleUILoaded:Fire(role)
end

--- Show the scoreboard overlay with mission results.
function UIManager:ShowScoreboard(result: Types.MissionResultPayload)
    self:SetScreen("Scoreboard")

    -- Populate scoreboard (the GUI template handles layout)
    -- This dispatches data to the scoreboard ScreenGui
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------

function UIManager:Init()
    local localPlayer = Players.LocalPlayer
    playerGui = localPlayer:WaitForChild("PlayerGui")
    guiFolder = playerGui:WaitForChild("GUI", 10)

    -- Cache screen references (these correspond to ScreenGui children in StarterGui)
    -- In production these would be pre-built UI; here we reference by name
    if guiFolder then
        for _, child in guiFolder:GetChildren() do
            if child:IsA("ScreenGui") or child:IsA("Frame") then
                screens[child.Name] = child
            end
        end
    end

    -- Set up remote event listeners
    local remotes = ReplicatedStorage:WaitForChild("GameRemotes", 10)
    if remotes then
        local phaseEvent = remotes:FindFirstChild("GamePhaseChanged")
        if phaseEvent then
            phaseEvent.OnClientEvent:Connect(function(data)
                local phase = data.phase
                if phase == "Lobby" then
                    self:SetScreen("Lobby")
                elseif phase == "Briefing" then
                    self:SetScreen("Briefing")
                elseif phase == "Active" then
                    self:SetScreen("HUD")
                elseif phase == "Scoring" then
                    self:SetScreen("Scoreboard")
                end
            end)
        end

        local notifEvent = remotes:FindFirstChild("NotificationPush")
        if notifEvent then
            notifEvent.OnClientEvent:Connect(function(data)
                self:ShowNotification(data.title, data.message, data.duration)
            end)
        end

        local objEvent = remotes:FindFirstChild("ObjectiveUpdated")
        if objEvent then
            objEvent.OnClientEvent:Connect(function(data)
                -- Update specific objective in the HUD
                -- In production, maintain local objective state and re-render
            end)
        end

        local healthEvent = remotes:FindFirstChild("PlayerHealthChanged")
        if healthEvent then
            healthEvent.OnClientEvent:Connect(function(data)
                if data.playerId == localPlayer.UserId then
                    self:UpdateHealth(data.health, Constants.BASE_HEALTH)
                end
            end)
        end

        local resultEvent = remotes:FindFirstChild("MissionResult")
        if resultEvent then
            resultEvent.OnClientEvent:Connect(function(data)
                self:ShowScoreboard(data)
            end)
        end
    end

    self:SetScreen("Lobby")
    print("[UIManager] Initialized")
end

return UIManager
