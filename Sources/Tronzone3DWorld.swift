import AppKit
import SceneKit
import SpriteKit

/// A real depth-buffered 3D world embedded behind the existing SpriteKit HUD.
/// Simulation, AI, collisions, weapons, and radar remain in BattlefieldScene.
/// World coordinates are mirrored in Z because SceneKit cameras look toward -Z.
final class Tronzone3DWorld {
    struct Site {
        let x: Double
        let z: Double
        let size: Double
        let kind: Int
    }
    struct Contact {
        let id: Int
        let x: Double
        let z: Double
        let heading: Double
        let kind: Int
        let altitude: Double
    }

    let viewport: SK3DNode
    private let scene = SCNScene()
    private let cameraNode = SCNNode()
    private let terrainRoot = SCNNode()
    private let structureRoot = SCNNode()
    private let backdropRoot = SCNNode()
    private let actorRoot = SCNNode()
    private let sun = SCNNode()
    private var contactNodes: [Int: SCNNode] = [:]
    private var contactKinds: [Int: Int] = [:]
    private var terrainTexture: CGImage?
    private var terrainOrigin = (Int.min, Int.min)
    private let groundMaterial = Tronzone3DWorld.material(0.018, 0.075, 0.047, roughness: 0.38)
    private let rockMaterial = Tronzone3DWorld.material(0.075, 0.13, 0.13, roughness: 0.85)
    private let bunkerMaterial = Tronzone3DWorld.material(0.045, 0.11, 0.095, roughness: 0.42)
    private let pineMaterial = Tronzone3DWorld.material(0.024, 0.16, 0.08, roughness: 0.85)
    private let hullMaterial = Tronzone3DWorld.material(0.075, 0.16, 0.12, roughness: 0.31)
    private let enemyMaterial = Tronzone3DWorld.material(0.18, 0.08, 0.075, roughness: 0.37)
    private let trim = Tronzone3DWorld.material(0.23, 0.88, 0.31, roughness: 0.2, glow: 0.36)
    private let redTrim = Tronzone3DWorld.material(0.95, 0.16, 0.09, roughness: 0.22, glow: 0.5)

    private static func material(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
                                 roughness: CGFloat, glow: CGFloat = 0) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
        material.metalness.contents = NSNumber(value: 0.33)
        material.roughness.contents = NSNumber(value: Double(roughness))
        if glow > 0 {
            material.emission.contents = NSColor(calibratedRed: r * glow,
                                                  green: g * glow,
                                                  blue: b * glow, alpha: 1)
        }
        material.isDoubleSided = true
        return material
    }

    init(viewportSize: CGSize) {
        viewport = SK3DNode(viewportSize: viewportSize)
        viewport.zPosition = 3.75
        viewport.scnScene = scene
        viewport.autoenablesDefaultLighting = false

        scene.background.contents = Self.makeSkyTexture()
        terrainTexture = Self.makeGroundTexture()
        if let texture = terrainTexture {
            groundMaterial.diffuse.contents = texture
            groundMaterial.diffuse.wrapS = .repeat
            groundMaterial.diffuse.wrapT = .repeat
            groundMaterial.diffuse.mipFilter = .linear
        }
        scene.fogColor = NSColor(calibratedRed: 0.075, green: 0.21,
                                blue: 0.11, alpha: 1)
        scene.fogStartDistance = 78
        scene.fogEndDistance = 345
        scene.fogDensityExponent = 0.85

        scene.rootNode.addChildNode(backdropRoot)
        scene.rootNode.addChildNode(terrainRoot)
        scene.rootNode.addChildNode(structureRoot)
        buildMountainBackdrop()
        scene.rootNode.addChildNode(actorRoot)
        let camera = SCNCamera()
        camera.zNear = 0.4
        camera.zFar = 400
        camera.fieldOfView = 48
        // SK3DNode composites SceneKit into SpriteKit's render pass. Camera
        // HDR/bloom can select a SceneKit post-processing render pipeline
        // without the host depth32Float_stencil8 attachment, triggering a
        // Metal validation assertion. Keep the initial embedded render path
        // single-pass; test advanced effects only after moving to SCNView.
        camera.wantsHDR = false
        camera.bloomIntensity = 0
        camera.bloomThreshold = 1
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        viewport.pointOfView = cameraNode

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = NSColor(calibratedRed: 0.20, green: 0.42,
                                blue: 0.31, alpha: 1)
        ambient.intensity = 460
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let sunlight = SCNLight()
        sunlight.type = .directional
        sunlight.color = NSColor(calibratedRed: 0.66, green: 1,
                                 blue: 0.69, alpha: 1)
        sunlight.intensity = 1150
        sunlight.castsShadow = true
        sunlight.shadowMode = .deferred
        sunlight.shadowSampleCount = 8
        sunlight.shadowRadius = 4
        sun.light = sunlight
        sun.eulerAngles = SCNVector3(-0.88, -0.65, 0)
        scene.rootNode.addChildNode(sun)
    }


    // Source-controlled, deterministic runtime material artwork. No local
    // bitmap dependencies and no translucent geometry masquerading as ground.
    private static func makeSkyTexture() -> CGImage? {
        guard let ctx = CGContext(data:nil,width:4,height:512,
                                  bitsPerComponent:8,bytesPerRow:0,
                                  space:CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),
                colors:[
                    NSColor(calibratedRed:0.14,green:0.27,blue:0.18,alpha:1).cgColor,
                    NSColor(calibratedRed:0.048,green:0.11,blue:0.076,alpha:1).cgColor,
                    NSColor(calibratedRed:0.008,green:0.018,blue:0.022,alpha:1).cgColor
                ] as CFArray,locations:[0,0.48,1]) else { return nil }
        ctx.drawLinearGradient(gradient,start:CGPoint(x:0,y:0),
                               end:CGPoint(x:0,y:512),options:[])
        return ctx.makeImage()
    }

    private static func makeGroundTexture() -> CGImage? {
        let width = 256, height = 256
        guard let ctx = CGContext(data:nil,width:width,height:height,
                                  bitsPerComponent:8,bytesPerRow:0,
                                  space:CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.setFillColor(NSColor(calibratedRed:0.045,green:0.13,
                                 blue:0.08,alpha:1).cgColor)
        ctx.fill(CGRect(x:0,y:0,width:width,height:height))
        // Fine strata, granular material variation and irregular fissures.
        // The terrain mesh supplies real lighting, shadows and depth.
        var state: UInt64 = 0x49F3C1A7
        func next() -> CGFloat {
            state = state &* 2862933555777941757 &+ 3037000493
            return CGFloat(state >> 32) / CGFloat(UInt32.max)
        }
        for _ in 0..<3400 {
            let x=next()*CGFloat(width), y=next()*CGFloat(height)
            let bright=next()>0.72
            ctx.setFillColor(NSColor(calibratedRed:bright ? 0.14 : 0.022,
                                     green:bright ? 0.25 : 0.073,
                                     blue:bright ? 0.15 : 0.058,
                                     alpha:0.42).cgColor)
            ctx.fill(CGRect(x:x,y:y,width:1+next()*2,height:0.6+next()))
        }
        for _ in 0..<23 {
            let x=next()*255, y=next()*255
            ctx.setStrokeColor(NSColor(calibratedRed:0.012,green:0.036,
                                       blue:0.026,alpha:0.65).cgColor)
            ctx.setLineWidth(0.7+next())
            ctx.move(to:CGPoint(x:x,y:y))
            ctx.addLine(to:CGPoint(x:x+7+next()*31,y:y-4-next()*12))
            ctx.strokePath()
        }
        return ctx.makeImage()
    }

    private func box(_ width: CGFloat, _ height: CGFloat, _ length: CGFloat,
                     material: SCNMaterial, chamfer: CGFloat = 0.05) -> SCNNode {
        let mesh = SCNBox(width: width, height: height, length: length,
                          chamferRadius: min(chamfer, width * 0.18, height * 0.18))
        mesh.firstMaterial = material
        let node = SCNNode(geometry: mesh)
        node.castsShadow = true
        return node
    }


    private func buildMountainBackdrop() {
        // World-anchored physical terrain, not a static panoramic screenshot.
        // Two depth-sorted ridge walls give the fog and directional lighting
        // a real surface to shade beyond the combat area.
        for layer in 0..<2 {
            let samples = 72
            let radius = layer == 0 ? 215.0 : 305.0
            let low = layer == 0 ? 0.0 : 6.0
            var vertices: [SCNVector3] = []
            var indices: [Int32] = []
            for i in 0...samples {
                let a = Double(i) * 2 * Double.pi / Double(samples)
                let ripple = abs(sin(a*9.0+Double(layer)*0.7))
                let spire = pow(abs(sin(a*16.0+0.45)), 12)
                let peak = 18.0 + ripple*20.0 + spire*40.0
                let near = radius - 33
                let far = radius + 33
                vertices.append(SCNVector3(Float(cos(a)*near),
                                           Float(low),
                                           Float(-sin(a)*near)))
                vertices.append(SCNVector3(Float(cos(a)*radius),
                                           Float(peak),
                                           Float(-sin(a)*radius)))
                vertices.append(SCNVector3(Float(cos(a)*far),
                                           Float(low),
                                           Float(-sin(a)*far)))
                if i < samples {
                    let base = Int32(i*3)
                    indices.append(contentsOf:[
                        base,base+1,base+3,
                        base+1,base+4,base+3,
                        base+1,base+2,base+4,
                        base+2,base+5,base+4])
                }
            }
            let geometry = SCNGeometry(sources:[SCNGeometrySource(vertices:vertices)],
                                       elements:[SCNGeometryElement(
                                         indices:indices, primitiveType:.triangles)])
            geometry.firstMaterial = layer == 0 ? rockMaterial : groundMaterial
            let mountains = SCNNode(geometry:geometry)
            mountains.castsShadow = false
            backdropRoot.addChildNode(mountains)
        }
    }

    private func level(_ x: Double, _ z: Double) -> Float {
        Float(TronzoneBiome.mountainHeight(GroundPoint(x, z)))
    }

    /// Chunked real terrain triangles with SceneKit PBR shading and depth.
    /// Rebuild only when the camera travels more than one 24-unit grid chunk.
    private func buildTerrain(aroundX x: Double, z: Double) {
        let chunkX = Int(floor(x / 24))
        let chunkZ = Int(floor(z / 24))
        if terrainOrigin == (chunkX, chunkZ) { return }
        terrainOrigin = (chunkX, chunkZ)
        terrainRoot.childNodes.forEach { $0.removeFromParentNode() }
        let step = 7.0
        let half = 27
        let count = half * 2 + 1
        let originX = Double(chunkX) * 24
        let originZ = Double(chunkZ) * 24
        var vertices: [SCNVector3] = []
        var uv: [CGPoint] = []
        var indices: [Int32] = []
        vertices.reserveCapacity(count * count)
        for row in 0..<count {
            for col in 0..<count {
                let xx = originX + Double(col-half) * step
                let zz = originZ + Double(row-half) * step
                vertices.append(SCNVector3(Float(xx), level(xx, zz), Float(-zz)))
                uv.append(CGPoint(x:xx/17, y:zz/17))
            }
        }
        for row in 0..<(count-1) {
            for col in 0..<(count-1) {
                let a = Int32(row * count + col)
                let b = Int32((row+1) * count + col)
                indices.append(contentsOf: [a,b,a+1, a+1,b,b+1])
            }
        }
        let source = SCNGeometrySource(vertices: vertices)
        let triangles = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let texcoords = SCNGeometrySource(textureCoordinates:uv)
        let geometry = SCNGeometry(sources: [source,texcoords], elements: [triangles])
        geometry.firstMaterial = groundMaterial
        let node = SCNNode(geometry: geometry)
        node.castsShadow = false
        terrainRoot.addChildNode(node)

        // A real depth-tested neon floor lattice. These segments follow the
        // sampled 3D topography rather than floating across a flat 2D plane.
        var gridIndices: [Int32] = []
        gridIndices.reserveCapacity((count-1) * count * 4)
        for row in 0..<count {
            for col in 0..<count {
                let vertex = Int32(row * count + col)
                if col + 1 < count {
                    gridIndices.append(vertex)
                    gridIndices.append(vertex+1)
                }
                if row + 1 < count {
                    gridIndices.append(vertex)
                    gridIndices.append(vertex+Int32(count))
                }
            }
        }
        let gridElement = SCNGeometryElement(indices:gridIndices,
                                             primitiveType:.line)
        let gridGeometry = SCNGeometry(sources:[source],elements:[gridElement])
        gridGeometry.firstMaterial = trim
        let gridNode = SCNNode(geometry:gridGeometry)
        gridNode.position.y = 0.045
        gridNode.castsShadow = false
        gridNode.opacity = 0.63
        terrainRoot.addChildNode(gridNode)
    }

    func load(_ sites: [Site]) {
        structureRoot.childNodes.forEach { $0.removeFromParentNode() }
        for (idx, site) in sites.enumerated() {
            let node = SCNNode()
            node.position = SCNVector3(Float(site.x), level(site.x, site.z),
                                       Float(-site.z))
            let s = CGFloat(site.size)
            if site.kind == 0 {
                let trunk = SCNCylinder(radius: s * 0.13, height: s * 2.3)
                trunk.firstMaterial = rockMaterial
                let trunkNode = SCNNode(geometry: trunk)
                trunkNode.position.y = CGFloat(s * 1.15)
                node.addChildNode(trunkNode)
                for tier in 0..<4 {
                    let cone = SCNCone(topRadius: 0, bottomRadius: s * (1.25-CGFloat(tier)*0.16),
                                       height: s * 2.15)
                    cone.radialSegmentCount = 9
                    cone.firstMaterial = pineMaterial
                    let crown = SCNNode(geometry: cone)
                    crown.position.y = CGFloat(s * (1.2 + CGFloat(tier)*0.72))
                    node.addChildNode(crown)
                }
            } else if site.kind == 1 {
                let rock = SCNSphere(radius: s)
                rock.segmentCount = 7
                rock.firstMaterial = rockMaterial
                let rockNode = SCNNode(geometry: rock)
                rockNode.scale = SCNVector3(1.2, 0.63, 0.92)
                rockNode.position.y = CGFloat(s * 0.52)
                rockNode.eulerAngles.y = CGFloat(Double(idx) * 0.73)
                node.addChildNode(rockNode)
            } else if site.kind == 2 {
                let body = box(s*1.9,s*1.25,s*1.9,material:bunkerMaterial,chamfer:s*0.08)
                body.position.y = (s*0.625)
                node.addChildNode(body)
                let roof = box(s*2.3,s*0.18,s*2.3,material:hullMaterial)
                roof.position.y = (s*1.32)
                node.addChildNode(roof)
                let beam = box(s*1.2,s*0.04,s*0.08,material:trim,chamfer:0)
                beam.position = SCNVector3(0,Float(s*0.85),Float(-s*0.98))
                node.addChildNode(beam)
            } else {
                let tower = box(s*0.72,s*5,s*0.72,material:bunkerMaterial)
                tower.position.y = (s*2.5)
                node.addChildNode(tower)
                let beacon = box(s*1.6,s*0.12,s*1.6,material:trim)
                beacon.position.y = (s*5)
                node.addChildNode(beacon)
                let dish = SCNTorus(ringRadius:s*0.8, pipeRadius:s*0.06)
                dish.firstMaterial = trim
                let radar = SCNNode(geometry:dish)
                radar.position.y = (s*5.5)
                radar.eulerAngles.x = 0.33
                node.addChildNode(radar)
            }
            structureRoot.addChildNode(node)
        }
    }

    private func tankModel(isEnemy: Bool) -> SCNNode {
        let root = SCNNode()
        let armor = isEnemy ? enemyMaterial : hullMaterial
        let glowing = isEnemy ? redTrim : trim
        let lower = box(4.7, 0.85, 6.3, material:armor, chamfer:0.25)
        lower.position.y = 0.65
        root.addChildNode(lower)
        let upper = box(3.7, 0.65, 4.5, material:armor, chamfer:0.30)
        upper.position.y = 1.25
        root.addChildNode(upper)
        let turret = box(2.35, 0.9, 2.55, material:armor,chamfer:0.38)
        turret.position = SCNVector3(0,1.95,-0.1)
        root.addChildNode(turret)
        let barrel = SCNCylinder(radius:0.23, height:3.7)
        barrel.radialSegmentCount = 10
        barrel.firstMaterial = armor
        let gun = SCNNode(geometry:barrel)
        gun.eulerAngles.x = -.pi / 2
        gun.position = SCNVector3(0,1.85,-3.0)
        root.addChildNode(gun)
        let muzzle = SCNTorus(ringRadius:0.28,pipeRadius:0.055)
        muzzle.firstMaterial = glowing
        let muzzleNode = SCNNode(geometry:muzzle)
        muzzleNode.eulerAngles.x = .pi/2
        muzzleNode.position = SCNVector3(0,1.85,-4.9)
        root.addChildNode(muzzleNode)
        // Continuous armored skirts with visible independent road wheels.
        // These are real depth-tested meshes, not decals or glowing outlines.
        for sign in [-1.0,1.0] {
            let track = box(0.58,0.90,6.2,material:rockMaterial,chamfer:0.18)
            track.position = SCNVector3(CGFloat(sign*2.3),0.46,0)
            root.addChildNode(track)
            let skirt = box(0.12,0.36,5.95,material:armor,chamfer:0.035)
            skirt.position = SCNVector3(CGFloat(sign*2.68),0.83,0)
            root.addChildNode(skirt)
            for wheel in 0..<6 {
                let tire = SCNCylinder(radius:0.36,height:0.15)
                tire.radialSegmentCount = 12
                tire.firstMaterial = rockMaterial
                let wheelNode = SCNNode(geometry:tire)
                wheelNode.eulerAngles.z = .pi/2
                wheelNode.position = SCNVector3(CGFloat(sign*2.70),0.36,
                                                 CGFloat(-2.35+Double(wheel)*0.94))
                root.addChildNode(wheelNode)
                let hub = SCNCylinder(radius:0.14,height:0.16)
                hub.radialSegmentCount = 10
                hub.firstMaterial = armor
                let hubNode = SCNNode(geometry:hub)
                hubNode.eulerAngles.z = .pi/2
                hubNode.position = SCNVector3(CGFloat(sign*2.78),0.36,
                                               CGFloat(-2.35+Double(wheel)*0.94))
                root.addChildNode(hubNode)
            }
            let rail = box(0.10,0.045,4.8,material:glowing,chamfer:0)
            rail.position = SCNVector3(CGFloat(sign*2.78),1.04,0)
            root.addChildNode(rail)
        }
        // Flush illuminated armor bands, recessed ventilation and gun optics.
        for z in [-1.9, 1.9] {
            let deck = box(3.25,0.065,0.075,material:glowing,chamfer:0)
            deck.position = SCNVector3(0,1.59,CGFloat(z))
            root.addChildNode(deck)
        }
        let sight = box(0.48,0.22,0.36,material:rockMaterial,chamfer:0.05)
        sight.position = SCNVector3(0.65,2.43,-0.75)
        root.addChildNode(sight)
        let optic = box(0.34,0.10,0.04,material:glowing,chamfer:0)
        optic.position = SCNVector3(0.65,2.47,-0.96)
        root.addChildNode(optic)
        return root
    }

    private func airModel(kind: Int) -> SCNNode {
        let root = SCNNode()
        if kind == 1 {
            let body = box(1.5,0.45,2.0,material:enemyMaterial,chamfer:0.16)
            root.addChildNode(body)
            for side in [-1.0,1.0] {
                for z in [-1.2,1.2] {
                    let arm = box(3.5,0.12,0.13,material:enemyMaterial,chamfer:0.02)
                    arm.position = SCNVector3(0,0.06,CGFloat(z))
                    root.addChildNode(arm)
                    let motor = SCNCylinder(radius:0.56,height:0.12)
                    motor.firstMaterial = redTrim
                    let node = SCNNode(geometry:motor)
                    node.position = SCNVector3(CGFloat(side*1.45),0.16,CGFloat(z))
                    root.addChildNode(node)
                }
            }
        } else if kind == 2 {
            let disk = SCNCylinder(radius:3.7,height:0.6)
            disk.radialSegmentCount = 20
            disk.firstMaterial = hullMaterial
            root.addChildNode(SCNNode(geometry:disk))
            let center = SCNSphere(radius:1.7)
            center.segmentCount = 12
            center.firstMaterial = enemyMaterial
            let dome = SCNNode(geometry:center)
            dome.scale.y = 0.6
            dome.position.y = 0.5
            root.addChildNode(dome)
            let ring = SCNTorus(ringRadius:3.6,pipeRadius:0.09)
            ring.firstMaterial = redTrim
            root.addChildNode(SCNNode(geometry:ring))
        } else {
            let fuselage = box(1.3,0.58,6.5,material:enemyMaterial,chamfer:0.15)
            root.addChildNode(fuselage)
            let wing = box(9.3,0.16,2.2,material:hullMaterial,chamfer:0.22)
            wing.position.z = -0.3
            root.addChildNode(wing)
            let tail = box(3.8,0.17,1.3,material:enemyMaterial,chamfer:0.12)
            tail.position.z = 2.2
            root.addChildNode(tail)
            let beam = box(0.10,0.05,5.0,material:redTrim,chamfer:0)
            beam.position.y = 0.35
            root.addChildNode(beam)
        }
        return root
    }

    func updateContacts(_ contacts: [Contact]) {
        var remaining = Set(contactNodes.keys)
        for contact in contacts {
            let node: SCNNode
            if let existing = contactNodes[contact.id],
               contactKinds[contact.id] == contact.kind {
                node = existing
            } else {
                contactNodes[contact.id]?.removeFromParentNode()
                node = contact.kind == 0
                    ? tankModel(isEnemy: true) : airModel(kind: contact.kind)
                actorRoot.addChildNode(node)
                contactNodes[contact.id] = node
                contactKinds[contact.id] = contact.kind
            }
            node.position = SCNVector3(Float(contact.x),
                                       level(contact.x, contact.z) + Float(contact.altitude),
                                       Float(-contact.z))
            node.eulerAngles.y = CGFloat(-contact.heading)
            node.isHidden = false
            remaining.remove(contact.id)
        }
        for id in remaining {
            contactNodes.removeValue(forKey:id)?.removeFromParentNode()
            contactKinds.removeValue(forKey:id)
        }
    }

    func updateCamera(x: Double, z: Double, heading: Double,
                      eyeHeight: Double, viewportSize: CGSize,
                      pitchPoints: Double) {
        buildTerrain(aroundX:x,z:z)
        viewport.viewportSize = viewportSize
        viewport.position = CGPoint(x: viewportSize.width/2, y: viewportSize.height/2)
        cameraNode.position = SCNVector3(Float(x),Float(eyeHeight),Float(-z))
        cameraNode.eulerAngles = SCNVector3(
            Float(pitchPoints / max(300,Double(viewportSize.height))),
            Float(-heading), 0)
        if let camera = cameraNode.camera {
            // The old game projects with focal=min(w*0.89,h*1.45).
            let focal = min(Double(viewportSize.width)*0.89,
                            Double(viewportSize.height)*1.45)
            camera.fieldOfView = CGFloat(2*atan(Double(viewportSize.height)/(2*focal))*180/Double.pi)
        }
    }
}
