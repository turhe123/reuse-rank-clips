import SwiftUI
import AppKit
import ApplicationServices

/// Entry point: a menu-bar-only app with a window-style popup and a Settings scene.
@main
struct ReuseRankClipsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        Prefs.registerDefaults()
    }

    var body: some Scene {
        MenuBarExtra("ReuseRankClips", systemImage: "star.square.on.square") {
            ContentView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

/// Boots the background services (clipboard polling, global hotkey) as soon as the app launches,
/// before the popup has ever been opened.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        _ = ClipStore.shared
        _ = Paster.shared
        PasteboardMonitor.shared.start()
        HotKeyManager.shared.onPress = { StatusItemToggler.toggle() }
        HotKeyManager.shared.registerFromDefaults()
        explainAccessibilityIfNeeded()
    }

    /// On first launch, explain why Accessibility is needed before triggering the system prompt.
    private func explainAccessibilityIfNeeded() {
        let defaults = UserDefaults.standard
        guard !AXIsProcessTrusted(), !defaults.bool(forKey: Prefs.Key.didExplainAX) else { return }
        defaults.set(true, forKey: Prefs.Key.didExplainAX)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Allow ReuseRankClips to paste for you?"
        alert.informativeText = """
        To paste a clip straight into the app you were using, ReuseRankClips sends a ⌘V keystroke. \
        macOS requires Accessibility permission for that. Without it, clips are copied to the clipboard \
        and you paste them yourself. You can change this any time in Settings.
        """
        alert.addButton(withTitle: "Grant Access…")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            Paster.requestAccessibility()
        }
    }

    static func openDonationPage() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}

/// Opens or closes the MenuBarExtra popup programmatically by clicking its status bar button.
enum StatusItemToggler {
    @MainActor
    static func toggle() {
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
            if let button = findButton(in: window.contentView) {
                button.performClick(nil)
                return
            }
        }
    }

    @MainActor
    private static func findButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton { return button }
        for sub in view.subviews {
            if let button = findButton(in: sub) { return button }
        }
        return nil
    }
}
