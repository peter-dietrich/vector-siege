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
