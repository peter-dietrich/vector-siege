import AppKit
import SpriteKit

/// Live instruments over the user-approved single-piece lower cockpit artwork.
/// Coordinates are in the artwork's 1600×256 space. No procedural chassis,
/// fallback mockup, or second legacy dashboard is ever drawn here.
final class CockpitV53LowerDeck {
    static let artworkName = "VectorSiege_Clean_Shell_Approved.png"
    private let root = SKNode()
    private let curtain = SKShapeNode()
    private let dataRoot = SKNode()
    private let cyan = NSColor(calibratedRed: 0.39, green: 0.92, blue: 0.93, alpha: 1)
    private let mint = NSColor(calibratedRed: 0.38, green: 0.98, blue: 0.66, alpha: 1)
    private let amber = NSColor(calibratedRed: 1, green: 0.66, blue: 0.23, alpha: 1)
    private let pale = NSColor(calibratedRed: 0.92, green: 0.95, blue: 0.93, alpha: 1)
    private let muted = NSColor(calibratedRed: 0.52, green: 0.70, blue: 0.69, alpha: 1)
    private var labels: [String: SKLabelNode] = [:]
    private let tankOutline = SKShapeNode()
    private let hitArc = SKShapeNode()
    private let compassTicks = SKShapeNode()
    private let compassNumbers = SKNode()
    private let terrainTrace = SKShapeNode()
    private let terrainFill = SKShapeNode()
    private let readinessBar = SKShapeNode()
    private var installed = false

    init(scene: SKScene) {
        curtain.zPosition = 37.8
        curtain.fillColor = NSColor(calibratedRed: 0.012, green: 0.018, blue: 0.020, alpha: 1)
        curtain.strokeColor = .clear
        scene.addChild(curtain)
        root.zPosition = 38
        scene.addChild(root)

        let locations = [
            Bundle.main.resourceURL?.appendingPathComponent("CockpitV5").appendingPathComponent(Self.artworkName),
            Bundle.main.resourceURL?.appendingPathComponent("Resources/CockpitV5").appendingPathComponent(Self.artworkName),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Resources/CockpitV5")
                .appendingPathComponent(Self.artworkName)
        ].compactMap { $0 }
        if let url = locations.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
           let image = NSImage(contentsOf: url) {
            let shell = SKSpriteNode(texture: SKTexture(image: image))
            shell.size = CGSize(width: 1600, height: 256)
            shell.position = CGPoint(x: 800, y: 128)
            shell.zPosition = 0
            root.addChild(shell)
            dataRoot.zPosition = 2
            root.addChild(dataRoot)
            buildInstruments()
            installed = true
        } else {
            let warning = SKLabelNode(fontNamed: "Menlo-Bold")
            warning.text = "APPROVED LOWER COCKPIT ART MISSING"
            warning.fontSize = 18
            warning.fontColor = .systemOrange
            warning.position = CGPoint(x: 800, y: 134)
            warning.horizontalAlignmentMode = .center
            root.addChild(warning)
        }
    }

    private func label(_ key: String, _ text: String, x: CGFloat, y: CGFloat,
                       size: CGFloat, color: NSColor,
                       alignment: SKLabelHorizontalAlignmentMode = .left) {
        let node = SKLabelNode(fontNamed: "Menlo-Bold")
        node.text = text
        node.position = CGPoint(x: x, y: y)
        node.fontColor = color
        node.fontSize = size
        node.horizontalAlignmentMode = alignment
        node.verticalAlignmentMode = .center
        node.zPosition = 5
        dataRoot.addChild(node)
        labels[key] = node
    }

    private func set(_ key: String, _ value: String) { labels[key]?.text = value }

    private func line(_ path: CGMutablePath, _ x: CGFloat, _ y: CGFloat,
                      _ endX: CGFloat, _ endY: CGFloat) {
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: endX, y: endY))
    }

    private func buildInstruments() {
        // PANEL 1: readable vehicle technical silhouette and truthful life
        // status. No invented armor-integrity percentage.
        let tank = CGMutablePath()
        tank.move(to: CGPoint(x: 93, y: 124))
        tank.addLine(to: CGPoint(x: 265, y: 124))
        tank.addLine(to: CGPoint(x: 282, y: 113))
        tank.addLine(to: CGPoint(x: 265, y: 101))
        tank.addLine(to: CGPoint(x: 98, y: 101))
        tank.closeSubpath()
        tank.move(to: CGPoint(x: 119, y: 125))
        tank.addLine(to: CGPoint(x: 137, y: 146))
        tank.addLine(to: CGPoint(x: 196, y: 149))
        tank.addLine(to: CGPoint(x: 220, y: 125))
        tank.move(to: CGPoint(x: 157, y: 149))
        tank.addLine(to: CGPoint(x: 157, y: 158))
        tank.addLine(to: CGPoint(x: 185, y: 158))
        tank.move(to: CGPoint(x: 200, y: 141))
        tank.addLine(to: CGPoint(x: 285, y: 144))
        for i in 0..<7 {
            let xx = 114 + CGFloat(i)*22
            tank.addEllipse(in: CGRect(x: xx, y: 106, width: 11, height: 11))
        }
        tankOutline.path = tank
        tankOutline.strokeColor = cyan
        tankOutline.fillColor = .clear
        tankOutline.lineWidth = 1.6
        tankOutline.zPosition = 4
        dataRoot.addChild(tankOutline)
        label("tankLives", "03 LIVES", x: 102, y: 83, size: 13, color: pale)
        label("tankStatus", "ONLINE", x: 357, y: 148, size: 15, color: mint, alignment: .right)
        label("tankStatusCaption", "VEHICLE STATE", x: 357, y: 171, size: 8.5, color: muted, alignment: .right)
        label("tankShield", "SHIELD READY", x: 357, y: 115, size: 10, color: cyan, alignment: .right)
        label("tankChaff", "CHAFF 02", x: 357, y: 92, size: 10, color: muted, alignment: .right)
        readinessBar.fillColor = mint
        readinessBar.strokeColor = .clear
        readinessBar.zPosition = 4
        dataRoot.addChild(readinessBar)

        // PANEL 2: primary accuracy + clearly labelled numerator/denominator.
        label("accuracy", "0%", x: 406, y: 151, size: 28, color: cyan)
        label("hits", "HITS 000", x: 406, y: 115, size: 10, color: pale)
        label("shots", "SHOTS 000", x: 406, y: 95, size: 10, color: muted)
        label("eff", "CANNON ACCURACY", x: 406, y: 76, size: 8, color: cyan)
        let ringTrack = SKShapeNode(circleOfRadius: 36)
        ringTrack.position = CGPoint(x: 570, y: 128)
        ringTrack.strokeColor = NSColor(calibratedRed: 0.12, green: 0.36, blue: 0.38, alpha: 1)
        ringTrack.lineWidth = 9
        ringTrack.fillColor = .clear
        ringTrack.zPosition = 3
        dataRoot.addChild(ringTrack)
        hitArc.position = ringTrack.position
        hitArc.strokeColor = mint
        hitArc.lineWidth = 9
        hitArc.lineCap = .round
        hitArc.fillColor = .clear
        hitArc.zPosition = 4
        dataRoot.addChild(hitArc)

        // PANEL 3: large amber heading and a centered moving bearing tape.
        label("heading", "000°", x: 835, y: 155, size: 33, color: amber, alignment: .center)
        label("navCue", "HEADING / TRUE", x: 835, y: 183, size: 8, color: muted, alignment: .center)
        let pointerPath = CGMutablePath()
        pointerPath.move(to: CGPoint(x: 828, y: 117))
        pointerPath.addLine(to: CGPoint(x: 842, y: 117))
        pointerPath.addLine(to: CGPoint(x: 835, y: 105))
        pointerPath.closeSubpath()
        let pointer = SKShapeNode(path: pointerPath)
        pointer.fillColor = amber
        pointer.strokeColor = .clear
        pointer.zPosition = 5
        dataRoot.addChild(pointer)
        compassTicks.strokeColor = cyan
        compassTicks.lineWidth = 1
        compassTicks.zPosition = 4
        dataRoot.addChild(compassTicks)
        compassNumbers.zPosition = 5
        dataRoot.addChild(compassNumbers)
        label("navSpeed", "0.0 MPH", x: 672, y: 82, size: 11, color: mint)
        label("navDirection", "STANDBY", x: 997, y: 82, size: 10, color: muted, alignment: .right)

        // PANEL 4: actual forward terrain samples; grid and tinted profile.
        let grid = CGMutablePath()
        for i in 0...4 {
            let x = CGFloat(1061+i*60)
            line(grid, x, 88, x, 160)
        }
        for i in 0...3 {
            let y = CGFloat(90+i*22)
            line(grid, 1059, y, 1313, y)
        }
        let gridNode = SKShapeNode(path: grid)
        gridNode.strokeColor = cyan.withAlphaComponent(0.17)
        gridNode.lineWidth = 0.8
        gridNode.zPosition = 2
        dataRoot.addChild(gridNode)
        terrainFill.fillColor = mint.withAlphaComponent(0.17)
        terrainFill.strokeColor = .clear
        terrainFill.zPosition = 3
        dataRoot.addChild(terrainFill)
        terrainTrace.strokeColor = mint
        terrainTrace.lineWidth = 2.2
        terrainTrace.fillColor = .clear
        terrainTrace.zPosition = 4
        dataRoot.addChild(terrainTrace)
        label("range", "AHEAD 480 FT", x: 1060, y: 179, size: 9, color: cyan)
        label("elevRange", "LIVE TOPOGRAPHY", x: 1060, y: 76, size: 8.5, color: muted)

        // PANEL 5: sector is dominant; supporting coordinates are legible.
        label("sector", "D-04", x: 1457, y: 157, size: 28, color: cyan, alignment: .center)
        label("sectorCaption", "CURRENT GRID", x: 1457, y: 185, size: 8.5, color: muted, alignment: .center)
        label("elevation", "ELEV +0 FT", x: 1365, y: 116, size: 10.5, color: pale)
        label("positionX", "X +0", x: 1365, y: 96, size: 10, color: mint)
        label("positionZ", "Z +0", x: 1550, y: 96, size: 10, color: mint, alignment: .right)
    }

    func update(_ snapshot: CockpitV5Snapshot, terrain: [Double]) {
        guard installed, snapshot.validate() else { return }
        // The game currently has lives, not a canonical 0-100 hull-health
        // variable. Never represent lives as a fabricated integrity sensor.
        set("tankLives", String(format: "%02d LIVES", snapshot.lives))
        let critical = snapshot.lives <= 1
        set("tankStatus", critical ? "CRITICAL" : "ONLINE")
        labels["tankStatus"]?.fontColor = critical ? amber : mint
        let shield: String
        if snapshot.shieldRemainingSeconds > 0 {
            shield = "SHIELD ACTIVE"
        } else if snapshot.shieldCooldownSeconds > 0 {
            shield = "SHIELD CHARGING"
        } else {
            shield = "SHIELD READY"
        }
        set("tankShield", shield)
        set("tankChaff", String(format: "CHAFF %02d", snapshot.chaffCharges))
        readinessBar.path = CGPath(roundedRect: CGRect(
            x: 249, y: 132, width: 108 * CGFloat(min(1, Double(snapshot.lives)/3)),
            height: 4), cornerWidth: 2, cornerHeight: 2, transform: nil)
        readinessBar.fillColor = critical ? amber : mint

        let ratio = max(0, min(1, snapshot.accuracyPercent/100))
        set("accuracy", String(format: "%.0f%%", snapshot.accuracyPercent))
        set("hits", String(format: "HITS %03d", snapshot.shotsHit))
        set("shots", String(format: "SHOTS %03d", snapshot.shotsFired))
        let arc = CGMutablePath()
        if ratio > 0 {
            arc.addArc(center: .zero, radius: 36,
                       startAngle: -.pi/2,
                       endAngle: -.pi/2 + CGFloat(ratio) * 2 * CGFloat.pi,
                       clockwise: false)
        }
        hitArc.path = arc

        set("heading", String(format: "%03.0f°", snapshot.headingDegrees))
        let mph = abs(snapshot.speedWorldUnitsPerSecond)*3600/1609.344
        set("navSpeed", String(format: "%.1f MPH", mph))
        set("navDirection", mph < 1 ? "STANDBY" :
            (snapshot.speedWorldUnitsPerSecond >= 0 ? "FORWARD" : "REVERSE"))
        let ticks = CGMutablePath()
        compassNumbers.removeAllChildren()
        for offset in -7...7 {
            let bearingOffset = CGFloat(offset)*10
            let x = 835 + bearingOffset*2.15
            let major = offset.isMultiple(of: 3)
            line(ticks, x, 105, x, major ? 119 : 113)
            if major {
                let number = SKLabelNode(fontNamed: "Menlo")
                let angle = (snapshot.headingDegrees + Double(offset)*10 + 720)
                    .truncatingRemainder(dividingBy: 360)
                number.text = String(format: "%03.0f", angle)
                number.fontSize = 9
                number.fontColor = cyan
                number.position = CGPoint(x: x, y: 93)
                number.horizontalAlignmentMode = .center
                number.zPosition = 4
                compassNumbers.addChild(number)
            }
        }
        compassTicks.path = ticks

        if terrain.count >= 2 {
            let low = (terrain.min() ?? 0) - 1
            let high = (terrain.max() ?? 1) + 1
            let span = max(1, high-low)
            let path = CGMutablePath()
            let fill = CGMutablePath()
            fill.move(to: CGPoint(x: 1060, y: 91))
            for (index, value) in terrain.enumerated() {
                let x = 1060 + CGFloat(index)*253/CGFloat(terrain.count-1)
                let y = 95 + CGFloat((value-low)/span)*60
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
                fill.addLine(to: CGPoint(x: x, y: y))
            }
            fill.addLine(to: CGPoint(x: 1313, y: 91))
            fill.closeSubpath()
            terrainTrace.path = path
            terrainFill.path = fill
            set("elevRange", String(format: "LOW %+.0f / HIGH %+.0f FT",
                    low*3.28084, high*3.28084))
        }
        set("sector", snapshot.sector)
        set("elevation", String(format: "ELEV %+.0f FT",
                                snapshot.terrainElevationWorldUnits*3.28084))
        set("positionX", String(format: "X %+.0f", snapshot.playerPosition.x))
        set("positionZ", String(format: "Z %+.0f", snapshot.playerPosition.z))
    }

    func layout(in size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }
        let scale = min(size.width/1600, size.height/900)
        root.setScale(scale)
        root.position = CGPoint(x: (size.width - 1600*scale)/2, y: 12*scale)
        curtain.path = CGPath(rect: CGRect(x: 0, y: 0, width: size.width,
                                           height: 274*scale), transform: nil)
        root.isHidden = false
        curtain.isHidden = false
    }

    func hide() {
        root.isHidden = true
        curtain.isHidden = true
    }
}
