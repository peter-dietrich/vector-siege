# Vector Siege v4.0.1 — Top-Mounted Tactical Command Cockpit

This revision replaces the rejected v4.0 bottom-deck layout, following the local screenshot review.

## Approved layout direction

- **Keep the four telemetry panels at the top**, with radar and rear camera between the two status groups, as in the successful v3.7 screenshot.
- **Keep the bottom tank status, hit ratio, heading tape, terrain profile and controls**. The large battlefield remains between these two instrument bands.
- Do not shrink the forward battlefield in order to move the main displays to the lower edge.
- Preserve Classic mode and the current gameplay, radar, aiming, save/resume, scoring and ammunition systems.

## Visual revision

- Use a broad matte gunmetal upper console behind the live screens.
- Give every monitor a layered, filled equipment housing with stepped bezel and dark inner shadow.
- Use machined edge details, recessed fasteners, restrained vent slots, narrow steel dividers, and small non-dominant cyan/amber highlights.
- Reduce neon glow around the instruments. Contrast should come from **solid materials, lighting hierarchy and high legibility**, not fuzzy wireframes.
- Avoid duplicate large numbers or decorative fake diagnostics.
- Keep the existing animated radar contacts, rear camera, target and systems telemetry functional.

## Code

The live telemetry nodes share `commandDeck` at zero vertical translation. `renderCommandCockpitShell` draws the hardware surrounding **top** panels. The existing `renderModernCockpit` draws the **bottom** dashboard again. `CommandCockpitLayout` now describes the top-panel extents and open battlefield gap; the abandoned bottom-deck offset was removed.

## Local visual review

Test Modern at regular desktop size and fullscreen. Verify:

- [ ] Main telemetry stays top-mounted, with radar and rear view inside individual panels
- [ ] Bottom command strip shows tank status, hit ratio, compass, terrain, and controls
- [ ] Buildings, reticle and battlefield appear in the center without overlapping cockpit panels
- [ ] Matte dark mechanical frames feel dimensional rather than fuzzy; panel labels stay legible
- [ ] No doubled lower command rail or stray cockpit legend from v4.0
- [ ] Proximity alarm displays without covering its own text or the reticle
- [ ] Classic mode matches prior releases
- [ ] UI reflows at 900×640, 1240×790, 1600×900, and fullscreen

CI verifies build and geometry, **not** the subjective visual result. The premium image-backed material and new display designs are future work after screenshot review.
