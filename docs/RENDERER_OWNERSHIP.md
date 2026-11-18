# Vector Siege rendering ownership and cleanup contract

## Canonical branch / renderers
- `tronzone-true3d-phase1` is the recovered SceneKit implementation, currently the authoritative *3D development baseline*, pending review and integration.
- `refactor/true3d-core-cleanup` is an isolated cleanup branch based on that baseline.
- `main` currently contains an older SpriteKit modern-Alpine path plus later cannon/MG/sky experiments. **Do not merge main into 3D wholesale**: it would reintroduce the obsolete renderer and conflicting time-of-day implementations.
- For **Alpine + Modern or Cockpit v5.3**, `Tronzone3DWorld` / SceneKit alone owns 3D scenery, opaque geometry, camera lighting, sky, celestial objects, and 3D enemies.
- SpriteKit owns gameplay state, physics, collision, weapon and visual effects, targeting, telemetry, radar, and approved cockpit overlay.
- Classic retains the original vector look intentionally. Futuristic City remains on the existing SpriteKit path until its own 3D conversion is implemented; do not silently relabel that city as a finished 3D world.

## Immediate cleanup
- Removed unreachable `tronzoneObstacleFaces` legacy Alpine solid-mesh generation, retained true-3D mesh generator in `Tronzone3DWorld.swift`.
- Make native Cockpit v5.3 the default for new sessions and a newly constructed scene. Existing saved display preferences still restore as stored.
- Keep the old classic/city renderer where still reachable. Do not delete shared geometry, radar, cockpit, or collision routines just because their function names say 'render'.

## Remaining migration (not yet removed)
1. Extract Classic/city SpriteKit world rendering out of the large `BattlefieldScene.swift` into a separate class/file with an explicit interface.
2. Convert Futuristic City to the SceneKit world, then retire its old opaque SpriteKit face pool and `tronzoneEnemyFaces`.
3. Remove residual Alpine-specific SpriteKit outlines/foliage geometry **only after** the Classic mode has its own equivalent preserved.
4. Separate `BattlefieldScene` simulation and state/save handling from both renderer implementations.
5. Port the cannon-pierces-drones, new machine-gun audio/tracers, and low-pass saucer vulnerability by reviewing code changes from the abandoned main branch selectively (not a merge).
6. Check both debug and release macOS builds plus geometry tests and a real playthrough before any default-branch promotion.

## Must-pass regressions
- The launch view in Modern / Cockpit v5.3 + Alpine visibly renders the actual depth-buffered SceneKit terrain, tanks, sun/moon and sky, not flat SpriteKit polygon approximations.
- Classic mode still works and looks like Classic by deliberate choice.
- Weapon firing, drone hits, AI, save/resume, radar and rear camera remain correct.
- Changing battlefield, display style, window size, and time of day does not blank SceneKit or allow old 2D Alpine geometry to cover the 3D scene.
- Release/debug build must package `Tronzone3DWorld.swift` and all approved cockpit assets.

Git history remains available as a backup; removal of unreachable code is not a history rewrite.
