# Game-A-Day: Godot Games

Source code for games built with Godot Engine in the [Game-A-Day](https://github.com/polats/game-a-day) project — a community-driven daily game jam on Reddit.

## Games

| Day | Game | Date | Engine |
|-----|------|------|--------|
| 26 | Arena Fighter | Mar 6, 2026 | Godot 4.6.1 |

## Day 26: Arena Fighter

3D arena brawler built entirely with Godot MCP tools — no editor, just AI + code. Tap to punch enemies, swipe to dodge roll (with i-frames), survive escalating waves. Three enemy types (normal, heavy, fast), combo system for bonus damage, and a HUD with health bar, score, wave counter, and combo display.

**Key technical achievements:**
- First Godot game in the project — established the full pipeline: create project, build scenes/scripts via MCP, export HTML5, deploy to Devvit
- Added dual-engine support to the Devvit client (`GODOT_DAYS` set determines engine per day)
- Shipped gzipped WASM (36MB → 9MB) with client-side `DecompressionStream` fetch interceptor
- All 3D geometry is procedural (capsules, boxes, cylinders, torus) — no imported assets

**Stats:** ~6 iterations · ~100k tokens
