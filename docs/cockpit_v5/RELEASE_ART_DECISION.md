# Release cockpit composition (November 2026)

Vector Siege v5.3 uses **13 original upper-cockpit RGBA PNGs** recovered from the v5.3 live-assets package and committed to `Resources/CockpitV5/` in commit `d8342a7`. The upper cockpit must NEVER silently fall back to the older line-drawn interface in a signed release.

The current lower console visible in the user's screenshot is a **source-controlled native CoreGraphics/SpriteKit chassis** from `Sources/CockpitV53LowerChassis.swift`, composed by `Sources/CockpitV53LowerDeck.swift`. Its panel geometry is 1600×256 logical points with five working instrument bays. The separately discussed `VectorSiege_Lower_Cockpit_Phase1_Approved.png` has not been located and is an **optional alternate art override**, not a release dependency.

The gate `python3 Tests/verify-approved-cockpit-art.py --app <VectorSiege.app>` validates the 13 PNGs in both repository and app bundle, plus source presence / Xcode linkage of the native lower renderer. It intentionally does not verify that telemetry updates correctly or that artwork looks good at runtime. The **signed distribution candidate must still be launched and visually compared** against the user's approved screenshot prior to public release.

Do not substitute the unrelated `VectorSiege_Clean_Shell_Approved.png` or fabricate PNGs just to satisfy the release check. If the absent Phase 1 override is later recovered, integrate it separately after visual review.
