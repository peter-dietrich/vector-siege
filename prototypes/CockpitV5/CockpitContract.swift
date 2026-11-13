// Vector Siege v5.0 — isolated cockpit integration prototype.
// Not imported by BattlefieldScene until the design proof is approved.
// Source of truth: docs/cockpit_v5/asset_manifest.json.
import Foundation
import CoreGraphics

enum CockpitV5Contract {
    struct Frame: Decodable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }
    struct DesignSpace: Decodable {
        let width: Double
        let height: Double
        enum CodingKeys: String, CodingKey {
            case width, height
        }
    }
    struct Screen: Decodable {
        let id: String
        let title: String
        let rect: Frame
        let dynamicFields: [String]
        let assetFrame: String
        enum CodingKeys: String, CodingKey {
            case id, title, rect
            case dynamicFields = "dynamic_fields"
            case assetFrame = "asset_frame"
        }
    }
    struct Artwork: Decodable {
        let id: String
        let path: String
        let rect: Frame?
        let pixelScale: Int
        let dimensionsPx: [Int]
        let layer: Int
        let containsText: Bool
        enum CodingKeys: String, CodingKey {
            case id, path, rect, layer
            case pixelScale = "pixel_scale"
            case dimensionsPx = "dimensions_px"
            case containsText = "contains_text"
        }
    }
    struct Manifest: Decodable {
        let schemaVersion: String
        let designSpace: DesignSpace
        let screens: [Screen]
        let artwork: [Artwork]
        enum CodingKeys: String, CodingKey {
            case screens, artwork
            case schemaVersion = "schema_version"
            case designSpace = "design_space"
        }
    }
    struct Projection {
        let scale: CGFloat
        let left: CGFloat
        let bottom: CGFloat
        let designHeight: CGFloat

        /// SpriteKit coordinates are bottom-left. Source manifest uses top-left.
        func frame(_ rect: Frame) -> CGRect {
            CGRect(x: left + CGFloat(rect.x) * scale,
                   y: bottom + (designHeight - CGFloat(rect.y + rect.height)) * scale,
                   width: CGFloat(rect.width) * scale,
                   height: CGFloat(rect.height) * scale)
        }
    }

    static func load(_ data: Data) throws -> Manifest {
        try JSONDecoder().decode(Manifest.self, from: data)
    }

    static func project(design: DesignSpace, into view: CGSize) -> Projection {
        let scale = min(view.width / CGFloat(design.width),
                        view.height / CGFloat(design.height))
        let left = (view.width - CGFloat(design.width) * scale) * 0.5
        let bottom = (view.height - CGFloat(design.height) * scale) * 0.5
        return Projection(scale: scale, left: left, bottom: bottom,
                          designHeight: CGFloat(design.height))
    }

    static func verify(_ manifest: Manifest) throws {
        enum Problem: Error { case badDimension, badScreenCount, badArt, missingBezel }
        guard manifest.designSpace.width > 0, manifest.designSpace.height > 0
        else { throw Problem.badDimension }
        guard manifest.screens.count == 4,
              Set(manifest.screens.map(\.id)).count == 4
        else { throw Problem.badScreenCount }
        let assetNames = Set(manifest.artwork.map(\.id))
        for screen in manifest.screens {
            guard assetNames.contains(screen.assetFrame),
                  screen.rect.width > 0, screen.rect.height > 0,
                  !screen.dynamicFields.isEmpty else { throw Problem.missingBezel }
        }
        for artwork in manifest.artwork {
            guard !artwork.containsText, artwork.pixelScale == 2,
                  artwork.dimensionsPx.count == 2 else { throw Problem.badArt }
            if let rect = artwork.rect {
                guard artwork.dimensionsPx[0] == Int(rect.width * 2),
                      artwork.dimensionsPx[1] == Int(rect.height * 2)
                else { throw Problem.badArt }
            }
        }
    }
}
