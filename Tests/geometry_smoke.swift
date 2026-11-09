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

        var shakenCamera = c
        shakenCamera.cameraLateral = 0.02
        shakenCamera.pitchPoints = -2.5
        precondition(shakenCamera.horizon != c.horizon)
        precondition(shakenCamera.local(WorldPoint(0, 0, 20)).right !=
                     c.local(WorldPoint(0, 0, 20)).right)
        print("Perspective, steering, ammo, suspension and camera motion checks passed.")
    }
}