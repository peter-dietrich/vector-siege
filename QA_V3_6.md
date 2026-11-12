# Vector Siege v3.6 — Gameplay QA and Release Readiness

This document is a **test checklist**, not a declaration that a release build has been playtested. Run it after pulling `main` in Xcode.

## Automated checks (GitHub Actions)

- [ ] `Tests/geometry_smoke.swift` passes, including v3.6 volley-bound tests, late-wave rules, route cadence, concealment, and save compatibility
- [ ] macOS Vector Siege build passes on the tip of `main`
- [ ] No uncommitted game or project changes in the local build

## Manual gameplay checks (required before tagging a release)

- [ ] Title screen starts correctly, then `Return` starts a run
- [ ] Classic and Modern render modes both remain readable (toggle `C`)
- [ ] Steering and tread controls, cannon fire, shield and chaff continue working
- [ ] Canon magazine refills to the configured capacity when the next level appears; firing remains disabled during the victory countdown
- [ ] Level completion depends on **ground vehicles**, not drones, fighters or saucers
- [ ] A machine-gun volley never pushes the simultaneous hostile projectile total over its wave limit
- [ ] Only a subset of ground enemies makes short evasive moves when a cannon shot passes near them; other enemies remain aimable
- [ ] Tanks find a route around city blocks instead of jittering or clipping through walls
- [ ] A stationary player occasionally faces flanking vehicles; moving away allows them to resume ordinary pursuit
- [ ] The 30-drone formation stays distinct and chaff can scatter/disrupt it
- [ ] One-pass fighters and blue saucers remain defeatable and do not stop progression
- [ ] Solid buildings hide enemy tanks in forward and rear views; the radar still reports hidden tanks
- [ ] Flatter downtown, dense nearby grid, curb outlines and sparse roadside planting remain legible
- [ ] Save and resume in the middle of a later wave (with airborne threats, partial ammo and active shield/reload) preserves state
- [ ] Play through waves 1–6 on Veteran and at least one custom preset; verify later waves stay possible
- [ ] Watch for frame-rate stalls during city intersections, wreck explosions and drone swarm passes
- [ ] Run at multiple window sizes and confirm radar, cockpit text, level-intro overlay and reticle remain correctly aligned

## Triage rules

Treat any crash, stuck level, impossible enemy spawn, loss of save data or damage through valid invulnerability as release-blocking. Treat severe frame stalls, non-opaque solid walls, clipped cockpit labels or enemies firing through terrain as high priority. Cosmetic effects and audio balance can follow after stability.

## Intentional gameplay limits

- Automatic director pressure stays in the three bounded states: RECOVERY, BALANCED and ACTIVE
- Default wave size and hostile shot limits remain capped by the existing rules
- Drone swarms and fighter passes are optional threats; ground-vehicle elimination remains the only wave gate
- No new player controls or changes to damage values were added by v3.6
