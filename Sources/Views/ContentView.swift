import SwiftUI
import AppKit

/// Drives the popup: search filtering, keyboard selection and paste actions.
@MainActor
final class PopupController: ObservableObject {
    @Published var query = "" { didSet { selection = flat.first?.id } }
    @Published var selection: UUID?
    weak var window: NSWindow?
    private var keyMonitor: Any?
    private let store = ClipStore.shared

    var frequent: [Clip] { store.frequent.filter(matches) }
    var recent: [Clip] { store.recent.filter(matches) }
    var flat: [Clip] { frequent + recent }

    private func matches(_ clip: Clip) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return clip.text.localizedCaseInsensitiveContains(q) || (clip.label ?? "").localizedCaseInsensitiveContains(q)
    }

    func reset() {
        query = ""
        selection = flat.first?.id
    }

    /// Arrow keys move the highlight, Return pastes, Escape closes — only for the popup window.
    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            switch Int(event.keyCode) {
            case 125: self.move(1); return nil
            case 126: self.move(-1); return nil
            case 36, 76: self.pasteSelection(); return nil
            case 53: self.window?.close(); return nil
            default: return event
            }
        }
    }

    private func move(_ delta: Int) {
        let items = flat
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selection } ?? -1
        selection = items[min(max(current + delta, 0), items.count - 1)].id
    }

    private func pasteSelection() {
        guard let clip = flat.first(where: { $0.id == selection }) ?? flat.first else { return }
        paste(clip)
    }

    func paste(_ clip: Clip) {
        Paster.shared.paste(clip, closing: window)
    }
}

/// The MenuBarExtra popup: search field, Frequent section, Recent section and a footer.
struct ContentView: View {
    @ObservedObject private var store = ClipStore.shared
    @StateObject private var controller = PopupController()
    @AppStorage(Prefs.Key.pasteImmediately) private var pasteImmediately = true
    @FocusState private var searchFocused: Bool
    @State private var renaming: Clip?
    @State private var renameText = ""
    @State private var trusted = Paster.isTrusted
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if store.clips.isEmpty {
                emptyState("Nothing copied yet", systemImage: "doc.on.clipboard",
                           detail: "Copy some text anywhere and it shows up here.")
            } else {
                list
            }
            if pasteImmediately && !trusted { accessibilityBanner }
            Divider()
            footer
        }
        .frame(width: 360, height: 460)
        .background(WindowAccessor { controller.window = $0 })
        .onAppear {
            controller.installKeyMonitor()
            controller.reset()
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard let window = note.object as? NSWindow, window === controller.window else { return }
            controller.reset()
            trusted = Paster.isTrusted
            searchFocused = true
        }
        .alert("Rename Clip", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Short label", text: $renameText)
            Button("Save") { if let clip = renaming { store.rename(clip.id, to: renameText) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Leave empty to remove the label.")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search clips", text: $controller.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !controller.query.isEmpty {
                Button { controller.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(10)
    }

    private var list: some View {
        let frequent = controller.frequent
        let recent = controller.recent
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    sectionHeader("Frequent", systemImage: "star.fill")
                    if frequent.isEmpty {
                        placeholder(controller.query.isEmpty ? "Items you reuse will appear here" : "No matches")
                    }
                    ForEach(frequent) { row($0, isFrequent: true) }
                    sectionHeader("Recent", systemImage: "clock").padding(.top, 6)
                    if recent.isEmpty {
                        placeholder(controller.query.isEmpty ? "Nothing copied yet" : "No matches")
                    }
                    ForEach(recent) { row($0, isFrequent: false) }
                }
                .padding(8)
            }
            .onChange(of: controller.selection) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private func row(_ clip: Clip, isFrequent: Bool) -> some View {
        ClipRow(clip: clip, isFrequent: isFrequent, isSelected: controller.selection == clip.id,
                onPaste: { controller.paste(clip) },
                onRename: { renameText = clip.label ?? ""; renaming = clip },
                onPin: { store.togglePin(clip.id) },
                onDemote: { store.demote(clip.id) },
                onDelete: { store.delete(clip.id) })
            .id(clip.id)
    }

    private var accessibilityBanner: some View {
        HStack {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            Text("Copy only: allow Accessibility to paste automatically.")
                .font(.caption)
            Spacer()
            Button("Allow…") { Paster.requestAccessibility() }.controlSize(.small)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
    }

    private var footer: some View {
        HStack {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: { Image(systemName: "gearshape") }
                .help("Settings")
            Button("Support / Donate ❤️") { AppDelegate.openDonationPage() }
            Spacer()
            Text("\(store.clips.count) clips").font(.caption).foregroundStyle(.secondary)
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .help("Quit ReuseRankClips")
        }
        .buttonStyle(.borderless)
        .padding(10)
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
    }

    private func emptyState(_ title: String, systemImage: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: systemImage).font(.system(size: 36)).foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary)
            Text("Items you reuse will appear here").font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// One clip in the list: optional label, three-line preview, use-count badge and actions.
struct ClipRow: View {
    let clip: Clip
    let isFrequent: Bool
    let isSelected: Bool
    let onPaste: () -> Void
    let onRename: () -> Void
    let onPin: () -> Void
    let onDemote: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let label = clip.label, clip.hasLabel {
                    Text(label).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                }
                Text(clip.preview)
                    .font(.system(size: 12))
                    .foregroundStyle(clip.hasLabel ? .secondary : .primary)
                    .lineLimit(3)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            if clip.pinned {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
            }
            Text("\(clip.count)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(isFrequent ? Color.orange.opacity(0.25) : Color.secondary.opacity(0.15)))
                .help("Used \(clip.count) times")
            Menu { actions } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : hovering ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onPaste)
        .onHover { hovering = $0 }
        .contextMenu { actions }
    }

    @ViewBuilder private var actions: some View {
        Button("Paste", action: onPaste)
        Button("Rename…", action: onRename)
        Button(clip.pinned ? "Unpin" : "Pin to Top", action: onPin)
        if isFrequent { Button("Demote to Recent", action: onDemote) }
        Divider()
        Button("Delete", role: .destructive, action: onDelete)
    }
}

/// Reports the hosting NSWindow so the controller can scope key handling and close the popup.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(nsView.window) }
    }
}
