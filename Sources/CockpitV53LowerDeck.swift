import AppKit
import SpriteKit

/// Clean cockpit visual gate: one authoritative approved shell asset.
/// No legacy procedural frames, synthetic instrumentation, or duplicate rails.
/// The five instruments will be layered separately after shell sign-off.
final class CockpitV53LowerDeck {
    static let artworkName = "VectorSiege_Clean_Shell_Approved.png"
    private let root = SKNode()
    private let curtain = SKShapeNode()
    private var artworkFound = false

    init(scene: SKScene) {
        curtain.zPosition = 37.8
        curtain.fillColor = NSColor(calibratedRed: 0.012, green: 0.018, blue: 0.020, alpha: 1)
        curtain.strokeColor = .clear
        scene.addChild(curtain)

        root.zPosition = 38
        scene.addChild(root)

        let paths = [
            Bundle.main.resourceURL?.appendingPathComponent("CockpitV5").appendingPathComponent(Self.artworkName),
            Bundle.main.resourceURL?.appendingPathComponent("Resources/CockpitV5").appendingPathComponent(Self.artworkName),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources/CockpitV5")
                .appendingPathComponent(Self.artworkName)
        ].compactMap { $0 }
        if let url = paths.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
           let img = NSImage(contentsOf: url) {
            let sprite = SKSpriteNode(texture: SKTexture(image: img))
            sprite.position = CGPoint(x: 800, y: 128)
            sprite.size = CGSize(width: 1600, height: 256)
            root.addChild(sprite)
            artworkFound = true
        } else {
            // Fail visibly instead of silently reverting to obsolete geometry.
            let warning = SKLabelNode(fontNamed: "Menlo-Bold")
            warning.text = "COCKPIT SHELL ART MISSING — INSTALL APPROVED IMAGE"
            warning.fontSize = 19
            warning.fontColor = .systemOrange
            warning.position = CGPoint(x: 800, y: 135)
            warning.horizontalAlignmentMode = .center
            root.addChild(warning)
        }
    }

    // Intentionally empty for the visual shell approval gate. The active game
    // still computes and publishes data, but we do not pretend an unfinished
    // instrument set is ready for user acceptance.
    func update(_ snapshot: CockpitV5Snapshot, terrain: [Double]) {
        _ = snapshot
        _ = terrain
    }

    func layout(in size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }
        let scale = min(size.width / 1600, size.height / 900)
        root.setScale(scale)
        root.position = CGPoint(x: (size.width - 1600 * scale) / 2,
                                y: 12 * scale)
        curtain.path = CGPath(rect: CGRect(x: 0, y: 0, width: size.width,
                                         height: 274 * scale), transform: nil)
        root.isHidden = false
        curtain.isHidden = false
    }

    func hide() {
        root.isHidden = true
        curtain.isHidden = true
    }
}
