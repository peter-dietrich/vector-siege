import SpriteKit
import AppKit

private struct Obstacle {
    enum Kind { case block, pyramid }
    var center: GroundPoint
    var size: Double
    var kind: Kind
}

private enum FoeType { case tank, hunter, saucer }
private struct Foe {
    var center: GroundPoint
    var heading: Double
    var kind: FoeType
    var reload: Double
    var phase: Double
    var hitPoints: Int
}

private struct Shell {
    var center: GroundPoint
    var direction: GroundPoint
    var hostile: Bool
    var timeLeft: Double
}

private struct Spark {
    var position: WorldPoint
    var velocity: WorldPoint
    var timeLeft: Double
    var maxLife: Double
}

private enum RoundState { case title, playing, paused, gameOver }

final class BattlefieldScene: SKScene {
    var onDisplayModeChange: ((DisplayMode) -> Void)?
    var displayMode: DisplayMode = .classic { didSet {
        configurePalette()
        if oldValue != displayMode { onDisplayModeChange?(displayMode) }
    } }
    var threatLevel: ThreatLevel = .veteran
    var soundOn = true

    private var round: RoundState = .title
    private var pressedKeys: Set<UInt16> = []
    private var tankPosition = GroundPoint(0, 0)
    private var heading: Double = 0
    private var driveSpeed: Double = 0
    private var score = 0
    private var wave = 1
    private var lives = 3
    private var bestScore = UserDefaults.standard.integer(forKey: "VectorSiegeHighScore")
    private var cannonCooldown: Double = 0
    private var shieldDuration: Double = 0
    private var shieldCooldown: Double = 0
    private var invulnerability: Double = 0
    private var pulse: Double = 0
    private var gameClock: Double = 0
    private var lastUpdateTime: TimeInterval = 0
    private var pendingWave: Double = 0
    private var obstacles: [Obstacle] = []
    private var enemies: [Foe] = []
    private var shells: [Shell] = []
    private var sparks: [Spark] = []

    private let skyline = SKShapeNode()
    private let farSkyline = SKShapeNode()
    private let ground = SKShapeNode()
    private let structures = SKShapeNode()
    private let opponentLines = SKShapeNode()
    private let shotLines = SKShapeNode()
    private let flashLines = SKShapeNode()
    private let reticle = SKShapeNode()
    private let radar = SKShapeNode()
    private let hudLines = SKShapeNode()
    private let leftHUD = SKLabelNode(fontNamed: "Menlo-Bold")
    private let rightHUD = SKLabelNode(fontNamed: "Menlo-Bold")
    private let midHUD = SKLabelNode(fontNamed: "Menlo-Bold")
    private let warning = SKLabelNode(fontNamed: "Menlo-Bold")
    private let banner = SKLabelNode(fontNamed: "Menlo-Bold")
    private let subtitle = SKLabelNode(fontNamed: "Menlo")
    private let message = SKLabelNode(fontNamed: "Menlo")
    private let scanlines = SKShapeNode()

    private var green = NSColor(calibratedRed: 0.35, green: 1.0, blue: 0.46, alpha: 1)
    private var muted = NSColor(calibratedRed: 0.10, green: 0.33, blue: 0.15, alpha: 1)
    private var accent = NSColor(calibratedRed: 1.0, green: 0.34, blue: 0.30, alpha: 1)

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = .black

        for (layer, z) in [
            (farSkyline, 1.0), (skyline, 2.0), (ground, 3.0), (structures, 4.0),
            (opponentLines, 5.0), (shotLines, 6.0), (flashLines, 7.0),
            (scanlines, 8.0), (reticle, 10.0), (hudLines, 12.0), (radar, 13.0)
        ] {
            layer.zPosition = z
            layer.lineCap = .round
            layer.lineJoin = .round
            layer.fillColor = .clear
            addChild(layer)
        }

        for (label, z) in [(leftHUD, 14.0), (rightHUD, 14.0), (midHUD, 14.0),
                           (warning, 15.0), (banner, 20.0), (subtitle, 20.0), (message, 20.0)] {
            label.zPosition = z
            label.verticalAlignmentMode = .center
            addChild(label)
        }
        leftHUD.horizontalAlignmentMode = .left
        rightHUD.horizontalAlignmentMode = .right
        midHUD.horizontalAlignmentMode = .center
        warning.horizontalAlignmentMode = .center
        banner.horizontalAlignmentMode = .center
        subtitle.horizontalAlignmentMode = .center
        message.horizontalAlignmentMode = .center
        configurePalette()
        makeObstacles()
        spawnWave()
    }

    required init?(coder: NSCoder) { fatalError("Use init(size:)") }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        configurePalette()
    }

    func pressed(_ code: UInt16, repeatEvent: Bool) {
        pressedKeys.insert(code)
        if repeatEvent { return }
        switch code {
        case 36, 76: // Return / keypad Enter
            if round == .title || round == .gameOver { restart() }
        case 35: // P
            if round == .playing { round = .paused }
            else if round == .paused { round = .playing }
        case 15: // R
            restart()
        case 8: // C
            displayMode = displayMode == .classic ? .modern : .classic
        case 56, 60: // Shift, usually delivered via flagsChanged instead
            triggerShield()
        default: break
        }
    }

    func released(_ code: UInt16) { pressedKeys.remove(code) }

    func setShift(_ isPressed: Bool) {
        if isPressed && !pressedKeys.contains(56) {
            pressedKeys.insert(56)
            triggerShield()
        } else if !isPressed {
            pressedKeys.remove(56)
            pressedKeys.remove(60)
        }
    }

    func restart() {
        pressedKeys.removeAll()
        score = 0
        wave = 1
        lives = 3
        driveSpeed = 0
        heading = 0
        tankPosition = GroundPoint(0, 0)
        gameClock = 0
        cannonCooldown = 0
        shieldDuration = 0
        shieldCooldown = 0
        invulnerability = 1.8
        pendingWave = 0
        shells.removeAll()
        sparks.removeAll()
        makeObstacles()
        spawnWave()
        round = .playing
        lastUpdateTime = 0
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime == 0 ? 0.0 : min(0.04, max(0, currentTime - lastUpdateTime))
        lastUpdateTime = currentTime
        if round != .paused { gameClock += dt }
        if round == .playing { tick(dt) }
        if round == .title { pulse += dt }
        render()
    }

    private func tick(_ dt: Double) {
        cannonCooldown = max(0, cannonCooldown - dt)
        shieldCooldown = max(0, shieldCooldown - dt)
        shieldDuration = max(0, shieldDuration - dt)
        invulnerability = max(0, invulnerability - dt)
        pulse = max(0, pulse - dt)

        let mainForward = key(126, 13) ? 1.0 : (key(125, 1) ? -1.0 : 0.0)
        let mainTurn = key(123, 0) ? -1.0 : (key(124, 2) ? 1.0 : 0.0)
        let leftTread = (key(34) ? 1.0 : 0.0) - (key(40) ? 1.0 : 0.0)
        let rightTread = (key(31) ? 1.0 : 0.0) - (key(37) ? 1.0 : 0.0)
        let usingTreads = leftTread != 0 || rightTread != 0
        let demand = usingTreads ? (leftTread + rightTread) / 2.0 : mainForward
        let turn = usingTreads ? (leftTread - rightTread) / 2.0 : mainTurn

        driveSpeed += (demand * 16.5 - driveSpeed) * min(1, dt * 4.0)
        heading = wrapAngle(heading + turn * 1.65 * dt * (usingTreads ? 1.1 : 1))
        if abs(driveSpeed) > 0.01 {
            let proposed = tankPosition + facing(heading) * (driveSpeed * dt)
            if !blocked(proposed, radius: 1.6) { tankPosition = proposed }
            else { driveSpeed *= -0.12 }
        }
        if key(49) && cannonCooldown <= 0 && !shells.contains(where: { !$0.hostile }) {
            firePlayer()
        }

        for idx in enemies.indices {
            let diff = tankPosition - enemies[idx].center
            let distance = max(0.001, diff.length)
            enemies[idx].reload -= dt
            enemies[idx].phase += dt
            let type = enemies[idx].kind
            let movement = (type == .hunter ? 4.6 : (type == .saucer ? 5.4 : 2.55)) * threatLevel.enemyVelocity
            let aim = atan2(diff.x, diff.z)
            if type == .saucer {
                let tangent = GroundPoint(cos(enemies[idx].phase * 0.8), sin(enemies[idx].phase * 0.8))
                enemies[idx].center = enemies[idx].center + tangent * (movement * dt)
            } else {
                let wobble = type == .hunter ? sin(enemies[idx].phase * 1.4) * 0.28 : 0
                enemies[idx].heading = wrapAngle(aim + wobble)
                if distance > (type == .hunter ? 13 : 18) {
                    let proposed = enemies[idx].center + facing(enemies[idx].heading) * (movement * dt)
                    if !blocked(proposed, radius: 2.7) && proposed.distance(to: tankPosition) > 5 {
                        enemies[idx].center = proposed
                    }
                }
            }
            if enemies[idx].reload <= 0 && type != .saucer && distance < 79 && distance > 7 {
                let error = Double.random(in: -threatLevel.enemyAimError ... threatLevel.enemyAimError)
                let direction = facing(aim + error)
                shells.append(Shell(center: enemies[idx].center + direction * 3.0,
                                    direction: direction, hostile: true, timeLeft: 4.0))
                enemies[idx].reload = Double.random(in: 2.3 ... 4.0) * threatLevel.enemyReload
                sound("enemy.wav")
            }
        }

        var survivingShells: [Shell] = []
        var casualties = Set<Int>()
        for var shell in shells {
            let old = shell.center
            shell.center = shell.center + shell.direction * (dt * (shell.hostile ? 23 : 90))
            shell.timeLeft -= dt
            if shell.timeLeft <= 0 { continue }
            if obstacles.contains(where: { segmentHitsObstacle(old, shell.center, $0) }) {
                burst(at: WorldPoint(shell.center, height: 1.2), count: 9)
                sound("impact.wav")
                continue
            }
            if shell.hostile {
                if shell.center.distance(to: tankPosition) < 2.0 {
                    burst(at: WorldPoint(tankPosition, height: 1.15), count: 24)
                    if shieldDuration <= 0 && invulnerability <= 0 { takeDamage() }
                    else { sound("impact.wav") }
                    continue
                }
            } else {
                var hit = false
                for idx in enemies.indices where !casualties.contains(idx) {
                    if shell.center.distance(to: enemies[idx].center) < (enemies[idx].kind == .saucer ? 3.1 : 2.9) {
                        hit = true
                        enemies[idx].hitPoints -= 1
                        burst(at: WorldPoint(enemies[idx].center,
                                             height: enemies[idx].kind == .saucer ? 5.1 : 1.45),
                              count: enemies[idx].hitPoints <= 0 ? 35 : 12)
                        if enemies[idx].hitPoints <= 0 {
                            casualties.insert(idx)
                            addPoints(enemies[idx].kind == .hunter ? 1500 : (enemies[idx].kind == .saucer ? 250 : 1000))
                            sound("explosion.wav")
                        } else { sound("impact.wav") }
                        break
                    }
                }
                if hit { continue }
            }
            survivingShells.append(shell)
        }
        shells = survivingShells
        for idx in casualties.sorted(by: >) { enemies.remove(at: idx) }

        for idx in sparks.indices {
            sparks[idx].position.x += sparks[idx].velocity.x * dt
            sparks[idx].position.y += sparks[idx].velocity.y * dt
            sparks[idx].position.z += sparks[idx].velocity.z * dt
            sparks[idx].velocity.y -= dt * 5.0
            sparks[idx].timeLeft -= dt
        }
        sparks.removeAll(where: { $0.timeLeft <= 0 })
        if enemies.isEmpty && pendingWave <= 0 { pendingWave = 2.1 }
        if pendingWave > 0 {
            pendingWave -= dt
            if pendingWave <= 0 {
                wave += 1
                spawnWave()
                shells.removeAll()
                shieldCooldown = 0
                invulnerability = 1.0
            }
        }
    }

    private func key(_ codes: UInt16...) -> Bool { codes.contains { pressedKeys.contains($0) } }

    private func blocked(_ p: GroundPoint, radius: Double) -> Bool {
        if abs(p.x) > 190 || abs(p.z) > 190 { return true }
        return obstacles.contains { p.distance(to: $0.center) < $0.size * 0.78 + radius }
    }

    private func segmentHitsObstacle(_ a: GroundPoint, _ b: GroundPoint, _ obstacle: Obstacle) -> Bool {
        let ab = b - a
        let ap = obstacle.center - a
        let len2 = max(0.0001, ab.x * ab.x + ab.z * ab.z)
        let t = max(0, min(1, (ap.x * ab.x + ap.z * ab.z) / len2))
        return (a + ab * t).distance(to: obstacle.center) < obstacle.size * 0.66
    }

    private func firePlayer() {
        cannonCooldown = 0.33
        let direction = facing(heading)
        shells.append(Shell(center: tankPosition + direction * 2.5,
                            direction: direction, hostile: false, timeLeft: 1.55))
        pulse = 0.13
        sound("shot.wav")
    }

    private func triggerShield() {
        guard round == .playing && shieldCooldown <= 0 && shieldDuration <= 0 else { return }
        shieldDuration = 2.25
        shieldCooldown = 11.0
        sound("shield.wav")
    }

    private func takeDamage() {
        lives -= 1
        invulnerability = 2.8
        driveSpeed = -6.0
        pulse = 0.5
        sound("damage.wav")
        if lives <= 0 {
            round = .gameOver
            if score > bestScore { bestScore = score; UserDefaults.standard.set(bestScore, forKey: "VectorSiegeHighScore") }
        }
    }

    private func addPoints(_ amount: Int) {
        score += amount
        if score > bestScore {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: "VectorSiegeHighScore")
        }
    }

    private func makeObstacles() {
        obstacles.removeAll()
        for i in 0..<23 {
            let angle = Double(i) * 2.39996 + Double.random(in: -0.4...0.4)
            let distance = Double.random(in: 24...145)
            let p = GroundPoint(sin(angle) * distance, cos(angle) * distance)
            let size = Double.random(in: 3.0...6.7)
            obstacles.append(Obstacle(center: p, size: size,
                                      kind: i.isMultiple(of: 2) ? .pyramid : .block))
        }
    }

    private func spawnWave() {
        enemies.removeAll()
        let count = min(2 + wave, 8)
        for n in 0..<count {
            let angle = heading + (n == 0 ? Double.random(in: -0.20...0.20) : Double.random(in: -3.0...3.0))
            let dist = Double.random(in: 35...88)
            var target = tankPosition + facing(angle) * dist
            var tries = 0
            while blocked(target, radius: 4) && tries < 20 {
                target = tankPosition + facing(Double.random(in: -3.1...3.1)) * Double.random(in: 30...110)
                tries += 1
            }
            let kind: FoeType = (wave >= 3 && n % 4 == 2) ? .hunter : ((wave >= 2 && n % 6 == 5) ? .saucer : .tank)
            enemies.append(Foe(center: target, heading: angle + .pi, kind: kind,
                               reload: Double.random(in: 2.0...4.0),
                               phase: Double.random(in: 0...6.0),
                               hitPoints: kind == .hunter ? 2 : 1))
        }
    }

    private func burst(at whereAt: WorldPoint, count: Int) {
        for _ in 0..<count {
            let life = Double.random(in: 0.16...0.78)
            sparks.append(Spark(position: whereAt,
                                velocity: WorldPoint(Double.random(in: -8...8),
                                                     Double.random(in: -1...9),
                                                     Double.random(in: -8...8)),
                                timeLeft: life, maxLife: life))
        }
        if sparks.count > 300 { sparks.removeFirst(sparks.count - 300) }
    }

    private func sound(_ name: String) {
        guard soundOn else { return }
        run(SKAction.playSoundFileNamed(name, waitForCompletion: false))
    }

    private func configurePalette() {
        if displayMode == .classic {
            green = NSColor(calibratedRed: 0.23, green: 1, blue: 0.27, alpha: 1)
            muted = NSColor(calibratedRed: 0.09, green: 0.38, blue: 0.13, alpha: 0.83)
            accent = NSColor(calibratedRed: 1, green: 0.25, blue: 0.22, alpha: 1)
            backgroundColor = .black
        } else {
            green = NSColor(calibratedRed: 0.43, green: 1, blue: 0.69, alpha: 1)
            muted = NSColor(calibratedRed: 0.07, green: 0.48, blue: 0.34, alpha: 0.65)
            accent = NSColor(calibratedRed: 1, green: 0.46, blue: 0.29, alpha: 1)
            backgroundColor = NSColor(calibratedRed: 0.009, green: 0.028, blue: 0.028, alpha: 1)
        }
        for (node, color, width, glow) in [
            (farSkyline, muted.withAlphaComponent(0.55), 1.0, 0.0),
            (skyline, green.withAlphaComponent(0.75), 1.25, displayMode == .classic ? 0.35 : 2.2),
            (ground, muted, 0.85, displayMode == .classic ? 0 : 0.7),
            (structures, green.withAlphaComponent(0.82), 1.5, displayMode == .classic ? 0.35 : 2.6),
            (opponentLines, green, 2.0, displayMode == .classic ? 0.7 : 4.0),
            (shotLines, accent, 2.5, displayMode == .classic ? 0.8 : 5),
            (flashLines, accent, 2.0, displayMode == .classic ? 1 : 5),
            (reticle, accent, 1.1, displayMode == .classic ? 0.25 : 2),
            (radar, accent, 1.5, displayMode == .classic ? 0.2 : 2),
            (hudLines, muted, 1.0, 0)
        ] {
            node.strokeColor = color
            node.lineWidth = CGFloat(width)
            node.glowWidth = CGFloat(glow)
        }
        let cc = green
        leftHUD.fontColor = cc
        midHUD.fontColor = cc
        rightHUD.fontColor = cc
        warning.fontColor = accent
        banner.fontColor = cc
        subtitle.fontColor = cc.withAlphaComponent(0.85)
        message.fontColor = accent
        scanlines.strokeColor = green.withAlphaComponent(displayMode == .classic ? 0.035 : 0.025)
        scanlines.lineWidth = 0.5
    }

    private func render() {
        let w = Double(size.width)
        let h = Double(size.height)
        guard w > 100 && h > 100 else { return }
        let camera = CameraProjection(position: tankPosition, yaw: heading,
                                      viewportWidth: w, viewportHeight: h)
        renderMountains(camera)
        renderGround(camera)
        renderObjects(camera)
        renderProjectiles(camera)
        renderHUD(camera)
    }

    private func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    private func segment(_ path: CGMutablePath, _ a: CGPoint, _ b: CGPoint) {
        path.move(to: a)
        path.addLine(to: b)
    }

    private func line(_ path: CGMutablePath, _ a: WorldPoint, _ b: WorldPoint,
                      _ camera: CameraProjection) {
        guard let (p, q) = camera.clipLine(a, b) else { return }
        let limit = 30000.0
        if abs(p.0) > limit || abs(p.1) > limit || abs(q.0) > limit || abs(q.1) > limit { return }
        segment(path, point(p.0, p.1), point(q.0, q.1))
    }

    private func ridge(_ azimuth: Double, multiplier: Double) -> Double {
        let a = abs(sin(azimuth * 8.2 + 1.7))
        let b = abs(sin(azimuth * 15.4 - 0.8))
        let c = abs(sin(azimuth * 25.0 + 2.3))
        return multiplier * (7 + 56 * pow(a, 5.2) + 26 * pow(b, 9) + 7 * pow(c, 3))
    }

    private func renderMountains(_ c: CameraProjection) {
        let farPath = CGMutablePath()
        let nearPath = CGMutablePath()
        let width = c.viewportWidth
        var prev1: CGPoint?
        var prev2: CGPoint?
        for i in 0...(Int(ceil(width / 15)) + 1) {
            let x = Double(i) * 15 - 10
            let azimuth = heading + atan2((x - width / 2) / c.focal, 1)
            let back = point(x, c.horizon + ridge(azimuth + 0.6, multiplier: 0.47))
            let front = point(x, c.horizon + ridge(azimuth, multiplier: 1.0))
            if let prev1 { segment(farPath, prev1, back) }
            if let prev2 { segment(nearPath, prev2, front) }
            prev1 = back
            prev2 = front
        }
        farSkyline.path = farPath
        skyline.path = nearPath
    }

    private func renderGround(_ c: CameraProjection) {
        let path = CGMutablePath()
        // A subtle near-field reference grid in Modern; the original's empty plane in Classic.
        if displayMode == .modern {
            let baseX = floor(tankPosition.x / 12) * 12
            let baseZ = floor(tankPosition.z / 12) * 12
            for k in -13...13 {
                let x = baseX + Double(k) * 12
                line(path, WorldPoint(x, 0, baseZ - 155), WorldPoint(x, 0, baseZ + 155), c)
                let z = baseZ + Double(k) * 12
                line(path, WorldPoint(baseX - 155, 0, z), WorldPoint(baseX + 155, 0, z), c)
            }
        }
        ground.path = path
    }

    private func renderObjects(_ c: CameraProjection) {
        let structurePath = CGMutablePath()
        for o in obstacles {
            // Culling far outside the visible scene.
            let offset = o.center - tankPosition
            if offset.length > 190 { continue }
            if o.kind == .pyramid { drawPyramid(o, on: structurePath, camera: c) }
            else { drawBlock(o, on: structurePath, camera: c) }
        }
        structures.path = structurePath

        let enemyPath = CGMutablePath()
        for enemy in enemies {
            if enemy.center.distance(to: tankPosition) > 170 { continue }
            if enemy.kind == .saucer { drawSaucer(enemy, on: enemyPath, camera: c) }
            else { drawTank(enemy, on: enemyPath, camera: c) }
        }
        opponentLines.path = enemyPath
    }

    private func drawPyramid(_ o: Obstacle, on path: CGMutablePath, camera c: CameraProjection) {
        let s = o.size
        let base = [WorldPoint(o.center.x-s, 0, o.center.z-s),
                    WorldPoint(o.center.x+s, 0, o.center.z-s),
                    WorldPoint(o.center.x+s, 0, o.center.z+s),
                    WorldPoint(o.center.x-s, 0, o.center.z+s)]
        let top = WorldPoint(o.center.x, s*1.28, o.center.z)
        for i in 0..<4 {
            line(path, base[i], base[(i+1)%4], c)
            line(path, base[i], top, c)
        }
    }

    private func drawBlock(_ o: Obstacle, on path: CGMutablePath, camera c: CameraProjection) {
        let s = o.size
        let bottom = [WorldPoint(o.center.x-s, 0, o.center.z-s),
                      WorldPoint(o.center.x+s, 0, o.center.z-s),
                      WorldPoint(o.center.x+s, 0, o.center.z+s),
                      WorldPoint(o.center.x-s, 0, o.center.z+s)]
        let top = bottom.map { WorldPoint($0.x, s*1.35, $0.z) }
        for i in 0..<4 {
            line(path, bottom[i], bottom[(i+1)%4], c)
            line(path, top[i], top[(i+1)%4], c)
            line(path, bottom[i], top[i], c)
        }
    }

    private func drawTank(_ e: Foe, on path: CGMutablePath, camera c: CameraProjection) {
        func v(_ x: Double, _ y: Double, _ z: Double) -> WorldPoint {
            let cs = cos(e.heading), sn = sin(e.heading)
            return WorldPoint(e.center.x + x*cs + z*sn, y,
                              e.center.z - x*sn + z*cs)
        }
        func polygon(_ vertices: [WorldPoint]) {
            guard vertices.count > 1 else { return }
            for i in vertices.indices { line(path, vertices[i], vertices[(i+1)%vertices.count], c) }
        }
        polygon([v(-2.3, 0.35, -3), v(2.3, 0.35, -3),
                 v(2.3, 0.35, 3), v(-2.3, 0.35, 3)])
        polygon([v(-1.9, 1.25, -2.4), v(1.9, 1.25, -2.4),
                 v(1.9, 1.25, 2.1), v(-1.9, 1.25, 2.1)])
        for (x,z) in [(-2.3,-3.0),(2.3,-3.0),(2.3,3.0),(-2.3,3.0)] {
            line(path, v(x, 0.35, z), v(x*0.83, 1.25, z*0.8), c)
        }
        polygon([v(-1.05, 1.35, -1.25), v(1.05, 1.35, -1.25),
                 v(1.05, 1.35, 1.1), v(-1.05, 1.35, 1.1)])
        polygon([v(-0.82, 2.05, -0.95), v(0.82, 2.05, -0.95),
                 v(0.82, 2.05, 0.85), v(-0.82, 2.05, 0.85)])
        for (x,z) in [(-1.05,-1.25),(1.05,-1.25),(1.05,1.1),(-1.05,1.1)] {
            line(path, v(x, 1.35, z), v(x*0.78, 2.05, z*0.77), c)
        }
        line(path, v(0, 1.80, 0.75), v(0, 1.8, 4.5), c)
        line(path, v(-0.19, 1.95, 0.8), v(-0.19, 1.95, 4.5), c)
        line(path, v(0.19, 1.68, 0.8), v(0.19, 1.68, 4.5), c)
        // Independent track outlines add depth at closer range.
        for x in [-2.17, 2.17] {
            polygon([v(x, 0.20, -2.8), v(x, 0.2, 2.7),
                     v(x, 0.75, 2.2), v(x, 0.75, -2.2)])
        }
    }

    private func drawSaucer(_ e: Foe, on path: CGMutablePath, camera c: CameraProjection) {
        let n = 10
        let height = 5.1 + sin(gameClock*2.4 + e.phase)*0.55
        for i in 0..<n {
            let a = Double(i) * 2 * .pi / Double(n)
            let b = Double(i+1) * 2 * .pi / Double(n)
            let outer1 = WorldPoint(e.center.x + cos(a)*3.1, height, e.center.z + sin(a)*3.1)
            let outer2 = WorldPoint(e.center.x + cos(b)*3.1, height, e.center.z + sin(b)*3.1)
            let cup1 = WorldPoint(e.center.x + cos(a)*1.4, height + 1.4, e.center.z + sin(a)*1.4)
            let cup2 = WorldPoint(e.center.x + cos(b)*1.4, height + 1.4, e.center.z + sin(b)*1.4)
            line(path, outer1, outer2, c)
            line(path, cup1, cup2, c)
            if i.isMultiple(of: 2) { line(path, outer1, cup1, c) }
        }
    }

    private func renderProjectiles(_ c: CameraProjection) {
        let bulletPath = CGMutablePath()
        for shell in shells {
            let height = shell.hostile ? 1.5 : 1.65
            let p = WorldPoint(shell.center, height: height)
            let tail = shell.center - shell.direction * (shell.hostile ? 2.4 : 3.8)
            line(bulletPath, p, WorldPoint(tail, height: height), c)
            line(bulletPath, WorldPoint(shell.center.x, height-0.28, shell.center.z),
                 WorldPoint(shell.center.x, height+0.28, shell.center.z), c)
        }
        shotLines.path = bulletPath

        let flarePath = CGMutablePath()
        for spark in sparks {
            let delta = spark.timeLeft / spark.maxLife
            if delta <= 0 { continue }
            let v = spark.velocity
            line(flarePath, spark.position,
                 WorldPoint(spark.position.x - v.x*0.045*delta,
                            spark.position.y - v.y*0.045*delta,
                            spark.position.z - v.z*0.045*delta), c)
        }
        flashLines.path = flarePath
    }

    private func renderHUD(_ c: CameraProjection) {
        let w = c.viewportWidth
        let h = c.viewportHeight
        let hp = CGMutablePath()
        let rp = CGMutablePath()
        let sight = CGMutablePath()
        let hudTop = h - 22
        let radarX = 92.0
        let radarY = h - 94
        let radarRadius = 44.0

        segment(hp, point(14, h - 163), point(w - 14, h - 163))
        segment(hp, point(14, h - 164), point(14, h - 12))
        segment(hp, point(w - 14, h - 164), point(w - 14, h - 12))
        segment(hp, point(14, h - 12), point(w - 14, h - 12))
        // Small registration ticks on top instrumentation strip.
        for i in 0...24 {
            let x = 180 + Double(i) / 24 * max(10, w - 390)
            segment(hp, point(x, h - 26), point(x, h - (i.isMultiple(of: 4) ? 37 : 30)))
        }
        hudLines.path = hp

        let circle = CGRect(x: radarX - radarRadius, y: radarY - radarRadius,
                            width: radarRadius*2, height: radarRadius*2)
        rp.addEllipse(in: circle)
        segment(rp, point(radarX, radarY-radarRadius), point(radarX, radarY+radarRadius))
        segment(rp, point(radarX-radarRadius, radarY), point(radarX+radarRadius, radarY))
        let sweepAngle = gameClock * 1.45
        segment(rp, point(radarX, radarY),
                point(radarX+sin(sweepAngle)*radarRadius, radarY+cos(sweepAngle)*radarRadius))
        for foe in enemies {
            let dx = foe.center.x-tankPosition.x
            let dz = foe.center.z-tankPosition.z
            let right = dx*cos(heading)-dz*sin(heading)
            let fwd = dx*sin(heading)+dz*cos(heading)
            let distance = hypot(right, fwd)
            if distance > 105 { continue }
            let x = radarX + right/105 * radarRadius
            let y = radarY + fwd/105 * radarRadius
            let blip = foe.kind == .hunter ? 3.8 : 2.6
            rp.addRect(CGRect(x: x-blip/2, y: y-blip/2, width: blip, height: blip))
        }
        radar.path = rp

        let cx = w / 2
        let cy = c.horizon + 18
        segment(sight, point(cx - 33, cy), point(cx - 8, cy))
        segment(sight, point(cx + 8, cy), point(cx + 33, cy))
        segment(sight, point(cx, cy - 30), point(cx, cy - 9))
        segment(sight, point(cx, cy + 9), point(cx, cy + 30))
        let corner = 60.0
        for sign in [-1.0, 1.0] {
            segment(sight, point(cx+sign*corner, cy-13), point(cx+sign*corner, cy+13))
        }
        if shieldDuration > 0 {
            sight.addEllipse(in: CGRect(x: cx-68, y: cy-68, width: 136, height: 136))
        }
        reticle.path = sight
        reticle.strokeColor = invulnerability > 0 && Int(gameClock * 9).isMultiple(of: 2)
            ? accent : (shieldDuration > 0 ? green : accent)

        leftHUD.position = point(155, h - 74)
        leftHUD.fontSize = 12
        leftHUD.text = "RADAR"
        midHUD.position = point(w*0.49, hudTop-41)
        midHUD.fontSize = 17
        midHUD.text = "SCORE  " + String(format: "%06d", score)
        rightHUD.position = point(w - 32, hudTop-38)
        rightHUD.fontSize = 13
        rightHUD.text = "BEST " + String(format: "%06d", bestScore)
        warning.position = point(w*0.52, h-131)
        warning.fontSize = 12
        let targetsInRange = enemies.contains { foe in
            let relative = foe.center - tankPosition
            return relative.length < 68 && abs(wrapAngle(atan2(relative.x, relative.z) - heading)) < 0.14
        }
        warning.text = targetsInRange ? "ENEMY IN SIGHTS" : (pendingWave > 0 ? "AREA SECURE" : "")

        let modeName = displayMode == .classic ? "CRT // 1980" : "VECTOR // ENHANCED"
        let extra = "WAVE " + String(format: "%02d", wave) + "    HULL " + String(repeating: "◆", count: max(0, lives))
        let shieldName = shieldDuration > 0 ? "SHIELD ACTIVE" : (shieldCooldown > 0 ? String(format: "SHIELD %.0fS", shieldCooldown) : "SHIELD READY")
        message.position = point(w/2, 47)
        message.fontSize = 12
        message.text = extra + "    //    " + shieldName + "    //    " + modeName
        message.fontColor = shieldDuration > 0 ? green : accent

        banner.position = point(w/2, h*0.67)
        banner.fontSize = min(42, w*0.052)
        subtitle.position = point(w/2, h*0.59)
        subtitle.fontSize = 15
        switch round {
        case .title:
            banner.text = "VECTOR SIEGE"
            subtitle.text = "PRESS RETURN TO DEPLOY"
        case .paused:
            banner.text = "PAUSED"
            subtitle.text = "PRESS P TO RESUME"
        case .gameOver:
            banner.text = "MISSION LOST"
            subtitle.text = "SCORE " + String(score) + "  //  PRESS RETURN TO REDEPLOY"
        case .playing:
            banner.text = pendingWave > 0 ? "SECTOR CLEAR" : ""
            subtitle.text = pendingWave > 0 ? "PREPARING WAVE " + String(wave+1) : ""
        }

        // CRT scanlines: inexpensive, persistent 2D paths, no texture dependencies.
        if displayMode == .classic {
            let sl = CGMutablePath()
            for y in stride(from: 0.0, through: h, by: 5.0) {
                segment(sl, point(0, y), point(w, y))
            }
            scanlines.path = sl
        } else { scanlines.path = nil }
    }
}