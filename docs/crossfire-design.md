# Carom — Game Design Document

## Vision

A neon-drenched, physics-driven arena game inspired by the 90s board game Crossfire. Players fire limited ammunition to ricochet a puck into their opponent's goal. The aesthetic is Geometry Wars meets Rocket League — glowing wireframes, particle trails, screen-shaking impacts, all wrapped in the Sweet Vinegar Games visual identity.

## Core Loop

1. **Aim** — rotate your mounted turret within a constrained firing arc
2. **Fire** — spend ammo from a finite clip to shoot projectiles at the puck
3. **Reload** — manually trigger a reload that refills the clip over time, creating timing risk
4. **Ricochet** — use arena walls and the puck's irregular contact shape for unpredictable deflections
5. **Score** — puck enters opponent's goal zone = 1 point, then resets to center until score limit reached

## Mechanics

### Ammo System
- Players start each round with a finite clip (target M1: 8 shots)
- Reloading is manual and refills one round at a time over a short interval
- Reload can be interrupted so you can fire whatever ammo has already been restored
- Ammo pickups are out of scope for M1; future variants can add alternate ammo types or arena refills
- Ammo types (future): standard, heavy (slow but high force), scatter, guided

### Puck Physics
- Rigid body using Godot's built-in 3D physics for the prototype
- Visual/core form reads like a ball so it rolls cleanly, but collision/contact geometry should become irregular or star-like to create unpredictable deflections
- Ricochets off arena walls with controlled energy loss (doesn't bounce forever)
- Multiple projectiles hitting simultaneously = big momentum transfer
- Puck speed cap to prevent instant-goal cheese

### Player / Turret
- Players are stationary mounted turrets in M1 — no player movement
- Core interaction is aiming left/right within a firing arc and choosing when to shoot or reload
- Turrets sit just inside their own goal line, creating an immediate offense/defense tradeoff
- Getting hit by projectiles or adding stun/elimination rules is deferred until the stationary-turret prototype proves fun

### Arena
- M1 starts with a rectangular arena roughly 20×12 units with goals at opposite ends
- Arena should be authored with future curvature/sloping in mind; a slight arc or grade can help the puck naturally drift back toward scoring spaces
- Corners should be beveled, rounded, or otherwise shaped so the puck does not get trapped
- Goals sit at opposite ends as slot/zone targets the puck must fully enter
- Possible arena hazards (future): bumpers, moving walls, gravity wells
- Multiple arena layouts for variety

### Scoring
- First to N goals wins (configurable: 3, 5, 7)
- Match timer optional (sudden death if tied at time)

## Camera

- **M1 camera**: top-down, centered to show the full arena and both turrets at all times
- **Future options**: isometric and first-person experiments can happen later if the prototype benefits from them

Top-down is the default because stationary turrets and ricochet planning both benefit from full-board readability.

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
- **Easy** — slow reaction, random-ish aim, weak reload timing
- **Medium** — decent aim, occasional bank shots, better reload timing
- **Hard** — predicts puck trajectory, uses bank shots, pressures during player reload windows
- **Brutal** — near-perfect aim, stronger defensive reads, minimal wasted shots

### AI Architecture
- M1 baseline: stationary opposing turret that sweeps aim, fires periodically, and reloads when depleted
- Later state machine can expand into Defend → Attack → Reload Pressure → Trick Shot behavior
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
│   ├── carom_arena.tscn      # Main 3D arena scene with goals, walls, camera
│   ├── carom_turret.tscn     # Mounted player / AI turret
│   ├── carom_puck.tscn       # Puck rigid body
│   └── carom_projectile.tscn # Ammo projectile
├── scripts/
│   ├── carom_game.gd         # Match state machine
│   ├── carom_arena.gd        # Arena setup and goal detection
│   ├── carom_turret.gd       # Aim, firing, reload behavior
│   ├── carom_puck.gd         # Puck physics helpers
│   └── carom_projectile.gd   # Projectile motion + impact logic
├── materials/
│   └── neon_grid.tres        # Arena visual materials (future)
└── shaders/
    ├── neon_trail.gdshader   # Projectile/puck trails
    └── impact_ripple.gdshader # Hit effects
```

### Physics Approach (M1 Decision)

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

**Recommendation**: Start with Option B for prototyping (get gameplay feel right), plan migration to Option A or C for multiplayer. This is the chosen M1 path.

## Milestones

### M1: Playable Prototype (Single Player)
- [ ] 3D arena with walls, goals, and anti-trap corners
- [ ] Stationary mounted turrets with aim-arc control (keyboard + touch)
- [ ] Shooting mechanic with finite clip and manual slow reload
- [ ] Puck physics using built-in 3D physics, including speed cap and naturally resolving arena flow
- [ ] Placeholder irregular puck contact setup (sphere first, star/compound follow-up)
- [ ] Basic scoring (first to 5)
- [ ] Single-player top-down camera
- [ ] Neon visual style (basic wireframe placeholders)
- [ ] Basic AI turret that aims and fires periodically

### M2: AI Opponent
- [ ] Expand beyond baseline turret AI into clearer difficulty tiers
- [ ] AI state machine (defend/attack/reload pressure)
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

- **Reload pacing**: How vulnerable should a player feel while manually reloading? Too slow = downtime, too fast = spam.
- **Puck irregularity**: How weird can the contact shape get before bounces feel unfair instead of exciting?
- **Arena curvature**: Is a subtle slope enough to prevent stalls, or should curvature be more explicit in the floor shape?
- **Corner treatment**: Which anti-trap corner shape preserves readability while keeping the puck live?
- **First-person viability**: Can you track a fast puck in first-person? May need aim assist or puck highlighting.
- **Cross-platform determinism**: If custom physics sim, need to ensure fixed-point math works identically on iOS/Android/PC.
- **Arena size**: Too big = boring downtime. Too small = chaotic. Needs to scale with player count.

## Integration with Sweet Vinegar Games

- Accessible from the main game selection menu alongside Sudoku, Shikaku, Blockudoku
- Shares: settings system, haptic manager, theme system (neon theme is natural fit), achievement system, analytics
- Does NOT share: 2D game infrastructure, board/grid systems
- New autoloads as needed: CaromMatchManager, CaromNetcode
