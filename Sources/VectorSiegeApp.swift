import SwiftUI
import SpriteKit
import AppKit

@main
struct VectorSiegeApp: App {
    var body: some Scene {
        WindowGroup("Vector Siege") {
            SiegeWindow()
                .frame(minWidth: 900, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1240, height: 790)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

enum DisplayMode: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case modern = "Modern"
    case cockpitV53 = "Cockpit v5.3"
    var id: String { rawValue }
}

enum ThreatLevel: String, CaseIterable, Identifiable {
    case cadet = "Cadet"
    case veteran = "Veteran"
    case ace = "Ace"
    var id: String { rawValue }

    var enemyVelocity: Double {
        switch self { case .cadet: return 0.75; case .veteran: return 1.0; case .ace: return 1.3 }
    }
    var enemyAimError: Double {
        switch self { case .cadet: return 0.16; case .veteran: return 0.085; case .ace: return 0.025 }
    }
    var enemyReload: Double {
        switch self { case .cadet: return 1.50; case .veteran: return 1.0; case .ace: return 0.73 }
    }
}

final class SiegeSession: ObservableObject {
    @Published var displayMode: DisplayMode = .classic
    @Published var threatLevel: ThreatLevel = .veteran
    @Published var battlefieldEnvironment: BattlefieldEnvironment = .alpine
    @Published var startTime: SiegeStartTime = .day
    @Published var hoursPerWave: Double = 2.75
    @Published var timeDisplay = "12:00 / DAY"
    @Published var soundOn = true
    let scene = BattlefieldScene(size: CGSize(width: 1180, height: 690))

    init() {
        scene.onDisplayModeChange = { [weak self] mode in
            self?.displayMode = mode
        }
        scene.onTimeOfDayChange = { [weak self] hour in
            self?.timeDisplay = "\(SiegeDaylight.clock(at:hour)) / \(SiegeDaylight.period(at:hour))"
        }
    }

    func apply() {
        scene.displayMode = displayMode
        scene.battlefieldEnvironment = battlefieldEnvironment
        scene.setTimeOfDay(startTime, hoursPerWave:hoursPerWave, preview:false)
        scene.threatLevel = threatLevel
        scene.soundOn = soundOn
    }

    func applyPreset(_ preset: SiegePreset?) {
        scene.customRules = preset?.rules.validated()
        scene.activePresetID = preset?.id ?? ""
        apply()
        scene.restart()
    }

    @discardableResult
    func resume(_ snapshot: SiegeSnapshot) -> Bool {
        guard scene.restore(snapshot) else { return false }
        displayMode = scene.displayMode
        battlefieldEnvironment = scene.battlefieldEnvironment
        startTime = scene.startTime
        hoursPerWave = scene.hoursPerWave
        timeDisplay = "\(SiegeDaylight.clock(at:scene.timeOfDayHour)) / \(SiegeDaylight.period(at:scene.timeOfDayHour))"
        threatLevel = scene.threatLevel
        soundOn = scene.soundOn
        return true
    }
}

struct SiegeWindow: View {
    @StateObject private var session = SiegeSession()
    @State private var showCustomGame = false
    @State private var showSavedGames = false
    @State private var savedGames: [SiegeSaveSlot] = []
    @State private var saveMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("VECTOR SIEGE")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                Text("v2026.11.17f")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.gray)
                    .help("Source build identifier: v2026.11.17f — true 3D Tronzone battlefield preview")
                Spacer(minLength: 4)
                Picker("Display", selection: $session.displayMode) {
                    ForEach(DisplayMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 278)
                Picker("Level", selection: $session.threatLevel) {
                    ForEach(ThreatLevel.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 136)
                Toggle(isOn: $session.soundOn) {
                    Image(systemName: session.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                .toggleStyle(.button)
                .help("Sound effects")
                Button("Custom Game") { showCustomGame = true }
                    .buttonStyle(.bordered)
                Button("Save Game") {
                    if let snapshot = session.scene.makeSnapshot() {
                        let slot = SiegeGameStore.saveGame(snapshot)
                        saveMessage = "Saved: \(slot.name)"
                    } else {
                        saveMessage = "Start a game before saving."
                    }
                }
                .buttonStyle(.bordered)
                Button("Resume") {
                    savedGames = SiegeGameStore.saves()
                    showSavedGames = true
                }
                .buttonStyle(.bordered)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.scene.feedbackReport(), forType: .string)
                } label: {
                    Label("Copy Feedback", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .help("Copy a local playtest snapshot; no automatic uploads")
                Button {
                    session.scene.restart()
                } label: {
                    Label("New Game", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .frame(height: 58)
            .background(Color(red: 0.055, green: 0.085, blue: 0.07))

            HStack(spacing: 12) {
                Text("BATTLEFIELD")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.85))
                Picker("Environment", selection: $session.battlefieldEnvironment) {
                    ForEach(BattlefieldEnvironment.allCases) { environment in
                        Text(environment.rawValue).tag(environment)
                    }
                }
                .labelsHidden()
                .frame(width: 203)
                Text(session.battlefieldEnvironment == .alpine
                     ? "ALPINE VECTOR FRONTIER  /  ACTIVE WORLD GEOMETRY"
                     : "NEON CITADEL  /  ORIGINAL CITY GEOMETRY")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.53))
                Spacer(minLength: 4)
                Text("TIME")
                    .font(.system(size:10,weight:.bold,design:.monospaced))
                    .foregroundStyle(.orange.opacity(0.9))
                Picker("Starting time",selection:$session.startTime) {
                    ForEach(SiegeStartTime.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width:105)
                Text(session.timeDisplay)
                    .font(.system(size:10,weight:.bold,design:.monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.orange.opacity(0.92))
                    .frame(width:112,alignment:.leading)
                Text("WAVE +")
                    .font(.system(size:9,weight:.medium,design:.monospaced))
                    .foregroundStyle(.white.opacity(0.60))
                Picker("Hours per wave",selection:$session.hoursPerWave) {
                    ForEach([0.0,0.5,1.0,1.5,2.0,2.75,3.0,4.0,6.0,12.0],id:\.self) { hours in
                        Text(String(format:"%g h",hours)).tag(hours)
                    }
                }
                .labelsHidden()
                .frame(width:88)
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Color(red: 0.025, green: 0.055, blue: 0.041))

            BattlefieldView(scene: session.scene)
                .background(.black)
                .overlay(alignment: .bottom) {
                    if session.displayMode != .cockpitV53 {
                        HStack(spacing: 12) {
                            Text("↑↓ DRIVE   ←→ TURN   SPACE CANNON   F TWIN MG   SHIFT SHIELD   E CHAFF")
                            Spacer(minLength: 2)
                            Text("I/K + O/L TREADS   P PAUSE   RETURN START")
                        }
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.51))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color.black.opacity(0.8))
                    }
                }
        }
        .onAppear { session.apply() }
        .onChange(of: session.displayMode) { _ in session.apply() }
        .onChange(of: session.threatLevel) { _ in session.apply() }
        .onChange(of: session.startTime) { preset in
            // A restored save already set the exact clock; changing the
            // SwiftUI picker model during resume must NOT reset that clock.
            if session.scene.startTime != preset {
                session.scene.setTimeOfDay(preset,
                                           hoursPerWave:session.hoursPerWave)
            }
        }
        .onChange(of: session.hoursPerWave) { amount in
            session.scene.setTimeOfDay(session.startTime,
                                      hoursPerWave:amount,preview:false)
        }
        .onChange(of: session.battlefieldEnvironment) { environment in
            if session.scene.battlefieldEnvironment != environment {
                session.scene.battlefieldEnvironment = environment
                session.scene.restart()
            }
        }
        .onChange(of: session.soundOn) { _ in session.apply() }
        .sheet(isPresented: $showCustomGame) {
            SiegePresetEditor(
                currentPresetID: session.scene.activePresetID,
                currentRules: session.scene.customRules,
                apply: { session.applyPreset($0) }
            )
        }
        .sheet(isPresented: $showSavedGames) {
            VStack(alignment: .leading, spacing: 14) {
                Text("SAVED GAMES")
                    .font(.system(.title2, design: .monospaced).bold())
                Text("Restore a paused battle, including its ammunition, enemies and world state.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                if savedGames.isEmpty {
                    Text("No saved games yet. Start playing, then choose Save Game.")
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(savedGames) { slot in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(slot.name).font(.headline)
                                    Text(slot.savedAt.formatted())
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text("\(slot.snapshot.displayMode) · \(slot.snapshot.threatLevel)")
                                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Resume") {
                                    if session.resume(slot.snapshot) {
                                        showSavedGames = false
                                        saveMessage = "Battle restored. Press P to continue."
                                    } else {
                                        saveMessage = "Unable to restore that save."
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                Button("Delete", role: .destructive) {
                                    SiegeGameStore.deleteGame(id: slot.id)
                                    savedGames = SiegeGameStore.saves()
                                }
                            }
                            Divider()
                        }
                    }
                }
                Button("Close") { showSavedGames = false }
            }
            .padding(24)
            .frame(width: 560, height: 465)
        }
        .alert("VECTOR SIEGE", isPresented: Binding(
            get: { !saveMessage.isEmpty },
            set: { if !$0 { saveMessage = "" } })) {
            Button("OK") { saveMessage = "" }
        } message: {
            Text(saveMessage)
        }
    }
}

struct BattlefieldView: NSViewRepresentable {
    let scene: BattlefieldScene

    func makeNSView(context: Context) -> NSView {
        // Two native sibling renderers, not SceneKit inside SK3DNode.
        // SceneKit renders opaque 3D terrain with its own depth-stencil buffer;
        // transparent SpriteKit draws the approved cockpit, HUD and effects.
        let container = NSView(frame: CGRect(origin: .zero, size: scene.size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        if let world = scene.tronzoneRenderView {
            world.frame = container.bounds
            world.autoresizingMask = [.width, .height]
            container.addSubview(world)
        }
        let overlay = TankKeyView(frame: container.bounds)
        overlay.allowsTransparency = true
        overlay.ignoresSiblingOrder = true
        overlay.preferredFramesPerSecond = 60
        overlay.autoresizingMask = [.width, .height]
        overlay.presentScene(scene)
        overlay.sceneRef = scene
        container.addSubview(overlay)
        DispatchQueue.main.async {
            overlay.window?.makeFirstResponder(overlay)
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let overlay = nsView.subviews.compactMap({ $0 as? TankKeyView }).first else { return }
        if overlay.scene !== scene {
            overlay.presentScene(scene)
            overlay.sceneRef = scene
        }
        if let world = scene.tronzoneRenderView, world.superview !== nsView {
            world.removeFromSuperview()
            world.frame = nsView.bounds
            world.autoresizingMask = [.width, .height]
            nsView.addSubview(world, positioned: .below, relativeTo: overlay)
        }
    }
}

final class TankKeyView: SKView {
    weak var sceneRef: BattlefieldScene?
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        sceneRef?.pressed(event.keyCode, repeatEvent: event.isARepeat)
    }

    override func keyUp(with event: NSEvent) {
        sceneRef?.released(event.keyCode)
    }

    override func flagsChanged(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        sceneRef?.setShift(shift)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { DispatchQueue.main.async { self.window?.makeFirstResponder(self) } }
    }
}

// The same named-preset workflow as Vector Drift, with tank-specific controls.
struct SiegePresetEditor: View {
    let currentPresetID: String
    let currentRules: SiegeRules?
    let apply: (SiegePreset?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var presets: [SiegePreset] = []
    @State private var selectedID = ""
    @State private var presetName = "My Tank Arena"
    @State private var rules = SiegeRules()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CUSTOM GAME")
                .font(.system(.title2, design: .monospaced).bold())
            Text("Customize gameplay, save named presets, and launch a new battle.")
                .font(.callout).foregroundStyle(.secondary)

            HStack {
                Picker("Saved preset", selection: $selectedID) {
                    Text("New preset").tag("")
                    ForEach(presets) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                .onChange(of: selectedID) { id in
                    if let found = presets.first(where: { $0.id == id }) {
                        rules = found.rules
                        presetName = found.name
                    }
                }
                Button("New") {
                    selectedID = ""
                    presetName = "My Tank Arena"
                    rules = SiegeRules()
                }
            }
            TextField("Preset name", text: $presetName)

            Form {
                Section("Cannon and ammunition") {
                    Stepper("Rounds per game: \(rules.ammoCapacity)",
                            value: $rules.ammoCapacity, in: 1...200)
                    HStack {
                        Text("Reload time")
                        Slider(value: $rules.reloadSeconds, in: 0.2...6, step: 0.1)
                        Text(String(format: "%.1f s", rules.reloadSeconds))
                            .monospacedDigit().frame(width: 56)
                    }
                    HStack {
                        Text("Projectile lifetime")
                        Slider(value: $rules.projectileLifetime, in: 0.5...5, step: 0.1)
                        Text(String(format: "%.1f s", rules.projectileLifetime))
                            .monospacedDigit().frame(width: 56)
                    }
                }
                Section("Shield and survivability") {
                    Stepper("Starting lives: \(rules.startingLives)",
                            value: $rules.startingLives, in: 1...12)
                    HStack {
                        Text("Shield duration")
                        Slider(value: $rules.shieldDuration, in: 1...20, step: 0.5)
                        Text(String(format: "%.1f s", rules.shieldDuration))
                            .monospacedDigit().frame(width: 56)
                    }
                    HStack {
                        Text("Shield recharge")
                        Slider(value: $rules.shieldCooldown, in: 0...45, step: 0.5)
                        Text(String(format: "%.1f s", rules.shieldCooldown))
                            .monospacedDigit().frame(width: 56)
                    }
                }
                Section("Enemies and waves") {
                    Stepper("Enemies in first wave: \(rules.startingEnemies)",
                            value: $rules.startingEnemies, in: 1...12)
                    Stepper("Additional enemies per wave: \(rules.extraEnemiesPerWave)",
                            value: $rules.extraEnemiesPerWave, in: 0...4)
                    Stepper("Maximum simultaneous enemies: \(rules.maxEnemies)",
                            value: $rules.maxEnemies, in: 1...16)
                    HStack {
                        Text("Enemy speed")
                        Slider(value: $rules.enemySpeed, in: 0.25...2.5, step: 0.05)
                        Text(String(format: "%.2f×", rules.enemySpeed)).frame(width: 56)
                    }
                    HStack {
                        Text("Enemy fire rate")
                        Slider(value: $rules.enemyReload, in: 0.4...3.0, step: 0.1)
                        Text(String(format: "%.1f×", rules.enemyReload)).frame(width: 56)
                    }
                    HStack {
                        Text("Enemy accuracy")
                        Slider(value: $rules.enemyAccuracy, in: 0.25...3.0, step: 0.05)
                        Text(String(format: "%.2f×", rules.enemyAccuracy)).frame(width: 56)
                    }
                    Toggle("Enable hunter tanks", isOn: $rules.huntersEnabled)
                    Toggle("Enable flying saucers", isOn: $rules.saucersEnabled)
                }
                Section("Battlefield") {
                    Stepper("City structures: \(rules.obstacleCount)",
                            value: $rules.obstacleCount, in: 0...120)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Delete preset", role: .destructive) {
                    guard !selectedID.isEmpty else { return }
                    let deleted = selectedID
                    SiegeGameStore.deletePreset(id: deleted)
                    presets = SiegeGameStore.presets()
                    selectedID = ""
                    presetName = "My Tank Arena"
                    rules = SiegeRules()
                    if currentPresetID == deleted { apply(nil) }
                }
                .disabled(selectedID.isEmpty)
                Spacer()
                Button("Built-in rules") {
                    apply(nil)
                    dismiss()
                }
                Button("Save & Start Custom Game") {
                    let trimmed = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let preset = SiegePreset(
                        id: selectedID.isEmpty ? UUID().uuidString : selectedID,
                        name: trimmed.isEmpty ? "My Tank Arena" : trimmed,
                        rules: rules.validated())
                    SiegeGameStore.savePreset(preset)
                    apply(preset)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 690, height: 730)
        .onAppear {
            presets = SiegeGameStore.presets()
            if let preset = SiegeGameStore.preset(id: currentPresetID) {
                selectedID = preset.id
                presetName = preset.name
                rules = preset.rules
            } else if let currentRules {
                rules = currentRules
            }
        }
    }
}
