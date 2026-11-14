import AppKit
import SpriteKit

/// v5.3 approved visual direction: individually framed graphite/amber lower
/// instruments. Replaces only the legacy lower HUD in Cockpit v5.3 mode.
/// All numbers, graphs, compass ticks and control hints are live SpriteKit.
final class CockpitV53LowerDeck {
    private let root = SKNode()
    private let curtain = SKShapeNode()
    private let approvedArtRoot = SKNode()
    private var approvedArtLoaded = false
    private var artLabels: [String: SKLabelNode] = [:]
    private var chassisSprite: SKSpriteNode?
    private let metal = NSColor(calibratedRed: 0.105, green: 0.122, blue: 0.131, alpha: 1)
    private let bevel = NSColor(calibratedRed: 0.41, green: 0.43, blue: 0.42, alpha: 1)
    private let glass = NSColor(calibratedRed: 0.012, green: 0.042, blue: 0.050, alpha: 1)
    private let amber = NSColor(calibratedRed: 1, green: 0.59, blue: 0.15, alpha: 1)
    private let mint = NSColor(calibratedRed: 0.35, green: 0.95, blue: 0.64, alpha: 1)
    private let cyan = NSColor(calibratedRed: 0.38, green: 0.81, blue: 0.87, alpha: 1)
    private let white = NSColor(calibratedRed: 0.90, green: 0.94, blue: 0.94, alpha: 1)
    private let muted = NSColor(calibratedRed: 0.45, green: 0.63, blue: 0.62, alpha: 1)
    private var labels: [String: SKLabelNode] = [:]
    private let hitArc = SKShapeNode()
    private let tankLines = SKShapeNode()
    private let compassTicks = SKShapeNode()
    private let compassLabels = SKNode()
    private let terrainTrace = SKShapeNode()
    private let terrainFill = SKShapeNode()
    private let integrityBar = SKShapeNode()
    private let alertStripe = SKShapeNode()

    init(scene: SKScene) {
        curtain.zPosition = 37.8
        curtain.fillColor = NSColor(calibratedWhite: 0.025, alpha: 1)
        curtain.strokeColor = .clear
        scene.addChild(curtain)
        root.zPosition = 38
        scene.addChild(root)
        build()
        installApprovedArtwork()
    }

    private func artLabel(_ key: String, _ value: String,
                          x: CGFloat, y: CGFloat, size: CGFloat,
                          color: NSColor? = nil,
                          align: SKLabelHorizontalAlignmentMode = .left) {
        let node = SKLabelNode(fontNamed: "Menlo-Bold")
        node.text = value
        node.fontSize = size
        node.fontColor = color ?? white
        node.position = CGPoint(x: x, y: y)
        node.verticalAlignmentMode = .center
        node.horizontalAlignmentMode = align
        node.zPosition = 26
        approvedArtRoot.addChild(node)
        artLabels[key] = node
    }

    private func installApprovedArtwork() {
        // This is derived from the user-approved cockpit mockup. The five
        // glass areas have been cleared of example telemetry; all values
        // below are live and updated from game state.
        let filename = "VectorSiege_Lower_Cockpit_Phase1_Approved.png"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("CockpitV5").appendingPathComponent(filename),
            Bundle.main.resourceURL?.appendingPathComponent("Resources/CockpitV5").appendingPathComponent(filename),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/CockpitV5").appendingPathComponent(filename)
        ].compactMap { $0 }
        guard let artworkURL = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }), let artwork = NSImage(contentsOf: artworkURL) else {
            // Preserve the working game if the optional artwork is missing.
            return
        }
        let sprite = SKSpriteNode(texture: SKTexture(image: artwork))
        sprite.size = CGSize(width: 1600, height: 256)
        sprite.position = CGPoint(x: 800, y: 128)
        sprite.zPosition = 1
        approvedArtRoot.zPosition = 39
        approvedArtRoot.addChild(sprite)
        root.parent?.addChild(approvedArtRoot)
        approvedArtLoaded = true

        // Reuse the existing live instrument geometry but move it above
        // the photographic glass rather than redrawing substitute frames.
        for dynamic in [tankLines, hitArc, compassTicks, compassLabels,
                        terrainFill, terrainTrace] {
            dynamic.removeFromParent()
            approvedArtRoot.addChild(dynamic)
        }
        tankLines.position = CGPoint(x: 39, y: 9)
        hitArc.position = CGPoint(x: 567, y: 129)
        hitArc.strokeColor = mint
        hitArc.lineWidth = 10
        compassTicks.zPosition = 10
        compassLabels.zPosition = 12
        terrainTrace.zPosition = 12
        terrainFill.zPosition = 10

        artLabel("artHull", "100%", x: 342, y: 167, size: 14,
                 color: mint, align: .right)
        artLabel("artSystems", "NORMAL", x: 342, y: 128, size: 11,
                 color: mint, align: .right)
        artLabel("artMode", "DRIVE", x: 342, y: 94, size: 11,
                 color: cyan, align: .right)
        artLabel("artPercent", "0%", x: 409, y: 158, size: 30, color: mint)
        artLabel("artHits", "HITS 000", x: 414, y: 122, size: 11)
        artLabel("artShots", "SHOTS 000", x: 414, y: 100, size: 11)
        artLabel("artEfficiency", "HIT / 0%", x: 414, y: 80, size: 9, color: muted)
        let ring = SKShapeNode(circleOfRadius: 39)
        ring.position = CGPoint(x: 567, y: 129)
        ring.fillColor = .clear
        ring.strokeColor = NSColor(calibratedRed: 0.12, green: 0.36, blue: 0.35, alpha: 1)
        ring.lineWidth = 10
        ring.zPosition = 9
        approvedArtRoot.addChild(ring)
        artLabel("artHeading", "000°", x: 833, y: 158, size: 34,
                 color: amber, align: .center)
        artLabel("artNavLeft", "‹‹", x: 744, y: 160, size: 21, color: amber)
        artLabel("artNavRight", "››", x: 904, y: 160, size: 21,
                 color: amber, align: .right)
        artLabel("artProfile", "LIVE / 480 FT", x: 1023, y: 171, size: 8,
                 color: cyan)
        artLabel("artProfileMin", "PROFILE / FORWARD", x: 1023, y: 76, size: 9,
                 color: muted)
        artLabel("artSector", "D-04", x: 1456, y: 163, size: 23,
                 color: mint, align: .center)
        artLabel("artElev", "ELEV +0 FT", x: 1535, y: 129, size: 10,
                 align: .right)
        artLabel("artX", "X +0", x: 1535, y: 104, size: 10,
                 align: .right)
        artLabel("artZ", "Z +0", x: 1535, y: 81, size: 10,
                 align: .right)
    }

    private func updateApprovedArt(_ snap: CockpitV5Snapshot,
                                   terrain: [Double]) {
        guard approvedArtLoaded else { return }
        func setArt(_ key: String, _ text: String) {
            artLabels[key]?.text = text
        }
        let integrity = min(100, max(0, 100.0 * Double(snap.lives)/3))
        setArt("artHull", String(format: "%.0f%%", integrity))
        setArt("artSystems", snap.lives <= 1 ? "CRITICAL" : "NORMAL")
        artLabels["artSystems"]?.fontColor = snap.lives <= 1 ? amber : mint
        setArt("artMode", snap.lives <= 0 ? "OFFLINE" : "DRIVE")
        setArt("artPercent", String(format: "%.0f%%", snap.accuracyPercent))
        setArt("artHits", String(format: "HITS %03d", snap.shotsHit))
        setArt("artShots", String(format: "SHOTS %03d", snap.shotsFired))
        setArt("artEfficiency", String(format: "EFFICIENCY %.0f%%", snap.accuracyPercent))
        setArt("artHeading", String(format: "%03.0f°", snap.headingDegrees))
        setArt("artSector", snap.sector)
        setArt("artElev", String(format: "ELEV %+.0f FT",
                                 snap.terrainElevationWorldUnits*3.28084))
        setArt("artX", String(format: "X %+.0f", snap.playerPosition.x))
        setArt("artZ", String(format: "Z %+.0f", snap.playerPosition.z))
        if let lo = terrain.min(), let hi = terrain.max() {
            setArt("artProfileMin", String(format: "LOW %+.0f / HIGH %+.0f FT",
                                          lo*3.28084, hi*3.28084))
        }
    }

    private func plate(_ frame: CGRect, color: NSColor, stroke: NSColor,
                       radius: CGFloat, lineWidth: CGFloat = 1,
                       z: CGFloat = 1) -> SKShapeNode {
        let node = SKShapeNode(rect: frame, cornerRadius: radius)
        node.fillColor = color
        node.strokeColor = stroke
        node.lineWidth = lineWidth
        node.zPosition = z
        root.addChild(node)
        return node
    }

    private func label(_ key: String, _ value: String,
                       x: CGFloat, y: CGFloat, size: CGFloat,
                       color: NSColor? = nil,
                       align: SKLabelHorizontalAlignmentMode = .left) {
        let node = SKLabelNode(fontNamed: "Menlo-Bold")
        node.text = value
        node.position = CGPoint(x: x, y: y)
        node.fontSize = size
        node.fontColor = color ?? white
        node.horizontalAlignmentMode = align
        node.verticalAlignmentMode = .center
        node.zPosition = 13
        root.addChild(node)
        labels[key] = node
    }

    private func set(_ key: String, _ value: String) {
        labels[key]?.text = value
    }

    private func line(_ a: CGPoint, _ b: CGPoint,
                      color: NSColor, width: CGFloat, z: CGFloat = 7) {
        let p = CGMutablePath()
        p.move(to: a)
        p.addLine(to: b)
        let node = SKShapeNode(path: p)
        node.strokeColor = color
        node.fillColor = .clear
        node.lineWidth = width
        node.zPosition = z
        root.addChild(node)
    }

    // Dedicated lower-module hardware. No stretched upper cockpit textures.
    // Every bezel shares the same Y bands and a 20pt instrument safe inset.
    private func frame(_ x: CGFloat, _ width: CGFloat, title: String, index: Int) {
        // The structural skin defines five exact cutouts. Text stays live.
        label("title\(index)", title, x: x+22, y: 184,
              size: 11, color: mint)
    }

    private func build() {
        // One specially rendered connected armored chassis; the cutouts,
        // glass, hardware and control strip are ONE coherent visual layer.
        if let texture = CockpitV53LowerChassis.texture() {
            let chassis = SKSpriteNode(texture: texture,
                                       size: CGSize(width: 1600, height: 256))
            chassis.position = CGPoint(x: 800, y: 128)
            chassis.zPosition = 1
            root.addChild(chassis)
            chassisSprite = chassis
        }
        frame(24, 351, title: "TANK STATUS", index: 0)
        frame(383, 243, title: "HIT RATIO", index: 1)
        frame(634, 405, title: "NAV / HEADING", index: 2)
        frame(1047, 285, title: "TERRAIN PROFILE", index: 3)
        frame(1340, 236, title: "SECTOR", index: 4)

        // 01 / Tank elevation schematic; original bottom design's content.
        let tank = CGMutablePath()
        tank.move(to: CGPoint(x: 66, y: 109))
        tank.addLine(to: CGPoint(x: 272, y: 109))
        tank.addLine(to: CGPoint(x: 292, y: 119))
        tank.addLine(to: CGPoint(x: 274, y: 127))
        tank.addLine(to: CGPoint(x: 86, y: 127))
        tank.closeSubpath()
        tank.move(to: CGPoint(x: 112, y: 128))
        tank.addLine(to: CGPoint(x: 136, y: 145))
        tank.addLine(to: CGPoint(x: 205, y: 146))
        tank.addLine(to: CGPoint(x: 221, y: 129))
        tank.move(to: CGPoint(x: 152, y: 145))
        tank.addLine(to: CGPoint(x: 152, y: 155))
        tank.addLine(to: CGPoint(x: 170, y: 155))
        tank.move(to: CGPoint(x: 202, y: 138))
        tank.addLine(to: CGPoint(x: 272, y: 142))
        for n in 0..<7 {
            tank.addEllipse(in: CGRect(x: 89+CGFloat(n)*25, y: 111,
                                       width: 14, height: 14))
        }
        tankLines.path = tank
        // Fit the side elevation to the left half; leave the right side for
        // integrity and system state, as in the approved mockup.
        tankLines.xScale = 0.57
        tankLines.position = CGPoint(x: 32, y: 0)
        tankLines.strokeColor = cyan
        tankLines.fillColor = .clear
        tankLines.lineWidth = 1.5
        tankLines.zPosition = 10
        root.addChild(tankLines)
        label("hullLabel", "INTEGRITY", x: 223, y: 143, size: 9, color: muted)
        label("hull", "100%", x: 350, y: 143, size: 17, color: mint, align: .right)
        label("tankState", "SYSTEMS ONLINE", x: 223, y: 110, size: 10)
        label("tankMode", "MODE / COMBAT", x: 223, y: 88, size: 10, color: cyan)
        plate(CGRect(x: 223, y: 130, width: 127, height: 4),
              color: NSColor(calibratedRed: 0.12, green: 0.30, blue: 0.27, alpha: 1),
              stroke: .clear, radius: 1, z: 9)
        integrityBar.path = CGPath(roundedRect: CGRect(x: 223, y: 130, width: 127, height: 4),
                                   cornerWidth: 1, cornerHeight: 1, transform: nil)
        integrityBar.fillColor = mint
        integrityBar.strokeColor = .clear
        integrityBar.zPosition = 12
        root.addChild(integrityBar)

        // 02 / Numeric firing efficiency and the original circular instrument.
        label("hitPercent", "0%", x: 403, y: 113, size: 34, color: cyan)
        label("hitCount", "HITS 000", x: 403, y: 86, size: 11)
        label("shotCount", "SHOTS 000", x: 403, y: 70, size: 11, color: muted)
        let dial = SKShapeNode(circleOfRadius: 39)
        dial.position = CGPoint(x: 565, y: 115)
        dial.strokeColor = NSColor(calibratedRed: 0.12, green: 0.37,
                                   blue: 0.38, alpha: 1)
        dial.fillColor = .clear
        dial.lineWidth = 10
        dial.zPosition = 9
        root.addChild(dial)
        hitArc.position = dial.position
        hitArc.strokeColor = mint
        hitArc.fillColor = .clear
        hitArc.lineWidth = 9
        hitArc.lineCap = .round
        hitArc.zPosition = 10
        root.addChild(hitArc)

        // 03 / Central navigation tape. Direction readings are true tank heading.
        plate(CGRect(x: 760, y: 173, width: 148, height: 34),
              color: NSColor(calibratedRed: 0.115, green: 0.075,
                             blue: 0.022, alpha: 1),
              stroke: amber, radius: 5, z: 8)
        label("heading", "000°", x: 833, y: 190, size: 29,
              color: amber, align: .center)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 827, y: 118))
        p.addLine(to: CGPoint(x: 840, y: 118))
        p.addLine(to: CGPoint(x: 833.5, y: 106))
        p.closeSubpath()
        let compassPointer = SKShapeNode(path: p)
        compassPointer.fillColor = amber
        compassPointer.strokeColor = .clear
        compassPointer.zPosition = 12
        root.addChild(compassPointer)
        compassTicks.strokeColor = cyan
        compassTicks.lineWidth = 1
        compassTicks.zPosition = 9
        root.addChild(compassTicks)
        compassLabels.zPosition = 12
        root.addChild(compassLabels)
        label("headingCaption", "NAV / HEADING", x: 833, y: 75,
              size: 11, color: cyan, align: .center)

        // 04 / Sampled physical landscape ahead of the tank.
        for idx in 0...4 {
            let xx = 1067+CGFloat(idx)*61
            line(CGPoint(x: xx, y: 81), CGPoint(x: xx, y: 158),
                 color: mint.withAlphaComponent(0.17), width: 0.6)
        }
        for idx in 0...3 {
            let yy = 82+CGFloat(idx)*24
            line(CGPoint(x: 1067, y: yy), CGPoint(x: 1312, y: yy),
                 color: mint.withAlphaComponent(0.15), width: 0.6)
        }
        terrainFill.fillColor = mint.withAlphaComponent(0.15)
        terrainFill.strokeColor = .clear
        terrainFill.zPosition = 8
        root.addChild(terrainFill)
        terrainTrace.strokeColor = mint
        terrainTrace.lineWidth = 2
        terrainTrace.fillColor = .clear
        terrainTrace.zPosition = 9
        root.addChild(terrainTrace)
        label("terrainMinMax", "PROFILE / LIVE", x: 1067, y: 71,
              size: 9, color: muted)
        label("terrainTag", "FORWARD TERRAIN  /  480 FT", x: 1067, y: 162,
              size: 8, color: cyan)

        // 05 / Separate grid position and elevation; no duplication of nav.
        label("sector", "D-04", x: 1457, y: 143, size: 29,
              color: cyan, align: .center)
        label("elev", "ELEV +0 FT", x: 1550, y: 105,
              size: 11, align: .right)
        label("coords", "X +0  Z +0", x: 1550, y: 80,
              size: 10, color: muted, align: .right)

        // Physical buttons are already integrated in the unified chassis.
        let actions: [(String, String, CGFloat, CGFloat)] = [
            ("DRIVE", "↑↓", 50, 208),
            ("TURN", "←→", 269, 206),
            ("CANNON", "SPACE", 486, 255),
            ("TWIN MG", "F", 752, 208),
            ("SHIELD", "SHIFT", 971, 194),
            ("CHAFF", "E", 1176, 169),
            ("PAUSE", "P", 1357, 181)
        ]
        for (title, key, x, w) in actions {
            label("control_\(title)", title, x: x+17, y: 27, size: 11)
            label("key_\(title)", key, x: x+w-11, y: 27,
                  size: 9, color: amber, align: .right)
        }
    }

    func update(_ snap: CockpitV5Snapshot, terrain: [Double]) {
        let integrity = min(100, max(0, 100.0 * Double(snap.lives) / 3))
        set("hull", String(format: "%.0f%%", integrity))
        set("tankState", snap.lives <= 1 ? "SYSTEMS CRITICAL" : "SYSTEMS ONLINE")
        integrityBar.path = CGPath(roundedRect: CGRect(x: 223, y: 130,
                               width: max(0.1, 127*CGFloat(integrity/100)), height: 4),
                               cornerWidth: 1, cornerHeight: 1, transform: nil)
        integrityBar.fillColor = snap.lives <= 1 ? amber : mint
        labels["hull"]?.fontColor = snap.lives <= 1 ? amber : mint
        set("hitPercent", String(format: "%.0f%%", snap.accuracyPercent))
        set("hitCount", String(format: "HITS %03d", snap.shotsHit))
        set("shotCount", String(format: "SHOTS %03d", snap.shotsFired))
        let ratio = max(0, min(1, snap.accuracyPercent/100))
        let arc = CGMutablePath()
        if ratio > 0 {
            arc.addArc(center: .zero, radius: 39,
                       startAngle: -.pi/2,
                       endAngle: -.pi/2 + CGFloat(ratio)*2 * .pi,
                       clockwise: false)
        }
        hitArc.path = arc
        set("heading", String(format: "%03.0f°", snap.headingDegrees))
        let ticks = CGMutablePath()
        compassLabels.removeAllChildren()
        let heading = snap.headingDegrees
        // +/- 75 degree scope centered on current tank heading.
        for index in -7...7 {
            let degrees = Double(index)*10
            let x = CGFloat(833 + degrees * 2.3)
            let large = index.isMultiple(of: 3)
            ticks.move(to: CGPoint(x: x, y: 100))
            ticks.addLine(to: CGPoint(x: x, y: large ? 114 : 109))
            if large {
                let node = SKLabelNode(fontNamed: "Menlo")
                let angle = (heading + degrees + 360).truncatingRemainder(dividingBy: 360)
                node.text = String(format: "%03.0f", angle)
                node.fontSize = 9
                node.fontColor = cyan
                node.position = CGPoint(x: x, y: 86)
                node.zPosition = 11
                compassLabels.addChild(node)
            }
        }
        compassTicks.path = ticks
        set("sector", snap.sector)
        set("elev", String(format: "ELEV %+.0f FT",
                           snap.terrainElevationWorldUnits*3.28084))
        set("coords", String(format: "X %+.0f  Z %+.0f",
                             snap.playerPosition.x, snap.playerPosition.z))
        updateApprovedArt(snap, terrain: terrain)
        if terrain.count > 1 {
            let minimum = (terrain.min() ?? 0) - 1
            let maximum = (terrain.max() ?? 1) + 1
            let extent = max(1, maximum-minimum)
            let trace = CGMutablePath()
            let fill = CGMutablePath()
            fill.move(to: CGPoint(x: 1067, y: 83))
            for (i, height) in terrain.enumerated() {
                let x = CGFloat(1067) + CGFloat(i)*245 / CGFloat(terrain.count-1)
                let y = CGFloat(89) + CGFloat((height-minimum)/extent)*63
                if i == 0 { trace.move(to: CGPoint(x: x, y: y)) }
                else { trace.addLine(to: CGPoint(x: x, y: y)) }
                fill.addLine(to: CGPoint(x: x, y: y))
            }
            fill.addLine(to: CGPoint(x: 1312, y: 83))
            fill.closeSubpath()
            terrainTrace.path = trace
            terrainFill.path = fill
            set("terrainMinMax", String(format: "ELEV %+.0f TO %+.0f FT",
                  minimum * 3.28084, maximum * 3.28084))
        }
    }

    func layout(in size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }
        let scale = min(size.width/1600, size.height/900)
        root.setScale(scale)
        // Raise the deck so the physical keycaps do not disappear behind the
        // app's bottom help strip. Preserve full width responsive scaling.
        root.position = CGPoint(x: (size.width-1600*scale)/2, y: 32*scale)
        curtain.path = CGPath(rect: CGRect(x: 0, y: 0, width: size.width,
                                           height: 264*scale), transform: nil)
        root.isHidden = approvedArtLoaded
        approvedArtRoot.isHidden = !approvedArtLoaded
        approvedArtRoot.setScale(scale)
        approvedArtRoot.position = CGPoint(x: (size.width-1600*scale)/2, y: 20*scale)
        curtain.isHidden = false
    }

    func hide() {
        root.isHidden = true
        approvedArtRoot.isHidden = true
        curtain.isHidden = true
    }
}
