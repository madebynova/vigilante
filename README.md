# Vigilante

A single-player third-person action-adventure game focused on traversal, combat, and player-created approaches.

Built with Godot 4.8 (GDScript).

## Overview

Vigilante is an original grounded vigilante action-adventure built around the fantasy of a highly mobile urban hero: sprinting across rooftops, vaulting and climbing through the environment, diving through windows and using brief bullet time.

The project is at an early stage. The current build is the **first playable piece of the game**: a responsive third-person player controller and parkour toolkit, a compact, vertically layered city greybox built around that movement, and a first short mission (**Dead Drop**) that gives it something to do - get to a package on a rooftop however you like, bring it home, beat your time. A greybox test level proves out every move. Combat and the wider game are planned but not started.

## Current Development Status

**Implemented**

- Third-person player controller (walk, sprint, jump, crouch, air control)
- Third-person orbit camera with collision avoidance
- Parkour: vaults, mantles, ledge grab / hang / shimmy / climb-up
- Wall-running and wall-jumping (wall-to-wall across alleys up to about 3.5 m wide, with any input)
- Climbing on deliberately climbable surfaces (orange ladders, drainpipes, scaffold and crane ladders): up, down, sideways, jump off, let go, climb down from above
- Window traversal (a deliberate dive through an opening, in either direction, on foot or mid-jump)
- Grapple arrow: fire an arrow at an anchor point, then get pulled along its cable, on foot or in the air
- Timed bullet-time ability
- The Vigilante character model in the player scene: an idle loop while standing still, a neutral stance while moving (procedural lean, squash and tumble on top)
- Greybox movement test level with a traversal playground
- First playable city greybox: five districts on three traversal layers (street, mid-level, skyline), audited as one traversal network
- Day / night prototype: **N** toggles between a clear day and a readable night (moonlight, street lamps, lit windows, feature lights)
- Landing: tap crouch just before touching down to roll out with your speed; big drops without a roll stagger (height matters)
- First mission, **Dead Drop**: a rooftop objective, a return to the safehouse, a run clock, par ratings and a saved best time
- Game HUD: objective and distance, an on-screen marker and a light beam on the objective, run clock, grapple reticle (circle = usable anchor, crossed circle = not, with why), slow-time meter, contextual prompts
- Pause menu (Esc) and a controls panel (F1); the developer readout moved to F3
- Automated test suites (movement, traversal, city, game)

**Not implemented yet**

- Combat, weapons and enemies
- Grapple swinging, rope physics and grapple combat (the grapple arrow is a straight pull to anchor points only)
- Other arrow types and the arrow selection menu (the grapple arrow is the only arrow so far)
- Locomotion animations: walk, run, jump, climb and so on (the model only has the idle loop and the neutral stance; moves read through procedural lean, tuck and tumble, and a wall-run only leans the body off the wall)
- Story, more missions, progression, audio

## Core Gameplay

The game starts in the **city greybox** at night, inside the safehouse, with the first mission (see First Mission below). The city stays open the whole time: the mission only marks a destination, how you get there is up to you, and once it's done the city is yours to run around. The movement sandbox is still there: `scenes/main/main.tscn` puts you in a small test level built to exercise every movement feature: low and waist-high obstacles, climbable walls, a crouch tunnel, ramps, platform gaps, a building with windows, a short rooftop run, a grapple test area (a tower with a rooftop window facing a gap, and a second tower across it to grapple to), and a **traversal playground** west and south of the spawn (see below).

## Movement / Traversal

- **Locomotion:** camera-relative movement with quick acceleration and braking. Walk (5 m/s), sprint (9.5 m/s) and crouch (2.6 m/s). The character turns smoothly toward its movement direction.
- **Jumping:** variable jump height (tap vs hold), heavier gravity when falling, coyote time and jump buffering.
- **Crouching:** the collider shrinks; the player stays crouched under low ceilings and stands automatically once clear.
- **Camera:** mouse orbit with pitch limits, smoothed follow, a sphere cast that keeps the camera out of walls, and a slight FOV increase while sprinting.
- **Vaulting:** sprinting into (or pressing Space at) a low or waist-high obstacle vaults over it; deep obstacles are vaulted onto. E never vaults: it is for windows and ladders.
- **Ledges:** jumping at a wall grabs its ledge. From a hang you can shimmy, climb up (a **[SPACE] CLIMB UP** prompt shows) or drop. Walls too low to hang from are mantled directly.
- Parkour moves play as short scripted motions along smooth paths, so they read as physical actions rather than teleports.
- **Chaining:** a jump or grapple pressed during a vault, mantle or climb-up is kept and goes off the moment it ends (vault -> jump, vault -> grapple), so quick moves flow into the next one instead of eating the input.

## Landing

Height matters, and rolling is how to carry speed down from it.

- **Roll:** tap **C** just before touching down (within 0.3 s) to roll out of the landing: the speed is kept (at least 6 m/s), the body stays low for the roll (0.42 s) and you can steer a little. Jump late in the roll springs straight out of it; the grapple fires from a roll as usual. Rolling into a wall stops at it; rolling off an edge just falls on.
- **Hard landings:** without a roll, touching down faster than 22 m/s (about a two-storey drop) staggers for 0.35 s (most of the speed lost, no sprint or jump); faster than 30 m/s (about three storeys) floors you for 0.8 s. A one-storey drop, even with a running jump, never staggers. From that high a roll still keeps your speed but ends in the short stagger.
- The first hard landing shows a one-off tip about rolling.

## Wall-Run

A short, grounded run along a wall, driven by momentum and input rather than a scripted path.

- **Starting:** in the air, moving at least 7 m/s along a tall, near-vertical wall right beside you, while steering along it (e.g. sprint alongside a wall and jump, or let go of a grapple next to one and steer in). Low walls, railings, slopes, walking pace and running *into* a wall don't start one.
- **On the wall:** hold a direction along the wall to keep running. Speed is kept (extra momentum, e.g. from a grapple, bleeds off gradually as when sprinting). Going up follows a normal jump arc; coming down, the feet on the wall hold the fall to a slow slide.
- **Leaving:** **Space** wall-jumps: a normal jump's height, a push off the wall (6 m/s), and the speed along the wall kept. Letting go of the direction, steering away or **C** drops off with the current momentum. A run also ends when the wall does, after 1.2 s, if blocked, or on reaching the ground.
- **Wall-jump carry:** for the first 0.32 s after a wall-jump the jump always rises its full height (a quick tap of Space goes as far as holding it) and holding W no longer bends the push back along the wall. It never adds speed: steering only turns the momentum, and steering back toward the wall is ordinary air control. Air control is otherwise unchanged.
- **Wall to wall:** wall-run -> wall-jump -> steer along the other wall (W, or W + toward it) starts a run on it. Measured usable range (clear width between the walls): 2 - 3.5 m with any input (tap or hold, W or W + toward), 4 m with W + toward and Space held, 5 m out of reach. Every alley and slot in the city is 2.8 m. Steering *only* toward the other wall (not along it) doesn't start a run. Alternating wall-jumps between two walls climb about 1.2 m per jump, for as long as the walls go on (the pace along them is kept, never added to).
- **Wall-jump to a rooftop:** from a ground-level wall-run, roofs up to 4.5 m across a 2 - 4 m gap (a standing jump-and-grab tops out at 3.7 m); 5.5 m and up need a chain or the grapple.
- The wall you just left can't be run on again until you land or fire the grapple, so there is no re-sticking.
- **Grapple:** letting go of a grapple beside a wall and steering in turns straight into a wall-run with the momentum the release keeps (see Grapple Arrow). The grapple can be fired from a wall-run or after a wall-jump.
- **Camera:** while wall-running the camera moves to the shoulder away from the wall and rolls very slightly away from it; aiming stays entirely with the player.
- **Debug readout:** the debug readout (F3) shows `[WALL RUN READY]` when a jump right now would start a wall-run, `[WALL RUN]` / `[WALL JUMP]` while it happens, and why a wall beside you isn't runnable yet (`wall: too slow along it`, `wall: steer along it`, `wall: get closer`, ...).

## Climbing

A controlled climb on surfaces the level marks as climbable, never on ordinary walls.

- **What's climbable:** only geometry on the `climbable` physics layer (layer 3): in the city these are the **orange** ladders, drainpipes, scaffold ladders and the crane's mast ladder. Everything else stays a wall, a ledge or a run surface.
- **Getting on:** **E** or **Space** facing one within reach (on the ground), or jump into one while holding toward it. Walking or sprinting into one never grabs it. A contextual **[E] CLIMB** prompt shows exactly when E will grab one.
- **On it:** **W / S** climb up (2.4 m/s) and down (3.5 m/s), **A / D** move sideways (as the camera sees it), each only while the surface carries on that way. At the top, holding W pulls up onto whatever the surface leads to (a roof, a landing, a deck); at the bottom S steps off onto the ground, or lets go of a surface that ends in mid-air.
- **Getting off:** **Space** jumps away from it (a push off plus a normal jump's rise), **C** lets go, **Right mouse** fires the grapple as usual. A surface just left can't be re-grabbed for 0.4 s.
- **Descent:** **E** standing at a roof edge above a climbable surface swings over onto it (prompt **[E] CLIMB DOWN**); hanging from a ledge above one, **S** climbs down it instead of dropping.
- Not an automatic or cinematic system: every step is the player's input, and there is no stamina yet.

## Bullet Time

A timed slow-motion ability.

- **F** activates it while airborne with a real drop below (at least 1.5 m), for example after leaving a roof edge. Space is only ever jump / wall-jump. It is also the easy way to time a roll on a big drop.
- Slows the game to **0.3x** for **0.4 s** (real time), with a subtle camera FOV tightening, then ends automatically.
- Recharges for **4 s** before it can be used again. A thin **SLOW TIME** meter under the prompt shows it running and recharging, and disappears once it is ready.
- Window dives also trigger it at takeoff (if it is ready).

## Window Traversal

- **Dive windows:** line up with the opening within about 3 m and press **E** to dive through. A contextual **[E] DIVE THROUGH** prompt appears only when the dive is available.
- Works from **either side**: outside to inside and inside to outside. The direction comes from the side the player is on.
- No run-up is needed; the dive always runs at sprint pace and exits with momentum.
- It also works **mid-jump**: jump toward the window and press E in the air to dive straight through. An E pressed a moment early (up to 0.15 s before the window is in reach) still counts.
- From right under the sill the move first rises in front of the wall and then goes through the opening, so the body never passes through the wall below the window.
- Diving out of a **high window** with nothing to land on hands the momentum over to a normal fall, ready for a grapple.
- Diving out onto a **narrow landing** (a balcony, a fire escape walkway: less than about 1.6 m of floor beyond the landing point) tumbles to a stop on it instead of carrying the dive's speed straight off its edge, so window -> fire escape -> stairs works as a route.
- Running, sprinting or jumping into a window does nothing on its own; it is always a deliberate button press. A window's sill is never used as a vault or a ledge to climb through.
- **Plain windows** (test level only): E climbs through, or vaults through when moving fast. Like dive windows they are never taken without E.

## Grapple Arrow

The Vigilante's grapple is a fired arrow, used for building-to-building traversal.

- **Anchor points** are placed in the level as small glowing markers. The one you are aiming at (camera centre, within 35 m, with line of sight) brightens.
- **Reticle:** a faint dot marks the camera centre. The anchor a press would fire at gets an amber **circle** (with the key, RMB; dim and filling up while the next arrow nocks). An anchor right under the aim that can't be used gets a red **crossed circle** saying why - **OUT OF RANGE**, **TOO CLOSE** or **NO LINE OF SIGHT** - but only if the camera can see it, or it's close (within 14 m) and just round a corner: the reticle never reveals anchors hidden behind buildings. Round the corner, with a clear line, it's a normal target again.
- **Balance - an extension, not the way to travel:** the grapple is strongest when it extends a movement line. Fired on the move (sprinting, jumping, diving out of a window, falling, off a wall-run) it pulls at **22 m/s**; from a standstill it winches at **13 m/s** (a walk gets about 17). After a grapple ends, the next arrow takes **1 s** to nock - unless a parkour move (vault, mantle, ledge grab, wall-run, window, climb, roll) comes first, which nocks it at once. So grapple -> parkour -> grapple flows, grapple -> grapple waits a beat. Range stays 35 m so wall-jump -> grapple and window -> grapple lines keep working (a measured 30 m cut mostly hit those).
- **The world wins:** if something gets between the player and the anchor during the pull (the cable would pass through it), or the body is driven head-on into a wall or overhang short of the ledge, the pull lets go (after 0.1 s) with the usual release rules. Nothing drags or launches the player through geometry; hold toward the wall and a ledge in reach is caught, or a wall-run, a window or a fall and roll takes over.
- Press **Right mouse** to fire a **grapple arrow** at it. The arrow flies to the anchor (80 m/s, slowed by bullet time like everything else) trailing its cable, and sticks in it. While it flies the player keeps their momentum; only once it has attached is the player pulled along the cable, hopping onto the ledge the anchor sits on. Works on foot or in the air, including straight out of a window dive.
- Press again to let go, either while the arrow is still flying or during the pull. Letting go keeps the way you were going but only what a body carries on with: at most 12.5 m/s across and a jump's rise (8 m/s) upward, never more than the pull itself. Let go under a ledge and you can catch it (holding toward it grabs the ledge or mantles); let go by a wall and you drop along it instead of being launched past the edge. Falling speed is always kept.
- If the arrow can't hold (something blocks its path, its anchor goes away, or it flies too long) the grapple ends without a pull.
- It never fires on its own. With no valid target, the press does nothing.
- The arrow is a placeholder model (claw head, shaft, fletching) built in code until a real arrow asset exists.
- The core loop it proves: **jump → E window dive → bullet time → fire grapple arrow → it attaches → pulled → next building**, repeatable in the grapple test area (walk up the ramp beside the first tower; the second tower has an anchor back).

## Traversal Playground

A compact greybox course for learning and testing the movement, in five separated sections. Each has a sign at its start, and **1 - 5** jump straight to it. Colours: **brown** walls are runnable, **teal** buildings carry a grapple anchor on top, **blue** blocks are platforms and rooftops, **green** are ramps, **yellow** low walls and the **purple** slab are deliberately not runnable, **grey** buildings have windows.

1. **Basic wall-run** - a 30 m straight wall with a long runway (wall on the left), an angled wall (wall on the right), and a low wall and a steep slab that won't take a wall-run.
2. **Wall-run -> wall-jump** - a tall wall and, across a 3 m gap, a 4 m rooftop no jump from the ground reaches: run the wall, wall-jump across, grab the edge. From that roof the same trick reaches an 8 m block.
3. **Wall-run -> grapple** - a ramp to a deck, a long wall to run at height, a 14 m grapple tower ahead, a low roof to jump or drop to and open ground: continue, wall-jump, grapple, drop or steer.
4. **Wall-run -> window** - ramp up and run the building's wing wall, wall-jump about halfway (the push lines you up with the upper window), E through it; the far window dives out high toward a grapple tower. Geometry for the future window chain.
5. **Open traversal** - two parallel runnable walls, low walls, stepped platforms, decks with a 2.5 m (jump) and a 7 m (wall-run) gap, a house with a dive window and a plain window, and two grapple anchors.

## First Mission: Dead Drop

The first slice of the actual game loop: **start -> clear objective -> traverse -> reach it -> satisfying finish**, kept deliberately small.

- **Premise:** a courier has left a package on the **Hotel roof** for a pickup tonight. Get to it first, then bring it back to the **safehouse**.
- **Start:** the game opens at night inside the safehouse with a short briefing. The run clock starts on your first move (looking around doesn't count).
- **Objective 1 - Intercept the drop:** a light beam rises from the package on the north end of the Hotel roof (17.5 m), visible across the city; the HUD shows the objective, the distance and a marker (pinned to the screen edge, pointing the way, when it's off screen). Touching the package picks it up.
- **Objective 2 - Bring it home:** the beam moves to the safehouse. Any way into the building counts: the street door, the loft's dive windows, or landing on its roof.
- **Finish:** a beat of slow motion, **DELIVERED**, your time, your best, a rating against par (**gold 0:22**, **silver 0:35**, **bronze 1:00**) and the next one to beat. The city stays open afterwards; **R** runs it again from the safehouse (R restarts at any time).
- **Routes (none required):** out of the door and grapple up the walk-up across South St, then grapple the Hotel's water tower; or jump the hotel yard from the walk-up roof and **E** in through the Hotel corridor's window (slow time), run through, dive out of the far end onto the fire escape and up; or the Hotel's fire escape from North Ave (drop ladder or jump-and-grab); or the North Ave grapple onto the roof edge; or across the catwalk from the service tenement. Home again: grapple down to the walk-up, then across South St onto the safehouse roof, or drop to the street and roll.
- **Records:** best times are saved in `user://vigilante.cfg` (only clean runs: a debug jump with the number keys marks the run and its time isn't saved or rated).
- **Built to grow:** a mission is data in a scene - a `Mission` node with `MissionStep` children, each an area to reach with its objective text - so the next mission is a new set of steps rather than new code (`scripts/game/`).

## City Greybox

The first playable city: a compact, dense, hand-placed greybox (about 132 x 142 m inside a ring of plain backdrop blocks) that gives the existing movement somewhere to exist. No new mechanics: every route below uses the movement exactly as it is. It is laid out on three layers that connect everywhere - **street** (avenues, alleys, a yard, a parking lot, plazas, a few interiors), **mid-level** (fire escapes, awnings, balconies, low roofs, decks, a skybridge, dive windows) and **skyline** (towers, setbacks, a crane, long grapple gaps) - and presents problems rather than paths: most spots can be left several ways.

**Districts** (debug keys **1 - 5** jump to each):

1. **Safehouse** (south) - start point and future base: a two-storey brick workshop with a street door, an inner stair to a loft and an outside stair to the roof. Its courtyard repeats playground route 4 at the same proportions: run off the loading deck along the courtyard wall, wall-jump, **E** in through the loft's back window, **E** out of the front window high over South St, grapple across. Around it: a parking lot with a billboard catwalk, a corner plaza, a row of walk-ups (fire escape, climbable facade, roof-to-roof steps) and a back lot with a water tank.
2. **Dense blocks** (centre, either side of Central Ave) - **Needle Alley** (see below); west of it the **hotel yard**, with a fire escape up the walk-up and an anchor on its roof edge; the **Hotel** (17.5 m): a fire escape on North Ave (drop ladder, level 2 runs into a wall-run along the north face), a corridor right through its fourth storey (E in from the fire escape's third level, E out over the hotel yard, grapple the walk-up) and a catwalk from its roof to the service tenement's across the lane; the **Window Building**, whose top floor has a dive window on every side: in from the walk-up roof across a light well or from the alley's top ledge, out over Central Ave (grapple across), over the alley (straight onto the roof opposite) or over South St (grapple home). East of the avenue: a corner block (fire escape from South St), a brick slot, and a stepped office carrying the skybridge, with a fire escape all the way up its tower on East St.
3. **Service yard** (west) - a loading yard ringed by three fire escapes (one to the tall tenement's roof) around a raised deck; a tenement whose brick flank runs past a gap (sprint along it from the walk-up roof, wall-run over the gap, wall-jump across the slot onto the next roof, grapple up); a brick slot beside a low workshop (wall-run, wall-jump, grab a roof no jump reaches).
4. **Mid-rise roofs** (east) - roofs to run at speed: skybridge in, a 3 m gap up to a roof 3.5 m higher (jump and grab), a drop-gap, then a 9 m gap no jump clears, with a tall block's brick flank alongside for a wall-run across. The loop carries on: from the south gap roof, grapple across South St to the tall walk-up's north edge (or take its fire escape down).
5. **Skyline** (north) - the **construction site** (see below) beside a tower crane (mast ladder, machinery deck at 30 m, walkable jib), the Meridian tower (38 m) with a terrace on North Ave, Spire Plaza and the **Spire** landmark (28 / 42 / 56 m setbacks, each deep enough to grapple the next), and two towers stepping down to the mid-rise roofs. The long skyline gap is Meridian to Spire across Central Ave (~25 m).

**Needle Alley** - a compact 14.5 m slot, 2.8 m clear, between the avenue block and the Window Building, open to Central Ave and to the hotel yard. Both walls are brick for wall-run -> wall-jump -> wall-run chains, and ledges alternate across it on the way up, each a jump across and up from the last: south at 3.5 m (a drainpipe or a jump-and-grab from the alley), north at 7 m (the avenue block's roof is a grab above it), south at 10.5 m in front of the Window Building's north window (E in; its roof is a grab above). Either roof, either building, from either wall - a route up rather than a ladder.

**Construction site** - a traversal landmark with no set path: a scaffold on its south face (drop ladder or jump-and-grab, flights to 7 m and on to floor 3 at 10.5 m); a 4 m light shaft beside a brick lift core (sprint in, wall-run the core, wall-jump across and grab a floor edge: 3.5 m from the street, 7 m from floor 1); floor 2's unfinished corner; floor 4 half-poured with two steel beams out over the open bay (walk out, jump off, grapple across North Ave to the service tenement); a site office on floor 4 with dive windows south (grapple the tenement) and east (grapple the Meridian terrace); plank ramps (forecourt -> floor 1, floor 3 -> floor 4); a stair tower to every level; floors stepping up to 24.5 m; the crane's mast ladder through a hatch to its deck, a jump down to the top slab, a grapple to the Meridian roof.

**Grapple**: 31 anchors, deliberately not on every roof (new this pass: the hotel yard, the courtyard's loading deck - reached from the billboard catwalk - and the tall walk-up's north edge, across South St from the mid-rise roofs), with short (~6 m), medium and long (up to ~33 m) pulls. **Wall-runs**: brick panels mark the intended surfaces; facades broken up by fire escapes, awnings and balconies don't carry a run. **Windows**: 10 dive windows (E only, never automatic), yellow-framed; the flat dark glass on facades is scenery (about a third of it lights up at night). **Ledges**: awnings (3.5 m) are a jump-and-grab from the street, a balcony 3.5 m above an awning is the next grab, and the roof 3.5 m higher the one after. **Fire escapes**: every level is a 0.5 m slab, so its edge is grabbable like an awning (the first level is a jump-and-grab from the street); the hotel's has a drop ladder instead of a street stair and its second level runs straight into a wall-run along the north face; the mid-rise gap roof has a new one with a ladder up its last 1.5 m. **Climbing**: ladders and drainpipes where a roof had only one way up - the billboard catwalk, the tall walk-up (from its neighbour's roof), both mid-rise gap roofs, the Window Building's roof, the service yard's gap roof - plus the scaffold and crane ladders; a dumpster in the service yard is the step up to the workshop roof; a ledge on the diner's east side turns the walk-ups' plaza wall-run into a way onto the diner roof. **Buildings**: important buildings have doors, windows and routes in (the hotel corridor, the Window Building's top floor, the safehouse, the site office); most others are scenery with doors and glass. **Rooftops**: vents, plant rooms and roof huts to vault, climb or duck behind; parapets only on tall roofs' edges that no route uses (a parapet stops edge grabs and grapple hops).

**Colours**: brick = runnable wall, orange = climbable (ladders, drainpipes), yellow frame = dive window (flat dark glass is scenery), slate blue = rooftops / decks / platforms, green = fire escapes, stairs, bridges, beams, pale green = awnings, balconies and ledges (grabbable), teal = carries a grapple anchor, dark grey = utility props; building bodies are tinted per district and the safehouse is dark red brick.

The layout is authored in `tools/city/` (one script per district, every number placed by hand) and baked into `scenes/city/city_greybox.tscn`; re-run the builder after changing it (see Development Notes).

## Day / Night

A deliberately simple prototype for judging the city in both lights: no clock, no schedule.

- **N** toggles between **day** and **night** (a 1.5 s blend, in real time so bullet time doesn't stretch it). The debug readout (F3) shows `DAY (N)` / `NIGHT (N)`. The first mission opens the city at night (`Mission.start_at_night`).
- **Day**: the clear, grounded look the city was built in - strong sun, sky-lit ambient, light haze.
- **Night**: a dark blue sky with a slightly brighter horizon so roofs stand out, a cool moon from the south-west, a flat bluish ambient light so every surface stays readable before any lamp, a touch of fog and glow. Street lamps, feature lights (billboard floodlight, construction work lights, the rooms behind dive windows, the hotel corridor, Needle Alley), glowing bulbs, aviation lights on the crane and the Spire, the diner's neon, and about a third of the facade windows light up warm.
- Movement, the grapple, bullet time and everything else play exactly the same at night.
- Built so a real time of day can drive it later: `DayNight.blend` (0 day .. 1 night) is the whole state (`scripts/world/day_night.gd`). The city's night pieces are found by group: `night_lights`, `night_glow`, `city_lit_windows`.

## Controls

| Input | Action |
|---|---|
| W A S D / arrow keys | Move (camera-relative) |
| Shift | Sprint |
| Space | Jump · vault · wall-jump during a wall-run |
| F | Bullet time (in the air, over a drop) |
| C / Ctrl | Crouch (hold) · tap just before landing to roll · drop off a wall-run |
| E | Dive through a window · grab a ladder / climb down onto one from a roof edge (windows and ladders only) |
| Right mouse | Fire a grapple arrow at the anchor you are aiming at (press again to let go) |
| While hanging | Space / E climb up · A / D shimmy · C drop · S climb down onto a ladder below |
| While climbing | W / S up / down · A / D sideways · Space jump off · C let go · Right mouse grapple |
| Mouse | Orbit camera |
| Esc | Pause menu (resume, restart the run, quit) with the controls |
| Left click | Recapture the mouse |
| R | Restart the run from the safehouse (respawn in the test level) |
| F1 | Show / hide the controls panel |
| F3 | Debug readout (state, speeds, wall-run hint, FPS) |
| 1 - 5 | Debug: jump to a city district (city) / traversal playground section (test level) |
| N | Debug: toggle day / night (city) |

## Technology

- **Engine:** Godot 4.8 (Forward+ renderer, D3D12 on Windows)
- **Language:** GDScript
- **Physics:** Jolt Physics, with physics interpolation enabled
- **Default resolution:** 1920x1080 (UI scales with the window)
- **Level art:** greybox blocks with a world-space grid shader

## Project Structure

```
assets/
  characters/vigilante/   Vigilante character model (GLB)
scenes/
  main/                   city_main (city + player + first mission + HUD and pause menu, the run scene), main (test level)
  city/                   City greybox (baked by tools/city)
  player/                 Player scene
  test/                   Greybox movement test level
scripts/
  game/                   Missions (Mission, MissionStep), the drop package, the objective beacon, save data
  ui/                     Player HUD (grapple reticle, slow-time meter), mission HUD, pause menu, shared UI style
  player/                 Controller, camera, visuals, bullet time, grapple, prompt
  arrows/                 Arrow projectiles (grapple arrow)
  movement/               Locomotion math, tuning settings, scripted motions
  parkour/                Parkour sensor, parkour moves, traversal windows, grapple anchors
  level/                  Greybox block and grid shader
  world/                  Day / night, facade windows
  debug/                  Debug readout (F3)
tests/
  movement_test.gd        Automated movement test suite (test level)
  traversal_test.gd       Wall-jump reach, climbing and window regressions in a bare lab built in code
  city_test.gd            City greybox routes and map-wide checks
  game_test.gd            Landing roll, grapple release / balance / obstruction, held input, reticle, prompts; the mission (with and without grapple), pause and controls
tools/
  city/                   City layout (one script per district), the builder that bakes it, the traversal audit
```

## Development Notes

**Running the project:** open the folder in Godot 4.8 and run the project: it starts in the city with the first mission (`scenes/main/city_main.tscn`). The movement test level and traversal playground are in `scenes/main/main.tscn` (open it and use Run Current Scene; its debug readout is on by default).

**Automated tests:** the suite drives the real main scene through the input system and checks movement, camera, parkour, wall-running, window traversal, bullet time, the grapple arrow and the character model.

```
godot --headless --path . -s res://tests/movement_test.gd
```

Add `-- --shots=<folder>` (without `--headless`) to also save screenshots.

**Traversal lab:** builds a bare lab in code with the city kit and measures the wall-jump (wall-to-wall range over widths, tap vs hold, chains, rooftops, grapple), climbing (every way on and off, descent, never by accident) and the window regressions (no way through a window but E, and no clipping through the wall under the sill).

```
godot --headless --path . -s res://tests/traversal_test.gd
```

**Game checks:** the landing roll and hard landings, letting go of the grapple by a wall, the grapple's momentum pull and nocking, a wall appearing mid-pull, reticle visibility behind walls, input held through quick moves, the early-E window dive, E never vaulting, the reticle readout and prompts (in a lab built in code), then the mission in the real city: briefing, a full run (street -> grapple -> grapple -> package -> grapple home), the drop by parkour alone (corridor windows and the fire escape, no grapple), window -> turn 180 -> grapple, best time, restart, debug-assisted runs, pause, F1 and F3, and the roll tip. It saves to its own `user://game_test.cfg`, never to the real save.

```
godot --headless --path . -s res://tests/game_test.gd
```

**City checks:** plays the intended city routes (with the mission switched off) through the input system and sweeps the map: every anchor pulled to from a real standing spot, the whole map as one traversal network (below), day / night, camera clearance at many spots and angles, a street-level flood fill for places to get stuck, and open-space coverage.

**Traversal network audit:** `tools/city/traversal_audit.gd` maps every elevated walkable surface and links them with the moves the player has (walk, stairs, ladder, jump-and-grab using the real ledge probe, running jumps, dive windows, grapples using the real line-of-sight check; wall-runs deliberately not assumed). The city test requires every surface to be reachable from the street, no dead-end roofs, at least two kinds of way up from the street in every district and every anchor usable. For a printed per-district report:

```
godot --headless --path . -s res://tools/city/audit_city.gd
```

```
godot --headless --path . -s res://tests/city_test.gd
```

**Rebuilding the city:** the layout lives in `tools/city/district_*.gd`. After editing it, bake the scene again. This overwrites `scenes/city/city_greybox.tscn`, so make layout changes in the scripts, not in the editor:

```
godot --headless --path . -s res://tools/city/build_city.gd
```

**Tuning:** movement values live in the `MovementSettings` resource on the player. Camera, parkour, window and bullet-time values are exported properties on their respective nodes.

## Future Development

Planned, not yet implemented:

- Animating the Vigilante character beyond the idle (walk, sprint, jump, fall, land, crouch, climb)
- An arrow selection menu and more arrow types alongside the grapple arrow
- Building on the grapple: swinging and grapple combat
- Combat
- Growing the city greybox into the real game world (the day / night structure, investigation, patrols and missions will live in it; none of that is implemented yet)
- Climbing: animation, stamina (if wanted), more climbable surface kinds (the layer-based setup already takes any shape)

## Future Architecture Notes

**Free-aim grapple (not implemented).** Targeting is already a single query, `Grapple.find_target()` (placed anchors in range, in the aim cone, in line of sight); the arrow, cable and pull only consume its result. Moving to free aim would need:
- A target value instead of a node: e.g. a `GrappleTarget` (point, surface normal, collider, optional anchor) returned by target finders. Placed `GrappleAnchor`s become one finder; a second one raycasts the camera aim against a **grappleable** physics layer (the same way climbing uses the `climbable` layer), so level geometry opts in deliberately.
- `GrappleArrow.launch()` flying to a point and sticking to the collider (following it if it moves), instead of to an anchor node.
- The pull's arrival: today it hops over the ledge the anchor sits on. For a free point it should check for a standable ledge at the point (`ParkourSensor.detect_ledge`) and hop only then; otherwise end hanging or let go with the momentum.
- The `grapple_fired` / `grapple_started` signals and the tests carry a `GrappleAnchor` today and would carry the target value.

**Aim-bow slow time (not implemented).** Desired chain: aim bow -> slow time -> fire -> grapple -> release -> steer. The current `BulletTime` is a timed burst (0.3x for 0.4 s, 4 s recharge) that owns `Engine.time_scale`; its timers run on real time, and the camera already corrects for the time scale, so nothing blocks a hold-based mode. The cleanest way in:
- Turn `BulletTime` into the single owner of time scale with requests by source: the existing burst (F, window dives) and a hold (`begin_hold(&"aim")` / `end_hold(&"aim")`) that drains a focus meter while held and recharges after; the effective scale is the lowest active request.
- Aiming as an overlay flag on the player, not a new state, so it works on foot, in the air, on a wall-run or a climb; the camera gets an aim framing (closer shoulder, tighter FOV).
- Input: aim becomes Right mouse held and fire the left button, with the grapple arrow as one arrow type; that replaces today's "Right mouse fires the grapple" and belongs with the planned arrow selection.
