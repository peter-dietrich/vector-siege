import Foundation

@main
struct GeometrySmoke {
    static func main() {
        let c = CameraProjection(position: GroundPoint(0,0), yaw: 0,
                                 viewportWidth: 1200, viewportHeight: 700)
        guard let (a,b) = c.clipLine(WorldPoint(-2,0,20), WorldPoint(2,0,20)) else {
            fatalError("Front-facing line should project")
        }
        precondition(a.0 < b.0, "Horizontal perspective ordering should be correct")
        precondition(a.1 == b.1, "Equal-height objects should be on the same row")
        precondition(c.clipLine(WorldPoint(-2,0,-20),WorldPoint(2,0,-20)) == nil,
                     "Behind-camera lines should be culled")
        guard let crossed = c.clipLine(WorldPoint(-2,1,-2),WorldPoint(2,1,7)) else {
            fatalError("Near-plane crossing should be clipped")
        }
        precondition(crossed.0.0.isFinite && crossed.1.0.isFinite)
        precondition(abs(facing(.pi/2).x - 1) < 0.0001)
        precondition(abs(wrapAngle(3 * .pi) - .pi) < 0.0001)
        precondition(abs(PrecisionSteering.tapAngle - .pi / 360) < 1e-12)
        precondition(PrecisionSteering.heldRate(elapsed: 0.02) == 0)
        precondition(PrecisionSteering.heldRate(elapsed: PrecisionSteering.holdDelay) == 0)
        precondition(PrecisionSteering.heldRate(elapsed: 0.20) > 0)
        precondition(PrecisionSteering.heldRate(elapsed: 0.70) >
                     PrecisionSteering.heldRate(elapsed: 0.20))
        precondition(PrecisionSteering.heldRate(elapsed: 10) < 2.0)
        var cannon = CannonMagazine()
        precondition(CannonMagazine.capacity == 40)
        precondition(CannonMagazine.minimumReload == 1 && CannonMagazine.maximumReload == 1)
        precondition(cannon.canFire && cannon.roundsRemaining == 40)
        precondition(cannon.fire(reloadDuration: 1))
        precondition(cannon.roundsRemaining == 39 && !cannon.canFire)
        precondition(cannon.statusText == "RELOAD 1.0s")
        precondition(!cannon.fire(reloadDuration: 1))
        cannon.advance(by: 0.5)
        precondition(!cannon.canFire && cannon.reloadRemaining > 0)
        cannon.advance(by: 0.5)
        precondition(cannon.canFire && cannon.statusText == "READY")
        precondition(cannon.fire(reloadDuration: 1))
        precondition(cannon.reloadRemaining == 1 && cannon.roundsRemaining == 38)
        cannon.advance(by: 1)
        for _ in 0..<38 {
            precondition(cannon.fire(reloadDuration: 1))
            cannon.advance(by: 1)
        }
        precondition(cannon.isEmpty && cannon.roundsRemaining == 0)
        precondition(cannon.statusText == "EMPTY" && !cannon.canFire)
        precondition(!cannon.fire(reloadDuration: 1))
        cannon = CannonMagazine()
        precondition(cannon.canFire && cannon.roundsRemaining == 40)
        precondition(EnemyMotion.saucerBaseSpeed >= 9.0,
                     "Saucer flyovers must move quickly across the battlefield")
        // Vehicle camera motion is visual only; the simulated tank aim remains
        // independent of suspension pitch and lateral shudder.
        var suspension = TankSuspension()
        suspension.update(speed: 12, dt: 1.0 / 60.0)
        precondition(abs(suspension.pitch) > 0.020, "Acceleration should visibly pitch the hull")
        for _ in 0..<120 { suspension.update(speed: 12, dt: 1.0 / 60.0) }
        precondition(abs(suspension.pitch) < 0.001, "Suspension should settle")
        suspension.update(speed: 0, dt: 1.0 / 60.0)
        precondition(abs(suspension.pitch) > 0.020, "Braking should visibly dip / rebound")
        for _ in 0..<120 { suspension.update(speed: 0, dt: 1.0 / 60.0) }
        precondition(abs(suspension.pitch) < 0.001, "Stopping wobble should decay")
        suspension.reset()
        precondition(suspension.pitch == 0 && suspension.pitchVelocity == 0)

        var tally = ShotTally()
        precondition(tally.fired == 0 && tally.pending == 0 && tally.hitPercentage == 0)
        tally.fire()
        tally.fire()
        tally.fire()
        precondition(tally.fired == 3 && tally.pending == 3)
        tally.hit()
        precondition(tally.pending == 2 && tally.hits == 1 && tally.hitPercentage == 100)
        tally.miss()
        precondition(tally.misses == 1 && tally.pending == 1)
        precondition(tally.hitPercentage == 50)
        tally.miss()
        precondition(tally.pending == 0 && abs(tally.hitPercentage - 100.0 / 3.0) < 0.0001)
        tally.miss()
        tally.hit()
        precondition(tally.resolved == 3 && tally.fired == 3, "One shot cannot resolve twice")
        tally = ShotTally()
        precondition(tally.fired == 0 && tally.resolved == 0)

        var shakenCamera = c
        shakenCamera.cameraLateral = 0.02
        shakenCamera.pitchPoints = -2.5
        precondition(shakenCamera.horizon != c.horizon)
        precondition(shakenCamera.local(WorldPoint(0, 0, 20)).right !=
                     c.local(WorldPoint(0, 0, 20)).right)
        // Custom presets clamp invalid values while preserving useful defaults.
        let standard = SiegeRules()
        precondition(standard.ammoCapacity == 40 && standard.reloadSeconds == 1)
        precondition(standard.shieldDuration == 5 && standard.shieldCooldown == 11)
        precondition(standard.enemies(forWave: 1) == 2)
        precondition(standard.enemies(forWave: 2) == 3)
        precondition(standard.enemies(forWave: 100) == 8)
        var custom = SiegeRules()
        custom.ammoCapacity = 250
        custom.reloadSeconds = 0.01
        custom.maxEnemies = 2
        custom.startingEnemies = 5
        custom.enemySpeed = 9
        let validated = custom.validated()
        precondition(validated.ammoCapacity == 200 && validated.reloadSeconds == 0.2)
        precondition(validated.maxEnemies >= validated.startingEnemies)
        precondition(validated.enemySpeed == 2.5)
        let rulesData = try! JSONEncoder().encode(validated)
        let decodedRules = try! JSONDecoder().decode(SiegeRules.self, from: rulesData)
        precondition(decodedRules == validated)

        // A reproducible city: large vacant blocks and clear streets first,
        // then clustered structures in just a subset of block interiors.
        precondition(CityLayout.isStreet(GroundPoint(0, 30)))
        precondition(CityLayout.isStreet(GroundPoint(60, 37)))
        precondition(CityLayout.isStreet(GroundPoint(7, 7)))
        precondition(!CityLayout.isStreet(GroundPoint(30, 30)))
        precondition(CityLayout.isBuildable(GroundPoint(30, 30), radius: 7))
        precondition(!CityLayout.isBuildable(GroundPoint(5, 30), radius: 5))
        let cityA = CityLayout.buildings(count: 23, seed: 8742)
        let cityB = CityLayout.buildings(count: 23, seed: 8742)
        let cityOther = CityLayout.buildings(count: 23, seed: 8743)
        precondition(cityA.count == 23, "Generate the configured building count")
        precondition(cityB.count == cityA.count)
        precondition(zip(cityA, cityB).allSatisfy { pair in
            pair.0.center.x == pair.1.center.x &&
            pair.0.center.z == pair.1.center.z
        }, "Same seed must reproduce the same town")
        precondition(zip(cityA, cityOther).contains { pair in
            pair.0.center.x != pair.1.center.x ||
            pair.0.center.z != pair.1.center.z
        }, "Different games should not use the same city blocks")
        let occupiedBlocks = Set(cityA.map { "\($0.blockX),\($0.blockZ)" })
        precondition(occupiedBlocks.count <= 9,
                     "Most of the 36 city blocks should remain empty")
        for site in cityA {
            precondition(CityLayout.isBuildable(
                site.center, radius: site.size * 0.9 + 2.7),
                "Building footprint must not enter a street")
        }
        for i in cityA.indices {
            for j in cityA.indices where j > i {
                precondition(cityA[i].center.distance(to: cityA[j].center) >
                             cityA[i].size * 0.78 + cityA[j].size * 0.78 + 5.4,
                             "Building collision buffers should not overlap")
            }
        }
        precondition(CityLayout.buildings(count: 0, seed: 1).isEmpty)
        precondition(CityLayout.buildings(count: 55, seed: 555).count == 55)
        let urban = CityLayout.buildings(count: 80, seed: 8526)
        precondition(urban.count == 80, "Default game should have a true city")
        let core = urban.filter { abs($0.blockX) <= 1 && abs($0.blockZ) <= 1 &&
                                  (-1...0).contains($0.blockX) &&
                                  (-1...0).contains($0.blockZ) }
        let mid = urban.filter { (-2...1).contains($0.blockX) &&
                                 (-2...1).contains($0.blockZ) &&
                                 !((-1...0).contains($0.blockX) &&
                                   (-1...0).contains($0.blockZ)) }
        let outside = urban.count - core.count - mid.count
        precondition(core.count == 36 && mid.count >= 28 && outside >= 10,
                     "High-density core, medium ring, and sparse outskirts")
        for building in urban {
            precondition(CityLayout.isBuildable(
                building.center, radius: building.size * 0.9 + 2.7),
                "No city building may block a street")
        }
        for index in urban.indices {
            for other in urban.indices where other > index {
                precondition(urban[index].center.distance(to: urban[other].center) >
                             urban[index].size * 0.78 +
                             urban[other].size * 0.78 + 5.4,
                             "City buildings must not overlap collision buffers")
            }
        }
        precondition(CityLayout.buildings(count: 120, seed: 123).count == 120,
                     "Maximum custom-city density remains supported")

        // Wave positions must fan out around the tank with a safe minimum
        // distance. Even if the preferred sector is blocked, never pile units.
        let origin = GroundPoint(0, 0)
        var spawned: [GroundPoint] = []
        for i in 0..<8 {
            let candidate = EnemySpawnLayout.choosePosition(
                player: origin, heading: 0, index: i, count: 8,
                existing: spawned,
                isOpen: { abs($0.x) < 185 && abs($0.z) < 185 })
            precondition(candidate != nil, "Unobstructed 8-way wave should spawn")
            let point = candidate!
            precondition(point.distance(to: origin) >= 28)
            precondition(EnemySpawnLayout.isSeparated(point, from: spawned))
            spawned.append(point)
        }
        precondition(spawned.count == 8)
        // Every new wave has a different angular phase. None of its enemies
        // may appear directly inside the commander's forward aiming cone.
        for phase in [-2.7, -0.9, 0.2, 1.6, 2.9] {
            var positions: [GroundPoint] = []
            for index in 0..<6 {
                let candidate = EnemySpawnLayout.choosePosition(
                    player: origin, heading: 0.6, index: index, count: 6,
                    existing: positions, phase: phase,
                    forwardExclusion: Double.pi / 5.0,
                    isOpen: { abs($0.x) < 177 && abs($0.z) < 177 })
                precondition(candidate != nil, "Wave needs safe side/rear spawn slots")
                let p = candidate!
                let bearing = atan2(p.x, p.z)
                precondition(abs(wrapAngle(bearing - 0.6)) >= Double.pi / 5 - 0.00001)
                precondition(EnemySpawnLayout.isSeparated(p, from: positions))
                positions.append(p)
            }
        }
        for angle in stride(from: -Double.pi, through: Double.pi,
                            by: Double.pi / 12) {
            let reach = TacticalRadarGeometry.squareReach(
                angle: angle, halfSide: 80)
            let x = abs(sin(angle) * reach)
            let y = abs(cos(angle) * reach)
            precondition(max(x, y) <= 80.00001)
            precondition(abs(max(x, y) - 80) < 0.00001,
                         "Radar beam must terminate exactly on the square")
        }
        // Group passive drones, but preserve separate clusters and counts.
        let radarGroups = TacticalRadarGeometry.droneClusters([
            GroundPoint(2, 4), GroundPoint(3, 5), GroundPoint(32, 35),
            GroundPoint(32, 39), GroundPoint(1, 1)
        ])
        precondition(radarGroups.count == 2)
        precondition(radarGroups.map(\.count).sorted() == [2, 3])
        precondition(TacticalRadarGeometry.droneClusters([]).isEmpty)
        precondition(TacticalRadarGeometry.droneClusters(
            [GroundPoint(1, 2)], cellSize: 0).isEmpty)
        precondition(TacticalRadarGeometry.intensity(trailingFraction: 0) == 1)
        precondition(TacticalRadarGeometry.intensity(trailingFraction: 1) == 0)
        precondition(TacticalRadarGeometry.intensity(trailingFraction: 0.2) >
                     TacticalRadarGeometry.intensity(trailingFraction: 0.8))
        precondition(!EnemySpawnLayout.isSeparated(
            GroundPoint(spawned[0].x + 1, spawned[0].z + 1),
            from: spawned))
        let impossible = EnemySpawnLayout.choosePosition(
            player: origin, heading: 0, index: 0, count: 2,
            existing: [], isOpen: { _ in false })
        precondition(impossible == nil, "Never fall back to a blocked spawn")

        // Save files retain exact magazine state, timers, world objects and shot stats.
        var savedAmmo = CannonMagazine(maxRounds: 75, reloadSeconds: 1.7)
        precondition(savedAmmo.fire())
        savedAmmo.advance(by: 0.3)
        var savedTally = ShotTally()
        savedTally.fire()
        savedTally.hit()
        let snapshot = SiegeSnapshot(
            version: 1, displayMode: "Modern", threatLevel: "Ace",
            soundOn: true, activePresetID: "unit-test", customRules: validated,
            score: 1500, lives: 2, wave: 4, gameClock: 123.5,
            heading: .pi / 2, driveSpeed: 5.2,
            tankPosition: GroundPoint(42, -17), shieldRemaining: 3.5,
            shieldCooldown: 8.1, invulnerability: 0, pendingWave: 0,
            cannon: savedAmmo, shotTally: savedTally,
            obstacles: [SavedSiegeObstacle(center: GroundPoint(10, 10), size: 4, kind: "pyramid")],
            enemies: [SavedSiegeFoe(center: GroundPoint(25, 12), heading: 1.3,
                                   kind: "hunter", reload: 2, phase: 0.8, hitPoints: 2)],
            shells: [SavedSiegeShell(center: GroundPoint(2, 6),
                                    direction: GroundPoint(0, 1), hostile: false, timeLeft: 1.1)],
            sparks: []
        )
        let slot = SiegeSaveSlot(id: "slot-1", name: "Test", savedAt: Date(),
                                 snapshot: snapshot)
        let encoded = try! JSONEncoder().encode(slot)
        let restored = try! JSONDecoder().decode(SiegeSaveSlot.self, from: encoded)
        precondition(restored.snapshot.displayMode == "Modern")
        precondition(restored.snapshot.score == 1500 && restored.snapshot.wave == 4)
        precondition(restored.snapshot.cannon.roundsRemaining == 74)
        precondition(abs(restored.snapshot.cannon.reloadRemaining - 1.4) < 0.0001)
        precondition(restored.snapshot.shotTally.hits == 1)
        precondition(restored.snapshot.enemies.first?.kind == "hunter")
        precondition(restored.snapshot.obstacles.first?.kind == "pyramid")
        precondition(restored.snapshot.shells.count == 1)
        precondition(restored.snapshot.customRules == validated)
        precondition(restored.snapshot.awaitingLevelStart == nil,
                     "Older save games should remain compatible")
        var levelSnapshot = snapshot
        levelSnapshot.awaitingLevelStart = true
        let introData = try! JSONEncoder().encode(levelSnapshot)
        let loadedIntro = try! JSONDecoder().decode(SiegeSnapshot.self, from: introData)
        precondition(loadedIntro.awaitingLevelStart == true,
                     "Save/Resume must preserve a pending level-intro")

        // Dynamic pressure never creates extra opponents or increases the
        // permitted number of simultaneous hostile rounds.
        precondition(DynamicBattlefieldDirector.nextPressure(
            current: 0, waveSeconds: 37, livesLost: 0, hitRate: 75, wave: 3) == 1)
        precondition(DynamicBattlefieldDirector.nextPressure(
            current: 1, waveSeconds: 37, livesLost: 0, hitRate: 90, wave: 5) == 1)
        precondition(DynamicBattlefieldDirector.nextPressure(
            current: 1, waveSeconds: 90, livesLost: 1, hitRate: 85, wave: 5) == 0)
        precondition(DynamicBattlefieldDirector.nextPressure(
            current: 0, waveSeconds: 155, livesLost: 0, hitRate: 20, wave: 4) == -1)
        precondition(DynamicBattlefieldDirector.nextPressure(
            current: 1, waveSeconds: 30, livesLost: 0, hitRate: 100, wave: 1) == 0)
        precondition(DynamicBattlefieldDirector.hostileShotLimit(
            wave: 5, pressure: 1) == BattlefieldWaveDirector.maximumHostileShots(forWave: 5))
        precondition(DynamicBattlefieldDirector.hostileShotLimit(wave: 5, pressure: -1) == 2)
        precondition(DynamicBattlefieldDirector.reinforcementDelay(
            base: 9, pressure: -1) > 9)
        precondition(DynamicBattlefieldDirector.reinforcementDelay(
            base: 9, pressure: 1) < 9)
        precondition(DynamicBattlefieldDirector.fireCooldownFactor(pressure: -1) > 1)
        precondition(DynamicBattlefieldDirector.fireCooldownFactor(pressure: 1) < 1)
        var tuned = snapshot
        tuned.directorPressure = -1
        tuned.directorWaveStartLives = 3
        tuned.directorWaveStartFired = 12
        tuned.directorWaveStartHits = 6
        let decodedTuned = try! JSONDecoder().decode(SiegeSnapshot.self,
            from: JSONEncoder().encode(tuned))
        precondition(decodedTuned.directorPressure == -1)
        precondition(decodedTuned.directorWaveStartFired == 12)
        precondition(restored.snapshot.directorPressure == nil)

        // Air groups rotate a six-drone attack lane without adding
        // simultaneous hostile shot pressure or gating ground waves.
        precondition(AirEncounterDirector.activeWing(elapsed: -0.01) == nil)
        precondition(AirEncounterDirector.activeWing(elapsed: 0) == 0)
        precondition(AirEncounterDirector.activeWing(elapsed: 3.99) == 0)
        precondition(AirEncounterDirector.activeWing(elapsed: 4.0) == nil)
        precondition(AirEncounterDirector.activeWing(elapsed: 13) == 1)
        precondition(AirEncounterDirector.activeWing(elapsed: 26) == 2)
        precondition(AirEncounterDirector.isAttacking(
            droneIndex: 0, elapsed: 0))
        precondition(!AirEncounterDirector.isAttacking(
            droneIndex: 6, elapsed: 0))
        precondition(AirEncounterDirector.isAttacking(
            droneIndex: 6, elapsed: 13))
        precondition(AirEncounterDirector.isAttacking(
            droneIndex: 29, elapsed: 52))
        precondition(AirEncounterDirector.mayLaunchAirThreat(
            groundRemaining: 2, simultaneousHostileShots: 1,
            currentAirCount: 30, maxHostileShots: 3))
        precondition(!AirEncounterDirector.mayLaunchAirThreat(
            groundRemaining: 0, simultaneousHostileShots: 0,
            currentAirCount: 0, maxHostileShots: 3))
        precondition(!AirEncounterDirector.mayLaunchAirThreat(
            groundRemaining: 2, simultaneousHostileShots: 3,
            currentAirCount: 30, maxHostileShots: 3))
        // New optional air state survives round-trip while legacy v1
        // SavedSiegeFoe shapes remain decodable.
        var restoredDrone = SavedSiegeFoe(
            center: GroundPoint(14, 23), heading: 0.5,
            kind: "drone", reload: 999, phase: 1.0, hitPoints: 1)
        precondition(restoredDrone.droneSeed == nil &&
                     restoredDrone.droneHasCharge == nil)
        restoredDrone.droneSeed = 4.854
        restoredDrone.droneOffset = GroundPoint(4, -3)
        restoredDrone.droneHasCharge = false
        restoredDrone.droneDropDelay = 2.5
        restoredDrone.droneDisrupted = 1.5
        restoredDrone.droneAltitude = 4.0
        restoredDrone.airShotsFired = 1
        let savedDroneData = try! JSONEncoder().encode(restoredDrone)
        let reloadedDrone = try! JSONDecoder().decode(
            SavedSiegeFoe.self, from: savedDroneData)
        precondition(reloadedDrone.droneSeed == 4.854 &&
                     reloadedDrone.droneHasCharge == false &&
                     reloadedDrone.droneOffset?.x == 4 &&
                     reloadedDrone.airShotsFired == 1)

        // Patrol arrival is based on active time, not wall clock or wave number.
        var patrol = SaucerPatrolClock()
        precondition(patrol.secondsUntilArrival == 15)
        precondition(!patrol.advance(by: 14.99))
        precondition(patrol.advance(by: 0.01))
        precondition(abs(patrol.secondsUntilArrival - SaucerPatrolClock.interval) < 0.0001)
        precondition(!patrol.advance(by: 57.99))
        precondition(patrol.advance(by: 0.01))
        patrol.restore(secondsRemaining: 23.5)
        precondition(patrol.secondsUntilArrival == 23.5)
        patrol.restore(secondsRemaining: nil)
        precondition(patrol.secondsUntilArrival == SaucerPatrolClock.interval)
        patrol.restore(secondsRemaining: .infinity)
        precondition(patrol.secondsUntilArrival == SaucerPatrolClock.interval)
        precondition(!patrol.advance(by: 0), "Pause must not advance timer")
        // Terrain is gently sloped, curbs are raised, and road grades are
        // always shallower than the surrounding landscape.
        // Downtown is intentionally flatter than the surrounding hills.
        precondition(abs(LandscapeTopology.height(GroundPoint(30, 30))) < 0.8)
        precondition(LandscapeTopology.clearFiringLine(
            from: GroundPoint(20, 20), to: GroundPoint(40, 40)))
        // Outer ridgelines are meaningful cover and intercept flat rounds.
        precondition(!LandscapeTopology.clearFiringLine(
            from: GroundPoint(-150, -150), to: GroundPoint(-60, -150)))
        precondition(LandscapeTopology.firstTerrainImpact(
            from: GroundPoint(-150, -120), to: GroundPoint(-90, -150),
            altitude: LandscapeTopology.height(GroundPoint(-150, -120)) + 1.65) != nil)
        precondition(LandscapeTopology.firstTerrainImpact(
            from: GroundPoint(20, 20), to: GroundPoint(40, 40),
            altitude: 5.0) == nil)
        let road = LandscapeTopology.height(GroundPoint(0, 30))
        let curb = LandscapeTopology.height(GroundPoint(9.3, 30))
        precondition(curb > road + 0.15)
        for x in stride(from: -150.0, through: 150.0, by: 10.0) {
            precondition(LandscapeTopology.height(GroundPoint(x, 24)).isFinite)
        }

        let migratedSave = try! JSONDecoder().decode(
            SiegeSaveSlot.self,
            from: JSONEncoder().encode(slot))
        precondition(migratedSave.snapshot.secondsUntilSaucerPatrol == nil,
                     "Old save slots must decode without the patrol field")

        precondition(TankProximity.alertRadius == 30)
        precondition(!TankProximity.isClose(30.01))
        precondition(TankProximity.isClose(30))
        precondition(TankProximity.isClose(12))
        precondition(TankProximity.isClose(6))
        precondition(!TankProximity.isClose(-1))
        precondition(!TankProximity.isClose(.infinity))
        precondition(TankProximity.repeatInterval(for: 5) <
                     TankProximity.repeatInterval(for: 10))
        precondition(TankProximity.repeatInterval(for: 10) <
                     TankProximity.repeatInterval(for: 28),
                     "Alarm must become more urgent as enemy approaches")

        // Real structure footprints, rather than undersized center circles,
        // must block shells at corners, walls and all four cardinal faces.
        let block = ObstacleCollision.body(
            center: GroundPoint(0, 0), size: 5, kind: .block)
        precondition(block.halfX == 5 && block.halfZ == 5)
        precondition(ObstacleCollision.contains(
            GroundPoint(4.7, 4.7), body: block, height: 1.65),
            "Previously unprotected square block corners must be solid")
        precondition(!ObstacleCollision.contains(
            GroundPoint(5.3, 5.3), body: block, height: 1.65))
        let wall = ObstacleCollision.firstImpact(
            from: GroundPoint(-15, 4.8), to: GroundPoint(15, 4.8),
            body: block, height: 1.65)
        precondition(wall != nil && abs(wall! - 1.0/3.0) < 0.000001,
                     "Bullet grazing visible near-edge must impact exactly")
        precondition(ObstacleCollision.firstImpact(
            from: GroundPoint(-15, 5.3), to: GroundPoint(15, 5.3),
            body: block, height: 1.65) == nil)
        precondition(ObstacleCollision.firstImpact(
            from: GroundPoint(0, 0), to: GroundPoint(10, 0),
            body: block, height: 1.65) == 0,
            "Projectile starting inside solid cover hits immediately")
        precondition(ObstacleCollision.firstImpact(
            from: GroundPoint(-20, 0), to: GroundPoint(20, 0),
            body: block, height: 1.65) != nil,
            "Fast bullets cannot pass all the way through a block in one frame")
        precondition(ObstacleCollision.firstImpact(
            from: GroundPoint(-15, 0), to: GroundPoint(15, 0),
            body: block, height: 8) == nil,
            "A projectile flying above a roof is not blocked by it")

        let pyramid = ObstacleCollision.body(
            center: GroundPoint(0, 0), size: 6, kind: .pyramid)
        precondition(ObstacleCollision.contains(
            GroundPoint(5, 0), body: pyramid, height: 0))
        precondition(!ObstacleCollision.contains(
            GroundPoint(5, 0), body: pyramid, height: 4),
            "Pyramid collision cross section tapers toward the peak")
        precondition(ObstacleCollision.firstImpact(
            from: GroundPoint(-8, 4), to: GroundPoint(8, 4),
            body: pyramid, height: 2.0) != nil)
        let tower = ObstacleCollision.body(
            center: GroundPoint(0, 0), size: 6, kind: .tower)
        let building = ObstacleCollision.body(
            center: GroundPoint(0, 0), size: 6, kind: .building)
        let monolith = ObstacleCollision.body(
            center: GroundPoint(0, 0), size: 6, kind: .monolith)
        precondition(abs(tower.halfX - 3.3) < 1e-10 &&
                     abs(monolith.halfZ - 2.52) < 1e-10)
        precondition(abs(building.halfX - 6.3) < 1e-10)

        // The same rectangular footprint governs tank driving and AI sight.
        let solid = [NavigationObstacle(body: building)]
        precondition(!EnemyNavigation.clearSegment(
            GroundPoint(-15, 4), GroundPoint(15, 4),
            obstacles: solid, height: 1.5))
        precondition(EnemyNavigation.clearSegment(
            GroundPoint(-15, 7), GroundPoint(15, 7),
            obstacles: solid, height: 1.5))
        precondition(!EnemyNavigation.isWalkable(
            GroundPoint(5, 3), obstacles: solid, otherTanks: []))
        precondition(EnemyNavigation.isWalkable(
            GroundPoint(20, 20), obstacles: solid, otherTanks: []))
        // Wall at x=5 hits at t=1/3; a tank at x=10 is farther away.
        let enemyBehind = ObstacleCollision.firstCircleImpact(
            from: GroundPoint(-15, 0), to: GroundPoint(15, 0),
            center: GroundPoint(10, 0), radius: 2.9)
        precondition(wall! < enemyBehind!,
                     "A blocking wall must be resolved before a farther target")
        // Conversely a near enemy must be hit before an obstacle behind it.
        let enemyBefore = ObstacleCollision.firstCircleImpact(
            from: GroundPoint(-15, 0), to: GroundPoint(15, 0),
            center: GroundPoint(-10, 0), radius: 2.9)
        precondition(enemyBefore! < wall!,
                     "A target in front of a wall must not be hidden by it")

        // Combined-arms waves ramp gradually and always stay within a
        // tank-defeatable target budget, including a two-hit aircraft.
        precondition(BattlefieldWaveDirector.drones(forWave: 1) == 0)
        precondition(BattlefieldWaveDirector.drones(forWave: 2) == 0)
        precondition(BattlefieldWaveDirector.drones(forWave: 3) == 30)
        precondition(BattlefieldWaveDirector.drones(forWave: 6) == 30)
        precondition(BattlefieldWaveDirector.drones(forWave: 15) == 30)
        precondition(BattlefieldWaveDirector.fighters(forWave: 4) == 0)
        precondition(BattlefieldWaveDirector.fighters(forWave: 5) == 1)
        let veteran = SiegeRules().validated()
        for level in 1...20 {
            let ground = veteran.enemies(forWave: level)
            let drones = BattlefieldWaveDirector.drones(forWave: level)
            let fighters = BattlefieldWaveDirector.fighters(forWave: level)
            // Thirty independent targets form one group; finite chaff
            // charges and normal cannon reload enable swarm attrition.
            precondition(ground <= 8)
            precondition(drones == 0 || drones == 30)
            precondition(ground * 2 + fighters * 2 <= veteran.ammoCapacity)
            precondition(BattlefieldWaveDirector.maximumHostileShots(
                forWave: level) <= 3)
            precondition(BattlefieldWaveDirector.droneDelay(forWave: level) >= 8)
            precondition(BattlefieldWaveDirector.fighterDelay(forWave: level) >= 16)
        }
        precondition(ChaffDefense.chargesPerWave == 2)
        precondition(ChaffDefense.cooldown >= 8)
        precondition(ChaffDefense.disrupts(distance: 25))
        precondition(!ChaffDefense.disrupts(distance: 40))

        // Each ground squad must originate from one approach sector, not
        // cardinally around the player, and never overlap or spawn ahead.
        for approach in [1.55, 2.15, -2.10] {
            var squad: [GroundPoint] = []
            for i in 0..<6 {
                guard let candidate = SquadSpawnLayout.choose(
                    player: GroundPoint(0, 0), heading: 0,
                    approach: approach, index: i, count: 6,
                    existing: squad, isOpen: { _ in true }) else {
                    fatalError("Six squad positions should fit a clear city")
                }
                let direction = atan2(candidate.x, candidate.z)
                precondition(abs(wrapAngle(direction - approach)) <= 0.91)
                precondition(abs(wrapAngle(direction)) > Double.pi / 5)
                precondition(EnemySpawnLayout.isSeparated(candidate, from: squad))
                squad.append(candidate)
            }
        }

        // New field defaults must round trip without invalidating legacy v1
        // archive decoding. Bomb payload is optional for old saves.
        let magazine = SavedSiegeShell(
            center: GroundPoint(2, 3), direction: GroundPoint(0, 1),
            hostile: true, timeLeft: 3.5, payload: "bomb")
        let encodedPayload = try! JSONEncoder().encode(magazine)
        let roundTripped = try! JSONDecoder().decode(
            SavedSiegeShell.self, from: encodedPayload)
        precondition(roundTripped.payload == "bomb")
        let legacyProjectileJSON = """
        {"center":{"x":2,"z":3},"direction":{"x":0,"z":1},
         "hostile":true,"timeLeft":3.5}
        """
        let legacyProjectile = try! JSONDecoder().decode(
            SavedSiegeShell.self, from: Data(legacyProjectileJSON.utf8))
        precondition(legacyProjectile.payload == nil)

        // A tank facing a building must be able to choose a reachable
        // intermediate waypoint around cover rather than driving into it.
        let cover = [NavigationObstacle(center: GroundPoint(42, 0), radius: 13)]
        let tankStart = GroundPoint(0, 0)
        let playerAt = GroundPoint(95, 0)
        precondition(!EnemyNavigation.clearSegment(
            tankStart, playerAt, obstacles: cover))
        let detour = EnemyNavigation.nextWaypoint(
            from: tankStart, player: playerAt, obstacles: cover,
            shotBlockers: cover, otherTanks: [])
        precondition(detour != nil, "Tank must route around an obstructing building")
        if let waypoint = detour {
            precondition(EnemyNavigation.clearSegment(
                tankStart, waypoint, obstacles: cover,
                clearance: EnemyNavigation.enemyRadius))
            precondition(EnemyNavigation.isWalkable(
                waypoint, obstacles: cover, otherTanks: []))
        }
        // Clear firing lanes should never be mistaken for blocked lanes.
        precondition(EnemyNavigation.clearSegment(
            GroundPoint(0, 40), GroundPoint(95, 40), obstacles: cover))
        // Close-range enemy collision buffers must be respected.
        precondition(!EnemyNavigation.isWalkable(
            GroundPoint(42, 0), obstacles: cover, otherTanks: []))
        precondition(!EnemyNavigation.isWalkable(
            GroundPoint(10, 10), obstacles: [],
            otherTanks: [GroundPoint(12, 10)]))

        print("Perspective, ammo, patrol, five-length warning and enemy detours passed.")
    }
}