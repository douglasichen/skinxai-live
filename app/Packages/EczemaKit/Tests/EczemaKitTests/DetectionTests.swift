import Foundation
import Testing
@testable import EczemaKit

/// Scratch detection on synthetic wrist signals (SPEC §5): scratching is found, everyday motion
/// is ignored, faster scratching reads as a higher rate, and answers teach the personal model.
@Suite struct DetectionTests {
    static let t0: TimeInterval = 780_000_000      // an arbitrary absolute time (2025)

    // MARK: - Helpers

    private func signal(_ build: (inout SyntheticMotion) -> Void) -> [MotionSample] {
        var b = SyntheticMotion(start: Self.t0)
        build(&b)
        return b.samples
    }

    private func run(_ build: (inout SyntheticMotion) -> Void, model: ScratchModel = ScratchModel(),
                     source: EpisodeSource = .live) -> [DetectorEvent] {
        let detector = ScratchDetector(model: model, source: source)
        return detector.process(signal(build)) + detector.finish()
    }

    private func seconds(_ date: Date) -> Double { date.timeIntervalSinceReferenceDate - Self.t0 }

    // MARK: - Scratching is detected

    @Test func scratchIsDetected() throws {
        let events = run { $0.still(6); $0.scratch(12, hz: 4); $0.still(6) }
        let episodes = events.episodes
        #expect(episodes.count == 1)
        let e = try #require(episodes.first).episode
        #expect(abs(seconds(e.start) - 6) <= 1.6, "starts when the scratching starts")
        #expect(abs(seconds(e.end) - 18) <= 1.6, "ends when it stops")
        #expect(abs(e.meanHz - 4) < 0.3)
        #expect(e.intense == false)
        #expect(e.source == .live)
        // The start is announced right away (to buzz), with the same id as the finished episode.
        let start = try #require(events.starts.first)
        #expect(events.starts.count == 1)
        #expect(start.shouldAlert)
        #expect(start.id == e.id)
        #expect(seconds(start.start) < 9, "announced within seconds, not at the end")
        #expect(start.windows.count == 2)
    }

    @Test func scratchWindowsScoreHigh() {
        let windows = run { $0.scratch(12, hz: 4.5) }.windows
        #expect(windows.count >= 6)
        #expect(windows.dropFirst().allSatisfy { $0.isScratch && $0.probability > 0.9 })
        #expect(windows.dropFirst().allSatisfy { $0.features.periodicity > 0.8 && $0.features.inBand > 0.7 })
    }

    @Test func gentleScratchStillCounts() {
        let episodes = run { $0.still(3); $0.scratch(10, hz: 3.5, amplitude: 0.08); $0.still(3) }.episodes
        #expect(episodes.count == 1)
    }

    // MARK: - Everyday motion is ignored

    @Test func walkingIsIgnored() {
        let swinging = run { $0.walk(30) }
        #expect(swinging.episodes.isEmpty)
        #expect(swinging.windows.allSatisfy { $0.features.moving && $0.probability < 0.5 })
        // Hands in pockets: the 1.8 Hz step rhythm is the main motion — rhythmic, but too slow.
        let pockets = run { $0.walk(30, armSwing: 0.04) }
        #expect(pockets.episodes.isEmpty)
        #expect(pockets.windows.allSatisfy { $0.probability < 0.5 })
    }

    @Test func typingIsIgnored() {
        let events = run { $0.type(30) }
        #expect(events.episodes.isEmpty)
        #expect(events.starts.isEmpty)
        #expect(events.windows.contains { $0.features.moving }, "typing passes the movement gate; the model rejects it")
        #expect(events.windows.allSatisfy { $0.probability < 0.5 })
    }

    @Test func stillIsIgnored() {
        let events = run { $0.still(30) }
        #expect(events.episodes.isEmpty)
        #expect(events.windows.count == 19)
        #expect(events.windows.allSatisfy { !$0.features.moving && $0.probability == 0 })
    }

    @Test func rollOverIsIgnored() {
        let events = run { $0.still(5); $0.rollOver(); $0.still(5) }
        #expect(events.episodes.isEmpty)
        #expect(events.windows.contains { $0.features.moving && $0.features.strength > 0.2 }, "a big movement…")
        #expect(events.windows.allSatisfy { $0.probability < 0.5 }, "…but not a rhythm")
    }

    @Test func nightMixFindsOnlyTheScratching() {
        let events = run {
            $0.still(10); $0.rollOver(); $0.still(8)
            $0.scratch(9, hz: 4.2); $0.still(12)
            $0.type(10); $0.walk(10); $0.still(6)
            $0.scratch(7, hz: 5.4, amplitude: 0.65); $0.still(6)
        }
        let episodes = events.episodes.map(\.episode)
        #expect(episodes.count == 2)
        #expect(episodes.first.map { abs(seconds($0.start) - 19.6) < 2 } == true)
        #expect(episodes.last?.intense == true)
    }

    // MARK: - Rate and intensity

    @Test func fasterScratchReadsHigherHz() {
        let rates = [2.8, 4.0, 5.2, 6.5].map { hz in
            run { $0.still(3); $0.scratch(9, hz: hz); $0.still(3) }.episodes.first?.episode.meanHz ?? 0
        }
        for (measured, truth) in zip(rates, [2.8, 4.0, 5.2, 6.5]) { #expect(abs(measured - truth) < 0.35) }
        #expect(rates == rates.sorted() && Set(rates).count == rates.count, "strictly increasing: \(rates)")
    }

    @Test func intenseNeedsStrongMotion() {
        let strong = run { $0.scratch(8, hz: 4, amplitude: 0.6) }.episodes.first?.episode
        let normal = run { $0.scratch(8, hz: 4, amplitude: 0.25) }.episodes.first?.episode
        #expect(strong?.intense == true)
        #expect((strong?.meanRMS ?? 0) >= 0.35)
        #expect(normal?.intense == false)
    }

    // MARK: - Episode logic

    private func window(_ i: Int, _ scratch: Bool) -> WindowResult {
        let f = WindowFeatures(start: Self.t0 + Double(i) * 1.5, axisSD: [0.2, 0.05, 0.05], strength: 0.2, moving: true, axis: 0,
                               dominantHz: 4, periodicity: scratch ? 0.95 : 0.1, inBand: scratch ? 0.9 : 0.1, crossingHz: 4,
                               logStrength: 1, crossingScore: 1)
        return WindowResult(features: f, probability: scratch ? 0.95 : 0.05, isScratch: scratch)
    }

    private func track(_ pattern: String) -> [DetectorEvent] {
        var tracker = EpisodeTracker(config: .standard, source: .live)
        var events: [DetectorEvent] = []
        for (i, c) in pattern.enumerated() { events += tracker.feed(window(i, c == "S")) }
        return events + tracker.finish()
    }

    @Test func episodeNeedsTwoScratchWindowsWithOneGapAllowed() throws {
        #expect(track("NNSNNN").episodes.isEmpty, "one lone window is not an episode")
        #expect(track("SNNSNN").episodes.isEmpty, "a 2-window gap breaks the run")
        #expect(track("SS").episodes.count == 1)
        let gap = track("NSNSNN")
        #expect(gap.episodes.count == 1, "a 1-window gap is allowed")
        let e = try #require(gap.episodes.first)
        #expect(e.windows.count == 2)
        // Trimmed by half a hop at both ends: windows 1 and 3 cover 1.5 s ... 4.5 + 3 s.
        #expect(abs(seconds(e.episode.start) - (1.5 + 0.75)) < 1e-6)
        #expect(abs(seconds(e.episode.end) - (4.5 + 3 - 0.75)) < 1e-6)
        let two = track("SSSNSSNNSS")
        #expect(two.episodes.count == 2)
        #expect(two.episodes.first?.windows.count == 5)
        #expect(two.starts.count == 2)
    }

    @Test func buzzesAtMostOncePer45Seconds() {
        let close = run { $0.scratch(6, hz: 4); $0.still(15); $0.scratch(6, hz: 4); $0.still(3) }
        #expect(close.episodes.count == 2)
        #expect(close.starts.map(\.shouldAlert) == [true, false])
        let apart = run { $0.scratch(6, hz: 4); $0.still(50); $0.scratch(6, hz: 4); $0.still(3) }
        #expect(apart.starts.map(\.shouldAlert) == [true, true])
    }

    @Test func holeInTheDataEndsTheEpisode() {
        var a = SyntheticMotion(start: Self.t0)
        a.scratch(8, hz: 4)
        var b = SyntheticMotion(start: a.time + 5, seed: 9)
        b.scratch(8, hz: 4)
        let detector = ScratchDetector()
        let events = detector.process(a.samples + b.samples) + detector.finish()
        #expect(events.episodes.count == 2)
    }

    @Test func streamingMatchesBatch() {
        let samples = signal { $0.still(4); $0.scratch(10, hz: 4.4); $0.walk(8); $0.scratch(6, hz: 3.3); $0.still(4) }
        let batch = ScratchDetector.episodes(in: samples, model: ScratchModel(), source: .recorded).map(\.episode)
        let streaming = ScratchDetector(source: .recorded)
        var events: [DetectorEvent] = []
        var i = 0
        while i < samples.count {                       // odd-sized chunks, like sensor callbacks
            let chunk = samples[i..<min(samples.count, i + 37)]
            events += streaming.process(chunk)
            i += 37
        }
        events += streaming.finish()
        let streamed = events.episodes.map(\.episode)
        #expect(batch.count == 2)
        #expect(streamed.map(\.start) == batch.map(\.start))
        #expect(streamed.map(\.end) == batch.map(\.end))
        #expect(batch.allSatisfy { $0.source == .recorded })
    }

    // MARK: - Learning from Yes / No

    private func borderline() -> [WindowFeatures] {
        run { $0.scratch(9, hz: 2.6, amplitude: 0.05) }.windows.map(\.features).filter(\.moving)
    }

    private func meanP(_ m: ScratchModel, _ ws: [WindowFeatures]) -> Double {
        ws.map(m.probability).reduce(0, +) / Double(ws.count)
    }

    @Test func answersMoveTheProbability() {
        let windows = borderline()
        #expect(!windows.isEmpty)
        var m = ScratchModel()
        let start = meanP(m, windows)
        #expect(start > 0.3 && start < 0.95, "a borderline pattern: \(start)")
        m.learn(from: windows, scratching: false)
        let afterNo = meanP(m, windows)
        #expect(afterNo < start, "No lowers it: \(start) → \(afterNo)")
        m.learn(from: windows, scratching: true)
        m.learn(from: windows, scratching: true)
        let afterYes = meanP(m, windows)
        #expect(afterYes > afterNo, "Yes raises it: \(afterNo) → \(afterYes)")
        #expect(m.confirmedCount == 2 && m.rejectedCount == 1 && m.answerCount == 3)
        #expect(m.updatedAt != nil)
    }

    @Test func repeatedNoTeachesTheWatchToIgnoreAPattern() {
        let windows = borderline()
        var m = ScratchModel()
        #expect(run({ $0.scratch(9, hz: 2.6, amplitude: 0.05) }, model: m).episodes.count == 1)
        for _ in 0..<4 { m.learn(from: windows, scratching: false) }
        #expect(run({ $0.scratch(9, hz: 2.6, amplitude: 0.05) }, model: m).episodes.isEmpty, "that gentle pattern is now ignored")
        #expect(run({ $0.scratch(9, hz: 4.5, amplitude: 0.3) }, model: m).episodes.count == 1, "real scratching still counts")
    }

    @Test func modelSurvivesJSONAndResets() throws {
        var m = ScratchModel()
        m.learn(from: borderline(), scratching: true)
        let data = try JSONEncoder().encode(m)
        let back = try JSONDecoder().decode(ScratchModel.self, from: data)
        #expect(back == m)
        #expect(back.weights != ScratchModel.startingWeights)
        var r = back
        r.reset()
        #expect(r.weights == ScratchModel.startingWeights && r.answerCount == 0)
    }

    @Test func brokenModelFileFallsBackToStartingWeights() throws {
        let json = #"{"weights":[1,2,3],"confirmedCount":9,"rejectedCount":2,"learningRate":0.3,"priorPull":0.02}"#
        var m = try JSONDecoder().decode(ScratchModel.self, from: Data(json.utf8))
        #expect(m.weights == ScratchModel.startingWeights && m.answerCount == 0)
        m.learn(from: borderline(), scratching: true)                // must not crash
        #expect(m.answerCount == 1)
    }

    @Test func stillWindowsNeverScore() {
        let f = FeatureExtractor().features(x: .init(repeating: 0.1, count: 150), y: .init(repeating: -0.2, count: 150),
                                            z: .init(repeating: -0.97, count: 150), start: 0)
        #expect(!f.moving && ScratchModel().probability(f) == 0)
    }

    @Test func crossingScoreShape() {
        #expect(FeatureExtractor.crossingScore(1) == 0)
        #expect(FeatureExtractor.crossingScore(4) == 1)
        #expect(FeatureExtractor.crossingScore(13) == 0)
        #expect(FeatureExtractor.crossingScore(2) > 0 && FeatureExtractor.crossingScore(2) < 1)
    }

    // MARK: - Reading a recording in pieces (watch background refresh)

    @Test func pendingSinceIsNilWhenNothingIsGoingOn() {
        let detector = ScratchDetector()
        detector.process(signal { $0.still(10) })
        #expect(detector.pendingSince == nil)
        detector.process(signal { $0.still(10); $0.scratch(8, hz: 4); $0.still(8) }.filter { $0.t > Self.t0 + 10 })
        #expect(detector.pendingSince == nil, "the episode is over")
    }

    @Test func pendingSinceMarksAnOpenEpisode() throws {
        let detector = ScratchDetector()
        let events = detector.process(signal { $0.still(6); $0.scratch(9, hz: 4) })
        #expect(events.episodes.isEmpty)
        #expect(detector.isInEpisode)
        let since = seconds(try #require(detector.pendingSince))
        #expect(since >= 3 && since <= 7.5, "the first scratch window: \(since)")
    }

    /// A cut in the middle of a bout (time budget used up) must not split it: the next piece starts
    /// again at `pendingSince` and finds one whole episode.
    @Test func resumingAtPendingSinceKeepsOneEpisode() throws {
        let samples = signal { $0.still(6); $0.scratch(12, hz: 4); $0.still(6) }
        let whole = ScratchDetector.episodes(in: samples, model: ScratchModel()).map(\.episode)
        #expect(whole.count == 1)

        let first = ScratchDetector(source: .recorded)
        let before = first.process(samples.filter { $0.t < Self.t0 + 12 })
        #expect(before.episodes.isEmpty)
        let resume = try #require(first.pendingSince).timeIntervalSinceReferenceDate
        let second = ScratchDetector(source: .recorded)
        let after = (second.process(samples.filter { $0.t >= resume }) + second.finish()).episodes.map(\.episode)
        #expect(after.count == 1)
        let e = try #require(after.first), w = try #require(whole.first)
        #expect(abs(e.start.timeIntervalSince(w.start)) < 0.05)
        #expect(abs(e.end.timeIntervalSince(w.end)) < 0.05)
    }

    // MARK: - RecordingAnalysis: the all-day recording, read within a budget

    private func reader(_ samples: [MotionSample], delivered: @escaping () -> Void = {})
        -> (Date, Date, (MotionSample) -> Bool) -> Void {
        { from, to, body in
            let a = from.timeIntervalSinceReferenceDate, b = to.timeIntervalSinceReferenceDate
            for s in samples where s.t >= a && s.t < b {
                delivered()
                if !body(s) { return }
            }
        }
    }

    private var date0: Date { Date(timeIntervalSinceReferenceDate: Self.t0) }

    /// Runs `RecordingAnalysis` again and again from where the last run stopped, each run allowed
    /// `budget` samples, like background refreshes picking up the recording.
    private func runInPieces(_ samples: [MotionSample], until end: Date, budget: Int)
        -> (episodes: [ScratchEpisode], runs: Int) {
        var from = date0
        var episodes: [ScratchEpisode] = []
        var runs = 0
        while from < end && runs < 200 {
            runs += 1
            var used = 0
            let r = RecordingAnalysis.run(from: from, to: end, sliceLength: 10, model: ScratchModel(), checkEvery: 50,
                                          outOfTime: { used >= budget }, read: reader(samples) { used += 1 })
            #expect(r.through > from, "every run moves on")
            episodes += r.episodes.map(\.episode)
            from = r.through
        }
        return (episodes, runs)
    }

    @Test func recordingInOneRunMatchesBatch() {
        let samples = signal { $0.still(20); $0.scratch(12, hz: 4); $0.still(30); $0.scratch(9, hz: 5, amplitude: 0.5); $0.still(20) }
        let end = date0.addingTimeInterval(91)
        let r = RecordingAnalysis.run(from: date0, to: end, sliceLength: 10, model: ScratchModel(),
                                      outOfTime: { false }, read: reader(samples))
        let batch = ScratchDetector.episodes(in: samples, model: ScratchModel())
        #expect(r.finished && r.through == end)
        #expect(r.episodes.count == 2 && batch.count == 2)
        #expect(r.episodes.map(\.episode.start) == batch.map(\.episode.start))
        #expect(r.episodes.map(\.episode.end) == batch.map(\.episode.end))
    }

    @Test func cutRunsAddUpToTheWholeRecording() throws {
        let samples = signal { $0.still(20); $0.scratch(12, hz: 4); $0.still(30); $0.scratch(9, hz: 5, amplitude: 0.5); $0.still(20) }
        let end = date0.addingTimeInterval(91)
        let whole = ScratchDetector.episodes(in: samples, model: ScratchModel()).map(\.episode)
        // 1000 samples (20 s) per run: longer than a bout and its closing windows, so the runs can
        // keep every bout whole, but both bouts get cut by a deadline at least once.
        let pieces = runInPieces(samples, until: end, budget: 1000)
        #expect(pieces.runs > 4)
        #expect(pieces.episodes.count == whole.count,
                "no bout split in two, none lost: \(pieces.episodes.map { (seconds($0.start), seconds($0.end)) })")
        // A run that starts at a cut lays its 1.5 s hops elsewhere, so an edge can move by up to
        // two hops; the bouts themselves stay whole.
        for (a, b) in zip(pieces.episodes.sorted { $0.start < $1.start }, whole) {
            #expect(abs(a.start.timeIntervalSince(b.start)) <= 3.1)
            #expect(abs(a.end.timeIntervalSince(b.end)) <= 3.1)
        }
    }

    @Test func boutLongerThanARunStillMovesOn() {
        let samples = signal { $0.still(5); $0.scratch(40, hz: 4); $0.still(10) }
        let end = date0.addingTimeInterval(55)
        let pieces = runInPieces(samples, until: end, budget: 1000)   // 20 s per run
        #expect(pieces.runs < 20, "terminates")
        let sorted = pieces.episodes.sorted { $0.start < $1.start }
        #expect(!sorted.isEmpty)
        for (a, b) in zip(sorted, sorted.dropFirst()) { #expect(a.end <= b.start, "no overlap") }
        let seconds = sorted.map(\.duration).reduce(0, +)
        #expect(abs(seconds - 40) < 6, "the whole bout is counted: \(seconds) s")
    }

    @Test func outOfTimeBeforeTheFirstSliceReadsNothing() {
        let samples = signal { $0.scratch(20, hz: 4) }
        let r = RecordingAnalysis.run(from: date0, to: date0.addingTimeInterval(20), sliceLength: 10, model: ScratchModel(),
                                      outOfTime: { true }, read: reader(samples))
        #expect(!r.finished && r.through == date0 && r.episodes.isEmpty)
    }

    // MARK: - Episodes travel to the phone as JSON (contract: default JSONEncoder)

    @Test func episodesRoundTripWithDefaultCoders() throws {
        let episodes = run { $0.scratch(8, hz: 4) }.episodes.map(\.episode)
        let data = try JSONEncoder().encode(episodes)
        let back = try JSONDecoder().decode([ScratchEpisode].self, from: data)
        #expect(back == episodes)
    }
}
