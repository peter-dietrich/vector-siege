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


/// v5.4: stable, presentation-only values shared by the four cockpit screens.
/// No mutable gameplay state and no invented armor/fuel/engine readings.
/// The adapter can be tested without SpriteKit or a running game scene.
extension CockpitV5Snapshot {
    struct ScreenReadouts {
        let fireControl: [String: String]
        let tacticalMap: [String: String]
        let rearOptics: [String: String]
        let vehicleSystems: [String: String]
        let lowerConsole: [String: String]
    }

    var screenReadouts: ScreenReadouts {
        func number(_ value: Double, places: Int = 0) -> String {
            guard value.isFinite else { return "—" }
            return String(format: "%.*f", places, value)
        }
        let remaining = max(0, roundsRemaining)
        let ammo = "\(remaining) / \(magazineCapacity)"
        let contactCounts = contacts.filter(\.visible)
        let groundCount = contactCounts.filter {
            $0.kind != .drone && $0.kind != .fighter && $0.kind != .saucer
        }.count
        let airCount = contactCounts.count - groundCount
        let hostileShots = projectiles.filter(\.hostile).count
        let targetRange = target.map { number($0.rangeWorldUnits, places: 1) } ?? "—"
        let targetBearing = target.map { number($0.bearingOffsetDegrees, places: 1) } ?? "—"
        let lineOfFire = target.map { $0.clearFiringLine ? "CLEAR" : "BLOCKED" } ?? "NO TARGET"
        let shieldStatus: String
        if shieldRemainingSeconds > 0 {
            shieldStatus = "ACTIVE \(number(shieldRemainingSeconds, places: 1))s"
        } else if shieldCooldownSeconds > 0 {
            shieldStatus = "COOLDOWN \(number(shieldCooldownSeconds, places: 1))s"
        } else {
            shieldStatus = "READY"
        }
        return ScreenReadouts(
            fireControl: [
                "heading_deg": number(headingDegrees, places: 1),
                "speed": number(speedWorldUnitsPerSecond, places: 1),
                "target_distance": targetRange,
                "target_bearing": targetBearing,
                "target_cover": lineOfFire,
                "ammo_remaining": String(remaining),
                "ammo_capacity": String(magazineCapacity),
                "reload_fraction": number(reloadFraction, places: 2)
            ],
            tacticalMap: [
                "player_position": "\(number(playerPosition.x, places: 1)), \(number(playerPosition.z, places: 1))",
                "player_heading": number(headingDegrees, places: 1),
                "ground_contacts": String(groundCount),
                "air_contacts": String(airCount),
                "selected_target": target?.contactID.map(String.init) ?? "—",
                "hostile_projectiles": String(hostileShots),
                // The corresponding renderers need actual world geometry, not a placeholder number.
                "building_footprints": "UNAVAILABLE",
                "terrain_profile": "UNAVAILABLE"
            ],
            rearOptics: [
                "rear_bearing": number((headingDegrees + 180).truncatingRemainder(dividingBy: 360), places: 1),
                "rear_camera_texture": "UNAVAILABLE",
                "threat_brackets": "UNAVAILABLE"
            ],
            vehicleSystems: [
                "lives": String(lives),
                "score": String(score),
                "best_score": String(bestScore),
                "wave": String(wave),
                "difficulty": difficultyLabel,
                "shield_remaining": number(shieldRemainingSeconds, places: 1),
                "shield_cooldown": number(shieldCooldownSeconds, places: 1),
                "shield_status": shieldStatus,
                "chaff_charges": String(chaffCharges),
                "ammo_remaining": String(remaining),
                "ammo_capacity": String(magazineCapacity)
            ],
            lowerConsole: [
                "terrain_elevation": number(terrainElevationWorldUnits, places: 1),
                "heading_deg": number(headingDegrees, places: 1),
                "sector": sector,
                "wave": String(wave),
                "accuracy_percent": number(accuracyPercent, places: 1),
                "hostile_projectiles": String(hostileShots),
                "ammunition": ammo
            ]
        )
    }
}
