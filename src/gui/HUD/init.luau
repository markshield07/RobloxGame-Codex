--[[
    HUD/init.luau
    Programmatic HUD construction for the in-mission interface.

    Creates:
      - Health/Stamina bars (top-left)
      - Timer (top-center)
      - Objectives panel (right side)
      - Ability bar (bottom-center)
      - Role indicator (bottom-left)
      - Currency display (top-right)
      - Minimap frame (bottom-right, placeholder)
      - Notification container (top-center, below timer)

    All elements are returned as a ScreenGui so UIManager can show/hide the whole thing.
    In production, these would be designed in a UI tool and exported; this code
    provides the functional skeleton.
]]

local Constants = nil -- loaded lazily to avoid require loops in StarterGui

local function createBar(parent: Frame, name: string, color: Color3, position: UDim2): Frame
    local bar = Instance.new("Frame")
    bar.Name = name
    bar.Size = UDim2.new(0, 200, 0, 20)
    bar.Position = position
    bar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    bar.BorderSizePixel = 0
    bar.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = bar

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.new(1, 0, 1, 0)
    fill.BackgroundColor3 = color
    fill.BorderSizePixel = 0
    fill.Parent = bar

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 6)
    fillCorner.Parent = fill

    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 12
    label.Text = "100/100"
    label.ZIndex = 3
    label.Parent = bar

    return bar
end

local function buildHUD(): ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "HUD"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = false
    screenGui.DisplayOrder = 10
    screenGui.Enabled = false -- UIManager controls visibility

    local container = Instance.new("Frame")
    container.Name = "Container"
    container.Size = UDim2.new(1, 0, 1, 0)
    container.BackgroundTransparency = 1
    container.Parent = screenGui

    ----------------------------------------------------------------
    -- HEALTH & STAMINA (top-left)
    ----------------------------------------------------------------
    local healthBar = createBar(container, "HealthBar", Color3.fromRGB(46, 204, 113), UDim2.new(0, 15, 0, 15))
    local staminaBar = createBar(container, "StaminaBar", Color3.fromRGB(52, 152, 219), UDim2.new(0, 15, 0, 42))
    staminaBar.Size = UDim2.new(0, 160, 0, 14)

    ----------------------------------------------------------------
    -- ROLE INDICATOR (below health)
    ----------------------------------------------------------------
    local roleIndicator = Instance.new("TextLabel")
    roleIndicator.Name = "RoleIndicator"
    roleIndicator.Size = UDim2.new(0, 200, 0, 25)
    roleIndicator.Position = UDim2.new(0, 15, 0, 62)
    roleIndicator.BackgroundTransparency = 1
    roleIndicator.TextColor3 = Color3.fromRGB(255, 255, 255)
    roleIndicator.Font = Enum.Font.GothamBold
    roleIndicator.TextSize = 16
    roleIndicator.TextXAlignment = Enum.TextXAlignment.Left
    roleIndicator.Text = "MEDIC"
    roleIndicator.Parent = container

    ----------------------------------------------------------------
    -- TIMER (top-center)
    ----------------------------------------------------------------
    local timerFrame = Instance.new("Frame")
    timerFrame.Name = "TimerFrame"
    timerFrame.Size = UDim2.new(0, 120, 0, 45)
    timerFrame.Position = UDim2.new(0.5, -60, 0, 10)
    timerFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    timerFrame.BackgroundTransparency = 0.3
    timerFrame.Parent = container

    local timerCorner = Instance.new("UICorner")
    timerCorner.CornerRadius = UDim.new(0, 8)
    timerCorner.Parent = timerFrame

    local timerLabel = Instance.new("TextLabel")
    timerLabel.Name = "TimerLabel"
    timerLabel.Size = UDim2.new(1, 0, 1, 0)
    timerLabel.BackgroundTransparency = 1
    timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    timerLabel.Font = Enum.Font.GothamBold
    timerLabel.TextSize = 28
    timerLabel.Text = "05:00"
    timerLabel.Parent = timerFrame

    ----------------------------------------------------------------
    -- CURRENCY DISPLAY (top-right)
    ----------------------------------------------------------------
    local currencyFrame = Instance.new("Frame")
    currencyFrame.Name = "CurrencyFrame"
    currencyFrame.Size = UDim2.new(0, 180, 0, 50)
    currencyFrame.Position = UDim2.new(1, -195, 0, 10)
    currencyFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    currencyFrame.BackgroundTransparency = 0.3
    currencyFrame.Parent = container

    local currCorner = Instance.new("UICorner")
    currCorner.CornerRadius = UDim.new(0, 8)
    currCorner.Parent = currencyFrame

    local coinsLabel = Instance.new("TextLabel")
    coinsLabel.Name = "CoinsLabel"
    coinsLabel.Size = UDim2.new(1, -10, 0.5, 0)
    coinsLabel.Position = UDim2.new(0, 5, 0, 0)
    coinsLabel.BackgroundTransparency = 1
    coinsLabel.TextColor3 = Color3.fromRGB(241, 196, 15)
    coinsLabel.Font = Enum.Font.GothamBold
    coinsLabel.TextSize = 14
    coinsLabel.TextXAlignment = Enum.TextXAlignment.Right
    coinsLabel.Text = "0"
    coinsLabel.Parent = currencyFrame

    local tokensLabel = Instance.new("TextLabel")
    tokensLabel.Name = "TokensLabel"
    tokensLabel.Size = UDim2.new(1, -10, 0.5, 0)
    tokensLabel.Position = UDim2.new(0, 5, 0.5, 0)
    tokensLabel.BackgroundTransparency = 1
    tokensLabel.TextColor3 = Color3.fromRGB(52, 152, 219)
    tokensLabel.Font = Enum.Font.GothamBold
    tokensLabel.TextSize = 14
    tokensLabel.TextXAlignment = Enum.TextXAlignment.Right
    tokensLabel.Text = "0"
    tokensLabel.Parent = currencyFrame

    ----------------------------------------------------------------
    -- OBJECTIVES PANEL (right side)
    ----------------------------------------------------------------
    local objectivesPanel = Instance.new("ScrollingFrame")
    objectivesPanel.Name = "ObjectivesPanel"
    objectivesPanel.Size = UDim2.new(0, 260, 0, 250)
    objectivesPanel.Position = UDim2.new(1, -275, 0, 70)
    objectivesPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    objectivesPanel.BackgroundTransparency = 0.4
    objectivesPanel.ScrollBarThickness = 4
    objectivesPanel.CanvasSize = UDim2.new(0, 0, 0, 400)
    objectivesPanel.Parent = container

    local objCorner = Instance.new("UICorner")
    objCorner.CornerRadius = UDim.new(0, 8)
    objCorner.Parent = objectivesPanel

    local objTitle = Instance.new("TextLabel")
    objTitle.Name = "Title"
    objTitle.Size = UDim2.new(1, -10, 0, 25)
    objTitle.Position = UDim2.new(0, 5, 0, 5)
    objTitle.BackgroundTransparency = 1
    objTitle.TextColor3 = Color3.fromRGB(241, 196, 15)
    objTitle.Font = Enum.Font.GothamBold
    objTitle.TextSize = 15
    objTitle.TextXAlignment = Enum.TextXAlignment.Left
    objTitle.Text = "OBJECTIVES"
    objTitle.Parent = objectivesPanel

    ----------------------------------------------------------------
    -- ABILITY BAR (bottom-center)
    ----------------------------------------------------------------
    local abilityBar = Instance.new("Frame")
    abilityBar.Name = "AbilityBar"
    abilityBar.Size = UDim2.new(0, 200, 0, 80)
    abilityBar.Position = UDim2.new(0.5, -100, 1, -100)
    abilityBar.BackgroundTransparency = 1
    abilityBar.Parent = container

    ----------------------------------------------------------------
    -- NOTIFICATION CONTAINER (top-center, below timer)
    ----------------------------------------------------------------
    local notificationContainer = Instance.new("Frame")
    notificationContainer.Name = "NotificationContainer"
    notificationContainer.Size = UDim2.new(1, 0, 0, 80)
    notificationContainer.Position = UDim2.new(0, 0, 0, 60)
    notificationContainer.BackgroundTransparency = 1
    notificationContainer.ClipsDescendants = true
    notificationContainer.Parent = container

    return screenGui
end

return buildHUD
