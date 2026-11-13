import AppKit
import SpriteKit

/// v5.3 approved artwork, v5.4 live battlefield connection.
/// Pure presentation: game rules, targeting and saved games remain authoritative
/// in BattlefieldScene. The existing Modern lower navigation deck is retained.
final class CockpitV53LiveRenderer {
    static let requiredFiles = [
        "cockpit_fire_bezel", "fire_screen_wells", "tank_technical_art",
        "fire_glass_overlay", "cockpit_map_bezel", "map_terrain_underlay",
        "map_glass_overlay", "cockpit_optics_bezel", "optics_sensor_underlay",
        "optics_glass_overlay", "cockpit_systems_bezel",
        "systems_screen_underlay", "systems_glass_overlay"
    ]

    static func assetDirectory() -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("CockpitV5"),
            Bundle.main.resourceURL?.appendingPathComponent("Resources/CockpitV5"),
            // Xcode-run development builds can use repo-original images.
            URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Resources/CockpitV5")
        ].compactMap { $0 }
        return candidates.first { base in
            requiredFiles.allSatisfy {
                fileManager.fileExists(atPath: base.appendingPathComponent($0 + ".png").path)
            }
        }
    }

    private weak var scene: SKScene?
    private let root = SKNode()
    private let blanking = SKShapeNode()
    private let mapMarkers = SKNode()
    private let mapPlayer = SKShapeNode()
    private let mapSweep = SKShapeNode()
    private let reloadBar = SKShapeNode()
    private let ammoBar = SKShapeNode()
    private let shieldBar = SKShapeNode()
    private var labels: [String: SKLabelNode] = [:]
    private let pale = NSColor(calibratedRed: 0.88, green: 0.92, blue: 0.89, alpha: 1)
    private let mint = NSColor(calibratedRed: 0.43, green: 0.95, blue: 0.72, alpha: 1)
    private let amber = NSColor(calibratedRed: 1, green: 0.68, blue: 0.28, alpha: 1)
    private let muted = NSColor(calibratedRed: 0.52, green: 0.66, blue: 0.64, alpha: 1)
    private let cyan = NSColor(calibratedRed: 0.51, green: 0.86, blue: 0.87, alpha: 1)
    private let images: URL
    private let mapCenter = CGPoint(x: 395 + 179, y: 900 - 78 - 263 + 125)
    private let opticsBase = CGPoint(x: 766, y: 900 - 78 - 263)

    init?(scene: SKScene) {
        guard let images = Self.assetDirectory() else { return nil }
        self.images = images
        self.scene = scene
        blanking.zPosition = 35
        blanking.fillColor = NSColor(calibratedRed: 0.01, green: 0.026, blue: 0.03, alpha: 1)
        blanking.strokeColor = .clear
        scene.addChild(blanking)
        root.zPosition = 36
        scene.addChild(root)
        assemble()
    }

    private func sprite(_ file: String, frame: CGRect, z: CGFloat, parent: SKNode? = nil) {
        guard let picture = NSImage(contentsOf: images.appendingPathComponent(file + ".png")) else { return }
        let node = SKSpriteNode(texture: SKTexture(image: picture))
        node.position = CGPoint(x: frame.midX, y: frame.midY)
        node.size = frame.size
        node.zPosition = z
        (parent ?? root).addChild(node)
    }

    private func text(_ key: String, _ value: String, x: CGFloat, y: CGFloat,
                      size: CGFloat, color: NSColor? = nil,
                      align: SKLabelHorizontalAlignmentMode = .left) {
        let node = SKLabelNode(fontNamed: "Menlo-Bold")
        node.text = value
        node.position = CGPoint(x: x, y: y)
        node.fontSize = size
        node.fontColor = color ?? pale
        node.horizontalAlignmentMode = align
        node.verticalAlignmentMode = .center
        node.zPosition = 12
        root.addChild(node)
        labels[key] = node
    }

    private func set(_ name: String, _ value: String) {
        labels[name]?.text = value
    }

    private func rect(_ x: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: x, y: 900 - top - height, width: width, height: height)
    }

    private func bar(_ shape: SKShapeNode, frame: CGRect, color: NSColor) {
        shape.path = CGPath(roundedRect: frame, cornerWidth: 2, cornerHeight: 2, transform: nil)
        shape.fillColor = color
        shape.strokeColor = .clear
        shape.zPosition = 13
        root.addChild(shape)
    }

    private func assemble() {
        // Artist-supplied 2x bitmap layers: each original stays separately editable.
        // All numbers, target marks and contacts remain native SpriteKit nodes.
        sprite("fire_screen_wells", frame: rect(40, 94, 326, 231), z: 2)
        sprite("tank_technical_art", frame: rect(50, 159, 176, 110), z: 3)
        sprite("fire_glass_overlay", frame: rect(40, 94, 326, 231), z: 5)
        sprite("cockpit_fire_bezel", frame: rect(24, 78, 358, 263), z: 20)

        sprite("map_terrain_underlay", frame: rect(411, 94, 326, 231), z: 2)
        sprite("map_glass_overlay", frame: rect(411, 94, 326, 231), z: 5)
        sprite("cockpit_map_bezel", frame: rect(395, 78, 358, 263), z: 20)

        // The v5.3 optics sensor underlay is a fallback only. During gameplay
        // the REAL rear-facing battlefield camera overlays it at z=4.
        sprite("optics_sensor_underlay", frame: rect(782, 94, 326, 231), z: 2)
        sprite("optics_glass_overlay", frame: rect(782, 94, 326, 231), z: 5)
        sprite("cockpit_optics_bezel", frame: rect(766, 78, 358, 263), z: 20)

        sprite("systems_screen_underlay", frame: rect(1153, 94, 407, 231), z: 2)
        sprite("tank_technical_art", frame: rect(1171, 163, 178, 112), z: 3)
        sprite("systems_glass_overlay", frame: rect(1153, 94, 407, 231), z: 5)
        sprite("cockpit_systems_bezel", frame: rect(1137, 78, 439, 263), z: 20)

        text("fireTitle", "FIRE CONTROL", x: 55, y: 900-78-263+222, size: 13)
        text("fireSubtitle", "MAIN GUN / TRACKING", x: 218, y: 900-78-263+222, size: 8, color: muted)
        text("fireTrack", "SENSOR / NO CONTACT", x: 55, y: 900-78-263+188, size: 8, color: mint)
        text("fireHeadingLabel", "HEADING", x: 248, y: 900-78-263+194, size: 8, color: muted)
        text("fireHeading", "000°", x: 248, y: 900-78-263+172, size: 18, color: cyan)
        text("fireSpeedLabel", "SPEED", x: 248, y: 900-78-263+153, size: 8, color: muted)
        text("fireSpeed", "0.0", x: 248, y: 900-78-263+134, size: 14)
        text("fireRange", "RNG ----", x: 248, y: 900-78-263+110, size: 9, color: amber)
        text("fireBearing", "BRG ----", x: 248, y: 900-78-263+95, size: 8.5)
        text("fireAim", "AIM ----", x: 248, y: 900-78-263+81, size: 8.5)
        text("fireWeaponLabel", "WEAPON STATUS", x: 70, y: 900-78-263+49, size: 8, color: muted)
        text("fireWeapon", "READY", x: 70, y: 900-78-263+33, size: 10, color: mint)
        text("fireAmmoLabel", "MAGAZINE", x: 243, y: 900-78-263+48, size: 8, color: amber)
        text("fireAmmo", "40 / 40", x: 243, y: 900-78-263+30, size: 10)
        bar(reloadBar, frame: CGRect(x: 312, y: 900-78-263+29, width: 38, height: 4), color: amber)

        let mapX: CGFloat = 395
        let mapY: CGFloat = 900-78-263
        text("mapTitle", "BATTLESPACE", x: mapX+31, y: mapY+222, size: 13)
        text("mapSubtitle", "TACTICAL / LIVE", x: mapX+207, y: mapY+222, size: 8, color: muted)
        text("mapContacts", "HOSTILE 00 / AIR 00", x: mapX+33, y: mapY+36, size: 9, color: mint)
        text("mapMode", "HDG UP / 165", x: mapX+214, y: mapY+36, size: 8, color: muted)
        text("mapTarget", "NO TRACK", x: mapX+33, y: mapY+55, size: 8, color: amber)
        mapMarkers.zPosition = 8
        root.addChild(mapMarkers)
        let radarShape = CGMutablePath()
        radarShape.move(to: .zero)
        radarShape.addLine(to: CGPoint(x: 0, y: 83))
        mapSweep.path = radarShape
        mapSweep.strokeColor = mint.withAlphaComponent(0.45)
        mapSweep.lineWidth = 1
        mapSweep.position = mapCenter
        mapSweep.zPosition = 7
        root.addChild(mapSweep)
        let markerPath = CGMutablePath()
        markerPath.move(to: CGPoint(x: 0, y: 8))
        markerPath.addLine(to: CGPoint(x: 5, y: -5))
        markerPath.addLine(to: CGPoint(x: -5, y: -5))
        markerPath.closeSubpath()
        mapPlayer.path = markerPath
        mapPlayer.position = mapCenter
        mapPlayer.fillColor = mint
        mapPlayer.strokeColor = .black
        mapPlayer.zPosition = 10
        root.addChild(mapPlayer)

        let rearX: CGFloat = 766
        let rearY: CGFloat = 900-78-263
        text("opticsTitle", "REAR OPTICS", x: rearX+31, y: rearY+223, size: 12)
        text("opticsSubtitle", "EO / LIVE REAR CAMERA", x: rearX+175, y: rearY+223, size: 8, color: mint)
        text("opticsMode", "REAR / 1.0X", x: rearX+33, y: rearY+40, size: 9, color: mint)
        text("opticsBearing", "AZ 180°", x: rearX+178, y: rearY+40, size: 9)
        text("opticsThreat", "NO TRACK", x: rearX+254, y: rearY+40, size: 8, color: amber)

        let systemsX: CGFloat = 1137
        let systemsY: CGFloat = 900-78-263
        text("systemsTitle", "VEHICLE SYSTEMS", x: systemsX+31, y: systemsY+223, size: 12)
        text("systemsSubtitle", "BATTLE STATUS / LIVE", x: systemsX+250, y: systemsY+223, size: 7.5, color: muted)
        text("scoreCaption", "SCORE", x: systemsX+30, y: systemsY+191, size: 8, color: muted)
        text("score", "000000", x: systemsX+30, y: systemsY+168, size: 19)
        text("bestCaption", "BEST", x: systemsX+195, y: systemsY+191, size: 8, color: muted)
        text("best", "000000", x: systemsX+195, y: systemsY+171, size: 13, color: mint)
        text("wave", "WAVE 01", x: systemsX+30, y: systemsY+147, size: 8.5)
        text("lives", "LIVES 03", x: systemsX+113, y: systemsY+147, size: 8.5, color: mint)
        text("difficulty", "VETERAN", x: systemsX+231, y: systemsY+147, size: 8, color: amber)
        text("mainGun", "MAIN GUN", x: systemsX+232, y: systemsY+121, size: 8, color: muted)
        text("ammo", "40 / 40", x: systemsX+232, y: systemsY+103, size: 13)
        bar(ammoBar, frame: CGRect(x: systemsX+232, y: systemsY+91, width: 159, height: 5), color: mint)
        text("shieldCaption", "SHIELD", x: systemsX+232, y: systemsY+75, size: 8, color: muted)
        text("shield", "READY", x: systemsX+306, y: systemsY+75, size: 8, color: mint)
        bar(shieldBar, frame: CGRect(x: systemsX+232, y: systemsY+61, width: 159, height: 5), color: amber)
        text("chaff", "CHAFF 02", x: systemsX+31, y: systemsY+38, size: 9, color: mint)
        text("reload", "RELOAD READY", x: systemsX+162, y: systemsY+38, size: 9)
    }

    private func updateBar(_ shape: SKShapeNode, x: CGFloat, y: CGFloat,
                           full: CGFloat, fraction: Double) {
        let width = full * CGFloat(max(0, min(1, fraction)))
        shape.path = CGPath(roundedRect: CGRect(x: x, y: y, width: max(0.01, width), height: 5),
                            cornerWidth: 2, cornerHeight: 2, transform: nil)
    }

    func update(_ snapshot: CockpitV5Snapshot, clock: Double) {
        guard snapshot.validate() else { return }
        set("fireHeading", String(format: "%03.0f°", snapshot.headingDegrees))
        set("fireSpeed", String(format: "%04.1f", snapshot.speedWorldUnitsPerSecond))
        let t = snapshot.target
        set("fireTrack", t == nil ? "SENSOR / NO CONTACT" : "TRACK / ACQUIRED")
        set("fireRange", t.map { String(format: "RNG %4.0f", $0.rangeWorldUnits) } ?? "RNG ----")
        set("fireBearing", t.map { String(format: "BRG %+0.0f°", $0.bearingOffsetDegrees) } ?? "BRG ----")
        set("fireAim", t.map { $0.clearFiringLine ? "AIM CLEAR" : "AIM BLOCKED" } ?? "AIM ----")
        set("fireAmmo", "\(snapshot.roundsRemaining) / \(snapshot.magazineCapacity)")
        let reloading = snapshot.reloadRemainingSeconds > 0
        set("fireWeapon", snapshot.roundsRemaining == 0 ? "EMPTY" : reloading ? "CYCLING" : "READY")
        let fraction = snapshot.reloadFraction
        let fireY: CGFloat = 900-78-263
        reloadBar.path = CGPath(roundedRect: CGRect(x: 312, y: fireY+29,
                                                   width: max(0.01, 38*CGFloat(fraction)), height: 4),
                                cornerWidth: 2, cornerHeight: 2, transform: nil)

        var ground = 0
        var air = 0
        mapMarkers.removeAllChildren()
        for contact in snapshot.contacts where contact.visible {
            let dx = contact.position.x - snapshot.playerPosition.x
            let dz = contact.position.z - snapshot.playerPosition.z
            // Heading-up: rotate relative world displacement into the tank frame.
            let right = dx*cos(snapshot.headingRadians) - dz*sin(snapshot.headingRadians)
            let ahead = dx*sin(snapshot.headingRadians) + dz*cos(snapshot.headingRadians)
            let distance = hypot(right, ahead)
            let airborne = contact.kind == .drone || contact.kind == .fighter || contact.kind == .saucer
            if airborne { air += 1 } else { ground += 1 }
            guard distance <= 165 else { continue }
            let node = SKShapeNode(circleOfRadius: contact.isPrimaryTarget ? 5 : 3)
            node.position = CGPoint(x: mapCenter.x + CGFloat(right/165)*96,
                                    y: mapCenter.y + CGFloat(ahead/165)*74)
            node.strokeColor = .black
            node.fillColor = contact.isPrimaryTarget ? amber : airborne ? cyan : mint
            node.lineWidth = 1
            node.zPosition = 8
            mapMarkers.addChild(node)
        }
        set("mapContacts", String(format: "HOSTILE %02d / AIR %02d", ground, air))
        set("mapTarget", t.map { String(format: "TRACK / %.0f", $0.rangeWorldUnits) } ?? "NO TRACK")
        mapSweep.zRotation = CGFloat(clock * 0.48)

        set("opticsBearing", String(format: "AZ %03.0f°", (snapshot.headingDegrees+180).truncatingRemainder(dividingBy: 360)))
        set("opticsThreat", t == nil ? "NO TRACK" : "TARGET")
        set("score", String(format: "%06d", snapshot.score))
        set("best", String(format: "%06d", snapshot.bestScore))
        set("wave", String(format: "WAVE %02d", snapshot.wave))
        set("lives", String(format: "LIVES %02d", snapshot.lives))
        set("difficulty", snapshot.difficultyLabel.uppercased())
        set("ammo", "\(snapshot.roundsRemaining) / \(snapshot.magazineCapacity)")
        set("shield", snapshot.shieldRemainingSeconds > 0 ? "ACTIVE"
            : snapshot.shieldCooldownSeconds > 0 ? "CHARGING" : "READY")
        set("chaff", String(format: "CHAFF %02d", snapshot.chaffCharges))
        set("reload", reloading ? "RELOAD CYCLING" : "RELOAD READY")
        let systemsX: CGFloat = 1137
        let systemsY: CGFloat = 900-78-263
        updateBar(ammoBar, x: systemsX+232, y: systemsY+91, full: 159,
                  fraction: snapshot.ammunitionFraction)
        let shieldFraction = snapshot.shieldRemainingSeconds > 0 ? 1.0
            : snapshot.shieldCooldownSeconds > 0 ? 0.15 : 1.0
        updateBar(shieldBar, x: systemsX+232, y: systemsY+61, full: 159, fraction: shieldFraction)
    }

    /// Final per-frame pass. Legacy HUD draws underneath; never draw opaque
    /// art across the central gameplay viewport or the existing lower console.
    func layout(in view: CGSize, rearCamera: SKCropNode) {
        guard view.width > 0 && view.height > 0 else { return }
        let scale = min(view.width / 1600, view.height / 900)
        let left = (view.width - 1600*scale)/2
        let bottom = (view.height - 900*scale)/2
        root.setScale(scale)
        root.position = CGPoint(x: left, y: bottom)
        blanking.path = CGPath(rect: CGRect(x: 0, y: bottom+550*scale,
                                           width: view.width,
                                           height: max(0, view.height-bottom-550*scale)),
                               transform: nil)
        root.isHidden = false
        blanking.isHidden = false

        // The camera is already rendered with real world objects and shadows
        // by BattlefieldScene. Reparent to the v5.3 optics screen rectangle.
        if rearCamera.parent !== root {
            rearCamera.removeFromParent()
            root.addChild(rearCamera)
        }
        let cameraSize = (rearCamera.maskNode as? SKShapeNode)?.path?.boundingBox.size
            ?? CGSize(width: 326, height: 231)
        let cameraScale = min(326/max(1, cameraSize.width),
                              231/max(1, cameraSize.height))
        rearCamera.setScale(cameraScale)
        rearCamera.position = CGPoint(x: opticsBase.x+16,
                                      y: opticsBase.y+16)
        rearCamera.zPosition = 4
    }

    func deactivate(_ rearCamera: SKCropNode) {
        root.isHidden = true
        blanking.isHidden = true
        if let scene, rearCamera.parent === root {
            rearCamera.removeFromParent()
            rearCamera.setScale(1)
            scene.addChild(rearCamera)
        }
    }
}
