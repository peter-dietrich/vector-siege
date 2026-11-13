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
    struct MapBuilding {
        let x: Double
        let z: Double
        let size: Double
        let isSolid: Bool
    }
    private let mapMarkers = SKNode()
    private let mapGrid = SKShapeNode()
    private let mapBuildings = SKShapeNode()
    private let mapRings = SKShapeNode()
    private let mapShots = SKNode()
    private let radarViewport = SKCropNode()
    private let mapPlayer = SKShapeNode()
    private let mapSweep = SKShapeNode()
    private let reloadBar = SKShapeNode()
    private let ammoBar = SKShapeNode()
    private let shieldBar = SKShapeNode()
    private var powertrain = PowertrainModel()
    private struct PowertrainModel {
        private(set) var engineC = 41.0
        private(set) var coolantC = 38.0
        private(set) var oilPercent = 99.0
        private(set) var fuelPercent = 96.0
        private(set) var oilPressureKPa = 282.0
        private(set) var voltage = 27.6
        private(set) var loadPercent = 18.0
        private var lastClock: Double?
        private var lastLives: Int?
        private var leakRate = 0.0

        mutating func sample(clock: Double, speed: Double, lives: Int) {
            if let previous = lastClock, clock < previous - 0.5 {
                self = PowertrainModel()
            }
            let dt = min(0.25, max(0, clock - (lastClock ?? clock)))
            if let before = lastLives, lives < before {
                let impacts = Double(before - lives)
                oilPercent = max(0, oilPercent - impacts * 3.5)
                leakRate += impacts * 0.004
            }
            lastClock = clock
            lastLives = lives
            let moving = min(1, abs(speed)/17)
            loadPercent = 16 + 73*moving
            // Gameplay-relative model, not a real vehicle's physical sensors.
            // Heat and fuel change only while game time advances.
            let targetTemp = 70 + 31*moving
            engineC += (targetTemp - engineC) * min(1, dt * 0.035)
            coolantC += (engineC - 5 - coolantC) * min(1, dt * 0.06)
            fuelPercent = max(0, fuelPercent - dt * (0.002 + 0.014*moving))
            oilPercent = max(0, oilPercent - dt * leakRate)
            oilPressureKPa = max(75, min(400,
                (270 + 78*moving) * (0.60 + 0.40*oilPercent/100)
                - max(0, engineC-97)*2))
            voltage = 27.2 + 0.7*moving - (oilPercent < 50 ? 0.4 : 0)
        }
        var warning: String {
            if oilPercent < 35 || oilPressureKPa < 125 { return "OIL SYSTEM CRITICAL" }
            if engineC > 105 || coolantC > 100 { return "OVERHEAT WARNING" }
            if fuelPercent < 15 { return "LOW FUEL" }
            if oilPercent < 75 { return "SERVICE / OIL LOSS" }
            return "POWERTRAIN NORMAL"
        }
    }
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
        // Real road grid, structural footprints, threat symbols and shells are
        // clipped to the live map screen; no decorative/fabricated contacts.
        let mask = SKShapeNode(rect: CGRect(x: 416, y: mapY+68,
                                            width: 318, height: 146), cornerRadius: 2)
        mask.fillColor = .white
        mask.strokeColor = .clear
        radarViewport.maskNode = mask
        radarViewport.zPosition = 7
        root.addChild(radarViewport)
        for shape in [mapGrid, mapBuildings, mapRings] {
            shape.fillColor = .clear
            shape.lineWidth = 0.8
            radarViewport.addChild(shape)
        }
        mapGrid.strokeColor = cyan.withAlphaComponent(0.28)
        mapBuildings.strokeColor = mint.withAlphaComponent(0.30)
        mapBuildings.fillColor = mint.withAlphaComponent(0.12)
        mapRings.strokeColor = cyan.withAlphaComponent(0.45)
        mapMarkers.zPosition = 8
        radarViewport.addChild(mapMarkers)
        mapShots.zPosition = 9
        radarViewport.addChild(mapShots)
        let radarShape = CGMutablePath()
        radarShape.move(to: .zero)
        radarShape.addLine(to: CGPoint(x: 0, y: 83))
        mapSweep.path = radarShape
        mapSweep.strokeColor = mint.withAlphaComponent(0.45)
        mapSweep.lineWidth = 1
        mapSweep.position = mapCenter
        mapSweep.zPosition = 7
        radarViewport.addChild(mapSweep)
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
        radarViewport.addChild(mapPlayer)

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
        text("systemsRun", "SIMULATED TANK SENSORS", x: systemsX+31, y: systemsY+193,
             size: 9, color: amber)
        text("systemsScore", "SCORE 000000", x: systemsX+256, y: systemsY+193,
             size: 9, color: pale)
        text("engineTemp", "ENGINE   41°C", x: systemsX+31, y: systemsY+167,
             size: 12, color: mint)
        text("coolantTemp", "COOLANT  38°C", x: systemsX+31, y: systemsY+141,
             size: 12)
        text("oilPressure", "OIL PSI  41", x: systemsX+31, y: systemsY+115,
             size: 12)
        text("oilLevel", "OIL LVL  99%", x: systemsX+31, y: systemsY+89,
             size: 12, color: cyan)
        text("fuelLevel", "FUEL     96%", x: systemsX+238, y: systemsY+167,
             size: 12, color: mint)
        text("voltage", "VOLT    27.6V", x: systemsX+238, y: systemsY+141,
             size: 12)
        text("engineLoad", "ENG LOAD 18%", x: systemsX+238, y: systemsY+115,
             size: 12)
        text("waveStatus", "WAVE 01  /  03", x: systemsX+238, y: systemsY+89,
             size: 12, color: cyan)
        text("engineWarning", "POWERTRAIN NORMAL", x: systemsX+31,
             y: systemsY+48, size: 11, color: mint)
        text("systemsDisclaimer", "MODELLED / LIVE GAME STATE", x: systemsX+238,
             y: systemsY+48, size: 8, color: muted)

    }

    private func updateBar(_ shape: SKShapeNode, x: CGFloat, y: CGFloat,
                           full: CGFloat, fraction: Double) {
        let width = full * CGFloat(max(0, min(1, fraction)))
        shape.path = CGPath(roundedRect: CGRect(x: x, y: y, width: max(0.01, width), height: 5),
                            cornerWidth: 2, cornerHeight: 2, transform: nil)
    }

    func update(_ snapshot: CockpitV5Snapshot, clock: Double,
                buildings: [MapBuilding]) {
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

        // World-to-tank projection, identical heading convention to the
        // live contact renderer. 165 game units = full map range.
        func radarPoint(_ x: Double, _ z: Double) -> CGPoint {
            let dx = x - snapshot.playerPosition.x
            let dz = z - snapshot.playerPosition.z
            let right = dx*cos(snapshot.headingRadians) - dz*sin(snapshot.headingRadians)
            let ahead = dx*sin(snapshot.headingRadians) + dz*cos(snapshot.headingRadians)
            return CGPoint(x: mapCenter.x + CGFloat(right/165)*137,
                           y: mapCenter.y + CGFloat(ahead/165)*75)
        }
        // Actual city road centerlines at 60-unit intervals. The crop region
        // prevents any road/building/shell symbol from leaving the glass.
        let streets = CGMutablePath()
        for road in -3...3 {
            let axis = Double(road) * CityLayout.streetSpacing
            for offset in [-CityLayout.streetHalfWidth, CityLayout.streetHalfWidth] {
                let a = radarPoint(axis+offset, -CityLayout.cityExtent)
                let b = radarPoint(axis+offset, CityLayout.cityExtent)
                streets.move(to: a)
                streets.addLine(to: b)
                let c = radarPoint(-CityLayout.cityExtent, axis+offset)
                let d = radarPoint(CityLayout.cityExtent, axis+offset)
                streets.move(to: c)
                streets.addLine(to: d)
            }
        }
        mapGrid.path = streets
        let footprint = CGMutablePath()
        for building in buildings {
            let p = radarPoint(building.x, building.z)
            let r = max(1.5, CGFloat(building.size/165)*96)
            footprint.addRect(CGRect(x: p.x-r, y: p.y-r,
                                     width: 2*r, height: 2*r))
        }
        mapBuildings.path = footprint
        let rings = CGMutablePath()
        for radius in [CGFloat(35), CGFloat(72), CGFloat(112)] {
            rings.addEllipse(in: CGRect(x: mapCenter.x-radius,
                                        y: mapCenter.y-radius*0.64,
                                        width: radius*2, height: radius*1.28))
        }
        mapRings.path = rings
        let ground = snapshot.contacts.filter {
            $0.visible && $0.kind != .drone && $0.kind != .fighter && $0.kind != .saucer
        }.count
        let air = snapshot.contacts.filter {
            $0.visible && ($0.kind == .drone || $0.kind == .fighter || $0.kind == .saucer)
        }.count
        mapMarkers.removeAllChildren()
        for contact in snapshot.contacts where contact.visible {
            let dx = contact.position.x - snapshot.playerPosition.x
            let dz = contact.position.z - snapshot.playerPosition.z
            guard hypot(dx, dz) <= 165 else { continue }
            let p = radarPoint(contact.position.x, contact.position.z)
            let airborne = contact.kind == .drone || contact.kind == .fighter || contact.kind == .saucer
            let node = SKShapeNode(circleOfRadius: contact.isPrimaryTarget ? 5 : 2.6)
            node.position = p
            node.strokeColor = contact.isPrimaryTarget ? amber : .black
            node.fillColor = contact.isPrimaryTarget ? amber : airborne ? cyan : mint
            node.lineWidth = contact.isPrimaryTarget ? 2 : 1
            mapMarkers.addChild(node)
            if contact.isPrimaryTarget {
                let cue = SKShapeNode(circleOfRadius: 8)
                cue.position = p
                cue.strokeColor = amber
                cue.fillColor = .clear
                cue.lineWidth = 1
                mapMarkers.addChild(cue)
            }
        }
        mapShots.removeAllChildren()
        for shot in snapshot.projectiles {
            let dx = shot.position.x - snapshot.playerPosition.x
            let dz = shot.position.z - snapshot.playerPosition.z
            guard hypot(dx, dz) <= 165 else { continue }
            let dot = SKShapeNode(circleOfRadius: 2)
            dot.position = radarPoint(shot.position.x, shot.position.z)
            dot.fillColor = shot.hostile ? amber : mint
            dot.strokeColor = .clear
            mapShots.addChild(dot)
        }
        set("mapContacts", String(format: "HOSTILE %02d / AIR %02d", ground, air))
        set("mapTarget", t.map { String(format: "TRACK / %.0f", $0.rangeWorldUnits) } ?? "NO TRACK")
        mapSweep.zRotation = CGFloat(clock * 0.48)

        set("opticsBearing", String(format: "AZ %03.0f°", (snapshot.headingDegrees+180).truncatingRemainder(dividingBy: 360)))
        set("opticsThreat", t == nil ? "NO TRACK" : "TARGET")
        powertrain.sample(clock: clock,
                          speed: snapshot.speedWorldUnitsPerSecond,
                          lives: snapshot.lives)
        set("systemsScore", String(format("SCORE %06d", snapshot.score))
        set("engineTemp", String(format("ENGINE  %3.0f°C", powertrain.engineC))
        set("coolantTemp", String(format("COOLANT %3.0f°C", powertrain.coolantC))
        set("oilPressure", String(format("OIL PSI %3.0f",
            powertrain.oilPressureKPa * 0.1450377))
        set("oilLevel", String(format("OIL LVL %3.0f%%", powertrain.oilPercent))
        set("fuelLevel", String(format("FUEL    %3.0f%%", powertrain.fuelPercent))
        set("voltage", String(format("VOLT    %.1fV", powertrain.voltage))
        set("engineLoad", String(format("ENG LOAD %2.0f%%", powertrain.loadPercent))
        set("waveStatus", String(format("WAVE %02d / %02d",
                                       snapshot.wave, snapshot.lives))
        set("engineWarning", powertrain.warning)
        labels["engineWarning"]?.fontColor =
            powertrain.warning == "POWERTRAIN NORMAL" ? mint : amber
    }

    /// Final per-frame pass. Legacy HUD draws underneath; never draw opaque
    /// art across the central gameplay viewport or the existing lower console.
    func layout(in view: CGSize, rearCamera: SKCropNode) {
        guard view.width > 0 && view.height > 0 else { return }
        let scale = min(view.width / 1600, view.height / 900)
        let left = (view.width - 1600*scale)/2
        let bottom = (view.height - 900*scale)/2
        root.setScale(scale)
        root.position = CGPoint(x: left, y: bottom + 68*scale)
        blanking.path = CGPath(rect: CGRect(x: 0, y: bottom+620*scale,
                                           width: view.width,
                                           height: max(0, view.height-bottom-620*scale)),
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
