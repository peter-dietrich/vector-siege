# True-3D Tronzone battlefield expansion — v2026.11.17h

**Canonical implementation:** `Sources/Tronzone3DWorld.swift` (SceneKit), with gameplay and collision state in `BattlefieldScene.swift` / `BattlefieldMath.swift`. This document supersedes the older procedural SpriteKit modernization notes below for the Modern / Cockpit v5.3 display. Classic retains its intentional vector visual style.

## Four selectable Modern environments

| Environment | New 3D landscape | Interactive cover / collision |
| --- | --- | --- |
| Mountain Wilderness | Shaded ridge geometry, detailed terrain mesh, pines, boulders, bunkers, relay towers | Existing deterministic Alpine obstacle footprints |
| Futuristic City | Neon high-rise buildings, varied floors, urban skyline, road corridors | Existing seeded city obstacles; all modern buildings are solid cover |
| Post-Apocalyptic City (Fallen Grid) | Damaged and tilted concrete blocks, debris/rubble, muted rust terrain and fractured skyline | Existing city footprints, fully solid in 3D |
| Oceanic Grid | Coastal dunes and traversable terrain, ocean planes, cliffs, palm-like vegetation, rocky cover and towers | Existing seeded Alpine-style collision bodies, using coastal topology |

All environments use the same SceneKit `SCNView`, depth buffer, 3D tank models, sky / sun / moon / star lighting system, current live cockpit, and gameplay simulation. There is no second modern SpriteKit rendering engine. The environment picker works with save-game environment raw strings; older saves still resolve by existing fallback.

### Limitations before visual sign-off

- This is a procedural first-pass, not photorealistic scenery. Textures and prop variety can be developed without changing world ownership.
- City and ruined city currently share the deterministic city footprint generator; differentiation is in 3D art and materials. Coast uses seeded physical cover and low dune-like terrain, not swimming or watercraft physics.
- Debug/Release macOS CI and actual cockpit playtesting are required. Do not present an unverified build as production-ready.
- This work is on `refactor/true3d-core-cleanup`, not the older `main` branch. Preserve the archived main until the recovery branch is verified.
- Cannon/drone piercing, improved machine guns and saucer low-altitude vulnerability are present in the recovered 3D code branch.

## Four-landscape verification

1. Open each environment in Cockpit v5.3; confirm **actual 3D geometry** instead of 2D green outlines.
2. Drive and shoot into each biome's cover; confirm blocked movement, cannon impacts, enemy pathfinding and map contacts.
3. Change time presets from midday to dusk and night in each biome; confirm lighting, sun/moon/star layering.
4. Switch Modern / Classic / Cockpit v5.3, resize window, start next wave and save/restore each selected biome.
5. Verify City and Fallen Grid are not indistinguishable; verify Oceanic Grid has a visible ocean horizon, not a continuous mountain ring.
6. Run geometry smoke tests, Debug and Release builds on the actual latest commit; capture visual proof from macOS.

---

# Tronzone battlefield modernization — implementation status

Reference: four user-supplied Tronzone concept images (Neon Battlezone / Neon Grid Tank series). These are **visual references**, not game backgrounds. Interactive scenes are constructed from live world coordinates and procedural shapes.

## What is implemented (2026-11-17)
- **Shared biome foundation:** `BattlefieldEnvironment` selection and deterministic `TronzoneBiome` site generation in `Sources/BattlefieldMath.swift`.
- **Mountain Wilderness / Alpine Vector Frontier:** terrain-aware projection, dark ground surface, fluorescent grid, faceted ridge silhouettes, green atmospheric layers, solid pine trees, collision-backed boulders, angular bunkers and communications towers. Seeded obstacle placement reserves a clear spawn area.
- **Original city retained:** selectable as Futuristic City. Its enhanced Tronzone architecture is reserved for Phase 3; the current urban mode is not falsely represented as complete.
- **Mechanical preservation:** cannon, twin machine guns, drones, enemy pathfinding, collision interception, radar, scoring, save/resume, difficulty and cockpit code remain intact.
- **Legacy save compatibility:** missing `battlefieldEnvironment` indicates the original city; new saves include their selected environment.
- **Tests:** city geometry regression plus deterministic Alpine placement / collision-spawn checks.
- **Assets:** the new environment is procedural, with its rendered shapes and materials authored entirely in tracked Swift. No externally-installed textures are required for this phase. Existing cockpit PNGs remain tracked in `Resources/CockpitV5`.

## Still pending
- Human visual review from macOS gameplay screenshot, especially composition, frame rate and collision feel.
- Higher-fidelity surface detail and additional environment prop varieties to approach the cinematic reference images.
- Phase 3: Futuristic City; Phase 4: Fallen Grid; Phase 5: Oceanic Grid; Phase 6: campaign rotation, environment presets and persistent selection.

## Validation checklist
1. Select Mountain Wilderness; start wave and drive forward toward pines, rocks and outposts. Each must block the tank.
2. Confirm enemies steer around obstacles and the radar tracks enemies correctly.
3. Confirm cannon projectiles strike terrain or obstacles, shield and twin MG still function.
4. Drive over changing terrain and verify terrain profile on the cockpit responds.
5. Save/resume a mountain battle, then switch to city, start a game, and verify city roads/buildings return.
6. Resize window and switch cockpit display modes.
7. Compare screenshot with concept art, noting remaining differences; never equate compile success with visual quality.
