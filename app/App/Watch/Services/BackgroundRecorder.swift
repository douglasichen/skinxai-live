import Foundation
@preconcurrency import CoreMotion
import EczemaKit

/// All-day detection without keeping the app awake: `CMSensorRecorder` records the accelerometer
/// at 50 Hz for 12 hours at a time (re-armed whenever the app opens), and the recording is read
/// back in 5-minute slices and analysed with the personal model.
///
/// Every read has a budget: how much recording it may read and how long it may take. A background
/// refresh gets a few seconds of CPU from watchOS, so it reads at most 15 minutes of recording;
/// opening the app reads up to 2 hours (off the main thread). Whatever is left is read next time.
final class BackgroundRecorder: @unchecked Sendable {
    static let recordingLength: TimeInterval = 12 * 3600
    static let sliceLength: TimeInterval = 5 * 60
    /// Recorded samples become readable a few minutes after the fact.
    static let dataLatency: TimeInterval = 180
    /// CMSensorRecorder keeps recorded data for 3 days.
    static let retention: TimeInterval = 3 * 86_400

    struct Budget: Sendable {
        /// Most recording one run reads.
        var recording: TimeInterval
        /// Most wall-clock time one run takes.
        var seconds: TimeInterval

        static let backgroundRefresh = Budget(recording: 15 * 60, seconds: 2.5)
        static let appOpen = Budget(recording: 2 * 3600, seconds: 20)
    }

    /// Stops a run early (background task expiring, app leaving the screen).
    final class Cancel: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        func cancel() { lock.lock(); flag = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    }

    struct Result: Sendable {
        var episodes: [DetectedEpisode]
        /// Read up to here; the next run starts here.
        var through: Date
    }

    /// false in the simulator and on watches without the recorder.
    static var isAvailable: Bool { CMSensorRecorder.isAccelerometerRecordingAvailable() }
    static var isDenied: Bool {
        let s = CMSensorRecorder.authorizationStatus()
        return s == .denied || s == .restricted
    }

    private lazy var recorder = CMSensorRecorder()
    private let queue = DispatchQueue(label: "com.jackyzhong.eczematwin.recorder", qos: .utility)

    /// Starts a fresh 12-hour recording unless one started less than an hour ago.
    /// Returns the new end of the recording, or nil when nothing was (re)armed.
    func armIfNeeded(armedUntil: Date?, now: Date = Date()) -> Date? {
        guard Self.isAvailable, !Self.isDenied else { return nil }
        if let until = armedUntil, until.timeIntervalSince(now) > Self.recordingLength - 3600 { return nil }
        recorder.recordAccelerometer(forDuration: Self.recordingLength)
        return now.addingTimeInterval(Self.recordingLength)
    }

    /// Reads the recording from `from` on, within `budget`, and returns the episodes found and how
    /// far it got. nil when there is nothing new to read yet.
    func analyze(from start: Date, model: ScratchModel, budget: Budget, cancel: Cancel) async -> Result? {
        guard Self.isAvailable, !Self.isDenied else { return nil }
        let now = Date()
        let from = max(start, now.addingTimeInterval(-Self.retention))
        let end = min(now.addingTimeInterval(-Self.dataLatency), from.addingTimeInterval(budget.recording))
        guard end.timeIntervalSince(from) > 60 else { return nil }
        let recorder = self.recorder
        return await withCheckedContinuation { continuation in
            queue.async {
                let deadline = Date().addingTimeInterval(budget.seconds)
                let run = RecordingAnalysis.run(from: from, to: end, sliceLength: Self.sliceLength, model: model,
                                                outOfTime: { cancel.isCancelled || Date() >= deadline }) { sliceStart, sliceEnd, body in
                    autoreleasepool {
                        guard let list = recorder.accelerometerData(from: sliceStart, to: sliceEnd) else { return }
                        var iterator = NSFastEnumerationIterator(list)
                        while let item = iterator.next() {
                            guard let d = item as? CMRecordedAccelerometerData else { continue }
                            let sample = MotionSample(date: d.startDate, x: d.acceleration.x, y: d.acceleration.y, z: d.acceleration.z)
                            if !body(sample) { return }
                        }
                    }
                }
                continuation.resume(returning: Result(episodes: run.episodes, through: run.through))
            }
        }
    }
}
