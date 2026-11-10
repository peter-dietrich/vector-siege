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
    // Transient routing cache: recalculated after restoring a save.
    var navigationWaypoint: GroundPoint? = nil
    var routeRefreshRemaining: Double = 0
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

private enum RoundState { case title, levelReady, playing, paused, gameOver }

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
    private let streetMarks = SKShapeNode()
    private let structures = SKShapeNode()
    private let opponentLines = SKShapeNode()
    private let opponentSaucerLines = SKShapeNode()
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
    private let rearSaucers = SKShapeNode()
    private let rearShots = SKShapeNode()
    private let rearBackground = SKShapeNode()
    private let rearLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let proximityLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let radarObstacleContacts = SKShapeNode()
    private let radarStreetGrid = SKShapeNode()
    private let radarProjectileGlow = SKShapeNode()
    private let radarProjectileCore = SKShapeNode()
    private let radarEnemyContacts = SKShapeNode()
    private let hudLines = SKShapeNode()
    private let leftHUD = SKLabelNode(fontNamed: "Menlo-Bold")
    private let rightHUD = SKLabelNode(fontNamed: "Menlo-Bold")
    private let midHUD = SKLabelNode(fontNamed: "Menlo-Bold")
    private let warning = SKLabelNode(fontNamed: "Menlo-Bold")
    private let banner = SKLabelNode(fontNamed: "Menlo-Bold")
    private let levelFrame = SKShapeNode()
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
    // Separate Modern instrument labels, not a screenshot or an image overlay.
    private let modernUpperText = (0..<25).map { _ in SKLabelNode(fontNamed: "Menlo-Bold") }
    private let modernUpperDividers = SKShapeNode()
    private let modernUpperIcons = SKShapeNode()
    private let modernOrangeCorners = SKShapeNode()

    // Modern-mode cockpit treatment. Separate decoration and text nodes make
    // every value live and keep Classic independent of the premium layout.
    private let modernCockpit = SKNode()
    private let modernTrim = SKShapeNode()
    private let modernLowerDash = SKShapeNode()
    private let modernLowerLines = SKShapeNode()
    private let modernTankIcon = SKShapeNode()
    private let modernTerrainProfile = SKShapeNode()
    private let modernHeadingPointer = SKShapeNode()
    private let modernLowerCorners = SKShapeNode()
    private let modernLowerExtra = (0..<10).map { _ in SKLabelNode(fontNamed: "Menlo") }
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
            (farSkyline, 1.0), (skyline, 2.0), (ground, 3.0),
            (streetMarks, 3.2), (structures, 4.0),
            (opponentLines, 5.0), (opponentSaucerLines, 5.1), (shotLines, 6.0),
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
                               (rearSaucers, 3.1), (rearShots, 4.0)] {
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
        radarStreetGrid.zPosition = 12.8
        addChild(radarStreetGrid)
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
        for (shape, depth) in [
            (modernUpperDividers, 12.7), (modernUpperIcons, 14.0),
            (modernOrangeCorners, 12.9)
        ] {
            shape.zPosition = depth
            shape.fillColor = .clear
            addChild(shape)
        }
        for label in modernUpperText {
            label.zPosition = 14.3
            label.horizontalAlignmentMode = .left
            label.verticalAlignmentMode = .center
            addChild(label)
        }
        stagePanel.zPosition = 18
        stagePanel.lineWidth = 1.2
        addChild(stagePanel)
        levelFrame.zPosition = 19
        levelFrame.fillColor = .clear
        levelFrame.lineWidth = 2
        addChild(levelFrame)
        modernCockpit.zPosition = 11.5
        addChild(modernCockpit)
        for (node, z) in [(modernTrim, 0.6), (modernLowerDash, 0.0),
                          (modernLowerLines, 0.7), (modernTankIcon, 1.4),
                          (modernTerrainProfile, 1.4), (modernHeadingPointer, 1.5),
                          (modernLowerCorners, 1.6), (modernHitTrack, 0.8),
                          (modernHitRing, 0.9), (modernAmmoTrack, 0.6),
                          (modernAmmoFill, 0.7), (modernShieldTrack, 0.6),
                          (modernShieldFill, 0.7), (modernThreatPanel, 0.4)] {
            node.zPosition = z
            modernCockpit.addChild(node)
        }
        for label in [modernBest, modernTankStatus, modernIntegrity,
                      modernHitCaption, modernHitValue, modernCompassLabel,
                      modernHeadingValue, modernTerrainLabel,
                      modernSectorValue, modernStatusText] + modernHeadingTicks + modernLowerExtra {
            label.zPosition = 4
            label.verticalAlignmentMode = .center
            modernCockpit.addChild(label)
        }
        for tick in modernHeadingTicks {
            tick.fontSize = 10
            tick.horizontalAlignmentMode = .center
        }
        for label in modernLowerExtra {
            label.fontSize = 11
            label.horizontalAlignmentMode = .left
            label.verticalAlignmentMode = .center
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
                     modernHitTrack, modernTankIcon, modernTerrainProfile,
                     modernHeadingPointer, modernLowerCorners] {
            node.fillColor = .clear
        }
        for node in [modernAmmoTrack, modernAmmoFill,
                     modernShieldTrack, modernShieldFill] {
            node.strokeColor = .clear
        }
        modernLowerDash.lineWidth = 1.1
        modernThreatPanel.lineWidth = 1.5
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
        // A level-intro is a true simulation pause: *any* key starts the wave,
        // without also steering, firing, or consuming ammunition on that press.
        if round == .levelReady {
            pressedKeys.removeAll()
            round = .playing
            lastUpdateTime = 0
            return
        }
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
            if round == .levelReady {
                pressedKeys.removeAll()
                round = .playing
                lastUpdateTime = 0
                return
            }
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
        pulse = 0
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
        round = .levelReady
        lastUpdateTime = 0
    }

    override func update(_ currentTime: TimeInterval) {
        let elapsedFrame = lastUpdateTime == 0 ? 0.0 : currentTime - lastUpdateTime
        if elapsedFrame > 0.001 && elapsedFrame < 1 {
            observedFPS = 0.92 * observedFPS + 0.08 * min(240, 1.0 / elapsedFrame)
        }
        let dt = lastUpdateTime == 0 ? 0.0 : min(0.04, max(0, currentTime - lastUpdateTime))
        lastUpdateTime = currentTime
        if round == .playing { gameClock += dt; tick(dt) }
        if round == .levelReady { pulse += dt }
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
            // Flying disks travel slowly to preserve their ominous, floating
            // appearance. Their visual rotation speed is independent.
            let movement = (type == .hunter ? 4.6 : (type == .saucer ? 1.10 : 2.55))
                * threatLevel.enemyVelocity * rules.enemySpeed
            let aim = atan2(diff.x, diff.z)
            if type == .saucer {
                let tangent = GroundPoint(cos(enemies[idx].phase * 0.8), sin(enemies[idx].phase * 0.8))
                enemies[idx].center = enemies[idx].center + tangent * (movement * dt)
            } else {
                let obstaclesForNavigation = obstacles.map {
                    NavigationObstacle(center: $0.center, radius: $0.size * 0.78)
                }
                let shotBlockers = obstacles.map {
                    NavigationObstacle(center: $0.center, radius: $0.size * 0.66)
                }
                let occupied = enemies.indices
                    .filter { $0 != idx && enemies[$0].kind != .saucer }
                    .map { enemies[$0].center }
                let clearShot = EnemyNavigation.clearSegment(
                    enemies[idx].center, tankPosition, obstacles: shotBlockers)
                let desiredDistance = type == .hunter ? 19.0 : 24.0

                // Replan if the target moves, cover blocks the shot, or the
                // previous waypoint was reached. Stagger work across frames.
                enemies[idx].routeRefreshRemaining -= dt
                if enemies[idx].routeRefreshRemaining <= 0 ||
                    (enemies[idx].navigationWaypoint?.distance(
                        to: enemies[idx].center) ?? .infinity) < 4 {
                    let shouldMove = !clearShot || distance > desiredDistance + 7
                    enemies[idx].navigationWaypoint = shouldMove
                        ? EnemyNavigation.nextWaypoint(
                            from: enemies[idx].center, player: tankPosition,
                            obstacles: obstaclesForNavigation,
                            shotBlockers: shotBlockers, otherTanks: occupied,
                            desiredStandOff: desiredDistance)
                        : nil
                    enemies[idx].routeRefreshRemaining =
                        0.55 + Double(idx % 4) * 0.12
                }

                // When a tank is already in range and has a clear line of
                // fire, face the player. Otherwise turn toward a waypoint
                // around buildings, keeping a safe distance from other tanks.
                let destination = enemies[idx].navigationWaypoint
                let shouldAdvance = destination != nil &&
                    (!clearShot || distance > desiredDistance + 6)
                let steeringVector = shouldAdvance
                    ? (destination! - enemies[idx].center) : diff
                let aimHeading = atan2(steeringVector.x, steeringVector.z)
                let wobble = type == .hunter ? sin(enemies[idx].phase * 1.4) * 0.12 : 0
                enemies[idx].heading = wrapAngle(aimHeading + wobble)
                if shouldAdvance {
                    let headingVector = steeringVector.normalized
                    let proposed = enemies[idx].center + headingVector * (movement * dt)
                    let clearMovement = EnemyNavigation.clearSegment(
                        enemies[idx].center, proposed,
                        obstacles: obstaclesForNavigation,
                        clearance: EnemyNavigation.enemyRadius)
                    if !blocked(proposed, radius: EnemyNavigation.enemyRadius) &&
                        clearMovement &&
                        proposed.distance(to: tankPosition) > 5 &&
                        EnemySpawnLayout.isSeparated(
                            proposed, from: occupied,
                            minimum: EnemySpawnLayout.movementSpacing) {
                        enemies[idx].center = proposed
                    } else {
                        // Obstacles or another tank can block the planned step;
                        // discard the stale route so next frame finds a detour.
                        enemies[idx].navigationWaypoint = nil
                        enemies[idx].routeRefreshRemaining = 0
                    }
                }
            }
            let visibleTarget = type != .saucer &&
                EnemyNavigation.clearSegment(
                    enemies[idx].center, tankPosition,
                    obstacles: obstacles.map {
                        NavigationObstacle(center: $0.center, radius: $0.size * 0.66)
                    })
            if enemies[idx].reload <= 0 && visibleTarget &&
                distance < 79 && distance > 7 {
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
                pressedKeys.removeAll()
                driveSpeed = 0
                // Do not advance simulation until the player acknowledges
                // the wireframe LEVEL banner.
                round = .levelReady
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
        // Layout the connected street grid first. Then fill a minority of
        // city-block interiors with small clusters, leaving broad empty blocks.
        let seed = UInt64.random(in: 1...UInt64.max)
        for site in CityLayout.buildings(count: rules.obstacleCount, seed: seed) {
            let centerDistrict = abs(site.center.x) < 60 &&
                                 abs(site.center.z) < 60
            let middleDistrict = abs(site.center.x) < 120 &&
                                 abs(site.center.z) < 120
            let kind: Obstacle.Kind
            if centerDistrict {
                // Downtown skyline: predominantly tall city buildings.
                switch site.variant % 5 {
                case 0, 1: kind = .building
                case 2, 3: kind = .tower
                default: kind = .monolith
                }
            } else if middleDistrict {
                switch site.variant % 5 {
                case 0, 1: kind = .building
                case 2: kind = .tower
                case 3: kind = .block
                default: kind = .pyramid
                }
            } else {
                kind = site.variant.isMultiple(of: 3) ? .building : .block
            }
            obstacles.append(Obstacle(center: site.center,
                                      size: site.size, kind: kind))
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
        // Change the angular starting sectors every wave. Keep the central
        // aiming cone empty on spawn, even after moving to a new city block.
        let wavePhase = Double.random(in: (-Double.pi)...Double.pi)
        let forwardExclusion = Double.pi / 5.0
        for n in 0..<count {
            let occupied = enemies.map { $0.center }
            guard let target = EnemySpawnLayout.choosePosition(
                player: tankPosition, heading: heading, index: n, count: count,
                existing: occupied, phase: wavePhase,
                forwardExclusion: forwardExclusion,
                isOpen: { !self.blocked($0, radius: 4) }) else {
                // Never spawn a pile of tanks: an obstructed sector produces
                // fewer enemies rather than falling back to an occupied cell.
                continue
            }
            let kind: FoeType = (rules.huntersEnabled && wave >= 3 && n % 4 == 2)
                ? .hunter : ((rules.saucersEnabled && wave >= 2 && n % 6 == 5) ? .saucer : .tank)
            let initialHeading = atan2(tankPosition.x - target.x,
                                       tankPosition.z - target.z)
            enemies.append(Foe(center: target, heading: initialHeading, kind: kind,
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
        guard round == .playing || round == .paused || round == .levelReady else { return nil }
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
            secondsUntilSaucerPatrol: saucerPatrol.secondsUntilArrival,
            awaitingLevelStart: round == .levelReady
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
        round = saved.awaitingLevelStart == true ? .levelReady : .paused
        // Older saves continue paused and require P; a saved level-intro
        // remains on its any-key start screen.
        return true
    }

    /// Manual, local-only snapshot for copying into bug reports. No automatic upload.
    func feedbackReport() -> String {
        let mode = displayMode == .classic ? "Classic" : "Modern"
        let state: String
        switch round {
        case .title: state = "Title"
        case .levelReady: state = "Level ready (press any key)"
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
            (ground, displayMode == .classic ? muted.withAlphaComponent(0.67) : muted,
             displayMode == .classic ? 1.05 : 1.2,
             displayMode == .classic ? 0 : 1.3),
            (structures, green.withAlphaComponent(0.82), 1.5, displayMode == .classic ? 0.35 : 2.6),
            // Enemy armor is always orange for immediate identification.
            (opponentLines, NSColor(calibratedRed: 1, green: 0.57, blue: 0.19, alpha: 1),
             displayMode == .classic ? 1.35 : 1.55,
             displayMode == .classic ? 0.15 : 0.8),
            (opponentSaucerLines, green, 1.8, displayMode == .classic ? 0.7 : 3.1),
            (shotLines, accent, 2.5, displayMode == .classic ? 0.8 : 5),
            (flashLines, accent, 2.0, displayMode == .classic ? 1 : 5),
            (reticle, accent, displayMode == .classic ? 1.05 : 1.5,
             displayMode == .classic ? 0.15 : 0.55),
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
        let enemyOrange = NSColor(calibratedRed: 1, green: 0.49, blue: 0.12, alpha: 1)
        radarEnemyContacts.strokeColor = enemyOrange
        radarEnemyContacts.fillColor = enemyOrange.withAlphaComponent(0.90)
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
        modernLowerLines.strokeColor = cyan.withAlphaComponent(0.45)
        modernLowerLines.lineWidth = 1
        modernTankIcon.strokeColor = cyan
        modernTankIcon.lineWidth = 2
        modernTankIcon.glowWidth = 3
        modernTerrainProfile.strokeColor = cyan.withAlphaComponent(0.94)
        modernTerrainProfile.lineWidth = 1.8
        modernTerrainProfile.glowWidth = 1.8
        modernHeadingPointer.strokeColor = amber
        modernHeadingPointer.lineWidth = 2
        modernHeadingPointer.glowWidth = 3
        modernLowerCorners.strokeColor = amber
        modernLowerCorners.lineWidth = 2
        modernLowerCorners.glowWidth = 3.5
        modernHitTrack.strokeColor = cyan.withAlphaComponent(0.18)
        modernHitTrack.lineWidth = 8
        modernHitRing.strokeColor = NSColor(calibratedRed: 0.16, green: 1, blue: 0.49, alpha: 1)
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
                      modernCompassLabel, modernTerrainLabel, modernStatusText]
                     + modernHeadingTicks + modernLowerExtra {
            label.fontColor = cyan.withAlphaComponent(0.85)
        }
        for label in [modernTankStatus, modernHitValue, modernHeadingValue, modernSectorValue] {
            label.fontColor = cyan
        }
        rearLabel.fontColor = amber
        proximityLabel.fontColor = amber
        streetMarks.strokeColor = modern
            ? NSColor(calibratedRed: 0.70, green: 0.84, blue: 0.74, alpha: 0.29)
            : green.withAlphaComponent(0.31)
        streetMarks.lineWidth = modern ? 0.9 : 0.65
        streetMarks.glowWidth = 0
        rearGround.strokeColor = green.withAlphaComponent(0.55)
        rearGround.lineWidth = 0.6
        rearEnvironment.strokeColor = green.withAlphaComponent(0.82)
        rearEnvironment.lineWidth = 1.15
        rearEnemies.strokeColor = enemyOrange
        rearEnemies.lineWidth = 1.45
        rearEnemies.glowWidth = displayMode == .modern ? 0.8 : 0.2
        rearSaucers.strokeColor = green
        rearSaucers.lineWidth = 1.5
        rearSaucers.glowWidth = displayMode == .modern ? 2.5 : 0.7
        rearShots.strokeColor = amber
        rearShots.glowWidth = 2.6
        rearBackground.strokeColor = .clear
        rearBackground.fillColor = NSColor(calibratedRed: 0.012, green: 0.04, blue: 0.055, alpha: 0.98)
        radarStreetGrid.strokeColor = modern
            ? NSColor(calibratedRed: 0.18, green: 0.79, blue: 0.65, alpha: 0.47)
            : muted.withAlphaComponent(0.62)
        radarStreetGrid.fillColor = .clear
        radarStreetGrid.lineWidth = 0.8
        radarObstacleContacts.strokeColor = muted.withAlphaComponent(0.95)
        radarObstacleContacts.fillColor = muted.withAlphaComponent(0.55)
        radarObstacleContacts.lineWidth = 0.7
        for rail in [telemetryLeftAccent, telemetryRightAccent] { rail.fillColor = amber }
        for label in [telemetryLeftHeading, telemetryRightHeading] {
            label.fontColor = modern ? cyan : amber
        }
        for label in [telemetryLeftDetail, telemetryLeftFootnote, telemetryCoordinates,
                      telemetryRightDetail, telemetryRightFootnote, telemetryAmmo] {
            label.fontColor = modern ? cyan.withAlphaComponent(0.94)
                                     : green.withAlphaComponent(0.86)
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
        let roads = CGMutablePath()
        let markings = CGMutablePath()
        // Wide, continuous orthogonal streets frame 60-unit city blocks.
        // World-space layout matches obstacle placement and the square radar.
        let halfStreet = CityLayout.streetHalfWidth
        let roadStep = CityLayout.streetSpacing
        let extent = CityLayout.cityExtent
        let roadOriginX = Int((tankPosition.x / roadStep).rounded())
        let roadOriginZ = Int((tankPosition.z / roadStep).rounded())
        for offset in -3...3 {
            let x = Double(roadOriginX + offset) * roadStep
            let z = Double(roadOriginZ + offset) * roadStep
            for side in [-1.0, 1.0] {
                let roadX = x + side * halfStreet
                line(roads, WorldPoint(roadX, 0.025, -extent),
                     WorldPoint(roadX, 0.025, extent), c)
                let roadZ = z + side * halfStreet
                line(roads, WorldPoint(-extent, 0.025, roadZ),
                     WorldPoint(extent, 0.025, roadZ), c)
            }
            // Dashed lane markings: only the road centerlines, so the
            // empty blocks stay visually distinct from the paved corridors.
            for segmentIndex in -18...17 {
                let start = Double(segmentIndex) * 10.0 + 1.3
                let end = start + 5.8
                line(markings, WorldPoint(x, 0.028, start),
                     WorldPoint(x, 0.028, end), c)
                line(markings, WorldPoint(start, 0.028, z),
                     WorldPoint(end, 0.028, z), c)
            }
        }
        ground.path = roads
        streetMarks.path = markings
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

        let tankPath = CGMutablePath()
        let saucerPath = CGMutablePath()
        for enemy in enemies {
            if enemy.center.distance(to: tankPosition) > 170 { continue }
            if enemy.kind == .saucer { drawSaucer(enemy, on: saucerPath, camera: c) }
            else { drawTank(enemy, on: tankPath, camera: c) }
        }
        opponentLines.path = tankPath
        opponentSaucerLines.path = saucerPath
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

        // Purpose-built inset grid. Projection of long world-space lines that
        // cross the near plane created full-screen diagonal streaks in the rear
        // camera; horizon-convergent short segments stay within the monitor.
        let gridPath = CGMutablePath()
        let backHeading = heading + .pi
        let horizon = max(14.0, min(height * 0.63, backCamera.horizon))
        for row in 1...7 {
            let normalized = Double(row) / 7.0
            let y = horizon * (1.0 - normalized * normalized)
            segment(gridPath, point(0, y), point(width, y))
        }
        for lane in -6...6 {
            let t = Double(lane) / 6
            let nearX = width / 2 + t * width * 0.65
            let farX = width / 2 + t * width * 0.07
            segment(gridPath, point(farX, horizon), point(nearX, 0))
        }
        // The mountains continue to respond to rear-facing tank heading.
        var previous = point(0, horizon)
        for i in 0...40 {
            let x = Double(i) * width / 40
            let bearing = backHeading + atan2((x - width / 2) / backCamera.focal, 1)
            let top = point(x, horizon + ridge(bearing, multiplier: 0.30))
            if i > 0 { segment(gridPath, previous, top) }
            previous = top
        }
        rearGround.path = gridPath

        let obstaclePath = CGMutablePath()
        // Structures intersecting the camera used to project giant shards.
        // Keep nearby rearward objects, but avoid drawing their interior faces.
        for object in obstacles where
            object.center.distance(to: tankPosition) < 95 &&
            object.center.distance(to: tankPosition) > max(5, object.size * 1.25) {
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

        let tankPath = CGMutablePath()
        let saucerPath = CGMutablePath()
        for foe in enemies where foe.center.distance(to: tankPosition) < 120 {
            if foe.kind == .saucer {
                drawSaucer(foe, on: saucerPath, camera: backCamera)
            } else {
                drawTank(foe, on: tankPath, camera: backCamera)
            }
        }
        rearEnemies.path = tankPath
        rearSaucers.path = saucerPath
        let projectilePath = CGMutablePath()
        for shell in shells {
            let height = shell.hostile ? 1.5 : 1.65
            let tail = shell.center - shell.direction * 2.6
            line(projectilePath, WorldPoint(shell.center, height: height),
                 WorldPoint(tail, height: height), backCamera)
        }
        rearShots.path = projectilePath
    }

    /// Reference-style upper instrumentation. All values come from the live
    /// game simulation and are positioned relative to their actual panel widths.
    /// The background art is still native SpriteKit vector geometry.
    private func renderModernUpperHUD(
        width w: Double, height h: Double,
        leftCenter: Double, rightCenter: Double,
        bankWidth: Double, panelHeight: Double
    ) {
        let cyan = NSColor(calibratedRed: 0.25, green: 0.95, blue: 0.98, alpha: 1)
        let greenBright = NSColor(calibratedRed: 0.43, green: 1.0, blue: 0.66, alpha: 1)
        let pale = NSColor(calibratedRed: 0.70, green: 0.97, blue: 0.98, alpha: 1)
        let amber = NSColor(calibratedRed: 1, green: 0.49, blue: 0.16, alpha: 1)
        let left = leftCenter - bankWidth / 2
        let right = rightCenter - bankWidth / 2
        let top = h - 16
        let scale = max(0.69, min(1, bankWidth / 310))
        func item(_ id: Int, _ text: String, _ x: Double, _ y: Double,
                  _ size: Double, _ color: NSColor = pale) {
            let label = modernUpperText[id]
            label.text = text
            label.position = point(x, y)
            label.fontSize = CGFloat(size * scale)
            label.fontColor = color
        }
        let bearing = Int((heading * 180 / .pi + 360)
                           .truncatingRemainder(dividingBy: 360).rounded()) % 360
        let target = targetTelemetry()
        let range = target?.range
        let targetBearing: Int? = target.map {
            Int((Double(bearing) + $0.error * 180 / .pi + 720)
                .truncatingRemainder(dividingBy: 360).rounded()) % 360
        }
        item(0, "TARGETING  //  NAVIGATION",
             left + 15, top - 23, 12, cyan)
        item(1, String(format: "HDG %03d°", bearing),
             left + 17, top - 79, 26, cyan)
        item(2, String(format: "SPD %+.1f", driveSpeed),
             left + bankWidth * 0.57, top - 79, 23, cyan)
        item(3, targetBearing.map { String(format: "TGT %03d", $0) } ?? "TGT ---",
             left + 16, top - 126, 15)
        item(4, target.map { String(format: "AIM %+.1f°", $0.error * 180 / .pi) }
                ?? "AIM ---",
             left + bankWidth * 0.34, top - 126, 14)
        item(5, range.map { String(format: "RNG %.0f", $0) } ?? "RNG ---",
             left + bankWidth * 0.73, top - 126, 14)
        item(6, String(format: "H/M %02d:%02d", shotTally.hits, shotTally.misses),
             left + 16, top - 166, 14)
        item(7, String(format: "HIT %.0f%%", shotTally.hitPercentage),
             left + bankWidth * 0.40, top - 166, 14, greenBright)
        item(8, String(format: "F %02d", shotTally.pending),
             left + bankWidth * 0.78, top - 166, 14)
        item(9, "POSITION", left + 16, top - 211, 14)
        item(10, String(format: "X %+.1f", tankPosition.x),
             left + bankWidth * 0.39, top - 211, 14)
        item(11, String(format: "Z %+.1f", tankPosition.z),
             left + bankWidth * 0.72, top - 211, 14)

        item(12, "COMBAT SYSTEMS  //  STATUS",
             right + 15, top - 23, 12, cyan)
        item(13, "SCORE", right + 17, top - 59, 13)
        item(14, String(format: "%06d", score),
             right + 17, top - 93, 33, cyan)
        item(15, "BEST", right + bankWidth * 0.72, top - 59, 13)
        item(16, String(format: "%06d", bestScore),
             right + bankWidth * 0.72, top - 92, 19, pale)
        item(17, String(format: "WAVE %02d", wave),
             right + 16, top - 128, 14)
        item(18, String(format: "LIVES %d", lives),
             right + bankWidth * 0.36, top - 128, 14)
        item(19, "LEVEL " + threatLevel.rawValue.uppercased(),
             right + bankWidth * 0.64, top - 128, 13, greenBright)
        item(20, "SHIELD", right + 52, top - 162, 14)
        let shieldStatus = shieldDuration > 0
            ? String(format: "ACTIVE %.1f", shieldDuration)
            : shieldCooldown > 0
                ? String(format: "CHARGING %.1f", shieldCooldown)
                : "READY [SHIFT]"
        item(21, shieldStatus, right + bankWidth * 0.49, top - 162,
             14, shieldDuration > 0 ? cyan : (shieldCooldown > 0 ? amber : greenBright))
        item(22, String(format: "AMMO %02d/%02d",
                         cannon.roundsRemaining, cannon.maxRounds),
             right + 52, top - 208, 14, cyan)
        item(23, String(format: "RELOAD %.1fs", cannon.reloadRemaining),
             right + bankWidth * 0.64, top - 208, 13)
        item(24, "◆", right + 24, top - 162, 14, greenBright)
        // A light panel hierarchy: header rule and three instrument rows.
        let dividers = CGMutablePath()
        func hline(_ x: Double, _ y: Double, _ length: Double) {
            segment(dividers, point(x, y), point(x + length, y))
        }
        func vline(_ x: Double, _ y1: Double, _ y2: Double) {
            segment(dividers, point(x, y1), point(x, y2))
        }
        for x in [left, right] {
            hline(x + 12, top - 42, bankWidth - 24)
            hline(x + 12, top - 106, bankWidth - 24)
            hline(x + 12, top - 145, bankWidth - 24)
            if x == left { hline(x + 12, top - 185, bankWidth - 24) }
            else { hline(x + 12, top - 146, bankWidth - 24) }
        }
        vline(left + bankWidth * 0.55, top - 98, top - 58)
        for fraction in [0.31, 0.70] {
            vline(left + bankWidth * fraction, top - 139, top - 114)
            vline(left + bankWidth * fraction, top - 179, top - 153)
        }
        vline(right + bankWidth * 0.66, top - 104, top - 53)
        for fraction in [0.32, 0.62] {
            vline(right + bankWidth * fraction, top - 139, top - 114)
        }
        modernUpperDividers.path = dividers
        modernUpperDividers.strokeColor = cyan.withAlphaComponent(0.32)
        modernUpperDividers.lineWidth = 0.9

        // Tiny armoured shield outline and a three-round magazine symbol.
        let icons = CGMutablePath()
        let shieldCenter = point(right + 29, top - 166)
        icons.move(to: point(shieldCenter.x - 10, shieldCenter.y + 11))
        icons.addLine(to: point(shieldCenter.x + 10, shieldCenter.y + 11))
        icons.addLine(to: point(shieldCenter.x + 9, shieldCenter.y - 3))
        icons.addLine(to: point(shieldCenter.x, shieldCenter.y - 14))
        icons.addLine(to: point(shieldCenter.x - 9, shieldCenter.y - 3))
        icons.closeSubpath()
        segment(icons, point(shieldCenter.x, shieldCenter.y + 7),
                point(shieldCenter.x, shieldCenter.y - 8))
        for bullet in 0..<3 {
            let x = right + 18 + Double(bullet) * 11
            let y = top - 215
            segment(icons, point(x, y - 5), point(x, y + 10))
            segment(icons, point(x + 6, y - 5), point(x + 6, y + 10))
            segment(icons, point(x, y + 10), point(x + 3, y + 16))
            segment(icons, point(x + 3, y + 16), point(x + 6, y + 10))
        }
        modernUpperIcons.path = icons
        modernUpperIcons.strokeColor = greenBright
        modernUpperIcons.lineWidth = 1.5
        modernUpperIcons.glowWidth = 2

        // Amber cut-corner accents distinguish the military display from
        // four ordinary rounded cards without relying on a raster background.
        let corners = CGMutablePath()
        for (x, sign) in [(left, 1.0), (right + bankWidth, -1.0)] {
            segment(corners, point(x, top - 26), point(x + sign * 14, top - 10))
            segment(corners, point(x + sign * 14, top - 10),
                    point(x + sign * 55, top - 10))
            segment(corners, point(x, top - panelHeight + 26),
                    point(x + sign * 14, top - panelHeight + 10))
        }
        modernOrangeCorners.path = corners
        modernOrangeCorners.strokeColor = amber
        modernOrangeCorners.lineWidth = 2.1
        modernOrangeCorners.glowWidth = 3.5
    }

    /// Vector Drift-inspired Modern cockpit. All gauges are driven by actual
    /// battle data; Classic keeps its original arcade readouts.
    /// Instrument panel modeled as a military tank command dashboard.
    /// Gauges, compass, and status are SpriteKit vectors linked to live state.
    private func renderModernCockpit(
        width w: Double, height h: Double, bankWidth: Double,
        leftX: Double, rightX: Double, radarX: Double,
        rearX: Double, radarPanelWidth: Double,
        rearPanelWidth: Double, topHeight: Double
    ) {
        let cyan = NSColor(calibratedRed: 0.22, green: 0.97, blue: 0.97, alpha: 1)
        let greenLight = NSColor(calibratedRed: 0.24, green: 1.0, blue: 0.54, alpha: 1)
        let amber = NSColor(calibratedRed: 1, green: 0.54, blue: 0.13, alpha: 1)
        let scale = min(1.0, max(0.72, w / 1450))
        let bottomY = 27.0
        let bottomHeight = max(113.0, min(152.0, h * 0.177))
        let topY = bottomY + bottomHeight
        let x0 = 12.0
        let x1 = w * 0.225
        let x2 = w * 0.370
        let x3 = w * 0.670
        let x4 = w * 0.830
        let x5 = w - 12
        let middleY = bottomY + bottomHeight * 0.51

        // Continuous beveled panel, with small orange accent plates.
        let border = CGMutablePath()
        let cut = 14.0
        border.move(to: point(x0 + cut, bottomY))
        border.addLine(to: point(x5 - cut, bottomY))
        border.addLine(to: point(x5, bottomY + cut))
        border.addLine(to: point(x5, topY - cut))
        border.addLine(to: point(x5 - cut, topY))
        border.addLine(to: point(x0 + cut, topY))
        border.addLine(to: point(x0, topY - cut))
        border.addLine(to: point(x0, bottomY + cut))
        border.closeSubpath()
        modernLowerDash.path = border
        modernLowerDash.strokeColor = cyan
        modernLowerDash.fillColor = NSColor(
            calibratedRed: 0.008, green: 0.041, blue: 0.055, alpha: 0.97)

        let strokes = CGMutablePath()
        segment(strokes, point(x0 + 32, topY - 8), point(x5 - 32, topY - 8))
        segment(strokes, point(x0 + 32, bottomY + 7), point(x5 - 32, bottomY + 7))
        for divider in [x1, x2, x3, x4] {
            segment(strokes, point(divider, bottomY + 15),
                    point(divider, topY - 15))
        }
        modernLowerLines.path = strokes

        let trim = CGMutablePath()
        for (x, direction) in [(x0, 1.0), (x5, -1.0)] {
            segment(trim, point(x, topY - 29), point(x + direction * 20, topY - 9))
            segment(trim, point(x + direction * 20, topY - 9),
                    point(x + direction * 65, topY - 9))
            segment(trim, point(x, bottomY + 29),
                    point(x + direction * 20, bottomY + 9))
        }
        modernLowerCorners.path = trim

        // Stylized side-view tank, drawn from independently projected lines.
        let tankPath = CGMutablePath()
        let tankX = x0 + 16
        let tankWidth = min(104.0, (x1 - x0) * 0.39)
        let tankY = middleY - 5
        let leftEdge = tankX
        let rightEdge = tankX + tankWidth
        let wheelY = tankY - 20
        segment(tankPath, point(leftEdge + 7, wheelY + 19),
                point(rightEdge - 7, wheelY + 19))
        segment(tankPath, point(rightEdge - 7, wheelY + 19),
                point(rightEdge, wheelY + 11))
        segment(tankPath, point(rightEdge, wheelY + 11),
                point(rightEdge - 10, wheelY - 3))
        segment(tankPath, point(rightEdge - 10, wheelY - 3),
                point(leftEdge + 9, wheelY - 3))
        segment(tankPath, point(leftEdge + 9, wheelY - 3),
                point(leftEdge, wheelY + 11))
        segment(tankPath, point(leftEdge, wheelY + 11),
                point(leftEdge + 7, wheelY + 19))
        for wheel in 0..<5 {
            let x = leftEdge + 17 + Double(wheel) * (tankWidth - 34) / 4
            tankPath.addEllipse(in: CGRect(x: x - 5, y: wheelY + 2,
                                           width: 10, height: 10))
        }
        segment(tankPath, point(leftEdge + 24, wheelY + 19),
                point(leftEdge + 35, wheelY + 39))
        segment(tankPath, point(leftEdge + 35, wheelY + 39),
                point(leftEdge + 73, wheelY + 39))
        segment(tankPath, point(leftEdge + 73, wheelY + 39),
                point(leftEdge + 83, wheelY + 19))
        segment(tankPath, point(leftEdge + 41, wheelY + 40),
                point(leftEdge + 41, wheelY + 48))
        segment(tankPath, point(leftEdge + 39, wheelY + 48),
                point(leftEdge + 63, wheelY + 48))
        segment(tankPath, point(leftEdge + 63, wheelY + 48),
                point(leftEdge + 63, wheelY + 40))
        segment(tankPath, point(leftEdge + 77, wheelY + 31),
                point(rightEdge + 12, wheelY + 31))
        modernTankIcon.path = tankPath

        // Tank integrity is a readiness proxy based on remaining lives; the
        // game doesn't yet simulate component-by-component armor damage.
        let integrity = 100.0 * Double(max(0, lives)) /
                        Double(max(1, rules.startingLives))
        let statusLeft = leftEdge + tankWidth + 22
        func setExtra(_ id: Int, _ value: String,
                      x: Double, y: Double, size: Double,
                      color: NSColor, alignedRight: Bool = false) {
            let label = modernLowerExtra[id]
            label.text = value
            label.position = point(x, y)
            label.fontSize = CGFloat(size * scale)
            label.fontColor = color
            label.horizontalAlignmentMode = alignedRight ? .right : .left
        }
        modernTankStatus.position = point(statusLeft, topY - 31)
        modernTankStatus.fontColor = greenLight
        modernTankStatus.fontSize = CGFloat(14 * scale)
        modernTankStatus.text = "• TANK STATUS"
        modernIntegrity.position = point(statusLeft, topY - 61)
        modernIntegrity.fontSize = CGFloat(12 * scale)
        modernIntegrity.text = "INTEGRITY"
        setExtra(0, String(format: "%.0f%%", max(0, min(100, integrity))),
                 x: x1 - 16, y: topY - 61,
                 size: 12, color: greenLight, alignedRight: true)
        modernStatusText.position = point(statusLeft, topY - 87)
        modernStatusText.fontSize = CGFloat(12 * scale)
        modernStatusText.text = "SYSTEMS"
        setExtra(1, round == .gameOver ? "OFFLINE" : "ONLINE",
                 x: x1 - 16, y: topY - 87,
                 size: 12, color: greenLight, alignedRight: true)
        setExtra(2, round == .playing ? "MODE  COMBAT" :
                       round == .paused ? "MODE  PAUSED" :
                       round == .levelReady ? "MODE  STANDBY" : "MODE  OFFLINE",
                 x: statusLeft, y: topY - 111, size: 11, color: cyan)

        // Hit ratio is backed by the existing resolved shot tally.
        modernHitCaption.position = point(x1 + 17, topY - 29)
        modernHitCaption.fontSize = CGFloat(13 * scale)
        modernHitCaption.text = "HIT RATIO"
        modernHitValue.position = point(x1 + 17, middleY - 12)
        modernHitValue.fontSize = CGFloat(35 * scale)
        modernHitValue.fontColor = cyan
        modernHitValue.text = String(format: "%.0f%%", shotTally.hitPercentage)
        let hitRadius = min(33.0, (x2 - x1) * 0.19)
        let hitPoint = point(x2 - hitRadius - 18, middleY - 4)
        let track = CGMutablePath()
        track.addEllipse(in: CGRect(x: hitPoint.x - hitRadius,
                                   y: hitPoint.y - hitRadius,
                                   width: hitRadius * 2, height: hitRadius * 2))
        modernHitTrack.path = track
        let ring = CGMutablePath()
        let hitFraction = min(1.0, max(0.0, shotTally.hitPercentage / 100))
        if hitFraction > 0 {
            ring.addArc(center: hitPoint, radius: hitRadius,
                        startAngle: -.pi / 2,
                        endAngle: -.pi / 2 + CGFloat(2.0 * .pi * hitFraction),
                        clockwise: false)
        }
        modernHitRing.path = ring

        // Calibrated moving compass tape: fine ticks and a fixed amber nose.
        let compassX = (x2 + x3) / 2
        let compassSpan = (x3 - x2) * 0.45
        let tapeY = bottomY + 49
        let headingDegrees = (heading * 180 / .pi + 360)
                             .truncatingRemainder(dividingBy: 360)
        let offset = headingDegrees.truncatingRemainder(dividingBy: 10) / 10
        let stepWidth = compassSpan / 6
        let tickPath = CGMutablePath()
        for step in -7...7 {
            let x = compassX + (Double(step) - offset) * stepWidth
            guard x >= compassX - compassSpan,
                  x <= compassX + compassSpan else { continue }
            let height = step.isMultiple(of: 2) ? 18.0 : 10.0
            segment(tickPath, point(x, tapeY), point(x, tapeY + height))
        }
        modernLowerLines.path = {
            let combined = CGMutablePath()
            combined.addPath(strokes)
            combined.addPath(tickPath)
            return combined
        }()
        let centerDegrees = Int(floor(headingDegrees / 10)) * 10
        for (index, label) in modernHeadingTicks.enumerated() {
            let step = (index - 3) * 2
            let x = compassX + (Double(step) - offset) * stepWidth
            label.position = point(x, bottomY + 30)
            label.text = String(format: "%03d°", (centerDegrees + step * 10 + 360) % 360)
            label.fontSize = CGFloat(11 * scale)
            label.isHidden = abs(x - compassX) > compassSpan - 8
        }
        let pointer = CGMutablePath()
        let pointerTip = bottomY + 66
        pointer.move(to: point(compassX, pointerTip))
        pointer.addLine(to: point(compassX - 7, pointerTip + 17))
        pointer.addLine(to: point(compassX + 7, pointerTip + 17))
        pointer.closeSubpath()
        modernHeadingPointer.path = pointer
        modernHeadingValue.position = point(compassX, topY - 28)
        modernHeadingValue.fontColor = amber
        modernHeadingValue.fontSize = CGFloat(25 * scale)
        modernHeadingValue.text = String(
            format: "%03d°", Int(headingDegrees.rounded()) % 360)
        modernCompassLabel.position = point(compassX, bottomY + 14)
        modernCompassLabel.fontSize = CGFloat(9 * scale)
        modernCompassLabel.text = "HEADING  //  LIVE"

        // Skyline terrain signature moves with tank heading. Flat-ground
        // elevation is zero: no nonexistent height sensor is implied.
        let plotStart = x3 + 19
        let plotEnd = x4 - 17
        let plotBottom = bottomY + 31
        let plotWidth = max(20.0, plotEnd - plotStart)
        let terrain = CGMutablePath()
        var old = point(plotStart, plotBottom)
        for i in 0...48 {
            let t = Double(i) / 48
            let bearing = heading + (t - 0.5) * 1.05
            let y = plotBottom + 16 + min(25.0, ridge(bearing, multiplier: 0.48))
            let next = point(plotStart + plotWidth * t, y)
            if i > 0 { segment(terrain, old, next) }
            old = next
        }
        segment(terrain, point(plotStart, plotBottom),
                point(plotEnd, plotBottom))
        for fraction in [0.25, 0.5, 0.75] {
            let x = plotStart + plotWidth * fraction
            segment(terrain, point(x, plotBottom),
                    point(x, plotBottom + 10))
        }
        modernTerrainProfile.path = terrain
        modernTerrainLabel.position = point(x4 - 17, topY - 28)
        modernTerrainLabel.text = "TERRAIN PROFILE"
        modernTerrainLabel.fontSize = CGFloat(12 * scale)

        // Sector readout uses actual 60-unit city blocks, not fabricated
        // location labels. X maps A-F, Z maps 01-06.
        let sectorX = min(5, max(0,
            Int(floor((tankPosition.x + CityLayout.cityExtent)
                      / CityLayout.streetSpacing))))
        let sectorZ = min(5, max(0,
            Int(floor((tankPosition.z + CityLayout.cityExtent)
                      / CityLayout.streetSpacing))))
        let sectorLetter = String(UnicodeScalar(65 + sectorX)!)
        modernSectorValue.position = point(x5 - 25, topY - 64)
        modernSectorValue.text = String(format: "SECTOR %@-%02d",
                                       sectorLetter, sectorZ + 1)
        modernSectorValue.fontSize = CGFloat(14 * scale)
        modernSectorValue.fontColor = cyan
        setExtra(3, "TERRAIN", x: x5 - 25, y: topY - 27,
                 size: 12, color: cyan, alignedRight: true)
        setExtra(4, "ELEV   +0.0 m", x: x5 - 25, y: topY - 97,
                 size: 12, color: cyan, alignedRight: true)
        setExtra(5, String(format: "X %+.0f   Z %+.0f",
                           tankPosition.x, tankPosition.z),
                 x: x5 - 25, y: bottomY + 18,
                 size: 10, color: cyan.withAlphaComponent(0.80),
                 alignedRight: true)
        for unused in 6..<modernLowerExtra.count {
            modernLowerExtra[unused].text = ""
        }

        // Upper combat bank: preserve actual five-second shield readiness and
        // magazine depletion while keeping independent vector progress bars.
        let barLeft = rightX - bankWidth + 70
        let barWidth = max(46.0, bankWidth - 91)
        let barHeight = 7.0
        let shieldY = h - 16 - 185.0
        let ammoY = h - 16 - 229.0
        func bar(_ x: Double, _ y: Double, _ width: Double) -> CGPath {
            CGPath(roundedRect: CGRect(x: x, y: y,
                                        width: max(0.1, width),
                                        height: barHeight),
                   cornerWidth: 2.5, cornerHeight: 2.5,
                   transform: nil)
        }
        modernShieldTrack.path = bar(barLeft, shieldY, barWidth)
        let shieldValue = shieldDuration > 0
            ? shieldDuration / max(1, rules.shieldDuration)
            : max(0, 1 - shieldCooldown / max(0.01, rules.shieldCooldown))
        modernShieldFill.path = bar(
            barLeft, shieldY,
            barWidth * min(1, max(0, shieldValue)))
        modernShieldFill.fillColor = shieldDuration > 0 ? greenLight : amber
        modernAmmoTrack.path = bar(barLeft, ammoY, barWidth)
        modernAmmoFill.path = bar(
            barLeft, ammoY,
            barWidth * Double(cannon.roundsRemaining)
                / Double(max(1, cannon.maxRounds)))
        modernAmmoFill.fillColor = cannon.roundsRemaining <
            max(4, cannon.maxRounds / 5) ? amber : cyan

        let decoration = CGMutablePath()
        let top = h - 16.0
        let topBottom = top - topHeight
        let radarFrom = radarX - radarPanelWidth / 2 + 15
        let rearTo = rearX + rearPanelWidth / 2 - 15
        segment(decoration, point(radarFrom, topBottom + 7),
                point(rearTo, topBottom + 7))
        modernTrim.path = decoration

        let close = nearestTankDistance.flatMap {
            TankProximity.isClose($0) ? $0 : nil
        }
        modernThreatPanel.isHidden = close == nil || round != .playing
        if let distance = close, round == .playing {
            let width = min(570.0, w * 0.60)
            modernThreatPanel.path = CGPath(
                roundedRect: CGRect(x: w / 2 - width / 2,
                                    y: bottomY + bottomHeight + 18,
                                    width: width, height: 49),
                cornerWidth: 8, cornerHeight: 8, transform: nil)
            modernThreatPanel.alpha = CGFloat(
                0.80 + 0.20 * abs(sin(gameClock * 7)))
            modernThreatPanel.strokeColor =
                distance <= TankProximity.tankLength ? NSColor.systemRed : amber
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
        let panelHeight = modernHUD ? min(278.0, max(248.0, h * 0.34)) : 154.0
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
        let radarSide = min(radarPanelWidth, panelHeight)
        let radarY = topCenterY
        let radarRadius = radarSide / 2 - 7.0
        let leftX = modernHUD ? leftCenterX - bankWidth / 2 + 18 : 34.0
        let rightX = modernHUD ? rightCenterX + bankWidth / 2 - 18 : w - 34
        func panelRect(width: Double) -> CGPath {
            CGPath(roundedRect: CGRect(x: -width / 2, y: -panelHeight / 2,
                                       width: width, height: panelHeight),
                   cornerWidth: 12, cornerHeight: 12, transform: nil)
        }
        telemetryLeftPanel.path = panelRect(width: bankWidth)
        telemetryRightPanel.path = panelRect(width: bankWidth)
        radarPanel.path = CGPath(
            roundedRect: CGRect(x: -radarSide / 2, y: -radarSide / 2,
                                width: radarSide, height: radarSide),
            cornerWidth: 10, cornerHeight: 10, transform: nil)
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

        // Square tactical map fills its monitor. The circular range rings and
        // sweep remain inside that square; the rotating ray reaches the edge.
        let mapBorder = CGRect(x: radarX - radarRadius, y: radarY - radarRadius,
                               width: radarRadius * 2, height: radarRadius * 2)
        rp.addRect(mapBorder)
        for fraction in [1.0/3.0, 2.0/3.0, 1.0] {
            let ringRadius = radarRadius * fraction
            rp.addEllipse(in: CGRect(x: radarX-ringRadius, y: radarY-ringRadius,
                                     width: ringRadius*2, height: ringRadius*2))
        }
        segment(rp, point(radarX, radarY-radarRadius),
                point(radarX, radarY+radarRadius))
        segment(rp, point(radarX-radarRadius, radarY),
                point(radarX+radarRadius, radarY))
        for i in 0..<12 {
            let angle = Double(i) * Double.pi / 6
            let inner = radarRadius - (i.isMultiple(of: 3) ? 9.0 : 4.0)
            segment(rp, point(radarX + sin(angle)*inner, radarY + cos(angle)*inner),
                    point(radarX + sin(angle)*radarRadius,
                          radarY + cos(angle)*radarRadius))
        }
        let sweepAngle = gameClock * 1.45
        let directionX = sin(sweepAngle)
        let directionY = cos(sweepAngle)
        let sweepReach = radarRadius / max(abs(directionX), abs(directionY), 0.001)
        segment(rp, point(radarX, radarY),
                point(radarX + directionX * sweepReach,
                      radarY + directionY * sweepReach))
        segment(rp, point(radarX-3.6, radarY-3), point(radarX, radarY+5.5))
        segment(rp, point(radarX, radarY+5.5), point(radarX+3.6, radarY-3))

        func projectedRadar(_ center: GroundPoint) -> CGPoint {
            let dx = center.x - tankPosition.x
            let dz = center.z - tankPosition.z
            let right = dx*cos(heading) - dz*sin(heading)
            let forward = dx*sin(heading) + dz*cos(heading)
            return point(radarX + right/radarRange*radarRadius,
                         radarY + forward/radarRange*radarRadius)
        }
        let cityMap = CGMutablePath()
        // Liang-Barsky line clipping prevents street marks bleeding outside
        // the radar square while allowing the whole urban grid to rotate.
        func mapStreet(_ a: GroundPoint, _ b: GroundPoint) {
            let p = projectedRadar(a)
            let q = projectedRadar(b)
            let dx = q.x - p.x
            let dy = q.y - p.y
            var lower: CGFloat = 0
            var upper: CGFloat = 1
            let values = [
                (-dx, p.x - mapBorder.minX), (dx, mapBorder.maxX - p.x),
                (-dy, p.y - mapBorder.minY), (dy, mapBorder.maxY - p.y)
            ]
            for (side, distance) in values {
                if abs(side) < 0.000001 {
                    if distance < 0 { return }
                } else {
                    let t = distance / side
                    if side < 0 { lower = max(lower, t) }
                    else { upper = min(upper, t) }
                    if lower > upper { return }
                }
            }
            cityMap.move(to: CGPoint(x: p.x + lower*dx, y: p.y + lower*dy))
            cityMap.addLine(to: CGPoint(x: p.x + upper*dx, y: p.y + upper*dy))
        }
        for road in -3...3 {
            let center = Double(road) * CityLayout.streetSpacing
            for side in [-1.0, 1.0] {
                let margin = side * CityLayout.streetHalfWidth
                mapStreet(GroundPoint(center + margin, -CityLayout.cityExtent),
                          GroundPoint(center + margin, CityLayout.cityExtent))
                mapStreet(GroundPoint(-CityLayout.cityExtent, center + margin),
                          GroundPoint(CityLayout.cityExtent, center + margin))
            }
        }
        radarStreetGrid.path = cityMap

        let obstaclesOnRadar = CGMutablePath()
        let enemyContacts = CGMutablePath()
        let projectileHalos = CGMutablePath()
        let projectileDots = CGMutablePath()
        func radarPoint(_ center: GroundPoint) -> CGPoint? {
            let dx = center.x - tankPosition.x
            let dz = center.z - tankPosition.z
            let right = dx*cos(heading) - dz*sin(heading)
            let forward = dx*sin(heading) + dz*cos(heading)
            guard abs(right) <= radarRange - 5,
                  abs(forward) <= radarRange - 5 else { return nil }
            return point(radarX + right/radarRange*radarRadius,
                         radarY + forward/radarRange*radarRadius)
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
        telemetryLeftDetail.fontSize = modernHUD ? 14 : 12
        telemetryLeftFootnote.fontSize = modernHUD ? 13 : 11
        telemetryCoordinates.fontSize = modernHUD ? 13 : 10.5
        telemetryRightDetail.fontSize = modernHUD ? 13 : 12
        telemetryRightFootnote.fontSize = modernHUD ? 13 : 11
        telemetryRightDetail.text = String(format: "WAVE %02d   LIVES %d   %@", wave, lives, threatLevel.rawValue.uppercased())
        let shieldName = shieldDuration > 0
            ? String(format: "SHIELD ACTIVE %.1fs", shieldDuration)
            : shieldCooldown > 0
                ? String(format: "RECHARGING %.1fs", shieldCooldown)
                : "SHIELD READY [SHIFT]"
        telemetryRightFootnote.text = shieldName
        telemetryAmmo.fontSize = modernHUD ? 16 : (w < 1050 ? 12 : 15)
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

        let legacyTexts: [SKLabelNode] = [
            midHUD, rightHUD, telemetryLeftHeading, telemetryRightHeading,
            telemetryLeftDetail, telemetryLeftFootnote, telemetryCoordinates,
            telemetryRightDetail, telemetryRightFootnote, telemetryAmmo
        ]
        for label in legacyTexts { label.isHidden = modernHUD }
        for label in modernUpperText { label.isHidden = !modernHUD }
        for shape in [modernUpperDividers, modernUpperIcons, modernOrangeCorners] {
            shape.isHidden = !modernHUD
        }
        if modernHUD {
            renderModernCockpit(
                width: w, height: h, bankWidth: bankWidth,
                leftX: leftX, rightX: rightX, radarX: radarX,
                rearX: rearX, radarPanelWidth: radarPanelWidth,
                rearPanelWidth: rearPanelWidth, topHeight: panelHeight)
            renderModernUpperHUD(width: w, height: h,
                                 leftCenter: leftCenterX, rightCenter: rightCenterX,
                                 bankWidth: bankWidth, panelHeight: panelHeight)
        }

        // Center game-state messaging inside its panel; keep title and
        // secondary line clear of the border at normal window dimensions.
        let dialogCenterY = h * 0.58
        stagePanel.path = CGPath(
            roundedRect: CGRect(x: -min(260.0, w * 0.25),
                                y: -82, width: 2 * min(260.0, w * 0.25),
                                height: 164),
            cornerWidth: 12, cornerHeight: 12, transform: nil)
        stagePanel.position = point(w / 2, dialogCenterY)
        stagePanel.strokeColor = modernHUD
            ? NSColor(calibratedRed: 0.18, green: 0.85, blue: 0.88, alpha: 0.8)
            : accent.withAlphaComponent(0.55)
        stagePanel.fillColor = modernHUD
            ? NSColor(calibratedRed: 0.006, green: 0.028, blue: 0.045, alpha: 0.88)
            : NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.05, alpha: 0.94)
        stagePanel.isHidden = round == .title || (round == .playing && pendingWave <= 0)
        let levelReady = round == .levelReady
        levelFrame.isHidden = !levelReady
        if levelReady {
            // Angular, glowing wireframe frame encloses the level label.
            // It belongs to the overlay, not the 3-D battlefield, and animates
            // gently without allowing the world simulation to advance.
            let halfWidth = min(285.0, w * 0.31)
            let halfHeight = 96.0
            let cx = w / 2
            let cy = dialogCenterY
            let perimeter = CGMutablePath()
            let corners: [CGPoint] = [
                point(cx - halfWidth + 22, cy + halfHeight),
                point(cx + halfWidth - 22, cy + halfHeight),
                point(cx + halfWidth, cy + halfHeight - 22),
                point(cx + halfWidth, cy - halfHeight + 22),
                point(cx + halfWidth - 22, cy - halfHeight),
                point(cx - halfWidth + 22, cy - halfHeight),
                point(cx - halfWidth, cy - halfHeight + 22),
                point(cx - halfWidth, cy + halfHeight - 22)
            ]
            perimeter.move(to: corners[0])
            for vertex in corners.dropFirst() { perimeter.addLine(to: vertex) }
            perimeter.closeSubpath()
            for side in [-1.0, 1.0] {
                for index in 0..<5 {
                    let x = cx + side * (halfWidth - 28 - Double(index) * 16)
                    segment(perimeter, point(x, cy + halfHeight - 7),
                            point(x + side * 5, cy + halfHeight - 17))
                    segment(perimeter, point(x, cy - halfHeight + 7),
                            point(x + side * 5, cy - halfHeight + 17))
                }
            }
            levelFrame.path = perimeter
            levelFrame.strokeColor = modernHUD
                ? NSColor(calibratedRed: 0.24, green: 0.99, blue: 0.92, alpha: 1)
                : green
            levelFrame.glowWidth = modernHUD ? 7 : 2
            levelFrame.alpha = CGFloat(0.78 + 0.22 * abs(sin(pulse * 2.4)))
        }
        banner.position = point(w / 2, dialogCenterY + 33)
        banner.fontSize = levelReady ? min(49, w * 0.057) : min(38, w * 0.042)
        subtitle.position = point(w / 2,
                                  round == .title ? h * 0.42 : dialogCenterY - 26)
        subtitle.fontSize = modernHUD ? 14 : 15
        switch round {
        case .title:
            banner.text = ""
            subtitle.text = "PRESS RETURN TO DEPLOY"
        case .levelReady:
            banner.text = String(format: "LEVEL %02d", wave)
            subtitle.text = "PRESS ANY KEY TO BEGIN"
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
