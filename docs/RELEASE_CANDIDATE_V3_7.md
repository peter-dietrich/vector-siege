# Vector Siege v3.7 — Release Candidate Gate

**Candidate state:** source and CI preflight prepared; no public release tag or downloadable notarized build has been created. A successful macOS CI run is necessary but not sufficient for distribution.

## What this candidate includes

The v3.0–v3.6 gameplay series (cannon response, terrain/cover, air encounters, adaptive pacing, full-ammo level restarts, opaque-building concealment, performance and enemy fairness) remains the gameplay baseline. v3.7 adds release validation only; no new enemy counts, scoring rules, controls or difficulty tiers.

## Automatic acceptance criteria

On the intended `main` commit:

- [ ] `bash Tests/check-geometry.sh` passes
- [ ] Unsigned Debug Xcode compilation passes
- [ ] Unsigned **Release** Xcode compilation passes
- [ ] `bash Tests/check-release-candidate.sh .../Release/VectorSiege.app` validates app identity
- [ ] Bundle ID remains `io.vectorsiege.game`, as Fun City's built-in Vector Siege cabinet expects
- [ ] No unreviewed tag or signing credentials stored in source

To reproduce the release check on a Mac with Xcode 16+:

```bash
cd ~/Documents/GitHub/vector-siege
git switch main
git pull --ff-only origin main
bash Tests/check-geometry.sh
xcodebuild -project VectorSiege.xcodeproj -scheme VectorSiege \
  -configuration Release -derivedDataPath /tmp/vector-siege-rc \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
bash Tests/check-release-candidate.sh \
  /tmp/vector-siege-rc/Build/Products/Release/VectorSiege.app
open /tmp/vector-siege-rc/Build/Products/Release/VectorSiege.app
```

This produces an **unsigned local app**. Do not distribute it as a trusted public release.

## Manual release-candidate acceptance

Record your Mac and Xcode versions, the tested commit, and pass/fail for every item in [QA_V3_6.md](../QA_V3_6.md). In particular:

- [ ] Play on macOS 13+ with both Classic and Modern views and at multiple window sizes
- [ ] Run through at least level 6 on Veteran, including full ammo refill and level-ready screen
- [ ] Test chaff, fighter and saucer encounters, game over and restart
- [ ] Confirm solid buildings hide tanks in both camera views while radar still tracks them
- [ ] Test old-save compatibility and fresh save/resume mid-wave
- [ ] Inspect performance in the dense downtown and during a full drone encounter
- [ ] Check absence of crashes and lost keyboard focus
- [ ] Confirm copyright, image and audio provenance and naming are cleared

## Fun City integration contract

Fun City's launcher already contains Vector Siege with bundle ID `io.vectorsiege.game`. The separate Vector Siege repository builds the game and retains its independent release workflow.

When approved, the Vector Siege release must publish **exactly** `VectorSiege-macOS.zip` and `VectorSiege-macOS.zip.sha256` on the official `peter-dietrich/vector-siege` GitHub Releases page. Fun City discovers, downloads and installs the released ZIP independently; publishing a Fun City launcher build alone does not make Vector Siege downloadable.

Do not produce a release tag until the following are in place: Apple Developer Program membership, Developer ID Application certificate, all six documented GitHub Actions signing/notarization secrets, manual QA approval and asset-rights review. Public release also requires verifying the published SHA-256, Developer ID signature, notarization/Gatekeeper on a clean Mac, and Fun City's download/update path.

## Current outcome

The v3.7 engineering work establishes a **release candidate gate**, not a shipped product. Successful CI cannot attest to GPU performance, human gameplay feel, provenance, notarization or Apple signing.
