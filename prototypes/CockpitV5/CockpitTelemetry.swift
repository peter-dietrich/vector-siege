// v5.0 cockpit-only transfer model. No gameplay authority and no simulated
// vehicle systems added by the cockpit. Foundation-only for testability.
import Foundation

struct CockpitV5Snapshot {
    struct Point {
        let x: Double
        let z: Double
    }

    enum ContactKind: String {
        case tank, hunter, apc, artillery, drone, fighter, saucer
    }

    struct Contact {
        let id: Int
        let kind: ContactKind
        let position: Point
        let headingRadians: Double
        let visible: Bool
        let hitPoints: Int
        let isPrimaryTarget: Bool
    }

    struct Target {
        let contactID: Int?
        let rangeWorldUnits: Double
        let bearingOffsetDegrees: Double
        let clearFiringLine: Bool
        let isGroundVehicle: Bool
    }

    struct Projectile {
        let position: Point
        let hostile: Bool
        let payload: String
    }

    // Read-only model data from BattlefieldScene. Everything remains owned
    // by the game simulation; no gameplay writes back through a display.
    let headingRadians: Double
    let speedWorldUnitsPerSecond: Double
    let playerPosition: Point
    let terrainElevationWorldUnits: Double
    let sector: String

    let wave: Int
    let lives: Int
    let score: Int
    let bestScore: Int
    let difficultyLabel: String
    let shotsFired: Int
    let shotsHit: Int

    let roundsRemaining: Int
    let magazineCapacity: Int
    let reloadRemainingSeconds: Double
    let reloadPeriodSeconds: Double

    let shieldRemainingSeconds: Double
    let shieldCooldownSeconds: Double
    let chaffCharges: Int

    let target: Target?
    let contacts: [Contact]
    let projectiles: [Projectile]

    var accuracyPercent: Double {
        guard shotsFired > 0 else { return 0 }
        return 100 * Double(shotsHit) / Double(shotsFired)
    }
    var reloadFraction: Double {
        guard reloadPeriodSeconds > 0 else { return 1 }
        return max(0, min(1, 1 - reloadRemainingSeconds / reloadPeriodSeconds))
    }
    var ammunitionFraction: Double {
        guard magazineCapacity > 0 else { return 0 }
        return max(0, min(1, Double(roundsRemaining) / Double(magazineCapacity)))
    }
    var headingDegrees: Double {
        let raw = headingRadians * 180 / .pi
        return (raw.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
    }

    /// A display frame with absent data must show "—" or "UNAVAILABLE",
    /// never manufactured fuel, armor %, engine temperature or crew health.
    func validate() -> Bool {
        wave >= 1 && lives >= 0 && score >= 0 &&
        magazineCapacity > 0 && roundsRemaining >= 0 &&
        roundsRemaining <= magazineCapacity &&
        shotsFired >= 0 && shotsHit >= 0 &&
        shieldRemainingSeconds >= 0 && shieldCooldownSeconds >= 0 &&
        chaffCharges >= 0 && headingRadians.isFinite &&
        playerPosition.x.isFinite && playerPosition.z.isFinite &&
        terrainElevationWorldUnits.isFinite
    }
}
