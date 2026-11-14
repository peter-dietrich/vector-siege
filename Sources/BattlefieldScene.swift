import SpriteKit
import AppKit
import AVFoundation

private struct Obstacle {
    enum Kind { case block, pyramid, tower, building, monolith }
    var center: GroundPoint
    var size: Double
    var kind: Kind
}

private enum FoeType {
    case tank, hunter, apc, artillery, saucer, drone, fighter
    var isAir: Bool { self == .saucer || self == .drone || self == .fighter }
    var isVehicle: Bool { !isAir }
}
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
    var attackTimer: Double = 0
    var evasiveSeconds = 0.0
    var droneVelocity = GroundPoint(0, 0)
    var droneOffset = GroundPoint(0, 0)
    var droneSeed = 0.0
    var dronePitch = 0.0
    var droneRoll = 0.0
    var droneAltitude = 3.1
    var droneHasCharge = true
    var droneDropDelay = 0.0
    var droneDisrupted = 0.0
    // Air patrol attack limits are per individual fly-through, not per frame.
    var airShotsFired = 0
}
private struct FallingDrone {
    var foe: Foe
    var speed: Double
}


private struct Shell {
    var center: GroundPoint
    var direction: GroundPoint
    var hostile: Bool
    var timeLeft: Double
    var payload: String = "cannon"
    // Transient world elevation. Nil preserves legacy save compatibility
    // and falling bomb behavior.
    var launchElevation: Double? = nil
}

private struct MachineGunRound {
    var center: GroundPoint
    var direction: GroundPoint
    var timeLeft: Double
    var barrel: Int
}
private struct MachineGunRicochet {
    var center: GroundPoint
    var direction: GroundPoint
    var timeLeft: Double
}

private struct Spark {
    var position: WorldPoint
    var velocity: WorldPoint
    var timeLeft: Double
    var maxLife: Double
}

private struct ChaffFlake {
    var position: WorldPoint
    var velocity: WorldPoint
    var timeLeft: Double
    var duration: Double
}

/// Short-lived multi-stage vector events. World-space effects do not alter
/// aim, hit testing, enemy movement, or save-file compatibility.
private struct CombatImpact {
    enum Kind { case ground, structure, armor, aircraft, destruction }
    var position: GroundPoint
    var kind: Kind
    var age: Double = 0
    var duration: Double = 0.9
}
private struct TankWreck {
    var position: GroundPoint
    var heading: Double
    var age: Double = 0
    var duration: Double = 9
}

private enum RoundState { case title, levelReady, playing, paused, gameOver }

// Render-only face; the existing world obstacle geometry still owns collisions.
private struct GlassFace {
    var vertices: [WorldPoint]
    var depth: Double
    var tint: Int
    var solid: Bool = false
}
private struct Vegetation {
    var location: GroundPoint
    var height: Double
    var crown: Double
    var isTree: Bool
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
    private var playerStillSeconds = 0.0
    private var suspension = TankSuspension()
    private lazy var movementAudio = TankMotionAudio()
    private lazy var proximityAudio = TankProximityAudio()
    private var proximityCountdown = 0.0
    private var nearestTankDistance: Double? = nil
    private typealias TargetTrack = (range: Double, error: Double,
                                     position: GroundPoint, ground: Bool,
                                     clearShot: Bool)
    private var targetingCache: TargetTrack? = nil
    private var targetingCacheValid = false
    // v5 cockpit observer: read-only data, never gameplay authority.
    var onCockpitV5Snapshot: ((CockpitV5Snapshot) -> Void)?
    private var cockpitV5Clock = 0.0
    private var approvedCockpit: CockpitV53LiveRenderer?
    private var approvedCockpitMissingAssets = false
    private var steerHoldSeconds: Double = 0
    private var previousSteerDirection: Double = 0
    private var score = 0
    private var wave = 1
    private var lives = 3
    private var bestScore = UserDefaults.standard.integer(forKey: "VectorSiegeHighScore")
    private var shotTally = ShotTally()
    // Two lightweight anti-drone guns, alternating barrels. Cannon remains
    // the only weapon that can penetrate armor or structures.
    private var mgRounds: [MachineGunRound] = []
    private var mgRicochets: [MachineGunRicochet] = []
    private var mgAmmo = 180
    private var mgHeat = 0.0
    private var mgShotCooldown = 0.0
    private var mgOverheatLock = false
    private var mgBarrel = 0
    private var mgHits = 0
    private var mgFired = 0
    private let machineGunLines = SKShapeNode()
    private let machineGunRicochetLines = SKShapeNode()
    private lazy var combatAudio = TankCombatAudio()
    private var muzzleRemaining = 0.0
    private var recoilRemaining = 0.0
    private var screenKickRemaining = 0.0
    private var screenKickStrength = 0.0
    private var incomingBearing = 0.0
    private var damageDirectionRemaining = 0.0
    private var combatImpacts: [CombatImpact] = []
    private var tankWrecks: [TankWreck] = []
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
    private var waveApproach = 0.0
    private var waveOrigin = GroundPoint(0, 0)
    private var waveElapsed = 0.0
    private var directorPressure = 0
    private var directorWaveStartLives = 3
    private var directorWaveStartFired = 0
    private var directorWaveStartHits = 0
    private var hostileShotLimit: Int {
        DynamicBattlefieldDirector.hostileShotLimit(
            wave: wave, pressure: directorPressure)
    }
    private var dronesPending = 0
    private var fightersPending = 0
    private var swarmCenter = GroundPoint(0, 0)
    private var swarmVelocity = GroundPoint(0, 0)
    private var swarmDropTimer = 0.0
    private var droneAttackClock = 0.0
    private var chaffCharges = ChaffDefense.chargesPerWave
    private var chaffCooldown = 0.0
    private var chaffActive = 0.0
    private var fallingDrones: [FallingDrone] = []
    private var chaffFlakes: [ChaffFlake] = []
    private var hitFlashRemaining = 0.0
    private var destructionRemaining = 0.0
    private var obstacles: [Obstacle] = []
    private var vegetation: [Vegetation] = []
    private var solidBuildingIndices: Set<Int> = []
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
    private let groundMesh = SKShapeNode()
    private let streetMarks = SKShapeNode()
    private let structures = SKShapeNode()
    private let foliageLines = SKShapeNode()
    private let opponentLines = SKShapeNode()
    private let opponentSaucerLines = SKShapeNode()
    private let shotLines = SKShapeNode()
    private let modernFriendlyShells = SKShapeNode()
    private let modernHostileShells = SKShapeNode()
    private let modernBombShells = SKShapeNode()
    private let saucerPulseLines = SKShapeNode()
    private let flashLines = SKShapeNode()
    private let damageOverlay = SKShapeNode()
    private let destructionRings = SKShapeNode()
    private let combatWorldEffects = SKShapeNode()
    private let combatWrecks = SKShapeNode()
    private let muzzleEffects = SKShapeNode()
    private let directionalDamageEffects = SKShapeNode()
    private let droneLines = SKShapeNode()
    private let fighterLines = SKShapeNode()
    private let armoredLines = SKShapeNode()
    private let countermeasureLines = SKShapeNode()
    private let chaffCloudLines = SKShapeNode()
    private let reticle = SKShapeNode()
    private let shieldBorder = SKShapeNode()
    private let shieldNotice = SKLabelNode(fontNamed: "Menlo-Bold")
    private let radar = SKShapeNode()
    private let radarSweepBeam = SKShapeNode()
    private let radarSweepGlow = (0..<24).map { _ in SKShapeNode() }
    private let radarCompassLabels = (0..<4).map { _ in SKLabelNode(fontNamed: "Menlo-Bold") }
    private let radarPanel = SKShapeNode()
    private let rearPanel = SKShapeNode()
    // Prebaked material textures: rendered once, never each simulation frame.
    // These are physical screen surfaces; live labels/contacts stay SpriteKit.
    private lazy var consoleTexture = Self.makeConsoleTexture()
    private lazy var opticsTexture = Self.makeOpticsTexture()
    private lazy var monitorMaterials = (0..<4).map { _ in
        SKSpriteNode(texture: consoleTexture)
    }
    private lazy var bottomMaterial = SKSpriteNode(texture: consoleTexture)
    private lazy var rearOpticsMaterial = SKSpriteNode(texture: opticsTexture)
    private let opticsGlass = SKShapeNode()
    private let opticsCaption = SKLabelNode(fontNamed: "Menlo-Bold")
    private let radarGroundShading = SKShapeNode()
    private let radarTargetLine = SKShapeNode()
    private let lowerTerrainFill = SKShapeNode()
    private let lowerTankFill = SKShapeNode()
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
    private let proximityWings = SKShapeNode()
    private let radarObstacleContacts = SKShapeNode()
    private let radarStreetGrid = SKShapeNode()
    private let radarProjectileGlow = SKShapeNode()
    private let radarProjectileCore = SKShapeNode()
    private let radarEnemyContacts = SKShapeNode()
    private let radarHunterContacts = SKShapeNode()
    private let radarSaucerContacts = SKShapeNode()
    private let radarDroneContacts = SKShapeNode()
    private let radarActiveDrones = SKShapeNode()
    private let radarTargetCue = SKShapeNode()
    private let radarFighterContacts = SKShapeNode()
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
    private let modernUpperBands = SKShapeNode()
    private let modernUpperDividers = SKShapeNode()
    private let modernUpperIcons = SKShapeNode()
    private let modernOrangeCorners = SKShapeNode()

    // Modern-mode cockpit treatment. Separate decoration and text nodes make
    // every value live and keep Classic independent of the premium layout.
    private let modernCockpit = SKNode()
    // v4.0: all four existing live modules share one relocated instrument
    // deck, framed as three larger hardware zones (weapons, battlespace,
    // vehicle). Classic mode uses the original coordinates, unchanged.
    private let commandDeck = SKNode()
    private let commandShellBack = SKShapeNode()
    private let commandShellBezel = SKShapeNode()
    private let commandShellShadow = SKShapeNode()
    private let commandShellEdges = SKShapeNode()
    private let commandShellHighlights = SKShapeNode()
    private let commandShellHardware = SKShapeNode()
    private let commandShellAlert = SKShapeNode()
    private let commandShellLabels = (0..<8).map {
        _ in SKLabelNode(fontNamed: "Menlo-Bold")
    }
    private let modernTrim = SKShapeNode()
    private let modernLowerDash = SKShapeNode()
    private let modernCompassPlate = SKShapeNode()
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
        for (node, layer) in [(radarEnemyContacts, 13.3), (radarHunterContacts, 13.4),
                               (radarSaucerContacts, 13.45), (radarDroneContacts, 13.47),
                               (radarActiveDrones, 13.50), (radarTargetCue, 13.55),
                               (radarFighterContacts, 13.49), (radarProjectileGlow, 13.6),
                               (radarProjectileCore, 13.8)] {
            node.zPosition = layer
            addChild(node)
        }
        radarSweepBeam.zPosition = 13.15
        radarSweepBeam.fillColor = .clear
        radarSweepBeam.lineWidth = 1.65
        addChild(radarSweepBeam)
        for wedge in radarSweepGlow {
            wedge.zPosition = 12.9
            wedge.strokeColor = .clear
            wedge.lineWidth = 0
            addChild(wedge)
        }
        for label in radarCompassLabels {
            label.zPosition = 13.7
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .center
            label.fontSize = 11
            addChild(label)
        }

        for (layer, z) in [
            (farSkyline, 1.0), (skyline, 2.0), (ground, 3.0),
            (groundMesh, 3.1), (streetMarks, 3.2), (foliageLines, 3.9), (structures, 4.0),
            (opponentLines, 5.0), (opponentSaucerLines, 5.1), (shotLines, 6.0),
            (modernFriendlyShells, 6.2), (modernHostileShells, 6.3),
            (modernBombShells, 6.4), (saucerPulseLines, 6.5),
            (machineGunLines, 6.7), (machineGunRicochetLines, 6.8),
            (flashLines, 7.0), (armoredLines, 5.3),
            (droneLines, 5.4), (fighterLines, 5.5),
            (chaffCloudLines, 7.8), (countermeasureLines, 8.6),
            (destructionRings, 9.0),
            (damageOverlay, 9.3), (combatWorldEffects, 7.25),
            (combatWrecks, 4.8), (muzzleEffects, 9.6),
            (directionalDamageEffects, 10.3), (proximityWings, 15.9),
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
        rearOpticsMaterial.zPosition = -1.0
        rearView.addChild(rearOpticsMaterial)
        opticsGlass.zPosition = 5.0
        opticsGlass.fillColor = .clear
        opticsGlass.lineCap = .round
        rearView.addChild(opticsGlass)
        opticsCaption.zPosition = 5.1
        opticsCaption.fontSize = 9
        opticsCaption.horizontalAlignmentMode = .left
        opticsCaption.verticalAlignmentMode = .center
        rearView.addChild(opticsCaption)
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
        damageOverlay.strokeColor = .clear
        damageOverlay.fillColor = .clear
        destructionRings.strokeColor = .clear
        countermeasureLines.strokeColor = .clear
        proximityWings.fillColor = .clear
        radarStreetGrid.zPosition = 12.8
        addChild(radarStreetGrid)
        radarGroundShading.zPosition = 12.65
        radarGroundShading.strokeColor = .clear
        addChild(radarGroundShading)
        radarObstacleContacts.zPosition = 13.1
        addChild(radarObstacleContacts)
        radarTargetLine.zPosition = 13.52
        radarTargetLine.fillColor = .clear
        addChild(radarTargetLine)
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
            (modernUpperBands, 11.4), (modernUpperDividers, 12.7),
            (modernUpperIcons, 14.0), (modernOrangeCorners, 12.9)
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
        bottomMaterial.zPosition = 0.15
        modernCockpit.addChild(bottomMaterial)
        lowerTerrainFill.zPosition = 1.2
        lowerTerrainFill.strokeColor = .clear
        modernCockpit.addChild(lowerTerrainFill)
        lowerTankFill.zPosition = 1.2
        lowerTankFill.strokeColor = .clear
        modernCockpit.addChild(lowerTankFill)
        for (node, z) in [(modernTrim, 0.6), (modernLowerDash, 0.0),
                          (modernCompassPlate, 0.5), (modernLowerLines, 0.7), (modernTankIcon, 1.4),
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
        // Reparent once after every label, shape and rear-camera mask has
        // been installed. Radar, the moving sweep and rear optical camera
        // now translate together, avoiding per-node coordinate rewriting.
        commandDeck.zPosition = 0
        addChild(commandDeck)
        let moduleNodes: [SKNode] = [
            telemetryLeftPanel, telemetryRightPanel,
            radarPanel, rearPanel, rearView, rearLabel,
            telemetryLeftAccent, telemetryRightAccent,
            radar, radarStreetGrid, radarGroundShading,
            radarObstacleContacts, radarTargetLine,
            radarSweepBeam, radarEnemyContacts, radarHunterContacts,
            radarSaucerContacts, radarDroneContacts, radarActiveDrones,
            radarTargetCue, radarFighterContacts,
            radarProjectileGlow, radarProjectileCore,
            modernUpperBands, modernUpperDividers,
            modernUpperIcons, modernOrangeCorners,
            leftHUD, midHUD, rightHUD,
            telemetryLeftHeading, telemetryRightHeading,
            telemetryLeftDetail, telemetryLeftFootnote,
            telemetryCoordinates, telemetryRightDetail,
            telemetryRightFootnote, telemetryAmmo
        ]
        for surface in monitorMaterials {
            surface.zPosition = 11.18
            commandDeck.addChild(surface)
        }
        for node in moduleNodes +
            radarSweepGlow.map({ $0 as SKNode }) +
            radarCompassLabels.map({ $0 as SKNode }) +
            modernUpperText.map({ $0 as SKNode }) {
            node.removeFromParent()
            commandDeck.addChild(node)
        }
        commandShellBack.zPosition = 10.35
        commandShellShadow.zPosition = 10.42
        commandShellBezel.zPosition = 10.50
        commandShellEdges.zPosition = 16.1
        commandShellHighlights.zPosition = 16.2
        commandShellHardware.zPosition = 16.3
        commandShellAlert.zPosition = 16.4
        for shape in [commandShellBack, commandShellShadow,
                      commandShellBezel, commandShellEdges,
                      commandShellHighlights, commandShellHardware,
                      commandShellAlert] {
            shape.lineCap = .round
            shape.lineJoin = .round
            addChild(shape)
        }
        for label in commandShellLabels {
            label.zPosition = 16.6
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .left
            addChild(label)
        }
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
            switch displayMode {
            case .classic: displayMode = .modern
            case .modern: displayMode = .cockpitV53
            case .cockpitV53: displayMode = .classic
            }
        case 17: // T: show extra local diagnostic details
            showDetailedTelemetry.toggle()
        case 14: // E: defensive chaff/ECM countermeasure pulse
            launchChaff()
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
        mgRounds.removeAll()
        mgRicochets.removeAll()
        mgAmmo = 180
        mgHeat = 0
        mgShotCooldown = 0
        mgOverheatLock = false
        mgBarrel = 0
        mgHits = 0
        mgFired = 0
        combatImpacts.removeAll()
        tankWrecks.removeAll()
        muzzleRemaining = 0
        recoilRemaining = 0
        screenKickRemaining = 0
        damageDirectionRemaining = 0
        observedFPS = 60
        nearestTankDistance = nil
        proximityCountdown = 0
        driveSpeed = 0
        turnMotion = 0
        playerStillSeconds = 0
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
        directorPressure = 0
        directorWaveStartLives = lives
        directorWaveStartFired = shotTally.fired
        directorWaveStartHits = shotTally.hits
        waveElapsed = 0
        dronesPending = 0
        fightersPending = 0
        chaffCharges = ChaffDefense.chargesPerWave
        chaffCooldown = 0
        chaffActive = 0
        chaffFlakes.removeAll()
        droneAttackClock = 0
        hitFlashRemaining = 0
        destructionRemaining = 0
        shells.removeAll()
        sparks.removeAll()
        makeObstacles()
        makeVegetation()
        selectSolidBuildings()
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
        // Damage feedback continues after the final life has ended, instead
        // of freezing sparks and the blast on the game-over frame.
        hitFlashRemaining = max(0, hitFlashRemaining - dt)
        destructionRemaining = max(0, destructionRemaining - dt)
        muzzleRemaining = max(0, muzzleRemaining - dt)
        recoilRemaining = max(0, recoilRemaining - dt)
        screenKickRemaining = max(0, screenKickRemaining - dt)
        damageDirectionRemaining = max(0, damageDirectionRemaining - dt)
        for index in combatImpacts.indices { combatImpacts[index].age += dt }
        combatImpacts.removeAll { $0.age >= $0.duration }
        for index in tankWrecks.indices { tankWrecks[index].age += dt }
        tankWrecks.removeAll { $0.age >= $0.duration }
        if round == .gameOver {
            updateSparks(dt)
        }
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
                .filter { $0.kind.isVehicle }
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
        cockpitV5Clock += dt
        if cockpitV5Clock >= 0.1 {
            cockpitV5Clock = 0
            if onCockpitV5Snapshot != nil || approvedCockpit != nil {
                let snapshot = makeCockpitV5Snapshot()
                onCockpitV5Snapshot?(snapshot)
                if displayMode == .cockpitV53 {
                    approvedCockpit?.update(
                        snapshot, clock: gameClock,
                        buildings: obstacles.map {
                            CockpitV53LiveRenderer.MapBuilding(
                                x: $0.center.x, z: $0.center.z,
                                size: $0.size,
                                isSolid: $0.kind == .building || $0.kind == .block)
                        }, mgAmmo: mgAmmo, mgHeat: mgHeat,
                        mgLocked: mgOverheatLock)
                }
            }
        }
    }

    private func tick(_ dt: Double) {
        if saucerPatrol.advance(by: dt) && rules.saucersEnabled { spawnPatrolSaucer() }
        cannon.advance(by: dt)
        shieldCooldown = max(0, shieldCooldown - dt)
        shieldDuration = max(0, shieldDuration - dt)
        chaffCooldown = max(0, chaffCooldown - dt)
        chaffActive = max(0, chaffActive - dt)
        updateChaffCloud(dt)
        swarmDropTimer = max(0, swarmDropTimer - dt)
        waveElapsed += dt
        if enemies.contains(where: { $0.kind == .drone }) {
            droneAttackClock += dt
        }
        // Reinforcements emerge from the same approach quadrant as the
        // ground force. They are delayed so wave starts remain readable.
        if dronesPending > 0 &&
            waveElapsed >= DynamicBattlefieldDirector.reinforcementDelay(
                base: BattlefieldWaveDirector.droneDelay(forWave: wave),
                pressure: directorPressure) &&
            AirEncounterDirector.mayLaunchAirThreat(
                groundRemaining: enemies.filter { $0.kind.isVehicle }.count,
                simultaneousHostileShots: shells.filter { $0.hostile }.count,
                currentAirCount: enemies.filter { $0.kind.isAir }.count,
                maxHostileShots: hostileShotLimit) {
            deployAirWing(kind: .drone, count: dronesPending)
            dronesPending = 0
        }
        if fightersPending > 0 &&
            waveElapsed >= DynamicBattlefieldDirector.reinforcementDelay(
                base: BattlefieldWaveDirector.fighterDelay(forWave: wave),
                pressure: directorPressure) &&
            AirEncounterDirector.mayLaunchAirThreat(
                groundRemaining: enemies.filter { $0.kind.isVehicle }.count,
                simultaneousHostileShots: shells.filter { $0.hostile }.count,
                currentAirCount: enemies.filter { $0.kind.isAir }.count,
                maxHostileShots: hostileShotLimit) {
            deployAirWing(kind: .fighter, count: fightersPending)
            fightersPending = 0
        }
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
        playerStillSeconds = abs(driveSpeed) < 0.9
            ? min(18, playerStillSeconds + dt)
            : max(0, playerStillSeconds - dt * 4)
        turnMotion += (abs(turn) - turnMotion) * min(1, dt * 12)
        if key(49) && cannon.canFire {
            firePlayer()
        }
        mgShotCooldown = max(0, mgShotCooldown - dt)
        mgHeat = max(0, mgHeat - dt * 14)
        if mgOverheatLock && mgHeat < 32 { mgOverheatLock = false }
        if key(3) { fireMachineGun() } // F: twin coaxial anti-drone guns
        advanceMachineGun(dt)

        // Every ground vehicle uses the same immutable collision map this
        // frame. Do not rebuild an 80+ building navigation array per tank.
        let navigationBodies = obstacles.map {
            NavigationObstacle(body: collisionBody(for: $0))
        }
        // Cohesive cloud: approach the player but remain at a playable standoff.
        if enemies.contains(where: { $0.kind == .drone }) {
            let target = tankPosition - facing(waveApproach) * 42
            let desired = (target - swarmCenter).normalized * 5.8
            swarmVelocity = swarmVelocity +
                (desired - swarmVelocity) * min(1, dt * 0.65)
            swarmCenter = swarmCenter + swarmVelocity * dt
        }
        for idx in enemies.indices {
            let diff = tankPosition - enemies[idx].center
            let distance = max(0.001, diff.length)
            enemies[idx].reload -= dt
            enemies[idx].phase += dt
            enemies[idx].evasiveSeconds = max(0, enemies[idx].evasiveSeconds - dt)
            let type = enemies[idx].kind
            // Flying disks travel slowly to preserve their ominous, floating
            // appearance. Their visual rotation speed is independent.
            let baseMovement: Double
            switch type {
            case .saucer: baseMovement = EnemyMotion.saucerBaseSpeed
            case .drone: baseMovement = 6.7
            case .fighter: baseMovement = 12.0
            case .hunter: baseMovement = 4.6
            case .apc: baseMovement = 3.3
            case .artillery: baseMovement = 1.9
            case .tank: baseMovement = 2.55
            }
            let movement = baseMovement * threatLevel.enemyVelocity * rules.enemySpeed
            let aim = atan2(diff.x, diff.z)
            if type == .saucer {
                enemies[idx].center = enemies[idx].center +
                    facing(enemies[idx].heading) * movement * dt
                enemies[idx].attackTimer += dt
            } else if type == .drone {
                var drone = enemies[idx]
                drone.droneDisrupted = max(0, drone.droneDisrupted - dt)
                let phase = drone.phase + drone.droneSeed
                // Independent long-period motion keeps the wider cloud organic.
                let wander = GroundPoint(
                    sin(phase * 0.67) * 4.8 + sin(phase * 1.31) * 1.8,
                    cos(phase * 0.53) * 4.5 + cos(phase * 1.17) * 1.9)
                let droneIndex = max(0, Int((drone.droneSeed / 1.618).rounded()))
                let attackRun = AirEncounterDirector.isAttacking(
                    droneIndex: droneIndex, elapsed: droneAttackClock) &&
                    drone.droneHasCharge && drone.droneDisrupted <= 0
                // A wing of six makes a recognizable inward run and then
                // naturally returns to its broad standoff formation.
                let raidTarget = tankPosition -
                    facing(waveApproach) * 17 +
                    drone.droneOffset * 0.24 + wander * 0.38
                let desiredPosition = attackRun ? raidTarget :
                    swarmCenter + drone.droneOffset + wander
                var separation = GroundPoint(0, 0)
                for other in enemies.indices where other != idx &&
                    enemies[other].kind == .drone {
                    let away = drone.center - enemies[other].center
                    let range = away.length
                    if range > 0.001 && range < 6.5 {
                        separation = separation + away.normalized * ((6.5 - range) / 6.5)
                    }
                }
                let speedFactor = 1.0 + 0.18 * sin(phase * 0.47) +
                    0.08 * sin(phase * 1.06)
                let disrupted = drone.droneDisrupted > 0
                let scatter = disrupted ? GroundPoint(
                    sin(drone.droneSeed * 3.1 + gameClock * 1.8),
                    cos(drone.droneSeed * 2.3 + gameClock * 1.9)) * 14
                    : GroundPoint(0, 0)
                let steering = (desiredPosition - drone.center) *
                    (disrupted ? 0.10 : attackRun ? 0.84 : 0.70) +
                    swarmVelocity + separation * 7 + scatter
                let speedTarget = min(attackRun ? 12.0 : 10.5,
                                      max(2.0, steering.length * speedFactor))
                let desiredVelocity = steering.normalized * speedTarget
                let previousVelocity = drone.droneVelocity
                var change = desiredVelocity - previousVelocity
                if change.length > 11 * dt {
                    change = change.normalized * (11 * dt)
                }
                drone.droneVelocity = previousVelocity + change
                let next = drone.center + drone.droneVelocity * dt
                drone.center = GroundPoint(
                    max(-176, min(176, next.x)),
                    max(-176, min(176, next.z)))
                let speed = drone.droneVelocity.length
                if speed > 0.15 {
                    let desiredHeading = atan2(
                        drone.droneVelocity.x, drone.droneVelocity.z)
                    drone.heading = wrapAngle(drone.heading +
                        wrapAngle(desiredHeading - drone.heading) * min(1, dt * 4))
                }
                let acceleration = (drone.droneVelocity - previousVelocity) *
                    (1 / max(0.001, dt))
                let forward = facing(drone.heading)
                let right = GroundPoint(forward.z, -forward.x)
                let forwardAccel = acceleration.x * forward.x +
                    acceleration.z * forward.z
                let lateralAccel = acceleration.x * right.x +
                    acceleration.z * right.z
                let pitchTarget = max(-0.44, min(0.26,
                    -0.035 * forwardAccel - 0.009 * speed))
                let rollTarget = max(-0.24, min(0.24, -0.031 * lateralAccel))
                drone.dronePitch += (pitchTarget - drone.dronePitch) *
                    min(1, dt * 6.5)
                drone.droneRoll += (rollTarget +
                    (disrupted ? 0.38 * sin(gameClock * 14 + drone.droneSeed) : 0) -
                    drone.droneRoll) * min(1, dt * 5)
                // Distinct height bands with continuous individual bobbing.
                // Never place rotors beneath the terrain.
                let altitudeBand = 2.3 + Double(idx % 6) * 0.48
                drone.droneAltitude = altitudeBand +
                    0.38 * sin(phase * 1.18) +
                    0.16 * sin(phase * 2.16)
                drone.droneDropDelay = max(0, drone.droneDropDelay - dt)
                let activeCharges = shells.filter {
                    $0.hostile && $0.payload == "droneCharge"
                }.count
                let hostileCount = shells.filter { $0.hostile }.count
                if pendingWave <= 0 &&
                    attackRun && drone.droneHasCharge && !disrupted &&
                    drone.droneDropDelay <= 0 &&
                    swarmDropTimer <= 0 && chaffActive <= 0 &&
                    distance < 78 && distance > 12 &&
                    activeCharges < 2 &&
                    hostileCount < hostileShotLimit {
                    let direction = (tankPosition - drone.center).normalized
                    shells.append(Shell(
                        center: drone.center + direction * 1.4,
                        direction: direction, hostile: true,
                        timeLeft: 5.5, payload: "droneCharge"))
                    drone.droneHasCharge = false
                    swarmDropTimer = Double.random(in: 1.7...2.4)
                    burst(at: WorldPoint(drone.center, height: drone.droneAltitude - 0.7),
                          count: 5)
                    sound("enemy.wav")
                }
                enemies[idx] = drone
            } else if type == .fighter {
                // A single recognizable strafing pass: travel across the
                // battlefield at constant heading rather than homing or orbiting.
                enemies[idx].center = enemies[idx].center +
                    facing(enemies[idx].heading) * max(14, movement) * dt
                enemies[idx].attackTimer += dt
            } else {
                let obstaclesForNavigation = navigationBodies
                let shotBlockers = navigationBodies
                let occupied = enemies.indices
                    .filter { $0 != idx && enemies[$0].kind.isVehicle }
                    .map { enemies[$0].center }
                let clearShot = EnemyNavigation.clearSegment(
                    enemies[idx].center, tankPosition, obstacles: shotBlockers,
                    height: 1.5) &&
                    LandscapeTopology.clearFiringLine(
                        from: enemies[idx].center, to: tankPosition)
                let desiredDistance = type == .hunter ? 19.0 :
                    (type == .artillery ? 48.0 : 24.0)

                // Replan if the target moves, cover blocks the shot, or the
                // previous waypoint was reached. Stagger work across frames.
                enemies[idx].routeRefreshRemaining -= dt
                if enemies[idx].routeRefreshRemaining <= 0 ||
                    (enemies[idx].navigationWaypoint?.distance(
                        to: enemies[idx].center) ?? .infinity) < 4 {
                    // One in three vehicles seeks a flank if the player
                    // camps. Others briefly change lanes under cannon fire.
                    let evasive = enemies[idx].evasiveSeconds > 0
                    let flank = CombatBalance.shouldFlank(
                        stillSeconds: playerStillSeconds, index: idx,
                        wave: wave, distance: distance)
                    let shouldMove = !clearShot ||
                        distance > desiredDistance + 7 || evasive || flank
                    let lateral = facing(heading + .pi / 2) *
                        ((idx % 2 == 0 ? 1.0 : -1.0) *
                         (evasive ? 25.0 : 18.0))
                    let tacticalGoal = (evasive || flank) &&
                        distance < 95 ? tankPosition + lateral : tankPosition
                    enemies[idx].navigationWaypoint = shouldMove
                        ? EnemyNavigation.nextWaypoint(
                            from: enemies[idx].center, player: tacticalGoal,
                            obstacles: obstaclesForNavigation,
                            shotBlockers: shotBlockers, otherTanks: occupied,
                            desiredStandOff: desiredDistance,
                            terrainAware: true)
                        : nil
                    enemies[idx].routeRefreshRemaining =
                        CombatBalance.routeRefreshDelay(index: idx,
                            recentlyBlocked: false)
                }

                // When a tank is already in range and has a clear line of
                // fire, face the player. Otherwise turn toward a waypoint
                // around buildings, keeping a safe distance from other tanks.
                let destination = enemies[idx].navigationWaypoint
                let shouldAdvance = destination != nil &&
                    (!clearShot || distance > desiredDistance + 6 ||
                     enemies[idx].evasiveSeconds > 0 ||
                     CombatBalance.shouldFlank(
                        stillSeconds: playerStillSeconds, index: idx,
                        wave: wave, distance: distance))
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
                        enemies[idx].routeRefreshRemaining =
                            CombatBalance.routeRefreshDelay(index: idx,
                                recentlyBlocked: true)
                    }
                }
            }
            let targetVisible = !type.isVehicle || (
                EnemyNavigation.clearSegment(
                    enemies[idx].center, tankPosition,
                    obstacles: navigationBodies, height: 1.5) &&
                LandscapeTopology.clearFiringLine(
                    from: enemies[idx].center, to: tankPosition))
            let hostileShots = shells.filter { $0.hostile }.count
            let forwardVector = facing(enemies[idx].heading)
            let forwardDot = diff.normalized.x * forwardVector.x +
                diff.normalized.z * forwardVector.z
            let fighterPass = type == .fighter &&
                enemies[idx].attackTimer < 13 &&
                enemies[idx].airShotsFired < 2 &&
                forwardDot > 0.30 && distance < 95
            let saucerPass = type == .saucer && wave >= 4 &&
                enemies[idx].attackTimer < 15 &&
                enemies[idx].airShotsFired == 0 &&
                forwardDot > 0.50 && distance < 85
            if pendingWave <= 0 && type != .drone &&
                (type != .fighter || fighterPass) &&
                (type != .saucer || saucerPass) &&
                enemies[idx].reload <= 0 && targetVisible &&
                hostileShots < hostileShotLimit &&
                distance < (type == .fighter ? 125 : 79) && distance > 9 &&
                (type != .fighter || chaffActive <= 0) {
                let errorScale = type == .fighter ? 1.7 :
                                 (type == .artillery ? 1.5 : 1.0)
                let aimError = threatLevel.enemyAimError /
                    rules.enemyAccuracy * errorScale
                let error = Double.random(in: -aimError...aimError)
                let direction = facing(aim + error)
                let explosive = type == .artillery ||
                    (type == .fighter && enemies[idx].airShotsFired == 1)
                let payload = type == .saucer ? "saucerPulse" :
                    explosive ? "bomb" :
                    (type == .fighter || type == .apc ? "machinegun" : "cannon")
                let requested = payload == "machinegun" ? 2 : 1
                let count = CombatBalance.permittedVolley(
                    requested: requested, alreadyHostile: hostileShots,
                    maximumHostile: hostileShotLimit)
                for burstIndex in 0..<count {
                    let scatter = Double(burstIndex) * 0.055
                    let flight = facing(aim + error + scatter)
                    shells.append(Shell(
                        center: enemies[idx].center + flight * 3,
                        direction: flight, hostile: true,
                        timeLeft: payload == "bomb" ? 7.2 :
                            payload == "saucerPulse" ? 7.0 : 4.0,
                        payload: payload,
                        launchElevation: type.isVehicle && payload != "bomb"
                            ? LandscapeTopology.height(enemies[idx].center) : nil))
                }
                enemies[idx].reload = (type == .fighter ? 5.8 :
                    type == .saucer ? 999.0 :
                    type == .artillery ? 5.7 : 3.5) *
                    threatLevel.enemyReload / rules.enemyReload *
                    DynamicBattlefieldDirector.fireCooldownFactor(
                        pressure: directorPressure)
                if type.isAir { enemies[idx].airShotsFired += 1 }
                sound("enemy.wav")
            }
        }
        var survivingShells: [Shell] = []
        var casualties = Set<Int>()
        for var shell in shells {
            let old = shell.center
            let shellSpeed = !shell.hostile ? 90.0 :
                (shell.payload == "bomb" || shell.payload == "droneCharge" ? 22.0 :
                    shell.payload == "saucerPulse" ? 16.0 :
                    shell.payload == "machinegun" ? 34.0 : 23.0)
            shell.center = shell.center + shell.direction * (dt * shellSpeed)
            shell.timeLeft -= dt
            if shell.timeLeft <= 0 {
                if !shell.hostile {
                    shotTally.miss()
                    // End-of-range rounds disturb the ground rather than
                    // vanishing silently, without manufacturing a target hit.
                    registerImpact(at: shell.center, kind: .ground)
                    burst(at: WorldPoint(shell.center, height: 0.3), count: 12)
                }
                continue
            }

            // Continuous swept collisions, ordered by first contact along
            // the actual projectile travel segment. A wall behind a target
            // must not absorb a shot that hits the tank first.
            let height = shell.hostile ? 1.5 : 1.65
            let worldAltitude = shell.launchElevation.map { $0 + height }
            let wallTime = firstObstacleImpact(
                from: old, to: shell.center, height: height,
                worldAltitude: worldAltitude)
            let terrainTime = worldAltitude.flatMap {
                LandscapeTopology.firstTerrainImpact(
                    from: old, to: shell.center, altitude: $0)
            }
            var targetTime: Double?
            var targetIndex: Int?
            if shell.hostile {
                targetTime = ObstacleCollision.firstCircleImpact(
                    from: old, to: shell.center, center: tankPosition,
                    radius: shell.payload == "bomb" ? 5.0 :
                        shell.payload == "droneCharge" ? 2.7 : 2.0)
            } else {
                for idx in enemies.indices where !casualties.contains(idx) {
                    let radius: Double
                    switch enemies[idx].kind {
                    case .fighter: radius = 5.5
                    case .drone: radius = 1.8
                    case .saucer: radius = 3.1
                    case .artillery: radius = 3.3
                    default: radius = 2.9
                    }
                    if let hit = ObstacleCollision.firstCircleImpact(
                        from: old, to: shell.center,
                        center: enemies[idx].center, radius: radius),
                        hit < (targetTime ?? .infinity) {
                        targetTime = hit
                        targetIndex = idx
                    }
                }
            }

            if let terrain = terrainTime,
                terrain <= (wallTime ?? .infinity) &&
                terrain <= (targetTime ?? .infinity) {
                let impact = old + (shell.center - old) * terrain
                if !shell.hostile { shotTally.miss() }
                burst(at: WorldPoint(impact, height: 0.25), count: 18)
                registerImpact(at: impact, kind: .ground)
                combatAudio.play(.impact, enabled: soundOn)
                continue
            }
            if let wall = wallTime, wall <= (targetTime ?? .infinity) {
                let impact = old + (shell.center - old) * wall
                if !shell.hostile { shotTally.miss() }
                burst(at: WorldPoint(impact, height: height),
                      count: shell.hostile ? 11 : 23)
                registerImpact(at: impact, kind: .structure)
                if !shell.hostile { combatAudio.play(.impact, enabled: soundOn) }
                else { sound("impact.wav") }
                continue
            }
            if let hit = targetTime {
                let impact = old + (shell.center - old) * hit
                if shell.hostile {
                    burst(at: WorldPoint(impact, height: height),
                          count: shell.payload == "bomb" ? 55 :
                            shell.payload == "droneCharge" ? 20 : 24)
                    if shieldDuration <= 0 && invulnerability <= 0 {
                        takeDamage(from: shell.center - tankPosition)
                    } else {
                        registerImpact(at: impact, kind: .armor)
                        sound("impact.wav")
                    }
                } else if let idx = targetIndex {
                    shotTally.hit()
                    enemies[idx].hitPoints -= 1
                    let impactHeight = enemies[idx].kind.isAir
                        ? (enemies[idx].kind == .fighter ? 4.0 :
                            enemies[idx].kind == .drone ? enemies[idx].droneAltitude : 2.8) : 1.45
                    let killed = enemies[idx].hitPoints <= 0
                    let kind: CombatImpact.Kind = enemies[idx].kind.isAir
                        ? .aircraft : .armor
                    burst(at: WorldPoint(impact, height: impactHeight),
                          count: enemies[idx].kind == .drone ? 9 :
                            (killed ? 55 : 26))
                    registerImpact(at: impact, kind: killed && enemies[idx].kind.isVehicle
                        ? .destruction : kind)
                    if killed {
                        casualties.insert(idx)
                        let points: Int
                        switch enemies[idx].kind {
                        case .drone: points = 225
                        case .fighter: points = 2200
                        case .artillery: points = 1650
                        case .apc: points = 850
                        case .hunter: points = 1500
                        case .saucer: points = 250
                        case .tank: points = 1000
                        }
                        addPoints(points)
                        if enemies[idx].kind.isVehicle {
                            tankWrecks.append(TankWreck(position: enemies[idx].center,
                                                        heading: enemies[idx].heading))
                            if tankWrecks.count > 10 { tankWrecks.removeFirst() }
                            // Primary armor burst and secondary debris bloom.
                            burst(at: WorldPoint(enemies[idx].center, height: 2.4), count: 46)
                            combatAudio.play(.explosion, enabled: soundOn)
                        } else {
                            sound(enemies[idx].kind == .drone
                                ? "impact.wav" : "explosion.wav")
                        }
                    } else {
                        combatAudio.play(.impact, enabled: soundOn)
                    }
                }
                continue
            }
            survivingShells.append(shell)
        }
        shells = survivingShells
        for idx in casualties.sorted(by: >) {
            if enemies[idx].kind == .drone {
                fallingDrones.append(FallingDrone(foe: enemies[idx], speed: 0.5))
            }
            enemies.remove(at: idx)
        }
        enemies.removeAll {
            (($0.kind == .saucer &&
              $0.attackTimer > AirEncounterDirector.saucerLifetime) ||
             ($0.kind == .fighter &&
              $0.attackTimer > AirEncounterDirector.fighterLifetime)) ||
            ($0.kind.isAir && $0.kind != .drone &&
             (abs($0.center.x) > 190 || abs($0.center.z) > 190))
        }
        updateFallingDrones(dt)
        updateSparks(dt)
        // Air contacts and pending reinforcements never block level progression.
        if !enemies.contains(where: { $0.kind.isVehicle }) &&
            pendingWave <= 0 {
            pendingWave = 2.1
            // Once the ground is secure, no stray air attack can steal
            // a life during the victory countdown.
            invulnerability = max(invulnerability, 3.1)
            shells.removeAll { $0.hostile }
        }
        if pendingWave > 0 {
            pendingWave -= dt
            if pendingWave <= 0 {
                let shotsThisWave = max(0, shotTally.fired - directorWaveStartFired)
                let hitsThisWave = max(0, shotTally.hits - directorWaveStartHits)
                let hitRate = shotsThisWave > 0
                    ? 100.0 * Double(hitsThisWave) / Double(shotsThisWave) : 0
                directorPressure = DynamicBattlefieldDirector.nextPressure(
                    current: directorPressure, waveSeconds: waveElapsed,
                    livesLost: max(0, directorWaveStartLives - lives),
                    hitRate: hitRate, wave: wave)
                // Every level starts with a completely full magazine and
                // no leftover per-shot reload timer, even in custom presets.
                cannon.rearmForNextLevel()
                mgAmmo = 180
                mgHeat = 0
                mgOverheatLock = false
                mgShotCooldown = 0
                mgRounds.removeAll()
                mgRicochets.removeAll()
                wave += 1
                spawnWave()
                for shell in shells where !shell.hostile { shotTally.miss() }
                shells.removeAll()
                fallingDrones.removeAll()
                shieldCooldown = 0
                chaffCharges = ChaffDefense.chargesPerWave
                chaffCooldown = 0
                chaffActive = 0
                chaffFlakes.removeAll()
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

    /// The visual structure and the physical collision volume use the exact
    /// same dimensions. Every gameplay system queries this one profile.
    private func collisionBody(for obstacle: Obstacle) -> ObstacleCollision.Body {
        let kind: ObstacleCollision.Kind
        switch obstacle.kind {
        case .block: kind = .block
        case .pyramid: kind = .pyramid
        case .tower: kind = .tower
        case .building: kind = .building
        case .monolith: kind = .monolith
        }
        return ObstacleCollision.body(
            center: obstacle.center, size: obstacle.size, kind: kind)
    }

    private func blocked(_ p: GroundPoint, radius: Double) -> Bool {
        if abs(p.x) > 190 || abs(p.z) > 190 { return true }
        return obstacles.contains {
            ObstacleCollision.contains(
                p, body: collisionBody(for: $0), margin: radius)
        }
    }

    private func firstObstacleImpact(
        from a: GroundPoint, to b: GroundPoint,
        height: Double, shellRadius: Double = 0.13,
        worldAltitude: Double? = nil
    ) -> Double? {
        obstacles.compactMap { structure in
            // Buildings rise from the local foundation, not sea level.
            let relativeHeight = worldAltitude.map {
                $0 - LandscapeTopology.height(structure.center)
            } ?? height
            return ObstacleCollision.firstImpact(
                from: a, to: b, body: collisionBody(for: structure),
                height: relativeHeight, radius: shellRadius)
        }.min()
    }

    private func registerImpact(at position: GroundPoint, kind: CombatImpact.Kind) {
        let duration: Double
        switch kind {
        case .ground: duration = 0.62
        case .structure: duration = 0.75
        case .armor: duration = 0.88
        case .aircraft: duration = 0.70
        case .destruction: duration = 1.65
        }
        combatImpacts.append(CombatImpact(position: position, kind: kind,
                                          duration: duration))
        if combatImpacts.count > 28 {
            combatImpacts.removeFirst(combatImpacts.count - 28)
        }
    }

    private func renderWorldCombatEffects(_ c: CameraProjection) {
        let effects = CGMutablePath()
        let wrecks = CGMutablePath()
        for event in combatImpacts where
            event.position.distance(to: tankPosition) < 180 {
            let t = event.age / event.duration
            let size: Double
            switch event.kind {
            case .ground: size = 2.2
            case .structure: size = 3.0
            case .armor: size = 4.0
            case .aircraft: size = 3.7
            case .destruction: size = 9.2
            }
            let center = event.position
            // The shock front expands and slows; later arcs read as smoke
            // instead of a permanent opaque particle layer.
            let radius = size * (0.30 + 1.75 * t)
            let ringY = event.kind == .aircraft ? 3.0 : 0.32 + t * size * 0.19
            for section in 0..<12 {
                let a = Double(section) * .pi / 6
                let b = Double(section + 1) * .pi / 6
                if t > 0.65 && section.isMultiple(of: 3) { continue }
                line(effects,
                     WorldPoint(center.x + cos(a) * radius, ringY,
                                center.z + sin(a) * radius),
                     WorldPoint(center.x + cos(b) * radius, ringY,
                                center.z + sin(b) * radius), c)
            }
            if t < 0.48 {
                // First-stage cross flash and outward armor fragments.
                let flare = (1 - t / 0.48) * size * 1.6
                for spoke in 0..<8 {
                    let a = Double(spoke) * .pi / 4
                    line(effects, WorldPoint(center, height: ringY + 0.5),
                         WorldPoint(center.x + cos(a) * flare,
                                    ringY + 0.7 + flare * 0.32,
                                    center.z + sin(a) * flare), c)
                }
            }
            if event.kind == .destruction && t > 0.25 {
                // Secondary, rising angular smoke plume. It dissipates
                // before obstructing the next engagement.
                let plumeY = (t - 0.25) * 8.0
                let plumeR = size * 0.36 * (1 + t)
                for petal in 0..<5 {
                    let a = Double(petal) * 2 * .pi / 5 + t * 0.22
                    line(effects,
                         WorldPoint(center.x + cos(a) * plumeR * 0.5,
                                    plumeY * 0.55,
                                    center.z + sin(a) * plumeR * 0.5),
                         WorldPoint(center.x + cos(a) * plumeR,
                                    plumeY + 1.0,
                                    center.z + sin(a) * plumeR), c)
                }
            }
        }
        for wreck in tankWrecks where
            wreck.position.distance(to: tankPosition) < 150 {
            let p = wreck.position
            let forward = facing(wreck.heading)
            let side = GroundPoint(forward.z, -forward.x)
            func vertex(_ x: Double, _ y: Double, _ z: Double) -> WorldPoint {
                WorldPoint(p.x + side.x * x + forward.x * z, y,
                           p.z + side.z * x + forward.z * z)
            }
            // Collapsed, scorched hull and an offset turret, rendered
            // separately from live enemy hit boxes and pathfinding.
            let corners = [vertex(-2.1, 0.20, -2.8),
                           vertex(2.1, 0.20, -2.8),
                           vertex(2.1, 0.20, 2.8),
                           vertex(-2.1, 0.20, 2.8)]
            for i in 0..<4 {
                line(wrecks, corners[i], corners[(i + 1) % 4], c)
                line(wrecks, corners[i], vertex(i == 0 || i == 3 ? -1.45 : 1.45,
                                                0.85,
                                                i < 2 ? -1.8 : 1.8), c)
            }
            line(wrecks, vertex(-0.7, 1.0, -0.3),
                 vertex(0.9, 1.1, 0.4), c)
            line(wrecks, vertex(0.9, 1.1, 0.4),
                 vertex(2.7, 0.45, 1.8), c)
        }
        combatWorldEffects.path = effects
        combatWorldEffects.alpha = 1
        let chaffPath = CGMutablePath()
        for flake in chaffFlakes {
            let life = max(0, flake.timeLeft / flake.duration)
            if life <= 0 { continue }
            let width = (displayMode != .classic ? 0.8 : 0.55) * life
            line(chaffPath,
                 WorldPoint(flake.position.x - width,
                            flake.position.y - width * 0.45,
                            flake.position.z),
                 WorldPoint(flake.position.x + width,
                            flake.position.y + width * 0.45,
                            flake.position.z), c)
        }
        chaffCloudLines.path = chaffPath
        combatWrecks.path = wrecks
    }

    private func firePlayer() {
        // No ammunition is spent after the ground targets are defeated.
        guard pendingWave <= 0, cannon.fire() else { return }
        shotTally.fire()
        let direction = facing(heading)
        // Incoming cannon corridors provoke a limited evasive reaction.
        for index in enemies.indices where enemies[index].kind.isVehicle {
            let relative = enemies[index].center - tankPosition
            let forward = relative.x * direction.x + relative.z * direction.z
            let lateral = abs(relative.x * direction.z -
                              relative.z * direction.x)
            let reaction = CombatBalance.evasionDuration(
                cannonDistance: forward, lateralError: lateral,
                enemyIndex: index)
            if reaction > 0 {
                enemies[index].evasiveSeconds = max(
                    enemies[index].evasiveSeconds, reaction)
                enemies[index].routeRefreshRemaining = 0
            }
        }
        shells.append(Shell(center: tankPosition + direction * 2.5,
                            direction: direction, hostile: false,
                            timeLeft: rules.projectileLifetime,
                            launchElevation: LandscapeTopology.height(tankPosition)))
        pulse = 0.13
        muzzleRemaining = 0.23
        recoilRemaining = 0.30
        screenKickRemaining = 0.19
        screenKickStrength = 1.0
        // Short-lived dust in front of the muzzle, not in the reticle.
        for _ in 0..<12 {
            let lateral = facing(heading + .pi / 2) * Double.random(in: -2.5...2.5)
            let position = tankPosition + direction * Double.random(in: 3.5...7.5) + lateral
            let life = Double.random(in: 0.28...0.75)
            sparks.append(Spark(position: WorldPoint(position, height: 0.2),
                                velocity: WorldPoint(Double.random(in: -2...2),
                                                     Double.random(in: 0.6...2.5),
                                                     Double.random(in: -2...2)),
                                timeLeft: life, maxLife: life))
        }
        combatAudio.play(.cannon, enabled: soundOn)
    }

    private func fireMachineGun() {
        guard round == .playing, pendingWave <= 0,
              mgAmmo > 0, !mgOverheatLock,
              mgShotCooldown <= 0 else { return }
        let forward = facing(heading)
        // Limited aim correction toward an airborne drone in the forward
        // sight cone: this is not all-direction auto-aim.
        let track = enemies.filter { $0.kind == .drone }.compactMap { drone
            -> (position: GroundPoint, range: Double, error: Double)? in
            let delta = drone.center - tankPosition
            let range = delta.length
            guard range > 3, range < 125 else { return nil }
            let error = wrapAngle(atan2(delta.x, delta.z) - heading)
            guard abs(error) < 0.22 else { return nil }
            return (drone.center, range, abs(error))
        }.min {
            $0.error + $0.range * 0.0004 < $1.error + $1.range * 0.0004
        }
        let direction: GroundPoint = track.map {
            ($0.position - tankPosition).normalized
        } ?? forward
        let side = GroundPoint(forward.z, -forward.x) *
                   (mgBarrel == 0 ? -1.05 : 1.05)
        let muzzle = tankPosition + forward * 2.8 + side
        mgRounds.append(MachineGunRound(center: muzzle,
                                         direction: direction,
                                         timeLeft: 1.15, barrel: mgBarrel))
        mgBarrel = 1 - mgBarrel
        mgAmmo -= 1
        mgFired += 1
        if mgFired.isMultiple(of: 3) { sound("shot.wav") }
        mgShotCooldown = 0.095
        mgHeat = min(110, mgHeat + 3.8)
        if mgHeat >= 100 { mgOverheatLock = true }
        if mgRounds.count > 55 { mgRounds.removeFirst() }
    }

    private func machineGunBounce(at position: GroundPoint,
                                  direction: GroundPoint) {
        // Cosmetic ricochet only: the projectile is consumed; it cannot
        // reflect into another target or damage architecture/armor.
        mgRicochets.append(MachineGunRicochet(center: position,
                                              direction: direction,
                                              timeLeft: 0.23))
        if mgRicochets.count > 26 { mgRicochets.removeFirst() }
        burst(at: WorldPoint(position, height: 2.4), count: 5)
    }

    private func advanceMachineGun(_ dt: Double) {
        var survivors: [MachineGunRound] = []
        var eliminated = Set<Int>()
        for var round in mgRounds {
            let previous = round.center
            round.center = round.center + round.direction * (dt * 150)
            round.timeLeft -= dt
            if round.timeLeft <= 0 { continue }
            let wall = firstObstacleImpact(
                from: previous, to: round.center, height: 3.2,
                shellRadius: 0.08,
                worldAltitude: LandscapeTopology.height(tankPosition) + 3.2)
            var contact: (index: Int, time: Double)?
            for index in enemies.indices where !eliminated.contains(index) {
                let foe = enemies[index]
                let radius = foe.kind == .drone ? 2.3 :
                             foe.kind == .fighter ? 4.7 : 2.8
                if let time = ObstacleCollision.firstCircleImpact(
                    from: previous, to: round.center, center: foe.center,
                    radius: radius),
                   time < (contact?.time ?? .infinity) {
                    contact = (index, time)
                }
            }
            if let wall, wall <= (contact?.time ?? .infinity) {
                let at = previous + (round.center - previous) * wall
                machineGunBounce(at: at, direction: round.direction)
                continue
            }
            if let contact {
                let at = previous + (round.center - previous) * contact.time
                if enemies[contact.index].kind == .drone {
                    enemies[contact.index].hitPoints -= 1
                    mgHits += 1
                    burst(at: WorldPoint(at, height: 3.1), count: 9)
                    registerImpact(at: at, kind: .aircraft)
                    if enemies[contact.index].hitPoints <= 0 {
                        eliminated.insert(contact.index)
                        addPoints(225)
                        sound("impact.wav")
                    }
                } else {
                    // Includes enemy tanks, APCs, artillery and fighters:
                    // machine gun rounds never decrease their hit points.
                    machineGunBounce(at: at, direction: round.direction)
                }
                continue
            }
            survivors.append(round)
        }
        mgRounds = survivors
        for index in eliminated.sorted(by: >) {
            fallingDrones.append(FallingDrone(foe: enemies[index], speed: 0.5))
            enemies.remove(at: index)
        }
        for index in mgRicochets.indices {
            mgRicochets[index].timeLeft -= dt
        }
        mgRicochets.removeAll { $0.timeLeft <= 0 }
    }

    private func launchChaff() {
        guard round == .playing, chaffCharges > 0,
              chaffCooldown <= 0 else { return }
        chaffCharges -= 1
        chaffCooldown = ChaffDefense.cooldown
        chaffActive = ChaffDefense.protectionDuration
        // Reflective strands disperse for seconds instead of a single flash.
        chaffFlakes.removeAll()
        for _ in 0..<82 {
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 7...20)
            let drift = Double.random(in: 1.1...3.2)
            let lifetime = Double.random(in: 1.8...3.3)
            let origin = tankPosition + facing(angle) *
                Double.random(in: 1.0...5.5)
            chaffFlakes.append(ChaffFlake(
                position: WorldPoint(origin, height: Double.random(in: 1.0...3.8)),
                velocity: WorldPoint(cos(angle) * speed,
                                     drift + Double.random(in: -0.6...2.2),
                                     sin(angle) * speed),
                timeLeft: lifetime, duration: lifetime))
        }
        for index in enemies.indices where enemies[index].kind == .drone {
            let distance = enemies[index].center.distance(to: tankPosition)
            if distance <= ChaffDefense.decoyRadius {
                enemies[index].droneDisrupted = 3.0 + Double(index % 5) * 0.45
                enemies[index].droneDropDelay = 5.0
                if ChaffDefense.disrupts(distance: distance) && index % 3 != 0 {
                    fallingDrones.append(FallingDrone(foe: enemies[index], speed: 0.8))
                    enemies[index].hitPoints = 0
                    addPoints(125)
                } else {
                    burst(at: WorldPoint(enemies[index].center,
                                        height: enemies[index].droneAltitude), count: 10)
                }
            }
        }
        enemies.removeAll { $0.kind == .drone && $0.hitPoints <= 0 }
        shells.removeAll {
            $0.hostile && $0.payload == "droneCharge" &&
            $0.center.distance(to: tankPosition) < ChaffDefense.disruptionRadius
        }
        sound("shield.wav")
    }

    private func updateChaffCloud(_ dt: Double) {
        for index in chaffFlakes.indices {
            chaffFlakes[index].position.x += chaffFlakes[index].velocity.x * dt
            chaffFlakes[index].position.y += chaffFlakes[index].velocity.y * dt
            chaffFlakes[index].position.z += chaffFlakes[index].velocity.z * dt
            chaffFlakes[index].velocity.x *= max(0, 1 - dt * 0.80)
            chaffFlakes[index].velocity.z *= max(0, 1 - dt * 0.80)
            chaffFlakes[index].velocity.y -= dt * 1.6
            chaffFlakes[index].timeLeft -= dt
        }
        chaffFlakes.removeAll { $0.timeLeft <= 0 }
    }

    private func updateFallingDrones(_ dt: Double) {
        for i in fallingDrones.indices {
            fallingDrones[i].speed += 9.8 * dt
            fallingDrones[i].foe.droneAltitude -= fallingDrones[i].speed * dt
            fallingDrones[i].foe.droneRoll += dt * 5.6
            fallingDrones[i].foe.dronePitch += dt * 3.8
            fallingDrones[i].foe.center = fallingDrones[i].foe.center +
                fallingDrones[i].foe.droneVelocity * (dt * 0.5)
        }
        for i in fallingDrones.indices.reversed()
            where fallingDrones[i].foe.droneAltitude <= 0.22 {
            let foe = fallingDrones[i].foe
            burst(at: WorldPoint(foe.center, height: 0.35), count: 44)
            sound("explosion.wav")
            fallingDrones.remove(at: i)
        }
    }

    private func updateSparks(_ dt: Double) {
        for idx in sparks.indices {
            sparks[idx].position.x += sparks[idx].velocity.x * dt
            sparks[idx].position.y += sparks[idx].velocity.y * dt
            sparks[idx].position.z += sparks[idx].velocity.z * dt
            sparks[idx].velocity.y -= dt * 5
            sparks[idx].timeLeft -= dt
        }
        sparks.removeAll(where: { $0.timeLeft <= 0 })
    }

    private func triggerShield() {
        guard round == .playing && shieldCooldown <= 0 && shieldDuration <= 0 else { return }
        shieldDuration = rules.shieldDuration
        shieldCooldown = rules.shieldCooldown
        sound("shield.wav")
    }

    private func takeDamage(from incoming: GroundPoint = GroundPoint(0, 0)) {
        incomingBearing = wrapAngle(atan2(incoming.x, incoming.z) - heading)
        damageDirectionRemaining = 1.15
        screenKickRemaining = 0.47
        screenKickStrength = 1.6
        lives -= 1
        invulnerability = 2.8
        driveSpeed = -6.0
        pulse = 0.5
        hitFlashRemaining = 0.66
        // Two layers of debris give an unmistakable armor impact. The death
        // burst is larger and remains animated through the GAME OVER overlay.
        burst(at: WorldPoint(tankPosition, height: 1.4), count: 45)
        burst(at: WorldPoint(tankPosition + facing(heading) * 2.0,
                             height: 2.8), count: 30)
        sound("damage.wav")
        registerImpact(at: tankPosition, kind: .armor)
        if lives <= 0 {
            destructionRemaining = 1.65
            hitFlashRemaining = 1.28
            burst(at: WorldPoint(tankPosition, height: 3.2), count: 115)
            burst(at: WorldPoint(tankPosition, height: 0.65), count: 65)
            registerImpact(at: tankPosition, kind: .destruction)
            combatAudio.play(.explosion, enabled: soundOn)
            round = .gameOver
            if score > bestScore {
                bestScore = score
                UserDefaults.standard.set(
                    bestScore, forKey: "VectorSiegeHighScore")
            }
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

    private func selectSolidBuildings() {
        // Choose exactly thirty percent of actual building structures.
        let indices = obstacles.indices.filter {
            switch obstacles[$0].kind {
            case .building, .tower, .monolith: return true
            default: return false
            }
        }
        let ordered = indices.sorted {
            let a = obstacles[$0].center
            let b = obstacles[$1].center
            let ha = sin(a.x * 13.37 + a.z * 7.11) * 100_000
            let hb = sin(b.x * 13.37 + b.z * 7.11) * 100_000
            return ha < hb
        }
        solidBuildingIndices = Set(ordered.prefix(Int((Double(ordered.count) * 0.30).rounded())))
    }

    private func makeVegetation() {
        vegetation.removeAll()
        // Sparse, irregular planting belongs outside the dense urban core.
        // Downtown is intentionally free of tree wireframes so the tighter
        // ground contours and buildings can establish depth.
        for grid in -2...2 {
            let axis = Double(grid) * CityLayout.streetSpacing
            for slot in -9...9 where (slot + grid * 3).isMultiple(of: 3) {
                let along = Double(slot) * 18 +
                    sin(Double(slot * 3 + grid * 7)) * 3.3
                for side in [-1.0, 1.0] {
                    let horizontal = slot % 2 == 0
                    let sideOffset = side * (10.5 + Double(abs(slot + grid) % 4))
                    let position = horizontal
                        ? GroundPoint(along, axis + sideOffset)
                        : GroundPoint(axis + sideOffset, along)
                    if abs(position.x) > 172 || abs(position.z) > 172 ||
                        max(abs(position.x), abs(position.z)) < 76 ||
                        blocked(position, radius: 2.4) { continue }
                    let variant = abs(slot * 11 + grid * 17 + Int(side * 7))
                    // Shrubs dominate; just one in four is a small tree.
                    let tree = variant % 4 == 0
                    let height = tree
                        ? 3.2 + Double(variant % 8) * 0.44
                        : 0.65 + Double(variant % 5) * 0.19
                    let crown = tree
                        ? 1.2 + Double(variant % 5) * 0.24
                        : 0.85 + Double(variant % 4) * 0.18
                    vegetation.append(Vegetation(
                        location: position, height: height, crown: crown,
                        isTree: tree))
                }
            }
        }
    }

    private func renderVegetation(_ c: CameraProjection) {
        let path = CGMutablePath()
        for plant in vegetation {
            let distance = plant.location.distance(to: tankPosition)
            guard distance < 110 else { continue }
            let view = c.local(WorldPoint(plant.location, height: 1))
            guard BattlefieldRenderLOD.isVisible(
                depth: view.forward, lateral: view.right,
                margin: 9) else { continue }
            let detail = BattlefieldRenderLOD.vegetationDetail(distance: distance)
            let p = plant.location
            let h = plant.height
            let r = plant.crown
            let center = WorldPoint(p, height: 0)
            if plant.isTree {
                // Branching pine form with an uneven conical canopy.
                line(path, center, WorldPoint(p, height: h), c)
                for level in 1...(detail == 2 ? 3 : 2) {
                    let rise = h * (0.26 + Double(level) * 0.18)
                    let span = r * (1.3 - Double(level) * 0.25)
                    for side in [-1.0, 1.0] {
                        line(path, WorldPoint(p, height: rise + h * 0.20),
                             WorldPoint(p.x + side * span, rise, p.z), c)
                        line(path, WorldPoint(p, height: rise + h * 0.20),
                             WorldPoint(p.x, rise, p.z + side * span), c)
                    }
                }
            } else {
                // Low angular scrub, not full spherical wireframe clutter.
                let count = detail == 2 ? 6 : detail == 1 ? 4 : 3
                for direction in 0..<count {
                    let a = Double(direction) * 2 * .pi / Double(count)
                    let b = Double(direction + 1) * 2 * .pi / Double(count)
                    line(path,
                         WorldPoint(p.x + cos(a) * r, h * 0.32, p.z + sin(a) * r),
                         WorldPoint(p.x + cos(b) * r, h * 0.32, p.z + sin(b) * r), c)
                    line(path, WorldPoint(p, height: h),
                         WorldPoint(p.x + cos(a) * r, h * 0.32, p.z + sin(a) * r), c)
                }
            }
        }
        foliageLines.path = path
    }

    private func spawnPatrolSaucer() {
        guard enemies.filter({ $0.kind == .saucer }).count < 1,
              enemies.contains(where: { $0.kind.isVehicle }) else { return }
        let side = Bool.random() ? 1.0 : -1.0
        let across = heading + side * (.pi / 2)
        let origin = tankPosition - facing(across) * 105 +
            facing(heading) * Double.random(in: 45...75)
        let safeOrigin = GroundPoint(max(-170, min(170, origin.x)),
                                     max(-170, min(170, origin.z)))
        enemies.append(Foe(center: safeOrigin,
                           heading: wrapAngle(across + Double.random(in: -0.16...0.16)),
                           kind: .saucer, reload: wave >= 4 ? 3.8 : 999,
                           phase: Double.random(in: 0...(2 * .pi)), hitPoints: 1))
    }

    private func spawnWave() {
        enemies.removeAll()
        waveElapsed = 0
        directorWaveStartLives = lives
        directorWaveStartFired = shotTally.fired
        directorWaveStartHits = shotTally.hits
        droneAttackClock = 0
        chaffFlakes.removeAll()
        // Evaluate several randomized approach quadrants. Keep the squad
        // together and favor an approach with enough clear positions even
        // when the commander is near the city's edge.
        let flank = Double.random(in: 1.15...2.75)
        let side = Bool.random() ? 1.0 : -1.0
        let approaches = [side * flank, -side * flank,
                          side * 2.2, -side * 2.2,
                          Double.pi, -Double.pi]
        let count = rules.enemies(forWave: wave)
        var bestPositions: [GroundPoint] = []
        var chosenApproach = wrapAngle(heading + approaches[0])
        for relative in approaches {
            let candidateApproach = wrapAngle(heading + relative)
            var candidatePositions: [GroundPoint] = []
            for index in 0..<count {
                if let location = SquadSpawnLayout.choose(
                    player: tankPosition, heading: heading,
                    approach: candidateApproach,
                    index: index, count: count, existing: candidatePositions,
                    isOpen: { !self.blocked($0, radius: 4) }) {
                    candidatePositions.append(location)
                }
            }
            if candidatePositions.count > bestPositions.count {
                bestPositions = candidatePositions
                chosenApproach = candidateApproach
            }
            if bestPositions.count == count { break }
        }
        // Last-resort sector scan if a dense block or map edge prevents
        // the formation search from finding even one legal ground target.
        // Without a ground target, a level would auto-complete immediately.
        if bestPositions.isEmpty, let fallback = EnemySpawnLayout.choosePosition(
            player: tankPosition, heading: heading, index: 0, count: 1,
            existing: [], phase: .pi, forwardExclusion: .pi / 6,
            isOpen: { !self.blocked($0, radius: 4) }) {
            bestPositions = [fallback]
            chosenApproach = atan2(fallback.x - tankPosition.x,
                                   fallback.z - tankPosition.z)
        }
        waveApproach = chosenApproach
        waveOrigin = bestPositions.isEmpty
            ? tankPosition + facing(waveApproach) * 125 :
            bestPositions.reduce(GroundPoint(0, 0), +) *
                (1.0 / Double(bestPositions.count))
        for (n, target) in bestPositions.enumerated() {
            let label = BattlefieldWaveDirector.vehicleKind(
                index: n, wave: wave)
            let kind: FoeType
            switch label {
            case "hunter" where rules.huntersEnabled: kind = .hunter
            case "apc": kind = .apc
            case "artillery": kind = .artillery
            default: kind = .tank
            }
            let orientation = atan2(tankPosition.x - target.x,
                                    tankPosition.z - target.z)
            enemies.append(Foe(center: target, heading: orientation,
                               kind: kind,
                               reload: Double.random(in: 3.2...5.4),
                               phase: Double.random(in: 0...6),
                               hitPoints: kind == .hunter || kind == .artillery ? 2 : 1))
        }
        dronesPending = BattlefieldWaveDirector.drones(forWave: wave)
        fightersPending = BattlefieldWaveDirector.fighters(forWave: wave)
        // Wave introductions expose the squad and upcoming air contingents.
        chaffCharges = ChaffDefense.chargesPerWave
        chaffCooldown = 0
        chaffActive = 0
    }

    private func deployAirWing(kind: FoeType, count: Int) {
        guard round == .playing, count > 0 else { return }
        if kind == .drone {
            swarmCenter = waveOrigin - facing(waveApproach) * 8
            swarmVelocity = GroundPoint(0, 0)
            swarmDropTimer = 3.0
            droneAttackClock = -2.0
        }
        for n in 0..<count {
            // Reinforcements originate from the *original* enemy staging
            // sector, even after the player has driven across the map.
            let angle = Double(n) * 2.39996323
            // Broad golden-angle cloud: six of thirty drones orbit farther
            // from the core, rather than merging into a solid wireframe blob.
            let outlier = kind == .drone && n % 5 == 0 ? 1.30 : 1.0
            let radius = sqrt((Double(n) + 0.5) / Double(max(1, count))) *
                29.5 * outlier
            let sideways = kind == .drone
                ? facing(waveApproach + .pi / 2) * (cos(angle) * radius)
                : facing(waveApproach + .pi / 2) *
                    ((Double(n) - Double(count - 1) / 2) * 13)
            let depth = facing(waveApproach) *
                (kind == .fighter ? 17.0 :
                    kind == .drone ? -8.0 + sin(angle) * radius : -8.0)
            // Fighters start far to the side for one continuous flyover.
            let flyover = waveApproach + (n.isMultiple(of: 2) ? 1.27 : -1.27)
            let position = kind == .fighter
                ? tankPosition - facing(flyover) * 115 +
                    facing(waveApproach) * 33
                : waveOrigin + sideways + depth
            let safe = GroundPoint(
                max(-174, min(174, position.x)),
                max(-174, min(174, position.z)))
            let approachHeading = kind == .fighter ? flyover :
                atan2(tankPosition.x - safe.x, tankPosition.z - safe.z)
            var foe = Foe(center: safe, heading: approachHeading,
                          kind: kind, reload: kind == .fighter ? 3.5 : 999,
                          phase: Double(n) * 0.29,
                          hitPoints: kind == .fighter ? 2 : 1)
            if kind == .drone {
                foe.droneOffset = sideways + facing(waveApproach) *
                    (sin(angle) * radius)
                foe.droneSeed = Double(n) * 1.618
                foe.droneVelocity = facing(approachHeading) *
                    Double.random(in: 2.0...4.0)
                foe.droneDropDelay = Double.random(in: 2.0...6.0)
            }
            enemies.append(foe)
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


    /// Snapshot data comes exclusively from existing gameplay state.
    private func makeCockpitV5Snapshot() -> CockpitV5Snapshot {
        func position(_ p: GroundPoint) -> CockpitV5Snapshot.Point {
            CockpitV5Snapshot.Point(x: p.x, z: p.z)
        }
        func contactKind(_ kind: FoeType) -> CockpitV5Snapshot.ContactKind {
            switch kind {
            case .tank: return .tank
            case .hunter: return .hunter
            case .apc: return .apc
            case .artillery: return .artillery
            case .drone: return .drone
            case .fighter: return .fighter
            case .saucer: return .saucer
            }
        }
        let track = targetTelemetry()
        let selectedID = track.flatMap { t in
            enemies.firstIndex { $0.center.distance(to: t.position) < 0.001 }
        }
        let contacts = enemies.enumerated().map { i, foe in
            CockpitV5Snapshot.Contact(
                id: i, kind: contactKind(foe.kind),
                position: position(foe.center), headingRadians: foe.heading,
                visible: true, hitPoints: foe.hitPoints,
                isPrimaryTarget: selectedID == i)
        }
        let selectedTarget = track.map { t in
            CockpitV5Snapshot.Target(
                contactID: selectedID, rangeWorldUnits: t.range,
                bearingOffsetDegrees: t.error * 180 / .pi,
                clearFiringLine: t.clearShot, isGroundVehicle: t.ground)
        }
        let sectorX = min(5, max(0, Int(floor(
            (tankPosition.x + CityLayout.cityExtent) / CityLayout.streetSpacing))))
        let sectorZ = min(5, max(0, Int(floor(
            (tankPosition.z + CityLayout.cityExtent) / CityLayout.streetSpacing))))
        let sectorName = String(format: "%@-%02d",
                                String(UnicodeScalar(65 + sectorX)!), sectorZ + 1)
        return CockpitV5Snapshot(
            headingRadians: heading,
            speedWorldUnitsPerSecond: driveSpeed,
            playerPosition: position(tankPosition),
            terrainElevationWorldUnits: LandscapeTopology.height(tankPosition),
            sector: sectorName, wave: wave, lives: lives, score: score,
            bestScore: bestScore, difficultyLabel: threatLevel.rawValue,
            shotsFired: shotTally.fired, shotsHit: shotTally.hits,
            roundsRemaining: cannon.roundsRemaining,
            magazineCapacity: cannon.maxRounds,
            reloadRemainingSeconds: cannon.reloadRemaining,
            reloadPeriodSeconds: cannon.lastReloadDuration,
            shieldRemainingSeconds: shieldDuration,
            shieldCooldownSeconds: shieldCooldown,
            chaffCharges: chaffCharges, target: selectedTarget,
            contacts: contacts,
            projectiles: shells.map {
                CockpitV5Snapshot.Projectile(
                    position: position($0.center),
                    hostile: $0.hostile, payload: $0.payload)
            })
    }

    private func targetTelemetry() -> TargetTrack? {
        if targetingCacheValid { return targetingCache }
        // Choose an actually aimable contact; favor ground vehicles by a
        // narrow angular margin so dense drones do not steal tank targeting.
        let candidate = enemies.compactMap { foe ->
            (foe: Foe, range: Double, error: Double)? in
            let relative = foe.center - tankPosition
            let range = relative.length
            let error = wrapAngle(atan2(relative.x, relative.z) - heading)
            guard range < 150, abs(error) < .pi / 2 else { return nil }
            return (foe, range, error)
        }.min { a, b in
            let aCost = abs(a.error) - (a.foe.kind.isVehicle ? 0.035 : 0)
            let bCost = abs(b.error) - (b.foe.kind.isVehicle ? 0.035 : 0)
            return aCost < bCost
        }
        guard let chosen = candidate else {
            targetingCacheValid = true
            targetingCache = nil
            return nil
        }
        let ground = chosen.foe.kind.isVehicle
        let clearShot = !ground || (
            firstObstacleImpact(from: tankPosition, to: chosen.foe.center,
                height: 1.65,
                worldAltitude: LandscapeTopology.height(tankPosition) + 1.65) == nil &&
            LandscapeTopology.clearFiringLine(
                from: tankPosition, to: chosen.foe.center))
        let result: TargetTrack = (chosen.range, chosen.error,
                                   chosen.foe.center, ground, clearShot)
        targetingCache = result
        targetingCacheValid = true
        return result
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

    private func foeKindName(_ kind: FoeType) -> String {
        switch kind {
        case .tank: return "tank"
        case .hunter: return "hunter"
        case .apc: return "apc"
        case .artillery: return "artillery"
        case .saucer: return "saucer"
        case .drone: return "drone"
        case .fighter: return "fighter"
        }
    }

    private func foeKind(named name: String) -> FoeType {
        switch name {
        case "hunter": return .hunter
        case "apc": return .apc
        case "artillery": return .artillery
        case "saucer": return .saucer
        case "drone": return .drone
        case "fighter": return .fighter
        default: return .tank
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
                kind: foeKindName($0.kind),
                reload: $0.reload, phase: $0.phase, hitPoints: $0.hitPoints,
                droneSeed: $0.kind == .drone ? $0.droneSeed : nil,
                droneOffset: $0.kind == .drone ? $0.droneOffset : nil,
                droneVelocity: $0.kind == .drone ? $0.droneVelocity : nil,
                droneHasCharge: $0.kind == .drone ? $0.droneHasCharge : nil,
                droneDropDelay: $0.kind == .drone ? $0.droneDropDelay : nil,
                droneDisrupted: $0.kind == .drone ? $0.droneDisrupted : nil,
                droneAltitude: $0.kind == .drone ? $0.droneAltitude : nil,
                attackTimer: $0.kind.isAir ? $0.attackTimer : nil,
                airShotsFired: $0.kind.isAir ? $0.airShotsFired : nil) },
            shells: shells.map { SavedSiegeShell(
                center: $0.center, direction: $0.direction,
                hostile: $0.hostile, timeLeft: $0.timeLeft,
                payload: $0.payload,
                launchElevation: $0.launchElevation) },
            sparks: sparks.map { SavedSiegeSpark(
                position: $0.position, velocity: $0.velocity,
                timeLeft: $0.timeLeft, maxLife: $0.maxLife) },
            secondsUntilSaucerPatrol: saucerPatrol.secondsUntilArrival,
            awaitingLevelStart: round == .levelReady,
            waveApproach: waveApproach,
            waveOrigin: waveOrigin,
            waveElapsed: waveElapsed,
            dronesPending: dronesPending,
            fightersPending: fightersPending,
            chaffCharges: chaffCharges,
            chaffCooldown: chaffCooldown,
            chaffActive: chaffActive,
            droneAttackClock: droneAttackClock,
            directorPressure: directorPressure,
            directorWaveStartLives: directorWaveStartLives,
            directorWaveStartFired: directorWaveStartFired,
            directorWaveStartHits: directorWaveStartHits,
            machineGunAmmo: mgAmmo, machineGunHeat: mgHeat,
            machineGunFired: mgFired, machineGunHits: mgHits
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
        waveApproach = saved.waveApproach ?? heading
        waveOrigin = saved.waveOrigin ?? tankPosition
        waveElapsed = max(0, saved.waveElapsed ?? 0)
        directorPressure = max(-1, min(1, saved.directorPressure ?? 0))
        droneAttackClock = saved.droneAttackClock ??
            max(0, waveElapsed - BattlefieldWaveDirector.droneDelay(forWave: wave))
        dronesPending = max(0, saved.dronesPending ?? 0)
        fightersPending = max(0, saved.fightersPending ?? 0)
        chaffCharges = max(0, min(ChaffDefense.chargesPerWave,
                                  saved.chaffCharges ?? ChaffDefense.chargesPerWave))
        chaffCooldown = max(0, saved.chaffCooldown ?? 0)
        chaffActive = max(0, saved.chaffActive ?? 0)
        chaffFlakes.removeAll()
        swarmCenter = waveOrigin - facing(waveApproach) * 8
        swarmVelocity = GroundPoint(0, 0)
        hitFlashRemaining = 0
        destructionRemaining = 0
        cannon = saved.cannon
        shotTally = saved.shotTally
        mgRounds.removeAll()
        mgRicochets.removeAll()
        mgAmmo = max(0, min(180, saved.machineGunAmmo ?? 180))
        mgHeat = max(0, min(110, (saved.machineGunHeat ?? 0).isFinite
                            ? (saved.machineGunHeat ?? 0) : 0))
        mgFired = max(0, saved.machineGunFired ?? 0)
        mgHits = max(0, saved.machineGunHits ?? 0)
        mgOverheatLock = mgHeat >= 100
        mgShotCooldown = 0
        mgBarrel = mgFired % 2
        directorWaveStartLives = max(lives, saved.directorWaveStartLives ?? lives)
        directorWaveStartFired = min(shotTally.fired, max(0,
            saved.directorWaveStartFired ?? shotTally.fired))
        directorWaveStartHits = min(shotTally.hits, max(0,
            saved.directorWaveStartHits ?? shotTally.hits))
        combatImpacts.removeAll()
        tankWrecks.removeAll()
        muzzleRemaining = 0
        recoilRemaining = 0
        screenKickRemaining = 0
        damageDirectionRemaining = 0
        obstacles = saved.obstacles.map { Obstacle(
            center: $0.center, size: $0.size,
            kind: obstacleKind(named: $0.kind)) }
        fallingDrones.removeAll()
        makeVegetation()
        selectSolidBuildings()
        enemies = saved.enemies.enumerated().map { entry -> Foe in
            let stored = entry.element
            let kind = foeKind(named: stored.kind)
            var foe = Foe(center: stored.center, heading: stored.heading,
                          kind: kind, reload: stored.reload,
                          phase: stored.phase, hitPoints: stored.hitPoints)
            if kind == .drone {
                foe.droneSeed = stored.droneSeed ?? Double(entry.offset) * 1.618
                foe.droneOffset = stored.droneOffset ?? (stored.center - swarmCenter)
                foe.droneVelocity = stored.droneVelocity ??
                    facing(stored.heading) * 2.0
                foe.droneHasCharge = stored.droneHasCharge ?? true
                foe.droneDropDelay = stored.droneDropDelay ?? 2.0
                foe.droneDisrupted = stored.droneDisrupted ?? 0
                foe.droneAltitude = stored.droneAltitude ?? 3.1
            }
            foe.attackTimer = stored.attackTimer ?? 0
            foe.airShotsFired = stored.airShotsFired ?? 0
            return foe
        }
        shells = saved.shells.map { Shell(
            center: $0.center, direction: $0.direction,
            hostile: $0.hostile, timeLeft: $0.timeLeft,
            payload: $0.payload ?? "cannon",
            launchElevation: $0.launchElevation) }
        sparks = saved.sparks.map { Spark(
            position: $0.position, velocity: $0.velocity,
            timeLeft: $0.timeLeft, maxLife: $0.maxLife) }
        steerHoldSeconds = 0
        previousSteerDirection = 0
        turnMotion = 0
        playerStillSeconds = 0
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
        let mode = displayMode.rawValue
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
        Reinforcements: \(dronesPending) drones / \(fightersPending) fighters
        Director: \(DynamicBattlefieldDirector.label(pressure: directorPressure))  Hostile fire cap: \(hostileShotLimit)
        Chaff: \(chaffCharges) charges, \(String(format: "%.1f", chaffCooldown))s cooldown
        FPS (smoothed): \(String(format: "%.1f", observedFPS))
        Shield: \(shieldDuration > 0 ? String(format: "Active %.1fs remaining", shieldDuration) : shieldCooldown > 0 ? "Recharging" : "Ready")
        Runtime: \(String(format: "%.1f", gameClock)) seconds
        Note: Manually copied from the game. No data sent automatically.
        """
    }

    /// Baked graphite/anti-reflective display glass. Fills and material
    /// shading provide apparent depth without drawing fuzzy wireframe trim.
    /// CoreGraphics runs only during initialization, not the render loop.
    private static func materialTexture(optics: Bool) -> SKTexture {
        let size = 256
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return SKTexture(image: NSImage(size: NSSize(width: 2, height: 2))) }
        let stops: [CGFloat] = [0, 0.20, 0.52, 0.85, 1]
        let shades: [CGColor] = optics ? [
            NSColor(calibratedRed: 0.012, green: 0.020, blue: 0.025, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.030, green: 0.048, blue: 0.052, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.058, green: 0.081, blue: 0.086, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.027, green: 0.048, blue: 0.052, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.010, green: 0.018, blue: 0.022, alpha: 1).cgColor
        ] : [
            NSColor(calibratedRed: 0.012, green: 0.019, blue: 0.025, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.025, green: 0.041, blue: 0.048, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.045, green: 0.066, blue: 0.075, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.024, green: 0.035, blue: 0.042, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.010, green: 0.017, blue: 0.023, alpha: 1).cgColor
        ]
        if let gradient = CGGradient(colorsSpace: colorSpace,
                                     colors: shades as CFArray,
                                     locations: stops) {
            ctx.drawLinearGradient(gradient,
                start: CGPoint(x: 0, y: 0), end: CGPoint(x: 256, y: 256),
                options: [])
        }
        // A soft anti-reflective diagonal streak and one narrow specular
        // shoulder suggest actual laminated display glass.
        ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: optics ? 0.022 : 0.016).cgColor)
        ctx.move(to: CGPoint(x: 0, y: 216))
        ctx.addLine(to: CGPoint(x: 175, y: 256))
        ctx.addLine(to: CGPoint(x: 238, y: 256))
        ctx.addLine(to: CGPoint(x: 0, y: 185))
        ctx.closePath()
        ctx.fillPath()
        ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.045).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: 3, y: 3, width: 250, height: 250))
        // Sparse pixel-level luminance variation avoids flat CG color slabs.
        // Never a scanline effect and never animated noisy/fizzy textures.
        for i in 0..<500 {
            let x = CGFloat((i * 73 + 19) % 253)
            let y = CGFloat((i * 109 + 37) % 253)
            ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.009).cgColor)
            ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
        guard let cgImage = ctx.makeImage() else {
            return SKTexture(image: NSImage(size: NSSize(width: 2, height: 2)))
        }
        let texture = SKTexture(cgImage: cgImage)
        texture.filteringMode = .linear
        return texture
    }

    private static func makeConsoleTexture() -> SKTexture {
        materialTexture(optics: false)
    }

    private static func makeOpticsTexture() -> SKTexture {
        materialTexture(optics: true)
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
            (opponentSaucerLines, NSColor(calibratedRed: 0.20, green: 0.75, blue: 1, alpha: 1),
             1.8, displayMode == .classic ? 0.7 : 3.1),
            (shotLines, accent, 2.5, displayMode == .classic ? 0.8 : 5),
            (flashLines, accent, 2.0, displayMode == .classic ? 1 : 5),
            (reticle, accent, displayMode == .classic ? 1.05 : 1.5,
             displayMode == .classic ? 0.15 : 0.55),
            (radar, displayMode != .classic
             ? NSColor(calibratedRed: 0.38, green: 0.56, blue: 0.53, alpha: 0.72)
             : accent, displayMode != .classic ? 0.8 : 1.1, 0),
            (hudLines, muted, 1.0, 0)
        ] {
            node.strokeColor = color
            node.lineWidth = CGFloat(width)
            node.glowWidth = CGFloat(glow)
        }
        if displayMode == .cockpitV53 {
            if approvedCockpit == nil {
                approvedCockpit = CockpitV53LiveRenderer(scene: self)
                approvedCockpitMissingAssets = approvedCockpit == nil
            }
        } else {
            approvedCockpit?.deactivate(rearView)
        }
        let modern = displayMode != .classic
        // v4.0 replaces the legacy bottom strip with a cohesive equipment
        // frame; its live figures remain available in the relocated modules.
        // Keep the player's proven top-mounted telemetry arrangement.
        // New hardware frames surround it; Classic remains untouched.
        // Clean cockpit renders from a separate owned root. Never draw the
        // legacy Modern lower deck when approved Cockpit v5.3 is selected.
        modernCockpit.isHidden = displayMode != .modern
        for surface in monitorMaterials { surface.isHidden = displayMode != .modern }
        bottomMaterial.isHidden = displayMode != .modern
        rearOpticsMaterial.isHidden = displayMode != .modern
        opticsGlass.isHidden = displayMode != .modern
        opticsCaption.isHidden = displayMode != .modern
        radarGroundShading.isHidden = displayMode != .modern
        radarTargetLine.isHidden = displayMode != .modern
        lowerTerrainFill.isHidden = displayMode != .modern
        lowerTankFill.isHidden = displayMode != .modern
        // The clean shell owns the entire Cockpit v5.3 presentation.
        // Hide all old module labels/radar meshes and hardware rather than
        // allowing them to appear as a second strip beneath the new upper art.
        commandDeck.isHidden = displayMode == .cockpitV53
        commandDeck.position.y = 0
        for node in [commandShellBack, commandShellShadow,
                     commandShellBezel, commandShellEdges,
                     commandShellHighlights, commandShellHardware,
                     commandShellAlert] { node.isHidden = displayMode != .modern }
        for label in commandShellLabels { label.isHidden = displayMode != .modern }
        modernFriendlyShells.isHidden = !modern
        modernHostileShells.isHidden = !modern
        modernFriendlyShells.strokeColor = NSColor(calibratedRed: 1, green: 0.89, blue: 0.35, alpha: 0.98)
        modernHostileShells.strokeColor = NSColor(calibratedRed: 1, green: 0.40, blue: 0.22, alpha: 0.94)
        for shellNode in [modernFriendlyShells, modernHostileShells] {
            shellNode.fillColor = .clear
            shellNode.lineWidth = 1.65
            shellNode.glowWidth = modern ? 3.5 : 0
        }
        modernBombShells.strokeColor = NSColor(
            calibratedRed: 1, green: 0.63, blue: 0.19, alpha: 1)
        modernBombShells.fillColor = .clear
        modernBombShells.lineWidth = 2.1
        modernBombShells.glowWidth = modern ? 1.8 : 0
        saucerPulseLines.strokeColor = NSColor(
            calibratedRed: 0.24, green: 0.78, blue: 1.0, alpha: 1)
        saucerPulseLines.lineWidth = modern ? 2.3 : 1.5
        saucerPulseLines.glowWidth = modern ? 4.5 : 1.3
        chaffCloudLines.strokeColor = NSColor(
            calibratedRed: 0.49, green: 0.99, blue: 0.94, alpha: 0.94)
        chaffCloudLines.lineWidth = modern ? 1.6 : 1.0
        chaffCloudLines.glowWidth = modern ? 2.2 : 0.2
        // Combat effects use a restrained warm palette that contrasts with
        // green terrain and the cyan cockpit without hiding the sight.
        muzzleEffects.strokeColor = NSColor(
            calibratedRed: 1, green: 0.94, blue: 0.43, alpha: 1)
        muzzleEffects.lineWidth = modern ? 2.8 : 1.7
        muzzleEffects.glowWidth = modern ? 8 : 2.0
        muzzleEffects.fillColor = .clear
        combatWorldEffects.strokeColor = NSColor(
            calibratedRed: 1, green: 0.59, blue: 0.20, alpha: 0.92)
        combatWorldEffects.lineWidth = modern ? 1.7 : 1.15
        combatWorldEffects.glowWidth = modern ? 2.7 : 0.6
        combatWrecks.strokeColor = NSColor(
            calibratedRed: 0.62, green: 0.36, blue: 0.21, alpha: 0.76)
        combatWrecks.lineWidth = 1.25
        combatWrecks.glowWidth = 0
        directionalDamageEffects.strokeColor = NSColor(
            calibratedRed: 1, green: 0.23, blue: 0.10, alpha: 1)
        directionalDamageEffects.lineWidth = modern ? 3.2 : 2.2
        directionalDamageEffects.glowWidth = modern ? 5 : 2
        // Solid 30% buildings must remain opaque in Classic too.
        glassLayer.isHidden = false
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
        banner.fontColor = displayMode != .classic
            ? NSColor(calibratedRed: 0.18, green: 0.95, blue: 0.98, alpha: 1)
            : cc
        subtitle.fontColor = cc.withAlphaComponent(0.85)
        message.fontColor = accent
        scanlines.strokeColor = green.withAlphaComponent(displayMode == .classic ? 0.035 : 0.025)
        scanlines.lineWidth = 0.5
        let enemyOrange = NSColor(calibratedRed: 1, green: 0.49, blue: 0.12, alpha: 1)
        radarEnemyContacts.strokeColor = enemyOrange
        radarEnemyContacts.fillColor = enemyOrange.withAlphaComponent(0.85)
        radarEnemyContacts.lineWidth = 1.4
        radarEnemyContacts.glowWidth = modern ? 0.7 : 3
        radarHunterContacts.strokeColor = NSColor(calibratedRed: 1, green: 0.18, blue: 0.23, alpha: 1)
        radarHunterContacts.fillColor = NSColor(calibratedRed: 1, green: 0.24, blue: 0.20, alpha: 0.38)
        radarHunterContacts.lineWidth = 1.8
        radarHunterContacts.glowWidth = modern ? 1.0 : 4
        radarSaucerContacts.strokeColor = NSColor(calibratedRed: 0.20, green: 0.75, blue: 1, alpha: 1)
        radarSaucerContacts.fillColor = NSColor(calibratedRed: 0.20, green: 0.75, blue: 1, alpha: 0.58)
        radarSaucerContacts.lineWidth = 1.2
        radarSaucerContacts.glowWidth = modern ? 0.8 : 3
        radarDroneContacts.strokeColor = NSColor(calibratedRed: 1, green: 0.85, blue: 0.24, alpha: 1)
        radarDroneContacts.fillColor = NSColor(calibratedRed: 1, green: 0.77, blue: 0.19, alpha: 0.68)
        radarDroneContacts.lineWidth = 1.4
        radarDroneContacts.glowWidth = 1.0
        radarActiveDrones.strokeColor = NSColor(
            calibratedRed: 1.0, green: 0.82, blue: 0.29, alpha: 1)
        radarActiveDrones.lineWidth = 1.55
        radarActiveDrones.glowWidth = modern ? 1.0 : 3.0
        radarTargetCue.strokeColor = NSColor(
            calibratedRed: 0.45, green: 1.0, blue: 0.69, alpha: 1)
        radarTargetCue.lineWidth = 1.6
        radarTargetCue.glowWidth = 2.3
        radarFighterContacts.strokeColor = NSColor(calibratedRed: 1, green: 0.35, blue: 0.19, alpha: 1)
        radarFighterContacts.fillColor = NSColor(calibratedRed: 1, green: 0.24, blue: 0.13, alpha: 0.35)
        radarFighterContacts.lineWidth = 1.7
        radarFighterContacts.glowWidth = modern ? 0.7 : 2.6
        radarSweepBeam.strokeColor = NSColor(calibratedRed: 0.22, green: 1, blue: 0.48, alpha: 1)
        radarSweepBeam.glowWidth = 0
        radarGroundShading.fillColor = NSColor(
            calibratedRed: 0.06, green: 0.14, blue: 0.15, alpha: 0.92)
        radarTargetLine.strokeColor = NSColor(
            calibratedRed: 0.92, green: 0.72, blue: 0.39, alpha: 0.85)
        radarTargetLine.lineWidth = 1.3
        radarTargetLine.glowWidth = 0
        for wedge in radarSweepGlow {
            wedge.fillColor = NSColor(calibratedRed: 0.05, green: 1, blue: 0.36, alpha: 1)
        }
        for compass in radarCompassLabels {
            compass.fontColor = NSColor(calibratedRed: 0.73, green: 1, blue: 0.83, alpha: 1)
        }
        radarProjectileGlow.strokeColor = .clear
        radarProjectileGlow.fillColor = NSColor(calibratedRed: 1, green: 0.81, blue: 0.11, alpha: 0.24)
        radarProjectileGlow.glowWidth = modern ? 2 : 9
        radarProjectileCore.strokeColor = NSColor(calibratedRed: 1, green: 0.96, blue: 0.41, alpha: 0.98)
        radarProjectileCore.fillColor = NSColor(calibratedRed: 1, green: 0.84, blue: 0.13, alpha: 1)
        radarProjectileCore.glowWidth = modern ? 1 : 5
        radarProjectileCore.lineWidth = 1.1

        let amber = NSColor(calibratedRed: 1, green: 0.72, blue: 0.40, alpha: 1)
        let panelFill = NSColor(calibratedRed: 0.018, green: 0.045, blue: 0.044, alpha: 0.90)
        for panel in [telemetryLeftPanel, telemetryRightPanel, radarPanel, rearPanel] {
            // Layered texture replaces the flat neon screen interior.
            panel.fillColor = modern ? .clear : panelFill
            panel.strokeColor = modern
                ? NSColor(calibratedRed: 0.29, green: 0.61, blue: 0.65, alpha: 0.73)
                : amber.withAlphaComponent(0.32)
            panel.glowWidth = modern ? 0.6 : 0
        }
        let cyan = NSColor(calibratedRed: 0.18, green: 0.97, blue: 0.95, alpha: 1)
        let orange = NSColor(calibratedRed: 1, green: 0.45, blue: 0.14, alpha: 1)
        modernTrim.strokeColor = cyan
        modernTrim.lineWidth = 1.3
        modernTrim.glowWidth = 0.7
        modernLowerDash.fillColor = NSColor(calibratedRed: 0.018, green: 0.026, blue: 0.032, alpha: 0.95)
        modernLowerDash.strokeColor = cyan
        modernUpperBands.fillColor = NSColor(
            calibratedRed: 0.075, green: 0.12, blue: 0.14, alpha: 0.54)
        modernUpperBands.strokeColor = .clear
        modernCompassPlate.fillColor = NSColor(
            calibratedRed: 0.014, green: 0.065, blue: 0.077, alpha: 0.95)
        modernCompassPlate.strokeColor = cyan.withAlphaComponent(0.38)
        modernCompassPlate.lineWidth = 1
        modernCompassPlate.glowWidth = 0
        modernLowerLines.strokeColor = cyan.withAlphaComponent(0.45)
        modernLowerLines.lineWidth = 1
        modernTankIcon.strokeColor = cyan
        modernTankIcon.lineWidth = 2
        modernTankIcon.glowWidth = 0.8
        modernTerrainProfile.strokeColor = cyan.withAlphaComponent(0.94)
        modernTerrainProfile.lineWidth = 1.8
        modernTerrainProfile.glowWidth = 0.7
        modernHeadingPointer.strokeColor = amber
        modernHeadingPointer.lineWidth = 2
        modernHeadingPointer.glowWidth = 3
        modernLowerCorners.strokeColor = amber
        modernLowerCorners.lineWidth = 2
        modernLowerCorners.glowWidth = 1.1
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
        // Raise displayed grid alpha by exactly ten percent.
        groundMesh.strokeColor = modern
            ? NSColor(calibratedRed: 0.19, green: 0.65, blue: 0.55, alpha: 0.297)
            : green.withAlphaComponent(0.198)
        groundMesh.lineWidth = 0.48
        groundMesh.glowWidth = 0
        streetMarks.strokeColor = modern
            ? NSColor(calibratedRed: 0.70, green: 0.84, blue: 0.74, alpha: 0.29)
            : green.withAlphaComponent(0.31)
        streetMarks.lineWidth = modern ? 0.9 : 0.65
        streetMarks.glowWidth = 0
        rearGround.strokeColor = modern
            ? NSColor(calibratedRed: 0.43, green: 0.58, blue: 0.58, alpha: 0.56)
            : green.withAlphaComponent(0.55)
        rearGround.lineWidth = 0.6
        rearEnvironment.strokeColor = modern
            ? NSColor(calibratedRed: 0.66, green: 0.78, blue: 0.76, alpha: 0.75)
            : green.withAlphaComponent(0.82)
        rearEnvironment.lineWidth = 1.15
        rearEnemies.strokeColor = enemyOrange
        rearEnemies.lineWidth = 1.45
        rearEnemies.glowWidth = displayMode != .classic ? 0.8 : 0.2
        armoredLines.strokeColor = NSColor(calibratedRed: 1, green: 0.68, blue: 0.24, alpha: 1)
        armoredLines.lineWidth = 1.6
        armoredLines.glowWidth = 0.7
        droneLines.strokeColor = NSColor(calibratedRed: 1, green: 0.84, blue: 0.25, alpha: 1)
        droneLines.lineWidth = 1.7
        droneLines.glowWidth = 1.2
        fighterLines.strokeColor = NSColor(calibratedRed: 1, green: 0.37, blue: 0.26, alpha: 1)
        fighterLines.lineWidth = 1.7
        fighterLines.glowWidth = 1.0
        countermeasureLines.strokeColor = NSColor(calibratedRed: 0.43, green: 0.96, blue: 1, alpha: 1)
        countermeasureLines.lineWidth = 1.7
        countermeasureLines.glowWidth = 1.1
        rearSaucers.strokeColor = green
        rearSaucers.lineWidth = 1.5
        rearSaucers.glowWidth = displayMode != .classic ? 2.5 : 0.7
        rearShots.strokeColor = amber
        rearShots.glowWidth = 2.6
        rearBackground.strokeColor = .clear
        rearBackground.fillColor = modern
            ? NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.04, alpha: 0.45)
            : NSColor(calibratedRed: 0.012, green: 0.04, blue: 0.055, alpha: 0.98)
        opticsGlass.strokeColor = NSColor(
            calibratedRed: 0.67, green: 0.83, blue: 0.76, alpha: 0.62)
        opticsGlass.lineWidth = 1.0
        opticsCaption.fontColor = NSColor(
            calibratedRed: 0.85, green: 0.88, blue: 0.81, alpha: 0.85)
        radarStreetGrid.strokeColor = modern
            ? NSColor(calibratedRed: 0.30, green: 0.48, blue: 0.45, alpha: 0.42)
            : muted.withAlphaComponent(0.62)
        radarStreetGrid.fillColor = .clear
        radarStreetGrid.lineWidth = 0.65
        radarStreetGrid.glowWidth = 0
        radarObstacleContacts.strokeColor = modern
            ? NSColor(calibratedRed: 0.24, green: 0.49, blue: 0.45, alpha: 0.76)
            : NSColor(calibratedRed: 0.22, green: 0.95, blue: 0.68, alpha: 0.93)
        radarObstacleContacts.fillColor = modern
            ? NSColor(calibratedRed: 0.12, green: 0.24, blue: 0.25, alpha: 0.95)
            : NSColor(calibratedRed: 0.25, green: 0.98, blue: 0.67, alpha: 0.50)
        radarObstacleContacts.lineWidth = 0.9
        radarObstacleContacts.glowWidth = modern ? 0 : 1.7
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
        // Each frame computes the expensive cover-aware target solution only
        // once, shared by radar, both HUD layouts, and warning telemetry.
        targetingCacheValid = false
        targetingCache = nil
        let w = Double(size.width)
        let h = Double(size.height)
        guard w > 100 && h > 100 else { return }
        var camera = CameraProjection(position: tankPosition, yaw: heading,
                                      viewportWidth: w, viewportHeight: h)
        camera.terrainEnabled = true
        camera.eyeHeight += LandscapeTopology.height(tankPosition)
        var worldCamera = camera
        let driveAmount = min(1.0, abs(driveSpeed) / 16.5)
        let turnAmount = min(1.0, turnMotion)
        // Small patterned shudder reads as track vibration, but the sight / HUD
        // stays fixed on the actual aim axis for precise, repeatable targeting.
        worldCamera.eyeHeight += driveAmount * (0.015 * sin(gameClock * 24)
                                               + 0.012 * sin(gameClock * 11.5))
        worldCamera.cameraLateral = driveAmount * 0.018 * sin(gameClock * 19)
                                   + turnAmount * 0.024 * sin(gameClock * 15.3)
        // Camera-only recoil and impacts: targeting uses the unmodified camera.
        let recoil = recoilRemaining > 0
            ? sin((0.30 - recoilRemaining) / 0.30 * .pi) : 0
        let kick = screenKickRemaining > 0
            ? (screenKickRemaining / 0.47) * screenKickStrength : 0
        worldCamera.pitchPoints = suspension.pitch * 138
                                  + driveAmount * 0.9 * sin(gameClock * 21)
                                  + recoil * (displayMode != .classic ? 9 : 5)
                                  + kick * 3.0 * sin(gameClock * 77)
        worldCamera.cameraLateral += kick * 0.028 * sin(gameClock * 63)
        renderMountains(worldCamera)
        renderGround(worldCamera)
        renderObjects(worldCamera)
        renderProjectiles(worldCamera)
        renderWorldCombatEffects(worldCamera)
        renderHUD(camera)
        renderCombatEffects(camera)
        if displayMode == .cockpitV53 {
            approvedCockpit?.layout(in: size, rearCamera: rearView)
        }
    }

    private func renderCombatEffects(_ c: CameraProjection) {
        let w = c.viewportWidth
        let h = c.viewportHeight
        let muzzlePath = CGMutablePath()
        if muzzleRemaining > 0 {
            let scale = muzzleRemaining / 0.23
            let cx = w * 0.5
            let cy = c.horizon - (displayMode != .classic ? 72 : 42)
            let radius = (displayMode != .classic ? 40.0 : 25.0) * scale
            for index in 0..<8 {
                let angle = Double(index) * .pi / 4
                let extent = index.isMultiple(of: 2) ? 1.75 : 1.0
                segment(muzzlePath, point(cx, cy),
                        point(cx + cos(angle) * radius * extent,
                              cy + sin(angle) * radius * extent))
            }
            muzzlePath.addEllipse(in: CGRect(x: cx - radius * 0.35,
                                              y: cy - radius * 0.35,
                                              width: radius * 0.7, height: radius * 0.7))
        }
        muzzleEffects.path = muzzlePath
        muzzleEffects.alpha = CGFloat(min(1, muzzleRemaining / 0.10))
        let warningPath = CGMutablePath()
        if damageDirectionRemaining > 0 {
            let side = sin(incomingBearing)
            let forward = cos(incomingBearing)
            let cx = w * 0.5 + side * min(120, w * 0.12)
            let cy = c.horizon + 90 * forward
            let intensity = damageDirectionRemaining / 1.15
            let radius = 22 + 12 * intensity
            for step in 0..<3 {
                let a = Double(step) * 2 * .pi / 3 + incomingBearing
                segment(warningPath,
                        point(cx + cos(a) * radius, cy + sin(a) * radius),
                        point(cx + cos(a + 0.45) * (radius + 10),
                              cy + sin(a + 0.45) * (radius + 10)))
            }
        }
        directionalDamageEffects.path = warningPath
        directionalDamageEffects.strokeColor = lives <= 1
            ? NSColor(calibratedRed: 1, green: 0.11, blue: 0.08, alpha: 1)
            : NSColor(calibratedRed: 1, green: 0.63, blue: 0.13, alpha: 1)
        directionalDamageEffects.alpha = CGFloat(
            min(1, damageDirectionRemaining * 1.5) *
            (0.70 + 0.30 * abs(sin(gameClock * 15))))
        // Damage shakes the instrumentation without moving its layout.
        let damagePulse = damageDirectionRemaining > 0
            ? 0.66 + 0.34 * abs(sin(gameClock * (lives <= 1 ? 19 : 12)))
            : 1.0
        telemetryRightHeading.alpha = CGFloat(damagePulse)
        telemetryRightFootnote.alpha = CGFloat(damagePulse)
        if hitFlashRemaining > 0 {
            let path = CGMutablePath()
            path.addRect(CGRect(x: 0, y: 0, width: w, height: h))
            damageOverlay.path = path
            let dying = destructionRemaining > 0
            let clock = dying ? destructionRemaining : hitFlashRemaining
            let flicker = 0.42 + 0.58 * abs(sin(clock * 29.0))
            damageOverlay.alpha = CGFloat(
                min(0.72, hitFlashRemaining * (dying ? 0.57 : 0.34) * flicker))
            damageOverlay.fillColor = dying
                ? NSColor(calibratedRed: 1.0, green: 0.26, blue: 0.11, alpha: 1)
                : NSColor(calibratedRed: 1.0, green: 0.09, blue: 0.06, alpha: 1)
        } else {
            damageOverlay.path = nil
        }
        if destructionRemaining > 0 {
            let elapsed = 1.65 - destructionRemaining
            let center = point(w / 2, c.horizon + 18)
            let shock = CGMutablePath()
            for index in 0..<3 {
                let radius = 22 + elapsed * (95 + Double(index) * 59)
                shock.addEllipse(in: CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2))
            }
            destructionRings.path = shock
            destructionRings.strokeColor = NSColor(
                calibratedRed: 1.0, green: 0.52, blue: 0.12,
                alpha: max(0, min(1, destructionRemaining / 1.4)))
            destructionRings.lineWidth = CGFloat(2.4 + destructionRemaining * 1.2)
            destructionRings.glowWidth = 2
        } else {
            destructionRings.path = nil
        }

        // Electronic countermeasure is an active, visible player defense:
        // concentric cyan rings and an E / charge readout in both modes.
        if chaffActive > 0 {
            let rings = CGMutablePath()
            let center = point(w / 2, c.horizon + 18)
            for index in 0..<3 {
                let elapsed = ChaffDefense.protectionDuration - chaffActive
                let radius = 38 + elapsed * (84 + Double(index) * 27)
                rings.addEllipse(in: CGRect(x: center.x-radius,
                                            y: center.y-radius,
                                            width: radius*2, height: radius*2))
            }
            countermeasureLines.path = rings
            countermeasureLines.alpha = CGFloat(
                min(1, chaffActive / ChaffDefense.protectionDuration + 0.2))
            countermeasureLines.lineWidth = 3.3
            countermeasureLines.glowWidth = 5.2
        } else {
            countermeasureLines.path = nil
        }
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
        if displayMode != .classic {
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
        if displayMode != .classic {
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
        let mesh = CGMutablePath()
        // A tight five-unit mesh makes the ground surface read as a surface,
        // particularly along kerbs and moderate ridges. Bound the extent to
        // control geometry cost on macOS while keeping roads as heavier lines.
        let meshStep = 5.0
        let meshRadius = 90.0
        let anchorX = floor(tankPosition.x / meshStep) * meshStep
        let anchorZ = floor(tankPosition.z / meshStep) * meshStep
        // Subdivide the mesh so rolling hills bend the actual ground grid.
        for index in -18...18 {
            // Keep the close city mesh at five-unit spacing. Outer ground
            // mesh lines thin to ten units, preventing distant wire clutter.
            if abs(index) > 12 && !index.isMultiple(of: 2) { continue }
            let x = anchorX + Double(index) * meshStep
            let z = anchorZ + Double(index) * meshStep
            for segment in -18..<18 {
                let a = Double(segment) * meshStep
                let b = Double(segment + 1) * meshStep
                line(mesh, WorldPoint(x, 0.018, anchorZ + a),
                     WorldPoint(x, 0.018, anchorZ + b), c)
                line(mesh, WorldPoint(anchorX + a, 0.018, z),
                     WorldPoint(anchorX + b, 0.018, z), c)
            }
        }
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
                let roadZ = z + side * halfStreet
                // Raised curb lips, beside a gradual roadside transition.
                for segment in -18..<18 {
                    let a = Double(segment) * 10
                    let b = Double(segment + 1) * 10
                    line(roads, WorldPoint(roadX, 0.025, a),
                         WorldPoint(roadX, 0.025, b), c)
                    line(roads, WorldPoint(a, 0.025, roadZ),
                         WorldPoint(b, 0.025, roadZ), c)
                    line(roads, WorldPoint(roadX + side * 0.30, 0.30, a),
                         WorldPoint(roadX + side * 0.30, 0.30, b), c)
                    line(roads, WorldPoint(a, 0.30, roadZ + side * 0.30),
                         WorldPoint(b, 0.30, roadZ + side * 0.30), c)
                }
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
        groundMesh.path = mesh
        streetMarks.path = markings
    }

    private func renderObjects(_ c: CameraProjection) {
        let structurePath = CGMutablePath()
        var facets: [GlassFace] = []
        for (index, o) in obstacles.enumerated() {
            // Culling far outside the visible scene.
            let offset = o.center - tankPosition
            let view = c.local(WorldPoint(o.center, height: 3))
            if offset.length > 190 ||
                !BattlefieldRenderLOD.isVisible(
                    depth: view.forward, lateral: view.right,
                    margin: max(20, o.size * 2.5)) { continue }
            switch o.kind {
            case .pyramid: drawPyramid(o, on: structurePath, camera: c)
            case .block: drawBlock(o, on: structurePath, camera: c)
            case .tower, .building, .monolith:
                if displayMode != .classic { drawArchitecture(o, on: structurePath, camera: c) }
                else { drawBlock(o, on: structurePath, camera: c) }
            }
            let solid = solidBuildingIndices.contains(index)
            if displayMode != .classic || solid {
                // Extremely distant translucent faces add fill overdraw
                // without helping architecture depth. Solid walls remain
                // fully drawn for concealment at every visible range.
                if solid || offset.length < 140 {
                    facets.append(contentsOf: glassFacets(
                        for: o, camera: c, solid: solid))
                }
            }
        }
        structures.path = structurePath
        renderVegetation(c)
        updateGlassFaces(facets, camera: c)

        // Only nearby solid geometry can hide visible armor. Reuse the
        // same broad-phase for the whole frame instead of all city facades.
        let opaqueBodies = solidBuildingIndices.sorted().compactMap { index
            -> ObstacleCollision.Body? in
            let object = obstacles[index]
            guard object.center.distance(to: tankPosition) < 165 else {
                return nil
            }
            let view = c.local(WorldPoint(object.center, height: 3))
            guard BattlefieldRenderLOD.isVisible(
                depth: view.forward, lateral: view.right,
                margin: max(18, object.size * 2.5)) else { return nil }
            return collisionBody(for: object)
        }
        let tankPath = CGMutablePath()
        let armoredPath = CGMutablePath()
        let saucerPath = CGMutablePath()
        let dronePath = CGMutablePath()
        let fighterPath = CGMutablePath()
        for falling in fallingDrones {
            let view = c.local(WorldPoint(falling.foe.center, height: 2))
            if BattlefieldRenderLOD.isVisible(
                depth: view.forward, lateral: view.right) {
                drawDrone(falling.foe, on: dronePath, camera: c)
            }
        }
        for enemy in enemies {
            if enemy.center.distance(to: tankPosition) > 170 { continue }
            let view = c.local(WorldPoint(enemy.center, height: 3))
            if !BattlefieldRenderLOD.isVisible(
                depth: view.forward, lateral: view.right,
                margin: enemy.kind.isAir ? 30 : 15) { continue }
            let blockers = enemy.kind.isVehicle
                ? BattlefieldVisibility.candidates(
                    camera: c.position, target: enemy.center,
                    opaqueBodies: opaqueBodies)
                : []
            switch enemy.kind {
            case .saucer: drawSaucer(enemy, on: saucerPath, camera: c)
            case .drone: drawDrone(enemy, on: dronePath, camera: c)
            case .fighter: drawFighter(enemy, on: fighterPath, camera: c)
            case .apc, .artillery:
                drawTank(enemy, on: armoredPath, camera: c, blockers: blockers)
                drawVehicleDetails(enemy, on: armoredPath, camera: c,
                                   blockers: blockers)
            case .tank, .hunter:
                drawTank(enemy, on: tankPath, camera: c, blockers: blockers)
            }
        }
        opponentLines.path = tankPath
        armoredLines.path = armoredPath
        opponentSaucerLines.path = saucerPath
        droneLines.path = dronePath
        fighterLines.path = fighterPath
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

    private func glassFacets(for o: Obstacle, camera c: CameraProjection,
                            solid: Bool = false) -> [GlassFace] {
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
            return GlassFace(vertices: vertices, depth: z, tint: index, solid: solid)
        }
    }

    private func updateGlassFaces(_ facets: [GlassFace], camera c: CameraProjection) {
        // Solid facades remain visible in classic and modern modes.
        let palette: [NSColor] = [
            NSColor(calibratedRed: 0.13, green: 0.43, blue: 0.51, alpha: 0.23),
            NSColor(calibratedRed: 0.32, green: 0.71, blue: 0.74, alpha: 0.17),
            NSColor(calibratedRed: 0.08, green: 0.25, blue: 0.35, alpha: 0.32),
            NSColor(calibratedRed: 0.40, green: 0.77, blue: 0.76, alpha: 0.18),
            NSColor(calibratedRed: 0.60, green: 0.91, blue: 0.89, alpha: 0.21)
        ]
        var visible = 0
        for facet in facets.sorted(by: { $0.depth > $1.depth }) {
            // Skip faces wholly behind the tank before creating a path.
            if facet.depth < -2 { continue }
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
            face.fillColor = facet.solid
                ? NSColor(calibratedRed: 0.025, green: 0.095, blue: 0.105, alpha: 1)
                : palette[facet.tint % palette.count]
            face.zPosition = CGFloat(visible) * 0.001
            // Render solid facades without the translucent glass edge
            // treatment, so they read as genuine non-transparent walls.
            face.strokeColor = facet.solid
                ? NSColor(calibratedRed: 0.11, green: 0.29,
                          blue: 0.30, alpha: 0.80)
                : NSColor(calibratedRed: 0.71, green: 0.98,
                          blue: 0.97, alpha: 0.25)
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

    /// Occlude precisely the wireframe fragments behind solid buildings.
    /// A partially concealed tank can still expose a gun barrel or tracks.
    private func armoredLine(_ path: CGMutablePath,
                             _ a: WorldPoint, _ b: WorldPoint,
                             _ c: CameraProjection,
                             blockers: [ObstacleCollision.Body]) {
        guard !blockers.isEmpty else {
            line(path, a, b, c)
            return
        }
        let length = sqrt((b.x-a.x)*(b.x-a.x) +
                          (b.y-a.y)*(b.y-a.y) +
                          (b.z-a.z)*(b.z-a.z))
        let steps = BattlefieldRenderLOD.tankSegmentCount(
            length: length, occluderCount: blockers.count)
        func interpolate(_ t: Double) -> WorldPoint {
            WorldPoint(a.x + (b.x-a.x)*t,
                       a.y + (b.y-a.y)*t,
                       a.z + (b.z-a.z)*t)
        }
        for step in 0..<steps {
            let lo = Double(step) / Double(steps)
            let hi = Double(step + 1) / Double(steps)
            let mid = interpolate((lo + hi) * 0.5)
            let hidden = BattlefieldVisibility.blocked(
                camera: c.position, eyeAltitude: c.eyeHeight,
                target: GroundPoint(mid.x, mid.z),
                targetHeight: mid.y, opaqueBodies: blockers)
            if !hidden {
                line(path, interpolate(lo), interpolate(hi), c)
            }
        }
    }

    private func drawTank(_ e: Foe, on path: CGMutablePath,
                          camera c: CameraProjection,
                          blockers: [ObstacleCollision.Body] = []) {
        func v(_ x: Double, _ y: Double, _ z: Double) -> WorldPoint {
            let cs = cos(e.heading), sn = sin(e.heading)
            return WorldPoint(e.center.x + x*cs + z*sn, y,
                              e.center.z - x*sn + z*cs)
        }
        func polygon(_ vertices: [WorldPoint]) {
            guard vertices.count > 1 else { return }
            for i in vertices.indices { armoredLine(path, vertices[i], vertices[(i+1)%vertices.count], c, blockers: blockers) }
        }
        polygon([v(-2.3, 0.35, -3), v(2.3, 0.35, -3),
                 v(2.3, 0.35, 3), v(-2.3, 0.35, 3)])
        polygon([v(-1.9, 1.25, -2.4), v(1.9, 1.25, -2.4),
                 v(1.9, 1.25, 2.1), v(-1.9, 1.25, 2.1)])
        for (x,z) in [(-2.3,-3.0),(2.3,-3.0),(2.3,3.0),(-2.3,3.0)] {
            armoredLine(path, v(x, 0.35, z), v(x*0.83, 1.25, z*0.8), c, blockers: blockers)
        }
        polygon([v(-1.05, 1.35, -1.25), v(1.05, 1.35, -1.25),
                 v(1.05, 1.35, 1.1), v(-1.05, 1.35, 1.1)])
        polygon([v(-0.82, 2.05, -0.95), v(0.82, 2.05, -0.95),
                 v(0.82, 2.05, 0.85), v(-0.82, 2.05, 0.85)])
        for (x,z) in [(-1.05,-1.25),(1.05,-1.25),(1.05,1.1),(-1.05,1.1)] {
            armoredLine(path, v(x, 1.35, z), v(x*0.78, 2.05, z*0.77), c, blockers: blockers)
        }
        armoredLine(path, v(0, 1.80, 0.75), v(0, 1.8, 4.5), c, blockers: blockers)
        armoredLine(path, v(-0.19, 1.95, 0.8), v(-0.19, 1.95, 4.5), c, blockers: blockers)
        armoredLine(path, v(0.19, 1.68, 0.8), v(0.19, 1.68, 4.5), c, blockers: blockers)
        // Independent track outlines add depth at closer range.
        for x in [-2.17, 2.17] {
            polygon([v(x, 0.20, -2.8), v(x, 0.2, 2.7),
                     v(x, 0.75, 2.2), v(x, 0.75, -2.2)])
        }

        // Classic keeps the original simple arcade tank. Modern alone adds
        // hull armor, detailed treads, road wheels, turret optics and hardware.
        guard displayMode != .classic else { return }

        // Faceted glacis armor, sloped hull seams and rear engine deck.
        polygon([v(-1.82, 1.18, 2.15), v(1.82, 1.18, 2.15),
                 v(1.58, 0.62, 3.25), v(-1.58, 0.62, 3.25)])
        armoredLine(path, v(-1.7, 0.75, 3.0), v(1.7, 0.75, 3.0), c, blockers: blockers)
        armoredLine(path, v(-1.65, 1.20, -1.95), v(1.65, 1.20, -1.95), c, blockers: blockers)
        for side in [-1.0, 1.0] {
            // Segmented armored track guards, track plates and side skirts.
            armoredLine(path, v(side*2.48, 0.90, -2.65), v(side*2.48, 0.90, 2.55), c, blockers: blockers)
            armoredLine(path, v(side*2.48, 0.16, -2.75), v(side*2.48, 0.16, 2.55), c, blockers: blockers)
            for index in -6...6 {
                let z = Double(index) * 0.42
                armoredLine(path, v(side*2.52, 0.10, z), v(side*2.52, 0.85, z + 0.09), c, blockers: blockers)
            }
            // Five eight-segment road wheels on each track.
            for index in -2...2 {
                let z = Double(index) * 1.02
                let wheelY = 0.44
                let radius = 0.31
                for j in 0..<8 {
                    let a = Double(j) * .pi / 4
                    let b = Double(j + 1) * .pi / 4
                    armoredLine(path,
                         v(side*2.56, wheelY + sin(a)*radius, z + cos(a)*radius),
                         v(side*2.56, wheelY + sin(b)*radius, z + cos(b)*radius), c, blockers: blockers)
                }
                armoredLine(path, v(side*2.56, wheelY, z),
                     v(side*2.59, wheelY + 0.11, z), c, blockers: blockers)
            }
            // Angled turret cheek armor and side lifting brackets.
            armoredLine(path, v(side*1.12, 1.38, 0.98), v(side*0.88, 2.10, 0.72), c, blockers: blockers)
            armoredLine(path, v(side*1.05, 1.55, -1.13), v(side*0.79, 2.07, -0.84), c, blockers: blockers)
            polygon([v(side*0.94, 1.89, -0.98), v(side*0.94, 1.89, -0.60),
                     v(side*0.70, 2.18, -0.64), v(side*0.70, 2.18, -0.91)])
        }
        // Turret roof, commander's hatch perimeter, sight and optics.
        polygon([v(-0.81, 2.06, -0.94), v(0.81, 2.06, -0.94),
                 v(0.81, 2.06, 0.84), v(-0.81, 2.06, 0.84)])
        for index in 0..<12 {
            let a = Double(index) * .pi / 6
            let b = Double(index + 1) * .pi / 6
            armoredLine(path,
                 v(-0.29 + cos(a)*0.42, 2.12, -0.25 + sin(a)*0.42),
                 v(-0.29 + cos(b)*0.42, 2.12, -0.25 + sin(b)*0.42), c, blockers: blockers)
        }
        polygon([v(0.22, 2.10, 0.18), v(0.55, 2.10, 0.18),
                 v(0.55, 2.46, 0.48), v(0.22, 2.46, 0.48)])
        armoredLine(path, v(0.38, 2.46, 0.48), v(0.38, 2.65, 0.51), c, blockers: blockers)

        // Recoil housing and three barrel reinforcing collars / muzzle ring.
        polygon([v(-0.29, 1.95, 1.28), v(0.29, 1.95, 1.28),
                 v(0.29, 1.61, 1.28), v(-0.29, 1.61, 1.28)])
        for z in [1.15, 3.1, 4.5] {
            polygon([v(-0.25, 1.97, z), v(0.25, 1.97, z),
                     v(0.25, 1.63, z), v(-0.25, 1.63, z)])
        }
        armoredLine(path, v(0, 1.80, 4.5), v(0, 1.80, 4.83), c, blockers: blockers)

        // Engine louvers, rear tow loops and whip antenna.
        for index in -3...3 {
            let x = Double(index) * 0.39
            armoredLine(path, v(x, 1.29, -1.86), v(x, 1.29, -2.43), c, blockers: blockers)
        }
        for side in [-1.0, 1.0] {
            polygon([v(side*1.31, 0.52, -3.07),
                     v(side*1.66, 0.52, -3.07),
                     v(side*1.66, 0.86, -3.07),
                     v(side*1.31, 0.86, -3.07)])
        }
        armoredLine(path, v(-0.73, 2.03, -0.76), v(-0.89, 3.42, -0.83), c, blockers: blockers)
        armoredLine(path, v(-0.89, 3.42, -0.83), v(-0.84, 3.71, -0.81), c, blockers: blockers)
    }

    private func drawVehicleDetails(_ e: Foe, on path: CGMutablePath,
                                    camera c: CameraProjection,
                                    blockers: [ObstacleCollision.Body] = []) {
        func v(_ x: Double, _ y: Double, _ z: Double) -> WorldPoint {
            let cs = cos(e.heading), sn = sin(e.heading)
            return WorldPoint(e.center.x + x*cs + z*sn, y,
                              e.center.z - x*sn + z*cs)
        }
        if e.kind == .apc {
            // Short armored personnel carrier: wider engine roof and several
            // access hatches, one-hit target that moves faster than a tank.
            for z in [-1.8, 0.0, 1.8] {
                armoredLine(path, v(-1.6, 1.5, z), v(1.6, 1.5, z), c, blockers: blockers)
            }
            armoredLine(path, v(-2.5, 0.72, -2.6), v(-2.5, 0.72, 2.6), c, blockers: blockers)
            armoredLine(path, v(2.5, 0.72, -2.6), v(2.5, 0.72, 2.6), c, blockers: blockers)
        } else if e.kind == .artillery {
            // Mobile artillery: elevated distinctive long-range cannon and
            // rear stabilizers. Two hits and a slower, distant attack.
            armoredLine(path, v(0, 2.2, 0), v(0, 3.6, 5.8), c, blockers: blockers)
            armoredLine(path, v(-0.32, 2.2, 0), v(-0.32, 3.6, 5.8), c, blockers: blockers)
            armoredLine(path, v(0.32, 2.2, 0), v(0.32, 3.6, 5.8), c, blockers: blockers)
            armoredLine(path, v(-2.4, 0.35, -2.6), v(-3.5, 0.10, -4), c, blockers: blockers)
            armoredLine(path, v(2.4, 0.35, -2.6), v(3.5, 0.10, -4), c, blockers: blockers)
        }
    }

    private func drawDrone(_ e: Foe, on path: CGMutablePath,
                           camera c: CameraProjection) {
        // Apply full 3D body attitude before yaw, so forward thrust pitches
        // the nose down and braking presents the underbelly to the player.
        func v(_ x: Double, _ rise: Double, _ z: Double) -> WorldPoint {
            let cr = cos(e.droneRoll), sr = sin(e.droneRoll)
            let cp = cos(e.dronePitch), sp = sin(e.dronePitch)
            let rx = x * cr - rise * sr
            let ry = x * sr + rise * cr
            let py = ry * cp - z * sp
            let pz = ry * sp + z * cp
            let cs = cos(e.heading), sn = sin(e.heading)
            return WorldPoint(e.center.x + rx * cs + pz * sn,
                              e.droneAltitude + py,
                              e.center.z - rx * sn + pz * cs)
        }
        func poly(_ vertices: [WorldPoint]) {
            for i in vertices.indices {
                line(path, vertices[i], vertices[(i + 1) % vertices.count], c)
            }
        }
        // Compact fuselage with depth, a raised canopy, and rear electronics.
        poly([v(-0.48, 0, -0.69), v(0.48, 0, -0.69),
              v(0.48, 0, 0.69), v(-0.48, 0, 0.69)])
        poly([v(-0.36, 0.23, -0.40), v(0.36, 0.23, -0.40),
              v(0.36, 0.23, 0.40), v(-0.36, 0.23, 0.40)])
        for x in [-0.36, 0.36] {
            for z in [-0.40, 0.40] {
                line(path, v(x, 0.23, z), v(x * 1.33, 0, z * 1.725), c)
            }
        }
        for side in [-1.0, 1.0] {
            for z in [-1.12, 1.12] {
                let x = side * 1.43
                line(path, v(side * 0.40, 0.03, z * 0.20),
                     v(x, 0.10, z), c)
                // Rotor hub, motor mast, circular guard and swept blade.
                line(path, v(x, 0.08, z), v(x, 0.23, z), c)
                for k in 0..<8 {
                    let a = Double(k) * .pi / 4
                    let b = Double(k + 1) * .pi / 4
                    line(path,
                         v(x + cos(a) * 0.44, 0.23, z + sin(a) * 0.44),
                         v(x + cos(b) * 0.44, 0.23, z + sin(b) * 0.44), c)
                }
                let spin = gameClock * 22 + e.droneSeed
                line(path, v(x + cos(spin) * 0.38, 0.25,
                             z + sin(spin) * 0.38),
                     v(x - cos(spin) * 0.38, 0.25,
                       z - sin(spin) * 0.38), c)
            }
        }
        // Skids and antenna, plus a distinct underslung charge while armed.
        for side in [-1.0, 1.0] {
            line(path, v(side * 0.45, -0.13, -0.56),
                 v(side * 0.56, -0.42, -0.56), c)
            line(path, v(side * 0.45, -0.13, 0.56),
                 v(side * 0.56, -0.42, 0.56), c)
            line(path, v(side * 0.56, -0.42, -0.76),
                 v(side * 0.56, -0.42, 0.76), c)
        }
        line(path, v(0, 0.24, -0.32), v(0, 0.70, -0.46), c)
        if e.droneHasCharge {
            line(path, v(0, -0.12, 0), v(0, -0.40, 0), c)
            poly([v(-0.28, -0.43, -0.36), v(0.28, -0.43, -0.36),
                  v(0.28, -0.43, 0.36), v(-0.28, -0.43, 0.36)])
            poly([v(-0.20, -0.76, -0.28), v(0.20, -0.76, -0.28),
                  v(0.20, -0.76, 0.28), v(-0.20, -0.76, 0.28)])
            line(path, v(-0.28, -0.43, -0.36), v(-0.20, -0.76, -0.28), c)
            line(path, v(0.28, -0.43, -0.36), v(0.20, -0.76, -0.28), c)
            line(path, v(0.28, -0.43, 0.36), v(0.20, -0.76, 0.28), c)
            line(path, v(-0.28, -0.43, 0.36), v(-0.20, -0.76, 0.28), c)
        }
    }

    private func drawFighter(_ e: Foe, on path: CGMutablePath,
                             camera c: CameraProjection) {
        let altitude = 3.9 + 0.40 * sin(e.phase * 0.9)
        func v(_ x: Double, _ y: Double, _ z: Double) -> WorldPoint {
            let cs = cos(e.heading), sn = sin(e.heading)
            return WorldPoint(e.center.x + x*cs + z*sn, altitude + y,
                              e.center.z - x*sn + z*cs)
        }
        // Delta wing and paired tail fins distinguish the strafing aircraft
        // from slow saucers. It makes a low enough pass for tank auto-elevation.
        let outer = [v(0, 0, 6.6), v(1.15, 0, 2.0),
                     v(6.1, 0, -1.1), v(5.0, 0, -2.4),
                     v(1.25, 0, -1.6), v(1.0, 0, -5.0),
                     v(-1.0, 0, -5.0), v(-1.25, 0, -1.6),
                     v(-5.0, 0, -2.4), v(-6.1, 0, -1.1),
                     v(-1.15, 0, 2.0)]
        for i in outer.indices {
            line(path, outer[i], outer[(i+1) % outer.count], c)
        }
        line(path, v(0, 0.5, 4.9), v(0, 1.2, 0.7), c)
        line(path, v(0, 1.2, 0.7), v(0, 0, -5.0), c)
        for x in [-1.0, 1.0] {
            line(path, v(x, 0, -3.6), v(x * 2.0, 1.6, -4.7), c)
            line(path, v(x * 2.0, 1.6, -4.7), v(x * 1.0, 0, -5), c)
        }
        line(path, v(-1.0, 0, 0.2), v(1.0, 0, 0.2), c)
    }

    private func drawSaucer(_ e: Foe, on path: CGMutablePath, camera c: CameraProjection) {
        // Animated rotating wireframe disk: moving facets and radial spokes make
        // the spin obvious in both Classic and Modern display modes.
        let n = displayMode != .classic ? 18 : 12
        let spin = gameClock * 2.9 + e.phase
        let hover = 7.5 + sin(gameClock * 2.4 + e.phase) * 0.55
        let radius = displayMode != .classic ? 3.7 : 3.1
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
            if displayMode != .classic && i.isMultiple(of: 3) {
                // Rotating elevated light bar and undercarriage facet.
                line(path, domeA, ring(a, radius: radius * 0.16, elevation: hover + 1.63), c)
                line(path, lowerA, ring(a, radius: radius * 0.24, elevation: hover - 0.77), c)
            }
        }
        if displayMode != .classic {
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
        let pulseWire = CGMutablePath()
        let friendlyWire = CGMutablePath()
        let hostileWire = CGMutablePath()
        let bombWire = CGMutablePath()
        for shell in shells {
            // Heightmap projection applies terrain elevation automatically.
            // Compensate for that in shell geometry so ballistic rounds keep
            // the actual world-space elevation used by hit tests.
            func shellLine(_ path: CGMutablePath,
                           _ a: WorldPoint, _ b: WorldPoint) {
                guard let origin = shell.launchElevation else {
                    line(path, a, b, c)
                    return
                }
                let adjustedA = WorldPoint(
                    a.x, a.y + origin -
                    LandscapeTopology.height(GroundPoint(a.x, a.z)), a.z)
                let adjustedB = WorldPoint(
                    b.x, b.y + origin -
                    LandscapeTopology.height(GroundPoint(b.x, b.z)), b.z)
                line(path, adjustedA, adjustedB, c)
            }
            let height = shell.hostile ? 1.5 : 1.65
            if shell.payload == "saucerPulse" {
                let p = shell.center
                let r = 0.76
                for spoke in 0..<8 {
                    let a = Double(spoke) * .pi / 4 + gameClock * 2.2
                    shellLine(pulseWire,
                        WorldPoint(p.x + cos(a) * r, 2.7, p.z + sin(a) * r),
                        WorldPoint(p.x + cos(a + .pi / 2) * r, 2.7,
                                   p.z + sin(a + .pi / 2) * r))
                }
                continue
            }
            if shell.payload == "bomb" && displayMode != .classic {
                // Bombs visibly descend from an air-delivered trajectory.
                // They remain low-speed, dodgeable area threats at impact.
                let timeInFlight = 7.2 - shell.timeLeft
                let altitude = max(1.5, 5.4 - timeInFlight * 0.80)
                let r = 0.90
                for index in 0..<10 {
                    let a = Double(index) * 2 * .pi / 10
                    let b = Double(index + 1) * 2 * .pi / 10
                    shellLine(bombWire,
                         WorldPoint(shell.center.x + cos(a)*r, altitude,
                                    shell.center.z + sin(a)*r),
                         WorldPoint(shell.center.x + cos(b)*r, altitude,
                                    shell.center.z + sin(b)*r))
                }
                shellLine(bombWire,
                     WorldPoint(shell.center.x, altitude + 1.0, shell.center.z),
                     WorldPoint(shell.center.x, altitude - 1.0, shell.center.z))
                continue
            }
            if displayMode == .classic {
                // Preserve the original compact tracer in Classic.
                let p = WorldPoint(shell.center, height: height)
                let tail = shell.center - shell.direction * (shell.hostile ? 2.4 : 3.8)
                shellLine(bulletPath, p, WorldPoint(tail, height: height))
                shellLine(bulletPath, WorldPoint(shell.center.x, height-0.28, shell.center.z),
                     WorldPoint(shell.center.x, height+0.28, shell.center.z))
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
                    shellLine(path, nose, frontRing[i])
                    shellLine(path, frontRing[i], frontRing[next])
                    shellLine(path, frontRing[i], backRing[i])
                    shellLine(path, backRing[i], backRing[next])
                    shellLine(path, backRing[i], tailTip)
                }
                for side in [-1.0, 1.0] {
                    let fin = vertex(end, side * radius * 1.65, 0)
                    shellLine(path, frontRing[side > 0 ? 0 : 2], fin)
                    shellLine(path, fin, tailTip)
                }
                // A narrow illuminated tracer axis makes fast rounds readable
                // without changing their position or hit detection.
                shellLine(path, nose, tailTip)
            }
        }
        shotLines.path = bulletPath
        modernFriendlyShells.path = friendlyWire
        modernHostileShells.path = hostileWire
        modernBombShells.path = bombWire
        saucerPulseLines.path = pulseWire

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
        let mgPath = CGMutablePath()
        for round in mgRounds {
            let back = round.center - round.direction * 3.5
            line(mgPath, WorldPoint(round.center, height: 3.2),
                 WorldPoint(back, height: 3.2), c)
        }
        machineGunLines.path = mgPath
        machineGunLines.strokeColor = NSColor(calibratedRed: 1,
            green: 0.83, blue: 0.37, alpha: 0.95)
        machineGunLines.lineWidth = 1.3
        let bouncePath = CGMutablePath()
        for spark in mgRicochets {
            let fraction = spark.timeLeft / 0.23
            let displacement = spark.direction * (5*(1-fraction))
            line(bouncePath,
                 WorldPoint(spark.center + displacement, height: 2.6+2*(1-fraction)),
                 WorldPoint(spark.center + displacement -
                            spark.direction * (2.0*fraction), height: 2.6), c)
        }
        machineGunRicochetLines.path = bouncePath
        machineGunRicochetLines.strokeColor = NSColor(calibratedRed: 1,
            green: 0.57, blue: 0.23, alpha: 0.9)
        machineGunRicochetLines.lineWidth = 1.3
    }

    /// A live, tank-relative rear camera rendered from a true 180-degree
    /// perspective. All paths are clipped by SKCropNode to the inset viewport.
    /// This does not affect physics, aiming or the main scene camera.
    private func renderRearView(width: Double, height: Double) {
        var backCamera = CameraProjection(
            position: tankPosition, yaw: wrapAngle(heading + .pi),
            viewportWidth: width, viewportHeight: height)
        backCamera.terrainEnabled = true
        backCamera.eyeHeight += LandscapeTopology.height(tankPosition)
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
                if displayMode != .classic {
                    drawArchitecture(object, on: obstaclePath, camera: backCamera)
                } else {
                    drawBlock(object, on: obstaclePath, camera: backCamera)
                }
            }
        }
        rearEnvironment.path = obstaclePath

        let rearOpaque = solidBuildingIndices.sorted().map {
            collisionBody(for: obstacles[$0])
        }
        let tankPath = CGMutablePath()
        let saucerPath = CGMutablePath()
        for foe in enemies where foe.center.distance(to: tankPosition) < 120 {
            switch foe.kind {
            case .saucer:
                drawSaucer(foe, on: saucerPath, camera: backCamera)
            case .drone:
                drawDrone(foe, on: saucerPath, camera: backCamera)
            case .fighter:
                drawFighter(foe, on: saucerPath, camera: backCamera)
            case .tank, .hunter, .apc, .artillery:
                let blockers = BattlefieldVisibility.candidates(
                    camera: backCamera.position, target: foe.center,
                    opaqueBodies: rearOpaque)
                drawTank(foe, on: tankPath, camera: backCamera,
                         blockers: blockers)
                if foe.kind == .apc || foe.kind == .artillery {
                    drawVehicleDetails(foe, on: tankPath, camera: backCamera,
                                       blockers: blockers)
                }
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
    /// Grid-based instrument banks. Stable column widths and baseline spacing
    /// replace the independently scattered labels from previous iterations.
    /// The readouts remain live SpriteKit text, not a background screenshot.
    private func renderModernUpperHUD(
        width w: Double, height h: Double,
        leftCenter: Double, rightCenter: Double,
        bankWidth: Double, panelHeight: Double
    ) {
        let cyan = NSColor(calibratedRed: 0.48, green: 0.80, blue: 0.81, alpha: 1)
        let greenBright = NSColor(calibratedRed: 0.49, green: 0.93, blue: 0.65, alpha: 1)
        let pale = NSColor(calibratedRed: 0.88, green: 0.92, blue: 0.89, alpha: 1)
        let mutedText = pale.withAlphaComponent(0.67)
        let amber = NSColor(calibratedRed: 1, green: 0.54, blue: 0.18, alpha: 1)
        let left = leftCenter - bankWidth / 2
        let right = rightCenter - bankWidth / 2
        let top = h - 16
        let inset = 17.0
        let inner = bankWidth - inset * 2
        // Layout follows a precise 5-band grid: title / primary / tracking /
        // performance / position or status. Height stays constant with resize.
        let titleY = top - 24
        let primaryY = top - 74
        let row2Y = top - 123
        let row3Y = top - 165
        let row4Y = top - 210
        let scale = max(0.76, min(1.0, inner / 332.0))
        let small = 12.0 * scale
        let medium = 13.0 * scale

        func put(_ id: Int, _ text: String, _ x: Double, _ y: Double,
                 _ size: Double, _ color: NSColor = pale,
                 align: SKLabelHorizontalAlignmentMode = .left) {
            let label = modernUpperText[id]
            label.text = text
            label.position = point(x, y)
            label.fontSize = CGFloat(size)
            label.fontColor = color
            label.horizontalAlignmentMode = align
        }
        let bearing = Int((heading * 180 / .pi + 360)
            .truncatingRemainder(dividingBy: 360).rounded()) % 360
        let target = targetTelemetry()
        let targetBearing = target.map {
            Int((Double(bearing) + $0.error * 180 / .pi + 720)
                .truncatingRemainder(dividingBy: 360).rounded()) % 360
        }
        // LEFT / targeting. Primary heading and speed use two fixed cells.
        put(0, "01  /  TARGETING + NAVIGATION",
            left + inset, titleY, 11.0 * scale, cyan)
        put(1, String(format: "HDG %03d°", bearing),
            left + inset, primaryY, 25 * scale, cyan)
        put(2, String(format: "SPD %+.1f", driveSpeed),
            left + bankWidth - inset, primaryY, 22 * scale, cyan, align: .right)

        // Three evenly spaced data columns, right aligned at cell boundaries.
        let c1 = left + inset
        let c2 = left + bankWidth * 0.36
        let c3 = left + bankWidth - inset
        put(3, targetBearing.map { String(format: "TGT %03d", $0) } ?? "TGT ---",
            c1, row2Y, medium)
        put(4, target.map {
                String(format: "AIM %+.1f°", $0.error * 180 / .pi)
            } ?? "AIM ---", c2, row2Y, small)
        put(5, target.map { String(format: "RNG %.0f", $0.range) }
            ?? "RNG ---", c3, row2Y, medium, align: .right)
        put(6, String(format: "H/M %02d:%02d",
                       shotTally.hits, shotTally.misses),
            c1, row3Y, small)
        put(7, String(format: "HIT %.0f%%", shotTally.hitPercentage),
            c2, row3Y, medium, greenBright)
        put(8, String(format: "F %02d", shotTally.pending),
            c3, row3Y, small, align: .right)
        let targetStatus = target.map { $0.ground
            ? ($0.clearShot ? "LOS CLEAR" : "COVER") : "AIR TRACK" } ?? "NO TRACK"
        put(9, targetStatus, c1, row4Y, 10 * scale,
            target?.clearShot == false ? amber : mutedText)
        put(10, String(format: "X %+.1f", tankPosition.x),
            c2, row4Y, medium)
        put(11, String(format: "Z %+.1f", tankPosition.z),
            c3, row4Y, medium, align: .right)

        // RIGHT / combat. Readiness is grouped directly with its bar.
        put(12, "04  /  COMBAT SYSTEMS + STATUS",
            right + inset, titleY, 11 * scale, cyan)
        put(13, "SCORE", right + inset, top - 50, small, mutedText)
        put(14, String(format: "%06d", score),
            right + inset, top - 87, 31 * scale, cyan)
        put(15, "BEST", right + bankWidth - inset, top - 50,
            small, mutedText, align: .right)
        put(16, String(format: "%06d", bestScore),
            right + bankWidth - inset, top - 85,
            17 * scale, pale, align: .right)
        put(17, String(format: "WAVE %02d", wave),
            right + inset, row2Y, medium)
        put(18, String(format: "LIVES %02d", lives),
            right + bankWidth * 0.47, row2Y, medium,
            align: .center)
        put(19, threatLevel.rawValue.uppercased(),
            right + bankWidth - inset, row2Y,
            11 * scale, greenBright, align: .right)
        put(20, "SHIELD", right + 48, row3Y, medium)
        let shieldStatus = shieldDuration > 0
            ? String(format: "ACTIVE %.1f", shieldDuration)
            : shieldCooldown > 0
                ? String(format: "CHARGE %.1f", shieldCooldown)
                : "READY [SHIFT]"
        put(21, shieldStatus, right + bankWidth - inset, row3Y,
            small, shieldDuration > 0 ? cyan :
                (shieldCooldown > 0 ? amber : greenBright), align: .right)
        put(22, String(format: "AMMO %02d/%02d",
                         cannon.roundsRemaining, cannon.maxRounds),
            right + 48, row4Y, medium, cyan)
        put(23, cannon.reloadRemaining > 0
                ? String(format: "RELOAD %.1fs", cannon.reloadRemaining)
                : "READY", right + bankWidth - inset, row4Y,
            small, cannon.reloadRemaining > 0 ? pale : greenBright,
            align: .right)
        put(24, "", right + 24, row3Y, small)

        // One disciplined divider system for both instrument banks.
        let line = CGMutablePath()
        func rule(_ x: Double, _ y: Double) {
            segment(line, point(x + 12, y), point(x + bankWidth - 12, y))
        }
        for x in [left, right] {
            for y in [top - 42, top - 105, top - 144, top - 186] {
                rule(x, y)
            }
        }
        segment(line, point(left + bankWidth * 0.51, top - 96),
                point(left + bankWidth * 0.51, top - 53))
        segment(line, point(right + bankWidth * 0.66, top - 96),
                point(right + bankWidth * 0.66, top - 52))
        modernUpperDividers.path = line
        modernUpperDividers.strokeColor = cyan.withAlphaComponent(0.26)
        modernUpperDividers.lineWidth = 0.75
        // Recess the two primary readout rows into subtle common instrument
        // wells so metrics read as grouped hardware instead of floating text.
        let wells = CGMutablePath()
        for x in [left, right] {
            wells.addRoundedRect(
                in: CGRect(x: x + 9, y: top - 101,
                           width: bankWidth - 18, height: 54),
                cornerWidth: 6, cornerHeight: 6)
        }
        modernUpperBands.path = wells

        // Icons are restrained and precisely aligned to the status text.
        let icons = CGMutablePath()
        let sx = right + 29.0
        let sy = row3Y
        icons.move(to: point(sx - 8, sy + 10))
        icons.addLine(to: point(sx + 8, sy + 10))
        icons.addLine(to: point(sx + 7, sy - 3))
        icons.addLine(to: point(sx, sy - 12))
        icons.addLine(to: point(sx - 7, sy - 3))
        icons.closeSubpath()
        for bullet in 0..<3 {
            let x = right + 17 + Double(bullet) * 10
            let y = row4Y
            segment(icons, point(x, y - 7), point(x, y + 10))
            segment(icons, point(x + 6, y - 7), point(x + 6, y + 10))
            segment(icons, point(x, y + 10), point(x + 3, y + 14))
            segment(icons, point(x + 3, y + 14), point(x + 6, y + 10))
        }
        modernUpperIcons.path = icons
        modernUpperIcons.strokeColor = greenBright.withAlphaComponent(0.9)
        modernUpperIcons.lineWidth = 1.3
        modernUpperIcons.glowWidth = 0.3

        // Minimal corner accents: two deliberate orange signals, not a
        // competing tangle of decorative traces.
        let corners = CGMutablePath()
        segment(corners, point(left, top - 25), point(left + 17, top - 8))
        segment(corners, point(left + 17, top - 8),
                point(left + 57, top - 8))
        segment(corners, point(right + bankWidth - 57, top - 8),
                point(right + bankWidth - 17, top - 8))
        segment(corners, point(right + bankWidth - 17, top - 8),
                point(right + bankWidth, top - 25))
        modernOrangeCorners.path = corners
        modernOrangeCorners.strokeColor = amber.withAlphaComponent(0.85)
        modernOrangeCorners.lineWidth = 1.7
        modernOrangeCorners.glowWidth = 0.7
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
        let scale = min(1.10, max(0.80, w / 1380))
        let bottomY = 27.0
        let bottomHeight = max(113.0, min(152.0, h * 0.177))
        let topY = bottomY + bottomHeight
        let x0 = 12.0
        // Strong, repeatable zones: vehicle 25%, accuracy 15%,
        // navigation 28%, terrain plot 16%, coordinates 16%.
        let x1 = w * 0.250
        let x2 = w * 0.400
        let x3 = w * 0.680
        let x4 = w * 0.840
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
        bottomMaterial.position = point(w * 0.5, (topY + bottomY) * 0.5)
        bottomMaterial.size = CGSize(width: w - 28,
                                     height: max(1, bottomHeight - 8))
        modernLowerDash.strokeColor = NSColor(
            calibratedRed: 0.26, green: 0.39, blue: 0.42, alpha: 0.85)
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
        let hull = CGMutablePath()
        hull.move(to: point(leftEdge + 7, wheelY + 18))
        hull.addLine(to: point(rightEdge - 7, wheelY + 18))
        hull.addLine(to: point(rightEdge - 10, wheelY + 2))
        hull.addLine(to: point(leftEdge + 11, wheelY + 2))
        hull.closeSubpath()
        hull.move(to: point(leftEdge + 31, wheelY + 21))
        hull.addLine(to: point(leftEdge + 36, wheelY + 35))
        hull.addLine(to: point(leftEdge + 69, wheelY + 35))
        hull.addLine(to: point(leftEdge + 77, wheelY + 21))
        hull.closeSubpath()
        lowerTankFill.path = hull
        lowerTankFill.fillColor = NSColor(
            calibratedRed: 0.18, green: 0.39, blue: 0.37, alpha: 0.85)

        // Tank integrity is a readiness proxy based on remaining lives; the
        // game doesn't yet simulate component-by-component armor damage.
        let integrity = 100.0 * Double(max(0, lives)) /
                        Double(max(1, rules.startingLives))
        let statusLeft = leftEdge + tankWidth + 17
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
        modernTankStatus.position = point(statusLeft, topY - 29)
        modernTankStatus.fontColor = greenLight
        modernTankStatus.fontSize = CGFloat(12.5 * scale)
        modernTankStatus.text = "TANK / STATUS"
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
        setExtra(2, "MODE", x: statusLeft, y: topY - 111,
                 size: 12, color: cyan)
        setExtra(6, round == .playing ? "COMBAT" :
                       round == .paused ? "PAUSED" :
                       round == .levelReady ? "STANDBY" : "OFFLINE",
                 x: x1 - 16, y: topY - 111, size: 12,
                 color: greenLight, alignedRight: true)

        // Hit ratio is backed by the existing resolved shot tally.
        modernHitCaption.position = point(x1 + 17, topY - 29)
        modernHitCaption.fontSize = CGFloat(13 * scale)
        modernHitCaption.text = "HIT RATIO"
        modernHitValue.position = point(x1 + 17, middleY - 12)
        modernHitValue.fontSize = CGFloat(32 * scale)
        modernHitValue.fontColor = cyan
        modernHitValue.text = String(format: "%.0f%%", shotTally.hitPercentage)
        let hitRadius = min(34.0, (x2 - x1) * 0.18)
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
        modernCompassPlate.path = CGPath(
            roundedRect: CGRect(x: compassX - min(57, (x3 - x2) * 0.20),
                                y: topY - 50, width: min(114, (x3 - x2) * 0.40),
                                height: 42),
            cornerWidth: 7, cornerHeight: 7, transform: nil)
        modernHeadingValue.position = point(compassX, topY - 28)
        modernHeadingValue.fontColor = amber
        modernHeadingValue.fontSize = CGFloat(26 * scale)
        modernHeadingValue.text = String(
            format: "%03d°", Int(headingDegrees.rounded()) % 360)
        modernCompassLabel.position = point(compassX, bottomY + 14)
        modernCompassLabel.fontSize = CGFloat(10 * scale)
        modernCompassLabel.text = "NAV  /  HEADING"

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
        let terrainFill = CGMutablePath()
        terrainFill.move(to: point(plotStart, plotBottom))
        for i in 0...48 {
            let t = Double(i) / 48
            let bearing = heading + (t - 0.5) * 1.05
            let elevation = plotBottom + 16 +
                min(25.0, ridge(bearing, multiplier: 0.48))
            terrainFill.addLine(to: point(plotStart + plotWidth*t, elevation))
        }
        terrainFill.addLine(to: point(plotEnd, plotBottom))
        terrainFill.closeSubpath()
        lowerTerrainFill.path = terrainFill
        lowerTerrainFill.fillColor = NSColor(
            calibratedRed: 0.12, green: 0.30, blue: 0.32, alpha: 0.79)
        modernTerrainLabel.position = point(x3 + 18, topY - 28)
        modernTerrainLabel.horizontalAlignmentMode = .left
        modernTerrainLabel.text = "TERRAIN / PROFILE"
        modernTerrainLabel.fontSize = CGFloat(11 * scale)

        // Sector readout uses actual 60-unit city blocks, not fabricated
        // location labels. X maps A-F, Z maps 01-06.
        let sectorX = min(5, max(0,
            Int(floor((tankPosition.x + CityLayout.cityExtent)
                      / CityLayout.streetSpacing))))
        let sectorZ = min(5, max(0,
            Int(floor((tankPosition.z + CityLayout.cityExtent)
                      / CityLayout.streetSpacing))))
        let sectorLetter = String(UnicodeScalar(65 + sectorX)!)
        modernSectorValue.position = point(x5 - 18, topY - 64)
        modernSectorValue.text = String(format: "%@-%02d",
                                       sectorLetter, sectorZ + 1)
        modernSectorValue.fontSize = CGFloat(19 * scale)
        modernSectorValue.fontColor = cyan
        setExtra(3, "SECTOR", x: x4 + 18, y: topY - 28,
                 size: 11, color: cyan)
        setExtra(4, String(format: "ELEV  %+.1f m",
                           LandscapeTopology.height(tankPosition)),
                 x: x5 - 18, y: topY - 94,
                 size: 11, color: cyan, alignedRight: true)
        setExtra(5, String(format: "X%+.0f  Z%+.0f",
                           tankPosition.x, tankPosition.z),
                 x: x5 - 18, y: bottomY + 20,
                 size: 10, color: cyan.withAlphaComponent(0.80),
                 alignedRight: true)
        let chaffStatus = chaffCooldown > 0
            ? String(format: "E CHAFF %d  %.0fs", chaffCharges, chaffCooldown)
            : String(format: "E CHAFF  %d/%d", chaffCharges,
                     ChaffDefense.chargesPerWave)
        setExtra(7, chaffStatus, x: x1 + 17, y: bottomY + 18,
                 size: 10, color: chaffCharges > 0 ? greenLight : amber)
        for unused in 8..<modernLowerExtra.count {
            modernLowerExtra[unused].text = ""
        }

        // Upper combat bank: preserve actual five-second shield readiness and
        // magazine depletion while keeping independent vector progress bars.
        let barLeft = rightX - bankWidth + 70
        let barWidth = max(46.0, bankWidth - 91)
        let barHeight = 6.0
        // Directly below each corresponding status row, never floating
        // across row separators or intersecting a neighboring label.
        let shieldY = h - 16 - 181.0
        let ammoY = h - 16 - 226.0
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
            // Floating full-width beveled hazard bar inspired by the supplied
            // mockup. The label is centered *inside* this very same rectangle.
            let width = min(w - 44, 1040.0)
            let high = 67.0
            let centerY = bottomY + bottomHeight + 56
            let x0 = (w - width) / 2
            let x1 = x0 + width
            let lo = centerY - high / 2
            let hi = centerY + high / 2
            let panel = CGMutablePath()
            let bevel = 15.0
            panel.move(to: point(x0 + bevel, lo))
            panel.addLine(to: point(x1 - bevel, lo))
            panel.addLine(to: point(x1, centerY))
            panel.addLine(to: point(x1 - bevel, hi))
            panel.addLine(to: point(x0 + bevel, hi))
            panel.addLine(to: point(x0, centerY))
            panel.closeSubpath()
            modernThreatPanel.path = panel
            modernThreatPanel.strokeColor = distance <= TankProximity.tankLength ?
                NSColor.systemRed : amber
            modernThreatPanel.fillColor = NSColor(
                calibratedRed: 0.15, green: 0.017, blue: 0.014, alpha: 0.91)
            modernThreatPanel.lineWidth = 2.5
            modernThreatPanel.glowWidth = 2.2
            modernThreatPanel.alpha = CGFloat(
                0.86 + 0.14 * abs(sin(gameClock * 5.0)))
            let wings = CGMutablePath()
            for side in [-1.0, 1.0] {
                for stripe in 0..<3 {
                    let offset = Double(stripe) * 15
                    let x = side < 0 ? x0 - 19 - offset : x1 + 19 + offset
                    let skew = side * 13
                    wings.move(to: point(x - 5, lo + 7))
                    wings.addLine(to: point(x + skew + 5, hi - 7))
                    wings.addLine(to: point(x + skew + 13, hi - 7))
                    wings.addLine(to: point(x + 3, lo + 7))
                    wings.closeSubpath()
                }
            }
            proximityWings.path = wings
            proximityWings.fillColor = NSColor(
                calibratedRed: 1, green: 0.33, blue: 0.11, alpha: 0.80)
            proximityWings.strokeColor = .clear
            proximityWings.isHidden = false
            proximityLabel.isHidden = false
            proximityLabel.position = point(w / 2, centerY)
            let content = String(format:
                "⚠  PROXIMITY ALERT   //   ENEMY %.1f TANK LENGTHS",
                distance / TankProximity.tankLength)
            proximityLabel.text = content
            proximityLabel.fontSize = CGFloat(
                min(22.0, (width - 38) / (Double(content.count) * 0.63)))
            proximityLabel.fontColor = distance <= TankProximity.tankLength ?
                NSColor.systemRed : NSColor(
                    calibratedRed: 1, green: 0.59, blue: 0.31, alpha: 1)
        } else {
            proximityLabel.isHidden = true
            proximityWings.isHidden = true
        }
    }

    /// v4.0.1 top-mounted cockpit hardware. Four live modules retain their
    /// successful v3.7 geometry while sitting in one physical armored header.
    /// Anodized panel fills, thick matte gaskets, sparse brass fasteners, and
    /// subtle edge lighting replace the distracting full-screen wireframes.
    private func renderCommandCockpitShell(width w: Double, height h: Double,
                                           bankWidth: Double,
                                           radarWidth: Double,
                                           rearWidth: Double,
                                           gap: Double, margin: Double) {
        let panelHeight = min(278.0, max(248.0, h * 0.34))
        let top = h - 16.0
        let foot = top - panelHeight
        let midX = margin + bankWidth + gap
        let farX = midX + radarWidth + gap
        let rightX = farX + rearWidth + gap
        let modules: [(Double, Double, String)] = [
            (margin, bankWidth, "01 / FIRE CONTROL"),
            (midX, radarWidth, "02 / TACTICAL RADAR"),
            (farX, rearWidth, "03 / REAR OPTICS"),
            (rightX, bankWidth, "04 / COMBAT SYSTEMS")
        ]
        let cyan = NSColor(calibratedRed: 0.40, green: 0.76,
                           blue: 0.76, alpha: 1)
        let mutedMetal = NSColor(calibratedRed: 0.18, green: 0.26,
                                blue: 0.29, alpha: 1)
        let amber = NSColor(calibratedRed: 0.96, green: 0.59,
                            blue: 0.22, alpha: 1)
        // Dark continuous backplate. It is thick enough to be perceived as
        // hardware, but leaves the central panoramic battlefield untouched.
        let rearPlate = CGMutablePath()
        rearPlate.addRoundedRect(
            in: CGRect(x: 4, y: foot - 37, width: max(1, w - 8),
                       height: panelHeight + 50),
            cornerWidth: 16, cornerHeight: 16)
        // Armored vertical jambs read as supporting structure, rather than
        // thin glowing borders floating above the battlefield.
        for x in [0.0, w - 11] {
            rearPlate.addRect(CGRect(x: x, y: foot - 44,
                                    width: 11, height: panelHeight + 62))
        }
        commandShellBack.path = rearPlate
        commandShellBack.fillColor = NSColor(
            calibratedRed: 0.021, green: 0.032, blue: 0.041, alpha: 0.99)
        commandShellBack.strokeColor = NSColor(
            calibratedRed: 0.14, green: 0.20, blue: 0.22, alpha: 0.90)
        commandShellBack.lineWidth = 1

        // Screen gaskets, stepped corners, and a shared reinforced sill.
        let borders = CGMutablePath()
        let high = CGMutablePath()
        let fittings = CGMutablePath()
        let raisedBezel = CGMutablePath()
        let shadowBezel = CGMutablePath()
        let width = w - 20
        borders.addRoundedRect(
            in: CGRect(x: 10, y: foot - 31, width: max(1, width),
                       height: panelHeight + 36),
            cornerWidth: 11, cornerHeight: 11)
        segment(borders, point(18, foot - 24), point(w - 18, foot - 24))
        segment(borders, point(18, top + 11), point(w - 18, top + 11))
        // Each recess has deliberately thick corner plates, not full
        // neon frames competing with the actual display content.
        for (index, unit) in modules.enumerated() {
            let x = unit.0
            let span = unit.1
            let innerY = foot - 6
            // Two filled stepped casings add a real sense of depth.
            // They sit under the live screen fill, not across the telemetry.
            shadowBezel.addRoundedRect(
                in: CGRect(x: x - 8, y: innerY - 7,
                           width: span + 16, height: panelHeight + 22),
                cornerWidth: 14, cornerHeight: 14)
            raisedBezel.addRoundedRect(
                in: CGRect(x: x - 5, y: innerY - 4,
                           width: span + 10, height: panelHeight + 16),
                cornerWidth: 11, cornerHeight: 11)
            borders.addRoundedRect(
                in: CGRect(x: x - 4, y: innerY,
                           width: span + 8,
                           height: panelHeight + 12),
                cornerWidth: 11, cornerHeight: 11)
            // Realistic bezel highlights: short spans with shadow gaps.
            segment(high, point(x + 15, top + 8),
                    point(x + min(span - 18, 64), top + 8))
            segment(high, point(x + span - 58, foot - 9),
                    point(x + span - 16, foot - 9))
            // Muted screwheads at four corners; crossed slots, no glow.
            for fx in [x + 9, x + span - 9] {
                for fy in [foot + 11, top - 9] {
                    fittings.addEllipse(in: CGRect(
                        x: fx - 3.1, y: fy - 3.1,
                        width: 6.2, height: 6.2))
                    segment(fittings, point(fx - 1.7, fy + 1.2),
                            point(fx + 1.7, fy - 1.2))
                }
            }
            // Small paired bezel vent ports, clear of the monitor labels.
            if span > 170 {
                for slot in 0..<5 {
                    let vx = x + 20 + Double(slot) * 12
                    fittings.addRoundedRect(
                        in: CGRect(x: vx, y: foot - 18,
                                   width: 7, height: 3),
                        cornerWidth: 1.0, cornerHeight: 1.0)
                }
            }
            if index > 0 {
                let split = x - gap * 0.5
                segment(borders, point(split, foot - 25),
                        point(split, top + 8))
            }
        }
        // Flat dark horizontal structural strips bridge the upper bezel;
        // three high-quality amber switch legends add warmth sparingly.
        let lipY = foot - 24
        for index in 0..<3 {
            let x = 18 + Double(index) * 18
            segment(high, point(x, lipY - 5), point(x + 9, lipY - 5))
            let x2 = w - x
            segment(high, point(x2 - 9, lipY - 5), point(x2, lipY - 5))
        }
        commandShellShadow.path = shadowBezel
        commandShellShadow.fillColor = NSColor(
            calibratedRed: 0.004, green: 0.009, blue: 0.012, alpha: 1)
        commandShellShadow.strokeColor = .clear
        commandShellBezel.path = raisedBezel
        commandShellBezel.fillColor = NSColor(
            calibratedRed: 0.085, green: 0.104, blue: 0.115, alpha: 1)
        commandShellBezel.strokeColor = NSColor(
            calibratedRed: 0.14, green: 0.17, blue: 0.19, alpha: 1)
        commandShellBezel.lineWidth = 1.4
        commandShellEdges.path = borders
        commandShellEdges.fillColor = .clear
        commandShellEdges.strokeColor = mutedMetal
        commandShellEdges.lineWidth = 3.1
        commandShellEdges.glowWidth = 0
        commandShellHighlights.path = high
        commandShellHighlights.fillColor = .clear
        commandShellHighlights.strokeColor = cyan.withAlphaComponent(0.58)
        commandShellHighlights.lineWidth = 1.15
        commandShellHighlights.glowWidth = 0
        commandShellHardware.path = fittings
        commandShellHardware.strokeColor = NSColor(
            calibratedRed: 0.40, green: 0.44,
            blue: 0.43, alpha: 0.9)
        commandShellHardware.fillColor = NSColor(
            calibratedRed: 0.09, green: 0.12,
            blue: 0.13, alpha: 0.97)
        commandShellHardware.lineWidth = 0.9
        commandShellHardware.glowWidth = 0

        // Quiet equipment legends in the sill. All status values already
        // live in the instrument modules, so do not duplicate large figures.
        for (i, unit) in modules.enumerated() {
            let label = commandShellLabels[i]
            label.text = unit.2
            label.position = point(unit.0 + 12, foot - 25)
            label.fontSize = CGFloat(max(7.4, min(9.5, unit.1 / 27)))
            label.fontColor = cyan.withAlphaComponent(0.77)
            label.horizontalAlignmentMode = .left
            label.isHidden = false
        }
        for index in 4..<8 {
            commandShellLabels[index].isHidden = true
        }
        commandShellAlert.isHidden = true
    }

    private func renderHUD(_ c: CameraProjection) {
        let w = c.viewportWidth
        let h = c.viewportHeight
        let hp = CGMutablePath()
        let rp = CGMutablePath()
        let sight = CGMutablePath()
        let modernHUD = displayMode != .classic
        if !modernHUD {
            proximityLabel.isHidden = true
            proximityWings.isHidden = true
        }
        let radarRange = 165.0
        let panelHeight = modernHUD ? min(278.0, max(248.0, h * 0.34)) : 154.0
        let outerMargin = modernHUD ? 14.0 : 14.0
        // Use narrower gutters. The radar monitor expands into the space
        // previously left on either side of its circular display.
        let panelGap = modernHUD ? 4.0 : 12.0
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
        // Widen the radar monitor to its allocated column instead of
        // artificially forcing a square frame of panelHeight width.
        // The dial stays circular and centered; no neighboring bank moves.
        radarPanel.path = CGPath(
            roundedRect: CGRect(x: -radarPanelWidth / 2,
                                y: -panelHeight / 2,
                                width: radarPanelWidth, height: panelHeight),
            cornerWidth: 10, cornerHeight: 10, transform: nil)
        rearPanel.path = panelRect(width: rearPanelWidth)
        telemetryLeftPanel.position = point(leftCenterX, topCenterY)
        telemetryRightPanel.position = point(rightCenterX, topCenterY)
        radarPanel.position = point(radarX, topCenterY)
        rearPanel.position = point(rearX, topCenterY)
        if modernHUD {
            let positions = [leftCenterX, radarX, rearX, rightCenterX]
            let widths = [bankWidth, radarPanelWidth,
                          rearPanelWidth, bankWidth]
            for index in 0..<monitorMaterials.count {
                let screen = monitorMaterials[index]
                screen.position = point(positions[index], topCenterY)
                screen.size = CGSize(width: max(1, widths[index] - 10),
                                     height: max(1, panelHeight - 10))
                screen.alpha = 0.98
            }
        }
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
        rearOpticsMaterial.position = point(rearWidth / 2, rearHeight / 2)
        rearOpticsMaterial.size = CGSize(width: rearWidth, height: rearHeight)
        opticsCaption.position = point(11, 15)
        opticsCaption.text = "EO/IR  //  REAR  180°  //  1.0X"
        let opticPath = CGMutablePath()
        let corner = 13.0
        let tick = 8.0
        for (x, dx) in [(corner, 1.0), (rearWidth - corner, -1.0)] {
            for (y, dy) in [(corner, 1.0), (rearHeight - corner, -1.0)] {
                segment(opticPath, point(x, y), point(x + dx*tick, y))
                segment(opticPath, point(x, y), point(x, y + dy*tick))
            }
        }
        segment(opticPath, point(rearWidth/2 - 15, rearHeight/2),
                point(rearWidth/2 - 4, rearHeight/2))
        segment(opticPath, point(rearWidth/2 + 4, rearHeight/2),
                point(rearWidth/2 + 15, rearHeight/2))
        opticsGlass.path = opticPath
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
        // Every five degrees, with longer 30-degree cardinal bearings.
        for i in 0..<72 {
            let angle = Double(i) * Double.pi / 36
            let major = i.isMultiple(of: 6)
            let mid = i.isMultiple(of: 3)
            let inner = radarRadius - (major ? 12.0 : (mid ? 7.0 : 3.6))
            segment(rp, point(radarX + sin(angle)*inner, radarY + cos(angle)*inner),
                    point(radarX + sin(angle)*radarRadius,
                          radarY + cos(angle)*radarRadius))
        }
        // Semi-transparent radial sectors trail the sweep beam. Twenty-four
        // thin wedges form a gradual fade, clipped exactly at the square.
        let sweepAngle = gameClock * 1.18
        let wedgeCount = radarSweepGlow.count
        let trailWidth = Double.pi * 0.57
        for index in 0..<wedgeCount {
            let age0 = Double(index) / Double(wedgeCount)
            let age1 = Double(index + 1) / Double(wedgeCount)
            let a0 = sweepAngle - age0 * trailWidth
            let a1 = sweepAngle - age1 * trailWidth
            let extent0 = TacticalRadarGeometry.squareReach(
                angle: a0, halfSide: radarRadius)
            let extent1 = TacticalRadarGeometry.squareReach(
                angle: a1, halfSide: radarRadius)
            let triangle = CGMutablePath()
            triangle.move(to: point(radarX, radarY))
            triangle.addLine(to: point(radarX + sin(a0)*extent0,
                                       radarY + cos(a0)*extent0))
            triangle.addLine(to: point(radarX + sin(a1)*extent1,
                                       radarY + cos(a1)*extent1))
            triangle.closeSubpath()
            let wedge = radarSweepGlow[index]
            wedge.path = triangle
            wedge.alpha = CGFloat((modernHUD ? 0.17 : 0.36) *
                TacticalRadarGeometry.intensity(
                trailingFraction: (age0 + age1) / 2))
        }
        let sweepReach = TacticalRadarGeometry.squareReach(
            angle: sweepAngle, halfSide: radarRadius)
        let beamPath = CGMutablePath()
        segment(beamPath, point(radarX, radarY),
                point(radarX + sin(sweepAngle) * sweepReach,
                      radarY + cos(sweepAngle) * sweepReach))
        radarSweepBeam.path = beamPath
        // Cardinal letters and small white/green bearing symbols follow the
        // actual tank heading, while the player's nose remains screen-up.
        for (i, letter) in ["N", "E", "S", "W"].enumerated() {
            let angle = Double(i) * .pi / 2 - heading
            let r = radarRadius - 14.0
            radarCompassLabels[i].text = letter
            radarCompassLabels[i].position = point(
                radarX + sin(angle) * r, radarY + cos(angle) * r)
        }
        segment(rp, point(radarX-5, radarY-5), point(radarX, radarY+8))
        segment(rp, point(radarX, radarY+8), point(radarX+5, radarY-5))

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
        if modernHUD {
            // Faint filled tactical blocks: this map conveys the road grid
            // as area and mass, rather than another copy of the vector world.
            let shaded = CGMutablePath()
            let limit = CGRect(x: radarX - radarRadius + 2,
                               y: radarY - radarRadius + 2,
                               width: radarRadius * 2 - 4,
                               height: radarRadius * 2 - 4)
            for object in obstacles where
                object.center.distance(to: tankPosition) < radarRange {
                let center = projectedRadar(object.center)
                guard limit.contains(center) else { continue }
                let extent = max(2.4, min(10.0, object.size *
                    radarRadius / radarRange * 0.7))
                let square = CGRect(x: center.x - extent, y: center.y - extent,
                                    width: extent * 2, height: extent * 2)
                shaded.addRoundedRect(in: square,
                                      cornerWidth: 1.5, cornerHeight: 1.5)
            }
            radarGroundShading.path = shaded
        } else {
            radarGroundShading.path = nil
        }

        let obstaclesOnRadar = CGMutablePath()
        let enemyContacts = CGMutablePath()
        let hunterContacts = CGMutablePath()
        let saucerContacts = CGMutablePath()
        let droneContacts = CGMutablePath()
        let activeDroneContacts = CGMutablePath()
        let focusedTarget = CGMutablePath()
        let fighterContacts = CGMutablePath()
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
            switch foe.kind {
            case .saucer:
                // Green diamond distinguishes the aerial patrol.
                let r = 4.6
                saucerContacts.move(to: point(contact.x, contact.y + r))
                saucerContacts.addLine(to: point(contact.x + r, contact.y))
                saucerContacts.addLine(to: point(contact.x, contact.y - r))
                saucerContacts.addLine(to: point(contact.x - r, contact.y))
                saucerContacts.closeSubpath()
            case .hunter, .artillery:
                let r = foe.kind == .artillery ? 5.7 : 5.2
                hunterContacts.move(to: point(contact.x, contact.y + r))
                hunterContacts.addLine(to: point(contact.x - r, contact.y - r))
                hunterContacts.addLine(to: point(contact.x + r, contact.y - r))
                hunterContacts.closeSubpath()
            case .drone:
                // Passive drones are grouped below the entity loop.
                // Only an active wing gets separate high-contrast contacts.
                let index = max(0, Int((foe.droneSeed / 1.618).rounded()))
                if AirEncounterDirector.isAttacking(
                    droneIndex: index, elapsed: droneAttackClock) &&
                    foe.droneDisrupted <= 0 {
                    let r = 3.5
                    activeDroneContacts.move(to: point(contact.x, contact.y + r))
                    activeDroneContacts.addLine(to: point(contact.x-r, contact.y-r))
                    activeDroneContacts.addLine(to: point(contact.x+r, contact.y-r))
                    activeDroneContacts.closeSubpath()
                }
            case .fighter:
                let r = 6.0
                fighterContacts.move(to: point(contact.x, contact.y+r))
                fighterContacts.addLine(to: point(contact.x+r, contact.y-r))
                fighterContacts.addLine(to: point(contact.x, contact.y-r*0.3))
                fighterContacts.addLine(to: point(contact.x-r, contact.y-r))
                fighterContacts.closeSubpath()
            case .tank, .apc:
                let r = foe.kind == .apc ? 3.8 : 3.2
                enemyContacts.addRect(CGRect(x: contact.x-r, y: contact.y-r,
                                             width: r*2, height: r*2))
            }
        }
        // Cluster non-attacking drone contacts into coherent squad markers.
        // Buildings and ground vehicles stay individually visible.
        let passiveDrones = enemies.filter { foe in
            guard foe.kind == .drone else { return false }
            let index = max(0, Int((foe.droneSeed / 1.618).rounded()))
            return !AirEncounterDirector.isAttacking(
                droneIndex: index, elapsed: droneAttackClock) ||
                foe.droneDisrupted > 0
        }.map(\.center)
        for cluster in TacticalRadarGeometry.droneClusters(passiveDrones) {
            guard let contact = radarPoint(cluster.center) else { continue }
            let r = cluster.count > 3 ? 3.1 : 2.1
            droneContacts.addEllipse(in: CGRect(
                x: contact.x-r, y: contact.y-r,
                width: r*2, height: r*2))
            if cluster.count > 3 {
                let ring = r + 2.3
                droneContacts.addEllipse(in: CGRect(
                    x: contact.x-ring, y: contact.y-ring,
                    width: ring*2, height: ring*2))
            }
        }
        let tacticalTarget = targetTelemetry()
        if let target = tacticalTarget,
            let contact = radarPoint(target.position) {
            let radius = 8.0
            for n in 0..<4 {
                let angle = Double(n) * .pi / 2 + .pi / 4
                let a = point(contact.x + cos(angle) * radius,
                              contact.y + sin(angle) * radius)
                let b = point(contact.x + cos(angle + 0.52) * radius,
                              contact.y + sin(angle + 0.52) * radius)
                segment(focusedTarget, a, b)
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
        radarHunterContacts.path = hunterContacts
        radarSaucerContacts.path = saucerContacts
        radarDroneContacts.path = droneContacts
        radarActiveDrones.path = activeDroneContacts
        radarTargetCue.path = focusedTarget
        if modernHUD, let selected = tacticalTarget,
            let location = radarPoint(selected.position) {
            let targeting = CGMutablePath()
            let origin = point(radarX, radarY)
            segment(targeting, origin, location)
            radarTargetLine.path = targeting
        } else {
            radarTargetLine.path = nil
        }
        radarTargetCue.strokeColor = tacticalTarget?.clearShot == false
            ? NSColor(calibratedRed: 1, green: 0.64, blue: 0.22, alpha: 1)
            : NSColor(calibratedRed: 0.45, green: 1, blue: 0.69, alpha: 1)
        radarFighterContacts.path = fighterContacts
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
            shieldBorder.glowWidth = displayMode != .classic ? 9.0 : 3.0
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
            String(format: "TGT %03.0f  AIM %+05.1f°  %@",
                   $0.range, $0.error * 180 / .pi,
                   $0.ground ? ($0.clearShot ? "CLEAR" : "COVER") : "AIR")
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
            // Modern uses the dedicated correctly fitted warning panel;
            // never draw the old loose label on top of its frame.
            warning.text = modernHUD ? "" :
                String(format: "⚠  ENEMY PROXIMITY  %.0f", distance)
        } else {
            warning.position = modernHUD ? point(w / 2, c.horizon + 100) : warning.position
            warning.fontSize = 12
            warning.fontColor = accent
            warning.alpha = 1
            warning.text = target.map {
                guard abs($0.error) < 0.055 && $0.range < 68 else { return "" }
                return $0.clearShot ? "TARGET ALIGNED" : "TARGET IN COVER"
            } ?? (pendingWave > 0 ? "AREA SECURE" : "")
        }

        let modeName = displayMode == .classic ? "CLASSIC CRT" : (displayMode == .cockpitV53 ? "APPROVED COCKPIT V5.3" : "ENHANCED VECTOR")
        message.position = point(w / 2, modernHUD ? 16 : 47)
        message.fontSize = 11
        message.isHidden = modernHUD && !showDetailedTelemetry
        if showDetailedTelemetry {
            message.text = String(format: "FPS %.0f  |  POSITION %+.1f, %+.1f  |  ENEMIES %d  |  SHELLS %d  |  [T] MINIMIZE",
                                  observedFPS, tankPosition.x, tankPosition.z, enemies.count, shells.count)
        } else {
            message.text = modeName + "   //   [E] CHAFF   //   [T] DIAGNOSTICS"
        }
        message.fontColor = shieldDuration > 0 ? green : accent

        let legacyTexts: [SKLabelNode] = [
            midHUD, rightHUD, telemetryLeftHeading, telemetryRightHeading,
            telemetryLeftDetail, telemetryLeftFootnote, telemetryCoordinates,
            telemetryRightDetail, telemetryRightFootnote, telemetryAmmo
        ]
        for label in legacyTexts { label.isHidden = modernHUD }
        for label in modernUpperText { label.isHidden = !modernHUD }
        for shape in [modernUpperBands, modernUpperDividers,
                      modernUpperIcons, modernOrangeCorners] {
            shape.isHidden = !modernHUD
        }
        if modernHUD {
            // Preserve the compact lower dashboard/compass from v3.7.
            // All premium instrumentation stays TOP-mounted in Modern.
            renderModernCockpit(
                width: w, height: h, bankWidth: bankWidth,
                leftX: leftX, rightX: rightX, radarX: radarX,
                rearX: rearX, radarPanelWidth: radarPanelWidth,
                rearPanelWidth: rearPanelWidth, topHeight: panelHeight)
            renderModernUpperHUD(width: w, height: h,
                                 leftCenter: leftCenterX, rightCenter: rightCenterX,
                                 bankWidth: bankWidth, panelHeight: panelHeight)
            renderCommandCockpitShell(
                width: w, height: h,
                bankWidth: bankWidth,
                radarWidth: radarPanelWidth,
                rearWidth: rearPanelWidth,
                gap: panelGap, margin: outerMargin)
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
            subtitle.text = wave > 1
                ? "FULL AMMO  //  PRESS ANY KEY"
                : "PRESS ANY KEY TO BEGIN"
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


/// Deep procedural combat transients with short noise attacks and low-frequency
/// body. Generated in memory to avoid packaging or changing existing sounds.
private final class TankCombatAudio {
    enum Kind: Int { case cannon = 0, impact = 1, explosion = 2 }
    private var players: [AVAudioPlayer?] = [nil, nil, nil]

    init() {
        for type in [Kind.cannon, .impact, .explosion] {
            let index = type.rawValue
            players[index] = try? AVAudioPlayer(data: Self.makeWAV(type))
            players[index]?.prepareToPlay()
            players[index]?.volume = type == .impact ? 0.48 : 0.72
        }
    }

    func play(_ kind: Kind, enabled: Bool) {
        guard enabled, let player = players[kind.rawValue] else { return }
        player.stop()
        player.currentTime = 0
        player.play()
    }

    private static func makeWAV(_ kind: Kind) -> Data {
        let rate = 22_050
        let duration: Double = kind == .cannon ? 0.48 :
            (kind == .impact ? 0.26 : 0.88)
        let count = Int(Double(rate) * duration)
        var data = Data(capacity: 44 + count * 2)
        func put16(_ n: UInt16) {
            data.append(UInt8(truncatingIfNeeded: n))
            data.append(UInt8(truncatingIfNeeded: n >> 8))
        }
        func put32(_ n: UInt32) {
            put16(UInt16(truncatingIfNeeded: n))
            put16(UInt16(truncatingIfNeeded: n >> 16))
        }
        data.append(contentsOf: [82,73,70,70])
        put32(UInt32(36 + count * 2))
        data.append(contentsOf: [87,65,86,69,102,109,116,32])
        put32(16)
        put16(1)
        put16(1)
        put32(UInt32(rate))
        put32(UInt32(rate * 2))
        put16(2)
        put16(16)
        data.append(contentsOf: [100,97,116,97])
        put32(UInt32(count * 2))

        var seed: UInt32 = 0xC4D7_19B1 &+ UInt32(kind.rawValue)
        var bassPhase = 0.0
        var filtered = 0.0
        for i in 0..<count {
            let t = Double(i) / Double(rate)
            let progress = t / duration
            seed = 1_664_525 &* seed &+ 1_013_904_223
            let white = Double((seed >> 10) & 0xFFFF) / 32_767.5 - 1
            filtered = 0.90 * filtered + 0.10 * white
            let frequency: Double
            let noiseWeight: Double
            let decay: Double
            switch kind {
            case .cannon:
                frequency = 93 - 58 * progress
                noiseWeight = 0.48
                decay = exp(-t * 7.8)
            case .impact:
                frequency = 142 - 66 * progress
                noiseWeight = 0.68
                decay = exp(-t * 14)
            case .explosion:
                frequency = 78 - 44 * progress
                noiseWeight = 0.75
                decay = exp(-t * 4.5)
            }
            bassPhase += 2 * .pi * frequency / Double(rate)
            let low = sin(bassPhase) + 0.30 * sin(bassPhase * 0.5)
            let transient = white * exp(-t * 85) * 0.62
            let body = (low * (1 - noiseWeight) + filtered * noiseWeight) * decay
            let tail = kind == .explosion
                ? 0.12 * filtered * sin(t * 45) * exp(-t * 3.4) : 0
            let envelope = min(1, t * 850) * min(1, (duration - t) * 130)
            let sample = max(-1, min(1, (transient + body + tail) * envelope * 0.88))
            put16(UInt16(bitPattern: Int16((sample * 32767).rounded())))
        }
        return data
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
