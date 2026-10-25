import Foundation
import Testing
@testable import EczemaKit

@Suite struct LivePresetTests {
    @Test func lightAndHardScratchingAreCaughtLive() {
        // Real light scratching measured 0.3–0.8 g of motion, hard scratching about 2.5 g.
        for amplitude in [0.35, 3.6] {
            var s = SyntheticMotion(start: 0, seed: 7)
            s.still(4)
            s.scratch(6, hz: 3.5, amplitude: amplitude)
            s.still(4)
            let live = ScratchDetector.episodes(in: s.samples, model: ScratchModel(), config: .live)
            #expect(live.count == 1, "amplitude \(amplitude)")
        }
    }

    @Test func pattingAThighIsIgnoredLive() {
        // A pat every third of a second: a sharp ~3 g spike on one axis, near-still in between.
        var samples: [MotionSample] = []
        var rng = SystemRandomNumberGenerator()
        for i in 0..<(50 * 12) {
            let t = Double(i) / 50
            let phase = t.truncatingRemainder(dividingBy: 1.0 / 3.0)
            let spike = 3.2 * exp(-pow((phase - 0.05) / 0.018, 2)) - 0.6 * exp(-pow((phase - 0.1) / 0.03, 2))
            let n = { Double.random(in: -0.02...0.02, using: &rng) }
            samples.append(MotionSample(t: t, x: 0.1 + n(), y: -0.2 + n(), z: -0.97 + spike + n()))
        }
        let windows = ScratchDetector(model: ScratchModel(), config: .live).process(samples).windows
        #expect(!windows.isEmpty && windows.allSatisfy { ($0.features.kurtosis ?? 0) > 5.5 })
        #expect(ScratchDetector.episodes(in: samples, model: ScratchModel(), config: .live).isEmpty)
    }

    @Test func liveStartsAfterOneWindow() {
        var s = SyntheticMotion(start: 0, seed: 9)
        s.still(3)
        s.scratch(8, hz: 4.5, amplitude: 0.2)
        let d = ScratchDetector(model: ScratchModel(), config: .live)
        var firstStart: Date?
        for sample in s.samples {
            for e in d.process(sample) { if case let .episodeStarted(st) = e, firstStart == nil { firstStart = st.start; _ = st } }
            if firstStart != nil { break }
        }
        #expect(firstStart != nil)
    }

    @Test func walkingAndTypingAreIgnoredLive() {
        var s = SyntheticMotion(start: 0, seed: 11)
        s.walk(20)
        s.still(3)
        s.type(15)
        #expect(ScratchDetector.episodes(in: s.samples, model: ScratchModel(), config: .live).isEmpty)
    }

    /// Trade-off chosen for the demo (rather a false alarm than a miss): slow ~1.8 Hz strokes count,
    /// so big waving at that rate counts too.
    @Test func slowStrokesCountLive() {
        var w = SyntheticMotion(start: 0, seed: 12)
        w.still(3)
        w.scratch(6, hz: 1.8, amplitude: 0.5)
        w.still(3)
        #expect(ScratchDetector.episodes(in: w.samples, model: ScratchModel(), config: .live).count == 1)
    }

    @Test func twoBoutsWithAPauseAreTwoEpisodes() {
        var s = SyntheticMotion(start: 0, seed: 21)
        s.still(3)
        s.scratch(3, hz: 3.5, amplitude: 0.5)
        s.still(2.5)
        s.scratch(3, hz: 3.5, amplitude: 0.5)
        s.still(4)
        #expect(ScratchDetector.episodes(in: s.samples, model: ScratchModel(), config: .live).count == 2)
    }

    @Test func shortBurstIsCaughtWithinAboutTwoSeconds() {
        var s = SyntheticMotion(start: 0, seed: 23)
        s.still(4)
        s.scratch(1.5, hz: 3.5, amplitude: 0.5)
        s.still(4)
        let d = ScratchDetector(model: ScratchModel(), config: .live)
        var startedAt: TimeInterval?
        for sample in s.samples {
            for e in d.process(sample) { if case .episodeStarted = e, startedAt == nil { startedAt = sample.t } }
        }
        #expect(startedAt != nil)
        if let t = startedAt { #expect(t - 4 < 2.5) }
    }
}
