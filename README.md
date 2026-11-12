# Vector Siege

## v3.7 — Release candidate preparation (November 2026)

The current development version includes terrain-aware combat, flat and readable downtown streets, opaque building cover, full ammo replenishment per level, staggered air encounters and adaptive difficulty. **v3.7 introduces release-validation checks, not a public release**. See [v3.7 release candidate gate](docs/RELEASE_CANDIDATE_V3_7.md) for the exact Xcode commands, acceptance checklist and Fun City distribution contract.

- GitHub CI now tests gameplay geometry and both **Debug and Release** macOS builds, then inspects the Release app bundle for Fun City-compatible identity (`io.vectorsiege.game`).
- The existing signed and notarized release workflow runs the same geometry and bundle preflight before any tag-triggered packaging.
- No public tag or signed download is created until Apple Developer ID credentials, manual playtests and asset-provenance review are complete.

**Historical change log:** Sections labeled v1.x–v2.x below describe the game at those earlier milestones. Where counts, speeds or features differ, the current source and [v3.7 release candidate gate](docs/RELEASE_CANDIDATE_V3_7.md) take precedence.

## Maintainer documentation (2026 audit)

- [Architecture and development](docs/DEVELOPMENT.md) — code structure, local workflow, data and gameplay scope.
- [Build, tests and quality checks](docs/QA_CHECKLIST.md) — repeatable Mac checks and what CI does **not** prove.
- [Release and signing](docs/RELEASE.md) — release tags, notarization, archive output and Fun City integration.
- [Licensing and provenance](docs/LICENSING.md) — MIT terms, inspiration/trademarks, asset-origin review and redistribution boundaries.
- [Third-party notices](THIRD_PARTY_NOTICES.md) — observed libraries/resources and verification status.


An original first-person, wireframe tank-combat arcade game for **macOS 13+**, inspired by the 1980 era of vector arcade games. Independent from and not affiliated with Atari or Battlezone. Built with **SwiftUI + SpriteKit**, with no external packages or artwork required.

## Start on your Mac

1. Clone [peter-dietrich/vector-siege](https://github.com/peter-dietrich/vector-siege) to `~/Documents/GitHub/vector-siege` (or run `git pull --ff-only` in your existing checkout).
2. Open `VectorSiege.xcodeproj` in **Xcode 16 or newer**.
3. Select scheme **VectorSiege**, run destination **My Mac** and press **⌘R**.
4. Click inside the battlefield to restore keyboard focus if needed. Press **Return** to begin.

Command-line build:

```bash
xcodebuild -project VectorSiege.xcodeproj -scheme VectorSiege -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Xcode may need to create the scheme when the project first opens; it normally generates the scheme from the target automatically.

## Controls

| Key | Action |
| --- | --- |
| **Return** | Deploy first level / redeploy after game over |
| **Any key** | Start the next level from its wireframe LEVEL banner (action key is consumed) |
| **↑ / W** | Drive forward |
| **↓ / S** | Reverse |
| **← / A** | Rotate left |
| **→ / D** | Rotate right |
| **Space** | Fire cannon (40 rounds, fixed 1-second reload per shot) |
| **Shift** | Activate brief protective energy shield (cooldown) |
| **E** | Launch CHAFF/ECM countermeasure (2 charges per wave, 9-second cooldown; disrupts bomb drones and fighter attacks) |
| **P** | Pause / resume |
| **R** | Start a new game |
| **C** | Toggle Classic/Modern graphics in-game |
| **T** | Toggle detailed local telemetry (FPS, world coordinates, enemies, shells) |
| **I / K** | Left tread forward / backward |
| **O / L** | Right tread forward / backward |

The two tread controls can be used simultaneously, arcade-style: **I+O** moves forward, **K+L** reverses, **I+L** turns right in place, and **K+O** turns left in place. Standard arrow/WASD controls work as a simpler alternative.

## v2.1 — combined-arms battlefield encounters and threat-response cockpit

- **Clear damage feedback:** larger animated explosions, multiple layers of debris, bright pulsing red/orange full-screen flashes on a direct hit, and an expanding shockwave when the last life is lost. Effects keep animating briefly after GAME OVER rather than freezing.
- **Rebuilt proximity banner:** the Modern five-tank-length alert uses a properly sized beveled orange/red warning bar with striped hazard wings, text geometrically centered *inside* its frame, and severity-sensitive color/pulse. Classic retains its compact alert.
- **Coordinated ground squads:** each wave now stages its tanks together in one randomly selected left/rear/right approach quadrant, with collision-safe spacing. Standard tanks are joined by faster one-hit armored personnel carriers (APCs, wave 2+), two-hit hunter tanks (wave 3+, if enabled), and slower two-hit mobile artillery vehicles (wave 4+).
- **Delayed bomb-drone swarms:** wave 3 introduces one low-altitude drone, wave 6 introduces two, and later waves cap out at three. They launch 8–10 seconds into active play from the original ground-force staging sector, fly toward the tank and explode when close. They can be shot down with ordinary tank ammunition.
- **Fighter aircraft:** from wave 5, one low-flying two-hit fighter approaches from the same staging sector after 16–18 seconds and performs passes using machine-gun bursts and slow descending explosive bombs. Its projected firing/hit area is deliberately generous to keep tank-only anti-air play achievable; the weapon model is arcade-style, not realistic three-dimensional ballistics.
- **New defense — E CHAFF / ECM:** press **E** to emit a countermeasure pulse. You receive two charges per wave, with a 9-second recharge delay between uses and 4 seconds of jamming/disruption. Nearby drones are neutralized; other drones suspend guidance, and fighters cannot initiate attacks during the pulse. The existing five-second shield also blocks drone collisions and incoming rounds. The lower cockpit reports charges/cooldown.
- **Difficulty progression:** Veteran still starts with two tanks. Ground armor caps at eight and air threats cap at three drones plus one fighter; incoming volleys are capped at two in the early levels and three later. A staged group of air reinforcements never forces an empty-wave transition, and quickly cleared ground units accelerate the next arrival. Existing fixed one-second cannon reload and 40-round magazine are unchanged.
- **Save and compatibility:** new reinforcement timing, staging origin, chaff status, enemy classes and bomb payloads persist in optional fields of version-1 saves; older saves remain readable. No third-party artwork, sounds or licensed vehicle models were added.

**Player advice:** watch for yellow drone radar contacts, use the shield for an imminent impact, press **E** to disperse a nearby drone group, and use normal cannon fire (with generous low-aircraft aim assistance) against planes, artillery and APCs.

## v2.0 — precision-aligned cockpit instrumentation

- **Modern targeting and combat banks:** consolidated upper telemetry into five shared baseline bands, with a fixed heading/speed hierarchy, even targeting and accuracy columns, right-anchored range and status values, and calmer header typography. The primary readout rows now sit inside understated recessed instrument wells.
- **Clearer visual structure:** thin horizontal rules, two deliberately placed orange cut-corner accents, consistent row padding and tightly aligned shield/ammunition symbols. Reduced icon glow and decorative noise in favor of an intentional military instrumentation style.
- **Lower command deck:** rebalanced tank-system, hit-ratio, heading-tape, terrain-profile and sector widths. Status now follows one consistent label/value grid, the heading has its own framed digital plate, and the duplicate terrain heading has been removed.
- **Live functionality:** score, reload, shield, headings, coordinates, radar, rear camera and hit accuracy remain driven by actual game values. Classic remains unchanged, and there are no save-game or game-rule changes.

## v1.9 — solid structural collision and accurate projectile impacts

- **No more ghost shots through building corners:** bullets are tested against the visible building shape, not a small circular hitbox. Blocks use their full square footprint; buildings, towers and monoliths use their rendered rectangular bases; pyramids use height-dependent, tapered cross-sections.
- **Continuous shell collisions:** the complete distance travelled in each frame is tested against solid structures. The first contact along the swept path determines whether a wall or tank is hit first; impact particles appear on the actual collision boundary instead of at the projectile's advanced endpoint.
- **Consistent physics:** the player tank, enemy movement grid, enemy firing-lane checks and projectiles now share the same geometric footprints. Tank clearance adds its physical radius to the building footprint; enemy line-of-sight tests use the actual shell height.
- **Regression coverage:** new geometry tests check square-block corners, narrow buildings, pyramids, roof clearance, frame-skipping shots, navigation blocking, and priority when a tank and a wall overlap a projectile's path.
- **Compatibility:** saved games and older obstacle lists retain the existing format, deriving their collision body from stored kind/size/position; Classic and Modern use the same collision rules. This is an arcade approximation rather than a fully 3-D physics engine: shell flight is at fixed vertical heights, and pyramid taper is evaluated at that height.

## v1.8 — readable telemetry, slower saucers and crisp radar

- **Saucers:** slow aerial movement by another **70%** from the prior 1.10 base speed to **0.33 world units/second**, before difficulty/Custom Game multipliers. Spin animation and two-minute encounter timing are unchanged.
- **Upper and lower instrumentation:** slightly larger responsive label fonts, with emphasis on heading, speed and score, to take better advantage of the available cockpit space. Narrow windows retain responsive font limits.
- **Radar framing:** reduce gaps between upper dashboard panels and expand the radar monitor to the allocated column width while retaining a centered circular dial and square tactical map.
- **Sharper radar:** remove the core radar line glow, narrow its sweep beam, and use thinner, non-glowing street and dial linework. The separate transparent green sweep-trail sectors, compass bearings, contacts and range rings remain.
- **Ground grid:** brighten the fine world-anchored ground grid by approximately 10% without changing road or building geometry.
- **Validation:** a geometry regression check enforces the new saucer base speed; macOS build results must be verified for the final commit.

## v1.7 — sharp vectors, randomized spawns and gradient tactical radar

- **Sharper vehicle and aiming wires:** less excessive glow and thinner, brighter orange enemy-tank outlines in the main and rear cameras, with a clearer, narrower central targeting reticle. Flying disks retain their distinct green presentation.
- **Tighter ground mesh:** adds a subdued world-anchored **six-unit ground grid** beneath the existing wider city streets, curbs and dashed road markings. Both Classic and Modern modes get more depth cues without placing geometry on the roads.
- **Less predictable level starts:** enemy waves use a fresh random angular phase each time rather than always placing the first unit at the commander's heading. Initial spawn points must stay outside the forward 36-degree half-angle cone, while respecting safe separation and building collision buffers; if none is legal, the enemy is skipped instead of stacked or placed directly in the sightline. Existing enemy navigation remains in effect once play resumes.
- **Tactical radar enhancement:** preserves the square full-panel map with **72 ticks at five-degree increments**, cardinal bearings moving with tank heading, extra green circular range rings, and a bright rotating green beam with a **24-slice fading trail** clipped to the square border.
- **Distinct colored contacts:** orange squares for ordinary tanks, red triangles for hunters, green diamonds for saucers, mint-green blocks/buildings, and yellow-glowing projectile locations. The transparent sweep and contacts are constructed from live SpriteKit geometry rather than imported images.
- **Compatibility:** no changes to current saved-game format or ammunition, shield, level, or enemy collision rules. A newly started wave receives newly randomized spawn sectors.

## v1.6 — military dashboard lower telemetry and orange enemy tanks

- **Modern lower dash:** replaced the older utility-strip presentation with a beveled, illuminated military dashboard drawn entirely in SpriteKit, following the approved reference composition. The left tank-silhouette section shows tank readiness and systems/mode status; the adjacent HIT RATIO section uses a live percentage and bright green circular progress ring. The center holds a dynamic heading tape, calibrated scale and orange bearing pointer. At right are a heading-responsive terrain profile and a sector ID calculated from actual city-grid coordinates, elevation (flat-ground baseline 0.0 m), and live position. These are native shapes/labels rather than an image overlay.
- **Integrity interpretation:** the displayed percentage is the proportion of **starting lives still remaining**, not a separate per-hit armor damage simulation. It reaches zero when the mission ends.
- **Orange enemies:** all enemy **tank** wireframes use a highly visible orange outline in both Classic and Modern, including the rear-view monitor. Flying saucers remain a distinct green color. Radar enemy markers are orange; friendly shells remain distinguishable.
- **No gameplay regressions intended:** enemy AI, shield, ammo/reload, save/restore, city geometry, and Classic's original bottom-of-screen help strip are not modified by this redesign.

## v1.5 — reference cockpit telemetry and downtown density gradient

- **Modern-only upper HUD redesign:** the left and right top telemetry panels are now built with real, independent SpriteKit labels, split rows and thin illuminated dividers inspired by the approved cockpit references. Navigation shows oversized heading and speed, followed by target heading, aim offset, range, confirmed hits/misses, resolved accuracy, rounds in flight and X/Z coordinates. Combat shows oversized score, best score, current wave, remaining lives and difficulty, a shield-status panel, ammunition and reload timer, plus actual shield/ammo progress bars. Cyan digital typography, green readiness values, icon outlines and orange cut-corner details keep the instrument hierarchy readable. The tactical radar and rear-facing camera continue updating live between the two panels.
- **No logo:** the splash-image sprite is no longer displayed and the toolbar emblem is removed. The application name remains as text for identification.
- **Dense center, quieter outskirts:** the default city now creates **80 structures**, rather than 23, with about **36 in four downtown blocks**, **31 in middle neighborhoods**, and **13 in peripheral blocks**. Taller wireframe towers and buildings dominate the center, with more mixed forms outward. All structures remain in designated block interiors, away from open road corridors.
- **Custom city size:** Custom Game now supports 0–120 structures. Existing named presets retain their chosen values; the new 80-building default applies to new built-in-rule games.
- **Compatibility:** source-rendered classic instruments and saved games remain supported. Previously saved cities load their prior exact obstacle arrangement; regenerating a city on a new deployment uses the new density.

## v1.4 — street-first city and square tactical map

- **Roads before buildings:** the battlefield is now organized as an orthogonal **60-unit city-block grid**, with **18-unit-wide streets**. The main 3D viewport draws continuous curb edges and dashed road centerlines in both Classic and Modern. Streets remain clear for tank travel and enemy pathfinding.
- **Mostly empty city blocks:** the generator selects a minority of the 36 possible interior blocks to develop. Each selected block receives a small cluster of about 2–4 different wireframe structures (buildings, towers, monoliths, blocks and pyramids); the remainder stay open. Structures are placed in buildable interiors, with collision clearance from road corridors and neighbors. A newly deployed game receives a different seed; saved games retain their generated structures.
- **Square radar:** the radar's actual instrument frame is square, and its map fills that area instead of leaving unused corners around a circular dial. The city road grid is shown on the map in player-relative orientation, with clipping at all four square edges. The rotating sweep extends to the square edge; circular range rings, buildings, enemies and yellow projectile contacts remain visible.
- **Gameplay:** ammo, waves, shield, enemy navigation, rear camera and custom-game options are unchanged. The existing obstacle-count custom rule controls how many buildings populate the designated blocks.

## v1.3 — five-length proximity detection and smart enemy cover navigation

- **Earlier warning:** the enemy-tank proximity perimeter expands to **five tank lengths / 30 world units** (previously two lengths). Both Classic and Modern continue showing the visual warning, with a softer alert every 1.4 seconds in the outer zone, every 0.65 seconds inside two tank lengths, and every 0.30 seconds inside one tank length. The existing Sound switch controls alarm audio.
- **Obstacle-aware enemy navigation:** instead of steering directly into nearby buildings and stopping, ground tanks periodically plan routes on a coarse obstacle-aware navigation grid. Obstacles have clearance buffers and enemies maintain separation from each other. Tanks travel through intermediate waypoints to reach a clear angle on the player's tank; they replan if their route is obstructed or the goal moves.
- **Line-of-sight checks:** enemies hold fire while a building, tower, monolith, block, or pyramid obstructs their firing line. They resume shooting when the route brings them into a clear firing position.
- **Compatibility:** applies to both display modes and the built-in/custom enemy difficulty multipliers. Existing save formats remain unchanged; enemy routes are temporary and recalculated after load. Saucers retain their separate slow aerial movement.

## v1.2 — paced flying disks, separated enemy waves and key-to-start levels

- **Slower flying disks:** saucer translation speed is reduced from a base 5.4 to 1.10 world units/s (about 80% slower), independently of the visible spinning disk animation. The existing difficulty and Custom Game enemy-speed multipliers remain active.
- **Fewer opening enemies:** normal games now begin with **two tanks**, with gradual growth on later waves up to the existing cap. Custom Game presets retain their own saved starting enemy counts.
- **Never spawn a pile:** level enemies use radial sector placement, at least 30 world units apart, with boundary and obstacle checks. If a safe slot cannot be found, it is skipped rather than stacking enemies. Active AI also checks neighboring tanks before advancing and attempts a lateral sidestep when crowded.
- **Level introduction:** Return deploys the first **LEVEL 01** wireframe banner; after each cleared wave a **LEVEL 02**, **LEVEL 03**, etc. banner appears. Gameplay and patrol timers stay paused while this screen is shown. **Any key** (including Shift) starts the level, without simultaneously firing, steering, or activating the shield.
- **Save compatibility:** a save created while waiting at a level banner restores to the same banner. Older saved games remain loadable and open paused as before.

## v0.2 playtest feedback and telemetry

Vector Siege now has **Vector Drift-inspired cockpit telemetry panels** with subtle amber headings and green vector readouts. The left radar/targeting panel shows tank heading, drive speed, nearest forward target distance, angular aim offset, and cumulative shots/hits/accuracy. The right panel tracks score, best score, current wave, lives, difficulty, and shield readiness. Press **T** to show/hide additional runtime diagnostics (smoothed FPS, world coordinates, enemy count, active projectiles).

Use **Copy Feedback** in the toolbar to copy a plaintext playtest snapshot (mode, difficulty, game state, wave, score, position, heading, speed, target offset, shots, hits, FPS, enemy/projectile counts, shield, and elapsed gameplay). Paste the snapshot into a bug report or this chat. **No telemetry is automatically uploaded or transmitted**; copying only accesses the local clipboard. A crash cannot be captured by the in-app button after the game has terminated; macOS crash diagnostics are separate.

## v1.1 — Modern cockpit dashboard

Modern mode now uses a **fully live Vector Drift-inspired armored-vehicle instrument suite** instead of the older compact row of floating instruments:

- **Top four-panel layout:** responsive left targeting/navigation bank, central tactical radar with bearing ticks and moving contacts, a wider 180° live rear camera, and a right-hand combat status bank. Glass-black panels, cyan illuminated frame traces and small orange accents mirror the updated design concept.
- **Reading hierarchy:** enlarged heading/drive speed, live score, best score, hit/miss ratio, position, target bearing, ammunition and reload. Smaller details are deliberately secondary; panel widths adapt with the game window.
- **Bottom instrument deck:** a persistent dark-glass utility strip shows actual lives, active enemies/wave, a circular resolved hit-rate gauge, live heading with calibrated ticks, and battlefield coordinates.
- **Readiness gauges:** live horizontal shield/recharge and remaining-ammunition bars track the underlying game state; low ammunition changes the bar color.
- **Targeting optics:** improved Modern-only crosshair with a central aperture, four aiming brackets, reference ticks and the existing shield ring.
- **Threat response:** a glass/red-orange warning bar frames the existing two-tank-length proximity alert without changing collision, shield or enemy behavior.
- **Classic mode:** the original vintage green arcade HUD, reticle and gameplay remain available, separate from the Modern cockpit decoration.

All instrument graphics are drawn from SpriteKit paths and actual game values, not a static image. The design mockup is a visual reference only; the macOS app renders its own HUD. Saved games and Custom Game settings are unchanged.

## v1.0 — rear camera, HUD readability and proximity defense

- **Twin center instruments:** the circular 165-unit radar dial still rotates inside a **rectangular panel**, paired with an adjacent **live rear-view camera**. The rear inset uses a real 180° reverse perspective: a rear-facing ground grid, distant horizon, battlefield structures, tanks, flying disks and moving projectiles. Camera content is cropped to its own rectangular monitor and works in Classic and Modern.
- **Readable HUD:** targeting and coordinates stay on the left, combat and ammunition on the right; emphasis shifts to larger speed/heading, score and ammo/reload typography. Smaller supporting text stays legible; the panels adjust their width for narrow windows.
- **Enemy proximity:** if any enemy **tank** (not saucer) is within **two approximate tank lengths / 12 world units**, a prominent amber warning appears. At closer than one tank length it turns urgent red. When Sound is enabled, a synthesized, subdued two-tone beep repeats every 0.65s and accelerates to 0.30s for very close tanks. The warning is visible even with Sound muted. No proximity sounds occur when paused.

## v0.9 — central tactical radar, modern architecture and rotating disk patrols

- **Central tactical radar:** enlarged to a **138-point diameter**, located at the top center between independent left targeting/position telemetry and right combat/ammo telemetry panels. The map now covers **165 world units** and includes inner range rings, twelve bearing marks, an animated sweep, a nose-direction marker, small obstacle footprints, red enemies, diamond-shaped disk contacts, and the previous yellow glowing projectile blips.
- **Modern architecture:** mixed tall wireframe towers, multi-story faceted buildings with window/deck details, narrow monoliths and classic blocks/pyramids. They have different heights and dimensions, with glass-like shaded surfaces; collision detection still uses their original horizontal footprint. Classic keeps the simple wireframe obstacles rather than rendering the architectural details.
- **Rotating disks:** a flying saucer patrol now enters at least once every **120 seconds of active, unpaused play** in either display mode, independently of regular wave spawns. The rotating disk has animated spokes, rims and dome facets; Modern has more detail than Classic. The scheduled patrol follows the Custom Game setting **Enable flying saucers**; turning that off intentionally disables them. The countdown persists across Save Game / Resume, and older saves continue to load.

## v0.8 — Custom Game presets and saved game slots

Vector Siege now includes the **Custom Game**, **Save Game**, and **Resume** controls from Vector Drift.

- **Custom Game:** name a preset and tune magazine capacity (1–200), cannon reload (0.2–6 seconds), projectile lifetime, starting lives, shield time and cooldown, first-wave and per-wave enemy counts, maximum enemies, obstacle count, enemy speed, enemy fire rate and accuracy, and hunter/saucer appearances. Choose **Save & Start Custom Game** to store and activate a reusable named preset, or **Built-in rules** to restore the original tank settings. The built-in Cadet, Veteran, and Ace difficulty levels remain selectable.
- **Save Game:** during active or paused play, saves a timestamped local snapshot. Up to **12 slots** are retained, most recent first; saving does not replace existing saves.
- **Resume:** shows saved games with their name, timestamp, display mode and difficulty; choose **Resume** or **Delete**. Restored battles retain score, lives, wave, position, heading, speed, ammo and reload timer, shield, invulnerability, enemies, obstacles, friendly and hostile shells, hit/miss stats, effects and selected custom rules. A restored game starts **paused**, so press **P** to resume safely.
- **Storage:** presets and saved games are JSON encoded in this Mac's UserDefaults, with Vector Siege-specific keys. No external service is required or contacted. Saves are local to the Mac account and are not automatically synced through GitHub or between computers.

## v0.7 — five-second shield with expiry warning and hit/miss tracking

- **Shield (Shift):** active for **5 seconds** (previously 2.25). A glowing perimeter outline and countdown indicate protection. During the **last second**, the border and notice blink and fade progressively. The existing 11-second cooldown is unchanged.
- **Telemetry:** continuous **H/M hit:miss ratio**, hit percentage measured over *resolved* shots only, and **F** count for rounds still in flight. Shots that hit enemies count as hits; shots that hit obstacles, expire, or are cleared between waves count as misses. Shots still airborne are not treated as misses.
- **Copy Feedback:** includes total rounds fired, confirmed hits, misses, in-flight projectiles, the resolved hit rate, and remaining shield time. These mechanics apply in Classic and Modern.

## v0.6 — classic terrain grid, modern shell mesh, stronger suspension dip

- **Classic:** a restrained, dim-green world-anchored perspective grid is now drawn on the terrain, using wider 18-unit spacing. It flows naturally as the tank moves and turns.
- **Modern:** flying shells now render as illuminated 3D wireframe darts with pointed noses, four-sided ring cross-sections, longitudinal struts, and tail fins. Friendly rounds are yellow-gold; enemy rounds remain red-orange. The projectile physics, radar detection, ammo, and reload rules are unchanged.
- **Tank suspension:** a moderately stronger nose dip when starting and stopping (about 25–40% more visual response) with the same spring damping. The view responds; gun aim and heading stay accurate.

## v0.5 — vehicle feel, detailed Modern tanks and radar projectiles

- **Movement audio:** a low procedural engine rumble grows with forward/reverse speed and a separate soft tread rattle builds while turning. Both fade out at rest, pause or game over; the existing Sound toggle controls them. No extra sound assets are required.
- **Vehicle suspension:** subtle lateral camera shudder while moving and turning, fine vertical track vibration, and a damped nose dip/rebound as acceleration or braking changes. These are visual-only offsets: physical position, heading, reticle, shooting direction and collision calculations stay stable.
- **Modern tank geometry:** sloped hull armor, armored side skirts, segmented tread shoes, individual road wheels, turret cheek plating, roof hatch, optics, reinforced cannon, exhaust/engine louvers, tow loops, and antenna. Classic retains the original simple wireframe tank.
- **Radar upgrade:** moving friendly and hostile shell positions appear as **yellow glowing blips** on the existing heading-relative radar (friendly shells slightly larger); red enemy contacts remain distinct. Radar tracks every live shell inside its normal 105-unit detection radius.

## v0.4 — faster cannon and Modern scenery

- Player cannon reload is a fixed **1 second**, keeping the existing 40-round capacity. Multiple friendly shells can travel simultaneously; the cooldown, not the prior shell's lifespan, controls firing.
- **Modern** graphics now feature a ten-band dark atmospheric sky gradient, three filled mountain silhouettes with different ridge profiles and parallax, a subtle horizon-mist band, and translucent cyan/teal glass-faced blocks and pyramids. Glass faces are clipped against the camera near plane, sorted by depth, and drawn below their bright vector outlines.
- **Classic** remains the original green-wireframe treatment. Rendering-only changes preserve obstacle positions, collision geometry, difficulty and score.

## v0.3 — ammunition and coordinate telemetry

Both **Classic** and **Modern** graphics use the same cannon ammunition mechanics:

- 40 rounds per new game/deployment; each successful shot consumes one round.
- Each shot triggers a fixed **1-second reload**. The cooldown is unaffected by display mode and difficulty. The shot key cannot bypass reloading.
- **AMMO 39/40 RELOAD 4.2s**, **AMMO 39/40 READY** or **AMMO 00/40 EMPTY** appear continuously in the right telemetry panel. No automatic ammunition refills occur between waves; New Game/redeploy restores 40.
- The left panel continuously shows **POSITION X, Z** in battlefield world units. It updates as the tank moves without pressing T.
- **Copy Feedback** includes remaining ammunition, cannon reload status, and the most recent reload duration.

Enemy attack timing is unchanged.

## What's in v0.1

- Native, resizable macOS window with a SpriteKit game view and SwiftUI control strip
- Perspective-projected **3D wireframe battlefield**, moving green mountain horizon, cubes and pyramids
- Distinct **Classic** and **Modern** visual treatments (Modern adds glowing vectors and receding ground grid)
- First-person cannon with line-of-fire crosshair, projectile travel and cover collision
- Enemy tank steering, ranged enemy fire, harder hunter tanks, and flying saucers as waves progress
- Red radar scanner with target contacts, target-acquisition warning
- Life/score/high-score tracking, attack waves, shield with recharge, damage and explosions
- Synthesized original WAV sound effects; no external dependencies or image assets
- Three difficulty levels and keyboard-first interaction

## Project files

- `Sources/VectorSiegeApp.swift` — native UI, settings and keyboard event handling
- `Sources/BattlefieldMath.swift` — pure geometry and perspective projection
- `Sources/BattlefieldScene.swift` — game state, artificial intelligence, collisions, scene drawing, HUD and effects
- `Resources/` — six original, tiny procedural sound effects
- `Tests/check-geometry.sh` — cross-platform geometry smoke checks (`bash Tests/check-geometry.sh`)

## Notes

- This initial version has been **syntax checked**, the Xcode project format validated, and the pure Swift geometry smoke tests passed, but has **not been compiled or play-tested in Xcode** (which requires macOS). Check the Xcode issue navigator if you encounter an environment-specific compile error.
- Visuals are rendered with SpriteKit paths rather than relying on any proprietary Battlezone art or code.
- This is a foundation for future work: multiple sectors, destructible terrain, atmospheric world backgrounds, mission variations and gamepad support.

## Source of truth

GitHub repository: https://github.com/peter-dietrich/vector-siege (branch `main`).
The bundled GitHub Actions workflow performs a macOS Xcode build on commits and pull requests.
## Arcade title screen

The starting screen now features an animated **Vector Siege** neon arcade logo, a slowly changing atmospheric backdrop and the existing Return-to-deploy prompt. The logo is bundled as `Resources/VectorSiegeLogo.jpg` and copied into the app by Xcode. The original full-resolution illustration may be substituted later for higher-DPI presentation.
