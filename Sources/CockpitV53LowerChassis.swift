import AppKit
import CoreGraphics
import SpriteKit

/// Phase 1 lower cockpit structural skin, drawn as a single coherent assembly.
/// The five recessed openings deliberately contain NO telemetry, so gameplay
/// values remain independently rendered by CockpitV53LowerDeck.
enum CockpitV53LowerChassis {
    struct Opening {
        let x: CGFloat
        let width: CGFloat
        let title: String
    }

    static let openings: [Opening] = [
        .init(x: 24, width: 351, title: "TANK STATUS"),
        .init(x: 383, width: 243, title: "HIT RATIO"),
        .init(x: 634, width: 405, title: "NAV / HEADING"),
        .init(x: 1047, width: 285, title: "TERRAIN PROFILE"),
        .init(x: 1340, width: 236, title: "SECTOR")
    ]

    // Native 1600x256 at 2x resolution, no dependence on a stretched
    // screenshot or any unshipped art files.
    static func texture() -> SKTexture? {
        let pixels = 2
        let width = 1600
        let height = 256
        guard let ctx = CGContext(
            data: nil, width: width * pixels, height: height * pixels,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.scaleBy(x: CGFloat(pixels), y: CGFloat(pixels))

        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
            CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                    components: [r, g, b, a])!
        }
        let black = rgb(0.015, 0.023, 0.028)
        let armor = rgb(0.12, 0.14, 0.148)
        let edge = rgb(0.32, 0.34, 0.34)
        let edgeLight = rgb(0.53, 0.54, 0.52)
        let amber = rgb(1.0, 0.56, 0.105)
        let glass = rgb(0.008, 0.028, 0.032)

        func rounded(_ rect: CGRect, radius: CGFloat) -> CGPath {
            CGPath(roundedRect: rect, cornerWidth: radius,
                   cornerHeight: radius, transform: nil)
        }
        func solid(_ path: CGPath, _ color: CGColor) {
            ctx.addPath(path)
            ctx.setFillColor(color)
            ctx.fillPath()
        }
        func line(_ a: CGPoint, _ b: CGPoint, _ color: CGColor, _ width: CGFloat = 1) {
            ctx.beginPath()
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.setStrokeColor(color)
            ctx.setLineWidth(width)
            ctx.strokePath()
        }
        func gradient(_ rect: CGRect, _ colors: [CGColor], _ stops: [CGFloat],
                      radius: CGFloat = 0, vertical: Bool = true) {
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray, locations: stops
            ) else { return }
            ctx.saveGState()
            ctx.addPath(rounded(rect, radius: radius))
            ctx.clip()
            ctx.drawLinearGradient(gradient,
                start: CGPoint(x: rect.midX, y: vertical ? rect.maxY : rect.midY),
                end: CGPoint(x: rect.midX, y: vertical ? rect.minY : rect.midY),
                options: [])
            ctx.restoreGState()
        }
        func outline(_ rect: CGRect, _ radius: CGFloat, _ color: CGColor,
                     _ width: CGFloat = 1) {
            ctx.addPath(rounded(rect, radius: radius))
            ctx.setStrokeColor(color)
            ctx.setLineWidth(width)
            ctx.strokePath()
        }
        func bolt(_ x: CGFloat, _ y: CGFloat) {
            let circle = CGRect(x: x-3.6, y: y-3.6, width: 7.2, height: 7.2)
            solid(CGPath(ellipseIn: circle, transform: nil), rgb(0.06, 0.08, 0.08))
            ctx.setStrokeColor(edgeLight)
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: circle)
            line(CGPoint(x: x-2, y: y-1.1), CGPoint(x: x+2, y: y+1.1),
                 rgb(0.49, 0.51, 0.49), 0.9)
        }

        // Full width monocoque: graphite steel with stacked bevels.
        gradient(CGRect(x: 7, y: 48, width: 1586, height: 202),
                 [rgb(0.37,0.38,0.37), rgb(0.15,0.17,0.18),
                  rgb(0.055,0.07,0.077),rgb(0.19,0.22,0.23)],
                 [0,0.12,0.72,1],radius: 16)
        outline(CGRect(x: 9, y: 49, width: 1582, height: 198),
                14, edgeLight, 2.2)
        outline(CGRect(x: 15, y: 55, width: 1570, height: 187),
                10, black, 3)
        line(CGPoint(x: 19, y: 236), CGPoint(x: 1580, y: 236),
             edgeLight, 1.4)

        // Main upper armor beam is a SINGLE connected section, not triangles
        // or decorative spikes above each module.
        gradient(CGRect(x: 16, y: 226, width: 1568, height: 20),
                 [rgb(0.37,0.38,0.37),rgb(0.15,0.17,0.18),rgb(0.09,0.11,0.12)],
                 [0,0.38,1], radius: 5)
        line(CGPoint(x: 28, y: 245), CGPoint(x: 1570, y: 245),
             rgb(0.60,0.59,0.53),1)
        line(CGPoint(x: 29, y: 225), CGPoint(x: 1569, y: 225),black,2)

        // A deliberate five-bay instrument recess. Opening frame edges are
        // made specifically for short/wide lower displays, with no stretching.
        for opening in openings {
            let x = opening.x
            let w = opening.width
            let outer = CGRect(x: x, y: 62, width: w, height: 156)
            gradient(outer,
                     [rgb(0.40,0.41,0.39),rgb(0.16,0.18,0.19),
                      rgb(0.09,0.11,0.12),rgb(0.27,0.29,0.29)],
                     [0,0.12,0.83,1], radius: 12)
            outline(outer.insetBy(dx: 1,dy: 1),11, edgeLight, 1.3)
            let recess = outer.insetBy(dx: 10, dy: 10)
            solid(rounded(recess, radius: 7), rgb(0.008,0.015,0.018))
            outline(recess,7,rgb(0.045,0.06,0.067),3)
            let screen = CGRect(x: x+18, y: 79, width: w-36, height: 120)
            gradient(screen,
                     [rgb(0.017,0.073,0.075), glass, rgb(0.008,0.018,0.022)],
                     [0,0.20,1], radius: 4)
            outline(screen,4,rgb(0.08,0.27,0.26),1.1)
            line(CGPoint(x: x+20, y: 202),CGPoint(x: x+w-20, y: 202),
                 rgb(0.28,0.42,0.40,0.7),0.8)
            line(CGPoint(x: x+17, y: 82),CGPoint(x: x+w-17, y: 82),
                 rgb(0.16,0.21,0.21),1)

            // Top and bottom armored light apertures repeat the upper theme
            // without repeating or warping an upper bezel bitmap.
            let barWidth = min(w*0.33, 118.0)
            let lightX = x+(w-barWidth)/2
            gradient(CGRect(x: lightX-6, y: 213, width: barWidth+12, height: 10),
                     [rgb(0.30,0.25,0.14),rgb(0.07,0.07,0.07)],
                     [0,1], radius: 4)
            gradient(CGRect(x: lightX, y: 216, width: barWidth, height: 3),
                     [rgb(1,0.73,0.30),amber,rgb(0.57,0.22,0.04)],
                     [0,0.5,1],radius: 1.4,vertical:false)
            solid(rounded(CGRect(x: x+w*0.38, y: 65,
                                  width: w*0.24, height: 4),radius: 1),
                  rgb(0.44,0.29,0.08))
            for xBolt in [x+11, x+w-11] {
                for yBolt in [73.0,208.0] { bolt(xBolt,yBolt) }
            }
            // Flush end-cap braces; never rise into the battlefield.
            for px in [x+14, x+w-18] {
                gradient(CGRect(x: px, y: 88, width: 4, height: 31),
                         [rgb(0.55,0.24,0.045),amber,rgb(0.19,0.11,0.04)],
                         [0,0.45,1],radius: 1)
            }
        }

        // Between-bay structural bridges; a continuous piece of hardware.
        for gapX in [379.0,630.0,1043.0,1336.0] {
            gradient(CGRect(x: gapX-4,y: 68,width: 8,height: 145),
                     [rgb(0.30,0.32,0.32),rgb(0.07,0.09,0.10)],
                     [0,1],radius: 2,vertical:false)
            bolt(gapX, 235)
        }

        // The physical control rail is integral to the assembly and sits
        // fully ABOVE the game help footer.
        gradient(CGRect(x: 10, y: 3, width: 1580, height: 49),
                 [rgb(0.36,0.37,0.36),rgb(0.11,0.12,0.13),
                  rgb(0.055,0.066,0.07)], [0,0.36,1],radius: 9)
        outline(CGRect(x: 10,y: 3,width: 1580,height: 49),
                9,edge,1.5)
        let caps: [(CGFloat,CGFloat)] = [
            (50,208), (269,206),(486,255),(752,208),
            (971,194),(1176,169),(1357,181)
        ]
        for (x,w) in caps {
            gradient(CGRect(x: x,y: 11,width: w,height: 33),
                     [rgb(0.25,0.28,0.29),rgb(0.045,0.060,0.065),
                      rgb(0.014,0.031,0.037)], [0,0.2,1],radius: 5)
            outline(CGRect(x:x,y:11,width:w,height:33),5,edgeLight,1.0)
            solid(rounded(CGRect(x:x+8,y:19,width:3,height:17),radius:1),amber)
        }
        // Vent grilles and fasteners at the far ends echo the approved
        // screenshot's industrial bottom chassis.
        for baseX in [19.0,1550.0] {
            for i in 0..<5 {
                let x = baseX + CGFloat(i)*5
                line(CGPoint(x:x,y:14),CGPoint(x:x+8,y:34),
                     rgb(0.055,0.06,0.066),2.5)
            }
        }
        for x in [24.0,1576.0] { bolt(x,27) }
        guard let cgImage = ctx.makeImage() else { return nil }
        let texture = SKTexture(cgImage: cgImage)
        texture.filteringMode = .linear
        return texture
    }
}
