import AppKit
import SpriteKit

/// v5.3 approved visual direction: individually framed graphite/amber lower
/// instruments. Replaces only the legacy lower HUD in Cockpit v5.3 mode.
/// All numbers, graphs, compass ticks and control hints are live SpriteKit.
final class CockpitV53LowerDeck {
    private let root = SKNode()
    private let curtain = SKShapeNode()
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

    private func frame(_ x: CGFloat, _ width: CGFloat, title: String, index: Int) {
        let y: CGFloat = 57, h: CGFloat = 158
        plate(CGRect(x: x, y: y, width: width, height: h),
              color: NSColor(calibratedWhite: 0.038, alpha: 1),
              stroke: NSColor(calibratedWhite: 0.15, alpha: 1),
              radius: 13, lineWidth: 3, z: 2)
        plate(CGRect(x: x+4, y: y+4, width: width-8, height: h-8),
              color: metal, stroke: bevel,
              radius: 10, lineWidth: 1.4, z: 3)
        plate(CGRect(x: x+10, y: y+12, width: width-20, height: h-25),
              color: glass, stroke: amber.withAlphaComponent(0.44),
              radius: 5, lineWidth: 0.9, z: 4)
        plate(CGRect(x: x+width*0.35, y: y+h-11,
                     width: width*0.30, height: 3),
              color: amber, stroke: .clear, radius: 1.2, z: 8)
        plate(CGRect(x: x+14, y: y+17, width: 3, height: 24),
              color: amber.withAlphaComponent(0.72),
              stroke: .clear, radius: 1, z: 8)
        plate(CGRect(x: x+width-17, y: y+17, width: 3, height: 24),
              color: amber.withAlphaComponent(0.72),
              stroke: .clear, radius: 1, z: 8)
        for screwX in [x+9, x+width-9] {
            for screwY in [y+10, y+h-9] {
                let screw = SKShapeNode(circleOfRadius: 2.2)
                screw.position = CGPoint(x: screwX, y: screwY)
                screw.strokeColor = NSColor(calibratedWhite: 0.62, alpha: 1)
                screw.fillColor = NSColor(calibratedWhite: 0.14, alpha: 1)
                screw.zPosition = 9
                root.addChild(screw)
            }
        }
        label("title\(index)", title, x: x+21, y: 185,
              size: 11, color: mint)
        line(CGPoint(x: x+20, y: 171),
             CGPoint(x: x+width-20, y: 171),
             color: muted.withAlphaComponent(0.26), width: 0.8)
    }

    private func build() {
        // Armored crossbeam connects the five discrete instrument housings.
        plate(CGRect(x: 11, y: 46, width: 1578, height: 184),
              color: metal, stroke: bevel, radius: 13,
              lineWidth: 2.4)
        for x in stride(from: CGFloat(18), through: CGFloat(1575), by: 115) {
            plate(CGRect(x: x, y: 218, width: 58, height: 4),
                  color: NSColor(calibratedWhite: 0.26, alpha: 1),
                  stroke: .clear, radius: 1, z: 3)
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
        tankLines.strokeColor = cyan
        tankLines.fillColor = .clear
        tankLines.lineWidth = 1.5
        tankLines.zPosition = 10
        root.addChild(tankLines)
        label("hull", "INTEGRITY 100%", x: 47, y: 91, size: 12, color: mint)
        label("tankState", "SYSTEMS ONLINE", x: 47, y: 75, size: 10)

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

        // 05 / Separate grid position and elevation; no duplication of nav.
        label("sector", "D-04", x: 1457, y: 143, size: 29,
              color: cyan, align: .center)
        label("elev", "ELEV +0 FT", x: 1550, y: 105,
              size: 11, align: .right)
        label("coords", "X +0  Z +0", x: 1550, y: 80,
              size: 10, color: muted, align: .right)

        // Mechanical control bar below, inspired by the approved mockup.
        plate(CGRect(x: 11, y: 5, width: 1578, height: 47),
              color: metal, stroke: bevel, radius: 9, lineWidth: 1.5)
        let actions: [(String, String, CGFloat, CGFloat)] = [
            ("DRIVE", "W/S", 50, 215),
            ("TURN", "A/D", 276, 210),
            ("SPACE / CANNON", "SPACE", 497, 259),
            ("TWIN MG", "F", 768, 214),
            ("SHIELD", "SHIFT", 994, 195),
            ("CHAFF", "E", 1200, 170),
            ("PAUSE", "P", 1380, 158)
        ]
        for (title, key, x, w) in actions {
            plate(CGRect(x: x, y: 12, width: w, height: 32),
                  color: glass, stroke: NSColor(calibratedWhite: 0.35, alpha: 1),
                  radius: 5, z: 4)
            plate(CGRect(x: x+8, y: 19, width: 3, height: 18),
                  color: amber, stroke: .clear, radius: 1, z: 5)
            label("control_\(title)", title, x: x+17, y: 27, size: 11)
            label("key_\(title)", key, x: x+w-11, y: 27,
                  size: 9, color: amber, align: .right)
        }
    }

    func update(_ snap: CockpitV5Snapshot, terrain: [Double]) {
        let integrity = min(100, max(0, 100.0 * Double(snap.lives) / 3))
        set("hull", String(format: "INTEGRITY %.0f%%", integrity))
        set("tankState", snap.lives <= 1 ? "SYSTEMS / CRITICAL" : "SYSTEMS / ONLINE")
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
        root.position = CGPoint(x: (size.width-1600*scale)/2, y: 0)
        curtain.path = CGPath(rect: CGRect(x: 0, y: 0, width: size.width,
                                           height: 232*scale), transform: nil)
        root.isHidden = false
        curtain.isHidden = false
    }

    func hide() {
        root.isHidden = true
        curtain.isHidden = true
    }
}
