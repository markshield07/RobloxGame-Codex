--[[
    ScoreboardScreen.luau
    Post-mission scoreboard showing results, ratings, and rewards.

    Layout:
      - Mission status header (SUCCESS / FAILED + rating letter)
      - Team score
      - Player score table (rank, name, role, score, rescues)
      - Reward breakdown (XP, coins, tokens)
      - "Continue" button
]]

local function buildScoreboardScreen(): ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "Scoreboard"
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 30
    screenGui.Enabled = false

    -- Dark overlay
    local overlay = Instance.new("Frame")
    overlay.Name = "Overlay"
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    overlay.BackgroundTransparency = 0.3
    overlay.Parent = screenGui

    -- Main panel
    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.Size = UDim2.new(0, 600, 0, 500)
    panel.Position = UDim2.new(0.5, -300, 0.5, -250)
    panel.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
    panel.BorderSizePixel = 0
    panel.Parent = screenGui

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, 16)
    panelCorner.Parent = panel

    -- Mission status header
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusLabel"
    statusLabel.Size = UDim2.new(1, 0, 0, 50)
    statusLabel.Position = UDim2.new(0, 0, 0, 15)
    statusLabel.BackgroundTransparency = 1
    statusLabel.TextColor3 = Color3.fromRGB(46, 204, 113) -- green for success, red for fail
    statusLabel.Font = Enum.Font.GothamBold
    statusLabel.TextSize = 32
    statusLabel.Text = "MISSION COMPLETE"
    statusLabel.Parent = panel

    -- Rating display
    local ratingLabel = Instance.new("TextLabel")
    ratingLabel.Name = "RatingLabel"
    ratingLabel.Size = UDim2.new(0, 80, 0, 80)
    ratingLabel.Position = UDim2.new(0.5, -40, 0, 65)
    ratingLabel.BackgroundColor3 = Color3.fromRGB(241, 196, 15)
    ratingLabel.TextColor3 = Color3.fromRGB(20, 20, 30)
    ratingLabel.Font = Enum.Font.GothamBold
    ratingLabel.TextSize = 48
    ratingLabel.Text = "A"
    ratingLabel.Parent = panel

    local ratingCorner = Instance.new("UICorner")
    ratingCorner.CornerRadius = UDim.new(0.5, 0)
    ratingCorner.Parent = ratingLabel

    -- Team score
    local teamScoreLabel = Instance.new("TextLabel")
    teamScoreLabel.Name = "TeamScoreLabel"
    teamScoreLabel.Size = UDim2.new(1, 0, 0, 30)
    teamScoreLabel.Position = UDim2.new(0, 0, 0, 155)
    teamScoreLabel.BackgroundTransparency = 1
    teamScoreLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    teamScoreLabel.Font = Enum.Font.GothamMedium
    teamScoreLabel.TextSize = 18
    teamScoreLabel.Text = "Team Score: 0"
    teamScoreLabel.Parent = panel

    -- Player scores container
    local scoresContainer = Instance.new("Frame")
    scoresContainer.Name = "ScoresContainer"
    scoresContainer.Size = UDim2.new(0.9, 0, 0, 180)
    scoresContainer.Position = UDim2.new(0.05, 0, 0, 195)
    scoresContainer.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    scoresContainer.BorderSizePixel = 0
    scoresContainer.Parent = panel

    local scoresCorner = Instance.new("UICorner")
    scoresCorner.CornerRadius = UDim.new(0, 8)
    scoresCorner.Parent = scoresContainer

    -- Column headers
    local headers = { "Rank", "Player", "Role", "Score", "Rescues" }
    local widths = { 0.08, 0.32, 0.2, 0.2, 0.2 }
    local xPos = 0
    for i, header in headers do
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(widths[i], 0, 0, 25)
        label.Position = UDim2.new(xPos, 0, 0, 0)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.fromRGB(150, 150, 150)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 11
        label.Text = header
        label.Parent = scoresContainer
        xPos += widths[i]
    end

    -- Player rows will be populated dynamically by UIManager

    -- Rewards section
    local rewardsFrame = Instance.new("Frame")
    rewardsFrame.Name = "RewardsFrame"
    rewardsFrame.Size = UDim2.new(0.9, 0, 0, 60)
    rewardsFrame.Position = UDim2.new(0.05, 0, 0, 385)
    rewardsFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    rewardsFrame.BorderSizePixel = 0
    rewardsFrame.Parent = panel

    local rewCorner = Instance.new("UICorner")
    rewCorner.CornerRadius = UDim.new(0, 8)
    rewCorner.Parent = rewardsFrame

    local rewardLabels = {
        { name = "XPReward", text = "+0 XP", color = Color3.fromRGB(155, 89, 182), pos = 0 },
        { name = "CoinReward", text = "+0 Coins", color = Color3.fromRGB(241, 196, 15), pos = 0.33 },
        { name = "TokenReward", text = "+0 Tokens", color = Color3.fromRGB(52, 152, 219), pos = 0.66 },
    }

    for _, rew in rewardLabels do
        local label = Instance.new("TextLabel")
        label.Name = rew.name
        label.Size = UDim2.new(0.33, 0, 1, 0)
        label.Position = UDim2.new(rew.pos, 0, 0, 0)
        label.BackgroundTransparency = 1
        label.TextColor3 = rew.color
        label.Font = Enum.Font.GothamBold
        label.TextSize = 16
        label.Text = rew.text
        label.Parent = rewardsFrame
    end

    -- Continue button
    local continueButton = Instance.new("TextButton")
    continueButton.Name = "ContinueButton"
    continueButton.Size = UDim2.new(0, 180, 0, 45)
    continueButton.Position = UDim2.new(0.5, -90, 1, -55)
    continueButton.BackgroundColor3 = Color3.fromRGB(52, 152, 219)
    continueButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    continueButton.Font = Enum.Font.GothamBold
    continueButton.TextSize = 18
    continueButton.Text = "CONTINUE"
    continueButton.Parent = panel

    local contCorner = Instance.new("UICorner")
    contCorner.CornerRadius = UDim.new(0, 10)
    contCorner.Parent = continueButton

    return screenGui
end

return buildScoreboardScreen
