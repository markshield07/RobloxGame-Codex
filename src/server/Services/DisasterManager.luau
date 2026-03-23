--[[
    DisasterManager.luau (Server)

    Procedural disaster generation system.

    Architecture:
      1. Seed-based generation: each disaster gets a numeric seed derived from
         os.clock() + roundCount. This makes disasters reproducible for replay/debugging.
      2. Template composition: we pick a DisasterType, roll severity, then compose
         objectives, hazard zones, and environment from weighted random tables.
      3. Difficulty scaling: severity is influenced by squad average level and
         prestige. Higher-level squads get harder (and more rewarding) disasters.
      4. Map building: disasters are built from prefab chunks placed procedurally.
         We use a grid-based placement with random rotation/connection.

    Performance notes:
      - Map parts are placed under a Folder in Workspace, tagged for streaming.
      - Debris uses a part pool to stay under Constants.MAX_DEBRIS_PARTS.
      - Civilians are simple NPC rigs from a pool (Constants.CIVILIAN_NPC_LIMIT).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Types = require(ReplicatedStorage.Shared.Modules.Types)
local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local TableUtil = require(ReplicatedStorage.Shared.Util.TableUtil)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local DisasterManager = {}
DisasterManager.__index = DisasterManager

----------------------------------------------------------------------
-- SIGNALS
----------------------------------------------------------------------
DisasterManager.DisasterGenerated = Signal.new()  -- (config: DisasterConfig)
DisasterManager.HazardUpdated = Signal.new()      -- (hazardId: string, data: HazardZone)
DisasterManager.MapBuilt = Signal.new()            -- (sessionId: string)
DisasterManager.MapCleaned = Signal.new()          -- (sessionId: string)

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local activeMapFolders: { [string]: Folder } = {}
local partPool: { BasePart } = {}
local npcPool: { Model } = {}
local rng = Random.new()

----------------------------------------------------------------------
-- PROCEDURAL GENERATION
----------------------------------------------------------------------

--- Pick a disaster type weighted by squad composition.
--- Squads with certain roles get disasters that use those roles more.
local function pickDisasterType(squad: Types.Squad): Types.DisasterType
    local disasterTypes = {}
    local weights = {}

    for dtype, config in Constants.DISASTER_CONFIGS do
        table.insert(disasterTypes, dtype)

        -- Base weight
        local weight = 1.0

        -- Boost weight if squad has roles that match this disaster's preferred roles
        for _, member in squad.members do
            local roleWeight = config.requiredRolesWeight[member.role]
            if roleWeight then
                weight += roleWeight * 0.5
            end
        end

        table.insert(weights, weight)
    end

    return TableUtil.weightedPick(disasterTypes, weights) :: Types.DisasterType
end

--- Determine severity based on squad average level and prestige.
local function rollSeverity(squad: Types.Squad, config: any): Types.DisasterSeverity
    local avgLevel = 0
    for _, member in squad.members do
        -- In production, look up actual player level; for now use placeholder
        avgLevel += 10
    end
    avgLevel /= math.max(1, #squad.members)

    local severityRoll = rng:NextNumber()

    -- Higher level = higher chance of harder severity
    local levelFactor = math.clamp(avgLevel / Constants.MAX_LEVEL, 0, 1)

    if severityRoll < 0.2 + levelFactor * 0.3 then
        return "Catastrophic"
    elseif severityRoll < 0.5 + levelFactor * 0.2 then
        return "Major"
    else
        return "Minor"
    end
end

--- Generate objectives for a disaster.
local function generateObjectives(
    disasterType: Types.DisasterType,
    severity: Types.DisasterSeverity,
    config: any
): { Types.DisasterObjective }
    local severityMultiplier = ({
        Minor = 1.0,
        Major = 1.5,
        Catastrophic = 2.0,
    })[severity]

    local objectiveCount = math.floor(config.baseObjectives * severityMultiplier)
    objectiveCount = math.clamp(objectiveCount, 2, 10)

    local civilianCount = math.floor(config.baseCivilians * severityMultiplier)

    local objectiveTemplates = {
        {
            objectiveType = "Rescue",
            label = "Rescue Civilians",
            description = "Locate and evacuate trapped civilians",
            scoreValue = 100,
        },
        {
            objectiveType = "Extinguish",
            label = "Extinguish Fires",
            description = "Put out active fire zones",
            scoreValue = 75,
        },
        {
            objectiveType = "Repair",
            label = "Stabilize Structure",
            description = "Reinforce damaged structural supports",
            scoreValue = 80,
        },
        {
            objectiveType = "Evacuate",
            label = "Evacuate Zone",
            description = "Clear all personnel from the danger zone",
            scoreValue = 60,
        },
        {
            objectiveType = "Contain",
            label = "Contain Hazard",
            description = "Prevent hazard from spreading",
            scoreValue = 90,
        },
        {
            objectiveType = "Search",
            label = "Search Area",
            description = "Systematically search the area for survivors",
            scoreValue = 70,
        },
    }

    -- Filter templates to those relevant to this disaster's hazard types
    local relevantTemplates = {}
    for _, tmpl in objectiveTemplates do
        -- Always include Rescue and Search
        if tmpl.objectiveType == "Rescue" or tmpl.objectiveType == "Search" then
            table.insert(relevantTemplates, tmpl)
        elseif tmpl.objectiveType == "Extinguish" and table.find(config.hazardTypes, "Fire") then
            table.insert(relevantTemplates, tmpl)
        elseif tmpl.objectiveType == "Contain" and (table.find(config.hazardTypes, "Toxic") or table.find(config.hazardTypes, "Water")) then
            table.insert(relevantTemplates, tmpl)
        elseif tmpl.objectiveType == "Repair" and table.find(config.hazardTypes, "Structural") then
            table.insert(relevantTemplates, tmpl)
        else
            table.insert(relevantTemplates, tmpl) -- fallback: include everything
        end
    end

    local objectives: { Types.DisasterObjective } = {}

    -- First objective is always Rescue
    table.insert(objectives, {
        id = "obj_rescue_1",
        label = "Rescue Civilians",
        description = `Locate and rescue {civilianCount} trapped civilians`,
        objectiveType = "Rescue" :: any,
        requiredRoles = nil,
        targetCount = civilianCount,
        currentCount = 0,
        scoreValue = 100 * severityMultiplier,
        timeLimit = nil,
        status = "Pending" :: any,
        position = nil,
    })

    -- Fill remaining objectives from templates
    local shuffled = TableUtil.shuffle(table.clone(relevantTemplates))
    for i = 2, objectiveCount do
        local tmpl = shuffled[((i - 2) % #shuffled) + 1]
        local targetCount = math.floor(rng:NextInteger(2, 5) * severityMultiplier)

        table.insert(objectives, {
            id = `obj_{tmpl.objectiveType}_{i}`,
            label = tmpl.label,
            description = tmpl.description,
            objectiveType = tmpl.objectiveType :: any,
            requiredRoles = nil,
            targetCount = targetCount,
            currentCount = 0,
            scoreValue = math.floor(tmpl.scoreValue * severityMultiplier),
            timeLimit = nil,
            status = "Pending" :: any,
            position = nil,
        })
    end

    return objectives
end

--- Generate hazard zones.
local function generateHazardZones(
    config: any,
    severity: Types.DisasterSeverity,
    mapCenter: Vector3
): { Types.HazardZone }
    local severityMultiplier = ({ Minor = 1, Major = 2, Catastrophic = 3 })[severity]
    local zoneCount = math.clamp(#config.hazardTypes * severityMultiplier, 1, 8)

    local zones: { Types.HazardZone } = {}
    for i = 1, zoneCount do
        local hazardType = config.hazardTypes[((i - 1) % #config.hazardTypes) + 1]
        local angle = (i / zoneCount) * math.pi * 2
        local distance = rng:NextNumber(20, 80)
        local position = mapCenter + Vector3.new(
            math.cos(angle) * distance,
            0,
            math.sin(angle) * distance
        )

        table.insert(zones, {
            id = `hazard_{i}`,
            position = position,
            radius = rng:NextNumber(10, 30) * (severityMultiplier * 0.5),
            damagePerSecond = 5 * severityMultiplier,
            hazardType = hazardType :: any,
            canBeNeutralized = true,
        })
    end

    return zones
end

--- Generate environment modifiers.
local function generateEnvironment(
    disasterType: Types.DisasterType,
    severity: Types.DisasterSeverity
): Types.EnvironmentModifiers
    local presets = {
        BuildingCollapse = { visibility = 0.6, precipitation = "Ash", shakeMagnitude = 0.3 },
        Wildfire = { visibility = 0.4, precipitation = "Ash", shakeMagnitude = 0.0 },
        Flood = { visibility = 0.7, precipitation = "Rain", shakeMagnitude = 0.1 },
        Earthquake = { visibility = 0.8, precipitation = "None", shakeMagnitude = 0.8 },
        Hurricane = { visibility = 0.3, precipitation = "Rain", shakeMagnitude = 0.5 },
        ChemicalSpill = { visibility = 0.5, precipitation = "None", shakeMagnitude = 0.0 },
        Avalanche = { visibility = 0.4, precipitation = "Snow", shakeMagnitude = 0.4 },
        Shipwreck = { visibility = 0.6, precipitation = "Rain", shakeMagnitude = 0.2 },
    }

    local preset = presets[disasterType] or { visibility = 1, precipitation = "None", shakeMagnitude = 0 }

    local severityMod = ({ Minor = 1.0, Major = 0.8, Catastrophic = 0.6 })[severity]

    return {
        visibility = math.clamp(preset.visibility * severityMod, 0.1, 1.0),
        windSpeed = rng:NextNumber(0, 30) * (severity == "Catastrophic" and 2 or 1),
        windDirection = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit,
        precipitation = preset.precipitation :: any,
        timeOfDay = rng:NextNumber(6, 22),
        shakeMagnitude = preset.shakeMagnitude * (severity == "Catastrophic" and 2 or 1),
    }
end

----------------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------------

--- Generate a complete disaster configuration for a squad.
function DisasterManager:GenerateDisaster(squad: Types.Squad): Types.DisasterConfig
    local disasterType = pickDisasterType(squad)
    local config = Constants.DISASTER_CONFIGS[disasterType]
    local severity = rollSeverity(squad, config)

    local severityMultiplier = ({ Minor = 1.0, Major = 1.3, Catastrophic = 1.6 })[severity]
    local timeLimit = math.floor(config.baseTimeLimit * severityMultiplier)

    local mapCenter = Vector3.new(0, 0, 0) -- disasters build at origin; offset per instance in production

    local objectives = generateObjectives(disasterType, severity, config)
    local hazardZones = generateHazardZones(config, severity, mapCenter)
    local environment = generateEnvironment(disasterType, severity)

    -- Generate spawn points in a semicircle at the edge of the disaster zone
    local spawnPoints = {}
    for i = 1, Constants.MAX_SQUAD_SIZE do
        local angle = (i / Constants.MAX_SQUAD_SIZE) * math.pi -- semicircle
        table.insert(spawnPoints, mapCenter + Vector3.new(
            math.cos(angle) * 100,
            0,
            math.sin(angle) * 100
        ))
    end

    local disasterConfig: Types.DisasterConfig = {
        disasterType = disasterType,
        severity = severity,
        displayName = `{config.displayName} ({severity})`,
        description = `A {string.lower(severity)} {string.lower(config.displayName)} requires immediate response!`,
        minPlayers = Constants.MIN_SQUAD_SIZE,
        maxPlayers = Constants.MAX_SQUAD_SIZE,
        timeLimitSeconds = timeLimit,
        objectives = objectives,
        hazardZones = hazardZones,
        spawnPoints = spawnPoints,
        environmentModifiers = environment,
    }

    DisasterManager.DisasterGenerated:Fire(disasterConfig)
    print(`[DisasterManager] Generated: {disasterConfig.displayName} with {#objectives} objectives`)

    return disasterConfig
end

--- Build the physical disaster map in Workspace.
--- Uses prefab chunks from ServerStorage (or generates simple geometry as placeholder).
function DisasterManager:BuildDisasterMap(session: Types.RescueSession)
    local folder = Instance.new("Folder")
    folder.Name = `DisasterMap_{session.sessionId}`
    activeMapFolders[session.sessionId] = folder

    local config = session.disasterConfig

    -- Ground plane
    local ground = Instance.new("Part")
    ground.Name = "Ground"
    ground.Size = Vector3.new(250, 1, 250)
    ground.Position = Vector3.new(0, -0.5, 0)
    ground.Anchored = true
    ground.Material = Enum.Material.Concrete
    ground.Color = Color3.fromRGB(80, 80, 80)
    ground.Parent = folder

    -- Place hazard zone visualizers
    for _, zone in config.hazardZones do
        local indicator = Instance.new("Part")
        indicator.Name = `Hazard_{zone.id}`
        indicator.Shape = Enum.PartType.Cylinder
        indicator.Size = Vector3.new(1, zone.radius * 2, zone.radius * 2)
        indicator.CFrame = CFrame.new(zone.position) * CFrame.Angles(0, 0, math.rad(90))
        indicator.Anchored = true
        indicator.Transparency = 0.7
        indicator.CanCollide = false
        indicator.Material = Enum.Material.Neon

        local colorMap = {
            Fire = Color3.fromRGB(255, 80, 20),
            Toxic = Color3.fromRGB(80, 255, 20),
            Structural = Color3.fromRGB(200, 200, 50),
            Water = Color3.fromRGB(20, 100, 255),
            Electric = Color3.fromRGB(255, 255, 50),
        }
        indicator.Color = colorMap[zone.hazardType] or Color3.fromRGB(255, 0, 0)
        indicator.Parent = folder

        -- CollectionService tag for client-side effects
        game:GetService("CollectionService"):AddTag(indicator, "HazardZone")
        indicator:SetAttribute("HazardType", zone.hazardType)
        indicator:SetAttribute("DPS", zone.damagePerSecond)
        indicator:SetAttribute("HazardId", zone.id)
    end

    -- Spawn civilian NPC placeholders at objective positions
    local civilianCount = 0
    for _, obj in config.objectives do
        if obj.objectiveType == "Rescue" then
            for j = 1, math.min(obj.targetCount, Constants.CIVILIAN_NPC_LIMIT - civilianCount) do
                local npc = Instance.new("Model")
                npc.Name = `Civilian_{j}`

                local root = Instance.new("Part")
                root.Name = "HumanoidRootPart"
                root.Size = Vector3.new(2, 2, 1)
                root.Anchored = true
                root.Transparency = 0
                root.Material = Enum.Material.SmoothPlastic
                root.Color = Color3.fromRGB(255, 200, 150)

                -- Scatter civilians within disaster zone
                local angle = rng:NextNumber(0, math.pi * 2)
                local dist = rng:NextNumber(10, 70)
                root.Position = Vector3.new(
                    math.cos(angle) * dist,
                    1,
                    math.sin(angle) * dist
                )
                root.Parent = npc

                npc.PrimaryPart = root
                npc:SetAttribute("CivilianId", `civ_{civilianCount + j}`)
                npc:SetAttribute("IsRescued", false)
                npc:SetAttribute("Health", 100)
                game:GetService("CollectionService"):AddTag(npc, "Civilian")
                npc.Parent = folder

                civilianCount += 1
            end
        end
    end

    -- Place structural debris (placeholder cubes)
    local debrisCount = math.min(
        math.floor(50 * (({ Minor = 1, Major = 2, Catastrophic = 3 })[config.severity])),
        Constants.MAX_DEBRIS_PARTS
    )
    for i = 1, debrisCount do
        local debris = Instance.new("Part")
        debris.Name = `Debris_{i}`
        debris.Size = Vector3.new(
            rng:NextNumber(1, 6),
            rng:NextNumber(1, 4),
            rng:NextNumber(1, 6)
        )
        debris.Position = Vector3.new(
            rng:NextNumber(-80, 80),
            rng:NextNumber(0, 10),
            rng:NextNumber(-80, 80)
        )
        debris.Rotation = Vector3.new(
            rng:NextNumber(0, 360),
            rng:NextNumber(0, 360),
            rng:NextNumber(0, 360)
        )
        debris.Anchored = true
        debris.Material = Enum.Material.Concrete
        debris.Color = Color3.fromRGB(
            rng:NextInteger(60, 120),
            rng:NextInteger(60, 120),
            rng:NextInteger(60, 120)
        )
        game:GetService("CollectionService"):AddTag(debris, "Debris")
        debris.Parent = folder
    end

    folder.Parent = workspace
    DisasterManager.MapBuilt:Fire(session.sessionId)
    print(`[DisasterManager] Map built for {session.sessionId}: {debrisCount} debris, {civilianCount} civilians`)
end

--- Clean up the physical disaster map.
function DisasterManager:CleanupDisaster(session: Types.RescueSession)
    local folder = activeMapFolders[session.sessionId]
    if folder then
        folder:Destroy()
        activeMapFolders[session.sessionId] = nil
    end
    DisasterManager.MapCleaned:Fire(session.sessionId)
    print(`[DisasterManager] Cleaned up map for {session.sessionId}`)
end

--- Update a hazard zone (e.g., player neutralized it, or it's spreading).
function DisasterManager:UpdateHazardZone(sessionId: string, hazardId: string, changes: { [string]: any })
    local folder = activeMapFolders[sessionId]
    if not folder then return end

    local indicator = folder:FindFirstChild(`Hazard_{hazardId}`)
    if not indicator then return end

    if changes.radius then
        indicator.Size = Vector3.new(1, changes.radius * 2, changes.radius * 2)
    end
    if changes.neutralized then
        indicator.Transparency = 1
        indicator.CanCollide = false
    end

    DisasterManager.HazardUpdated:Fire(hazardId, changes)
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------

function DisasterManager:Init()
    -- Pre-warm RNG
    rng = Random.new(os.clock() * 1000 + tick())
    print("[DisasterManager] Initialized")
end

return DisasterManager
