import Foundation

struct GroundPoint {
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

struct WorldPoint {
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
struct CannonMagazine {
    static let capacity = 40
    static let minimumReload = 1.0
    static let maximumReload = 1.0

    private(set) var roundsRemaining = capacity
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
        let sampled = reloadDuration ?? Double.random(in: Self.minimumReload...Self.maximumReload)
        lastReloadDuration = min(Self.maximumReload, max(Self.minimumReload, sampled))
        reloadRemaining = roundsRemaining > 0 ? lastReloadDuration : 0
        return true
    }

    mutating func advance(by dt: Double) {
        reloadRemaining = max(0, reloadRemaining - max(0, dt))
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
        pitchVelocity -= delta * 0.11
        pitchVelocity += (-54 * pitch - 10.5 * pitchVelocity) * step
        pitch = min(0.10, max(-0.10, pitch + pitchVelocity * step))
    }
}
