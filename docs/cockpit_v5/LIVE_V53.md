# Vector Siege — Approved v5.3 Live Cockpit Integration

Status: approved original artwork bridge, **playtest required**. Do not describe this as a completed signed-off cockpit.

## What is new

- Picker adds `Cockpit v5.3` alongside Classic and Modern.
- `Sources/CockpitV53LiveRenderer.swift` layers the original thirteen 2× RGBA PNGs in their exact v5.3 locations.
- The cockpit reads the real `CockpitV5Snapshot` published by `BattlefieldScene`.
- Fire control, tactical contacts, wave, score, ammo, reload, shields, chaff, heading and speed are game data, not prototype simulated values.
- The rear optics region reuses the game's true rear-facing renderer instead of the proof's simulated optical scene.
- The existing Modern lower console remains during this phase. The v5.3 ZIP does not contain an approved replacement lower chassis.
- The combat viewport and Classic/Modern presentation remain functional.

## Artwork installation (required to see the design)

The original `vector_siege_v5_3_full_cockpit_prototype.zip` is an artwork/proof project and is **not** the game.
The asset installer ZIP, prepared from those exact 13 PNGs, must copy them to `Resources/CockpitV5`.
The Xcode resource folder reference copies the directory into the app bundle. CI builds without production art but only Modern renders until these images are installed.

Do not commit fabricated placeholders or screenshots as live art. Sprite layers must remain separate.

## Acceptance tests

1. Install all 13 PNGs; confirm the new metal/amber four-module artwork differs visibly from Modern mode.
2. Check labels do not drift into bezel borders at normal window size and at the original 1600×900 design size.
3. Start a wave: score, ammunition, contacts, reloading, heading and shield/chaff change with actual gameplay.
4. Verify the rear-view camera follows the world; no sample/static optics scenes.
5. Switch Modern → Cockpit v5.3 → Classic repeatedly; verify all modes remain usable, including resume/save.
6. Confirm center battlefield, aim reticle and lower console are not obscured.
7. Confirm screenshots and report failures before declaring art-composition signoff.

## Known boundaries

The v5.3 prototype source contains illustrative sample readouts, a simulated rear sensor and deterministic sample map geometry. None of those are carried into live game authority. In live mode target IDs come from the current enemy list; they are display-only.
The separate approved lower console artwork does not exist in the supplied 13 PNGs. Lower chassis polishing is a separate milestone and should not be improvised without approval.
