# Rescue Squad Simulator - Technical Architecture

## Overview

Rescue Squad Simulator is a multiplayer Roblox game where teams of 4-6 players
respond to procedurally generated emergency disasters with role-based gameplay.
This document describes the complete technical architecture.

---

## 1. Project Structure (Rojo File Sync)

```
RescueSquadSimulator/
├── default.project.json          # Rojo project config
├── ARCHITECTURE.md               # This file
├── RESEARCH.md                   # Market research
│
├── src/
│   ├── server/                   # -> ServerScriptService
│   │   ├── init.server.luau      # Server bootstrap (entry point)
│   │   ├── Services/
│   │   │   ├── GameManager.luau      # Round lifecycle state machine
│   │   │   ├── DisasterManager.luau  # Procedural disaster generation
│   │   │   ├── SquadManager.luau     # Team formation & matchmaking
│   │   │   ├── RescueManager.luau    # Active mission logic & scoring
│   │   │   ├── ProgressionManager.luau # XP, levels, prestige
│   │   │   ├── EconomyManager.luau   # Currency, shop, game passes
│   │   │   ├── InventoryManager.luau # Equipment & cosmetics
│   │   │   └── NetworkManager.luau   # Centralized RemoteEvent routing
│   │   ├── Data/
│   │   │   └── PlayerDataManager.luau # DataStore persistence (ProfileService pattern)
│   │   └── Components/               # Future: ECS-style entity components
│   │
│   ├── client/                   # -> StarterPlayerScripts
│   │   ├── init.client.luau      # Client bootstrap (entry point)
│   │   ├── Controllers/
│   │   │   ├── UIManager.luau        # Screen management, HUD updates
│   │   │   ├── InputManager.luau     # Action-based input, interaction detection
│   │   │   ├── CameraManager.luau    # Multi-mode camera system
│   │   │   └── EffectsManager.luau   # VFX, particles, screen effects
│   │   ├── Components/               # Future: client-side components
│   │   └── UI/                       # Future: reusable UI component modules
│   │
│   ├── shared/                   # -> ReplicatedStorage
│   │   ├── Modules/
│   │   │   ├── Types.luau            # All type definitions (single source of truth)
│   │   │   └── Constants.luau        # Game config, tuning numbers, role defs
│   │   ├── Util/
│   │   │   ├── Signal.luau           # Custom event/signal implementation
│   │   │   └── TableUtil.luau        # Table helpers (deepCopy, merge, shuffle, etc.)
│   │   └── Data/                     # Future: shared data schemas
│   │
│   └── gui/                      # -> StarterGui
│       ├── HUD/
│       │   └── init.luau             # In-mission HUD builder
│       ├── Menus/
│       │   ├── RoleSelectionMenu.luau # Pre-mission role picker
│       │   └── ScoreboardScreen.luau  # Post-mission results
│       └── Components/               # Future: shared UI components
│
└── assets/                       # -> ReplicatedStorage.Assets
    ├── models/                   # 3D models (prefab chunks, vehicles, NPCs)
    ├── sounds/                   # SFX and music
    ├── particles/                # Particle emitter presets
    └── animations/               # Character animations
```

---

## 2. Core Systems Architecture

### System Dependency Graph

```
                    ┌─────────────────┐
                    │   GameManager    │  (orchestrator)
                    └───────┬─────────┘
                            │
            ┌───────────────┼───────────────────┐
            │               │                   │
    ┌───────▼──────┐ ┌──────▼──────┐ ┌─────────▼──────────┐
    │ SquadManager │ │DisasterMgr  │ │ ProgressionManager │
    └───────┬──────┘ └──────┬──────┘ └─────────┬──────────┘
            │               │                   │
            │       ┌───────▼──────┐   ┌────────▼────────┐
            │       │RescueManager │   │ EconomyManager  │
            │       └──────────────┘   └────────┬────────┘
            │                                   │
            │                          ┌────────▼────────┐
            │                          │InventoryManager │
            │                          └─────────────────┘
            │
    ┌───────▼──────────┐
    │  NetworkManager   │  (all modules use for remotes)
    └──────────────────┘
            │
    ┌───────▼──────────┐
    │PlayerDataManager │  (all write paths go through here)
    └──────────────────┘
```

### GameManager (Orchestrator)

The GameManager owns the game phase state machine:

```
Lobby -> Matchmaking -> Briefing -> Deploying -> Active -> Extraction -> Scoring -> Intermission -> Lobby
```

- Single authority for phase transitions (prevents race conditions)
- Fires `PhaseChanged` signal so all systems react without polling
- Runs a continuous round loop on a dedicated thread
- Delegates all domain logic to specialized managers

### DisasterManager (Procedural Generation)

**Seed-based generation** ensures reproducibility for debugging and replay:

1. Pick disaster type (weighted by squad composition)
2. Roll severity (influenced by squad average level/prestige)
3. Generate objectives from templates filtered by hazard type
4. Place hazard zones in a radial pattern around map center
5. Generate environment modifiers (visibility, wind, precipitation)
6. Build physical map (ground, debris, hazard indicators, civilian NPCs)

**Difficulty scaling formula:**
```
severity_chance = base_chance + (avg_level / MAX_LEVEL) * scaling_factor
objective_count = base_objectives * severity_multiplier
civilian_count = base_civilians * severity_multiplier
time_limit = base_time * severity_multiplier
```

Severity multipliers: Minor=1.0, Major=1.5, Catastrophic=2.0

### SquadManager (Team Formation)

- Solo matchmaking queue: forms squads of MIN-MAX size from queue
- Private squads: invite-only via squad codes
- Role assignment: honors player preferences, fills gaps automatically
- Cannot join squad mid-mission (anti-abuse)
- AFK detection: unready players auto-kicked after timeout

### RescueManager (Active Mission)

**Interaction model (authoritative server):**
```
Client: presses [E] near target
Client: local validation (distance, cooldown) -> sends InteractionRequest(targetId, actionType)
Server: re-validates distance, cooldown, role permission, target state
Server: applies effect (rescue civilian, neutralize hazard, heal teammate)
Server: fires ObjectiveUpdated to all squad members
```

**Scoring formula:**
```
team_score = base_score * speed_multiplier * casualty_multiplier * severity_multiplier

speed_multiplier: 1.5 (>50% time left), 1.25 (<75%), 1.0 (otherwise)
casualty_multiplier: civilians_rescued / total_civilians (clamped 0.5-1.0)
severity_multiplier: Minor=1.0, Major=1.5, Catastrophic=2.0
```

Rating thresholds: S(1.5x+), A(1.2x), B(0.9x), C(0.6x), D(0.3x), F(<0.3x)

---

## 3. Client Systems

### UIManager
- Screen stack: only one screen active at a time
- HUD layered on top during Active phase
- Role-specific ability bar swapped based on assigned role
- Notification toasts with tween-in/out animation

### InputManager
- Action-based (not raw key checks): `Interact`, `Ability1`, `Ability2`, `Sprint`, `Ping`
- Proximity-based interaction detection using CollectionService tags
- Client-side cooldown pre-check before sending to server
- Touch device support with ContextActionService positioned buttons
- BillboardGui interaction prompts on nearby interactables

### CameraManager
- Modes: Default, Cinematic, Overhead (Commander), FirstPerson (Diver), Shake
- Camera shake uses spring-damper physics model for natural feel
- Mode auto-switches based on game phase

### EffectsManager
- Particle pool with performance budget (MAX_ACTIVE_PARTICLES = 200)
- CollectionService-driven: auto-attaches particles to tagged HazardZone parts
- Screen effects: damage vignette, underwater tint, fog/visibility
- Reduced effects mode for low-end devices
- Hazard type -> emitter mapping: Fire, Toxic, Structural(smoke), Electric

---

## 4. Data Architecture

### DataStore Schema (PlayerData)

Uses a **ProfileService-inspired pattern** with session locking:

| Field | Type | Description |
|-------|------|-------------|
| `dataVersion` | number | Schema version for migrations |
| `firstJoin` / `lastJoin` | number | UTC timestamps |
| `totalPlayTime` | number | Seconds |
| `globalXP` / `globalLevel` | number | Overall progression |
| `prestigeLevel` / `prestigeMultiplier` | number | Prestige system |
| `roleStats` | {[Role]: RoleStats} | Per-role progression |
| `coins` / `rescueTokens` / `premiumGems` | number | Three currencies |
| `equipment` | {EquipmentData} | Owned + equipped items with levels |
| `cosmetics` | {string} | Owned cosmetic IDs |
| `equippedCosmetics` | table | Active cosmetic per slot |
| `gamePasses` | {string} | Owned game pass IDs |
| `totalMissions` / `totalRescues` / `totalScore` | number | Lifetime stats |
| `missionsPerDisasterType` | {[string]: number} | Per-disaster-type counts |
| `dailyLoginStreak` / `lastDailyReward` | number | Streak tracking |
| `weeklyMissions` | table | Weekly mission progress |
| `settings` | table | Client preferences |

### Data Migration Strategy

The `dataVersion` field enables forward-compatible migrations:

```luau
if data.dataVersion < 2 then
    data.newField = defaultValue
    data.dataVersion = 2
end
```

Migrations are applied sequentially on load. Old data is never discarded;
new fields are added with defaults via `deepMerge` with the template.

### Session vs Persistent Data

| Data Type | Storage | Examples |
|-----------|---------|----------|
| Persistent | DataStore | XP, levels, inventory, currency, stats |
| Session | Server memory | Current squad, mission state, cooldowns |
| Ephemeral | Client memory | Camera state, UI state, particle references |

---

## 5. Networking

### RemoteEvent Catalog

**Server -> Client (13 events):**
| Event | Payload | Frequency |
|-------|---------|-----------|
| GamePhaseChanged | {phase, timestamp} | On transition |
| DisasterBriefing | Full briefing payload | Once per mission |
| ObjectiveUpdated | {objectiveId, current, target, status} | On progress |
| HazardZoneUpdated | {hazardId, neutralized, radius} | On change |
| PlayerHealthChanged | {playerId, health} | 30 Hz max |
| PlayerStaminaChanged | {playerId, stamina} | 10 Hz |
| ScoreUpdated | {teamScore, playerScore} | On change |
| MissionResult | Full result payload | Once per mission |
| EffectTrigger | {effectType, position, data} | On event |
| SquadUpdated | {squadId, members, leaderId} | On change |
| NotificationPush | {title, message, type} | On event |
| EnvironmentUpdate | {visibility, wind, shake} | On change |
| CivilianStateChanged | {civilianId, isRescued, rescuedBy} | On event |

**Client -> Server (9 events):**
| Event | Payload | Rate Limit |
|-------|---------|------------|
| PlayerReady | boolean | 1/sec |
| RoleSelected | role string | 1/sec |
| AbilityActivated | abilityId string | Per cooldown |
| InteractionRequest | {actionType, targetId} | 1.5s cooldown |
| SquadInviteSent | targetPlayerId | 5/min |
| SquadInviteResponse | {squadId, accepted} | 1/sec |
| EquipmentChanged | {itemId, equipped} | 1/sec |
| PurchaseRequest | itemId | 1/sec |
| SettingsChanged | settings table | 1/sec |

**RemoteFunctions (5):** GetPlayerData, GetShopCatalog, GetLeaderboard, GetSquadInfo, GetMissionHistory

### Anti-Cheat

1. **Server-authoritative**: all game state mutations happen server-side
2. **Rate limiting**: burst limiter (10 fires/sec/player/event) on all incoming events
3. **Input validation**: type checks, range checks, enum validation on all payloads
4. **Distance checks**: server re-validates interaction range (10 studs)
5. **Cooldown enforcement**: server tracks per-player cooldowns independently
6. **Session locking**: prevents duplicate data writes from rejoin exploits

### Bandwidth Optimization

- Non-critical updates (score, objectives): 10 Hz max
- Critical updates (health, position corrections): 30 Hz max
- Payloads use IDs instead of full objects (e.g., civilianId, not full civilian data)
- Bulk updates batched where possible (squad state sent as single payload)
- Streaming enabled with 256/512 min/target radius

---

## 6. Key Technical Decisions

### Procedural Disaster Generation

**Why procedural:** 8 disaster types * 3 severities * randomized objectives/hazards =
effectively unlimited variety. No two missions feel the same.

**How it works:**
1. Disaster type is weighted by squad composition (so your roles feel useful)
2. Objectives are drawn from templates filtered by hazard type relevance
3. Hazard zones placed radially with random offsets
4. Environment modifiers drawn from per-disaster presets
5. Physical map uses scattered debris parts + civilian NPCs + hazard indicators

**Performance guardrails:**
- MAX_DEBRIS_PARTS = 500 (anchored, no physics simulation)
- CIVILIAN_NPC_LIMIT = 20 (simple parts, not full Humanoid rigs in initial impl)
- Hazard zones use transparent cylinders (cheap to render)

### Role-Specific Mechanics

Each role has:
- **Unique equipment** (3 base items + purchasable upgrades)
- **2 active abilities** with cooldowns and stamina costs
- **1 passive bonus** (e.g., Medic = 50% faster revives, Diver = 2x underwater speed)
- **Interaction restrictions** (only Engineers neutralize non-water hazards, only Divers handle water hazards, only Medics heal teammates)

This creates true role dependency: you NEED a diverse squad to succeed.

### Physics for Rescue Scenarios

**Decision: Anchored parts, no real-time physics simulation.**

Rationale:
- Physics simulation across 500+ debris parts would destroy server performance
- Rescue scenarios need deterministic behavior, not emergent physics
- Instead: debris is anchored and "cleared" via interaction (disappears/moves via tween)
- Structural collapse is animated via pre-scripted tween sequences
- Water level changes are mesh deformation, not fluid simulation

**Budget:** 4ms per frame for custom physics logic (Constants.PHYSICS_STEP_BUDGET_MS)

### Performance Budget

**Target devices:** Mobile phones (iPhone 8+ era), low-end PCs, Xbox.

| Budget Item | Limit |
|-------------|-------|
| Active particles | 200 |
| Debris parts | 500 |
| Civilian NPCs | 20 |
| Server physics budget | 4ms/frame |
| Network update rate (non-critical) | 10 Hz |
| Network update rate (critical) | 30 Hz |
| Streaming min radius | 256 studs |
| Streaming target radius | 512 studs |
| LOD High/Medium/Low | 100/250/500 studs |

**Reduced effects mode:** Players can toggle reduced VFX in settings, which
halves particle emission rates across all emitters.

### Why Rojo?

- Version control: every file is a .luau on disk, tracked in git
- Team collaboration: merge conflicts are resolved in text, not binary
- IDE support: full Luau LSP integration in VS Code / Neovim
- CI/CD: can lint, test, and build from command line

### Why Not Knit/AeroGameFramework?

This architecture uses a simpler manual dependency injection pattern:
- Each module exports an `:Init(dependencies)` method
- The bootstrap script controls initialization order explicitly
- No framework magic, no hidden singletons, no Service/Controller auto-wiring
- Easier to debug, easier to understand for new team members
- Lower overhead than framework abstractions

---

## 7. Initialization Sequence

### Server Boot Order
```
1. NetworkManager      (creates all RemoteEvents/Functions)
2. PlayerDataManager   (sets up DataStore, PlayerAdded/Removing)
3. EconomyManager      (depends on PlayerDataManager, NetworkManager)
4. InventoryManager    (depends on PlayerDataManager, EconomyManager)
5. ProgressionManager  (depends on PlayerDataManager, EconomyManager, NetworkManager)
6. SquadManager        (depends on NetworkManager)
7. DisasterManager     (standalone)
8. RescueManager       (depends on NetworkManager, DisasterManager)
9. GameManager         (depends on all above - starts round loop)
10. Wire up client->server event handlers
11. Wire up RemoteFunction handlers
```

### Client Boot Order
```
1. Wait for game.Loaded
2. Wait for GameRemotes folder
3. CameraManager.Init()
4. EffectsManager.Init()
5. UIManager.Init()
6. InputManager.Init()
7. Request initial player data from server
8. Wire cross-controller signals
```
