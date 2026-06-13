# Sweet Vinegar Games

A multi-game collection app published under the Sweet Vinegar brand. Contains games of any genre sharing a common platform layer (settings, themes, replays, analytics, haptics).

## Language

**Collection**:
The Sweet Vinegar Games app itself — a container that hosts multiple Games and provides shared platform services.
_Avoid_: Suite, launcher

**Game**:
A distinct playable experience within the Collection, with its own rules, UI, and progression. Each Game is self-contained but shares platform services.
_Avoid_: Mode (when referring to a whole game), mini-game, level

**Mode**:
A variation within a single Game (e.g., difficulty tier, solo vs AI). Not used to refer to the Games themselves.
_Avoid_: Using "mode" to mean a distinct Game

**Platform**:
The shared layer of autoloaded services that every Game in the Collection depends on: settings, sound, haptics, themes, analytics, save/load, scene transitions, crash reporting, replay, safe-area management.
_Avoid_: Framework, engine, core (too vague)

**Hub** _(synonym: Main Menu)_:
The game picker screen — entry point into the Collection where the player selects which Game to play.

**Game Menu**:
A per-Game setup screen shown before play begins (e.g., difficulty selection, puzzle size). Not every Game requires one.

**Game Screen**:
The active play surface where gameplay happens. Owns its own UI, input handling, and state.

**Session Persistence**:
The Platform's ability to save and restore a Game's in-progress state across scene transitions. Each Game serializes/deserializes its own state; the Platform provides the storage layer.

**Replay**:
A recorded sequence of player actions (not video) that can re-simulate a play session. Each Game defines its own action vocabulary (e.g., cell placements for puzzles, shot angle + timing for Carom). Stored and managed by the Platform's ReplayManager.

## Carom

_Design principle: Carom is a **real-physics game**. All motion — Projectile travel, Puck deflection, wall bounces — is resolved by the physics engine (RigidBody3D collisions), never faked with tweens, animations, or scripted movement._

**Carom**:
A physics-based arena Game inspired by the board game Crossfire. Two Turrets face off across an Arena, firing Projectiles to push Pucks into the opponent's Goal. First to a target score wins.

**Arena**:
The bounded 3D playfield containing the floor, walls, Goals, and spawn points. Slightly sloped so Pucks drift toward Goals and never stall.

**Turret**:
A stationary, rotatable weapon controlled by a player or AI. Fires Projectiles and has limited ammo that reloads over time.

**Projectile**:
A physics body fired from a Turret. Bounces off walls, Pucks, and other Projectiles. Pushes Pucks via natural collision. Never destroyed on contact.
_Avoid_: Bullet (implies destruction)

**Puck**:
The scoring object. Irregularly shaped so momentum is unpredictable. Pushed by Projectile collisions toward a Goal. Multiple Pucks may be in play simultaneously.
_Avoid_: Ball (shape is intentionally non-spherical for gameplay)

**Goal**:
The scoring zone behind each Turret. A Puck entering a Goal scores a point for the opposing player.

**Match**:
A single competitive session of Carom — from kickoff to one side reaching the score target. A Match has exactly two Turrets, one or more Pucks, and a Difficulty Tier governing the AI.

**AI Controller**:
The state-machine brain driving the AI Turret. Cycles through behaviors (Attack, Defend, Reload Pressure, Trick Shot) based on Puck state and ammo.
_Avoid_: Bot, opponent (too informal for code/doc)

**Difficulty Tier**:
A named preset (Easy, Medium, Hard, Brutal) that scales the AI Controller's reaction speed, aim precision, fire rate, and tactical decision quality. A property of the AI, not the Match.

