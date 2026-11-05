# Melissae

*Tend the hive.* A browser game made in **Godot 4.7** — nothing to download.

**Play:** https://kmad666.github.io/space-game-test/

You are one worker of a living alien hive. You don't build, buy or command anything — you **fly**, and the hive's survival depends on where you choose to be.

## The hive
- **Queen's Heart** at the center. The hive eats **nectar** every second (upkeep). If the stores run dry the Heart starts to wither — if it withers completely, the hive dies and the run ends.
- Each resource is delivered to its own organ, spread across the hive:
  - **Nectar → Nectar Vault** (food; also hatches drones)
  - **Ore → Comb Forge** (the Forge grows the hive by itself, following its growth plan)
  - **Ice → Rime Cistern** (powers the Stinger Spires and mending)
- **Brood Chamber** hatches drones: foragers that harvest whatever the hive craves, and guards that patrol.
- The Forge grows **Stinger Spires** (turrets) and **glands** — Carapace, Wing, Pouch, Venom, Proboscis, Eye. Glands reshape *you*: as they mature you molt through five forms, Nymph → Worker → Forager → Warden → Aristaeus.

## The dark
- **Six resource fields**, far apart, each with resident guardians that come back after they're killed:
  - Nectar blooms — **Polyps** that spit spores and breed **Mites**
  - Ice shelves — translucent **Lurkers** that lie in wait and lunge
  - Ore veins — rings of **Spitter** spine-turrets
  - Inner fields are milder; outer fields are richer and nastier.
- **Swarms** descend on the hive and nibble its organs. Wounded organs work at half strength; downed organs go dark. **Fly over a wounded organ to mend it** (uses ice).
- **The Reaper** — a huge, slow, armored serpent — comes for the Vault and siphons **15–30% of every store**, then flees. Hurt it and it takes less. Kill it before it escapes and it bursts, spilling its hoard as globs you can scoop up.
- **Fog of war**: you only see what you, your drones and the hive's organs can see.

## Controls
Mouse — fly (farther cursor = faster) · Mouse wheel or − / + — zoom · Space — hover · P — pause · F — fullscreen · Q — graphics quality.
Your stingers lock on and fire automatically.

## How it's built
- All art is painted in code at startup (chitin shells, glowing membranes and veins) and baked into a sprite atlas, so the GPU draws it in a handful of batches — see `scripts/gfx.gd` and `scripts/bio.gd`.
- Fog of war is a tiny texture updated ~8×/s and stretched over the world with a shader (`scripts/fog.gd`).
- **Low-spec mode** turns on automatically below ~45 FPS (fixed 1280×720 render, fewer particles). Press **Q** to switch.
- `.github/workflows/deploy.yml` exports the web build on every push to `main` and publishes it to the `gh-pages` branch for GitHub Pages.
- `tools/` holds dev-only scenes (sprite preview sheet), excluded from the export.
