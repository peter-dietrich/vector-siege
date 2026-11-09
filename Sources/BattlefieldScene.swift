import SpriteKit
import AppKit
import AVFoundation

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

// Render-only face; the existing world obstacle geometry still owns collisions.
private struct GlassFace {
    var vertices: [WorldPoint]
    var depth: Double
    var tint: Int
}


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
    private var turnMotion: Double = 0
    private var suspension = TankSuspension()
    private lazy var movementAudio = TankMotionAudio()
    private var steerHoldSeconds: Double = 0
    private var previousSteerDirection: Double = 0
    private var score = 0
    private var wave = 1
    private var lives = 3
    private var bestScore = UserDefaults.standard.integer(forKey: "VectorSiegeHighScore")
    private var shotTally = ShotTally()
    private var observedFPS: Double = 60
    private var showDetailedTelemetry = false
    private var cannon = CannonMagazine()
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
    private let skyBands = (0..<10).map { _ in SKShapeNode() }
    private let distantMountains = SKShapeNode()
    private let middleMountains = SKShapeNode()
    private let nearMountains = SKShapeNode()
    private let horizonMist = SKShapeNode()
    private let glassLayer = SKNode()
    private var glassFacePool: [SKShapeNode] = []
    private let ground = SKShapeNode()
    private let structures = SKShapeNode()
    private let opponentLines = SKShapeNode()
    private let shotLines = SKShapeNode()
    private let modernFriendlyShells = SKShapeNode()
    private let modernHostileShells = SKShapeNode()
    private let flashLines = SKShapeNode()
    private let reticle = SKShapeNode()
    private let shieldBorder = SKShapeNode()
    private let shieldNotice = SKLabelNode(fontNamed: "Menlo-Bold")
    private let radar = SKShapeNode()
    private let radarProjectileGlow = SKShapeNode()
    private let radarProjectileCore = SKShapeNode()
    private let radarEnemyContacts = SKShapeNode()
    private let hudLines = SKShapeNode()
    private let leftHUD = SKLabelNode(fontNamed: "Menlo-Bold")
    private let rightHUD = SKLabelNode(fontNamed: "Menlo-Bold")
    private let midHUD = SKLabelNode(fontNamed: "Menlo-Bold")
    private let warning = SKLabelNode(fontNamed: "Menlo-Bold")
    private let banner = SKLabelNode(fontNamed: "Menlo-Bold")
    private let subtitle = SKLabelNode(fontNamed: "Menlo")
    private let message = SKLabelNode(fontNamed: "Menlo")
    private let scanlines = SKShapeNode()
    private let telemetryLeftPanel = SKShapeNode(rectOf: CGSize(width: 390, height: 152), cornerRadius: 9)
    private let telemetryRightPanel = SKShapeNode(rectOf: CGSize(width: 330, height: 152), cornerRadius: 9)
    private let telemetryLeftAccent = SKShapeNode(rectOf: CGSize(width: 3, height: 130))
    private let telemetryRightAccent = SKShapeNode(rectOf: CGSize(width: 3, height: 130))
    private let telemetryLeftHeading = SKLabelNode(fontNamed: "Menlo-Bold")
    private let telemetryRightHeading = SKLabelNode(fontNamed: "Menlo-Bold")
    private let telemetryLeftDetail = SKLabelNode(fontNamed: "Menlo")
    private let telemetryLeftFootnote = SKLabelNode(fontNamed: "Menlo")
    private let telemetryCoordinates = SKLabelNode(fontNamed: "Menlo")
    private let telemetryRightDetail = SKLabelNode(fontNamed: "Menlo")
    private let telemetryRightFootnote = SKLabelNode(fontNamed: "Menlo")
    private let telemetryAmmo = SKLabelNode(fontNamed: "Menlo-Bold")
    private let stagePanel = SKShapeNode(rectOf: CGSize(width: 470, height: 128), cornerRadius: 10)

    private var green = NSColor(calibratedRed: 0.35, green: 1.0, blue: 0.46, alpha: 1)
    private var muted = NSColor(calibratedRed: 0.10, green: 0.33, blue: 0.15, alpha: 1)
    private var accent = NSColor(calibratedRed: 1.0, green: 0.34, blue: 0.30, alpha: 1)

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = .black
        for band in skyBands {
            band.zPosition = 0.1
            band.strokeColor = .clear
            addChild(band)
        }
        for (layer, z) in [
            (distantMountains, 0.8), (middleMountains, 1.25),
            (nearMountains, 1.8), (horizonMist, 2.3)
        ] {
            layer.zPosition = z
            layer.strokeColor = .clear
            addChild(layer)
        }
        glassLayer.zPosition = 3.7
        addChild(glassLayer)
        for (node, layer) in [(radarEnemyContacts, 13.3), (radarProjectileGlow, 13.6),
                               (radarProjectileCore, 13.8)] {
            node.zPosition = layer
            addChild(node)
        }

        for (layer, z) in [
            (farSkyline, 1.0), (skyline, 2.0), (ground, 3.0), (structures, 4.0),
            (opponentLines, 5.0), (shotLines, 6.0),
            (modernFriendlyShells, 6.2), (modernHostileShells, 6.3),
            (flashLines, 7.0),
            (scanlines, 8.0), (reticle, 10.0), (hudLines, 12.0), (radar, 13.0)
        ] {
            layer.zPosition = z
            layer.lineCap = .round
            layer.lineJoin = .round
            layer.fillColor = .clear
            addChild(layer)
        }

        for panel in [telemetryLeftPanel, telemetryRightPanel] {
            panel.zPosition = 11
            panel.lineWidth = 0.8
            addChild(panel)
        }
        for rail in [telemetryLeftAccent, telemetryRightAccent] {
            rail.zPosition = 12
            rail.strokeColor = .clear
            addChild(rail)
        }
        stagePanel.zPosition = 18
        stagePanel.lineWidth = 1.2
        addChild(stagePanel)
        shieldBorder.zPosition = 9.0
        shieldBorder.fillColor = .clear
        shieldBorder.lineWidth = 3.0
        shieldBorder.isHidden = true
        addChild(shieldBorder)
        shieldNotice.zPosition = 16.0
        shieldNotice.fontSize = 15
        shieldNotice.horizontalAlignmentMode = .center
        shieldNotice.verticalAlignmentMode = .center
        shieldNotice.isHidden = true
        addChild(shieldNotice)
        for (label, z) in [
            (telemetryLeftHeading, 15.0), (telemetryRightHeading, 15.0),
            (telemetryLeftDetail, 15.0), (telemetryLeftFootnote, 15.0),
            (telemetryCoordinates, 15.0), (telemetryRightDetail, 15.0),
            (telemetryRightFootnote, 15.0), (telemetryAmmo, 15.0)
        ] {
            label.zPosition = z
            label.verticalAlignmentMode = .center
            addChild(label)
        }
        telemetryLeftHeading.text = "VECTOR SIEGE  //  TARGETING"
        telemetryRightHeading.text = "SYSTEMS  //  COMBAT STATUS"
        telemetryLeftHeading.horizontalAlignmentMode = .left
        telemetryLeftDetail.horizontalAlignmentMode = .left
        telemetryLeftFootnote.horizontalAlignmentMode = .left
        telemetryCoordinates.horizontalAlignmentMode = .left
        telemetryRightHeading.horizontalAlignmentMode = .right
        telemetryRightDetail.horizontalAlignmentMode = .right
        telemetryRightFootnote.horizontalAlignmentMode = .right
        telemetryAmmo.horizontalAlignmentMode = .right
        // Deliberate hierarchy: small section captions, medium supporting readouts,
        // and larger speed, score and ammunition values. Keep rows tightly stacked.
        for headingNode in [telemetryLeftHeading, telemetryRightHeading] { headingNode.fontSize = 9 }
        telemetryLeftDetail.fontSize = 11
        telemetryRightDetail.fontSize = 11
        telemetryLeftFootnote.fontSize = 9
        telemetryRightFootnote.fontSize = 10
        telemetryCoordinates.fontSize = 10
        telemetryAmmo.fontSize = 13

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
        let newlyPressed = !pressedKeys.contains(code)
        pressedKeys.insert(code)
        if repeatEvent || !newlyPressed { return }
        switch code {
        case 123, 0: // Left arrow / A: 0.5-degree tap
            if round == .playing { heading = wrapAngle(heading - PrecisionSteering.tapAngle) }
        case 124, 2: // Right arrow / D: 0.5-degree tap
            if round == .playing { heading = wrapAngle(heading + PrecisionSteering.tapAngle) }
        case 36, 76: // Return / keypad Enter
            if round == .title || round == .gameOver { restart() }
        case 35: // P
            if round == .playing { round = .paused }
            else if round == .paused { round = .playing }
        case 15: // R
            restart()
        case 8: // C
            displayMode = displayMode == .classic ? .modern : .classic
        case 17: // T: show extra local diagnostic details
            showDetailedTelemetry.toggle()
        case 56, 60: // Shift, usually delivered via flagsChanged instead
            triggerShield()
        default: break
        }
    }

    func released(_ code: UInt16) {
        pressedKeys.remove(code)
        if !key(123, 0, 124, 2) {
            steerHoldSeconds = 0
            previousSteerDirection = 0
        }
    }

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
        shotTally = ShotTally()
        observedFPS = 60
        driveSpeed = 0
        turnMotion = 0
        suspension.reset()
        heading = 0
        steerHoldSeconds = 0
        previousSteerDirection = 0
        tankPosition = GroundPoint(0, 0)
        gameClock = 0
        cannon = CannonMagazine()
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
        let elapsedFrame = lastUpdateTime == 0 ? 0.0 : currentTime - lastUpdateTime
        if elapsedFrame > 0.001 && elapsedFrame < 1 {
            observedFPS = 0.92 * observedFPS + 0.08 * min(240, 1.0 / elapsedFrame)
        }
        let dt = lastUpdateTime == 0 ? 0.0 : min(0.04, max(0, currentTime - lastUpdateTime))
        lastUpdateTime = currentTime
        if round != .paused { gameClock += dt }
        if round == .playing { tick(dt) }
        if round == .title { pulse += dt }
        let playing = round == .playing
        movementAudio.update(
            moving: playing ? min(1, abs(driveSpeed) / 16.5) : 0,
            turning: playing ? turnMotion : 0,
            enabled: playing && soundOn, dt: max(dt, 0.016))
        render()
    }

    private func tick(_ dt: Double) {
        cannon.advance(by: dt)
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
        if usingTreads {
            // Explicit tread driving retains its original, immediate turn response.
            steerHoldSeconds = 0
            previousSteerDirection = 0
            heading = wrapAngle(heading + turn * 1.65 * 1.1 * dt)
        } else if mainTurn != 0 {
            if mainTurn != previousSteerDirection { steerHoldSeconds = 0 }
            previousSteerDirection = mainTurn
            steerHoldSeconds += dt
            let turnRate = PrecisionSteering.heldRate(elapsed: steerHoldSeconds)
            heading = wrapAngle(heading + mainTurn * turnRate * dt)
        } else {
            steerHoldSeconds = 0
            previousSteerDirection = 0
        }
        if abs(driveSpeed) > 0.01 {
            let proposed = tankPosition + facing(heading) * (driveSpeed * dt)
            if !blocked(proposed, radius: 1.6) { tankPosition = proposed }
            else { driveSpeed *= -0.12 }
        }
        // Suspension reacts to braking and collisions; a damped rebound dies away
        // instead of drifting the actual tank heading or changing its shot trajectory.
        suspension.update(speed: driveSpeed, dt: dt)
        turnMotion += (abs(turn) - turnMotion) * min(1, dt * 12)
        if key(49) && cannon.canFire {
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
            if shell.timeLeft <= 0 {
                if !shell.hostile { shotTally.miss() }
                continue
            }
            if obstacles.contains(where: { segmentHitsObstacle(old, shell.center, $0) }) {
                if !shell.hostile { shotTally.miss() }
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
                        shotTally.hit()
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
                for shell in shells where !shell.hostile { shotTally.miss() }
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
        guard cannon.fire() else { return }
        shotTally.fire()
        let direction = facing(heading)
        shells.append(Shell(center: tankPosition + direction * 2.5,
                            direction: direction, hostile: false, timeLeft: 1.55))
        pulse = 0.13
        sound("shot.wav")
    }

    private func triggerShield() {
        guard round == .playing && shieldCooldown <= 0 && shieldDuration <= 0 else { return }
        shieldDuration = 5.0
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

    private func targetTelemetry() -> (range: Double, error: Double)? {
        enemies.compactMap { foe -> (range: Double, error: Double)? in
            let difference = foe.center - tankPosition
            let distance = difference.length
            let error = wrapAngle(atan2(difference.x, difference.z) - heading)
            guard distance < 150, abs(error) < .pi / 2 else { return nil }
            return (distance, error)
        }.min(by: { abs($0.error) < abs($1.error) })
    }

    /// Manual, local-only snapshot for copying into bug reports. No automatic upload.
    func feedbackReport() -> String {
        let mode = displayMode == .classic ? "Classic" : "Modern"
        let state: String
        switch round {
        case .title: state = "Title"
        case .playing: state = "Playing"
        case .paused: state = "Paused"
        case .gameOver: state = "Game over"
        }
        let bearing = (heading * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let target = targetTelemetry().map {
            String(format: "%.1f units, aim error %+.2f degrees", $0.range, $0.error * 180 / .pi)
        } ?? "None in front"
        let accuracy = shotTally.hitPercentage
        return """
        VECTOR SIEGE // PLAYTEST TELEMETRY
        Display: \(mode)  Difficulty: \(threatLevel.rawValue)  State: \(state)
        Wave: \(wave)  Score: \(score)  Best: \(bestScore)  Lives: \(lives)
        Heading: \(String(format: "%.2f", bearing)) degrees
        Drive speed: \(String(format: "%.2f", driveSpeed)) units/s
        World position: \(String(format: "x %.1f, z %.1f", tankPosition.x, tankPosition.z))
        Target: \(target)
        Shots: \(shotTally.fired)  Hits: \(shotTally.hits)  Confirmed misses: \(shotTally.misses)
        Hit/miss ratio: \(shotTally.hits):\(shotTally.misses)  Resolved hit rate: \(String(format: "%.1f%%", accuracy))
        In flight: \(shotTally.pending)
        Ammo: \(cannon.roundsRemaining)/\(CannonMagazine.capacity)  Cannon: \(cannon.statusText)
        Last reload duration: \(String(format: "%.2f", cannon.lastReloadDuration)) seconds (fixed 1s)
        Enemies: \(enemies.count)  Projectiles: \(shells.count)
        FPS (smoothed): \(String(format: "%.1f", observedFPS))
        Shield: \(shieldDuration > 0 ? String(format: "Active %.1fs remaining", shieldDuration) : shieldCooldown > 0 ? "Recharging" : "Ready")
        Runtime: \(String(format: "%.1f", gameClock)) seconds
        Note: Manually copied from the game. No data sent automatically.
        """
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
            (ground, displayMode == .classic ? muted.withAlphaComponent(0.34) : muted,
             displayMode == .classic ? 0.65 : 0.85,
             displayMode == .classic ? 0.0 : 0.7),
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
        let modern = displayMode == .modern
        modernFriendlyShells.isHidden = !modern
        modernHostileShells.isHidden = !modern
        modernFriendlyShells.strokeColor = NSColor(calibratedRed: 1, green: 0.89, blue: 0.35, alpha: 0.98)
        modernHostileShells.strokeColor = NSColor(calibratedRed: 1, green: 0.40, blue: 0.22, alpha: 0.94)
        for shellNode in [modernFriendlyShells, modernHostileShells] {
            shellNode.fillColor = .clear
            shellNode.lineWidth = 1.65
            shellNode.glowWidth = modern ? 3.5 : 0
        }
        glassLayer.isHidden = !modern
        for band in skyBands { band.isHidden = !modern }
        for layer in [distantMountains, middleMountains, nearMountains, horizonMist] {
            layer.isHidden = !modern
        }
        distantMountains.fillColor = NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.22, alpha: 0.92)
        middleMountains.fillColor = NSColor(calibratedRed: 0.085, green: 0.18, blue: 0.21, alpha: 0.94)
        nearMountains.fillColor = NSColor(calibratedRed: 0.035, green: 0.115, blue: 0.125, alpha: 0.98)
        horizonMist.fillColor = NSColor(calibratedRed: 0.25, green: 0.65, blue: 0.67, alpha: 0.06)
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
        radarEnemyContacts.strokeColor = accent
        radarEnemyContacts.fillColor = accent.withAlphaComponent(0.82)
        radarEnemyContacts.lineWidth = 0.5
        radarProjectileGlow.strokeColor = .clear
        radarProjectileGlow.fillColor = NSColor(calibratedRed: 1, green: 0.81, blue: 0.11, alpha: 0.24)
        radarProjectileGlow.glowWidth = 9
        radarProjectileCore.strokeColor = NSColor(calibratedRed: 1, green: 0.96, blue: 0.41, alpha: 0.98)
        radarProjectileCore.fillColor = NSColor(calibratedRed: 1, green: 0.84, blue: 0.13, alpha: 1)
        radarProjectileCore.glowWidth = 5
        radarProjectileCore.lineWidth = 1.1

        let amber = NSColor(calibratedRed: 1, green: 0.72, blue: 0.40, alpha: 1)
        let panelFill = NSColor(calibratedRed: 0.018, green: 0.045, blue: 0.044, alpha: 0.90)
        for panel in [telemetryLeftPanel, telemetryRightPanel] {
            panel.fillColor = panelFill
            panel.strokeColor = amber.withAlphaComponent(displayMode == .classic ? 0.32 : 0.50)
        }
        for rail in [telemetryLeftAccent, telemetryRightAccent] { rail.fillColor = amber }
        for label in [telemetryLeftHeading, telemetryRightHeading] { label.fontColor = amber }
        for label in [telemetryLeftDetail, telemetryLeftFootnote, telemetryCoordinates,
                      telemetryRightDetail, telemetryRightFootnote, telemetryAmmo] {
            label.fontColor = green.withAlphaComponent(0.86)
        }
        stagePanel.fillColor = NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.05, alpha: 0.94)
        stagePanel.strokeColor = amber.withAlphaComponent(0.55)
    }

    private func render() {
        let w = Double(size.width)
        let h = Double(size.height)
        guard w > 100 && h > 100 else { return }
        let camera = CameraProjection(position: tankPosition, yaw: heading,
                                      viewportWidth: w, viewportHeight: h)
        var worldCamera = camera
        let driveAmount = min(1.0, abs(driveSpeed) / 16.5)
        let turnAmount = min(1.0, turnMotion)
        // Small patterned shudder reads as track vibration, but the sight / HUD
        // stays fixed on the actual aim axis for precise, repeatable targeting.
        worldCamera.eyeHeight += driveAmount * (0.015 * sin(gameClock * 24)
                                               + 0.012 * sin(gameClock * 11.5))
        worldCamera.cameraLateral = driveAmount * 0.018 * sin(gameClock * 19)
                                   + turnAmount * 0.024 * sin(gameClock * 15.3)
        worldCamera.pitchPoints = suspension.pitch * 138
                                  + driveAmount * 0.9 * sin(gameClock * 21)
        renderMountains(worldCamera)
        renderGround(worldCamera)
        renderObjects(worldCamera)
        renderProjectiles(worldCamera)
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
        let distantFill = CGMutablePath()
        let middleFill = CGMutablePath()
        let closeFill = CGMutablePath()
        let width = c.viewportWidth
        let step = 10.0
        let samples = Int(ceil(width / step)) + 2

        // Sky bands imitate atmospheric scattering with no textures or asset downloads.
        // The brighter lower bands shift very slightly with heading, not with frame time.
        if displayMode == .modern {
            let skyBottom = c.horizon - 8
            let bandHeight = (c.viewportHeight - skyBottom) / Double(skyBands.count)
            for i in skyBands.indices {
                let y = skyBottom + Double(i) * bandHeight
                skyBands[i].path = CGPath(rect: CGRect(x: 0, y: y, width: width + 1,
                                                        height: bandHeight + 1), transform: nil)
                let t = Double(i) / Double(max(1, skyBands.count - 1))
                skyBands[i].fillColor = NSColor(
                    calibratedRed: CGFloat(0.045 - t * 0.027),
                    green: CGFloat(0.105 - t * 0.072),
                    blue: CGFloat(0.16 - t * 0.083), alpha: 1)
            }
        }
        for i in 0...samples {
            let x = min(width + 10, Double(i) * step - 10)
            let azimuth = heading + atan2((x - width / 2) / c.focal, 1)
            let back = point(x, c.horizon + ridge(azimuth + 0.6, multiplier: 0.47))
            let front = point(x, c.horizon + ridge(azimuth, multiplier: 1.0))
            if i == 0 {
                farPath.move(to: back)
                nearPath.move(to: front)
                distantFill.move(to: point(x, c.horizon - 50))
                middleFill.move(to: point(x, c.horizon - 50))
                closeFill.move(to: point(x, c.horizon - 50))
                distantFill.addLine(to: back)
                middleFill.addLine(to: point(x, c.horizon + ridge(azimuth + 0.12, multiplier: 0.72)))
                closeFill.addLine(to: front)
            } else {
                farPath.addLine(to: back)
                nearPath.addLine(to: front)
                distantFill.addLine(to: back)
                middleFill.addLine(to: point(x, c.horizon + ridge(azimuth + 0.12, multiplier: 0.72)))
                closeFill.addLine(to: front)
            }
        }
        for path in [distantFill, middleFill, closeFill] {
            path.addLine(to: point(width + 10, c.horizon - 55))
            path.closeSubpath()
        }
        farSkyline.path = farPath
        skyline.path = nearPath
        if displayMode == .modern {
            distantMountains.path = distantFill
            middleMountains.path = middleFill
            nearMountains.path = closeFill
            horizonMist.path = CGPath(rect: CGRect(x: 0, y: c.horizon - 10,
                                                   width: width, height: 26), transform: nil)
        }
    }

    private func renderGround(_ c: CameraProjection) {
        let path = CGMutablePath()
        // A world-anchored perspective grid in both modes. Classic uses wider,
        // dimmer green lines while Modern preserves its existing denser grid.
        let classic = displayMode == .classic
        let spacing = classic ? 18.0 : 12.0
        let extent = classic ? 144.0 : 156.0
        let count = classic ? 8 : 13
        let baseX = floor(tankPosition.x / spacing) * spacing
        let baseZ = floor(tankPosition.z / spacing) * spacing
        for k in -count...count {
            let x = baseX + Double(k) * spacing
            line(path, WorldPoint(x, 0, baseZ - extent),
                 WorldPoint(x, 0, baseZ + extent), c)
            let z = baseZ + Double(k) * spacing
            line(path, WorldPoint(baseX - extent, 0, z),
                 WorldPoint(baseX + extent, 0, z), c)
        }
        ground.path = path
    }

    private func renderObjects(_ c: CameraProjection) {
        let structurePath = CGMutablePath()
        var facets: [GlassFace] = []
        for o in obstacles {
            // Culling far outside the visible scene.
            let offset = o.center - tankPosition
            if offset.length > 190 { continue }
            if o.kind == .pyramid { drawPyramid(o, on: structurePath, camera: c) }
            else { drawBlock(o, on: structurePath, camera: c) }
            if displayMode == .modern { facets.append(contentsOf: glassFacets(for: o, camera: c)) }
        }
        structures.path = structurePath
        updateGlassFaces(facets, camera: c)

        let enemyPath = CGMutablePath()
        for enemy in enemies {
            if enemy.center.distance(to: tankPosition) > 170 { continue }
            if enemy.kind == .saucer { drawSaucer(enemy, on: enemyPath, camera: c) }
            else { drawTank(enemy, on: enemyPath, camera: c) }
        }
        opponentLines.path = enemyPath
    }

    // Filled translucent polygons are rendered back-to-front beneath the vector
    // outlines. Near-plane clipping prevents screen-sized spikes when driving close.
    private func glassFacePath(_ points: [WorldPoint], camera c: CameraProjection) -> CGPath? {
        struct Vertex {
            var right: Double
            var up: Double
            var forward: Double
        }
        var clipped = points.map {
            let v = c.local($0)
            return Vertex(right: v.right, up: v.up, forward: v.forward)
        }
        guard clipped.count >= 3 else { return nil }
        let near = 0.8
        var output: [Vertex] = []
        var previous = clipped[clipped.count - 1]
        for current in clipped {
            let wasInside = previous.forward >= near
            let isInside = current.forward >= near
            if wasInside != isInside {
                let t = (near - previous.forward) / (current.forward - previous.forward)
                output.append(Vertex(right: previous.right + (current.right - previous.right) * t,
                                     up: previous.up + (current.up - previous.up) * t,
                                     forward: near))
            }
            if isInside { output.append(current) }
            previous = current
        }
        clipped = output
        guard clipped.count >= 3 else { return nil }
        let path = CGMutablePath()
        for (i, p) in clipped.enumerated() {
            let projected = c.screen(right: p.right, up: p.up, forward: p.forward)
            guard projected.x.isFinite && projected.y.isFinite,
                  abs(projected.x) < 30000 && abs(projected.y) < 30000 else { return nil }
            if i == 0 { path.move(to: point(projected.x, projected.y)) }
            else { path.addLine(to: point(projected.x, projected.y)) }
        }
        path.closeSubpath()
        return path
    }

    private func glassFacets(for o: Obstacle, camera c: CameraProjection) -> [GlassFace] {
        let s = o.size
        let bottom = [
            WorldPoint(o.center.x-s, 0, o.center.z-s),
            WorldPoint(o.center.x+s, 0, o.center.z-s),
            WorldPoint(o.center.x+s, 0, o.center.z+s),
            WorldPoint(o.center.x-s, 0, o.center.z+s)
        ]
        let topHeight = o.kind == .pyramid ? s * 1.28 : s * 1.35
        let top = bottom.map { WorldPoint($0.x, topHeight, $0.z) }
        let apex = WorldPoint(o.center.x, topHeight, o.center.z)
        var polygons: [[WorldPoint]] = []
        if o.kind == .pyramid {
            for i in 0..<4 { polygons.append([bottom[i], bottom[(i+1)%4], apex]) }
        } else {
            for i in 0..<4 {
                polygons.append([bottom[i], bottom[(i+1)%4], top[(i+1)%4], top[i]])
            }
            polygons.append(top)
        }
        return polygons.enumerated().map { index, vertices in
            let z = vertices.reduce(0.0) { $0 + c.local($1).forward } / Double(vertices.count)
            return GlassFace(vertices: vertices, depth: z, tint: index)
        }
    }

    private func updateGlassFaces(_ facets: [GlassFace], camera c: CameraProjection) {
        guard displayMode == .modern else {
            for face in glassFacePool { face.isHidden = true }
            return
        }
        let palette: [NSColor] = [
            NSColor(calibratedRed: 0.13, green: 0.43, blue: 0.51, alpha: 0.23),
            NSColor(calibratedRed: 0.32, green: 0.71, blue: 0.74, alpha: 0.17),
            NSColor(calibratedRed: 0.08, green: 0.25, blue: 0.35, alpha: 0.32),
            NSColor(calibratedRed: 0.40, green: 0.77, blue: 0.76, alpha: 0.18),
            NSColor(calibratedRed: 0.60, green: 0.91, blue: 0.89, alpha: 0.21)
        ]
        var visible = 0
        for facet in facets.sorted(by: { $0.depth > $1.depth }) {
            guard let path = glassFacePath(facet.vertices, camera: c) else { continue }
            if visible >= glassFacePool.count {
                let face = SKShapeNode()
                face.lineWidth = 0.5
                face.strokeColor = NSColor(calibratedRed: 0.71, green: 0.98, blue: 0.97, alpha: 0.25)
                glassLayer.addChild(face)
                glassFacePool.append(face)
            }
            let face = glassFacePool[visible]
            face.isHidden = false
            face.path = path
            face.fillColor = palette[facet.tint % palette.count]
            face.zPosition = CGFloat(visible) * 0.001
            visible += 1
        }
        for i in visible..<glassFacePool.count { glassFacePool[i].isHidden = true }
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

        // Classic keeps the original simple arcade tank. Modern alone adds
        // hull armor, detailed treads, road wheels, turret optics and hardware.
        guard displayMode == .modern else { return }

        // Faceted glacis armor, sloped hull seams and rear engine deck.
        polygon([v(-1.82, 1.18, 2.15), v(1.82, 1.18, 2.15),
                 v(1.58, 0.62, 3.25), v(-1.58, 0.62, 3.25)])
        line(path, v(-1.7, 0.75, 3.0), v(1.7, 0.75, 3.0), c)
        line(path, v(-1.65, 1.20, -1.95), v(1.65, 1.20, -1.95), c)
        for side in [-1.0, 1.0] {
            // Segmented armored track guards, track plates and side skirts.
            line(path, v(side*2.48, 0.90, -2.65), v(side*2.48, 0.90, 2.55), c)
            line(path, v(side*2.48, 0.16, -2.75), v(side*2.48, 0.16, 2.55), c)
            for index in -6...6 {
                let z = Double(index) * 0.42
                line(path, v(side*2.52, 0.10, z), v(side*2.52, 0.85, z + 0.09), c)
            }
            // Five eight-segment road wheels on each track.
            for index in -2...2 {
                let z = Double(index) * 1.02
                let wheelY = 0.44
                let radius = 0.31
                for j in 0..<8 {
                    let a = Double(j) * .pi / 4
                    let b = Double(j + 1) * .pi / 4
                    line(path,
                         v(side*2.56, wheelY + sin(a)*radius, z + cos(a)*radius),
                         v(side*2.56, wheelY + sin(b)*radius, z + cos(b)*radius), c)
                }
                line(path, v(side*2.56, wheelY, z),
                     v(side*2.59, wheelY + 0.11, z), c)
            }
            // Angled turret cheek armor and side lifting brackets.
            line(path, v(side*1.12, 1.38, 0.98), v(side*0.88, 2.10, 0.72), c)
            line(path, v(side*1.05, 1.55, -1.13), v(side*0.79, 2.07, -0.84), c)
            polygon([v(side*0.94, 1.89, -0.98), v(side*0.94, 1.89, -0.60),
                     v(side*0.70, 2.18, -0.64), v(side*0.70, 2.18, -0.91)])
        }
        // Turret roof, commander's hatch perimeter, sight and optics.
        polygon([v(-0.81, 2.06, -0.94), v(0.81, 2.06, -0.94),
                 v(0.81, 2.06, 0.84), v(-0.81, 2.06, 0.84)])
        for index in 0..<12 {
            let a = Double(index) * .pi / 6
            let b = Double(index + 1) * .pi / 6
            line(path,
                 v(-0.29 + cos(a)*0.42, 2.12, -0.25 + sin(a)*0.42),
                 v(-0.29 + cos(b)*0.42, 2.12, -0.25 + sin(b)*0.42), c)
        }
        polygon([v(0.22, 2.10, 0.18), v(0.55, 2.10, 0.18),
                 v(0.55, 2.46, 0.48), v(0.22, 2.46, 0.48)])
        line(path, v(0.38, 2.46, 0.48), v(0.38, 2.65, 0.51), c)

        // Recoil housing and three barrel reinforcing collars / muzzle ring.
        polygon([v(-0.29, 1.95, 1.28), v(0.29, 1.95, 1.28),
                 v(0.29, 1.61, 1.28), v(-0.29, 1.61, 1.28)])
        for z in [1.15, 3.1, 4.5] {
            polygon([v(-0.25, 1.97, z), v(0.25, 1.97, z),
                     v(0.25, 1.63, z), v(-0.25, 1.63, z)])
        }
        line(path, v(0, 1.80, 4.5), v(0, 1.80, 4.83), c)

        // Engine louvers, rear tow loops and whip antenna.
        for index in -3...3 {
            let x = Double(index) * 0.39
            line(path, v(x, 1.29, -1.86), v(x, 1.29, -2.43), c)
        }
        for side in [-1.0, 1.0] {
            polygon([v(side*1.31, 0.52, -3.07),
                     v(side*1.66, 0.52, -3.07),
                     v(side*1.66, 0.86, -3.07),
                     v(side*1.31, 0.86, -3.07)])
        }
        line(path, v(-0.73, 2.03, -0.76), v(-0.89, 3.42, -0.83), c)
        line(path, v(-0.89, 3.42, -0.83), v(-0.84, 3.71, -0.81), c)
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
        let friendlyWire = CGMutablePath()
        let hostileWire = CGMutablePath()
        for shell in shells {
            let height = shell.hostile ? 1.5 : 1.65
            if displayMode == .classic {
                // Preserve the original compact tracer in Classic.
                let p = WorldPoint(shell.center, height: height)
                let tail = shell.center - shell.direction * (shell.hostile ? 2.4 : 3.8)
                line(bulletPath, p, WorldPoint(tail, height: height), c)
                line(bulletPath, WorldPoint(shell.center.x, height-0.28, shell.center.z),
                     WorldPoint(shell.center.x, height+0.28, shell.center.z), c)
            } else {
                // Modern rounds are small three-dimensional wireframe darts:
                // pointed nose, two diamond rings, longitudinal ribs and
                // stabilizing fins. Their actual physics remain unchanged.
                let path = shell.hostile ? hostileWire : friendlyWire
                let direction = shell.direction.normalized
                let lateral = GroundPoint(direction.z, -direction.x)
                let radius = shell.hostile ? 0.26 : 0.38
                let tip = shell.center + direction * 1.2
                let middle = shell.center + direction * 0.15
                let rear = shell.center - direction * 0.75
                let end = shell.center - direction * 1.55
                func vertex(_ center: GroundPoint, _ side: Double, _ rise: Double) -> WorldPoint {
                    WorldPoint(center.x + lateral.x * side, height + rise,
                               center.z + lateral.z * side)
                }
                let nose = vertex(tip, 0, 0)
                let tailTip = vertex(end, 0, 0)
                let frontRing = [
                    vertex(middle, radius, 0), vertex(middle, 0, radius),
                    vertex(middle, -radius, 0), vertex(middle, 0, -radius)
                ]
                let backRing = [
                    vertex(rear, radius * 0.75, 0), vertex(rear, 0, radius * 0.75),
                    vertex(rear, -radius * 0.75, 0), vertex(rear, 0, -radius * 0.75)
                ]
                for i in 0..<4 {
                    let next = (i + 1) % 4
                    line(path, nose, frontRing[i], c)
                    line(path, frontRing[i], frontRing[next], c)
                    line(path, frontRing[i], backRing[i], c)
                    line(path, backRing[i], backRing[next], c)
                    line(path, backRing[i], tailTip, c)
                }
                for side in [-1.0, 1.0] {
                    let fin = vertex(end, side * radius * 1.65, 0)
                    line(path, frontRing[side > 0 ? 0 : 2], fin, c)
                    line(path, fin, tailTip, c)
                }
                // A narrow illuminated tracer axis makes fast rounds readable
                // without changing their position or hit detection.
                line(path, nose, tailTip, c)
            }
        }
        shotLines.path = bulletPath
        modernFriendlyShells.path = friendlyWire
        modernHostileShells.path = hostileWire

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
        let radarX = 90.0
        let radarY = h - 92
        let radarRadius = 39.0

        // Compact corner instruments: fewer blank vertical gaps, more playfield visible.
        let leftPanelWidth = 390.0
        let rightPanelWidth = 330.0
        let panelHeight = 152.0
        func panelRect(width: Double) -> CGPath {
            CGPath(roundedRect: CGRect(x: -width / 2, y: -panelHeight / 2,
                                       width: width, height: panelHeight),
                   cornerWidth: 9, cornerHeight: 9, transform: nil)
        }
        telemetryLeftPanel.path = panelRect(width: leftPanelWidth)
        telemetryRightPanel.path = panelRect(width: rightPanelWidth)
        telemetryLeftPanel.position = point(14 + leftPanelWidth / 2, h - 81)
        telemetryRightPanel.position = point(w - 14 - rightPanelWidth / 2, h - 81)
        telemetryLeftAccent.position = point(20, h - 81)
        telemetryRightAccent.position = point(w - 20, h - 81)
        telemetryLeftHeading.position = point(162, h - 33)
        telemetryRightHeading.position = point(w - 34, h - 33)
        telemetryLeftDetail.position = point(162, h - 81)
        telemetryLeftFootnote.position = point(162, h - 104)
        telemetryCoordinates.position = point(162, h - 127)
        telemetryRightDetail.position = point(w - 34, h - 81)
        telemetryRightFootnote.position = point(w - 34, h - 104)
        telemetryAmmo.position = point(w - 34, h - 129)
        // Slim radar divider, shortened to match the compressed instrument panel.
        segment(hp, point(149, h - 136), point(149, h - 48))
        hudLines.path = hp

        let circle = CGRect(x: radarX - radarRadius, y: radarY - radarRadius,
                            width: radarRadius*2, height: radarRadius*2)
        rp.addEllipse(in: circle)
        segment(rp, point(radarX, radarY-radarRadius), point(radarX, radarY+radarRadius))
        segment(rp, point(radarX-radarRadius, radarY), point(radarX+radarRadius, radarY))
        let sweepAngle = gameClock * 1.45
        segment(rp, point(radarX, radarY),
                point(radarX+sin(sweepAngle)*radarRadius, radarY+cos(sweepAngle)*radarRadius))
        let enemyContacts = CGMutablePath()
        let projectileHalos = CGMutablePath()
        let projectileDots = CGMutablePath()
        // All contacts share the same player-relative, heading-rotated radar grid.
        func radarPoint(_ center: GroundPoint) -> CGPoint? {
            let dx = center.x - tankPosition.x
            let dz = center.z - tankPosition.z
            let right = dx * cos(heading) - dz * sin(heading)
            let forward = dx * sin(heading) + dz * cos(heading)
            guard hypot(right, forward) <= 105 else { return nil }
            return point(radarX + right / 105 * radarRadius,
                         radarY + forward / 105 * radarRadius)
        }
        for foe in enemies {
            guard let contact = radarPoint(foe.center) else { continue }
            let blip = foe.kind == .hunter ? 3.8 : 2.6
            enemyContacts.addRect(CGRect(x: contact.x - blip/2, y: contact.y - blip/2,
                                         width: blip, height: blip))
        }
        for shell in shells {
            guard let contact = radarPoint(shell.center) else { continue }
            let radius = shell.hostile ? 2.0 : 2.8
            projectileHalos.addEllipse(in: CGRect(x: contact.x - 4.7, y: contact.y - 4.7,
                                                   width: 9.4, height: 9.4))
            projectileDots.addEllipse(in: CGRect(x: contact.x - radius, y: contact.y - radius,
                                                  width: radius * 2, height: radius * 2))
        }
        radar.path = rp
        radarEnemyContacts.path = enemyContacts
        radarProjectileGlow.path = projectileHalos
        radarProjectileCore.path = projectileDots

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

        // The border and a central countdown show protection without obscuring
        // the battlefield. Both blink and fade during the last second.
        let shieldOnline = shieldDuration > 0 && (round == .playing || round == .paused)
        shieldBorder.isHidden = !shieldOnline
        shieldNotice.isHidden = !shieldOnline
        if shieldOnline {
            let finalSecond = shieldDuration <= 1.0
            let fade = finalSecond ? min(1.0, shieldDuration * 2.8) : 1.0
            let blink = finalSecond ? 0.28 + 0.72 * abs(sin(gameClock * 17.0)) : 1.0
            let opacity = CGFloat(fade * blink)
            shieldBorder.path = CGPath(
                roundedRect: CGRect(x: 9, y: 15, width: max(1, w - 18), height: max(1, h - 30)),
                cornerWidth: 18, cornerHeight: 18, transform: nil)
            shieldBorder.strokeColor = (finalSecond ? accent : green)
                .withAlphaComponent(0.60 * opacity)
            shieldBorder.glowWidth = displayMode == .modern ? 9.0 : 3.0
            shieldNotice.position = point(w / 2, 82)
            shieldNotice.fontColor = (finalSecond ? accent : green)
                .withAlphaComponent(0.95 * opacity)
            shieldNotice.text = finalSecond
                ? String(format: "SHIELD FAILING  %.1fS", shieldDuration)
                : String(format: "SHIELD ACTIVE  %.1fS", shieldDuration)
        }

        leftHUD.position = point(radarX, h - 33)
        leftHUD.horizontalAlignmentMode = .center
        leftHUD.fontSize = 9
        leftHUD.text = "RADAR / 105"
        midHUD.position = point(162, h - 57)
        midHUD.horizontalAlignmentMode = .left
        midHUD.fontSize = 15
        let compass = Int((heading * 180 / .pi + 360).truncatingRemainder(dividingBy: 360).rounded()) % 360
        midHUD.text = String(format: "HDG %03d°   SPD %05.1f", compass, driveSpeed)
        let target = targetTelemetry()
        telemetryLeftDetail.text = target.map {
            String(format: "TGT %03.0f   AIM %+05.1f°", $0.range, $0.error * 180 / .pi)
        } ?? "TGT ---   AIM ---"
        let accuracy = shotTally.hitPercentage
        // Only resolved projectiles count toward the ratio; F is still in flight.
        telemetryLeftFootnote.text = String(
            format: "H/M %02d:%02d   HIT %.0f%%   F %02d",
            shotTally.hits, shotTally.misses, accuracy, shotTally.pending)
        telemetryCoordinates.text = String(format: "POSITION   X %+.1f   Z %+.1f", tankPosition.x, tankPosition.z)
        rightHUD.position = point(w - 34, h - 57)
        rightHUD.horizontalAlignmentMode = .right
        rightHUD.fontSize = 15
        rightHUD.text = String(format: "SCORE %06d  BEST %06d", score, bestScore)
        telemetryRightDetail.text = String(format: "WAVE %02d   LIVES %d   %@", wave, lives, threatLevel.rawValue.uppercased())
        let shieldName = shieldDuration > 0
            ? String(format: "SHIELD ACTIVE %.1fs", shieldDuration)
            : shieldCooldown > 0
                ? String(format: "RECHARGING %.1fs", shieldCooldown)
                : "SHIELD READY [SHIFT]"
        telemetryRightFootnote.text = shieldName
        telemetryAmmo.text = String(format: "AMMO %02d/%02d   %@", cannon.roundsRemaining,
                                           CannonMagazine.capacity, cannon.statusText)
        telemetryAmmo.fontColor = cannon.isEmpty ? accent : green
        warning.position = point(w / 2, h - 163)
        warning.fontSize = 12
        warning.text = target.map { abs($0.error) < 0.055 && $0.range < 68 ? "TARGET ALIGNED" : "" }
            ?? (pendingWave > 0 ? "AREA SECURE" : "")

        let modeName = displayMode == .classic ? "CLASSIC CRT" : "ENHANCED VECTOR"
        message.position = point(w / 2, 47)
        message.fontSize = 11
        if showDetailedTelemetry {
            message.text = String(format: "FPS %.0f  |  POSITION %+.1f, %+.1f  |  ENEMIES %d  |  SHELLS %d  |  [T] MINIMIZE",
                                  observedFPS, tankPosition.x, tankPosition.z, enemies.count, shells.count)
        } else {
            message.text = modeName + "   //   [T] DIAGNOSTICS   //   COPY FEEDBACK IN TOOLBAR"
        }
        message.fontColor = shieldDuration > 0 ? green : accent

        stagePanel.position = point(w / 2, h * 0.61)
        stagePanel.isHidden = round == .playing && pendingWave <= 0
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

// Two low-level, seamlessly repeating procedural sounds. No external samples:
// AVAudioPlayer manages simple loops; volume tracks vehicle speed and steering.
private final class TankMotionAudio {
    private var engine: AVAudioPlayer?
    private var treads: AVAudioPlayer?
    private var driveLevel = 0.0
    private var turnLevel = 0.0

    init() {
        engine = try? AVAudioPlayer(data: Self.makeWAV(treads: false))
        treads = try? AVAudioPlayer(data: Self.makeWAV(treads: true))
        for player in [engine, treads] {
            player?.numberOfLoops = -1
            player?.volume = 0
            player?.prepareToPlay()
        }
    }

    func update(moving: Double, turning: Double, enabled: Bool, dt: Double) {
        let desiredDrive = enabled ? max(0, min(1, moving)) : 0
        let desiredTurn = enabled ? max(0, min(1, turning)) : 0
        let factor = min(1, max(0, dt) * 6)
        driveLevel += (desiredDrive - driveLevel) * factor
        turnLevel += (desiredTurn - turnLevel) * factor
        if desiredDrive > 0.001 || desiredTurn > 0.001 {
            if engine?.isPlaying == false { engine?.play() }
            if treads?.isPlaying == false { treads?.play() }
        }
        engine?.volume = Float(driveLevel * 0.16)
        treads?.volume = Float(turnLevel * 0.12)
        if !enabled && driveLevel < 0.002 && turnLevel < 0.002 {
            engine?.stop()
            treads?.stop()
        }
    }

    private static func makeWAV(treads: Bool) -> Data {
        let rate = 22_050
        let samples = rate * 2
        var bytes = Data(capacity: 44 + samples * 2)
        func put16(_ number: UInt16) {
            bytes.append(UInt8(truncatingIfNeeded: number))
            bytes.append(UInt8(truncatingIfNeeded: number >> 8))
        }
        func put32(_ number: UInt32) {
            put16(UInt16(truncatingIfNeeded: number))
            put16(UInt16(truncatingIfNeeded: number >> 16))
        }
        bytes.append(contentsOf: [82, 73, 70, 70]) // RIFF
        put32(UInt32(36 + samples * 2))
        bytes.append(contentsOf: [87, 65, 86, 69, 102, 109, 116, 32]) // WAVEfmt
        put32(16)
        put16(1) // uncompressed PCM
        put16(1) // mono
        put32(UInt32(rate))
        put32(UInt32(rate * 2))
        put16(2)
        put16(16)
        bytes.append(contentsOf: [100, 97, 116, 97]) // data
        put32(UInt32(samples * 2))
        var seed: UInt32 = treads ? 0xC2D6_6A11 : 0x95F2_A41B
        var lowNoise = 0.0
        let twoPi = 2.0 * Double.pi
        for i in 0..<samples {
            let t = Double(i) / Double(rate)
            seed = 1_664_525 &* seed &+ 1_013_904_223
            let noise = Double((seed >> 12) & 0xFFFF) / 32767.5 - 1
            lowNoise = 0.87 * lowNoise + 0.13 * noise
            let signal: Double
            if treads {
                let chatter = 0.45 + 0.55 * abs(sin(twoPi * 12.7 * t))
                signal = chatter * (0.55 * lowNoise + 0.12 * noise)
                         + 0.13 * sin(twoPi * 76 * t) * chatter
            } else {
                let idle = 0.40 * sin(twoPi * 43 * t)
                           + 0.20 * sin(twoPi * 86 * t)
                           + 0.12 * sin(twoPi * 129 * t)
                signal = idle + 0.55 * lowNoise + 0.09 * noise
            }
            // A short fade at loop boundaries prevents sudden sample discontinuity.
            let blend = min(1, Double(min(i, samples - 1 - i)) / 500)
            let clamped = max(-1.0, min(1.0, signal * blend * 0.75))
            put16(UInt16(bitPattern: Int16((clamped * 32767).rounded())))
        }
        return bytes
    }
}
