import Foundation
import EczemaKit

/// Bookkeeping kept next to the episodes (`state.json`).
struct WatchBookkeeping: Codable, Sendable {
    /// Episodes already handed to WatchConnectivity.
    var sentIDs: Set<UUID> = []
    /// Recorded accelerometer data is analysed up to here.
    var analyzedThrough: Date?
    /// The current CMSensorRecorder recording runs until here.
    var recorderArmedUntil: Date?
    /// Window features of recent episodes, so a late answer can still teach the model.
    var evidence: [String: [WindowFeatures]] = [:]
    var lastSentAt: Date?
}

/// Local persistence on the watch: real episodes (`episodes.json`), the personal model
/// (`model.json`) and bookkeeping (`state.json`), all in Application Support.
/// Demo and simulated episodes are never written here.
///
/// Changes are kept in memory at once and saved shortly after, in one batch: the JSON is encoded
/// and written on a background queue, never on the main actor. `flush()` saves right away (the
/// background refresh calls it before it tells watchOS it is done).
@MainActor
final class WatchStore {
    private(set) var episodes: [ScratchEpisode] = []
    private(set) var model = ScratchModel()
    private(set) var book = WatchBookkeeping()

    /// Keep two weeks of episodes on the watch.
    private let retention: TimeInterval = 14 * 86_400
    /// Evidence is kept for this many recent episodes.
    private let evidenceLimit = 40
    private let disk: StoreDisk
    private var dirty: Set<StoreDisk.File> = []
    private var saveTask: Task<Void, Never>?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        disk = StoreDisk(dir: base.appendingPathComponent("EczemaTwin", isDirectory: true))
        episodes = disk.read([ScratchEpisode].self, .episodes) ?? []
        model = disk.read(ScratchModel.self, .model) ?? ScratchModel()
        book = disk.read(WatchBookkeeping.self, .book) ?? WatchBookkeeping()
        prune()
    }

    // MARK: - Episodes

    /// Adds real episodes, skipping any that overlap one we already have (live and recorded data
    /// can cover the same minutes). Returns the ones actually added.
    @discardableResult
    func add(_ new: [ScratchEpisode]) -> [ScratchEpisode] {
        var added: [ScratchEpisode] = []
        for e in new where e.source != .demo {
            let overlaps = episodes.contains { $0.id == e.id || ($0.start < e.end && e.start < $0.end) }
            if !overlaps { episodes.append(e); added.append(e) }
        }
        if !added.isEmpty {
            episodes.sort { $0.start < $1.start }
            markDirty(.episodes)
        }
        return added
    }

    /// One run of the all-day recorder: its episodes, their evidence and how far it read, saved
    /// together. Returns the episodes actually added.
    @discardableResult
    func addRecorded(_ found: [DetectedEpisode], analyzedThrough: Date) -> [ScratchEpisode] {
        let added = add(found.map(\.episode))
        let ids = Set(added.map(\.id))
        for d in found where ids.contains(d.id) { book.evidence[d.id.uuidString] = d.windows }
        trimEvidence()
        book.analyzedThrough = analyzedThrough
        markDirty(.book)
        return added
    }

    func episode(_ id: UUID) -> ScratchEpisode? { episodes.first { $0.id == id } }

    func setLabel(_ label: EpisodeLabel, for id: UUID) {
        guard let i = episodes.firstIndex(where: { $0.id == id }) else { return }
        episodes[i].label = label
        markDirty(.episodes)
    }

    /// Real episodes that still have to go to the iPhone (rejected ones never go).
    func unsent(excluding id: UUID? = nil) -> [ScratchEpisode] {
        episodes.filter { $0.label != .rejected && !book.sentIDs.contains($0.id) && $0.id != id }
    }

    func markSent(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        book.sentIDs.formUnion(ids)
        book.lastSentAt = Date()
        markDirty(.book)
    }

    func markUnsent(_ ids: [UUID]) {
        book.sentIDs.subtract(ids)
        markDirty(.book)
    }

    /// Something else (demo-story episodes) went to the iPhone just now.
    func noteSent() {
        book.lastSentAt = Date()
        markDirty(.book)
    }

    // MARK: - Model and evidence

    func setModel(_ m: ScratchModel) {
        model = m
        markDirty(.model)
    }

    func setEvidence(_ windows: [WindowFeatures], for id: UUID) {
        book.evidence[id.uuidString] = windows
        trimEvidence(keeping: id)
        markDirty(.book)
    }

    func evidence(for id: UUID) -> [WindowFeatures]? { book.evidence[id.uuidString] }

    private func trimEvidence(keeping id: UUID? = nil) {
        guard book.evidence.count > evidenceLimit else { return }
        // Forget the oldest evidence.
        let keep = Set(episodes.suffix(evidenceLimit).map(\.id.uuidString))
        book.evidence = book.evidence.filter { keep.contains($0.key) || $0.key == id?.uuidString }
    }

    // MARK: - Recorder bookkeeping

    func setRecorderArmedUntil(_ date: Date) {
        book.recorderArmedUntil = date
        markDirty(.book)
    }

    // MARK: - Saving

    /// Writes every pending change now (and waits until it is on disk).
    func flush() async {
        saveTask?.cancel()
        saveTask = nil
        guard !dirty.isEmpty else { return }
        let files = dirty
        dirty.removeAll()
        await disk.write(episodes: files.contains(.episodes) ? episodes : nil,
                         model: files.contains(.model) ? model : nil,
                         book: files.contains(.book) ? book : nil)
    }

    /// Changes made close together (an answer, a batch of recorded episodes) share one save.
    private func markDirty(_ file: StoreDisk.File) {
        dirty.insert(file)
        guard saveTask == nil else { return }
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            self.saveTask = nil
            await self.flush()
        }
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-retention)
        let kept = episodes.filter { $0.end >= cutoff }
        guard kept.count != episodes.count else { return }
        let dropped = Set(episodes.map(\.id)).subtracting(kept.map(\.id))
        episodes = kept
        book.sentIDs.subtract(dropped)
        markDirty(.episodes)
        markDirty(.book)
    }
}

/// The files, read once at launch and written on a serial background queue (in order, so the
/// newest snapshot always lands last).
final class StoreDisk: @unchecked Sendable {
    enum File: String, CaseIterable {
        case episodes = "episodes.json", model = "model.json", book = "state.json"
    }

    private let dir: URL
    private let queue = DispatchQueue(label: "com.jackyzhong.eczematwin.store", qos: .utility)

    init(dir: URL) {
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func read<T: Decodable>(_ type: T.Type, _ file: File) -> T? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(file.rawValue)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func write(episodes: [ScratchEpisode]?, model: ScratchModel?, book: WatchBookkeeping?) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                func save<T: Encodable>(_ value: T?, _ file: File) {
                    guard let value, let data = try? encoder.encode(value) else { return }
                    try? data.write(to: self.dir.appendingPathComponent(file.rawValue), options: [.atomic])
                }
                save(episodes, .episodes)
                save(model, .model)
                save(book, .book)
                done.resume()
            }
        }
    }
}
