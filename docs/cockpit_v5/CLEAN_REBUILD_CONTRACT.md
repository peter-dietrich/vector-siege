# Vector Siege cockpit clean rebuild — acceptance contract

Status: CLEAN REBUILD BRANCH, NOT APPROVED FOR MERGE.

## Source of truth
- The user-approved "Industrial Sci-Fi Cockpit Telemetry Console" mockup is the visual target.
- User screenshots of the running game are evidence of defects, not replacement mockups.
- Match framing, materials, recess depth, proportions, amber hardware lighting, and physical control rail to the mockup.
- Do not invent a different panel layout or call similar colors equivalent.

## What stays
- BattlefieldScene: gameplay, projection, enemy and projectile logic, sound, save/resume.
- The public live CockpitV5Snapshot telemetry contract (extend only for genuinely missing data).
- Four working upper instrument roles, game view, existing Classic and Modern modes.
- Five lower roles: Tank Status, Hit Ratio, Heading/Navigation, Terrain Profile, Sector.
- Native controls, twin MG, and US customary units.

## What is retired for the cockpitV53 mode
- ALL Modern lower HUD surfaces, labels, hardware, rails, and material panels.
- CockpitV53LowerChassis procedural fallback and the frame/plate layout in CockpitV53LowerDeck.
- Attempts to stretch upper bezels into lower shapes.
- Multiple competing lower-deck renderers and duplicated shortcut captions.

## Clean architecture
1. BattlefieldScene sends immutable snapshot data into one cockpit presentation adapter.
2. The cockpit presentation has a single root coordinate system and explicitly owned bands:
   upper art, center battlefield, lower approved art, controls.
3. Approved mockup-derived transparent artwork forms a verified lower structural background.
4. Five independent telemetry nodes are clipped strictly to mapped instrument rectangles.
5. All old HUD roots must be hidden when Cockpit v5.3 is selected; Classic and Modern remain unaffected.
6. The authored mockup is not a screenshot overlay with fake static telemetry; live fields and gauges are separately rendered.
7. No silent fallback to the old lower console. Missing assets must produce a clear debug diagnostic, not a misleading "success" UI.

## Gates, in order
- Gate A: Decomposition/inventory: explicit per-layer asset files, 1600×900 geometry map, exact source screenshots and panel coordinates. Validate alpha and readability. No game changes required.
- Gate B: Shell screenshot: render game with NO numeric telemetry first; lower metal housing and physical controls must visually match mockup and not overlap world.
- Gate C: Instruments: add tank, accuracy, heading, terrain, and sector data into their exact display-safe rectangles; no duplicate or example numbers.
- Gate D: Integration: show upper displays, battlefield, and lower shell together; ensure no old Modern overlay/strips/controls appear in Cockpit v5.3.
- Gate E: Runtime: macOS build and screenshot comparison, game play, window resize, save/resume, mode switching.

## Merge policy
No modifications to main until user approves screenshot from the clean branch.
Compilation success is necessary but never sufficient for visual approval.
No next phase until prior visual gate passes.
