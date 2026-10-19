import Foundation

/// Owns all clip records: dedupes captures, counts uses, promotes/demotes Frequent items,
/// expires Recent items and persists everything as JSON in Application Support.
@MainActor
final class ClipStore: ObservableObject {
    static let shared = ClipStore()
    static let frequentCap = 50

    @Published private(set) var clips: [Clip] = []

    private let fileURL: URL
    private let ioQueue = DispatchQueue(label: "com.turhe123.reuserankclips.persist", qos: .utility)
    private var pendingSave: DispatchWorkItem?

    init() {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("ReuseRankClips", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("clips.json")
        load()
        maintain()
    }

    // MARK: Sections

    var frequent: [Clip] {
        clips.filter { $0.pinned || $0.promoted }.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if a.count != b.count { return a.count > b.count }
            return a.lastUsed > b.lastUsed
        }
    }

    var recent: [Clip] {
        clips.filter { !$0.pinned && !$0.promoted }.sorted { $0.lastUsed > $1.lastUsed }
    }

    // MARK: Mutations

    /// Records an external copy. Identical (normalized) text increments the existing record.
    func capture(_ text: String, sourceApp: String?) {
        let key = ClipKey.hash(text)
        let now = Date()
        if let i = clips.firstIndex(where: { $0.key == key }) {
            clips[i].text = text
            clips[i].count += 1
            clips[i].lastUsed = now
            clips[i].sourceApp = sourceApp ?? clips[i].sourceApp
        } else {
            clips.append(Clip(key: key, text: text, count: 1, created: now, lastUsed: now, sourceApp: sourceApp))
        }
        maintain()
    }

    /// Counts a paste/copy made from inside the app.
    func recordUse(_ id: UUID) {
        guard let i = index(id) else { return }
        clips[i].count += 1
        clips[i].lastUsed = Date()
        maintain()
    }

    func rename(_ id: UUID, to label: String) {
        guard let i = index(id) else { return }
        let trimmed = String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        clips[i].label = trimmed.isEmpty ? nil : trimmed
        maintain()
    }

    func togglePin(_ id: UUID) {
        guard let i = index(id) else { return }
        clips[i].pinned.toggle()
        maintain()
    }

    func demote(_ id: UUID) {
        guard let i = index(id) else { return }
        demote(at: i)
        maintain()
    }

    func delete(_ id: UUID) {
        clips.removeAll { $0.id == id }
        maintain()
    }

    func clearRecent() {
        clips.removeAll { !$0.pinned && !$0.promoted }
        maintain()
    }

    /// Re-applies promotion, caps and expiry (also called when settings change), then saves.
    func maintain() {
        promote()
        prune()
        scheduleSave()
    }

    // MARK: Rules

    private func index(_ id: UUID) -> Int? { clips.firstIndex { $0.id == id } }

    private func demote(at i: Int) {
        clips[i].promoted = false
        clips[i].pinned = false
        clips[i].demotedAtCount = clips[i].count
    }

    private func promote() {
        let threshold = Prefs.threshold
        for i in clips.indices where !clips[i].promoted && clips[i].count - clips[i].demotedAtCount >= threshold {
            clips[i].promoted = true
        }
        let overflow = clips.filter { $0.pinned || $0.promoted }.count - Self.frequentCap
        guard overflow > 0 else { return }
        let victims = clips.indices
            .filter { clips[$0].promoted && !clips[$0].pinned }
            .sorted { clips[$0].lastUsed < clips[$1].lastUsed }
            .prefix(overflow)
        for i in victims { demote(at: i) }
    }

    private func prune() {
        let days = Prefs.retentionDays
        if days > 0 {
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            clips.removeAll { !$0.pinned && !$0.promoted && $0.lastUsed < cutoff }
        }
        let recentItems = recent
        if recentItems.count > Prefs.historySize {
            let drop = Set(recentItems.dropFirst(Prefs.historySize).map(\.id))
            clips.removeAll { drop.contains($0.id) }
        }
    }

    // MARK: Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            clips = try JSONDecoder().decode([Clip].self, from: data)
        } catch {
            // Corrupted store: keep a backup for the user and start fresh.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("clips.corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            clips = []
        }
    }

    /// Debounced write on a background queue so copy bursts never block the UI.
    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = clips
        let url = fileURL
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
        pendingSave = work
        ioQueue.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
}
