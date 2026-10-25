import Foundation
import Testing
@testable import EczemaKit

@Suite struct LiveRelayTests {
    let t0 = Date(timeIntervalSince1970: 1_792_821_000)
    func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    static let scratchWindow = LiveBatch.Window(scratch: true, p: 0.95, hz: 3.4, strength: 0.6)
    static let calmWindow = LiveBatch.Window(scratch: false, p: 0.02, hz: 0, strength: 0.01)
    func batch(_ windows: [LiveBatch.Window] = [], _ events: [LiveBatch.Event] = [], live: Bool? = true) -> LiveBatch {
        LiveBatch(live: live, windows: windows, events: events)
    }

    // MARK: Parsing

    @Test func parsesRelayFrames() throws {
        let text = #"""
        {"type":"batch","receivedAt":1792821009.5,"sentAt":null,"live":true,"backing":"workout","appState":"active",
         "samples":[[1792821009.1,0.012]],"raw":[[1792821009.1,0.1,0.2,0.9]],
         "windows":[{"t":1792821006.8,"p":0.994,"scratch":true,"strength":0.847,"hz":3.644,"moving":true,"kurtosis":2.1}],
         "events":[{"type":"start","id":"6ACB87A8","t":1792821031.66,"hz":3.644,"intense":false},
                   {"type":"end","t":1792821031.66,"end":1792821052.7,"seconds":21.085,"intense":true,"hz":2.868},
                   {"type":"label"}]}
        """#
        guard case let .batch(b) = try #require(LiveRelayMessage.parse(text)) else {
            Issue.record("not a batch")
            return
        }
        #expect(b.live == true)
        #expect(b.windows == [LiveBatch.Window(scratch: true, p: 0.994, hz: 3.644, strength: 0.847)])
        #expect(b.events == [LiveBatch.Event(.start, hz: 3.644, intense: false),
                             LiveBatch.Event(.end, hz: 2.868, intense: true, seconds: 21.085)])
        #expect(b.motion == [0.012])

        #expect(LiveRelayMessage.parse(#"{"type":"reset"}"#) == .reset)
        #expect(LiveRelayMessage.parse(#"{"type":"hello","lastSeen":null,"now":1792821009}"#) == .other)
        #expect(LiveRelayMessage.parse(#"{"type":"pong","lastSeen":1792821009,"now":1792821010}"#) == .other)
        #expect(LiveRelayMessage.parse("pong") == nil)
        #expect(LiveRelayMessage.parse(#"{"live":true}"#) == nil)
        // Odd fields never break a frame: no live flag (counts as live), numbers as flags, junk entries.
        guard case let .batch(odd) = try #require(LiveRelayMessage.parse(
            #"{"type":"batch","windows":[{"scratch":1,"p":"x"},7,{"p":0.2}],"events":[{"type":"wiggle"},{"type":"end"}]}"#)) else {
            Issue.record("not a batch")
            return
        }
        #expect(odd.live == nil)
        #expect(odd.windows == [LiveBatch.Window(scratch: true), LiveBatch.Window(scratch: false, p: 0.2)])
        #expect(odd.events == [LiveBatch.Event(.end)])
        #expect(odd.motion == [])
    }

    @Test func motionKeepsTheWristValuesInOrderAndSkipsJunk() throws {
        guard case let .batch(b) = try #require(LiveRelayMessage.parse(
            #"{"type":"batch","live":true,"samples":[[1,0.02],[2,0.61],"x",[3],[4,-1],[5,"y"],[6,1.4]]}"#)) else {
            Issue.record("not a batch")
            return
        }
        #expect(b.motion == [0.02, 0.61, 1.4])
    }

    @Test func windowPassesOnTheWatchDecisionOnly() {
        #expect(Self.scratchWindow.passes)
        #expect(!Self.calmWindow.passes)
        // High probability but not flagged by the watch (it also checks strength and rhythm): no.
        #expect(!LiveBatch.Window(scratch: false, p: 0.99, strength: 1.6).passes)
        #expect(LiveBatch.Window(scratch: true).passes)
    }

    // MARK: Episodes and scratching

    @Test func startAndEndCountOneEpisode() {
        var s = LiveRelayState()
        #expect(s.take(batch([Self.calmWindow]), at: at(0)) == [.sessionStarted])
        #expect(s.startedAt == at(0) && s.count == 0 && !s.isScratching(at: at(0)))

        #expect(s.take(batch([Self.scratchWindow], [.init(.start, hz: 3.4)]), at: at(2)) == [.episodeStarted(1)])
        #expect(s.count == 1 && s.isScratching(at: at(2)))
        #expect(s.episodes.map(\.id) == [1] && s.episodes[0].start == at(2) && s.episodes[0].end == nil)

        // A second start while the first is open doesn't count twice.
        #expect(s.take(batch([Self.scratchWindow], [.init(.start)]), at: at(2.5)).isEmpty)
        #expect(s.count == 1)

        // Between windows the open episode keeps "scratching" on.
        #expect(s.isScratching(at: at(6)))
        #expect(s.take(batch([Self.calmWindow], [.init(.end, intense: true, seconds: 3)]), at: at(6)) == [.episodeEnded(1)])
        #expect(s.episodes[0].end == at(6) && s.episodes[0].intense)
        // The last scratch window was at 2.5 s: its 1.2 s hold is over.
        #expect(!s.isScratching(at: at(6)))
        // An end without an open episode is ignored.
        #expect(s.take(batch([], [.init(.end)]), at: at(6.3)).isEmpty)
    }

    @Test func aScratchWindowHoldsScratchingFor1_2Seconds() {
        var s = LiveRelayState()
        s.take(batch([Self.scratchWindow]), at: at(0))
        #expect(s.count == 0)                         // a window alone is not an episode
        #expect(s.isScratching(at: at(0.1)))
        #expect(s.isScratching(at: at(1.19)))
        #expect(!s.isScratching(at: at(1.21)))
        s.take(batch([Self.scratchWindow]), at: at(1.0))
        #expect(s.isScratching(at: at(2.1)))
    }

    @Test func startWaitsForAScratchWindow() {
        // monitor.js: a start whose batch ends on a calm window waits ("ignoring")…
        var s = LiveRelayState()
        s.take(batch([Self.calmWindow]), at: at(0))
        #expect(s.take(batch([Self.scratchWindow, Self.calmWindow], [.init(.start)]), at: at(1)).isEmpty)
        #expect(s.count == 0)
        // …and starts with the next scratch window,
        #expect(s.take(batch([Self.scratchWindow]), at: at(1.5)) == [.episodeStarted(1)])
        #expect(s.count == 1 && s.episodes[0].start == at(1.5))
        #expect(s.take(batch([Self.calmWindow], [.init(.end)]), at: at(3)) == [.episodeEnded(1)])

        // …or an end before any scratch window cancels it (nothing counted, nothing ended).
        #expect(s.take(batch([Self.calmWindow], [.init(.start)]), at: at(10)).isEmpty)
        #expect(s.take(batch([Self.calmWindow], [.init(.end)]), at: at(11)).isEmpty)
        #expect(s.take(batch([Self.scratchWindow]), at: at(12)).isEmpty)
        #expect(s.count == 1)
    }

    @Test func startUsesTheLastWindowOfAnEarlierBatch() {
        var s = LiveRelayState()
        s.take(batch([Self.scratchWindow]), at: at(0))
        // A batch with no windows: the last window seen (a scratch) decides.
        #expect(s.take(batch([], [.init(.start)]), at: at(0.3)) == [.episodeStarted(1)])
    }

    @Test func aLostEndDoesNotLeaveScratchingOn() {
        // The `end` went missing (the socket reconnected at that moment): batches keep coming with
        // calm windows. The watch would have ended it within ~2 s; after 6 s the phone does.
        var s = LiveRelayState()
        s.take(batch([Self.scratchWindow], [.init(.start)]), at: at(0))
        s.take(batch([Self.scratchWindow]), at: at(1))
        for t in stride(from: 1.5, to: 6.9, by: 0.5) {
            #expect(s.take(batch([Self.calmWindow]), at: at(t)).isEmpty)
        }
        #expect(s.isScratching(at: at(6.9)))
        #expect(s.take(batch([Self.calmWindow]), at: at(7)) == [.episodeEnded(1)])
        #expect(!s.isScratching(at: at(7)))
        // It ends where the last scratch window's hold ran out, not when the phone noticed.
        #expect(s.episodes[0].end == at(2.2))
        // The late `end` changes nothing; the next episode counts normally.
        #expect(s.take(batch([], [.init(.end)]), at: at(8)).isEmpty)
        #expect(s.take(batch([Self.scratchWindow], [.init(.start)]), at: at(9)) == [.episodeStarted(2)])

        // An episode that started on an older scratch window gets its full 6 s from its own start.
        var late = LiveRelayState()
        late.take(batch([Self.scratchWindow]), at: at(0))
        late.take(batch(), at: at(2))
        late.take(batch(), at: at(4))
        #expect(late.take(batch([], [.init(.start)]), at: at(5)) == [.episodeStarted(1)])
        #expect(late.take(batch([Self.calmWindow]), at: at(10.9)).isEmpty)
        #expect(late.take(batch([Self.calmWindow]), at: at(11)) == [.episodeEnded(1)])
        #expect(late.episodes[0].end == at(6.2))

        // A long silence is the stop rule's business, not this one's: no batches, nothing ends here.
        var quiet = LiveRelayState()
        quiet.take(batch([Self.scratchWindow], [.init(.start)]), at: at(0))
        #expect(quiet.tick(at: at(7)).isEmpty && quiet.isScratching(at: at(7)))
    }

    @Test func aStaleWaitingStartExpires() {
        // A start that waited for a scratch window, whose `end` was lost, doesn't start a phantom
        // episode on a stray window much later.
        var s = LiveRelayState()
        s.take(batch([Self.calmWindow], [.init(.start)]), at: at(0))
        for t in stride(from: 0.5, to: 7, by: 0.5) { s.take(batch([Self.calmWindow]), at: at(t)) }
        #expect(s.take(batch([Self.scratchWindow]), at: at(7)).isEmpty)
        #expect(s.count == 0)
    }

    // MARK: Tracking and sessions

    @Test func trackingNeedsARecentLiveBatch() {
        var s = LiveRelayState()
        #expect(!s.isTracking(at: at(0)))
        s.take(batch(), at: at(0))
        #expect(s.isTracking(at: at(3.4)))
        #expect(!s.isTracking(at: at(3.5)))
        s.take(batch(live: nil), at: at(4))           // no flag: still live
        #expect(s.isTracking(at: at(4.1)))
        s.take(batch(live: false), at: at(5))
        #expect(!s.isTracking(at: at(5)))
    }

    @Test func liveFalseStopsTheWatchAndTheNextBatchStartsANewNight() {
        var s = LiveRelayState()
        s.take(batch([Self.scratchWindow], [.init(.start)]), at: at(0))
        // The last flush after Stop still carries events: they count before the stop.
        let changes = s.take(batch([Self.calmWindow], [.init(.end)], live: false), at: at(4))
        #expect(changes == [.episodeEnded(1), .watchStopped])
        #expect(!s.isRunning && !s.isTracking(at: at(4)) && !s.isScratching(at: at(4)))
        #expect(s.count == 1 && s.episodes[0].end == at(4))
        // A late second `live: false` changes nothing.
        #expect(s.take(batch(live: false), at: at(5)).isEmpty)

        // Start again 10 s later: a new session, count from 0.
        #expect(s.take(batch(), at: at(15)) == [.sessionStarted])
        #expect(s.count == 0 && s.episodes.isEmpty && s.startedAt == at(15) && s.isTracking(at: at(15)))
    }

    @Test func stopWhileAnEpisodeIsOpenEndsIt() {
        var s = LiveRelayState()
        s.take(batch([Self.scratchWindow], [.init(.start)]), at: at(0))
        #expect(s.take(batch(live: false), at: at(1)) == [.episodeEnded(1), .watchStopped])
        #expect(s.episodes[0].end == at(1))
    }

    @Test func eightSecondsOfSilenceGoQuietOnce() {
        var s = LiveRelayState()
        s.take(batch([Self.scratchWindow], [.init(.start)]), at: at(0))
        #expect(s.tick(at: at(7.9)).isEmpty)
        #expect(s.isRunning && s.isScratching(at: at(7.9)) && !s.isTracking(at: at(7.9)))
        // Silence is not the watch's Stop: the session pauses, it doesn't end the night.
        #expect(s.tick(at: at(8)) == [.episodeEnded(1), .wentQuiet])
        #expect(s.tick(at: at(9)).isEmpty)
        #expect(!s.isRunning && s.isQuiet && !s.isScratching(at: at(9)))

        // Batches back within 60 s: the same night goes on (count kept, no new session).
        #expect(s.take(batch(), at: at(30)).isEmpty)
        #expect(s.isRunning && !s.isQuiet && s.count == 1 && s.startedAt == at(0) && s.isTracking(at: at(30)))
        #expect(s.take(batch([Self.scratchWindow], [.init(.start)]), at: at(31)) == [.episodeStarted(2)])
    }

    @Test func theWatchsStopAfterAQuietSpellIsStillAStop() {
        var s = LiveRelayState()
        s.take(batch([Self.scratchWindow], [.init(.start)]), at: at(0))
        #expect(s.tick(at: at(8)) == [.episodeEnded(1), .wentQuiet])
        // The Wi-Fi comes back just as he taps Stop: the last batch says live: false.
        #expect(s.take(batch(live: false), at: at(12)) == [.watchStopped])
        #expect(!s.isRunning && !s.isQuiet && s.count == 1)
        #expect(s.take(batch(live: false), at: at(13)).isEmpty)
        // Whatever comes next is a new night.
        #expect(s.take(batch(), at: at(20)) == [.sessionStarted])
        #expect(s.count == 0 && s.startedAt == at(20))

        // A `live: false` from a session the phone never heard running is nothing.
        var fresh = LiveRelayState()
        #expect(fresh.take(batch(live: false), at: at(0)).isEmpty)
    }

    @Test func sixtySecondsOfSilenceStartANewSession() {
        var s = LiveRelayState()
        s.take(batch([Self.scratchWindow], [.init(.start)]), at: at(0))
        s.take(batch([], [.init(.end)]), at: at(2))
        s.tick(at: at(10))
        #expect(s.take(batch(), at: at(62)) == [.sessionStarted])
        #expect(s.count == 0 && s.episodes.isEmpty && s.startedAt == at(62))
    }

    @Test func silenceIsOnlyCountedWhileListening() {
        var s = LiveRelayState()
        s.take(batch(), at: at(0))
        // Heard 2 s of silence, then the phone was away (background, socket down) until 20 s.
        s.notListening(from: at(2), to: at(20))
        #expect(s.tick(at: at(25.9)).isEmpty)
        #expect(s.tick(at: at(26)) == [.wentQuiet])

        // A batch clears the time away; a gap that started before the last batch only counts from it.
        var t = LiveRelayState()
        t.take(batch(), at: at(0))
        t.notListening(from: at(1), to: at(5))
        t.take(batch(), at: at(6))
        t.notListening(from: at(3), to: at(7))
        #expect(t.tick(at: at(14.9)).isEmpty)
        #expect(t.tick(at: at(15)) == [.wentQuiet])
    }

    @Test func resetClearsTonight() {
        var s = LiveRelayState()
        s.take(batch([Self.scratchWindow], [.init(.start)]), at: at(0))
        s.take(batch([], [.init(.end)]), at: at(2))
        s.take(batch([Self.scratchWindow], [.init(.start)]), at: at(5))
        #expect(s.count == 2)
        s.reset(at: at(6))
        #expect(s.count == 0 && s.episodes.isEmpty && !s.isScratching(at: at(6)))
        #expect(s.startedAt == at(6) && s.isRunning)
        // The end of the episode that was going on is ignored; the next one is number 1.
        #expect(s.take(batch([Self.calmWindow], [.init(.end)]), at: at(7)).isEmpty)
        #expect(s.take(batch([Self.scratchWindow], [.init(.start)]), at: at(9)) == [.episodeStarted(1)])

        // Before any session, a reset keeps it that way.
        var idle = LiveRelayState()
        idle.reset(at: at(0))
        #expect(idle.startedAt == nil && idle.count == 0)
    }

    // MARK: A real recording

    /// Replays a labelled recording from the relay frame by frame, ticking every 0.1 s like the app:
    /// four episodes count (the "typing" one is dropped by the last-window rule), tracking never
    /// drops between batches (the longest gap is 3.43 s), and the watch never "stops".
    @Test func replaysARealRecording() throws {
        var s = LiveRelayState()
        var started: [TimeInterval] = []
        var ended: [TimeInterval] = []
        var stops = 0
        var sessions = 0
        var trackingDrops = 0
        var previous: TimeInterval?
        for frame in LiveRecordingFixture.frames {
            if let previous {
                var t = previous + 0.1
                while t < frame.received {
                    if !s.isTracking(at: at(t)) { trackingDrops += 1 }
                    stops += s.tick(at: at(t)).filter { $0 == .watchStopped || $0 == .wentQuiet }.count
                    t += 0.1
                }
            }
            guard case let .batch(b) = try #require(LiveRelayMessage.parse(frame.text)) else {
                Issue.record("frame at \(frame.received) is not a batch")
                continue
            }
            for change in s.take(b, at: at(frame.received)) {
                switch change {
                case .episodeStarted: started.append(frame.received)
                case .episodeEnded: ended.append(frame.received)
                case .watchStopped, .wentQuiet: stops += 1
                case .sessionStarted: sessions += 1
                }
            }
            previous = frame.received
        }
        #expect(LiveRecordingFixture.frames.count == 179)
        #expect(sessions == 1 && stops == 0 && trackingDrops == 0)
        #expect(s.count == 4)
        #expect(started == [24.972, 67.241, 79.216, 91.514])
        #expect(ended == [47.112, 75.048, 82.244, 94.259])
        #expect(s.episodes.allSatisfy { $0.end != nil } && s.episodes.allSatisfy(\.intense))
        let last = try #require(LiveRecordingFixture.frames.last?.received)
        #expect(s.isTracking(at: at(last + 1)) && !s.isScratching(at: at(last + 1)))
        // Nothing after the last batch: tracking ends after 3.5 s and the session goes quiet after 8 s.
        #expect(!s.isTracking(at: at(last + 3.5)))
        #expect(s.tick(at: at(last + 8)) == [.wentQuiet])
    }
}
