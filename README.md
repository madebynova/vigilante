# Vigilante

A single-player third-person action-adventure game focused on traversal, combat, and player-created approaches.

Built with Godot 4.7 (GDScript).

## Overview

Vigilante is an original grounded vigilante action-adventure built around the fantasy of a highly mobile urban hero: sprinting across rooftops, vaulting and climbing through the environment, diving through windows and using brief bullet time.

The project is at an early stage. The current build is a **movement foundation**: a responsive third-person player controller, a parkour toolkit and a small greybox test level to prove out how the character feels to control. Combat and the wider game are planned but not started.

## Current Development Status

**Implemented**

- Third-person player controller (walk, sprint, jump, crouch, air control)
- Third-person orbit camera with collision avoidance
- Parkour: vaults, mantles, ledge grab / hang / shimmy / climb-up
- Window traversal (a deliberate dive through an opening, in either direction)
- Timed bullet-time ability
- The Vigilante character model in the player scene (static for now)
- Greybox movement test level
- Automated movement test suite

**Not implemented yet**

- Combat, weapons and enemies
- Grappling / building-to-building traversal
- Character rigging and animations (the model is currently a static, unrigged mesh)
- Story, missions, progression, audio

## Core Gameplay

The current build is a movement sandbox. You control the Vigilante in a small test level built to exercise every movement feature: low and waist-high obstacles, climbable walls, a crouch tunnel, ramps, platform gaps, a building with windows and a short rooftop run.

## Movement / Traversal

- **Locomotion:** camera-relative movement with quick acceleration and braking. Walk (5 m/s), sprint (9.5 m/s) and crouch (2.6 m/s). The character turns smoothly toward its movement direction.
- **Jumping:** variable jump height (tap vs hold), heavier gravity when falling, coyote time and jump buffering.
- **Crouching:** the collider shrinks; the player stays crouched under low ceilings and stands automatically once clear.
- **Camera:** mouse orbit with pitch limits, smoothed follow, a sphere cast that keeps the camera out of walls, and a slight FOV increase while sprinting.
- **Vaulting:** sprinting into (or pressing Jump / E at) a low or waist-high obstacle vaults over it; deep obstacles are vaulted onto.
- **Ledges:** jumping at a wall grabs its ledge. From a hang you can shimmy, climb up or drop. Walls too low to hang from are mantled directly.
- Parkour moves play as short scripted motions along smooth paths, so they read as physical actions rather than teleports.

## Bullet Time

A timed slow-motion ability.

- **Space** activates it while airborne with a real drop below (at least 1.5 m), for example after leaving a roof edge. Normal jumps and buffered jumps are unaffected.
- Slows the game to **0.3x** for **0.4 s** (real time), with a subtle camera FOV tightening, then ends automatically.
- Recharges for **4 s** before it can be used again.
- Window dives also trigger it at takeoff (if it is ready).

## Window Traversal

- **Dive windows:** line up with the opening within about 3 m and press **E** to dive through. A contextual **[E] DIVE THROUGH** prompt appears only when the dive is available.
- Works from **either side**: outside to inside and inside to outside. The direction comes from the side the player is on.
- No run-up is needed; the dive always runs at sprint pace and exits with momentum.
- Running or jumping into a dive window does nothing on its own; it is always a deliberate button press.
- **Plain windows** behave like regular obstacles: sprinting into one vaults through it, and E / Jump climbs through.

## Controls

| Input | Action |
|---|---|
| W A S D / arrow keys | Move (camera-relative) |
| Shift | Sprint |
| Space | Jump · bullet time when airborne over a drop |
| C / Ctrl | Crouch (hold) |
| E | Dive through a window · vault / climb elsewhere |
| While hanging | Space / E climb up · A / D shimmy · C drop |
| Mouse | Orbit camera |
| Esc / left click | Release / recapture mouse |
| R | Respawn (debug) |
| F1 | Toggle the on-screen controls help |

## Technology

- **Engine:** Godot 4.7 (Forward+ renderer)
- **Language:** GDScript
- **Physics:** Jolt Physics, with physics interpolation enabled
- **Default resolution:** 1920x1080 (UI scales with the window)
- **Level art:** greybox blocks with a world-space grid shader

## Project Structure

```
assets/
  characters/vigilante/   Vigilante character model (GLB)
scenes/
  main/                   Main scene (level + player + debug HUD)
  player/                 Player scene
  test/                   Greybox movement test level
scripts/
  player/                 Controller, camera, visuals, bullet time, prompt
  movement/               Locomotion math, tuning settings, scripted motions
  parkour/                Parkour sensor, parkour moves, traversal windows
  level/                  Greybox block and grid shader
  debug/                  On-screen debug HUD
tests/
  movement_test.gd        Automated movement test suite
```

## Development Notes

**Running the project:** open the folder in Godot 4.7 and run the main scene (`scenes/main/main.tscn`).

**Automated tests:** the suite drives the real main scene through the input system and checks movement, camera, parkour, window traversal, bullet time and the character model.

```
godot --headless --path . -s res://tests/movement_test.gd
```

Add `-- --shots=<folder>` (without `--headless`) to also save screenshots.

**Tuning:** movement values live in the `MovementSettings` resource on the player. Camera, parkour, window and bullet-time values are exported properties on their respective nodes.

## Future Development

Planned, not yet implemented:

- Rigging and animating the Vigilante character (idle, walk, sprint, jump, fall, land, crouch)
- Grappling and building-to-building traversal, including diving out of tall windows in bullet time
- Combat
- A playable environment beyond the movement test level
