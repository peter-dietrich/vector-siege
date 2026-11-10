# Vector Siege

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
| **Return** | Start game / redeploy after game over |
| **↑ / W** | Drive forward |
| **↓ / S** | Reverse |
| **← / A** | Rotate left |
| **→ / D** | Rotate right |
| **Space** | Fire cannon (40 rounds, fixed 1-second reload per shot) |
| **Shift** | Activate brief protective energy shield (cooldown) |
| **P** | Pause / resume |
| **R** | Start a new game |
| **C** | Toggle Classic/Modern graphics in-game |
| **T** | Toggle detailed local telemetry (FPS, world coordinates, enemies, shells) |
| **I / K** | Left tread forward / backward |
| **O / L** | Right tread forward / backward |

The two tread controls can be used simultaneously, arcade-style: **I+O** moves forward, **K+L** reverses, **I+L** turns right in place, and **K+O** turns left in place. Standard arrow/WASD controls work as a simpler alternative.

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
