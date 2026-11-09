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
        precondition(CannonMagazine.minimumReload == 3 && CannonMagazine.maximumReload == 5)
        precondition(cannon.canFire && cannon.roundsRemaining == 40)
        precondition(cannon.fire(reloadDuration: 3))
        precondition(cannon.roundsRemaining == 39 && !cannon.canFire)
        precondition(cannon.statusText == "RELOAD 3.0s")
        precondition(!cannon.fire(reloadDuration: 4))
        cannon.advance(by: 2.5)
        precondition(!cannon.canFire && cannon.reloadRemaining > 0)
        cannon.advance(by: 0.5)
        precondition(cannon.canFire && cannon.statusText == "READY")
        precondition(cannon.fire(reloadDuration: 5))
        precondition(cannon.reloadRemaining == 5 && cannon.roundsRemaining == 38)
        cannon.advance(by: 5)
        for _ in 0..<38 {
            precondition(cannon.fire(reloadDuration: 4))
            cannon.advance(by: 4)
        }
        precondition(cannon.isEmpty && cannon.roundsRemaining == 0)
        precondition(cannon.statusText == "EMPTY" && !cannon.canFire)
        precondition(!cannon.fire(reloadDuration: 3))
        cannon = CannonMagazine()
        precondition(cannon.canFire && cannon.roundsRemaining == 40)
        print("Perspective, steering, 40 rounds and randomized 3–5s reload checks passed.")
    }
}