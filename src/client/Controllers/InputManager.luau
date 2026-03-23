--[[
    InputManager.luau (Client)

    Handles all player input: keyboard, mouse, touch, gamepad.
    Maps inputs to actions, handles role-specific bindings, and communicates
    with the server via RemoteEvents.

    Architecture:
      - Action-based input system (not raw key checks).
      - Bindings are remappable and role-aware.
      - Touch support: virtual joystick + action buttons for mobile.
      - All interactions validated client-side (distance, cooldown) before
        sending to server. Server re-validates authoritatively.
]]

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Types = require(ReplicatedStorage.Shared.Modules.Types)
local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local InputManager = {}
InputManager.__index = InputManager

----------------------------------------------------------------------
-- SIGNALS
----------------------------------------------------------------------
InputManager.ActionTriggered = Signal.new()     -- (actionName: string)
InputManager.InteractionRequested = Signal.new() -- (targetId: string, actionType: string)
InputManager.AbilityActivated = Signal.new()    -- (abilityId: string)

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local currentRole: Types.Role? = nil
local isInteracting: boolean = false
local interactionTarget: Instance? = nil
local interactionPromptActive: boolean = false
local abilityCooldowns: { [string]: number } = {} -- abilityId -> available_at

local remotes = nil
local localPlayer = Players.LocalPlayer

----------------------------------------------------------------------
-- DEFAULT KEY BINDINGS
----------------------------------------------------------------------

local KEY_BINDINGS = {
    Interact = { Enum.KeyCode.E, Enum.KeyCode.ButtonX },
    Ability1 = { Enum.KeyCode.Q, Enum.KeyCode.ButtonL1 },
    Ability2 = { Enum.KeyCode.R, Enum.KeyCode.ButtonR1 },
    Sprint = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3 },
    Ping = { Enum.KeyCode.Z, Enum.KeyCode.DPadUp },
    OpenMenu = { Enum.KeyCode.Tab, Enum.KeyCode.ButtonSelect },
}

----------------------------------------------------------------------
-- INTERACTION DETECTION
----------------------------------------------------------------------

--- Cast a ray from the camera to find interactable objects within range.
local function findInteractionTarget(): (Instance?, string?)
    local character = localPlayer.Character
    if not character then return nil, nil end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return nil, nil end

    local maxRange = 12 -- studs

    -- Check for nearby tagged objects
    local CollectionService = game:GetService("CollectionService")

    -- Check civilians
    for _, civilian in CollectionService:GetTagged("Civilian") do
        if civilian:IsA("Model") and civilian.PrimaryPart then
            local dist = (rootPart.Position - civilian.PrimaryPart.Position).Magnitude
            if dist <= maxRange and not civilian:GetAttribute("IsRescued") then
                return civilian, "RescueCivilian"
            end
        end
    end

    -- Check hazard zones (interact at edge)
    for _, hazard in CollectionService:GetTagged("HazardZone") do
        if hazard:IsA("BasePart") then
            local dist = (rootPart.Position - hazard.Position).Magnitude
            local radius = hazard:GetAttribute("Radius") or 15
            if dist <= radius + 5 then
                return hazard, "NeutralizeHazard"
            end
        end
    end

    -- Check debris (repair)
    for _, debris in CollectionService:GetTagged("Debris") do
        if debris:IsA("BasePart") then
            local dist = (rootPart.Position - debris.Position).Magnitude
            if dist <= maxRange then
                return debris, "RepairStructure"
            end
        end
    end

    -- Check nearby players (heal)
    for _, player in Players:GetPlayers() do
        if player ~= localPlayer and player.Character then
            local otherRoot = player.Character:FindFirstChild("HumanoidRootPart")
            if otherRoot then
                local dist = (rootPart.Position - otherRoot.Position).Magnitude
                if dist <= maxRange then
                    return player.Character, "HealTeammate"
                end
            end
        end
    end

    return nil, nil
end

----------------------------------------------------------------------
-- ACTION HANDLERS
----------------------------------------------------------------------

local function handleInteract(_actionName, inputState, _inputObject)
    if inputState ~= Enum.UserInputState.Begin then return end

    local target, actionType = findInteractionTarget()
    if not target or not actionType then return end

    -- Get target ID
    local targetId = nil
    if actionType == "RescueCivilian" then
        targetId = target:GetAttribute("CivilianId")
    elseif actionType == "NeutralizeHazard" then
        targetId = target:GetAttribute("HazardId")
    elseif actionType == "RepairStructure" then
        targetId = target.Name
    elseif actionType == "HealTeammate" then
        local humanoid = target:FindFirstChildOfClass("Humanoid")
        local targetPlayer = Players:GetPlayerFromCharacter(target)
        targetId = targetPlayer and tostring(targetPlayer.UserId)
    end

    if not targetId then return end

    -- Fire to server
    if remotes then
        local interactRemote = remotes:FindFirstChild("InteractionRequest")
        if interactRemote then
            interactRemote:FireServer(actionType, targetId)
        end
    end

    InputManager.InteractionRequested:Fire(targetId, actionType)
end

local function handleAbility(abilityIndex: number)
    if not currentRole then return end

    local roleConfig = Constants.ROLES[currentRole]
    if not roleConfig then return end

    local ability = roleConfig.abilities[abilityIndex]
    if not ability then return end

    -- Client-side cooldown check
    local now = os.clock()
    if abilityCooldowns[ability.id] and now < abilityCooldowns[ability.id] then
        return -- still on cooldown
    end

    -- Set client-side cooldown
    abilityCooldowns[ability.id] = now + ability.cooldown

    -- Fire to server
    if remotes then
        local abilityRemote = remotes:FindFirstChild("AbilityActivated")
        if abilityRemote then
            abilityRemote:FireServer(ability.id)
        end
    end

    InputManager.AbilityActivated:Fire(ability.id)
end

local function handleAbility1(_actionName, inputState, _inputObject)
    if inputState == Enum.UserInputState.Begin then
        handleAbility(1)
    end
end

local function handleAbility2(_actionName, inputState, _inputObject)
    if inputState == Enum.UserInputState.Begin then
        handleAbility(2)
    end
end

local function handleSprint(_actionName, inputState, _inputObject)
    local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    if inputState == Enum.UserInputState.Begin then
        humanoid.WalkSpeed = 24  -- sprint speed
    elseif inputState == Enum.UserInputState.End then
        humanoid.WalkSpeed = 16  -- normal speed
    end
end

----------------------------------------------------------------------
-- INTERACTION PROMPT (proximity-based UI hint)
----------------------------------------------------------------------

local interactionPrompt: BillboardGui? = nil

local function updateInteractionPrompt()
    while true do
        local target, actionType = findInteractionTarget()

        if target and actionType then
            if not interactionPrompt then
                interactionPrompt = Instance.new("BillboardGui")
                interactionPrompt.Size = UDim2.new(0, 150, 0, 40)
                interactionPrompt.StudsOffset = Vector3.new(0, 3, 0)
                interactionPrompt.AlwaysOnTop = true

                local label = Instance.new("TextLabel")
                label.Name = "PromptLabel"
                label.Size = UDim2.new(1, 0, 1, 0)
                label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                label.BackgroundTransparency = 0.4
                label.TextColor3 = Color3.fromRGB(255, 255, 255)
                label.Font = Enum.Font.GothamBold
                label.TextSize = 16
                label.Parent = interactionPrompt

                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 6)
                corner.Parent = label
            end

            local promptText = {
                RescueCivilian = "[E] Rescue",
                NeutralizeHazard = "[E] Neutralize",
                RepairStructure = "[E] Repair",
                HealTeammate = "[E] Heal",
                K9Search = "[E] Search",
            }

            local label = interactionPrompt:FindFirstChild("PromptLabel")
            if label then
                label.Text = promptText[actionType] or "[E] Interact"
            end

            local adornee = if target:IsA("Model") then target.PrimaryPart else target
            interactionPrompt.Adornee = adornee
            interactionPrompt.Parent = adornee
            interactionPromptActive = true
        else
            if interactionPrompt then
                interactionPrompt.Parent = nil
            end
            interactionPromptActive = false
        end

        task.wait(0.15) -- update 6-7 times per second
    end
end

----------------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------------

--- Set the current role (changes available abilities and bindings).
function InputManager:SetRole(role: Types.Role)
    currentRole = role
    abilityCooldowns = {}
    print(`[InputManager] Role set to: {role}`)
end

--- Get remaining cooldown for an ability (in seconds).
function InputManager:GetAbilityCooldown(abilityId: string): number
    local available = abilityCooldowns[abilityId]
    if not available then return 0 end
    return math.max(0, available - os.clock())
end

--- Check if the player is on mobile/touch device.
function InputManager:IsTouchDevice(): boolean
    return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------

function InputManager:Init()
    remotes = ReplicatedStorage:WaitForChild("GameRemotes", 10)

    -- Bind actions
    ContextActionService:BindAction("Interact", handleInteract, false, table.unpack(KEY_BINDINGS.Interact))
    ContextActionService:BindAction("Ability1", handleAbility1, false, table.unpack(KEY_BINDINGS.Ability1))
    ContextActionService:BindAction("Ability2", handleAbility2, false, table.unpack(KEY_BINDINGS.Ability2))
    ContextActionService:BindAction("Sprint", handleSprint, false, table.unpack(KEY_BINDINGS.Sprint))

    -- Create touch buttons for mobile
    if self:IsTouchDevice() then
        ContextActionService:SetPosition("Interact", UDim2.new(0.8, 0, 0.5, 0))
        ContextActionService:SetPosition("Ability1", UDim2.new(0.7, 0, 0.6, 0))
        ContextActionService:SetPosition("Ability2", UDim2.new(0.9, 0, 0.6, 0))
    end

    -- Start interaction prompt loop
    task.spawn(updateInteractionPrompt)

    -- Listen for role assignment from server
    if remotes then
        local squadEvent = remotes:FindFirstChild("SquadUpdated")
        if squadEvent then
            squadEvent.OnClientEvent:Connect(function(data)
                for _, member in data.members do
                    if member.playerId == localPlayer.UserId then
                        self:SetRole(member.role)
                        break
                    end
                end
            end)
        end
    end

    print("[InputManager] Initialized")
end

return InputManager
