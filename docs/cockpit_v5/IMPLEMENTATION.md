# Vector Siege v5.0 — Artwork-to-Code Production Contract

**Status: Design contract / registration prototype. Final artwork is NOT yet approved or produced.** This is a clean-room cockpit redesign; the original game's Classic and existing Modern modes are preserved until the replacement is proven superior.

## Why this differs from v4.x

The previous work used `SKShapeNode` linework to imitate a cinematic cockpit. The resulting playable UI did not resemble the supplied visual references. This version reverses the workflow: **every art layer is a separately measurable, directly insertable SpriteKit sprite**, and every operational value is a coded overlay. A full-width inspiration render must NEVER be shipped as an in-game asset.

## Deliverables tracked by source

- `asset_manifest.json`: exact 1600 × 900 logical-space bounds, IDs, layers, pixel sizes, screen live-field requirements and composition order
- `registration.svg`: build-coordinate visual sheet; compare every artist export against it at 100% scale
- `Tests/check-cockpit-v5.py`: deterministic draft and strict asset checks, plus registration-sheet export
- `prototypes/CockpitV5/CockpitContract.swift`: decodable scene layout and top-left-to-SpriteKit geometry adapter
- Final RGBA art assets, to be produced **individually**, under `Resources/CockpitV5/` (not yet supplied)
- A **working side-by-side prototype** with real text and interactive target indication before swapping Modern mode (not yet implemented)

## The golden master is a composition, not a bitmap

### Art-only layers

The artist should make a master 1600 × 900 layout only as a **visual approval guide**. Export the listed PNG elements independently, at exactly 2× resolution:

| Sprite | Content | Hard limits |
|---|---|---|
| `cockpit_top_chassis` | Rear chassis, heavy gunmetal rails, hardware recesses, panel mounts | Alpha over screen windows and combat viewport |
| `cockpit_fire_bezel` | Gasket, bevel, fasteners, grill around left fire-control screen | 100% transparent in screen cutout |
| `cockpit_map_bezel` | Separate map-screen bezel and industrial corner hardware | 100% transparent in screen cutout |
| `cockpit_optics_bezel` | Optical monitor surround with restrained metal/glass edge | 100% transparent in screen cutout |
| `cockpit_systems_bezel` | Wider vehicle systems screen surround | 100% transparent in screen cutout |
| `cockpit_lower_chassis` | Metal navigation and controls console beneath battlefield | Alpha in dynamic indicator zones |
| `cockpit_screw_atlas` | Small reusable screw and hardware decals | Sprite-atlas tiles, not a full-screen layer |
| `cockpit_glass_reflection` | VERY faint reflection overlay | No permanent glare over data or combat |

Layer 10 is the chassis. Layer 12 is native screen base graphics. Layer 15 is bezel art. Layer 20 is reusable hardware. Layer 30 is live instrumentation. Layer 40 is alerts/interaction. Layer 45 is an optional weak glass highlight.

No file contains changing text, number readouts, targeting reticles, radar contacts, threat markers, game environment or fake diagnostics. This is a **hard source rule**, not a preference.

### Code-only pieces

These are dedicated SpriteKit or map-rendering components, fed by a single **read-only battlefield snapshot**:

| Display | Data bindings from current game | Implementation |
|---|---|---|
| Fire Control | heading, speed, ammo/max, reload fraction, selected target, cover/range/bearing | crisp text + native gauges |
| Tactical Map | ground/air enemies, buildings, player, actual target and hostile shots | filled tactical symbols/map tiles, not world wireframe |
| Rear Optics | rear camera image and bearing; optional detected threat brackets | existing rear renderer in material-framed sensor viewport |
| Vehicle Systems | lives, score/best, wave/difficulty, shield countdown/cooldown, chaff, ammunition | vehicle and combat status with meaningful discrete indicators |
| Lower Console | real terrain height, heading tape, sector, actionable warnings | brief at-a-glance native overlays |

Do not show engine temperature, fuel, crew injury, ammunition caliber changes or health percentages unless real gameplay systems are created to supply those values. A believable display cannot rely on fabricated values.

## Exact assembly and viewport

- Authoring resolution: **1600 × 900 logical points**; 2× export resolution for all bitmap layers
- Logical origin: top-left, with x increasing right and y increasing downward
- SpriteKit origin: bottom-left; `CockpitContract.Projection.frame` performs the conversion
- Fit/canvas scaling: `min(viewWidth/1600, viewHeight/900)`, centered with letterboxing. Never independently stretch a bezel or panel.
- Screens and art each have separate layer IDs and bounding rectangles. Validation rejects overlapping live screens, incorrectly sized PNGs, and missing bezels.
- The existing vector battlefield is rendered normally inside `battlefield`: x=0, y=350, w=1600, h=398. It cannot be baked into the art.
- Preserve established keyboard controls and pause, targeting, gameplay, Classic mode, and v4 Modern mode while proving the new version.

## Two independent approvals are required

**Gate A — Master art quality.** A rendered cinematic design is reviewed at actual game-window scale. Sign off on material depth, display hierarchy, readability, and the balance of cockpit vs. battlefield.

**Gate B — Translation proof.** All *separate* transparent artwork passes `python3 Tests/check-cockpit-v5.py --strict`. The standalone prototype must show precisely the same composition when populated with real SVG/native telemetry and representative changing values; compare a native screenshot against the Gate A master at identical dimensions.

If the layout looks great but cannot be reconstructed from the individual sprites, **Gate B fails**. Do not integrate into BattlefieldScene or mark it a success.

## Export quality rules

1. Render each sprite independently against transparency, not a flat screenshot crop with painted-over holes. Record original editable artwork/project sources in the same design project; the runtime uses generated RGBA.
2. Pixel edges of transparent screen openings must align with the screen rect and never contain baked numbers.
3. Keep shadows physically confined to appropriate chassis/bezels; avoid whole-screen soft-glow overlays.
4. Design at 2×, inspect at 1×. Fast gameplay text must remain readable at normal window size without zooming.
5. Keep imagery at consistent camera angle and lighting direction. Avoid photographic details that cannot be reconciled across the separate parts.
6. Any human-readable labels belong to code overlays unless static hardware labels are reviewed and intentionally fixed.
7. Do not modify the gameplay renderer to compensate for an artwork misalignment. Correct the artwork or manifest and validate again.

## Reproducible checks

```bash
# Layout and source definition only; passes BEFORE any art exists:
python3 Tests/check-cockpit-v5.py --svg /tmp/vector-siege-cockpit-v5-registration.svg

# When all final 2x PNGs have been exported:
python3 Tests/check-cockpit-v5.py --strict

# Typecheck standalone Swift geometry adapter on a Mac:
swiftc -typecheck prototypes/CockpitV5/CockpitContract.swift
```

**Current milestone** is the code-translatable definition and its geometry proof, not cinematic production art and not a new playable cockpit. Only after Gate B should the replacement interface be added as a selectable `Realistic` cockpit mode.
