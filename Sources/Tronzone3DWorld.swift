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
    private let actorRoot = SCNNode()
    private let sun = SCNNode()
    private var contactNodes: [Int: SCNNode] = [:]
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

        scene.background.contents = NSColor(calibratedRed: 0.014, green: 0.045,
                                            blue: 0.026, alpha: 1)
        scene.fogColor = NSColor(calibratedRed: 0.075, green: 0.21,
                                blue: 0.11, alpha: 1)
        scene.fogStartDistance = 78
        scene.fogEndDistance = 225
        scene.fogDensityExponent = 0.85

        scene.rootNode.addChildNode(terrainRoot)
        scene.rootNode.addChildNode(structureRoot)
        scene.rootNode.addChildNode(actorRoot)
        let camera = SCNCamera()
        camera.zNear = 0.4
        camera.zFar = 400
        camera.fieldOfView = 48
        camera.wantsHDR = true
        camera.bloomIntensity = 0.18
        camera.bloomThreshold = 0.88
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

    private func box(_ width: CGFloat, _ height: CGFloat, _ length: CGFloat,
                     material: SCNMaterial, chamfer: CGFloat = 0.05) -> SCNNode {
        let mesh = SCNBox(width: width, height: height, length: length,
                          chamferRadius: min(chamfer, width * 0.18, height * 0.18))
        mesh.firstMaterial = material
        let node = SCNNode(geometry: mesh)
        node.castsShadow = true
        return node
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
        var indices: [Int32] = []
        vertices.reserveCapacity(count * count)
        for row in 0..<count {
            for col in 0..<count {
                let xx = originX + Double(col-half) * step
                let zz = originZ + Double(row-half) * step
                vertices.append(SCNVector3(Float(xx), level(xx, zz), Float(-zz)))
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
        let geometry = SCNGeometry(sources: [source], elements: [triangles])
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
        for sign in [-1.0,1.0] {
            let track = box(0.52,0.85,6.2,material:rockMaterial,chamfer:0.16)
            track.position = SCNVector3(Float(Double(sign)*2.3),0.47,0)
            root.addChildNode(track)
            let rail = box(0.11,0.06,4.6,material:glowing,chamfer:0)
            rail.position = SCNVector3(Float(Double(sign)*2.52),1.02,0)
            root.addChildNode(rail)
        }
        return root
    }

    func updateContacts(_ contacts: [Contact]) {
        var remaining = Set(contactNodes.keys)
        for contact in contacts {
            let node: SCNNode
            if let existing = contactNodes[contact.id] {
                node = existing
            } else {
                node = tankModel(isEnemy: true)
                actorRoot.addChildNode(node)
                contactNodes[contact.id] = node
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
