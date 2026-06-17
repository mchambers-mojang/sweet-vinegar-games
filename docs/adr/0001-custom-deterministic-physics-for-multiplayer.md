# 0001 — Custom Deterministic Physics for Multiplayer

**Status:** Accepted  
**Date:** 2025-06-14  
**Deciders:** @mchambers-mojang

## Context

Carom M4 adds internet multiplayer (PC vs phone) with rollback netcode. Rollback requires that both peers produce bit-identical simulation results from the same inputs. Godot's built-in Jolt physics is not deterministic across platforms — floating-point rounding differs between ARM (mobile) and x86 (desktop).

## Decision

Build a custom 2D deterministic physics simulation in GDScript using 64-bit fixed-point arithmetic (48.16 format). The sim lives in `carom/scripts/sim/` as pure RefCounted classes with zero Godot scene-tree dependencies.

### Key properties

- **Fixed-point only** — all positions, velocities, and collision math use integer arithmetic with 16 fractional bits. No IEEE 754 floats in the sim.
- **2D on the XZ plane** — Carom's gameplay is effectively top-down; Y-axis is unused in the sim (rendered in 3D but simulated in 2D).
- **Pure data** — the sim module has no Node inheritance, no signals, no scene-tree access. Existing scene scripts become thin render adapters that interpolate visual state from sim snapshots.
- **GDScript** — object count is small (~25 bodies max: 1 puck, ~20 projectiles, 4 walls, 2 goals). Re-simulating 10 rollback frames within one frame budget is trivial at this scale.

### Collision shapes needed

- Circle (projectiles, puck rolling core)
- Convex polygon (puck contact prism — 3 edges projected flat)
- Line segments (arena walls)
- Point-in-zone (goal detection)

## Alternatives Considered

1. **Godot Jolt with "hope for the best"** — Rejected. ARM vs x86 float divergence is well-documented and would cause desyncs within seconds of play.
2. **Software float library (soft-float)** — Deterministic but 20-30% performance overhead and poor GDScript ecosystem support.
3. **GDExtension in C/C++** — Overkill for ~25 bodies. Adds build complexity (cross-compile for mobile). Can port later if needed.
4. **Lockstep instead of rollback** — Rejected. Lockstep adds perceived input lag equal to round-trip time, unacceptable for a reflex-based shooting game on cellular connections.

## Consequences

- All gameplay tuning values (speeds, damping, arena dimensions) must be expressed in fixed-point, making iteration slightly more verbose.
- Unit tests can run thousands of sim frames per second without a scene tree — excellent for regression testing determinism.
- Future 3D gameplay (FPS milestone) will require extending the sim to 3D, but the architecture (pure data, fixed-point) carries over.
- Rendering must interpolate between sim frames for smooth visuals at display refresh rates above 30 Hz.
