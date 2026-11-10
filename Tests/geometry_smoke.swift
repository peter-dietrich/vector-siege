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

        // Patrol arrival is based on active time, not wall clock or wave number.
        var patrol = SaucerPatrolClock()
        precondition(patrol.secondsUntilArrival == 120)
        precondition(!patrol.advance(by: 60))
        precondition(patrol.secondsUntilArrival == 60)
        precondition(!patrol.advance(by: 59.95))
        precondition(patrol.advance(by: 0.05))
        precondition(abs(patrol.secondsUntilArrival - 120) < 0.0001)
        precondition(!patrol.advance(by: 119.99))
        precondition(patrol.advance(by: 0.01))
        patrol.restore(secondsRemaining: 23.5)
        precondition(patrol.secondsUntilArrival == 23.5)
        patrol.restore(secondsRemaining: nil)
        precondition(patrol.secondsUntilArrival == 120)
        patrol.restore(secondsRemaining: .infinity)
        precondition(patrol.secondsUntilArrival == 120)
        precondition(!patrol.advance(by: 0), "Pause must not advance timer")

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