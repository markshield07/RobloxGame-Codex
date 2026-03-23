--[[
    HUDController.luau (Client)

    Manages all HUD elements: health bar, stamina bar, timer, objectives,
    score display, minimap indicators, notifications, and role info.

    Listens to NetworkController for server updates and reflects state in UI.
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HUDController = {}
HUDController.__index = HUDController

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local NetworkController = nil
local hudScreenGui: ScreenGui = nil

-- UI element references
local healthBar = nil
local staminaBar = nil
local timerLabel = nil
local objectivesList = nil
local scoreLabel = nil
local roleLabel = nil
local notificationFrame = nil
local phaseLabel = nil

----------------------------------------------------------------------
-- UI CREATION
----------------------------------------------------------------------

local function createColor(r, g, b): Color3
    return Color3.fromRGB(r, g, b)
end

local function createBar(parent: Frame, name: string, color: Color3, yOffset: number): { frame: Frame, fill: Frame, label: TextLabel }
    local container = Instance.new("Frame")
    container.Name = name
    container.Size = UDim2.new(0, 200, 0, 24)
    container.Position = UDim2.new(0, 15, 0, yOffset)
    container.BackgroundColor3 = createColor(30, 30, 30)
    container.BorderSizePixel = 0
    container.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = container

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.new(1, 0, 1, 0)
    fill.BackgroundColor3 = color
    fill.BorderSizePixel = 0
    fill.Parent = container

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 6)
    fillCorner.Parent = fill

    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = createColor(255, 255, 255)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Text = `{name}: 100/100`
    label.ZIndex = 2
    label.Parent = container

    return { frame = container, fill = fill, label = label }
end

local function buildHUD()
    hudScreenGui = Instance.new("ScreenGui")
    hudScreenGui.Name = "RescueHUD"
    hudScreenGui.ResetOnSpawn = false
    hudScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    hudScreenGui.Parent = playerGui

    -- Top-left: Health and Stamina bars
    local barsFrame = Instance.new("Frame")
    barsFrame.Name = "BarsFrame"
    barsFrame.Size = UDim2.new(0, 230, 0, 80)
    barsFrame.Position = UDim2.new(0, 0, 0, 0)
    barsFrame.BackgroundTransparency = 1
    barsFrame.Parent = hudScreenGui

    local healthData = createBar(barsFrame, "Health", createColor(231, 76, 60), 10)
    healthBar = healthData

    local staminaData = createBar(barsFrame, "Stamina", createColor(52, 152, 219), 42)
    staminaBar = staminaData

    -- Top-center: Phase and Timer
    local topCenter = Instance.new("Frame")
    topCenter.Name = "TopCenter"
    topCenter.Size = UDim2.new(0, 300, 0, 60)
    topCenter.Position = UDim2.new(0.5, -150, 0, 5)
    topCenter.BackgroundColor3 = createColor(20, 20, 20)
    topCenter.BackgroundTransparency = 0.3
    topCenter.BorderSizePixel = 0
    topCenter.Parent = hudScreenGui

    local tcCorner = Instance.new("UICorner")
    tcCorner.CornerRadius = UDim.new(0, 8)
    tcCorner.Parent = topCenter

    phaseLabel = Instance.new("TextLabel")
    phaseLabel.Name = "Phase"
    phaseLabel.Size = UDim2.new(1, 0, 0.5, 0)
    phaseLabel.BackgroundTransparency = 1
    phaseLabel.TextColor3 = createColor(255, 200, 50)
    phaseLabel.TextScaled = true
    phaseLabel.Font = Enum.Font.GothamBold
    phaseLabel.Text = "LOBBY"
    phaseLabel.Parent = topCenter

    timerLabel = Instance.new("TextLabel")
    timerLabel.Name = "Timer"
    timerLabel.Size = UDim2.new(1, 0, 0.5, 0)
    timerLabel.Position = UDim2.new(0, 0, 0.5, 0)
    timerLabel.BackgroundTransparency = 1
    timerLabel.TextColor3 = createColor(255, 255, 255)
    timerLabel.TextScaled = true
    timerLabel.Font = Enum.Font.GothamMedium
    timerLabel.Text = ""
    timerLabel.Parent = topCenter

    -- Top-right: Score and Role
    local topRight = Instance.new("Frame")
    topRight.Name = "TopRight"
    topRight.Size = UDim2.new(0, 200, 0, 60)
    topRight.Position = UDim2.new(1, -215, 0, 5)
    topRight.BackgroundColor3 = createColor(20, 20, 20)
    topRight.BackgroundTransparency = 0.3
    topRight.BorderSizePixel = 0
    topRight.Parent = hudScreenGui

    local trCorner = Instance.new("UICorner")
    trCorner.CornerRadius = UDim.new(0, 8)
    trCorner.Parent = topRight

    roleLabel = Instance.new("TextLabel")
    roleLabel.Name = "Role"
    roleLabel.Size = UDim2.new(1, 0, 0.5, 0)
    roleLabel.BackgroundTransparency = 1
    roleLabel.TextColor3 = createColor(46, 204, 113)
    roleLabel.TextScaled = true
    roleLabel.Font = Enum.Font.GothamBold
    roleLabel.Text = "MEDIC"
    roleLabel.Parent = topRight

    scoreLabel = Instance.new("TextLabel")
    scoreLabel.Name = "Score"
    scoreLabel.Size = UDim2.new(1, 0, 0.5, 0)
    scoreLabel.Position = UDim2.new(0, 0, 0.5, 0)
    scoreLabel.BackgroundTransparency = 1
    scoreLabel.TextColor3 = createColor(255, 255, 255)
    scoreLabel.TextScaled = true
    scoreLabel.Font = Enum.Font.GothamMedium
    scoreLabel.Text = "Score: 0"
    scoreLabel.Parent = topRight

    -- Right side: Objectives panel
    local objPanel = Instance.new("Frame")
    objPanel.Name = "ObjectivesPanel"
    objPanel.Size = UDim2.new(0, 250, 0, 300)
    objPanel.Position = UDim2.new(1, -265, 0, 80)
    objPanel.BackgroundColor3 = createColor(20, 20, 20)
    objPanel.BackgroundTransparency = 0.4
    objPanel.BorderSizePixel = 0
    objPanel.Parent = hudScreenGui

    local opCorner = Instance.new("UICorner")
    opCorner.CornerRadius = UDim.new(0, 8)
    opCorner.Parent = objPanel

    local objTitle = Instance.new("TextLabel")
    objTitle.Name = "Title"
    objTitle.Size = UDim2.new(1, 0, 0, 30)
    objTitle.BackgroundTransparency = 1
    objTitle.TextColor3 = createColor(255, 200, 50)
    objTitle.TextScaled = true
    objTitle.Font = Enum.Font.GothamBold
    objTitle.Text = "OBJECTIVES"
    objTitle.Parent = objPanel

    objectivesList = Instance.new("Frame")
    objectivesList.Name = "List"
    objectivesList.Size = UDim2.new(1, -10, 1, -35)
    objectivesList.Position = UDim2.new(0, 5, 0, 32)
    objectivesList.BackgroundTransparency = 1
    objectivesList.Parent = objPanel

    local listLayout = Instance.new("UIListLayout")
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 4)
    listLayout.Parent = objectivesList

    -- Bottom-center: Notification area
    notificationFrame = Instance.new("Frame")
    notificationFrame.Name = "Notifications"
    notificationFrame.Size = UDim2.new(0, 400, 0, 200)
    notificationFrame.Position = UDim2.new(0.5, -200, 1, -220)
    notificationFrame.BackgroundTransparency = 1
    notificationFrame.Parent = hudScreenGui

    local notifLayout = Instance.new("UIListLayout")
    notifLayout.SortOrder = Enum.SortOrder.LayoutOrder
    notifLayout.Padding = UDim.new(0, 5)
    notifLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    notifLayout.Parent = notificationFrame
end

----------------------------------------------------------------------
-- UI UPDATE FUNCTIONS
----------------------------------------------------------------------

local function updateBar(bar: any, current: number, max: number)
    if not bar then return end
    local ratio = math.clamp(current / max, 0, 1)
    local tween = TweenService:Create(bar.fill, TweenInfo.new(0.3), {
        Size = UDim2.new(ratio, 0, 1, 0),
    })
    tween:Play()
    bar.label.Text = `{bar.frame.Name}: {math.floor(current)}/{max}`
end

local function showNotification(message: string, color: Color3?, duration: number?)
    if not notificationFrame then return end

    local dur = duration or 3
    local col = color or createColor(255, 255, 255)

    local notif = Instance.new("TextLabel")
    notif.Size = UDim2.new(1, 0, 0, 30)
    notif.BackgroundColor3 = createColor(20, 20, 20)
    notif.BackgroundTransparency = 0.3
    notif.TextColor3 = col
    notif.TextScaled = true
    notif.Font = Enum.Font.GothamBold
    notif.Text = message
    notif.Parent = notificationFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = notif

    -- Fade out and remove
    task.delay(dur, function()
        local fadeOut = TweenService:Create(notif, TweenInfo.new(0.5), {
            BackgroundTransparency = 1,
            TextTransparency = 1,
        })
        fadeOut:Play()
        fadeOut.Completed:Wait()
        notif:Destroy()
    end)
end

local function updateObjective(data: any)
    if not objectivesList then return end

    local existing = objectivesList:FindFirstChild(data.objectiveId)
    if existing then
        local label = existing:FindFirstChild("Label")
        if label then
            label.Text = `{data.objectiveId}: {data.currentCount}/{data.targetCount}`
            if data.status == "Completed" then
                label.TextColor3 = createColor(46, 204, 113)
                label.Text = `✓ {label.Text}`
            end
        end
    else
        local objFrame = Instance.new("Frame")
        objFrame.Name = data.objectiveId
        objFrame.Size = UDim2.new(1, 0, 0, 24)
        objFrame.BackgroundTransparency = 1
        objFrame.Parent = objectivesList

        local label = Instance.new("TextLabel")
        label.Name = "Label"
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.TextColor3 = createColor(200, 200, 200)
        label.TextScaled = true
        label.Font = Enum.Font.GothamMedium
        label.Text = `{data.objectiveId}: {data.currentCount}/{data.targetCount}`
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = objFrame
    end
end

----------------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------------

function HUDController:Init(networkCtrl: any)
    NetworkController = networkCtrl
    buildHUD()

    -- Listen for server events
    NetworkController:OnServerEvent("GamePhaseChanged", function(data)
        if phaseLabel then
            phaseLabel.Text = string.upper(data.phase or "")
        end
    end)

    NetworkController:OnServerEvent("PlayerHealthChanged", function(data)
        if data.playerId == player.UserId then
            updateBar(healthBar, data.health, 100)
            if data.isDowned then
                showNotification("YOU ARE DOWN! Wait for revive...", createColor(231, 76, 60), 5)
            end
        end
    end)

    NetworkController:OnServerEvent("PlayerStaminaChanged", function(data)
        if data.playerId == player.UserId then
            updateBar(staminaBar, data.stamina, 100)
        end
    end)

    NetworkController:OnServerEvent("ScoreUpdated", function(data)
        if scoreLabel and data.playerId == player.UserId then
            scoreLabel.Text = `Score: {data.playerScore}`
        end
    end)

    NetworkController:OnServerEvent("ObjectiveUpdated", function(data)
        updateObjective(data)
        if data.status == "Completed" then
            showNotification(`Objective Complete: {data.objectiveId}`, createColor(46, 204, 113))
        end
    end)

    NetworkController:OnServerEvent("CivilianStateChanged", function(data)
        if data.isRescued then
            showNotification(`Civilian rescued by {data.rescuedBy}!`, createColor(52, 152, 219))
        end
    end)

    NetworkController:OnServerEvent("NotificationPush", function(data)
        local message = data.message or data.title or ""
        local color = data.type == "Error" and createColor(231, 76, 60)
            or data.type == "Reward" and createColor(255, 200, 50)
            or createColor(255, 255, 255)
        showNotification(message, color, 5)
    end)

    NetworkController:OnServerEvent("MissionResult", function(data)
        -- Clear objectives
        if objectivesList then
            for _, child in objectivesList:GetChildren() do
                if not child:IsA("UIListLayout") then
                    child:Destroy()
                end
            end
        end

        local resultColor = data.success and createColor(46, 204, 113) or createColor(231, 76, 60)
        local resultText = data.success and "MISSION SUCCESS!" or "MISSION FAILED"
        showNotification(`{resultText} Rating: {data.rating} | Score: {data.teamScore}`, resultColor, 8)
    end)

    NetworkController:OnServerEvent("SquadUpdated", function(data)
        -- Update role display
        if data.members then
            for _, member in data.members do
                if member.playerId == player.UserId and roleLabel then
                    roleLabel.Text = string.upper(member.role)
                end
            end
        end
    end)

    NetworkController:OnServerEvent("DisasterBriefing", function(data)
        showNotification(`INCOMING: {data.displayName}`, createColor(255, 100, 50), 8)
        showNotification(data.description, createColor(200, 200, 200), 8)
    end)

    print("[HUDController] Initialized")
end

return HUDController
