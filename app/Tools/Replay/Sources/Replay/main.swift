import Foundation
import EczemaKit

// Replays a recording through the real ScratchDetector and prints one CSV row per window.
// Input CSV (header required): t,x,y,z   — seconds, acceleration in g with gravity included, ~50 Hz.
// Optional env: PRESET=live, GATE (movement gate g), THRESHOLD, MAXSTRENGTH, WEIGHTS ("b,w1,w2,w3,w4").
// Usage: swift run -c release Replay samples.csv > windows.csv
let args = CommandLine.arguments
guard args.count >= 2, let text = try? String(contentsOfFile: args[1], encoding: .utf8) else {
    FileHandle.standardError.write("usage: Replay samples.csv\n".data(using: .utf8)!); exit(2)
}
let env = ProcessInfo.processInfo.environment
var config = env["PRESET"] == "live" ? DetectorConfig.live : DetectorConfig.standard
if let m = env["MAXSTRENGTH"].flatMap(Double.init) { config.maxStrength = m }
if let k = env["MAXKURT"].flatMap(Double.init) { config.maxKurtosis = k }
if let k = env["MAXIMP"].flatMap(Double.init) { config.maxImpulsiveness = k }
if let w = env["WINDOW"].flatMap(Double.init) { config.windowSeconds = w }
if let h = env["HOP"].flatMap(Double.init) { config.hopSeconds = h }
if let q = env["QUIET"].flatMap(Int.init) { config.quietWindowsToEnd = q }
if let lo = env["BANDLO"].flatMap(Double.init), let hi = env["BANDHI"].flatMap(Double.init) { config.scratchBand = lo...hi }
if let lo = env["CROSSLO"].flatMap(Double.init), let hi = env["CROSSHI"].flatMap(Double.init) { config.crossingBand = lo...hi }
if let s = env["STILL"].flatMap(Double.init) { config.stillLevel = s }
if let g = env["GATE"].flatMap(Double.init) { config.movementGate = g }
if let th = env["THRESHOLD"].flatMap(Double.init) { config.threshold = th }
var model = ScratchModel()
if let w = env["WEIGHTS"]?.split(separator: ",").compactMap({ Double($0) }), w.count == ScratchModel.startingWeights.count {
    model = ScratchModel(weights: w)
}
var samples: [MotionSample] = []
for (i, line) in text.split(whereSeparator: \.isNewline).enumerated() where i > 0 {
    let p = line.split(separator: ",")
    guard p.count >= 4, let t = Double(p[0]), let x = Double(p[1]), let y = Double(p[2]), let z = Double(p[3]) else { continue }
    samples.append(MotionSample(t: t, x: x, y: y, z: z))
}
let detector = ScratchDetector(model: model, config: config, source: .recorded)
let events = detector.process(samples) + detector.finish()
print("start,strength,maxAxisSD,moving,dominantHz,periodicity,inBand,crossingHz,logStrength,crossingScore,kurtosis,impulsiveness,p,isScratch")
for w in events.windows {
    let f = w.features
    print([f.start, f.strength, f.axisSD.max() ?? 0, f.moving ? 1 : 0, f.dominantHz, f.periodicity, f.inBand, f.crossingHz,
           f.logStrength, f.crossingScore, f.kurtosis ?? 0, f.impulsiveness ?? 0, w.probability, w.isScratch ? 1 : 0].map { String(format: "%.4f", $0) }.joined(separator: ","))
}
let eps = events.episodes
FileHandle.standardError.write("samples=\(samples.count) windows=\(events.windows.count) episodes=\(eps.count)\n".data(using: .utf8)!)
for e in events {
    switch e {
    case let .episodeStarted(s): FileHandle.standardError.write(String(format: "EP_START %.2f emitted %.2f\n", s.start.timeIntervalSinceReferenceDate, (s.windows.last?.start ?? 0) + config.windowSeconds).data(using: .utf8)!)
    case let .episodeEnded(d): FileHandle.standardError.write(String(format: "EP_END %.2f %.2f\n", d.episode.start.timeIntervalSinceReferenceDate, d.episode.end.timeIntervalSinceReferenceDate).data(using: .utf8)!)
    default: break
    }
}
