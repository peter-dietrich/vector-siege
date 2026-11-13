# Vector Siege v4.0 — Tactical Command Cockpit

## Scope

This is the **Modern-mode visual-shell milestone** for the supplied command-cockpit concept. Classic remains independent.

The v4.0 implementation deliberately preserves existing physics, combat balance, scoring, controls, saving, drone behavior, and all four live instrument modules.

## Visible changes

- A much larger panoramic forward battlefield window (approximately 52–55% of normal window height; the remaining region forms a recessed lower equipment deck)
- Unified dark gunmetal windshield side pillars and roof visor
- Three structural monitor groups: **01 Weapons + Fire Control**, **02 Battlespace + Optics** (existing tactical radar and rear optical camera together), and **03 Vehicle Systems**
- Machined angular screen frames, double-edge highlights, metallic fasteners, amber status hardware and continuous lower command sill
- One responsive vertical translation for the actual radar, contacts, active sweep, rear camera, telemetry labels, and screen surfaces; no fabricated sensor values
- Live sill readouts for cannon ammunition/reload, current city sector/ground contacts, shield/chaff, and heading
- Compact contextual proximity warning above the panel in place of the previous large Modern hazard banner

## Engineering design

`CommandCockpitLayout` in `Sources/BattlefieldMath.swift` provides stable deck dimensions and viewport ratios. `BattlefieldScene.swift` reparents the pre-existing instrument nodes into `commandDeck`, preserving their internal local coordinates. Modern translates the deck downward, while Classic uses a zero offset and its historical positions.

The former Modern lower dashboard implementation remains in source for reference, but is no longer drawn or recalculated during normal Modern play. No legacy lower dashboard overlays should overlap the new shell.

## Deliberately deferred

- v4.1: Fully integrated center tactical map, target diagnostics and fire-control graphics
- v4.2: Live system diagram, instrument layout modernization and real terrain-profile telemetry
- v4.3: Cinematic startup, reactive lighting, premium buttons, audio and glass material polish
- v4.4: Visual QA across all window sizes, performance and release candidate checks

This milestone is a **working shell**, not the finished photorealistic console of the mockup. Detailed panel and glass materials should be evaluated with real screenshots in the next phase.

## Manual acceptance

- [ ] Classic looks unchanged after pressing C to toggle modes
- [ ] Modern panels live in the lower deck; battlefield fills the upper panorama
- [ ] All radar markers, scanning sweep, compass headings and optical rear feed move with their frames
- [ ] Two center displays share the battlespace bezel without overlapping adjacent modules
- [ ] No duplicate or ghost copy of the former Modern lower dashboard is visible
- [ ] Cannon, reload, shield and chaff readings continue responding to actions
- [ ] Proximity alert stays just above the equipment deck, not over radar or reticle
- [ ] Test at 900x640, 1240x790, 1600x900 and fullscreen
- [ ] Verify cursor/reticle, level transition, pause screen and alert layers remain legible
- [ ] Check sustained frame rate with dense buildings and 30 drones

Passes in Geometry Smoke and Xcode CI verify compilation and layout math, **not** screenshot fidelity or gameplay interaction on a human Mac.
