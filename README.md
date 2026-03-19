# Game-A-Day: Godot Games

Source code for games built with Godot Engine in the [Game-A-Day](https://github.com/polats/game-a-day) project — a community-driven daily game jam on Reddit.

## Games

| Day | Game | Date | Engine |
|-----|------|------|--------|
| 26 | Arena Fighter | Mar 6, 2026 | Godot 4.6.1 |
| 27 | Fit The Block | Mar 9, 2026 | Godot 4.6.1 |
| 28 | Super Plumber Run | Mar 10, 2026 | Godot 4.6.1 |
| 30 | Terraforming Mars | Mar 12, 2026 | Godot 4.6.1 |
| 31 | Survive Till Dawn | Mar 13, 2026 | Godot 4.6.1 |
| 32 | Greenhouse Garden | Mar 14, 2026 | Godot 4.6.1 |
| 35 | Wrecking Ball | Mar 17, 2026 | Godot 4.6.1 |
| 36 | Third Space | Mar 18, 2026 | Godot 4.6.1 |
| 37 | Claws | Mar 19, 2026 | Godot 4.6.1 |

## Day 37: Claws

Magnetic claw machine with 600-ball physics ball pit. Drag to position the magnet over the prize pile, tap DROP to lower it. The magnet attracts glowing prize shapes (cubes, cylinders, gold spheres) while repulsing the blue balls outward — creating a satisfying parting effect. 8 prizes hidden in the pile (50-150 pts each), 10 attempts per round. Iterated through 4 grab systems: force-based pull, physical cage, freeze-on-contact, and finally magnetics.

**Key technical details:**
- 600 RigidBody3D balls + 8 prize bodies running on Godot 3D physics (HTML5)
- Magnetic attraction: per-frame force toward magnet for prizes within radius, freeze + lock when close
- Ball repulsion: per-frame force away from magnet pushes balls aside on descent
- AnimatableBody3D magnet with cylinder collision physically pushes balls on contact
- Pulsing blue TorusMesh glow ring when magnet is active
- Transparent circular DROP button appears only after first drag
- All geometry procedural (no imported assets)

**Stats:** ~10 iterations · ~300k tokens

## Day 36: Third Space

Liminal space exploration game focused on atmosphere and dread. Walk through procedurally generated empty rooms — hallways, pools, offices, hotel corridors, stairwells, malls, parking garages, bathrooms — rendered in one-point perspective. Tap the floor to walk, tap doors to enter them. An unease meter builds over time (faster when standing still). As unease rises: colors shift sickly green, lights dim, camera wobbles, whispered text appears, scan lines overlay, and rooms repeat with déjà vu messages. Doors randomly vanish as you approach — one safe door is secretly chosen per room, creating a guessing game. Score = rooms traversed before the space overwhelms you.

**Key technical details:**
- One-point perspective rendering: back wall + 4 trapezoid surfaces (floor, ceiling, left/right walls) with per-room-type depth/width configs
- Perspective-correct side doors: computed as wall-surface quads via `_wall_point()` depth/vert interpolation
- Door vanishing system: safe door pre-selected randomly at room setup, doomed doors fade when player crosses 25% depth threshold
- Alternating left/right shoe-print footprints with toe+heel circles, fading over 8 seconds
- 5 ambient event types: shadow crossing back wall, light section going dark, door handle jiggling, wall breathing, peripheral motion
- 5 anomaly types at high unease: wrong room label, upside-down ceiling door, repeating hotel numbers, pre-existing footprints, impossible window
- Corridor stretch effect: back wall recedes as you walk toward it
- Procedural audio: 120Hz fluorescent hum (volume scales with unease), footstep taps, water drip, distant elevator ding
- Photosensitivity-safe: flicker only dims to 70-85% above 50% unease, no rapid strobing

**Stats:** ~6 iterations · ~200k tokens

## Day 35: Wrecking Ball

Demolition game with crane + boom arm + golf-style power bar. Tap to aim boom at target, tap ball to start oscillating power bar, tap again to launch. 5 procedural building types (office, house, tower, pyramid, skyscraper) × 6 color palettes with reinforced immovable blocks as structural elements. Blocks check for support below — knocking out foundations causes cascade collapses. Star blocks (gold, 5x points) in hard-to-reach spots, combo multiplier for chain hits (up to x10). 5 shots per building, ground rubble auto-destroys after 1 second. ~12 iterations, ~350k tokens.

## Day 32: Greenhouse Garden

Cozy greenhouse garden with procedural L-system branching trees and blooming flowers. Choose to plant trees or flowers, water to keep them alive, prune branches to boost production, harvest fruit and blooms. Flowers fill a bouquet collection. Butterflies and bees visit thriving gardens. Seasonal arc from Spring through Summer to Autumn with color-shifting visuals and falling leaves. Garden Portrait end screen.

**Key technical details:**
- L-system-inspired procedural branching: deterministic per-plant RNG, up to depth 4, animated growth
- Pruning mechanic: tap leaf clusters to snip, grants 8s of 2x production boost
- Seasonal system: 3 phases with interpolated background/leaf colors, varying growth/drain rates
- Plant chooser UI: tree vs flower selection with distinct gameplay loops
- Bouquet collection: harvested flowers accumulate in a vase display
- Visitor system: butterflies (flowers) and bees (trees, 1.5x ripen speed)
- Responsive: portrait 2-row layout, font sizes scale with min(sw, sh)

**Stats:** ~8 iterations · ~200k tokens

## Day 31: Survive Till Dawn

Friday the 13th stealth survival at Camp Crystal Lake. Tap to move through darkness with only a flashlight circle. Search 7 cabins for 5 escape items while Jason stalks the camp. Heartbeat audio pulses faster as Jason approaches. Survive until 6 AM or find all items to escape.

**Key technical details:**
- Darkness via alpha modulation: near-black ground + radial lit circle + `_visibility()` distance function on all objects
- Jason AI: patrol/hunt two-state machine with line-of-sight blocked by cabin AABBs
- Procedural camp: rejection-sampled cabins, trees, lake, paths
- Runtime PCM heartbeat: dual-thump "lub-dub" with proximity-driven pitch and volume
- Cabin glow beacons visible from 3x light radius for navigation

**Stats:** ~6 iterations · ~100k tokens

## Day 30: Terraforming Mars

Engine-builder card game inspired by the board game. Draft project cards, build production engines, convert Heat/Plants into parameter steps, and race to terraform Mars in 20 generations. 3D procedural planet with shader-driven terrain, oceans, greenery, and atmosphere that visually transform. Horizontal card hand UI (Hearthstone-style) with fixed action bar. 36 cards with tag synergies across 6 types.

**Key technical details:**
- Custom spatial shader: fbm noise terrain, depth-based oceans, oxygen-driven greenery, fresnel atmosphere
- Planet patches: glowing spheres spawn on visible hemisphere when parameters change (orange/blue/green)
- Income compound growth: every parameter step gives +1 permanent income per turn
- 4 UI iterations from vertical lists to horizontal card hand

**Stats:** ~6 iterations · ~180k tokens

## Day 28: Super Plumber Run

Mario Day auto-running platformer — tap to jump, double-jump mid-air. 10-section designed level with pipes, goombas, coin arcs, question blocks, brick bridges, pits, and a flagpole + castle finish. Runtime-generated chiptune audio (square wave melody + triangle wave bass + death jingle) — all PCM, no imported WAV files. Scored by coins, stomps, block bonuses, flag height, and time remaining.

**Key technical details:**
- All audio generated at runtime as raw PCM via AudioStreamWAV (Godot's WAV import QOA compression is broken on HTML5)
- Parallax scrolling (clouds 0.15x, hills 0.3x, bushes 0.6x) with camera-relative drawing
- Shared Godot runtime across all days — archived days only need the .pck file (~33KB)

**Stats:** ~8 iterations · ~120k tokens

## Day 27: Fit The Block

3D "fit the shape through the wall" puzzle game — a wall with a cutout approaches down a tunnel, and you rotate a 3D block to match the silhouette. Tap to rotate face-on, swipe horizontally/vertically to flip along different axes. Smooth quaternion-slerp rotation animation using an inverse-then-identity trick. 12 shape definitions scaling from 2D tetrominos (levels 1-3) to full 3D shapes (levels 4+). 3 lives, increasing wall speed, urgency pulse when the wall gets close.

**Key technical details:**
- Rotation animation: rebuild cubes at final positions, set node to inverse rotation, slerp back to identity — no visual pop
- Shape silhouette matching: project 3D blocks onto XY plane, compare with wall hole grid
- Scramble system ensures the initial rotation never accidentally matches the solution

**Stats:** ~4 iterations · ~60k tokens

## Day 26: Arena Fighter

3D arena brawler built entirely with Godot MCP tools — no editor, just AI + code. Tap to punch enemies, swipe to dodge roll (with i-frames), survive escalating waves. Three enemy types (normal, heavy, fast), combo system for bonus damage, and a HUD with health bar, score, wave counter, and combo display.

**Key technical achievements:**
- First Godot game in the project — established the full pipeline: create project, build scenes/scripts via MCP, export HTML5, deploy to Devvit
- Added dual-engine support to the Devvit client (`GODOT_DAYS` set determines engine per day)
- Shipped gzipped WASM (36MB → 9MB) with client-side `DecompressionStream` fetch interceptor
- All 3D geometry is procedural (capsules, boxes, cylinders, torus) — no imported assets

**Stats:** ~6 iterations · ~100k tokens
