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

    var focal: Double { min(viewportWidth * 0.89, viewportHeight * 1.45) }
    var horizon: Double { viewportHeight * 0.455 }

    func local(_ world: WorldPoint) -> (right: Double, up: Double, forward: Double) {
        let dx = world.x - position.x
        let dz = world.z - position.z
        return (dx * cos(yaw) - dz * sin(yaw), world.y - eyeHeight,
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