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
