# Vector Siege

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