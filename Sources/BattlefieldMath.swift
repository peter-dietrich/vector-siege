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

struct CameraProjection {
    var position: GroundPoint
    var yaw: Double
    var viewportWidth: Double
    var viewportHeight: Double
    var eyeHeight = 1.5
    var cameraLateral: Double = 0
    var pitchPoints: Double = 0

    var focal: Double { min(viewportWidth * 0.89, viewportHeight * 1.45) }
    var horizon: Double { viewportHeight * 0.455 + pitchPoints }

    func local(_ world: WorldPoint) -> (right: Double, up: Double, forward: Double) {
        let dx = world.x - position.x
        let dz = world.z - position.z
        return (dx * cos(yaw) - dz * sin(yaw) - cameraLateral, world.y - eyeHeight,
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
        existing: [GroundPoint], isOpen: (GroundPoint) -> Bool
    ) -> GroundPoint? {
        let sector = heading + 2 * Double.pi * Double(index) / Double(max(1, count))
        let angleOffsets: [Double] = [0, 0.18, -0.18, 0.36, -0.36,
                                      0.58, -0.58, 0.83, -0.83]
        let radii: [Double] = [76, 92, 110, 62, 128, 48, 140]
        func acceptable(_ point: GroundPoint) -> Bool {
            point.distance(to: player) >= 28 &&
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
    var obstacleCount: Int = 23
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
        r.obstacleCount = min(55, max(0, obstacleCount))
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
    static let interval = 120.0
    private(set) var secondsUntilArrival = interval

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
    static let alertRadius = tankLength * 2.0

    static func isClose(_ distance: Double) -> Bool {
        distance.isFinite && distance <= alertRadius && distance >= 0
    }

    static func repeatInterval(for distance: Double) -> Double {
        distance <= tankLength ? 0.30 : 0.65
    }
}
