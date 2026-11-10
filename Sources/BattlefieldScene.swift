import SpriteKit
import AppKit
import AVFoundation

private struct Obstacle {
    enum Kind { case block, pyramid, tower, building, monolith }
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
    var customRules: SiegeRules?
    var activePresetID = ""
    private var rules: SiegeRules { (customRules ?? SiegeRules()).validated() }

    private var round: RoundState = .title
    private var pressedKeys: Set<UInt16> = []
    private var tankPosition = GroundPoint(0, 0)
    private var heading: Double = 0
    private var driveSpeed: Double = 0
    private var turnMotion: Double = 0
    private var suspension = TankSuspension()
    private lazy var movementAudio = TankMotionAudio()
    private lazy var proximityAudio = TankProximityAudio()
    private var proximityCountdown = 0.0
    private var nearestTankDistance: Double? = nil
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
    private var saucerPatrol = SaucerPatrolClock()
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
    private let radarPanel = SKShapeNode()
    private let rearPanel = SKShapeNode()
    private let rearView = SKCropNode()
    private let rearMask = SKShapeNode()
    private let rearGround = SKShapeNode()
    private let rearEnvironment = SKShapeNode()
    private let rearEnemies = SKShapeNode()
    private let rearShots = SKShapeNode()
    private let rearBackground = SKShapeNode()
    private let rearLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let proximityLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let radarObstacleContacts = SKShapeNode()
    private let radarProjectileGlow = SKShapeNode()
    private let radarProjectileCore = SKShapeNode()
    private let radarEnemyContacts = SKShapeNode()
    private let hudLines = SKShapeNode()
    private let leftHUD = SKLabelNode(fontNamed: "Menlo-Bold")
    private let rightHUD = SKLabelNode(fontNamed: "Menlo-Bold")
    private let midHUD = SKLabelNode(fontNamed: "Menlo-Bold")
    private let warning = SKLabelNode(fontNamed: "Menlo-Bold")
    private let banner = SKLabelNode(fontNamed: "Menlo-Bold")
    private let titleLogo = SKSpriteNode(imageNamed: "VectorSiegeLogo")
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

    // Modern-mode cockpit treatment. Separate decoration and text nodes make
    // every value live and keep Classic independent of the premium layout.
    private let modernCockpit = SKNode()
    private let modernTrim = SKShapeNode()
    private let modernLowerDash = SKShapeNode()
    private let modernLowerLines = SKShapeNode()
    private let modernHitRing = SKShapeNode()
    private let modernHitTrack = SKShapeNode()
    private let modernAmmoTrack = SKShapeNode()
    private let modernAmmoFill = SKShapeNode()
    private let modernShieldTrack = SKShapeNode()
    private let modernShieldFill = SKShapeNode()
    private let modernThreatPanel = SKShapeNode()
    private let modernBest = SKLabelNode(fontNamed: "Menlo")
    private let modernTankStatus = SKLabelNode(fontNamed: "Menlo-Bold")
    private let modernIntegrity = SKLabelNode(fontNamed: "Menlo")
    private let modernHitCaption = SKLabelNode(fontNamed: "Menlo-Bold")
    private let modernHitValue = SKLabelNode(fontNamed: "Menlo-Bold")
    private let modernCompassLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let modernHeadingValue = SKLabelNode(fontNamed: "Menlo-Bold")
    private let modernHeadingTicks = (0..<7).map { _ in SKLabelNode(fontNamed: "Menlo") }
    private let modernTerrainLabel = SKLabelNode(fontNamed: "Menlo")
    private let modernSectorValue = SKLabelNode(fontNamed: "Menlo-Bold")
    private let modernStatusText = SKLabelNode(fontNamed: "Menlo")
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

        radarPanel.zPosition = 11
        radarPanel.lineWidth = 0.8
        addChild(radarPanel)
        rearPanel.zPosition = 11
        rearPanel.lineWidth = 0.8
        addChild(rearPanel)
        rearView.zPosition = 12.5
        rearMask.path = CGPath(roundedRect: CGRect(x: -86, y: -54, width: 172, height: 108),
                               cornerWidth: 6, cornerHeight: 6, transform: nil)
        rearMask.fillColor = .white
        rearMask.strokeColor = .clear
        // Projection and crop coordinates are both bottom-left-relative.
        rearMask.position = .zero
        rearView.maskNode = rearMask
        for (shape, depth) in [(rearBackground, 0.0), (rearGround, 1.0),
                               (rearEnvironment, 2.0), (rearEnemies, 3.0),
                               (rearShots, 4.0)] {
            shape.zPosition = depth
            rearView.addChild(shape)
        }
        addChild(rearView)
        rearLabel.zPosition = 15
        rearLabel.fontSize = 10
        rearLabel.horizontalAlignmentMode = .center
        rearLabel.verticalAlignmentMode = .center
        addChild(rearLabel)
        proximityLabel.zPosition = 16
        proximityLabel.fontSize = 14
        proximityLabel.horizontalAlignmentMode = .center
        proximityLabel.verticalAlignmentMode = .center
        proximityLabel.isHidden = true
        addChild(proximityLabel)
        radarObstacleContacts.zPosition = 13.1
        addChild(radarObstacleContacts)
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
        modernCockpit.zPosition = 11.5
        addChild(modernCockpit)
        for (node, z) in [(modernTrim, 0.6), (modernLowerDash, 0.0),
                          (modernLowerLines, 0.7), (modernHitTrack, 0.8),
                          (modernHitRing, 0.9), (modernAmmoTrack, 0.6),
                          (modernAmmoFill, 0.7), (modernShieldTrack, 0.6),
                          (modernShieldFill, 0.7), (modernThreatPanel, 0.4)] {
            node.zPosition = z
            modernCockpit.addChild(node)
        }
        for label in [modernBest, modernTankStatus, modernIntegrity,
                      modernHitCaption, modernHitValue, modernCompassLabel,
                      modernHeadingValue, modernTerrainLabel,
                      modernSectorValue, modernStatusText] + modernHeadingTicks {
            label.zPosition = 4
            label.verticalAlignmentMode = .center
            modernCockpit.addChild(label)
        }
        for tick in modernHeadingTicks {
            tick.fontSize = 10
            tick.horizontalAlignmentMode = .center
        }
        modernBest.horizontalAlignmentMode = .right
        modernTankStatus.horizontalAlignmentMode = .left
        modernIntegrity.horizontalAlignmentMode = .left
        modernHitCaption.horizontalAlignmentMode = .left
        modernHitValue.horizontalAlignmentMode = .left
        modernCompassLabel.horizontalAlignmentMode = .center
        modernHeadingValue.horizontalAlignmentMode = .center
        modernTerrainLabel.horizontalAlignmentMode = .right
        modernSectorValue.horizontalAlignmentMode = .right
        modernStatusText.horizontalAlignmentMode = .left
        for label in [modernHitCaption, modernCompassLabel, modernTerrainLabel] {
            label.fontSize = 10
        }
        modernBest.fontSize = 11
        modernTankStatus.fontSize = 12
        modernIntegrity.fontSize = 12
        modernHitValue.fontSize = 28
        modernHeadingValue.fontSize = 25
        modernSectorValue.fontSize = 14
        modernStatusText.fontSize = 10
        for node in [modernTrim, modernLowerLines, modernHitRing,
                     modernHitTrack] { node.fillColor = .clear }
        for node in [modernAmmoTrack, modernAmmoFill,
                     modernShieldTrack, modernShieldFill] {
            node.strokeColor = .clear
        }
        modernLowerDash.lineWidth = 1.1
        modernThreatPanel.lineWidth = 1.5
        titleLogo.size = CGSize(width: 245, height: 245)
        titleLogo.zPosition = 21
        titleLogo.isHidden = true
        addChild(titleLogo)
        titleLogo.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.78, duration: 2.2),
            .fadeAlpha(to: 1.0, duration: 2.2)
        ])))
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
        telemetryLeftDetail.fontSize = 12
        telemetryRightDetail.fontSize = 12
        telemetryLeftFootnote.fontSize = 11
        telemetryRightFootnote.fontSize = 11
        telemetryCoordinates.fontSize = 10.5
        telemetryAmmo.fontSize = 15

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
        lives = rules.startingLives
        shotTally = ShotTally()
        observedFPS = 60
        nearestTankDistance = nil
        proximityCountdown = 0
        driveSpeed = 0
        turnMotion = 0
        suspension.reset()
        heading = 0
        steerHoldSeconds = 0
        previousSteerDirection = 0
        tankPosition = GroundPoint(0, 0)
        gameClock = 0
        cannon = CannonMagazine(maxRounds: rules.ammoCapacity, reloadSeconds: rules.reloadSeconds)
        shieldDuration = 0
        shieldCooldown = 0
        invulnerability = 1.8
        pendingWave = 0
        saucerPatrol = SaucerPatrolClock()
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
        if round == .title {
            pulse += dt
            // Gently pulse existing atmospheric bands during attract mode.
            for (index, band) in skyBands.enumerated() {
                band.alpha = 0.82 + 0.14 * sin(pulse * 0.6 + Double(index) * 0.65)
            }
        }
        let playing = round == .playing
        movementAudio.update(
            moving: playing ? min(1, abs(driveSpeed) / 16.5) : 0,
            turning: playing ? turnMotion : 0,
            enabled: playing && soundOn, dt: max(dt, 0.016))
        if playing {
            nearestTankDistance = enemies
                .filter { $0.kind != .saucer }
                .map { $0.center.distance(to: tankPosition) }
                .min()
            proximityCountdown = max(0, proximityCountdown - dt)
            if let distance = nearestTankDistance, TankProximity.isClose(distance) {
                if proximityCountdown <= 0 {
                    if soundOn { proximityAudio.beep() }
                    proximityCountdown = TankProximity.repeatInterval(for: distance)
                }
            } else {
                proximityCountdown = 0
            }
        }
        render()
    }

    private func tick(_ dt: Double) {
        if saucerPatrol.advance(by: dt) && rules.saucersEnabled { spawnPatrolSaucer() }
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
            let movement = (type == .hunter ? 4.6 : (type == .saucer ? 5.4 : 2.55)) * threatLevel.enemyVelocity * rules.enemySpeed
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
                let aimError = threatLevel.enemyAimError / rules.enemyAccuracy
                let error = Double.random(in: -aimError ... aimError)
                let direction = facing(aim + error)
                shells.append(Shell(center: enemies[idx].center + direction * 3.0,
                                    direction: direction, hostile: true, timeLeft: 4.0))
                enemies[idx].reload = Double.random(in: 2.3 ... 4.0) * threatLevel.enemyReload / rules.enemyReload
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
                            direction: direction, hostile: false, timeLeft: rules.projectileLifetime))
        pulse = 0.13
        sound("shot.wav")
    }

    private func triggerShield() {
        guard round == .playing && shieldCooldown <= 0 && shieldDuration <= 0 else { return }
        shieldDuration = rules.shieldDuration
        shieldCooldown = rules.shieldCooldown
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
        for i in 0..<rules.obstacleCount {
            let angle = Double(i) * 2.39996 + Double.random(in: -0.4...0.4)
            let distance = Double.random(in: 24...145)
            let p = GroundPoint(sin(angle) * distance, cos(angle) * distance)
            let size = Double.random(in: 3.0...6.7)
            let style = i % 8
            let kind: Obstacle.Kind
            switch style {
            case 0, 5: kind = .pyramid
            case 2, 6: kind = .tower
            case 3: kind = .building
            case 7: kind = .monolith
            default: kind = .block
            }
            obstacles.append(Obstacle(center: p, size: size, kind: kind))
        }
    }

    private func spawnPatrolSaucer() {
        let bearing = heading + Double.random(in: -0.9...0.9)
        let origin = tankPosition + facing(bearing) * 96
        let safeOrigin = GroundPoint(max(-175, min(175, origin.x)),
                                     max(-175, min(175, origin.z)))
        enemies.append(Foe(center: safeOrigin, heading: bearing + .pi,
                           kind: .saucer, reload: 999,
                           phase: Double.random(in: 0...(2 * .pi)), hitPoints: 1))
    }

    private func spawnWave() {
        enemies.removeAll()
        let count = rules.enemies(forWave: wave)
        for n in 0..<count {
            let angle = heading + (n == 0 ? Double.random(in: -0.20...0.20) : Double.random(in: -3.0...3.0))
            let dist = Double.random(in: 35...88)
            var target = tankPosition + facing(angle) * dist
            var tries = 0
            while blocked(target, radius: 4) && tries < 20 {
                target = tankPosition + facing(Double.random(in: -3.1...3.1)) * Double.random(in: 30...110)
                tries += 1
            }
            let kind: FoeType = (rules.huntersEnabled && wave >= 3 && n % 4 == 2)
                ? .hunter : ((rules.saucersEnabled && wave >= 2 && n % 6 == 5) ? .saucer : .tank)
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

    private func obstacleKindName(_ kind: Obstacle.Kind) -> String {
        switch kind {
        case .block: return "block"
        case .pyramid: return "pyramid"
        case .tower: return "tower"
        case .building: return "building"
        case .monolith: return "monolith"
        }
    }

    private func obstacleKind(named name: String) -> Obstacle.Kind {
        switch name {
        case "pyramid": return .pyramid
        case "tower": return .tower
        case "building": return .building
        case "monolith": return .monolith
        default: return .block
        }
    }

    // Exact in-progress battle state; displayed next in a paused state when resumed.
    func makeSnapshot() -> SiegeSnapshot? {
        guard round == .playing || round == .paused else { return nil }
        return SiegeSnapshot(
            version: 1,
            displayMode: displayMode.rawValue,
            threatLevel: threatLevel.rawValue, soundOn: soundOn,
            activePresetID: activePresetID, customRules: customRules,
            score: score, lives: lives, wave: wave, gameClock: gameClock,
            heading: heading, driveSpeed: driveSpeed, tankPosition: tankPosition,
            shieldRemaining: shieldDuration, shieldCooldown: shieldCooldown,
            invulnerability: invulnerability, pendingWave: pendingWave,
            cannon: cannon, shotTally: shotTally,
            obstacles: obstacles.map { SavedSiegeObstacle(
                center: $0.center, size: $0.size,
                kind: obstacleKindName($0.kind)) },
            enemies: enemies.map { SavedSiegeFoe(
                center: $0.center, heading: $0.heading,
                kind: $0.kind == .hunter ? "hunter" : $0.kind == .saucer ? "saucer" : "tank",
                reload: $0.reload, phase: $0.phase, hitPoints: $0.hitPoints) },
            shells: shells.map { SavedSiegeShell(
                center: $0.center, direction: $0.direction,
                hostile: $0.hostile, timeLeft: $0.timeLeft) },
            sparks: sparks.map { SavedSiegeSpark(
                position: $0.position, velocity: $0.velocity,
                timeLeft: $0.timeLeft, maxLife: $0.maxLife) },
            secondsUntilSaucerPatrol: saucerPatrol.secondsUntilArrival
        )
    }

    @discardableResult
    func restore(_ saved: SiegeSnapshot) -> Bool {
        guard saved.version == 1, saved.lives > 0,
              saved.score >= 0, saved.wave >= 1,
              saved.tankPosition.x.isFinite, saved.tankPosition.z.isFinite,
              saved.heading.isFinite, saved.gameClock.isFinite else { return false }
        pressedKeys.removeAll()
        activePresetID = saved.activePresetID
        customRules = saved.customRules?.validated()
        displayMode = DisplayMode(rawValue: saved.displayMode) ?? .classic
        threatLevel = ThreatLevel(rawValue: saved.threatLevel) ?? .veteran
        soundOn = saved.soundOn
        score = saved.score
        lives = saved.lives
        wave = saved.wave
        gameClock = saved.gameClock
        heading = wrapAngle(saved.heading)
        driveSpeed = saved.driveSpeed.isFinite ? saved.driveSpeed : 0
        tankPosition = saved.tankPosition
        shieldDuration = max(0, saved.shieldRemaining)
        shieldCooldown = max(0, saved.shieldCooldown)
        invulnerability = max(0, saved.invulnerability)
        pendingWave = max(0, saved.pendingWave)
        saucerPatrol.restore(secondsRemaining: saved.secondsUntilSaucerPatrol)
        cannon = saved.cannon
        shotTally = saved.shotTally
        obstacles = saved.obstacles.map { Obstacle(
            center: $0.center, size: $0.size,
            kind: obstacleKind(named: $0.kind)) }
        enemies = saved.enemies.map { Foe(
            center: $0.center, heading: $0.heading,
            kind: $0.kind == "hunter" ? .hunter : $0.kind == "saucer" ? .saucer : .tank,
            reload: $0.reload, phase: $0.phase, hitPoints: $0.hitPoints) }
        shells = saved.shells.map { Shell(
            center: $0.center, direction: $0.direction,
            hostile: $0.hostile, timeLeft: $0.timeLeft) }
        sparks = saved.sparks.map { Spark(
            position: $0.position, velocity: $0.velocity,
            timeLeft: $0.timeLeft, maxLife: $0.maxLife) }
        steerHoldSeconds = 0
        previousSteerDirection = 0
        turnMotion = 0
        suspension.reset()
        observedFPS = 60
        nearestTankDistance = nil
        proximityCountdown = 0
        pulse = 0
        lastUpdateTime = 0
        bestScore = max(bestScore, score)
        UserDefaults.standard.set(bestScore, forKey: "VectorSiegeHighScore")
        round = .paused // Explicit P resumes, preventing surprise damage on load.
        return true
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
        Ammo: \(cannon.roundsRemaining)/\(cannon.maxRounds)  Cannon: \(cannon.statusText)
        Last reload duration: \(String(format: "%.2f", cannon.lastReloadDuration)) seconds
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
            (radar, displayMode == .modern
             ? NSColor(calibratedRed: 0.17, green: 0.96, blue: 0.74, alpha: 1)
             : accent, 1.5, displayMode == .classic ? 0.2 : 2),
            (hudLines, muted, 1.0, 0)
        ] {
            node.strokeColor = color
            node.lineWidth = CGFloat(width)
            node.glowWidth = CGFloat(glow)
        }
        let modern = displayMode == .modern
        modernCockpit.isHidden = !modern
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
        banner.fontColor = displayMode == .modern
            ? NSColor(calibratedRed: 0.18, green: 0.95, blue: 0.98, alpha: 1)
            : cc
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
        for panel in [telemetryLeftPanel, telemetryRightPanel, radarPanel, rearPanel] {
            panel.fillColor = modern
                ? NSColor(calibratedRed: 0.008, green: 0.040, blue: 0.060, alpha: 0.96)
                : panelFill
            panel.strokeColor = modern
                ? NSColor(calibratedRed: 0.18, green: 0.86, blue: 0.91, alpha: 0.85)
                : amber.withAlphaComponent(0.32)
        }
        let cyan = NSColor(calibratedRed: 0.18, green: 0.97, blue: 0.95, alpha: 1)
        let orange = NSColor(calibratedRed: 1, green: 0.45, blue: 0.14, alpha: 1)
        modernTrim.strokeColor = cyan
        modernTrim.lineWidth = 1.3
        modernTrim.glowWidth = 2
        modernLowerDash.fillColor = NSColor(calibratedRed: 0.012, green: 0.052, blue: 0.070, alpha: 0.93)
        modernLowerDash.strokeColor = cyan
        modernLowerLines.strokeColor = cyan.withAlphaComponent(0.48)
        modernLowerLines.lineWidth = 1
        modernHitTrack.strokeColor = cyan.withAlphaComponent(0.17)
        modernHitTrack.lineWidth = 8
        modernHitRing.strokeColor = cyan
        modernHitRing.lineWidth = 8
        modernHitRing.glowWidth = 3
        modernAmmoTrack.fillColor = cyan.withAlphaComponent(0.2)
        modernAmmoFill.fillColor = cyan
        modernShieldTrack.fillColor = cyan.withAlphaComponent(0.2)
        modernShieldFill.fillColor = cyan
        modernThreatPanel.fillColor = NSColor(calibratedRed: 0.14, green: 0.02, blue: 0.015, alpha: 0.88)
        modernThreatPanel.strokeColor = orange
        modernThreatPanel.glowWidth = 4
        for label in [modernBest, modernIntegrity, modernHitCaption,
                      modernCompassLabel, modernTerrainLabel, modernStatusText] + modernHeadingTicks {
            label.fontColor = cyan.withAlphaComponent(0.85)
        }
        for label in [modernTankStatus, modernHitValue, modernHeadingValue, modernSectorValue] {
            label.fontColor = cyan
        }
        rearLabel.fontColor = amber
        proximityLabel.fontColor = amber
        rearGround.strokeColor = green.withAlphaComponent(0.55)
        rearGround.lineWidth = 0.6
        rearEnvironment.strokeColor = green.withAlphaComponent(0.82)
        rearEnvironment.lineWidth = 1.15
        rearEnemies.strokeColor = accent
        rearEnemies.lineWidth = 1.9
        rearEnemies.glowWidth = displayMode == .modern ? 3.0 : 0.8
        rearShots.strokeColor = amber
        rearShots.glowWidth = 2.6
        rearBackground.strokeColor = .clear
        rearBackground.fillColor = NSColor(calibratedRed: 0.012, green: 0.04, blue: 0.055, alpha: 0.98)
        radarObstacleContacts.strokeColor = muted.withAlphaComponent(0.95)
        radarObstacleContacts.fillColor = muted.withAlphaComponent(0.55)
        radarObstacleContacts.lineWidth = 0.7
        for rail in [telemetryLeftAccent, telemetryRightAccent] { rail.fillColor = amber }
        for label in [telemetryLeftHeading, telemetryRightHeading] {
            label.fontColor = modern ? cyan : amber
        }
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
            switch o.kind {
            case .pyramid: drawPyramid(o, on: structurePath, camera: c)
            case .block: drawBlock(o, on: structurePath, camera: c)
            case .tower, .building, .monolith:
                if displayMode == .modern { drawArchitecture(o, on: structurePath, camera: c) }
                else { drawBlock(o, on: structurePath, camera: c) }
            }
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
        let halfX: Double
        let halfZ: Double
        let topHeight: Double
        switch o.kind {
        case .pyramid: halfX = s; halfZ = s; topHeight = s * 1.28
        case .block: halfX = s; halfZ = s; topHeight = s * 1.35
        case .tower: halfX = s * 0.55; halfZ = s * 0.62; topHeight = s * 4.1
        case .building: halfX = s * 1.05; halfZ = s * 0.85; topHeight = s * 2.2
        case .monolith: halfX = s * 0.45; halfZ = s * 0.42; topHeight = s * 6.0
        }
        let bottom = [
            WorldPoint(o.center.x-halfX, 0, o.center.z-halfZ),
            WorldPoint(o.center.x+halfX, 0, o.center.z-halfZ),
            WorldPoint(o.center.x+halfX, 0, o.center.z+halfZ),
            WorldPoint(o.center.x-halfX, 0, o.center.z+halfZ)
        ]
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

    private func drawArchitecture(_ o: Obstacle, on path: CGMutablePath, camera c: CameraProjection) {
        let s = o.size
        let halfX: Double
        let halfZ: Double
        let height: Double
        switch o.kind {
        case .tower: halfX = s * 0.55; halfZ = s * 0.62; height = s * 4.1
        case .building: halfX = s * 1.05; halfZ = s * 0.85; height = s * 2.2
        case .monolith: halfX = s * 0.45; halfZ = s * 0.42; height = s * 6.0
        default: return
        }
        func v(_ x: Double, _ y: Double, _ z: Double) -> WorldPoint {
            WorldPoint(o.center.x + x, y, o.center.z + z)
        }
        let bottom = [v(-halfX, 0, -halfZ), v(halfX, 0, -halfZ),
                      v(halfX, 0, halfZ), v(-halfX, 0, halfZ)]
        let top = [v(-halfX, height, -halfZ), v(halfX, height, -halfZ),
                   v(halfX, height, halfZ), v(-halfX, height, halfZ)]
        for i in 0..<4 {
            let next = (i+1) % 4
            line(path, bottom[i], bottom[next], c)
            line(path, top[i], top[next], c)
            line(path, bottom[i], top[i], c)
        }
        if o.kind == .building {
            // Tiered roof, two side window grids and a simple door portal.
            let innerHeight = height + s * 0.34
            for i in 0..<4 {
                let j = (i + 1) % 4
                let a = v((i == 0 || i == 3 ? -1.0 : 1.0) * halfX * 0.68,
                          innerHeight, (i < 2 ? -1.0 : 1.0) * halfZ * 0.68)
                let b = v((j == 0 || j == 3 ? -1.0 : 1.0) * halfX * 0.68,
                          innerHeight, (j < 2 ? -1.0 : 1.0) * halfZ * 0.68)
                line(path, a, b, c)
                line(path, top[i], a, c)
            }
            for floor in 1...3 {
                let y = height * Double(floor) / 4
                line(path, v(-halfX, y, halfZ + 0.02), v(halfX, y, halfZ + 0.02), c)
                line(path, v(halfX + 0.02, y, -halfZ), v(halfX + 0.02, y, halfZ), c)
                for column in 1...3 {
                    let x = -halfX + 2 * halfX * Double(column) / 4
                    line(path, v(x, y - height * 0.08, halfZ + 0.03),
                         v(x, y + height * 0.08, halfZ + 0.03), c)
                }
            }
            line(path, v(-s*0.22, 0, halfZ + 0.04),
                 v(-s*0.22, height*0.35, halfZ + 0.04), c)
            line(path, v(s*0.22, 0, halfZ + 0.04),
                 v(s*0.22, height*0.35, halfZ + 0.04), c)
        } else if o.kind == .tower {
            // Cross bracing, vertical antenna and an elevated observation ring.
            for floor in 1...5 {
                let y0 = height * Double(floor - 1) / 5
                let y1 = height * Double(floor) / 5
                for side in [-1.0, 1.0] {
                    line(path, v(side*halfX, y0, -halfZ), v(side*halfX, y1, halfZ), c)
                }
                line(path, v(-halfX, y1, halfZ), v(halfX, y1, halfZ), c)
            }
            line(path, v(0, height, 0), v(0, height + s*1.2, 0), c)
            line(path, v(-halfX*1.2, height * 0.86, halfZ*1.1),
                 v(halfX*1.2, height * 0.86, halfZ*1.1), c)
        } else {
            // Tall rectangular monolith, subtle horizontal seams and inset
            // front vertical glowing strips.
            for floor in 1...8 {
                let y = height * Double(floor) / 9
                line(path, v(-halfX, y, halfZ), v(halfX, y, halfZ), c)
            }
            for side in [-0.65, 0.65] {
                line(path, v(side*halfX, height*0.08, halfZ+0.02),
                     v(side*halfX, height*0.93, halfZ+0.02), c)
            }
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
        // Animated rotating wireframe disk: moving facets and radial spokes make
        // the spin obvious in both Classic and Modern display modes.
        let n = displayMode == .modern ? 18 : 12
        let spin = gameClock * 2.9 + e.phase
        let hover = 5.1 + sin(gameClock * 2.4 + e.phase) * 0.55
        let radius = displayMode == .modern ? 3.7 : 3.1
        func ring(_ angle: Double, radius r: Double, elevation: Double) -> WorldPoint {
            WorldPoint(e.center.x + cos(angle) * r, elevation,
                       e.center.z + sin(angle) * r)
        }
        for i in 0..<n {
            let a = spin + Double(i) * 2 * .pi / Double(n)
            let b = spin + Double(i + 1) * 2 * .pi / Double(n)
            let rimA = ring(a, radius: radius, elevation: hover)
            let rimB = ring(b, radius: radius, elevation: hover)
            let lowerA = ring(a, radius: radius * 0.73, elevation: hover - 0.54)
            let lowerB = ring(b, radius: radius * 0.73, elevation: hover - 0.54)
            let domeA = ring(a, radius: radius * 0.44, elevation: hover + 1.27)
            let domeB = ring(b, radius: radius * 0.44, elevation: hover + 1.27)
            line(path, rimA, rimB, c)
            line(path, lowerA, lowerB, c)
            line(path, domeA, domeB, c)
            if i.isMultiple(of: 2) {
                line(path, rimA, domeA, c)
                line(path, rimA, lowerA, c)
                line(path, rimA,
                     WorldPoint(e.center.x, hover + 0.33, e.center.z), c)
            }
            if displayMode == .modern && i.isMultiple(of: 3) {
                // Rotating elevated light bar and undercarriage facet.
                line(path, domeA, ring(a, radius: radius * 0.16, elevation: hover + 1.63), c)
                line(path, lowerA, ring(a, radius: radius * 0.24, elevation: hover - 0.77), c)
            }
        }
        if displayMode == .modern {
            let crown = WorldPoint(e.center.x, hover + 1.70, e.center.z)
            for i in 0..<8 {
                let a = spin + Double(i) * .pi / 4
                line(path, crown,
                     ring(a, radius: radius * 0.16, elevation: hover + 1.63), c)
            }
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

    /// A live, tank-relative rear camera rendered from a true 180-degree
    /// perspective. All paths are clipped by SKCropNode to the inset viewport.
    /// This does not affect physics, aiming or the main scene camera.
    private func renderRearView(width: Double, height: Double) {
        let backCamera = CameraProjection(
            position: tankPosition, yaw: wrapAngle(heading + .pi),
            viewportWidth: width, viewportHeight: height)
        let backgroundPath = CGMutablePath()
        backgroundPath.addRect(CGRect(x: 0, y: 0, width: width, height: height))
        rearBackground.path = backgroundPath

        let gridPath = CGMutablePath()
        let backHeading = heading + .pi
        let baseX = floor(tankPosition.x / 20) * 20
        let baseZ = floor(tankPosition.z / 20) * 20
        for i in -8...8 {
            let x = baseX + Double(i) * 20
            line(gridPath, WorldPoint(x, 0, baseZ-160),
                 WorldPoint(x, 0, baseZ+160), backCamera)
            let z = baseZ + Double(i) * 20
            line(gridPath, WorldPoint(baseX-160, 0, z),
                 WorldPoint(baseX+160, 0, z), backCamera)
        }
        // Distant skyline, viewed from the rear camera instead of mirrored front.
        let horizon = backCamera.horizon
        var previous = point(0, horizon)
        for i in 0...34 {
            let x = Double(i) * width / 34
            let bearing = backHeading + atan2((x - width/2)/backCamera.focal, 1)
            let top = point(x, horizon + ridge(bearing, multiplier: 0.38))
            if i > 0 { segment(gridPath, previous, top) }
            previous = top
        }
        rearGround.path = gridPath

        let obstaclePath = CGMutablePath()
        for object in obstacles where object.center.distance(to: tankPosition) < 95 {
            switch object.kind {
            case .pyramid: drawPyramid(object, on: obstaclePath, camera: backCamera)
            case .block: drawBlock(object, on: obstaclePath, camera: backCamera)
            case .tower, .building, .monolith:
                if displayMode == .modern {
                    drawArchitecture(object, on: obstaclePath, camera: backCamera)
                } else {
                    drawBlock(object, on: obstaclePath, camera: backCamera)
                }
            }
        }
        rearEnvironment.path = obstaclePath

        let enemyPath = CGMutablePath()
        for foe in enemies where foe.center.distance(to: tankPosition) < 120 {
            if foe.kind == .saucer {
                drawSaucer(foe, on: enemyPath, camera: backCamera)
            } else {
                drawTank(foe, on: enemyPath, camera: backCamera)
            }
        }
        rearEnemies.path = enemyPath
        let projectilePath = CGMutablePath()
        for shell in shells {
            let height = shell.hostile ? 1.5 : 1.65
            let tail = shell.center - shell.direction * 2.6
            line(projectilePath, WorldPoint(shell.center, height: height),
                 WorldPoint(tail, height: height), backCamera)
        }
        rearShots.path = projectilePath
    }

    /// Vector Drift-inspired Modern cockpit. All gauges are driven by actual
    /// battle data; Classic keeps its original arcade readouts.
    private func renderModernCockpit(
        width w: Double, height h: Double, bankWidth: Double,
        leftX: Double, rightX: Double, radarX: Double,
        rearX: Double, radarPanelWidth: Double,
        rearPanelWidth: Double, topHeight: Double
    ) {
        let cyan = NSColor(calibratedRed: 0.21, green: 0.98, blue: 0.94, alpha: 1)
        let amber = NSColor(calibratedRed: 1, green: 0.52, blue: 0.22, alpha: 1)
        let unit = min(1.0, max(0.68, w / 1320))
        let bottomY = 29.0
        let bottomHeight = max(96.0, min(119.0, h * 0.145))
        modernLowerDash.path = CGPath(
            roundedRect: CGRect(x: 12, y: bottomY, width: max(1, w - 24),
                                height: bottomHeight),
            cornerWidth: 12, cornerHeight: 12, transform: nil)

        let leftDivider = w * 0.24
        let rightDivider = w * 0.71
        let compassX = w * 0.53
        let ringX = w * 0.33
        let midY = bottomY + bottomHeight * 0.53
        let deco = CGMutablePath()
        // Deck segments, circuit-board traces, subtle index and compass ticks.
        segment(deco, point(24, bottomY + bottomHeight - 10),
                point(w - 24, bottomY + bottomHeight - 10))
        for x in [leftDivider, w * 0.42, rightDivider] {
            segment(deco, point(x, bottomY + 13),
                    point(x, bottomY + bottomHeight - 15))
        }
        let halfScale = min(150.0, (rightDivider - w * 0.42) * 0.43)
        let headingDegrees = (heading * 180 / .pi + 360)
                             .truncatingRemainder(dividingBy: 360)
        let tickStep = halfScale / 6
        let tickShift = headingDegrees.truncatingRemainder(dividingBy: 10) / 10
                        * tickStep
        for step in -7...7 {
            let x = compassX + Double(step) * tickStep - tickShift
            if x < compassX - halfScale || x > compassX + halfScale { continue }
            let major = step.isMultiple(of: 2)
            segment(deco, point(x, bottomY + 23),
                    point(x, bottomY + (major ? 40 : 32)))
        }
        let baseHeading = Int(floor(headingDegrees / 10)) * 10
        for (index, label) in modernHeadingTicks.enumerated() {
            let offset = (index - 3) * 2
            let x = compassX + Double(offset) * tickStep - tickShift
            label.position = point(x, bottomY + 51)
            let bearing = (baseHeading + offset * 10 + 360) % 360
            label.text = String(format: "%03d°", bearing)
            label.isHidden = abs(x - compassX) > halfScale - 8
        }

        // Small real-time terrain signature at the far right of the lower deck.
        let terrainLeft = w * 0.735
        let terrainWidth = max(30, w * 0.10)
        let terrainBase = bottomY + 25
        var previousTerrain = point(terrainLeft, terrainBase)
        for i in 0...24 {
            let t = Double(i) / 24
            let angle = heading + (t - 0.5) * 0.9
            let y = terrainBase + min(27, ridge(angle, multiplier: 0.23))
            let current = point(terrainLeft + t * terrainWidth, y)
            if i > 0 { segment(deco, previousTerrain, current) }
            previousTerrain = current
        }
        modernLowerLines.path = deco

        // Corner brackets and linking traces visually tie the top four panels
        // together without obstructing the live radar or rear camera image.
        let trim = CGMutablePath()
        let panelTop = h - 16.0
        let panelBottom = panelTop - topHeight
        for (x, direction) in [(14.0, 1.0), (w - 14.0, -1.0)] {
            segment(trim, point(x, panelTop - 28),
                    point(x + direction * 22, panelTop))
            segment(trim, point(x + direction * 22, panelTop),
                    point(x + direction * 90, panelTop))
            segment(trim, point(x, panelBottom + 28),
                    point(x + direction * 22, panelBottom))
            segment(trim, point(x + direction * 22, panelBottom),
                    point(x + direction * 90, panelBottom))
        }
        let bridgeStart = radarX - radarPanelWidth / 2 + 15
        let bridgeEnd = rearX + rearPanelWidth / 2 - 15
        segment(trim, point(bridgeStart, panelBottom + 7),
                point(bridgeEnd, panelBottom + 7))
        modernTrim.path = trim

        // A circular percent gauge highlights accuracy without relying solely
        // on tiny text in the upper targeting panel.
        let hitCenter = point(ringX, midY)
        let hitRadius = max(18.0, 24 * unit)
        let track = CGMutablePath()
        track.addEllipse(in: CGRect(x: hitCenter.x - hitRadius,
                                    y: hitCenter.y - hitRadius,
                                    width: hitRadius * 2, height: hitRadius * 2))
        modernHitTrack.path = track
        let hitArc = CGMutablePath()
        let fraction = min(1, max(0, shotTally.hitPercentage / 100))
        if fraction > 0 {
            hitArc.addArc(center: hitCenter, radius: hitRadius,
                          startAngle: -.pi / 2,
                          endAngle: -.pi / 2 + CGFloat(Double.pi * 2 * fraction),
                          clockwise: false)
        }
        modernHitRing.path = hitArc

        modernBest.position = point(rightX, h - 110)
        modernBest.text = String(format: "BEST %06d", bestScore)
        modernBest.fontSize = CGFloat(11 * unit)
        modernTankStatus.position = point(31, bottomY + bottomHeight - 32)
        modernTankStatus.text = "TANK SYSTEMS"
        modernIntegrity.position = point(31, bottomY + bottomHeight - 60)
        modernIntegrity.text = String(format: "%02d LIVES  //  %@", lives,
                                      round == .gameOver ? "OFFLINE" : "ONLINE")
        modernHitCaption.position = point(leftDivider + 15, bottomY + bottomHeight - 29)
        modernHitCaption.text = "HIT RATE"
        modernHitValue.position = point(leftDivider + 15, bottomY + 40)
        modernHitValue.text = String(format: "%.0f%%", shotTally.hitPercentage)
        modernHitValue.fontSize = CGFloat(28 * unit)

        modernHeadingValue.position = point(compassX, bottomY + bottomHeight - 35)
        let bearing = Int((heading * 180 / .pi + 360)
                          .truncatingRemainder(dividingBy: 360).rounded()) % 360
        modernHeadingValue.text = String(format: "%03d°", bearing)
        modernCompassLabel.position = point(compassX, bottomY + 13)
        modernCompassLabel.text = "DRIVE HEADING  //  LIVE"

        modernTerrainLabel.position = point(w - 35, bottomY + bottomHeight - 28)
        modernTerrainLabel.text = "BATTLEFIELD POSITION"
        modernSectorValue.position = point(w - 35, bottomY + bottomHeight - 56)
        modernSectorValue.text = String(format: "X %+.0f   Z %+.0f",
                                        tankPosition.x, tankPosition.z)
        modernStatusText.position = point(31, bottomY + 18)
        modernStatusText.text = String(format: "WAVE %02d   //   %02d ENEMIES",
                                        wave, enemies.count)

        // Tank-style horizontal readiness bars in the right upper display.
        let barLeft = rightX - bankWidth * 0.75
        let barWidth = max(48.0, bankWidth * 0.72)
        let barHeight = 5.0
        let shieldY = h - 188.0
        let ammoY = h - 221.0
        func bar(_ x: Double, _ y: Double, _ width: Double) -> CGPath {
            CGPath(roundedRect: CGRect(x: x, y: y,
                                        width: max(0.1, width), height: barHeight),
                   cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
        }
        modernShieldTrack.path = bar(barLeft, shieldY, barWidth)
        let shieldValue = shieldDuration > 0
            ? shieldDuration / max(1, rules.shieldDuration)
            : max(0, 1 - shieldCooldown / max(0.01, rules.shieldCooldown))
        modernShieldFill.path = bar(barLeft, shieldY,
                                    max(0.1, barWidth * min(1, max(0, shieldValue))))
        modernShieldFill.fillColor = shieldDuration > 0 ? cyan : amber
        modernAmmoTrack.path = bar(barLeft, ammoY, barWidth)
        modernAmmoFill.path = bar(barLeft, ammoY,
                                  max(0.1, barWidth * Double(cannon.roundsRemaining)
                                      / Double(max(1, cannon.maxRounds))))
        modernAmmoFill.fillColor = cannon.roundsRemaining < max(4, cannon.maxRounds / 5)
            ? amber : cyan

        let close = nearestTankDistance.flatMap {
            TankProximity.isClose($0) ? $0 : nil
        }
        modernThreatPanel.isHidden = close == nil || round != .playing
        if let distance = close, round == .playing {
            let threatWidth = min(570.0, w * 0.60)
            modernThreatPanel.path = CGPath(
                roundedRect: CGRect(x: w / 2 - threatWidth / 2, y: 152,
                                    width: threatWidth, height: 49),
                cornerWidth: 8, cornerHeight: 8, transform: nil)
            modernThreatPanel.alpha = CGFloat(0.80 + 0.20 * abs(sin(gameClock * 7)))
            modernThreatPanel.strokeColor = distance <= TankProximity.tankLength
                ? NSColor.systemRed : amber
        }
    }

    private func renderHUD(_ c: CameraProjection) {
        let w = c.viewportWidth
        let h = c.viewportHeight
        let hp = CGMutablePath()
        let rp = CGMutablePath()
        let sight = CGMutablePath()
        let modernHUD = displayMode == .modern
        let radarRange = 165.0
        let panelHeight = modernHUD ? min(268.0, max(200.0, h * 0.295)) : 154.0
        let outerMargin = modernHUD ? 14.0 : 14.0
        let panelGap = modernHUD ? 10.0 : 12.0
        let available = w - outerMargin * 2 - panelGap * 3
        // Side systems 26% each, radar 21%, and a wider rear monitor 27%.
        // This keeps the radar's circle visually close to its instrument frame.
        let modernBankWidth = available * 0.26
        let bankWidth = modernHUD ? modernBankWidth
            : min(316.0, max(202.0, (w - 530.0) / 2))
        let radarPanelWidth = modernHUD ? available * 0.21 : 178.0
        let rearPanelWidth = modernHUD ? available * 0.27 : 182.0
        let topCenterY = modernHUD ? h - 16 - panelHeight / 2 : h - 94.0
        let leftCenterX = modernHUD ? outerMargin + bankWidth / 2 : 14 + bankWidth / 2
        let radarX = modernHUD
            ? outerMargin + bankWidth + panelGap + radarPanelWidth / 2
            : w / 2 - 104.0
        let rearX = modernHUD
            ? outerMargin + bankWidth + radarPanelWidth + panelGap * 2 + rearPanelWidth / 2
            : w / 2 + 103.0
        let rightCenterX = modernHUD
            ? w - outerMargin - bankWidth / 2
            : w - 14 - bankWidth / 2
        let radarY = modernHUD ? topCenterY - 6 : h - 103.0
        let radarRadius = modernHUD
            ? min((radarPanelWidth - 24) / 2, (panelHeight - 42) / 2)
            : 79.0
        let leftX = modernHUD ? leftCenterX - bankWidth / 2 + 18 : 34.0
        let rightX = modernHUD ? rightCenterX + bankWidth / 2 - 18 : w - 34
        func panelRect(width: Double) -> CGPath {
            CGPath(roundedRect: CGRect(x: -width / 2, y: -panelHeight / 2,
                                       width: width, height: panelHeight),
                   cornerWidth: 12, cornerHeight: 12, transform: nil)
        }
        telemetryLeftPanel.path = panelRect(width: bankWidth)
        telemetryRightPanel.path = panelRect(width: bankWidth)
        radarPanel.path = panelRect(width: radarPanelWidth)
        rearPanel.path = panelRect(width: rearPanelWidth)
        telemetryLeftPanel.position = point(leftCenterX, topCenterY)
        telemetryRightPanel.position = point(rightCenterX, topCenterY)
        radarPanel.position = point(radarX, topCenterY)
        rearPanel.position = point(rearX, topCenterY)
        telemetryLeftAccent.position = point(leftCenterX - bankWidth / 2 + 6, topCenterY)
        telemetryRightAccent.position = point(rightCenterX + bankWidth / 2 - 6, topCenterY)
        telemetryLeftHeading.position = point(leftX, h - (modernHUD ? 41 : 33))
        telemetryRightHeading.position = point(rightX, h - (modernHUD ? 41 : 33))
        telemetryLeftDetail.position = point(leftX, h - (modernHUD ? 133 : 82))
        telemetryLeftFootnote.position = point(leftX, h - (modernHUD ? 168 : 107))
        telemetryCoordinates.position = point(leftX, h - (modernHUD ? 202 : 134))
        telemetryRightDetail.position = point(rightX, h - (modernHUD ? 137 : 82))
        telemetryRightFootnote.position = point(rightX, h - (modernHUD ? 174 : 107))
        telemetryAmmo.position = point(rightX, h - (modernHUD ? 207 : 134))
        telemetryLeftAccent.setScale(modernHUD ? 1.45 : 1)
        telemetryRightAccent.setScale(modernHUD ? 1.45 : 1)

        // Resize the actual rear camera's crop region and projection together.
        // Classic retains the original narrow rear monitor.
        let rearWidth = modernHUD ? max(120.0, rearPanelWidth - 20) : 172.0
        let rearHeight = modernHUD ? panelHeight - 53 : 108.0
        rearMask.path = CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: rearWidth, height: rearHeight),
            cornerWidth: 8, cornerHeight: 8, transform: nil)
        rearView.position = modernHUD
            ? point(rearX - rearWidth / 2, topCenterY - rearHeight / 2 - 13)
            : point(rearX - 86, h - 143)
        rearLabel.position = point(rearX, h - (modernHUD ? 35 : 19))
        rearLabel.text = modernHUD ? "REAR VIEW  //  180°" : "REAR VIEW / 180°"
        rearLabel.fontSize = modernHUD ? 12 : 10
        renderRearView(width: rearWidth, height: rearHeight)
        hudLines.path = hp

        // Circular range rings and bearing grid; contacts are player-relative.
        let circle = CGRect(x: radarX - radarRadius, y: radarY - radarRadius,
                            width: radarRadius * 2, height: radarRadius * 2)
        rp.addEllipse(in: circle)
        for fraction in [1.0/3.0, 2.0/3.0] {
            let rad = radarRadius * fraction
            rp.addEllipse(in: CGRect(x: radarX - rad, y: radarY - rad,
                                     width: rad * 2, height: rad * 2))
        }
        segment(rp, point(radarX, radarY-radarRadius), point(radarX, radarY+radarRadius))
        segment(rp, point(radarX-radarRadius, radarY), point(radarX+radarRadius, radarY))
        for i in 0..<12 {
            let a = Double(i) * Double.pi / 6
            let inner = radarRadius - (i.isMultiple(of: 3) ? 9.0 : 4.0)
            segment(rp, point(radarX + sin(a)*inner, radarY + cos(a)*inner),
                    point(radarX + sin(a)*radarRadius, radarY + cos(a)*radarRadius))
        }
        let sweepAngle = gameClock * 1.45
        segment(rp, point(radarX, radarY),
                point(radarX + sin(sweepAngle)*radarRadius,
                      radarY + cos(sweepAngle)*radarRadius))
        // Fixed nose-direction chevron identifies the center of the map.
        segment(rp, point(radarX-3.6, radarY-3), point(radarX, radarY+5.5))
        segment(rp, point(radarX, radarY+5.5), point(radarX+3.6, radarY-3))

        let obstaclesOnRadar = CGMutablePath()
        let enemyContacts = CGMutablePath()
        let projectileHalos = CGMutablePath()
        let projectileDots = CGMutablePath()
        func radarPoint(_ center: GroundPoint) -> CGPoint? {
            let dx = center.x - tankPosition.x
            let dz = center.z - tankPosition.z
            let right = dx * cos(heading) - dz * sin(heading)
            let forward = dx * sin(heading) + dz * cos(heading)
            guard hypot(right, forward) <= radarRange else { return nil }
            return point(radarX + right / radarRange * radarRadius,
                         radarY + forward / radarRange * radarRadius)
        }
        for obstacle in obstacles {
            guard let contact = radarPoint(obstacle.center) else { continue }
            let radius = obstacle.kind == .monolith || obstacle.kind == .tower ? 2.9 : 2.1
            obstaclesOnRadar.addRect(CGRect(x: contact.x-radius, y: contact.y-radius,
                                            width: radius*2, height: radius*2))
        }
        for foe in enemies {
            guard let contact = radarPoint(foe.center) else { continue }
            if foe.kind == .saucer {
                let size = 5.0
                enemyContacts.move(to: point(contact.x, contact.y+size))
                enemyContacts.addLine(to: point(contact.x+size, contact.y))
                enemyContacts.addLine(to: point(contact.x, contact.y-size))
                enemyContacts.addLine(to: point(contact.x-size, contact.y))
                enemyContacts.closeSubpath()
            } else {
                let radius = foe.kind == .hunter ? 3.8 : 2.7
                enemyContacts.addEllipse(in: CGRect(x: contact.x-radius, y: contact.y-radius,
                                                     width: radius*2, height: radius*2))
            }
        }
        for shell in shells {
            guard let contact = radarPoint(shell.center) else { continue }
            let radius = shell.hostile ? 2.0 : 2.8
            projectileHalos.addEllipse(in: CGRect(x: contact.x-4.7, y: contact.y-4.7,
                                                   width: 9.4, height: 9.4))
            projectileDots.addEllipse(in: CGRect(x: contact.x-radius, y: contact.y-radius,
                                                  width: radius*2, height: radius*2))
        }
        radar.path = rp
        radarObstacleContacts.path = obstaclesOnRadar
        radarEnemyContacts.path = enemyContacts
        radarProjectileGlow.path = projectileHalos
        radarProjectileCore.path = projectileDots

        let cx = w / 2
        let cy = c.horizon + 18
        if modernHUD {
            // Commander's sight: framing brackets, calibrated ticks, center
            // aiming aperture, and a stable horizon reference. Purely cosmetic.
            let spread = min(86.0, w * 0.09)
            let rise = 45.0
            for signX in [-1.0, 1.0] {
                for signY in [-1.0, 1.0] {
                    let x = cx + signX * spread
                    let y = cy + signY * rise
                    segment(sight, point(x, y), point(x - signX * 25, y))
                    segment(sight, point(x, y), point(x, y - signY * 19))
                }
            }
            for side in [-1.0, 1.0] {
                segment(sight, point(cx + side * 42, cy),
                        point(cx + side * 9, cy))
                segment(sight, point(cx, cy + side * 32),
                        point(cx, cy + side * 8))
            }
            sight.addEllipse(in: CGRect(x: cx - 8, y: cy - 8, width: 16, height: 16))
            for offset in [-4, -3, -2, -1, 1, 2, 3, 4] {
                let tickX = cx + Double(offset) * 27.0
                segment(sight, point(tickX, cy - 73),
                        point(tickX, cy - (abs(offset).isMultiple(of: 2) ? 61 : 65)))
            }
            for delta in [-1.0, 1.0] {
                segment(sight, point(cx + delta * 106, cy),
                        point(cx + delta * 118, cy))
            }
        } else {
            segment(sight, point(cx - 33, cy), point(cx - 8, cy))
            segment(sight, point(cx + 8, cy), point(cx + 33, cy))
            segment(sight, point(cx, cy - 30), point(cx, cy - 9))
            segment(sight, point(cx, cy + 9), point(cx, cy + 30))
            let corner = 60.0
            for sign in [-1.0, 1.0] {
                segment(sight, point(cx+sign*corner, cy-13),
                        point(cx+sign*corner, cy+13))
            }
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

        leftHUD.position = point(radarX, h - (modernHUD ? 34 : 16))
        leftHUD.horizontalAlignmentMode = .center
        leftHUD.fontSize = modernHUD ? 12 : 10
        leftHUD.text = modernHUD ? "TACTICAL RADAR  //  165" : "RADAR / 165"
        midHUD.position = point(leftX, h - (modernHUD ? 86 : 57))
        midHUD.horizontalAlignmentMode = .left
        midHUD.fontSize = modernHUD ? (w < 1060 ? 15 : 21)
            : (w < 1050 ? 13 : 17)
        let compass = Int((heading * 180 / .pi + 360).truncatingRemainder(dividingBy: 360).rounded()) % 360
        midHUD.text = modernHUD && w < 1060
            ? String(format: "HDG %03d°  %+.1f", compass, driveSpeed)
            : String(format: "HDG %03d°   SPD %05.1f", compass, driveSpeed)
        let target = targetTelemetry()
        telemetryLeftDetail.text = target.map {
            String(format: "TGT %03.0f   AIM %+05.1f°", $0.range, $0.error * 180 / .pi)
        } ?? "TGT ---   AIM ---"
        let accuracy = shotTally.hitPercentage
        // Only resolved projectiles count toward the ratio; F is still in flight.
        telemetryLeftFootnote.text = String(
            format: "H/M %02d:%02d   HIT %.0f%%   F %02d",
            shotTally.hits, shotTally.misses, accuracy, shotTally.pending)
        telemetryLeftHeading.text = modernHUD
            ? "TARGETING  //  NAVIGATION" : "VECTOR SIEGE  //  TARGETING"
        telemetryCoordinates.text = String(format: "POSITION   X %+.1f   Z %+.1f", tankPosition.x, tankPosition.z)
        rightHUD.position = point(rightX, h - (modernHUD ? 87 : 57))
        rightHUD.horizontalAlignmentMode = .right
        rightHUD.fontSize = modernHUD ? (w < 1060 ? 17 : 24)
            : (w < 1050 ? 11 : 15)
        rightHUD.text = modernHUD
            ? String(format: "SCORE %06d", score)
            : String(format: "SCORE %06d  BEST %06d", score, bestScore)
        telemetryRightHeading.text = modernHUD
            ? "COMBAT SYSTEMS  //  STATUS" : "SYSTEMS  //  COMBAT STATUS"
        telemetryLeftDetail.fontSize = modernHUD ? 13 : 12
        telemetryLeftFootnote.fontSize = modernHUD ? 12 : 11
        telemetryCoordinates.fontSize = modernHUD ? 12 : 10.5
        telemetryRightDetail.fontSize = modernHUD ? 12 : 12
        telemetryRightFootnote.fontSize = modernHUD ? 12 : 11
        telemetryRightDetail.text = String(format: "WAVE %02d   LIVES %d   %@", wave, lives, threatLevel.rawValue.uppercased())
        let shieldName = shieldDuration > 0
            ? String(format: "SHIELD ACTIVE %.1fs", shieldDuration)
            : shieldCooldown > 0
                ? String(format: "RECHARGING %.1fs", shieldCooldown)
                : "SHIELD READY [SHIFT]"
        telemetryRightFootnote.text = shieldName
        telemetryAmmo.fontSize = modernHUD ? 15 : (w < 1050 ? 12 : 15)
        telemetryAmmo.text = String(format: "AMMO %02d/%02d   %@", cannon.roundsRemaining,
                                           cannon.maxRounds, cannon.statusText)
        telemetryAmmo.fontColor = cannon.isEmpty ? accent : green
        warning.position = modernHUD ? point(w / 2, 178) : point(w / 2, h - 213)
        let closeEnemy = nearestTankDistance.flatMap {
            TankProximity.isClose($0) ? $0 : nil
        }
        if let distance = closeEnemy, round == .playing {
            let urgency = distance <= TankProximity.tankLength
            warning.fontSize = modernHUD ? (urgency ? 21 : 18) : (urgency ? 20 : 17)
            warning.fontColor = urgency ? .red : NSColor.systemOrange
            warning.alpha = CGFloat(0.70 + 0.30 * abs(sin(gameClock * 8.0)))
            warning.text = modernHUD
                ? String(format: "⚠  PROXIMITY ALERT   //   ENEMY %.1f TANK LENGTHS",
                         distance / TankProximity.tankLength)
                : String(format: "⚠  ENEMY PROXIMITY  %.0f", distance)
        } else {
            warning.position = modernHUD ? point(w / 2, c.horizon + 100) : warning.position
            warning.fontSize = 12
            warning.fontColor = accent
            warning.alpha = 1
            warning.text = target.map {
                abs($0.error) < 0.055 && $0.range < 68 ? "TARGET ALIGNED" : ""
            } ?? (pendingWave > 0 ? "AREA SECURE" : "")
        }

        let modeName = displayMode == .classic ? "CLASSIC CRT" : "ENHANCED VECTOR"
        message.position = point(w / 2, modernHUD ? 16 : 47)
        message.fontSize = 11
        message.isHidden = modernHUD && !showDetailedTelemetry
        if showDetailedTelemetry {
            message.text = String(format: "FPS %.0f  |  POSITION %+.1f, %+.1f  |  ENEMIES %d  |  SHELLS %d  |  [T] MINIMIZE",
                                  observedFPS, tankPosition.x, tankPosition.z, enemies.count, shells.count)
        } else {
            message.text = modeName + "   //   [T] DIAGNOSTICS   //   COPY FEEDBACK IN TOOLBAR"
        }
        message.fontColor = shieldDuration > 0 ? green : accent

        if modernHUD {
            renderModernCockpit(
                width: w, height: h, bankWidth: bankWidth,
                leftX: leftX, rightX: rightX, radarX: radarX,
                rearX: rearX, radarPanelWidth: radarPanelWidth,
                rearPanelWidth: rearPanelWidth, topHeight: panelHeight)
        }

        stagePanel.position = point(w / 2, h * 0.61)
        stagePanel.strokeColor = modernHUD
            ? NSColor(calibratedRed: 0.18, green: 0.85, blue: 0.88, alpha: 0.8)
            : accent.withAlphaComponent(0.55)
        stagePanel.fillColor = modernHUD
            ? NSColor(calibratedRed: 0.006, green: 0.028, blue: 0.045, alpha: 0.88)
            : NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.05, alpha: 0.94)
        stagePanel.isHidden = round == .title || (round == .playing && pendingWave <= 0)
        banner.position = point(w/2, h*0.67)
        banner.fontSize = min(42, w*0.052)
        titleLogo.position = point(w/2, h*0.66)
        titleLogo.isHidden = round != .title
        subtitle.position = point(w/2, round == .title ? h*0.42 : h*0.59)
        subtitle.fontSize = 15
        switch round {
        case .title:
            banner.text = ""
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


/// Short synthesized two-tone warning; never plays if Sound is disabled.
/// Repeats only while an enemy tank is within roughly two hull lengths.
private final class TankProximityAudio {
    private var player: AVAudioPlayer?

    init() {
        player = try? AVAudioPlayer(data: Self.makeAlert())
        player?.volume = 0.33
        player?.prepareToPlay()
    }

    func beep() {
        player?.stop()
        player?.currentTime = 0
        player?.play()
    }

    private static func makeAlert() -> Data {
        let sampleRate = 22_050
        let sampleCount = Int(Double(sampleRate) * 0.18)
        var bytes = Data(capacity: 44 + sampleCount * 2)
        func append16(_ n: UInt16) {
            bytes.append(UInt8(truncatingIfNeeded: n))
            bytes.append(UInt8(truncatingIfNeeded: n >> 8))
        }
        func append32(_ n: UInt32) {
            append16(UInt16(truncatingIfNeeded: n))
            append16(UInt16(truncatingIfNeeded: n >> 16))
        }
        bytes.append(contentsOf: [82,73,70,70]) // RIFF
        append32(UInt32(36 + sampleCount * 2))
        bytes.append(contentsOf: [87,65,86,69,102,109,116,32]) // WAVEfmt
        append32(16); append16(1); append16(1)
        append32(UInt32(sampleRate)); append32(UInt32(sampleRate * 2))
        append16(2); append16(16)
        bytes.append(contentsOf: [100,97,116,97])
        append32(UInt32(sampleCount * 2))
        for i in 0..<sampleCount {
            let time = Double(i) / Double(sampleRate)
            let edge = min(1, Double(min(i, sampleCount - 1 - i)) / 220)
            let tone = sin(2 * .pi * 650 * time) * 0.48
                       + sin(2 * .pi * 940 * time) * 0.24
            let value = Int16((max(-1, min(1, tone * edge)) * 32767).rounded())
            append16(UInt16(bitPattern: value))
        }
        return bytes
    }
}
