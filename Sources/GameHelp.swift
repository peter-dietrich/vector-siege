import AppKit
import SwiftUI

// Native, entirely offline help book. This does not intercept gameplay keys,
// mutate saves, or require a browser, internet connection or account.
private struct HelpRow: Identifiable {
    let id = UUID()
    let key: String
    let action: String
}
private enum HelpPage: String, CaseIterable {
    case overview, controls, progress
    var title: String {
        switch self {
        case .overview: return "How to Play"
        case .controls: return "Controls & Shortcuts"
        case .progress: return "Scores & Saving"
        }
    }
}

private enum GameHelpContent {
    static let title = "Vector Siege"
    static let tagline = "Tank combat — command your terrain"
    static let overview = "Choose a landscape, display mode, and threat level. Defend your tank against armored enemies and airborne threats. Use the dashboard telemetry for rounds, shield, heading, and threat indicators."
    static let progress = "Save Game records a local snapshot when a game is running. Resume loads previously saved slots. Custom Game presets and selected difficulty remain independent of the launcher and are not uploaded."
    static let controls: [HelpRow] = [
        HelpRow(key: "Return / any key", action: "Deploy, then start the next level at the level banner."),
        HelpRow(key: "WASD or arrow keys", action: "Drive and turn."),
        HelpRow(key: "I/O/K/L", action: "Independent tread controls for pivoting or driving."),
        HelpRow(key: "Space", action: "Fire the cannon."),
        HelpRow(key: "Shift", action: "Activate the temporary shield."),
        HelpRow(key: "E", action: "Deploy anti-drone chaff."),
        HelpRow(key: "P", action: "Pause or resume."),
        HelpRow(key: "R", action: "Restart."),
        HelpRow(key: "Click battlefield", action: "Restore keyboard focus if needed.")
    ]
}

@MainActor
private enum GameHelpPanel {
    private static var helpWindow: NSWindow?

    static func show(_ page: HelpPage = .overview) {
        let view = HelpBookView(page: page)
        if let existing = helpWindow {
            existing.contentView = NSHostingView(rootView: view)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = GameHelpContent.title + " Help"
        window.minSize = NSSize(width: 530, height: 420)
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: view)
        helpWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct HelpBookView: View {
    @State var page: HelpPage
    private let amber = Color(red: 1, green: 0.67, blue: 0.29)
    private let navy = Color(red: 0.035, green: 0.045, blue: 0.09)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(GameHelpContent.title.uppercased())
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(.white)
                    Text(GameHelpContent.tagline)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(amber)
                }
                Spacer()
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(amber)
                    .accessibilityHidden(true)
            }
            .padding(24)
            Picker("Help topic", selection: $page) {
                ForEach(HelpPage.allCases, id: \.self) { topic in
                    Text(topic.title).tag(topic)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Text(page.title.uppercased())
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(amber)
                    switch page {
                    case .overview:
                        Text(GameHelpContent.overview)
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Open Controls & Shortcuts for the keys used by this game. The game window may need keyboard focus.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.65))
                    case .controls:
                        ForEach(GameHelpContent.controls) { row in
                            HStack(alignment: .top, spacing: 18) {
                                Text(row.key)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(amber)
                                    .frame(width: 210, alignment: .leading)
                                Text(row.action)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.86))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 5)
                            Divider().overlay(.white.opacity(0.08))
                        }
                    case .progress:
                        Text(GameHelpContent.progress)
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.86))
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("LOCAL FIRST  ·  NO ACCOUNT REQUIRED")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(amber)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 530, minHeight: 420)
        .background(navy)
        .preferredColorScheme(.dark)
    }
}

// Dock and About window identity are explicit: the app must not rely on
// LaunchServices caches or a system-generated About panel for its branding.
final class ArcadeIconAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL), icon.isValid else {
            NSLog("Fun City branding: AppIcon.icns is missing or invalid in %@", Bundle.main.bundlePath)
            return
        }
        NSApplication.shared.applicationIconImage = icon
    }
}

@MainActor
private enum GameAboutPanel {
    private static var aboutWindow: NSWindow?

    static func show() {
        if let window = aboutWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 365),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "About " + GameHelpContent.title
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: GameAboutView())
        aboutWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() {
        aboutWindow?.close()
    }
}

private struct GameAboutView: View {
    private let amber = Color(red: 1, green: 0.67, blue: 0.29)
    private let navy = Color(red: 0.035, green: 0.045, blue: 0.09)

    private var version: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return value.flatMap { $0.isEmpty ? nil : $0 } ?? "Development build"
    }
    private var build: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return value.flatMap { $0.isEmpty ? nil : $0 } ?? "—"
    }
    private var appIcon: NSImage? {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .center, spacing: 24) {
                Group {
                    if let image = appIcon {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    } else {
                        Image(systemName: "gamecontroller.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(amber)
                            .padding(24)
                    }
                }
                .frame(width: 140, height: 140)
                .accessibilityLabel(GameHelpContent.title + " application icon")

                VStack(alignment: .leading, spacing: 10) {
                    Text(GameHelpContent.title.uppercased())
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(GameHelpContent.tagline)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(amber)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Version " + version + "  •  Build " + build)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.82))
                    Text("A native Fun City Arcade experience for macOS")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(amber.opacity(0.3))
            HStack(spacing: 12) {
                Text("© 2026 Fun City Arcade")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
                Button("Help & Controls…") { GameHelpPanel.show(.overview) }
                    .buttonStyle(.bordered)
                Button("Close") { GameAboutPanel.close() }
                    .buttonStyle(.borderedProminent)
                    .tint(amber)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(25)
        .frame(width: 600, height: 365)
        .background(navy)
        .preferredColorScheme(.dark)
    }
}


struct GameHelpCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About " + GameHelpContent.title) { GameAboutPanel.show() }
        }
        CommandMenu("Game") {
            Button("How to Play…") { GameHelpPanel.show(.overview) }
            Button("Controls & Shortcuts…") { GameHelpPanel.show(.controls) }
            Divider()
            Button("Scores & Saving…") { GameHelpPanel.show(.progress) }
        }
        CommandGroup(replacing: .help) {
            Button(GameHelpContent.title + " Help") { GameHelpPanel.show(.overview) }
                .keyboardShortcut("?", modifiers: .command)
            Button("Keyboard Controls…") { GameHelpPanel.show(.controls) }
            Button("Saved Games & Scores…") { GameHelpPanel.show(.progress) }
        }
    }
}
