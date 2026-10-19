import SwiftUI
import AppKit
import ServiceManagement

/// Preferences: promotion rules, history limits, ignored apps, paste behavior, hotkey and login item.
struct SettingsView: View {
    @AppStorage(Prefs.Key.threshold) private var threshold = 3
    @AppStorage(Prefs.Key.historySize) private var historySize = 200
    @AppStorage(Prefs.Key.retentionDays) private var retentionDays = 30
    @AppStorage(Prefs.Key.pasteImmediately) private var pasteImmediately = true
    @AppStorage(Prefs.Key.ignoredApps) private var ignoredRaw = Prefs.defaultIgnoredApps
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var trusted = Paster.isTrusted
    @State private var newBundleID = ""
    private let recheck = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var ignoredApps: [String] {
        ignoredRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        Form {
            Section("Frequent") {
                Stepper("Promote after \(threshold) uses", value: $threshold, in: 2...20)
                Text("Items copied or pasted this many times move to Frequent and never expire (up to \(ClipStore.frequentCap)).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Recent History") {
                Picker("Keep up to", selection: $historySize) {
                    ForEach([50, 100, 200, 500, 1000], id: \.self) { Text("\($0) items").tag($0) }
                }
                Picker("Remove items older than", selection: $retentionDays) {
                    Text("1 day").tag(1)
                    Text("1 week").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("Never").tag(0)
                }
                Button("Clear Recent History", role: .destructive) { ClipStore.shared.clearRecent() }
            }

            Section("Paste") {
                Picker("When choosing a clip", selection: $pasteImmediately) {
                    Text("Paste immediately").tag(true)
                    Text("Copy only").tag(false)
                }
                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    Text(trusted ? "Accessibility access granted." : "Accessibility access is needed to paste; until then clips are copied only.")
                        .font(.caption)
                    Spacer()
                    if !trusted {
                        Button("Grant…") { Paster.requestAccessibility() }
                        Button("Open Settings") { Paster.openAccessibilitySettings() }
                    }
                }
            }

            Section("Ignored Apps") {
                ForEach(ignoredApps, id: \.self) { bundleID in
                    HStack {
                        Text(bundleID).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button { setIgnored(ignoredApps.filter { $0 != bundleID }) } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Bundle identifier", text: $newBundleID)
                        .onSubmit(addTypedBundleID)
                    Button("Add", action: addTypedBundleID).disabled(newBundleID.isEmpty)
                    Menu("Running App") {
                        ForEach(runningApps, id: \.self) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                                if let id = app.bundleIdentifier { addIgnored(id) }
                            }
                        }
                    }.fixedSize()
                }
            }

            Section("General") {
                LabeledContent("Open popup hotkey") { HotkeyRecorder() }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in updateLoginItem(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                HStack {
                    Text("Your clips are stored only on this Mac.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Support / Donate ❤️") { AppDelegate.openDonationPage() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 620)
        .onChange(of: threshold) { ClipStore.shared.maintain() }
        .onChange(of: historySize) { ClipStore.shared.maintain() }
        .onChange(of: retentionDays) { ClipStore.shared.maintain() }
        .onReceive(recheck) { _ in trusted = Paster.isTrusted }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0 != .current }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func addTypedBundleID() {
        addIgnored(newBundleID.trimmingCharacters(in: .whitespaces))
        newBundleID = ""
    }

    private func addIgnored(_ bundleID: String) {
        guard !bundleID.isEmpty, !ignoredApps.contains(bundleID) else { return }
        setIgnored(ignoredApps + [bundleID])
    }

    private func setIgnored(_ list: [String]) {
        ignoredRaw = list.joined(separator: "\n")
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Click-to-record control that captures a modifier+key combination for the global hotkey.
struct HotkeyRecorder: View {
    @AppStorage(Prefs.Key.hotkeyName) private var name = "⌘⇧V"
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Type shortcut…" : name) {
            recording ? stop() : start()
        }
        .frame(minWidth: 110)
        .onDisappear { if recording { stop() } }
    }

    private func start() {
        recording = true
        HotKeyManager.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }   // Escape cancels
            let (mods, symbols) = HotKeyManager.carbonModifiers(event.modifierFlags)
            let needsModifier = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            guard !needsModifier, let key = event.charactersIgnoringModifiers?.uppercased(), !key.isEmpty else {
                NSSound.beep()
                return nil
            }
            let defaults = UserDefaults.standard
            defaults.set(Int(event.keyCode), forKey: Prefs.Key.hotkeyCode)
            defaults.set(Int(mods), forKey: Prefs.Key.hotkeyMods)
            name = symbols + (key == " " ? "Space" : key)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        HotKeyManager.shared.registerFromDefaults()
    }
}
