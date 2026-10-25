import Foundation

/// Reads a long recording (the watch's all-day `CMSensorRecorder` data) in pieces, within a time
/// budget, and picks up next time exactly where it stopped.
///
/// - The interval is read slice by slice; `outOfTime` is checked before every slice and every
///   `checkEvery` samples, so a run stops within a fraction of a second of its deadline.
/// - A bout of scratching is never split between two runs: when a run stops (deadline or end of
///   the data) while an episode, or a lone scratch window, is still open, `through` points at that
///   bout's first window and the next run reads it again whole. Only a bout that began where the
///   run began (longer than a whole run) is closed where the run stops, so every run moves on.
public enum RecordingAnalysis {
    public struct Result: Sendable {
        public var episodes: [DetectedEpisode]
        /// Read up to here: the next run starts here.
        public var through: Date
        /// false when the run stopped before `end` (out of time).
        public var finished: Bool
    }

    /// - Parameters:
    ///   - read: reads one slice `[from, to)` in time order, calling `body` for each sample; it
    ///     must stop as soon as `body` returns false. A slice without data calls `body` never.
    public static func run(from: Date, to end: Date, sliceLength: TimeInterval, model: ScratchModel,
                           config: DetectorConfig = .standard, checkEvery: Int = 1000,
                           outOfTime: @escaping () -> Bool,
                           read: (_ from: Date, _ to: Date, _ body: (MotionSample) -> Bool) -> Void) -> Result {
        let detector = ScratchDetector(model: model, config: config, source: .recorded)
        var found: [DetectedEpisode] = []
        var through = from
        var sliceStart = from
        var finished = true
        while sliceStart < end {
            if outOfTime() { finished = false; break }
            let sliceEnd = min(sliceStart.addingTimeInterval(max(1, sliceLength)), end)
            var count = 0
            var last: Date?
            var cut = false
            read(sliceStart, sliceEnd) { sample in
                count += 1
                if count % max(1, checkEvery) == 0, outOfTime() { cut = true; return false }
                found += detector.process(sample).episodes
                last = sample.date
                return true
            }
            if cut {
                // Next run starts just after the last sample read.
                through = last.map { $0.addingTimeInterval(0.001) } ?? sliceStart
                finished = false
                break
            }
            through = sliceEnd
            sliceStart = sliceEnd
        }
        if let pending = detector.pendingSince, pending > from.addingTimeInterval(1) {
            through = min(through, pending)
        } else {
            found += detector.finish().episodes
        }
        return Result(episodes: found, through: through, finished: finished)
    }
}
