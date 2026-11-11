import Foundation

struct GroundPoint: Codable {
    var x: Double
    var z: Double
    init(_ x: Double, _ z: Double) { self.x = x; self.z = z }

    static func + (a: Self, b: Self) -> Self { Self(a.x + b.x, a.z + b.z) }
    static func - (a: Self, b: Self) -> Self { Self(a.x - b.x, a.z - b.z) }
    static func * (a: Self, n: Double) -> Self { Self(a.x * n, a.z * n) }
    var length: Double { hypot(x, z) }
    var normalized: Self { self * (1 / max(0.00001, length)) }
    func distance(to p: Self) -> Double { (self - p).length }
}

struct WorldPoint: Codable {
    var x: Double
    var y: Double
    var z: Double
    init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    init(_ ground: GroundPoint, height: Double) { self.init(ground.x, height, ground.z) }
}

/// Continuous low-amplitude landscape. Streets follow gentle grade while
/// blocks rise away from a raised, clearly visible curb edge.
enum LandscapeTopology {
    static let roadSpacing = 60.0
    static let roadHalfWidth = 9.0

    static func distanceToRoadAxis(_ n: Double) -> Double {
        abs(n - (n / roadSpacing).rounded() * roadSpacing)
    }

    static func height(_ p: GroundPoint) -> Double {
        let dx = distanceToRoadAxis(p.x)
        let dz = distanceToRoadAxis(p.z)
        let nearest = min(dx, dz)
        // Road grade is deliberately gentle to keep steering predictable.
        let grade = 0.42 * sin(p.x / 63) + 0.36 * cos(p.z / 71)
        // Downtown is a deliberately restrained, readable urban plateau;
        // hill strength ramps smoothly outside the central city blocks.
        let center = max(abs(p.x), abs(p.z))
        let urban = min(1.0, max(0.0, (center - 68.0) / 64.0))
        let terrainStrength = urban * urban * (3.0 - 2.0 * urban)
        let rolling = terrainStrength * (
            2.3 * sin(p.x / 31) * cos(p.z / 42) +
            1.5 * sin((p.x + p.z) / 66) +
            1.4 * cos((p.x - p.z) / 47))
        if nearest <= roadHalfWidth { return grade * (0.4 + 0.6 * terrainStrength) }
        // 0.28-unit curb lip; beyond it landscaping gradually rises
        // to the full rolling height without sharp cliffs.
        let distance = nearest - roadHalfWidth
        let blend = min(1.0, max(0.0, distance / 7.0))
        let smooth = blend * blend * (3 - 2 * blend)
        let roadGrade = grade * (0.4 + 0.6 * terrainStrength)
        return roadGrade + 0.28 + rolling * smooth
    }

    /// Terrain occlusion for tank-to-tank aim lines. Sample a low-height
    /// sight ray above both endpoints, so hills and berms provide real cover.
    static func clearFiringLine(from start: GroundPoint, to end: GroundPoint,
                                eyeHeight: Double = 1.65) -> Bool {
        let span = end - start
        let distance = span.length
        if distance < 0.01 { return true }
        let startY = height(start) + eyeHeight
        let endY = height(end) + eyeHeight
        let steps = max(2, Int(ceil(distance / 2.5)))
        for i in 1..<steps {
            let t = Double(i) / Double(steps)
            let p = start + span * t
            let ray = startY + (endY - startY) * t
            if height(p) > ray - 0.17 { return false }
        }
        return true
    }

    /// First physical ground interception for a projectile at a fixed
    /// world altitude (the cannon uses a shallow, arcade-style trajectory).
    static func firstTerrainImpact(from start: GroundPoint, to end: GroundPoint,
                                   altitude: Double, clearance: Double = 0.12) -> Double? {
        let span = end - start
        let distance = span.length
        if distance < 0.01 { return nil }
        let steps = max(1, Int(ceil(distance / 1.4)))
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            if height(start + span * t) + clearance >= altitude { return t }
        }
        return nil
    }
}

struct CameraProjection {
    var position: GroundPoint
    var yaw: Double
    var viewportWidth: Double
    var viewportHeight: Double
    var eyeHeight = 1.5
    var terrainEnabled = false
    var cameraLateral: Double = 0
    var pitchPoints: Double = 0

    var focal: Double { min(viewportWidth * 0.89, viewportHeight * 1.45) }
    var horizon: Double { viewportHeight * 0.455 + pitchPoints }

    func local(_ world: WorldPoint) -> (right: Double, up: Double, forward: Double) {
        let dx = world.x - position.x
        let dz = world.z - position.z
        return (dx * cos(yaw) - dz * sin(yaw) - cameraLateral, world.y + (terrainEnabled ? LandscapeTopology.height(GroundPoint(world.x, world.z)) : 0) - eyeHeight,
                dx * sin(yaw) + dz * cos(yaw))
    }

    func screen(right: Double, up: Double, forward: Double) -> (x: Double, y: Double) {
        (viewportWidth / 2 + focal * right / forward,
         horizon + focal * up / forward)
    }

    /// Clips a 3D line to a near plane, avoiding exploding coordinates when a line crosses the viewer.
    func clipLine(_ a: WorldPoint, _ b: WorldPoint, near: Double = 0.7)
        -> ((Double, Double), (Double, Double))? {
        var v = local(a)
        var w = local(b)
        if v.forward < near && w.forward < near { return nil }
        if v.forward < near {
            let t = (near - v.forward) / (w.forward - v.forward)
            v = (v.right + (w.right - v.right) * t,
                 v.up + (w.up - v.up) * t, near)
        } else if w.forward < near {
            let t = (near - w.forward) / (v.forward - w.forward)
            w = (w.right + (v.right - w.right) * t,
                 w.up + (v.up - w.up) * t, near)
        }
        let p = screen(right: v.right, up: v.up, forward: v.forward)
        let q = screen(right: w.right, up: w.up, forward: w.forward)
        if !p.x.isFinite || !p.y.isFinite || !q.x.isFinite || !q.y.isFinite { return nil }
        return ((p.x, p.y), (q.x, q.y))
    }
}

func wrapAngle(_ angle: Double) -> Double {
    atan2(sin(angle), cos(angle))
}

func facing(_ angle: Double) -> GroundPoint { GroundPoint(sin(angle), cos(angle)) }

/// Fine keyboard aiming: one small step on key-down, then a delayed,
/// smoothly accelerating turn while the direction is held.
enum PrecisionSteering {
    static let tapAngle = Double.pi / 360.0 // 0.5 degree per tap
    static let holdDelay = 0.12

    static func heldRate(elapsed: Double) -> Double {
        guard elapsed > holdDelay else { return 0 }
        let ramp = min(1.0, max(0.0, (elapsed - holdDelay) / 0.45))
        return 0.32 + 1.65 * ramp // 0.32 -> 1.97 rad/sec
    }
}


/// 40-shot player cannon with a fixed one-second reload after every shot.
/// Shared by Classic and Modern display modes.
struct CannonMagazine: Codable {
    static let capacity = 40
    static let minimumReload = 1.0
    static let maximumReload = 1.0

    private(set) var roundsRemaining = capacity
    private(set) var maxRounds = capacity
    private(set) var reloadSeconds = 1.0

    init(maxRounds: Int = CannonMagazine.capacity, reloadSeconds: Double = 1.0) {
        let bounded = max(1, min(200, maxRounds))
        self.maxRounds = bounded
        self.roundsRemaining = bounded
        self.reloadSeconds = max(0.2, min(6, reloadSeconds))
    }
    private(set) var reloadRemaining: Double = 0
    private(set) var lastReloadDuration: Double = 0

    var canFire: Bool { roundsRemaining > 0 && reloadRemaining <= 0 }
    var isEmpty: Bool { roundsRemaining == 0 }

    var statusText: String {
        if isEmpty { return "EMPTY" }
        if reloadRemaining > 0 { return String(format: "RELOAD %.1fs", reloadRemaining) }
        return "READY"
    }

    mutating func fire(reloadDuration: Double? = nil) -> Bool {
        guard canFire else { return false }
        roundsRemaining -= 1
        let sampled = reloadDuration ?? reloadSeconds
        lastReloadDuration = max(0.2, min(6.0, sampled))
        reloadRemaining = roundsRemaining > 0 ? lastReloadDuration : 0
        return true
    }

    mutating func advance(by dt: Double) {
        reloadRemaining = max(0, reloadRemaining - max(0, dt))
    }
}


/// Tallies only confirmed outcomes; unresolved rounds remain in flight.
struct ShotTally: Codable {
    private(set) var fired = 0
    private(set) var hits = 0
    private(set) var misses = 0

    var pending: Int { max(0, fired - hits - misses) }
    var resolved: Int { hits + misses }
    var hitPercentage: Double {
        resolved > 0 ? 100 * Double(hits) / Double(resolved) : 0
    }

    mutating func fire() { fired += 1 }
    mutating func hit() {
        if pending > 0 { hits += 1 }
    }
    mutating func miss() {
        if pending > 0 { misses += 1 }
    }
}

/// A critically damped-ish vehicle suspension with a short nose dip / rebound
/// on acceleration and braking. Rendering uses this, not actual gun aim.
struct TankSuspension {
    private(set) var pitch: Double = 0
    private(set) var pitchVelocity: Double = 0
    private(set) var lastSpeed: Double = 0

    mutating func reset() {
        pitch = 0
        pitchVelocity = 0
        lastSpeed = 0
    }

    mutating func update(speed: Double, dt: Double) {
        let step = max(0, min(0.04, dt))
        guard step > 0 else { return }
        let delta = speed - lastSpeed
        lastSpeed = speed
        // A speed change kicks the hull; spring and damping then settle it.
        pitchVelocity -= delta * 0.14
        pitchVelocity += (-54 * pitch - 10.5 * pitchVelocity) * step
        pitch = min(0.125, max(-0.125, pitch + pitchVelocity * step))
    }
}


/// Shared baseline movement speeds (before skill/custom multipliers).
/// Saucer motion was reduced from 1.10 to 0.33, a 70% decrease.
enum EnemyMotion {
    static let saucerBaseSpeed = 10.0
}

/// Spread initial enemies into angular sectors instead of clustering around
/// a random heading. Reject any overlap with previous spawns or level geometry.
enum EnemySpawnLayout {
    static let minimumSpacing = 30.0
    static let movementSpacing = 10.5

    static func isSeparated(_ candidate: GroundPoint,
                            from positions: [GroundPoint],
                            minimum: Double = minimumSpacing) -> Bool {
        positions.allSatisfy { candidate.distance(to: $0) >= minimum }
    }

    static func choosePosition(
        player: GroundPoint, heading: Double, index: Int, count: Int,
        existing: [GroundPoint], phase: Double = 0,
        forwardExclusion: Double = 0, isOpen: (GroundPoint) -> Bool
    ) -> GroundPoint? {
        // Randomizing the wave's phase (once per wave) breaks the previous
        // fixed first-enemy-at-heading alignment. The optional exclusion
        // prevents any enemy from starting in the player's central sightline.
        let sector = heading + phase +
            2 * Double.pi * Double(index) / Double(max(1, count))
        let angleOffsets: [Double] = [0, 0.18, -0.18, 0.36, -0.36,
                                      0.58, -0.58, 0.83, -0.83]
        let radii: [Double] = [76, 92, 110, 62, 128, 48, 140]
        func acceptable(_ point: GroundPoint) -> Bool {
            let offset = point - player
            let bearing = atan2(offset.x, offset.z)
            let centeredOnPlayer = abs(wrapAngle(bearing - heading))
            return offset.length >= 43 &&
                centeredOnPlayer >= forwardExclusion &&
                isSeparated(point, from: existing) && isOpen(point)
        }
        for offset in angleOffsets {
            for distance in radii {
                let position = player + facing(sector + offset) * distance
                if acceptable(position) { return position }
            }
        }
        // Search the full circle if a sector is blocked by buildings or the
        // world boundary. Never choose an overlapping fallback position.
        for offset in 0..<72 {
            let angle = sector + Double(offset) * (2 * Double.pi / 72)
            for distance in radii {
                let position = player + facing(angle) * distance
                if acceptable(position) { return position }
            }
        }
        return nil
    }
}

/// Mixed-arms difficulty is deliberately bounded. Ground vehicles deploy
/// together; drones and one aircraft arrive later as optional reinforcements.
/// None of the air units are bullet sponges or require a separate weapon.
enum BattlefieldWaveDirector {
    static func drones(forWave wave: Int) -> Int {
        guard wave >= 3 else { return 0 }
        // One visual cloud, introduced at wave three. Keep weapon pressure
        // bounded separately from the visual density.
        return 30
    }
    static func fighters(forWave wave: Int) -> Int {
        wave >= 5 ? 1 : 0
    }
    static func droneDelay(forWave wave: Int) -> Double {
        8.0 + Double(wave % 3)
    }
    static func fighterDelay(forWave wave: Int) -> Double {
        16.0 + Double(wave % 3)
    }
    static func maximumHostileShots(forWave wave: Int) -> Int {
        // One volley at a time early on; never more than three in late waves.
        wave < 5 ? 2 : 3
    }
    static func vehicleKind(index: Int, wave: Int) -> String {
        if wave >= 4 && index == 0 { return "artillery" }
        if wave >= 3 && index % 4 == 2 { return "hunter" }
        if wave >= 2 && index % 3 == 1 { return "apc" }
        return "tank"
    }
}

/// Predictable mixed-air encounter pacing. This is intentionally small:
/// the existing 30-drone cloud remains a visual formation, but only one of
/// five six-drone wings conducts a brief attack run at a time.
enum AirEncounterDirector {
    static let droneWingSize = 6
    static let droneWingCount = 5
    static let attackPeriod = 13.0
    static let attackDuration = 4.0
    static let fighterLifetime = 19.0
    static let saucerLifetime = 22.0

    static func activeWing(elapsed: Double) -> Int? {
        guard elapsed >= 0 else { return nil }
        let phase = elapsed.truncatingRemainder(dividingBy: attackPeriod)
        guard phase < attackDuration else { return nil }
        return Int(elapsed / attackPeriod) % droneWingCount
    }

    static func isAttacking(droneIndex: Int, elapsed: Double) -> Bool {
        guard droneIndex >= 0 else { return false }
        return activeWing(elapsed: elapsed) ==
            (droneIndex / droneWingSize) % droneWingCount
    }

    static func mayLaunchAirThreat(groundRemaining: Int,
                                   simultaneousHostileShots: Int,
                                   currentAirCount: Int,
                                   maxHostileShots: Int) -> Bool {
        groundRemaining > 0 && currentAirCount < 34 &&
            simultaneousHostileShots < maxHostileShots
    }
}

/// Place a squad within the same approach quadrant rather than surrounding
/// the player in a perfect circle. Always respect a clear central sightline,
/// street/building exclusions, minimum separation and map boundaries.
enum SquadSpawnLayout {
    static let angularHalfWidth = 0.72

    static func choose(
        player: GroundPoint, heading: Double, approach: Double,
        index: Int, count: Int, existing: [GroundPoint],
        isOpen: (GroundPoint) -> Bool
    ) -> GroundPoint? {
        let slot = index % 5
        let row = index / 5
        let slotOffsets: [Double] = [-0.62, -0.30, 0, 0.30, 0.62]
        let baseAngle = approach + slotOffsets[slot]
        let primaryRadii: [Double] = [78, 112, 144, 92, 128, 158]
        for offset in [0.0, 0.12, -0.12, 0.24, -0.24] {
            let bearing = baseAngle + offset
            guard abs(wrapAngle(bearing - approach)) <= angularHalfWidth + 0.18,
                  abs(wrapAngle(bearing - heading)) > Double.pi / 5 else { continue }
            for delta in [0, 24, -24, 43, -43] {
                for radius in primaryRadii {
                    let distance = radius + Double(row) * 12 + Double(delta)
                    guard distance >= 50 && distance <= 170 else { continue }
                    let point = player + facing(bearing) * distance
                    if abs(point.x) >= 177 || abs(point.z) >= 177 { continue }
                    if EnemySpawnLayout.isSeparated(point, from: existing) &&
                        isOpen(point) {
                        return point
                    }
                }
            }
        }
        return nil
    }
}

/// Anti-drone countermeasure uses finite charges and a real cooldown, so the
/// player must choose between chaff, shield and accurate cannon fire.
enum ChaffDefense {
    static let chargesPerWave = 2
    static let cooldown = 9.0
    static let protectionDuration = 4.0
    static let disruptionRadius = 34.0
    static let decoyRadius = 80.0
    static func disrupts(distance: Double) -> Bool {
        distance >= 0 && distance <= disruptionRadius
    }
}

/// Pure sweep geometry used by the tactical-radar fill and regression tests.
/// A ray is clipped to the edges of a square to prevent sweep glow escaping
/// the panel even when the beam passes near a corner.
enum TacticalRadarGeometry {
    static func squareReach(angle: Double, halfSide: Double) -> Double {
        halfSide / max(abs(sin(angle)), abs(cos(angle)), 0.000001)
    }
    static func intensity(trailingFraction: Double) -> Double {
        let t = min(1, max(0, trailingFraction))
        return (1 - t) * (1 - t)
    }
}

/// Street-first, world-aligned city layout shared by world generation, drawing
/// and the tactical radar. Streets are wide enough for full-sized tanks and are
/// never populated with procedural building obstacles.
struct CityBuildingSite {
    var center: GroundPoint
    var size: Double
    var variant: Int
    var blockX: Int
    var blockZ: Int
}

enum CityLayout {
    static let streetSpacing = 60.0
    static let streetHalfWidth = 9.0
    static let cityExtent = 180.0
    static let blockHalfWidth = streetSpacing / 2 - streetHalfWidth - 1.5

    /// True for roads running north/south or east/west, including junctions.
    static func isStreet(_ p: GroundPoint, clearance: Double = 0) -> Bool {
        let xRoad = abs(p.x - (p.x / streetSpacing).rounded() * streetSpacing)
        let zRoad = abs(p.z - (p.z / streetSpacing).rounded() * streetSpacing)
        return xRoad <= streetHalfWidth + clearance ||
               zRoad <= streetHalfWidth + clearance
    }

    static func isBuildable(_ p: GroundPoint, radius: Double) -> Bool {
        guard abs(p.x) <= cityExtent - 2, abs(p.z) <= cityExtent - 2 else {
            return false
        }
        return !isStreet(p, clearance: radius + 2.0)
    }

    static func blockCenter(x: Int, z: Int) -> GroundPoint {
        GroundPoint((Double(x) + 0.5) * streetSpacing,
                    (Double(z) + 0.5) * streetSpacing)
    }

    /// Downtown grows denser toward the center of the same street-first grid:
    /// 4 core blocks (up to 9 buildings each), 12 middle-ring blocks (up to
    /// 4 each), and mostly open outer neighborhoods (up to 2 per selected block).
    /// The seed randomizes lots and developed districts while keeping streets
    /// free and replayable through the saved obstacle list.
    static func buildings(count: Int, seed: UInt64) -> [CityBuildingSite] {
        guard count > 0 else { return [] }
        let requested = min(120, count)
        var state = seed == 0 ? 0xA735_9D1C_002F_1869 : seed
        func random() -> Double {
            state = state &* 2_862_933_555_777_941_757 &+ 3_037_000_493
            return Double(state >> 11) / 9_007_199_254_740_992.0
        }
        func shuffled<T>(_ original: [T]) -> [T] {
            var result = original
            if result.count > 1 {
                for i in stride(from: result.count - 1, through: 1, by: -1) {
                    let j = Int(random() * Double(i + 1))
                    result.swapAt(i, j)
                }
            }
            return result
        }
        var downtown: [(Int, Int)] = []
        var middle: [(Int, Int)] = []
        var outer: [(Int, Int)] = []
        for z in -3...2 {
            for x in -3...2 {
                if (-1...0).contains(x) && (-1...0).contains(z) {
                    downtown.append((x,z))
                } else if (-2...1).contains(x) && (-2...1).contains(z) {
                    middle.append((x,z))
                } else {
                    outer.append((x,z))
                }
            }
        }

        let coreQuota = min(36, Int((Double(requested) * 0.50).rounded(.up)))
        let middleQuota = min(48, requested - coreQuota,
                              Int((Double(requested) * 0.38).rounded(.up)))
        let outerQuota = min(40, requested - coreQuota - middleQuota)

        // Interior lots are 12 units apart. The maximum building footprint
        // plus navigation collision clearance is smaller than that interval.
        let allLots: [(Double, Double)] = [
            (-12,-12), (0,-12), (12,-12),
            (-12,0), (0,0), (12,0),
            (-12,12), (0,12), (12,12)
        ]
        var placements: [CityBuildingSite] = []
        func allocate(_ districts: [(Int, Int)], quota: Int,
                      maxPerBlock: Int, zone: Int) {
            guard quota > 0 else { return }
            let blocks = shuffled(districts)
            let active = min(blocks.count, (quota + maxPerBlock - 1) / maxPerBlock)
            guard active > 0 else { return }
            for index in 0..<active {
                let block = blocks[index]
                let number = quota / active + (index < quota % active ? 1 : 0)
                let lots = shuffled(allLots)
                let center = blockCenter(x: block.0, z: block.1)
                for lot in 0..<number {
                    let offset = lots[lot]
                    let size: Double
                    switch zone {
                    case 0: size = 2.8 + random() * 0.9
                    case 1: size = 3.0 + random() * 0.9
                    default: size = 3.2 + random() * 0.7
                    }
                    let location = GroundPoint(center.x + offset.0,
                                               center.z + offset.1)
                    if isBuildable(location, radius: size * 0.9 + 2.7) {
                        placements.append(CityBuildingSite(
                            center: location, size: size,
                            variant: Int(random() * 1000),
                            blockX: block.0, blockZ: block.1))
                    }
                }
            }
        }
        allocate(downtown, quota: coreQuota, maxPerBlock: 9, zone: 0)
        allocate(middle, quota: middleQuota, maxPerBlock: 4, zone: 1)
        allocate(outer, quota: outerQuota, maxPerBlock: 2, zone: 2)
        return placements
    }
}

// Custom tank-game rules. These do not mutate the built-in difficulty presets.
struct SiegeRules: Codable, Equatable {
    var ammoCapacity: Int = 40
    var reloadSeconds: Double = 1.0
    var projectileLifetime: Double = 1.55
    var shieldDuration: Double = 5.0
    var shieldCooldown: Double = 11.0
    var startingLives: Int = 3
    var startingEnemies: Int = 2
    var extraEnemiesPerWave: Int = 1
    var maxEnemies: Int = 8
    var obstacleCount: Int = 80
    var enemySpeed: Double = 1.0
    var enemyReload: Double = 1.0
    var enemyAccuracy: Double = 1.0
    var huntersEnabled: Bool = true
    var saucersEnabled: Bool = true

    func validated() -> SiegeRules {
        var r = self
        r.ammoCapacity = min(200, max(1, ammoCapacity))
        r.reloadSeconds = min(6, max(0.2, reloadSeconds))
        r.projectileLifetime = min(5, max(0.5, projectileLifetime))
        r.shieldDuration = min(20, max(1, shieldDuration))
        r.shieldCooldown = min(45, max(0, shieldCooldown))
        r.startingLives = min(12, max(1, startingLives))
        r.startingEnemies = min(12, max(1, startingEnemies))
        r.extraEnemiesPerWave = min(4, max(0, extraEnemiesPerWave))
        r.maxEnemies = min(16, max(r.startingEnemies, maxEnemies))
        r.obstacleCount = min(120, max(0, obstacleCount))
        r.enemySpeed = min(2.5, max(0.25, enemySpeed))
        r.enemyReload = min(3, max(0.4, enemyReload))
        r.enemyAccuracy = min(3, max(0.25, enemyAccuracy))
        return r
    }

    func enemies(forWave wave: Int) -> Int {
        min(maxEnemies, startingEnemies + max(0, wave - 1) * extraEnemiesPerWave)
    }
}

struct SiegePreset: Codable, Identifiable {
    var id: String
    var name: String
    var rules: SiegeRules
}

// Pure Codable save types, independent of SpriteKit nodes and graphics.
struct SavedSiegeObstacle: Codable {
    var center: GroundPoint
    var size: Double
    var kind: String
}
struct SavedSiegeFoe: Codable {
    var center: GroundPoint
    var heading: Double
    var kind: String
    var reload: Double
    var phase: Double
    var hitPoints: Int
}
struct SavedSiegeShell: Codable {
    var center: GroundPoint
    var direction: GroundPoint
    var hostile: Bool
    var timeLeft: Double
    // Older save slots contain no projectile payload field.
    var payload: String? = nil
}
struct SavedSiegeSpark: Codable {
    var position: WorldPoint
    var velocity: WorldPoint
    var timeLeft: Double
    var maxLife: Double
}

struct SiegeSnapshot: Codable {
    var version: Int
    var displayMode: String
    var threatLevel: String
    var soundOn: Bool
    var activePresetID: String
    var customRules: SiegeRules?
    var score: Int
    var lives: Int
    var wave: Int
    var gameClock: Double
    var heading: Double
    var driveSpeed: Double
    var tankPosition: GroundPoint
    var shieldRemaining: Double
    var shieldCooldown: Double
    var invulnerability: Double
    var pendingWave: Double
    var cannon: CannonMagazine
    var shotTally: ShotTally
    var obstacles: [SavedSiegeObstacle]
    var enemies: [SavedSiegeFoe]
    var shells: [SavedSiegeShell]
    var sparks: [SavedSiegeSpark]
    // Optional for backwards compatibility with v0.8 game saves.
    var secondsUntilSaucerPatrol: Double? = nil
    // Backwards compatible with snapshots saved before level-intro screens.
    var awaitingLevelStart: Bool? = nil
    // Optional additive fields retain compatibility with all v1 save slots.
    var waveApproach: Double? = nil
    var waveOrigin: GroundPoint? = nil
    var waveElapsed: Double? = nil
    var dronesPending: Int? = nil
    var fightersPending: Int? = nil
    var chaffCharges: Int? = nil
    var chaffCooldown: Double? = nil
    var chaffActive: Double? = nil
}

struct SiegeSaveSlot: Codable, Identifiable {
    var id: String
    var name: String
    var savedAt: Date
    var snapshot: SiegeSnapshot
}

enum SiegeGameStore {
    private static let presetsKey = "vectorSiege.customPresets.v1"
    private static let savesKey = "vectorSiege.savedGames.v1"

    private static func load<T: Decodable>(_ key: String) -> [T] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let values = try? JSONDecoder().decode([T].self, from: data) else { return [] }
        return values
    }

    private static func persist<T: Encodable>(_ values: [T], at key: String) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func presets() -> [SiegePreset] { load(presetsKey) }
    static func preset(id: String) -> SiegePreset? {
        presets().first(where: { $0.id == id })
    }
    static func savePreset(_ preset: SiegePreset) {
        var values = presets()
        let clean = SiegePreset(id: preset.id, name: preset.name,
                                rules: preset.rules.validated())
        if let i = values.firstIndex(where: { $0.id == preset.id }) {
            values[i] = clean
        } else {
            values.insert(clean, at: 0)
        }
        persist(values, at: presetsKey)
    }
    static func deletePreset(id: String) {
        persist(presets().filter { $0.id != id }, at: presetsKey)
    }

    static func saves() -> [SiegeSaveSlot] {
        let values: [SiegeSaveSlot] = load(savesKey)
        return values.sorted { $0.savedAt > $1.savedAt }
    }
    @discardableResult
    static func saveGame(_ snapshot: SiegeSnapshot) -> SiegeSaveSlot {
        let presetName = snapshot.customRules == nil ? snapshot.threatLevel : "Custom"
        let slot = SiegeSaveSlot(
            id: UUID().uuidString,
            name: "Wave \(snapshot.wave) · \(presetName) · \(snapshot.score) points",
            savedAt: Date(), snapshot: snapshot)
        persist(Array(([slot] + saves()).prefix(12)), at: savesKey)
        return slot
    }
    static func deleteGame(id: String) {
        persist(saves().filter { $0.id != id }, at: savesKey)
    }
}


/// Guarantees one patrol arrival per 120 seconds of active, unpaused play.
/// Codable so the clock survives Save Game / Resume without restarting.
struct SaucerPatrolClock: Codable {
    static let interval = 58.0
    private(set) var secondsUntilArrival = 15.0

    mutating func advance(by elapsed: Double) -> Bool {
        guard elapsed > 0 else { return false }
        secondsUntilArrival -= elapsed
        // Tolerate sub-microsecond floating-point error at exactly 120s.
        if secondsUntilArrival <= 0.000001 {
            secondsUntilArrival = min(Self.interval, secondsUntilArrival + Self.interval)
            return true
        }
        return false
    }

    mutating func restore(secondsRemaining: Double?) {
        guard let value = secondsRemaining, value.isFinite else {
            secondsUntilArrival = Self.interval
            return
        }
        secondsUntilArrival = max(0.001, min(Self.interval, value))
    }
}


/// Radar/proximity units are world units; the standard tank is about 6 long.
enum TankProximity {
    static let tankLength = 6.0
    static let alertRadius = tankLength * 5.0

    static func isClose(_ distance: Double) -> Bool {
        distance.isFinite && distance <= alertRadius && distance >= 0
    }

    static func repeatInterval(for distance: Double) -> Double {
        if distance <= tankLength { return 0.30 }
        if distance <= tankLength * 2 { return 0.65 }
        return 1.4
    }
}

/// Canonical footprint of the geometry drawn by the scene. The same shape
/// is used for tank movement, AI navigation, line-of-fire tests and shells.
/// All structures are axis-aligned; pyramid cross-sections taper with height.
enum ObstacleCollision {
    enum Kind { case block, pyramid, tower, building, monolith }

    struct Body {
        var center: GroundPoint
        var halfX: Double
        var halfZ: Double
        var height: Double
        var tapered: Bool
    }

    static func body(center: GroundPoint, size: Double, kind: Kind) -> Body {
        switch kind {
        case .block:
            return Body(center: center, halfX: size, halfZ: size,
                        height: size * 1.35, tapered: false)
        case .pyramid:
            return Body(center: center, halfX: size, halfZ: size,
                        height: size * 1.28, tapered: true)
        case .tower:
            return Body(center: center, halfX: size * 0.55,
                        halfZ: size * 0.62, height: size * 4.1,
                        tapered: false)
        case .building:
            return Body(center: center, halfX: size * 1.05,
                        halfZ: size * 0.85, height: size * 2.2,
                        tapered: false)
        case .monolith:
            return Body(center: center, halfX: size * 0.45,
                        halfZ: size * 0.42, height: size * 6,
                        tapered: false)
        }
    }

    /// Horizontal cross-section at a real shell height. Above a structure's
    /// roof there is no collision, while pyramids get narrower toward the tip.
    static func extents(_ body: Body, height: Double,
                        margin: Double = 0) -> (halfX: Double, halfZ: Double)? {
        guard height >= 0 && height <= body.height else { return nil }
        let taper = body.tapered ? max(0, 1 - height / body.height) : 1
        return (body.halfX * taper + max(0, margin),
                body.halfZ * taper + max(0, margin))
    }

    static func contains(_ location: GroundPoint, body: Body,
                         height: Double = 0, margin: Double = 0) -> Bool {
        guard let e = extents(body, height: height, margin: margin) else {
            return false
        }
        let delta = location - body.center
        return abs(delta.x) <= e.halfX && abs(delta.z) <= e.halfZ
    }

    /// Swept point/round test against the horizontal rectangular cross-section
    /// of a structure. Liang-Barsky slab clipping returns earliest impact t
    /// in [0,1], including starting within solid geometry and grazing edges.
    static func firstImpact(
        from start: GroundPoint, to end: GroundPoint,
        body: Body, height: Double, radius: Double = 0
    ) -> Double? {
        guard let e = extents(body, height: height, margin: radius) else {
            return nil
        }
        let a = start - body.center
        let b = end - body.center
        let dx = b.x - a.x
        let dz = b.z - a.z
        var entering = 0.0
        var leaving = 1.0
        for (origin, direction, half) in [(a.x, dx, e.halfX),
                                          (a.z, dz, e.halfZ)] {
            if abs(direction) < 1e-10 {
                if abs(origin) > half { return nil }
            } else {
                let first = (-half - origin) / direction
                let second = (half - origin) / direction
                entering = max(entering, min(first, second))
                leaving = min(leaving, max(first, second))
                if entering > leaving { return nil }
            }
        }
        return entering >= 0 && entering <= 1 ? entering : nil
    }

    /// Swept circular target collision; avoids shells tunneling between frames.
    static func firstCircleImpact(
        from start: GroundPoint, to end: GroundPoint,
        center: GroundPoint, radius: Double
    ) -> Double? {
        let a = start - center
        let d = end - start
        let aa = d.x*d.x + d.z*d.z
        let cc = a.x*a.x + a.z*a.z - radius*radius
        if cc <= 0 { return 0 }
        guard aa > 1e-12 else { return nil }
        let bb = 2*(a.x*d.x + a.z*d.z)
        let discriminant = bb*bb - 4*aa*cc
        guard discriminant >= 0 else { return nil }
        let t = (-bb - sqrt(discriminant)) / (2*aa)
        return t >= 0 && t <= 1 ? t : nil
    }
}

/// AI navigation accepts exact building footprints. A radius-only fallback
/// preserves compatibility with existing generic navigation smoke tests.
struct NavigationObstacle {
    var center: GroundPoint
    var radius: Double
    var body: ObstacleCollision.Body?

    init(center: GroundPoint, radius: Double) {
        self.center = center
        self.radius = radius
        self.body = nil
    }
    init(body: ObstacleCollision.Body) {
        self.center = body.center
        self.radius = max(body.halfX, body.halfZ)
        self.body = body
    }
}

/// Low-cost grid search for a clear position to fire from, not merely a
/// route to the player's current position. Designed for the small arcade map.
/// This runs on a staggered refresh schedule, not every frame.
enum EnemyNavigation {
    static let gridSpacing = 9.0
    static let gridMin = -180.0
    static let gridMax = 180.0
    static let gridCount = 41
    static let enemyRadius = 2.7
    static let navigationMargin = 0.9

    static func segmentDistance(_ center: GroundPoint,
                                from start: GroundPoint, to end: GroundPoint) -> Double {
        let vector = end - start
        let length2 = vector.x * vector.x + vector.z * vector.z
        guard length2 > 0.000001 else { return center.distance(to: start) }
        let diff = center - start
        let t = max(0, min(1, (diff.x * vector.x + diff.z * vector.z) / length2))
        return center.distance(to: start + vector * t)
    }

    static func clearSegment(_ start: GroundPoint, _ end: GroundPoint,
                             obstacles: [NavigationObstacle],
                             clearance: Double = 0,
                             height: Double = 0) -> Bool {
        obstacles.allSatisfy {
            if let body = $0.body {
                return ObstacleCollision.firstImpact(
                    from: start, to: end, body: body,
                    height: height, radius: clearance) == nil
            }
            return segmentDistance($0.center, from: start, to: end)
                > $0.radius + clearance
        }
    }

    static func isWalkable(_ location: GroundPoint,
                           obstacles: [NavigationObstacle],
                           otherTanks: [GroundPoint]) -> Bool {
        guard abs(location.x) <= gridMax - enemyRadius,
              abs(location.z) <= gridMax - enemyRadius else { return false }
        return obstacles.allSatisfy {
            if let body = $0.body {
                return !ObstacleCollision.contains(
                    location, body: body,
                    margin: enemyRadius + navigationMargin)
            }
            return $0.center.distance(to: location)
                > $0.radius + enemyRadius + navigationMargin
        } && otherTanks.allSatisfy {
            $0.distance(to: location) >= EnemySpawnLayout.movementSpacing + 1.0
        }
    }

    /// Find an intermediate point on a collision-free path to a firing lane.
    /// Prefer a spot 14–78 units from the player with an unobstructed shot.
    /// Returns nil when none can be reached, so the caller may choose local
    /// obstacle-avoidance fallback without ever teleporting the enemy.
    static func nextWaypoint(
        from start: GroundPoint, player: GroundPoint,
        obstacles: [NavigationObstacle], shotBlockers: [NavigationObstacle],
        otherTanks: [GroundPoint], desiredStandOff: Double = 18,
        terrainAware: Bool = false
    ) -> GroundPoint? {
        let count = gridCount
        func index(_ point: GroundPoint) -> Int {
            let col = max(0, min(count - 1, Int(((point.x - gridMin) / gridSpacing).rounded())))
            let row = max(0, min(count - 1, Int(((point.z - gridMin) / gridSpacing).rounded())))
            return row * count + col
        }
        func point(_ index: Int) -> GroundPoint {
            GroundPoint(gridMin + Double(index % count) * gridSpacing,
                        gridMin + Double(index / count) * gridSpacing)
        }
        let origin = index(start)
        let offsets = [(-1,0),(1,0),(0,-1),(0,1),
                       (-1,-1),(-1,1),(1,-1),(1,1)]
        var predecessors = Array(repeating: -1, count: count * count)
        var visited = Array(repeating: false, count: count * count)
        var queue: [Int] = [origin]
        var front = 0
        visited[origin] = true

        var found: Int?
        while front < queue.count {
            let currentIndex = queue[front]
            front += 1
            let candidate = currentIndex == origin ? start : point(currentIndex)
            let distance = candidate.distance(to: player)
            let clearShot = distance >= max(10, desiredStandOff - 5) &&
                            distance <= 78 &&
                            clearSegment(candidate, player, obstacles: shotBlockers,
                                         height: 1.5) &&
                            (!terrainAware ||
                             LandscapeTopology.clearFiringLine(
                                 from: candidate, to: player))
            if clearShot {
                found = currentIndex
                break
            }
            let col = currentIndex % count
            let row = currentIndex / count
            for (dx, dz) in offsets {
                let c = col + dx
                let r = row + dz
                if c < 0 || r < 0 || c >= count || r >= count { continue }
                let neighbor = r * count + c
                if visited[neighbor] { continue }
                let next = point(neighbor)
                if !isWalkable(next, obstacles: obstacles,
                               otherTanks: otherTanks) { continue }
                let here = currentIndex == origin ? start : candidate
                if !clearSegment(here, next, obstacles: obstacles,
                                 clearance: enemyRadius + navigationMargin) { continue }
                // A diagonal grid hop may cut a corner occupied by another tank.
                if otherTanks.contains(where: {
                    segmentDistance($0, from: here, to: next)
                        < EnemySpawnLayout.movementSpacing
                }) { continue }
                visited[neighbor] = true
                predecessors[neighbor] = currentIndex
                queue.append(neighbor)
            }
        }
        guard var cursor = found else { return nil }
        var route: [GroundPoint] = []
        while cursor != origin {
            route.append(point(cursor))
            cursor = predecessors[cursor]
            if cursor < 0 { return nil }
        }
        route.reverse()
        // Skip unnecessary grid corners when the direct route is traversable.
        for waypoint in route.reversed() {
            if clearSegment(start, waypoint, obstacles: obstacles,
                            clearance: enemyRadius + navigationMargin) &&
                otherTanks.allSatisfy({
                    segmentDistance($0, from: start, to: waypoint)
                        >= EnemySpawnLayout.movementSpacing
                }) {
                return waypoint
            }
        }
        return route.first
    }
}
