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
| **Space** | Fire tank cannon (one friendly shell on screen) |
| **Shift** | Activate brief protective energy shield (cooldown) |
| **P** | Pause / resume |
| **R** | Start a new game |
| **C** | Toggle Classic/Modern graphics in-game |
| **I / K** | Left tread forward / backward |
| **O / L** | Right tread forward / backward |

The two tread controls can be used simultaneously, arcade-style: **I+O** moves forward, **K+L** reverses, **I+L** turns right in place, and **K+O** turns left in place. Standard arrow/WASD controls work as a simpler alternative.

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