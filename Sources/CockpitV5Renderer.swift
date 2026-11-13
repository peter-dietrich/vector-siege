import SpriteKit
import AppKit

/// Vector Siege v5.4 independently composed native cockpit.
/// No rasterized master screenshot, no fabricated vehicle diagnostics.
/// Existing rear camera remains the real scene renderer, reparented into its new viewport.
final class CockpitV5Renderer {
    private weak var scene: SKScene?
    private let root = SKNode()
    private var readouts: [String: SKLabelNode] = [:]
    private let contactsLayer = SKNode()
    private let gaugeLayer = SKNode()
    private let rearWindow = CGRect(x: 790, y: 900 - 316, width: 310, height: 198)
    private let mapCenter = CGPoint(x: 574, y: 900 - 213)
    private let mapRadius: CGFloat = 95
    private let white = NSColor(calibratedRed: 0.87, green: 0.91, blue: 0.91, alpha: 1)
    private let dim = NSColor(calibratedRed: 0.50, green: 0.63, blue: 0.65, alpha: 1)
    private let cyan = NSColor(calibratedRed: 0.39, green: 0.80, blue: 0.84, alpha: 1)
    private let amber = NSColor(calibratedRed: 1, green: 0.65, blue: 0.28, alpha: 1)
    private let dark = NSColor(calibratedRed: 0.016, green: 0.026, blue: 0.033, alpha: 1)

    init(scene: SKScene) {
        self.scene = scene
        root.zPosition = 40
        scene.addChild(root)
        compose()
    }

    private func rectangle(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x, y: 900 - top - h, width: w, height: h)
    }

    @discardableResult
    private func plate(_ frame: CGRect, fill: NSColor, stroke: NSColor, radius: CGFloat = 8,
                       thickness: CGFloat = 1, z: CGFloat = 0) -> SKShapeNode {
        let shape = SKShapeNode(rect: frame, cornerRadius: radius)
        shape.fillColor = fill
        shape.strokeColor = stroke
        shape.lineWidth = thickness
        shape.zPosition = z
        root.addChild(shape)
        return shape
    }

    @discardableResult
    private func label(_ key: String, text: String, x: CGFloat, top: CGFloat,
                       size: CGFloat = 15, color: NSColor? = nil,
                       alignment: SKLabelHorizontalAlignmentMode = .left) -> SKLabelNode {
        let node = SKLabelNode(fontNamed: "Menlo-Bold")
        node.text = text
        node.fontColor = color ?? white
        node.fontSize = size
        node.horizontalAlignmentMode = alignment
        node.verticalAlignmentMode = .center
        node.position = CGPoint(x: x, y: 900 - top)
        node.zPosition = 15
        root.addChild(node)
        readouts[key] = node
        return node
    }

    private func line(_ a: CGPoint, _ b: CGPoint, color: NSColor, width: CGFloat = 1, z: CGFloat = 4) {
        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: b)
        let shape = SKShapeNode(path: path)
        shape.strokeColor = color
        shape.lineWidth = width
        shape.zPosition = z
        root.addChild(shape)
    }

    private func compose() {
        // Deliberately restrained fallback chassis. Individual approved art
        // replaces these plates later; nothing dynamic is baked into artwork.
        plate(rectangle(0, 0, 1600, 350), fill: NSColor(calibratedWhite: 0.055, alpha: 1),
              stroke: .clear, radius: 0)
        plate(rectangle(0, 748, 1600, 152), fill: NSColor(calibratedWhite: 0.065, alpha: 1),
              stroke: .clear, radius: 0)
        plate(rectangle(15, 8, 1570, 55), fill: NSColor(calibratedWhite: 0.10, alpha: 1),
              stroke: NSColor(calibratedWhite: 0.22, alpha: 1))
        label("headingTop", text: "VECTOR SIEGE    /    TACTICAL COMMAND", x: 34, top: 36, size: 18)
        label("modeTop", text: "REALISTIC COCKPIT  /  V5.4", x: 1560, top: 36,
              size: 13, color: cyan, alignment: .right)
        line(CGPoint(x: 24, y: 900 - 66), CGPoint(x: 1576, y: 900 - 66),
             color: NSColor(calibratedWhite: 0.29, alpha: 1), width: 2)

        let panels: [(String, CGRect)] = [
            ("01  FIRE CONTROL", rectangle(40, 94, 326, 231)),
            ("02  TACTICAL BATTLESPACE", rectangle(411, 94, 326, 231)),
            ("03  REAR OPTICS", rectangle(782, 94, 326, 231)),
            ("04  VEHICLE SYSTEMS", rectangle(1153, 94, 407, 231))
        ]
        for (title, frame) in panels {
            plate(frame.insetBy(dx: -9, dy: -10), fill: NSColor(calibratedWhite: 0.105, alpha: 1),
                  stroke: NSColor(calibratedWhite: 0.31, alpha: 1), radius: 12, thickness: 2)
            plate(frame, fill: dark, stroke: NSColor(calibratedRed: 0.24, green: 0.38,
                                                     blue: 0.41, alpha: 1), radius: 5)
            label("title_" + title, text: title, x: frame.minX + 14,
                  top: 900 - frame.maxY + 20, size: 11, color: cyan)
            line(CGPoint(x: frame.minX + 12, y: frame.maxY - 37),
                 CGPoint(x: frame.maxX - 12, y: frame.maxY - 37),
                 color: NSColor(calibratedWhite: 0.20, alpha: 1))
        }

        // FIRE CONTROL: only actual targeting solution and real weapon data.
        label("fireHeading", text: "HDG —", x: 57, top: 159, size: 23, color: white)
        label("fireSpeed", text: "SPD —", x: 352, top: 159, size: 18, color: cyan, alignment: .right)
        label("fireTarget", text: "NO TARGET", x: 57, top: 205, size: 16, color: amber)
        label("fireRange", text: "RNG —", x: 57, top: 243, size: 13, color: dim)
        label("fireBearing", text: "BRG —", x: 354, top: 243, size: 13, color: dim, alignment: .right)
        label("fireAmmo", text: "AMMO —", x: 57, top: 294, size: 13, color: cyan)
        label("fireReload", text: "READY", x: 354, top: 294, size: 13, color: amber, alignment: .right)

        // Map geometry is driven by contacts and player position, not an image.
        let mapPath = CGMutablePath()
        for fraction in [CGFloat(1.0/3.0), CGFloat(2.0/3.0), CGFloat(1)] {
            let r = mapRadius * fraction
            mapPath.addEllipse(in: CGRect(x: mapCenter.x - r, y: mapCenter.y - r,
                                          width: r * 2, height: r * 2))
        }
        mapPath.move(to: CGPoint(x: mapCenter.x - mapRadius, y: mapCenter.y))
        mapPath.addLine(to: CGPoint(x: mapCenter.x + mapRadius, y: mapCenter.y))
        mapPath.move(to: CGPoint(x: mapCenter.x, y: mapCenter.y - mapRadius))
        mapPath.addLine(to: CGPoint(x: mapCenter.x, y: mapCenter.y + mapRadius))
        let mapGrid = SKShapeNode(path: mapPath)
        mapGrid.strokeColor = NSColor(calibratedRed: 0.20, green: 0.39, blue: 0.40, alpha: 0.75)
        mapGrid.lineWidth = 1
        mapGrid.zPosition = 4
        root.addChild(mapGrid)
        contactsLayer.zPosition = 8
        root.addChild(contactsLayer)
        label("mapRange", text: "RANGE 165", x: 722, top: 304,
              size: 11, color: dim, alignment: .right)

        // The actual rear camera is inserted by render(...). No fake imagery.
        label("rearBearing", text: "REAR 180°", x: 1093, top: 304,
              size: 12, color: cyan, alignment: .right)

        label("systemsWave", text: "WAVE —", x: 1170, top: 155, size: 18)
        label("systemsScore", text: "SCORE —", x: 1542, top: 155,
              size: 17, alignment: .right)
        label("systemsLives", text: "LIVES —", x: 1170, top: 195, size: 13, color: dim)
        label("systemsBest", text: "BEST —", x: 1542, top: 195,
              size: 13, color: dim, alignment: .right)
        label("systemsShield", text: "SHIELD —", x: 1170, top: 236, size: 14, color: cyan)
        label("systemsChaff", text: "CHAFF —", x: 1542, top: 236,
              size: 14, color: amber, alignment: .right)
        label("systemsAmmo", text: "AMMO —", x: 1170, top: 288, size: 15)
        label("systemsDifficulty", text: "—", x: 1542, top: 288,
              size: 12, color: dim, alignment: .right)

        // Lower console remains physically separate from the battlefield.
        plate(rectangle(24, 757, 1552, 131),
              fill: NSColor(calibratedWhite: 0.086, alpha: 1),
              stroke: NSColor(calibratedWhite: 0.32, alpha: 1), radius: 11, thickness: 2)
        for x in [390.0, 780.0, 1155.0] {
            line(CGPoint(x: x, y: 900 - 772),
                 CGPoint(x: x, y: 900 - 875),
                 color: NSColor(calibratedWhite: 0.25, alpha: 1))
        }
        label("consoleVehicleTitle", text: "VEHICLE / STATUS", x: 45, top: 783, size: 12, color: cyan)
        label("consoleVehicle", text: "WAVE —  /  LIVES —", x: 45, top: 816, size: 17)
        label("consoleDefense", text: "SHIELD —", x: 45, top: 850, size: 13, color: amber)
        label("consoleNavTitle", text: "NAVIGATION", x: 412, top: 783, size: 12, color: cyan)
        label("consoleHeading", text: "HEADING —", x: 412, top: 816, size: 18)
        label("consoleSpeed", text: "SPEED —", x: 412, top: 849, size: 13)
        label("consoleThreatTitle", text: "THREAT / FIRE CONTROL", x: 805, top: 783, size: 12, color: cyan)
        label("consoleThreat", text: "CONTACTS —", x: 805, top: 816, size: 17)
        label("consoleAccuracy", text: "HIT —", x: 805, top: 849, size: 13)
        label("consoleSectorTitle", text: "POSITION", x: 1181, top: 783, size: 12, color: cyan)
        label("consoleSector", text: "SECTOR —", x: 1181, top: 816, size: 18)
        label("consoleElevation", text: "ELEV —", x: 1181, top: 849, size: 13)
        gaugeLayer.zPosition = 8
        root.addChild(gaugeLayer)
    }

    private func set(_ key: String, _ value: String) {
        readouts[key]?.text = value
    }

    private func glyph(_ at: CGPoint, radius: CGFloat, color: NSColor, filled: Bool) -> SKShapeNode {
        let node = SKShapeNode(circleOfRadius: radius)
        node.position = at
        node.fillColor = filled ? color : .clear
        node.strokeColor = color
        node.lineWidth = 1.5
        return node
    }

    func render(_ snapshot: CockpitV5Snapshot, size: CGSize, rearView: SKCropNode) {
        guard size.width > 0 && size.height > 0 else { return }
        let scale = min(size.width / 1600, size.height / 900)
        root.setScale(scale)
        root.position = CGPoint(x: (size.width - 1600 * scale) / 2,
                                y: (size.height - 900 * scale) / 2)
        root.isHidden = false

        let v = snapshot.screenReadouts
        set("fireHeading", "HDG " + (v.fireControl["heading_deg"] ?? "—") + "°")
        set("fireSpeed", "SPD " + (v.fireControl["speed"] ?? "—"))
        set("fireTarget", v.fireControl["target_cover"] ?? "NO TARGET")
        set("fireRange", "RNG " + (v.fireControl["target_distance"] ?? "—"))
        set("fireBearing", "BRG " + (v.fireControl["target_bearing"] ?? "—") + "°")
        set("fireAmmo", "AMMO " + String(snapshot.roundsRemaining) + "/" + String(snapshot.magazineCapacity))
        set("fireReload", snapshot.reloadRemainingSeconds > 0
            ? String(format: "RELOAD %.1fs", snapshot.reloadRemainingSeconds) : "READY")
        set("rearBearing", String(format: "REAR %.0f° / EO-IR", (snapshot.headingDegrees + 180).truncatingRemainder(dividingBy: 360)))
        set("systemsWave", String(format: "WAVE %02d", snapshot.wave))
        set("systemsScore", String(format: "SCORE %06d", snapshot.score))
        set("systemsLives", String(format: "LIVES %02d", snapshot.lives))
        set("systemsBest", String(format: "BEST %06d", snapshot.bestScore))
        set("systemsShield", "SHIELD " + (v.vehicleSystems["shield_status"] ?? "—"))
        set("systemsChaff", "CHAFF " + String(snapshot.chaffCharges))
        set("systemsAmmo", "AMMO " + String(snapshot.roundsRemaining) + "/" + String(snapshot.magazineCapacity))
        set("systemsDifficulty", snapshot.difficultyLabel.uppercased())
        set("consoleVehicle", String(format: "WAVE %02d   /   LIVES %02d", snapshot.wave, snapshot.lives))
        set("consoleDefense", "SHIELD " + (v.vehicleSystems["shield_status"] ?? "—"))
        set("consoleHeading", String(format: "HDG %03.0f°", snapshot.headingDegrees))
        set("consoleSpeed", String(format: "SPEED %+.1f", snapshot.speedWorldUnitsPerSecond))
        let hostile = snapshot.contacts.filter { $0.visible }.count
        set("consoleThreat", "CONTACTS " + String(hostile))
        set("consoleAccuracy", String(format: "HIT %.0f%%   /   SHOTS %d", snapshot.accuracyPercent, snapshot.shotsFired))
        set("consoleSector", "SECTOR " + snapshot.sector)
        set("consoleElevation", String(format: "ELEV %+.1f", snapshot.terrainElevationWorldUnits))

        contactsLayer.removeAllChildren()
        // Track-up map: each contact is relative to the player, range 165.
        for contact in snapshot.contacts where contact.visible {
            let dx = contact.position.x - snapshot.playerPosition.x
            let dz = contact.position.z - snapshot.playerPosition.z
            let right = dx * cos(snapshot.headingRadians) - dz * sin(snapshot.headingRadians)
            let forward = dx * sin(snapshot.headingRadians) + dz * cos(snapshot.headingRadians)
            let range = hypot(right, forward)
            guard range <= 165 else { continue }
            let pt = CGPoint(x: mapCenter.x + CGFloat(right / 165) * mapRadius,
                             y: mapCenter.y + CGFloat(forward / 165) * mapRadius)
            let isAir = contact.kind == .drone || contact.kind == .fighter || contact.kind == .saucer
            let symbol = glyph(pt, radius: contact.isPrimaryTarget ? 6 : 3.5,
                               color: contact.isPrimaryTarget ? amber : (isAir ? cyan : white),
                               filled: !isAir)
            contactsLayer.addChild(symbol)
        }
        contactsLayer.addChild(glyph(mapCenter, radius: 5, color: cyan, filled: true))
        gaugeLayer.removeAllChildren()
        let track = CGRect(x: 1170, y: 900 - 311, width: 368, height: 4)
        let background = SKShapeNode(rect: track, cornerRadius: 2)
        background.fillColor = NSColor(calibratedWhite: 0.23, alpha: 1)
        background.strokeColor = .clear
        gaugeLayer.addChild(background)
        let fraction = CGFloat(snapshot.ammunitionFraction)
        if fraction > 0 {
            let fill = SKShapeNode(rect: CGRect(x: track.minX, y: track.minY,
                                                 width: track.width * fraction, height: track.height),
                                   cornerRadius: 2)
            fill.fillColor = cyan
            fill.strokeColor = .clear
            gaugeLayer.addChild(fill)
        }

        // Preserve the real existing rear camera; never replace it with
        // a bitmap or pretend an unavailable camera texture is live.
        if rearView.parent !== root {
            rearView.removeFromParent()
            root.addChild(rearView)
        }
        let bounds = rearView.maskNode?.calculateAccumulatedFrame() ?? CGRect(x: 0, y: 0, width: 300, height: 180)
        let width = max(1, bounds.width)
        let height = max(1, bounds.height)
        let rearScale = min(rearWindow.width / width, rearWindow.height / height)
        rearView.setScale(rearScale)
        rearView.position = CGPoint(x: rearWindow.minX, y: rearWindow.minY)
        rearView.zPosition = 9
    }

    func hide() {
        root.isHidden = true
    }
}
