# Rescue Squad Simulator - Game Design Document

**Version:** 0.1.0-alpha
**Last Updated:** March 2026

---

## 1. GAME OVERVIEW

**Title:** Rescue Squad Simulator
**Tagline:** "Respond. Rescue. Save."
**Genre:** Co-op Simulator / Action
**Platform:** Roblox
**Target Audience:** Ages 8-16 (core), 16+ (extended)
**Team Size:** 4-6 players per squad

### Elevator Pitch
Form an elite emergency response team with friends. Choose your specialist role, coordinate with your squad, and tackle procedurally generated disasters from building collapses to hurricanes. Every player matters. Every second counts.

### Core Fantasy
Players live the heroic fantasy of being a professional rescue worker. The game delivers the adrenaline of responding to emergencies, the satisfaction of saving lives, and the camaraderie of working as a coordinated team.

---

## 2. CORE GAMEPLAY LOOP

```
LOBBY → QUEUE/SQUAD UP → ROLE SELECT → BRIEFING → DEPLOY → ACTIVE RESCUE → EXTRACTION → SCORING → REWARDS → LOOP
```

### Session Flow (8-12 minutes per mission)

1. **Lobby (30-60s):** Players are at HQ. They can browse shop, customize loadout, check stats, join queue.
2. **Matchmaking (15-60s):** Solo players auto-matched into squads. Friends can create private squads.
3. **Role Selection (15s):** Each squad member picks a specialist role. No duplicates within a squad.
4. **Briefing (10s):** Disaster details revealed: type, severity, objectives, hazards. Squad sees overview camera.
5. **Deployment (3s):** Cinematic drop-in to the disaster zone.
6. **Active Rescue (3-7 min):** The core gameplay. Squad works together to complete objectives under a time limit. Hazards deal damage, civilians need rescuing, structures need stabilizing.
7. **Extraction (5s):** Cinematic pullout when objectives complete or time expires.
8. **Scoring (10s):** Mission rated S/A/B/C/D/F. Individual and team scores displayed.
9. **Rewards:** XP, coins, rescue tokens awarded based on performance.

---

## 3. SPECIALIST ROLES

### Medic (Unlock: Level 1)
- **Color:** Green (#2ECC71)
- **Equipment:** Med Kit, Defibrillator, Stretcher
- **Passive:** 50% faster revives
- **Ability 1 - Heal Burst (15s CD):** AoE heal that restores 30 HP to nearby teammates
- **Ability 2 - Triage (30s CD):** Reveals all civilian locations to the squad for 10 seconds
- **Gameplay:** The healer. Keeps team alive, stabilizes civilians before extraction. Earns bonus score for rescues.

### Engineer (Unlock: Level 1)
- **Color:** Yellow (#F1C40F)
- **Equipment:** Jacks & Braces, Cutting Torch, Structural Scanner
- **Passive:** 30% hazard damage resistance
- **Ability 1 - Reinforce (20s CD):** Stabilizes nearby structure, reducing hazard zone radius and damage by 50%
- **Ability 2 - Controlled Demolition (45s CD):** Clears a large debris pile, opening new paths
- **Gameplay:** The problem solver. Neutralizes hazards, clears paths, makes the zone safer for everyone.

### K9 Handler (Unlock: Level 3)
- **Color:** Purple (#9B59B6)
- **Equipment:** K9 Companion, Tracking Device, Extraction Harness
- **Passive:** 50% larger detection radius
- **Ability 1 - Search Command (12s CD):** K9 dog locates nearest buried civilian with a ping on everyone's HUD
- **Ability 2 - Alert Bark (25s CD):** Marks danger zones and alerts team to structural instability
- **Gameplay:** The scout. Finds civilians faster than anyone. Critical for search-type objectives.

### Pilot (Unlock: Level 5)
- **Color:** Blue (#3498DB)
- **Equipment:** Helicopter, Winch System, Water Bucket
- **Passive:** 20% movement speed boost
- **Ability 1 - Aerial Drop (30s CD):** Drops supplies (health packs) at a target location
- **Ability 2 - Spotlight (10s CD):** Illuminates a dark area, revealing hidden civilians/hazards
- **Gameplay:** Aerial support and logistics. Provides overwatch, drops supplies, and airlifts civilians in water/mountain disasters.

### Diver (Unlock: Level 5)
- **Color:** Teal (#1ABC9C)
- **Equipment:** Diving Suit, Underwater Cutter, Inflatable Raft
- **Passive:** 2x underwater movement speed
- **Ability 1 - Swift Swim (15s CD):** Burst of underwater speed for rapid rescue
- **Ability 2 - Air Pocket (40s CD):** Creates a temporary safe zone underwater for trapped civilians
- **Gameplay:** Water specialist. Essential for flood, shipwreck, and hurricane disasters. Can go where others can't.

### Commander (Unlock: Level 8)
- **Color:** Red (#E74C3C)
- **Equipment:** Tactical Radio, Flare Gun, Supply Drop
- **Passive:** 25% larger team buff radius
- **Ability 1 - Rallying Cry (30s CD):** Restores 25 stamina to all squad members and boosts morale
- **Ability 2 - Supply Airdrop (60s CD):** Calls in a supply crate with equipment and health packs
- **Gameplay:** The leader. Buffs the whole team, manages resources, coordinates the operation.

---

## 4. DISASTER TYPES

| Disaster | Severity Range | Time Limit | Key Roles | Unique Hazard |
|----------|---------------|------------|-----------|---------------|
| Building Collapse | 1-3 | 5-8 min | Engineer, K9 | Falling debris, unstable floors |
| Wildfire | 1-3 | 6-10 min | Pilot, Commander | Spreading fire, smoke visibility |
| Flash Flood | 1-3 | 5-8 min | Diver, Pilot | Rising water, strong currents |
| Earthquake | 2-3 | 6-10 min | Engineer, K9 | Aftershocks, ground cracks |
| Hurricane | 2-3 | 7-10 min | Commander, Pilot | Wind knockback, flying debris |
| Chemical Spill | 1-3 | 4-6 min | Engineer, Medic | Toxic zones, contamination |
| Avalanche | 1-3 | 5-8 min | K9, Pilot | Snow burial, cold damage |
| Shipwreck | 1-3 | 6-10 min | Diver, Pilot | Sinking vessel, water hazards |

### Severity Levels
- **Minor:** 4 objectives, 6-8 civilians, standard hazards. Good for new players.
- **Major:** 6 objectives, 10-12 civilians, increased hazards. Requires coordination.
- **Catastrophic:** 8-10 objectives, 15+ civilians, extreme hazards. Prestige-level challenge.

---

## 5. PROGRESSION SYSTEM

### XP & Leveling
- **Max Level:** 100
- **Formula:** XP_required = 100 * level^1.15
- **XP Sources:** Completing objectives, rescuing civilians, finishing missions, speed bonuses
- **Global Level:** Unlocks roles, equipment, cosmetics, new disaster types
- **Role Level:** Per-role XP tracks mastery of each specialist role

### Prestige (Rebirth)
- **Requirement:** Reach Level 100
- **Max Prestige:** 10
- **Reward:** +10% permanent multiplier per prestige level to all XP and coin rewards
- **Cost:** Reset to Level 1 and Role Level 1 (stats preserved)
- **Bonus:** 50 rescue tokens + 10 premium gems per prestige level

### Rank Titles
| Level Range | Rank |
|-------------|------|
| 1-10 | Rookie |
| 11-25 | Responder |
| 26-50 | Specialist |
| 51-75 | Veteran |
| 76-99 | Elite |
| 100 | Legend |
| Prestige 1+ | Prestige [P-Level] Legend |

---

## 6. ECONOMY & MONETIZATION

### Currency Types
| Currency | Earned By | Spent On |
|----------|-----------|----------|
| Coins | Missions, dailies, streaks | Equipment, some cosmetics |
| Rescue Tokens | Perfect missions, weeklies, prestige | Premium equipment, rare cosmetics |
| Premium Gems | Prestige, Robux purchase | Boosts, exclusive cosmetics |

### Game Passes (One-Time Robux Purchase)
| Pass | Price (R$) | Benefit |
|------|-----------|---------|
| VIP | 499 | 1.5x coin multiplier, VIP badge, exclusive emote |
| Double XP | 299 | 2x XP permanently |
| Extra Loadout | 199 | Carry 2 extra equipment items |
| Auto-Collect | 149 | Auto-pickup nearby items during missions |
| Premium Cosmetics | 399 | Access to exclusive cosmetic line |

### Daily Login Rewards
- Base: 50 coins + streak bonus (25 coins per day)
- Day 7 milestone: +20 rescue tokens
- Day 14 milestone: +5 premium gems
- Day 30 milestone: +15 premium gems, +50 rescue tokens

---

## 7. RETENTION MECHANICS

### Daily Systems
- Daily login rewards with escalating streak bonuses
- 3 daily missions (rotate randomly)
- Daily disaster spotlight (boosted rewards for one disaster type)

### Weekly Systems
- Weekly challenge (complete 10 missions)
- Weekend special events (unique disaster scenarios)
- Weekly leaderboard reset with rewards for top players

### Seasonal Content (Every 4-6 weeks)
- New disaster type or variant
- Seasonal cosmetic set (limited time)
- Seasonal challenge track (battle pass equivalent)
- Special event disasters (holiday-themed)

### Collection Catalog
- Track all discovered disaster variations
- Collect all cosmetic sets
- Achievement badges for milestones
- Role mastery badges (Level 50 in a role)

---

## 8. SOCIAL SYSTEMS

### Squads
- Create private squads with invite codes
- Squad leaderboards
- Squad XP bonuses (+10% when playing with full squad)
- Persistent squads across sessions

### Communication
- Quick chat wheel (role-specific callouts)
- Emotes (unlockable)
- Ping system (mark locations for teammates)
- Voice proximity chat (optional, Roblox native)

---

## 9. TECHNICAL ARCHITECTURE

### Server-Side Modules
- `GameManager` - Round lifecycle state machine
- `DisasterManager` - Procedural disaster generation
- `SquadManager` - Team formation and matchmaking
- `RescueManager` - Active mission logic and interactions
- `ProgressionManager` - XP, leveling, prestige
- `EconomyManager` - Currency, shop, game passes
- `DataManager` - Player data persistence (DataStore)
- `NetworkManager` - Centralized remote events/functions

### Client-Side Controllers
- `NetworkController` - Client networking layer
- `HUDController` - All UI elements
- `InteractionController` - Proximity interactions and keybinds
- `CameraController` - Dynamic camera effects

### Key Technical Decisions
- **Rojo** for file-sync based development
- **Streaming Enabled** for large disaster maps
- **CollectionService tags** for hazard/civilian detection
- **Session locking** for data safety
- **Rate limiting** on all client-to-server events

---

## 10. DEVELOPMENT ROADMAP

### Phase 1: Core Gameplay (Current)
- [x] Type definitions and constants
- [x] Server architecture (all 8 modules)
- [x] Client architecture (4 controllers)
- [x] Rojo project structure
- [ ] Placeholder disaster map building
- [ ] Basic HUD functional
- [ ] All 6 roles playable
- [ ] 1 disaster type fully playable (Building Collapse)

### Phase 2: Content & Polish
- [ ] All 8 disaster types
- [ ] Full UI/UX (menus, shop, stats)
- [ ] Sound design and music
- [ ] Visual effects (fire, water, smoke, particles)
- [ ] NPC civilian models and animations
- [ ] Equipment upgrade system

### Phase 3: Economy & Retention
- [ ] Shop fully functional
- [ ] Game passes integrated
- [ ] Daily/weekly mission system
- [ ] Login streak rewards
- [ ] Leaderboards
- [ ] Achievement system

### Phase 4: Social & Events
- [ ] Private squad system
- [ ] Squad leaderboards
- [ ] Seasonal event framework
- [ ] First seasonal content
- [ ] Quick chat and emotes

### Phase 5: Launch Prep
- [ ] Performance optimization
- [ ] Anti-cheat hardening
- [ ] Closed beta testing
- [ ] Marketing assets (thumbnails, descriptions)
- [ ] Monetization balancing
- [ ] Launch!
