--[[
    RoleSelectionMenu.luau
    Creates the role selection screen shown during matchmaking/lobby.
    Players pick their preferred role before the squad deploys.

    Layout:
      - 6 role cards in a 3x2 grid
      - Each card shows: icon, name, description, color accent
      - Selected role is highlighted; selection fires a RemoteEvent
      - "Ready" button at bottom
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Constants"))

local function createRoleCard(parent: Frame, roleName: string, config: any, index: number): TextButton
    local row = math.floor((index - 1) / 3)
    local col = (index - 1) % 3

    local card = Instance.new("TextButton")
    card.Name = `Role_{roleName}`
    card.Size = UDim2.new(0, 180, 0, 200)
    card.Position = UDim2.new(0, col * 195, 0, row * 215)
    card.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    card.BorderSizePixel = 0
    card.AutoButtonColor = true
    card.Text = ""
    card.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Name = "SelectionStroke"
    stroke.Color = config.color
    stroke.Thickness = 0 -- 3 when selected
    stroke.Parent = card

    -- Color accent bar at top
    local accent = Instance.new("Frame")
    accent.Name = "Accent"
    accent.Size = UDim2.new(1, 0, 0, 4)
    accent.BackgroundColor3 = config.color
    accent.BorderSizePixel = 0
    accent.Parent = card

    -- Role icon placeholder
    local iconFrame = Instance.new("Frame")
    iconFrame.Name = "IconFrame"
    iconFrame.Size = UDim2.new(0, 60, 0, 60)
    iconFrame.Position = UDim2.new(0.5, -30, 0, 20)
    iconFrame.BackgroundColor3 = config.color
    iconFrame.BackgroundTransparency = 0.7
    iconFrame.Parent = card

    local iconCorner = Instance.new("UICorner")
    iconCorner.CornerRadius = UDim.new(0.5, 0)
    iconCorner.Parent = iconFrame

    -- Role name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "RoleName"
    nameLabel.Size = UDim2.new(1, -10, 0, 25)
    nameLabel.Position = UDim2.new(0, 5, 0, 90)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = config.color
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 16
    nameLabel.Text = config.displayName
    nameLabel.Parent = card

    -- Description
    local descLabel = Instance.new("TextLabel")
    descLabel.Name = "Description"
    descLabel.Size = UDim2.new(1, -16, 0, 60)
    descLabel.Position = UDim2.new(0, 8, 0, 118)
    descLabel.BackgroundTransparency = 1
    descLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    descLabel.Font = Enum.Font.Gotham
    descLabel.TextSize = 11
    descLabel.TextWrapped = true
    descLabel.TextYAlignment = Enum.TextYAlignment.Top
    descLabel.Text = config.description
    descLabel.Parent = card

    -- Lock overlay for level-gated roles
    if config.unlockLevel > 1 then
        local lockOverlay = Instance.new("Frame")
        lockOverlay.Name = "LockOverlay"
        lockOverlay.Size = UDim2.new(1, 0, 1, 0)
        lockOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        lockOverlay.BackgroundTransparency = 0.6
        lockOverlay.ZIndex = 5
        lockOverlay.Parent = card

        local lockCorner = Instance.new("UICorner")
        lockCorner.CornerRadius = UDim.new(0, 12)
        lockCorner.Parent = lockOverlay

        local lockLabel = Instance.new("TextLabel")
        lockLabel.Size = UDim2.new(1, 0, 0, 30)
        lockLabel.Position = UDim2.new(0, 0, 0.5, -15)
        lockLabel.BackgroundTransparency = 1
        lockLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
        lockLabel.Font = Enum.Font.GothamBold
        lockLabel.TextSize = 14
        lockLabel.Text = `Unlock at Level {config.unlockLevel}`
        lockLabel.ZIndex = 6
        lockLabel.Parent = lockOverlay
    end

    return card
end

local function buildRoleSelectionMenu(): ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "RoleSelectionMenu"
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 20
    screenGui.Enabled = false

    -- Dark background overlay
    local overlay = Instance.new("Frame")
    overlay.Name = "Overlay"
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    overlay.BackgroundTransparency = 0.4
    overlay.Parent = screenGui

    -- Main panel
    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.Size = UDim2.new(0, 620, 0, 540)
    panel.Position = UDim2.new(0.5, -310, 0.5, -270)
    panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    panel.BorderSizePixel = 0
    panel.Parent = screenGui

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, 16)
    panelCorner.Parent = panel

    -- Title
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 40)
    title.Position = UDim2.new(0, 0, 0, 10)
    title.BackgroundTransparency = 1
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 24
    title.Text = "SELECT YOUR ROLE"
    title.Parent = panel

    -- Role cards container
    local cardsContainer = Instance.new("Frame")
    cardsContainer.Name = "Cards"
    cardsContainer.Size = UDim2.new(0, 585, 0, 430)
    cardsContainer.Position = UDim2.new(0.5, -292, 0, 55)
    cardsContainer.BackgroundTransparency = 1
    cardsContainer.Parent = panel

    -- Create role cards
    local selectedCard: TextButton? = nil
    local selectedRole: string? = nil
    local index = 0
    local roleOrder = { "Medic", "Engineer", "K9Handler", "Pilot", "Diver", "Commander" }

    for _, roleName in roleOrder do
        local config = Constants.ROLES[roleName]
        if not config then continue end
        index += 1

        local card = createRoleCard(cardsContainer, roleName, config, index)

        card.Activated:Connect(function()
            -- Check lock
            if config.unlockLevel > 1 then
                -- In production, check player level here
                -- For now, allow selection anyway
            end

            -- Deselect previous
            if selectedCard then
                local prevStroke = selectedCard:FindFirstChild("SelectionStroke")
                if prevStroke then prevStroke.Thickness = 0 end
            end

            -- Select new
            selectedCard = card
            selectedRole = roleName
            local stroke = card:FindFirstChild("SelectionStroke")
            if stroke then stroke.Thickness = 3 end

            -- Fire to server
            local remotes = ReplicatedStorage:FindFirstChild("GameRemotes")
            if remotes then
                local roleEvent = remotes:FindFirstChild("RoleSelected")
                if roleEvent then
                    roleEvent:FireServer(roleName)
                end
            end
        end)
    end

    -- Ready button
    local readyButton = Instance.new("TextButton")
    readyButton.Name = "ReadyButton"
    readyButton.Size = UDim2.new(0, 200, 0, 50)
    readyButton.Position = UDim2.new(0.5, -100, 1, -65)
    readyButton.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
    readyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    readyButton.Font = Enum.Font.GothamBold
    readyButton.TextSize = 20
    readyButton.Text = "READY UP"
    readyButton.Parent = panel

    local readyCorner = Instance.new("UICorner")
    readyCorner.CornerRadius = UDim.new(0, 10)
    readyCorner.Parent = readyButton

    local isReady = false
    readyButton.Activated:Connect(function()
        isReady = not isReady
        readyButton.Text = isReady and "CANCEL" or "READY UP"
        readyButton.BackgroundColor3 = isReady
            and Color3.fromRGB(231, 76, 60)
            or Color3.fromRGB(46, 204, 113)

        local remotes = ReplicatedStorage:FindFirstChild("GameRemotes")
        if remotes then
            local readyEvent = remotes:FindFirstChild("PlayerReady")
            if readyEvent then
                readyEvent:FireServer(isReady)
            end
        end
    end)

    return screenGui
end

return buildRoleSelectionMenu
