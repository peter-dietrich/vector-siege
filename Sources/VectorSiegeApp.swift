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
    @Published var soundOn = true
    let scene = BattlefieldScene(size: CGSize(width: 1180, height: 690))

    init() {
        scene.onDisplayModeChange = { [weak self] mode in
            self?.displayMode = mode
        }
    }

    func apply() {
        scene.displayMode = displayMode
        scene.threatLevel = threatLevel
        scene.soundOn = soundOn
    }
}

struct SiegeWindow: View {
    @StateObject private var session = SiegeSession()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                HStack(spacing: 7) {
                    Image(systemName: "scope")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Color(red: 0.46, green: 1, blue: 0.56))
                    Text("VECTOR SIEGE")
                        .font(.system(size: 16, weight: .heavy, design: .monospaced))
                        .tracking(2.5)
                }
                Spacer(minLength: 4)
                Picker("Display", selection: $session.displayMode) {
                    ForEach(DisplayMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                Picker("Level", selection: $session.threatLevel) {
                    ForEach(ThreatLevel.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 136)
                Toggle(isOn: $session.soundOn) {
                    Image(systemName: session.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                .toggleStyle(.button)
                .help("Sound effects")
                Button {
                    session.scene.restart()
                } label: {
                    Label("New Game", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 22)
            .frame(height: 58)
            .background(Color(red: 0.055, green: 0.085, blue: 0.07))

            BattlefieldView(scene: session.scene)
                .background(.black)
                .overlay(alignment: .bottom) {
                    HStack(spacing: 12) {
                        Text("↑↓ DRIVE   ←→ TURN   SPACE FIRE   SHIFT SHIELD")
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
        .onAppear { session.apply() }
        .onChange(of: session.displayMode) { _ in session.apply() }
        .onChange(of: session.threatLevel) { _ in session.apply() }
        .onChange(of: session.soundOn) { _ in session.apply() }
    }
}

struct BattlefieldView: NSViewRepresentable {
    let scene: BattlefieldScene

    func makeNSView(context: Context) -> TankKeyView {
        let view = TankKeyView()
        view.allowsTransparency = false
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        view.presentScene(scene)
        view.sceneRef = scene
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: TankKeyView, context: Context) {
        if nsView.scene !== scene { nsView.presentScene(scene) }
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