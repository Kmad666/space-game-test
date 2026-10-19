# Aegis Run

A neon space mining-and-defense game made in **Godot 4.7**, playable in the browser — nothing to download.

**Play:** https://kmad666.github.io/space-game-test/

## How to play
- **Your ship follows the mouse.** The further the cursor, the faster you fly. Hold **Space** to brake.
- Fly within the dashed ring around a crystal asteroid to **mine ore** (gold asteroids are worth 3x).
- Haul ore into the dashed ring around **Aegis Station**. Every delivery grows the station: bigger rings, solar arrays, defense turrets and a new escort bot each level.
- **Raids** arrive from the edge of space: red raiders, magenta bombers and burning meteors. Your missiles **lock on and fire automatically** when anything is in range.
- Escort bots (Castor, Pollux, Atalanta…) mine and fight beside you.
- Spend credits on **upgrades** (click the bar or press **1–7**). Every few upgrades your hull is rebuilt into a bigger class: Wisp → Hermes → Perseus → Achilles → Atlas.
- **P** pause · **F** fullscreen · **Q** toggle graphics quality. Lose the station and it's game over.

## Performance
Built to run on laptops with integrated graphics:
- All neon art is baked once at startup into a single sprite atlas, so a busy frame is ~270 draw calls instead of ~2,200.
- Trails, particles and the grid are drawn as a few batched commands.
- **Low-spec mode** turns on automatically if the game runs below ~45 FPS: it renders at 1280×720 and scales up, halves particles and trails, and drops the nebula. Press **Q** to switch either way. The current FPS shows under the minimap.

## How it's built
- Everything is drawn in code (no image assets) — see `scripts/`.
- `.github/workflows/deploy.yml` exports the web build with Godot on every push to `main` and publishes it to the `gh-pages` branch, which GitHub Pages serves.
- Exported without threads, so it runs on GitHub Pages with no special headers.
