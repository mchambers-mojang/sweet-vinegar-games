# Carom — Game Design Document

## Vision

A neon-drenched, physics-driven arena game inspired by the 90s board game Crossfire. Players fire limited ammunition to ricochet a puck into their opponent's goal. The aesthetic is Geometry Wars meets Rocket League — glowing wireframes, particle trails, screen-shaking impacts, all wrapped in the Sweet Vinegar Games visual identity.

## Core Loop

1. **Collect ammo** — pickups spawn around the arena; you must move to grab them
2. **Fire** — shoot projectiles at the puck to push it toward the opponent's goal
3. **Ricochet** — projectiles bounce off walls, creating indirect angles and trick shots
4. **Score** — puck enters opponent's goal zone = 1 point
5. **Reset** — puck returns to center, play continues until score limit reached

## Mechanics

### Ammo System
- Players start with a small clip (e.g., 5-8 shots)
- Ammo pickups spawn at timed intervals in contested zones (mid-arena, corners)
- Collecting ammo creates risk/reward — you leave your defensive position
- Ammo types (future): standard, heavy (slow but high force), scatter, guided

### Puck Physics
- Rigid body with realistic mass and friction
- Ricochets off arena walls with energy loss (doesn't bounce forever)
- Multiple projectiles hitting simultaneously = big momentum transfer
- Puck speed cap to prevent instant-goal cheese

### Player
- Can move freely within their half (or full arena — TBD based on playtesting)
- Getting hit by a projectile = stunned for ~1.5s (Rocket League demolition style)
- No elimination — stun is temporary tactical disadvantage
- Movement speed balanced so you can't just camp your goal

### Arena
- Rectangular arena with walls on all sides
- Goals at opposite ends (slot/zone that puck must enter)
- Possible arena hazards (future): bumpers, moving walls, gravity wells
- Multiple arena layouts for variety

### Scoring
- First to N goals wins (configurable: 3, 5, 7)
- Match timer optional (sudden death if tied at time)

## Camera

Support multiple camera modes:
- **Top-down** — full arena visibility, best for learning and spectating
- **Isometric** — adds depth and style, still shows full arena
- **First-person** — aspirational, most immersive, limited awareness creates tension

Players can choose preferred camera. Multiplayer may restrict to ensure fairness (e.g., first-person-only lobbies).

## Visual Style

- **Neon wireframe** arena walls and floor grid
- **Glowing projectiles** with motion trails (reuse ring/ribbon system from drag effect)
- **Puck** — bright, pulsing, leaves a trail showing momentum direction
- **Impact effects** — screen shake, particle burst, ripple distortion on wall hits
- **Goal scored** — explosion of particles, board shatter-style celebration
- **Player** — simple geometric avatar (sphere, triangle) with glow outline
- **UI** — minimal, neon-styled score display at top

## AI (Single Player)

### Difficulty Levels
- **Easy** — slow reaction, poor aim, doesn't collect ammo aggressively
- **Medium** — decent aim, sometimes uses ricochets, moderate ammo management
- **Hard** — predicts puck trajectory, uses bank shots, contests ammo pickups
- **Brutal** — near-perfect aim, actively tries to stun player, defensive positioning

### AI Architecture
- State machine: Defend → Collect Ammo → Attack → Evade
- Difficulty scales: reaction delay, aim accuracy (spread cone), decision quality
- AI should feel fair, not omniscient — add intentional imperfection even at high levels

## Multiplayer

### Architecture
- **Rollback netcode** for responsive feel (critical for fast-paced physics game)
- **Deterministic game state** required for rollback consistency
- Physics approach: custom deterministic simulation with fixed-point math OR fixed timestep with state snapshots and reconciliation
- Evaluate: NetFox addon (Godot 4, supports rollback + prediction) vs custom implementation

### Modes
- **1v1 Ranked** — random matchmaking with skill rating
- **Lobby/Custom** — create games, invite friends, configure rules
- **LAN** — local network discovery for low-latency play
- **Future**: 2v2, 4-player FFA, 8-player chaos mode

### Netcode Strategy
- Fixed simulation tick rate (e.g., 60Hz)
- Input delay + rollback hybrid
- State serialization for snapshots (positions, velocities, ammo counts)
- Server-authoritative for ranked; peer-to-peer for LAN/casual

## Technical Architecture

### Scene Structure
```
carom/
├── scenes/
│   ├── carom_arena.tscn      # Main 3D arena scene
│   ├── carom_player.tscn     # Player controller
│   ├── carom_puck.tscn       # Puck rigid body
│   ├── carom_projectile.tscn # Ammo projectile
│   └── carom_menu.tscn       # Game mode selection
├── scripts/
│   ├── carom_game.gd         # Match state machine
│   ├── carom_physics.gd      # Deterministic physics sim
│   ├── carom_ai.gd           # AI controller
│   ├── carom_player.gd       # Player input/movement
│   └── carom_netcode.gd      # Multiplayer sync
├── materials/
│   └── neon_grid.tres        # Arena visual materials
└── shaders/
    ├── neon_trail.gdshader   # Projectile/puck trails
    └── impact_ripple.gdshader # Hit effects
```

### Physics Approach (Decision Needed)

**Option A: Custom Deterministic Sim**
- Fixed-point math (no floating point drift)
- Simple shapes only (spheres, boxes, planes)
- Full control over state serialization
- More work upfront, but guaranteed rollback compatibility
- Arena is simple enough that this is feasible

**Option B: Godot Physics + State Reconciliation**
- Use Godot's built-in 3D physics (Jolt)
- Accept non-determinism, compensate with aggressive reconciliation
- Simpler to prototype, harder to make feel right in multiplayer
- May have "snapping" artifacts on correction

**Option C: NetFox + Careful State Management**
- Use NetFox addon for rollback infrastructure
- Custom physics layer for the puck/projectiles only
- Godot physics for non-gameplay elements (particles, debris)

**Recommendation**: Start with Option B for prototyping (get gameplay feel right), plan migration to Option A or C for multiplayer.

## Milestones

### M1: Playable Prototype (Single Player)
- [ ] 3D arena with walls and goals
- [ ] Player movement (keyboard + touch)
- [ ] Shooting mechanic with limited ammo
- [ ] Puck physics (ricochet, goal detection)
- [ ] Ammo pickups spawning
- [ ] Basic scoring (first to 5)
- [ ] Top-down camera
- [ ] Neon visual style (basic)

### M2: AI Opponent
- [ ] Basic AI (Easy difficulty)
- [ ] AI state machine (defend/collect/attack)
- [ ] Medium + Hard difficulty tuning
- [ ] Game over / rematch flow

### M3: Polish & Feel
- [ ] Particle effects (trails, impacts, goal explosions)
- [ ] Screen shake and camera effects
- [ ] Sound design (shots, ricochets, goals, ambient)
- [ ] Stun mechanic with visual feedback
- [ ] Multiple camera angles (top-down, isometric)
- [ ] First-person camera experiment

### M4: Multiplayer Foundation
- [ ] Deterministic physics migration (Option A or C)
- [ ] Rollback netcode integration
- [ ] Peer-to-peer LAN play
- [ ] Input serialization and state snapshots

### M5: Online Multiplayer
- [ ] Server infrastructure (matchmaking, lobbies)
- [ ] Ranked mode with skill rating
- [ ] Custom lobbies with rule configuration
- [ ] Anti-cheat considerations

### M6: Expansion
- [ ] 4-player and 8-player arena layouts
- [ ] New ammo types (heavy, scatter, guided)
- [ ] Arena hazards (bumpers, gravity wells)
- [ ] Team modes (2v2)
- [ ] Cosmetic unlocks tied to achievement system
- [ ] Trick shot / physics puzzle mode (see below)

## Trick Shot Mode (Physics Puzzles)

A single-player puzzle mode that uses the core Carom mechanics in a different context:

- **Concept**: Given a fixed arena layout with bumpers/walls/obstacles, score a goal using a limited number of shots (par system like golf)
- **Trajectory preview**: Optional faint line showing first bounce to help plan
- **Star rating**: 3 stars for par, 2 for par+1, 1 for completing at all
- **Progression**: Unlock packs of increasingly complex arenas
- **Level editor**: Reuse arena editor to let players create and share trick shot puzzles
- **Leaderboard**: Fewest shots / fastest completion per puzzle
- **Training value**: Teaches ricochet angles that transfer to competitive play

## Open Questions

- **Movement constraint**: Full arena freedom or restricted to your half? Playtesting needed.
- **Ammo scarcity tuning**: How scarce is too scarce? If ammo is too rare, gameplay stalls. Too plentiful, it's just spam.
- **Stun duration**: 1.5s feels right on paper but needs playtesting. Too long = frustrating, too short = meaningless.
- **First-person viability**: Can you track a fast puck in first-person? May need aim assist or puck highlighting.
- **Cross-platform determinism**: If custom physics sim, need to ensure fixed-point math works identically on iOS/Android/PC.
- **Arena size**: Too big = boring downtime. Too small = chaotic. Needs to scale with player count.

## Integration with Sweet Vinegar Games

- Accessible from the main game selection menu alongside Sudoku, Shikaku, Blockudoku
- Shares: settings system, haptic manager, theme system (neon theme is natural fit), achievement system, analytics
- Does NOT share: 2D game infrastructure, board/grid systems
- New autoloads as needed: CaromMatchManager, CaromNetcode
