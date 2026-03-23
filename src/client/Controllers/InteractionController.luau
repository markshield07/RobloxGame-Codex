--[[
    InteractionController.luau (Client)

    Handles player interactions with game objects:
      - Proximity prompts for civilians, hazards, teammates
      - Ability activation via keybinds
      - Interaction UI (progress bars, prompts)
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local InteractionController = {}
InteractionController.__index = InteractionController

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local NetworkController = nil
local INTERACT_RANGE = 12  -- studs

----------------------------------------------------------------------
-- KEYBINDS
----------------------------------------------------------------------
local KEYBINDS = {
    Interact = Enum.KeyCode.E,
    Ability1 = Enum.KeyCode.Q,
    Ability2 = Enum.KeyCode.R,
    Sprint = Enum.KeyCode.LeftShift,
}

----------------------------------------------------------------------
-- PROXIMITY DETECTION
----------------------------------------------------------------------

local function getCharacterPosition(): Vector3?
    local char = player.Character
    if char then
        local root = char:FindFirstChild("HumanoidRootPart")
        if root then
            return root.Position
        end
    end
    return nil
end

local function findNearestInteractable(): (Instance?, string?, string?)
    local pos = getCharacterPosition()
    if not pos then return nil, nil, nil end

    local nearestDist = INTERACT_RANGE
    local nearestObj = nil
    local nearestAction = nil
    local nearestTargetId = nil

    -- Check civilians
    for _, civilian in CollectionService:GetTagged("Civilian") do
        if civilian:GetAttribute("IsRescued") then continue end
        local civPart = civilian.PrimaryPart or civilian:FindFirstChild("HumanoidRootPart")
        if civPart then
            local dist = (pos - civPart.Position).Magnitude
            if dist < nearestDist then
                nearestDist = dist
                nearestObj = civilian
                nearestAction = "RescueCivilian"
                nearestTargetId = civilian:GetAttribute("CivilianId")
            end
        end
    end

    -- Check hazard zones
    for _, hazard in CollectionService:GetTagged("HazardZone") do
        if hazard.Transparency >= 1 then continue end -- already neutralized
        local dist = (pos - hazard.Position).Magnitude
        local radius = hazard:GetAttribute("Radius") or 15
        if dist < radius + INTERACT_RANGE and dist < nearestDist then
            nearestDist = dist
            nearestObj = hazard
            nearestAction = "NeutralizeHazard"
            nearestTargetId = hazard:GetAttribute("HazardId")
        end
    end

    -- Check debris (for repair)
    for _, debris in CollectionService:GetTagged("Debris") do
        local dist = (pos - debris.Position).Magnitude
        if dist < nearestDist then
            nearestDist = dist
            nearestObj = debris
            nearestAction = "RepairStructure"
            nearestTargetId = debris.Name
        end
    end

    -- Check other players (for healing)
    for _, otherPlayer in Players:GetPlayers() do
        if otherPlayer == player then continue end
        local otherChar = otherPlayer.Character
        if otherChar then
            local otherRoot = otherChar:FindFirstChild("HumanoidRootPart")
            if otherRoot then
                local dist = (pos - otherRoot.Position).Magnitude
                if dist < nearestDist then
                    nearestDist = dist
                    nearestObj = otherChar
                    nearestAction = "HealTeammate"
                    nearestTargetId = tostring(otherPlayer.UserId)
                end
            end
        end
    end

    return nearestObj, nearestAction, nearestTargetId
end

----------------------------------------------------------------------
-- INTERACTION PROMPT UI
----------------------------------------------------------------------

local interactPrompt: BillboardGui? = nil
local currentTarget: Instance? = nil

local function showPrompt(target: Instance, actionText: string)
    if currentTarget == target and interactPrompt then return end

    hidePrompt()

    local adornee = nil
    if target:IsA("Model") then
        adornee = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
    elseif target:IsA("BasePart") then
        adornee = target
    end
    if not adornee then return end

    interactPrompt = Instance.new("BillboardGui")
    interactPrompt.Name = "InteractPrompt"
    interactPrompt.Size = UDim2.new(0, 150, 0, 50)
    interactPrompt.StudsOffset = Vector3.new(0, 3, 0)
    interactPrompt.AlwaysOnTop = true
    interactPrompt.Adornee = adornee
    interactPrompt.Parent = player.PlayerGui

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    label.BackgroundTransparency = 0.3
    label.TextColor3 = Color3.fromRGB(255, 255, 100)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Text = `[E] {actionText}`
    label.Parent = interactPrompt

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = label

    currentTarget = target
end

function hidePrompt()
    if interactPrompt then
        interactPrompt:Destroy()
        interactPrompt = nil
    end
    currentTarget = nil
end

----------------------------------------------------------------------
-- INPUT HANDLING
----------------------------------------------------------------------

local function onInputBegan(input: InputObject, gameProcessed: boolean)
    if gameProcessed then return end

    if input.KeyCode == KEYBINDS.Interact then
        local _, action, targetId = findNearestInteractable()
        if action and targetId then
            NetworkController:FireServer("InteractionRequest", {
                actionType = action,
                targetId = targetId,
            })
        end
    elseif input.KeyCode == KEYBINDS.Ability1 then
        -- K9Search or HealBurst (role-specific ability 1)
        NetworkController:FireServer("AbilityActivated", {
            abilitySlot = 1,
        })
    elseif input.KeyCode == KEYBINDS.Ability2 then
        -- Triage or Reinforce (role-specific ability 2)
        NetworkController:FireServer("AbilityActivated", {
            abilitySlot = 2,
        })
    end
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------

function InteractionController:Init(networkCtrl: any)
    NetworkController = networkCtrl

    UserInputService.InputBegan:Connect(onInputBegan)

    -- Proximity detection loop
    RunService.Heartbeat:Connect(function()
        local target, action, _ = findNearestInteractable()
        if target and action then
            local actionLabels = {
                RescueCivilian = "Rescue Civilian",
                NeutralizeHazard = "Neutralize Hazard",
                RepairStructure = "Repair Structure",
                HealTeammate = "Heal Teammate",
                K9Search = "K9 Search",
            }
            showPrompt(target, actionLabels[action] or action)
        else
            hidePrompt()
        end
    end)

    print("[InteractionController] Initialized")
end

return InteractionController
