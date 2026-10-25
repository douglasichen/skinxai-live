import Foundation

/// Folds watch episodes into the day records (minutes per hour, episode and intense counts).
public enum EpisodeMerge {
    /// Applies `incoming` to the dataset. An episode already present (same id) is replaced, so a
    /// later "No" from the watch (label `.rejected`) takes its minutes back out.
    /// Returns how many new, kept episodes landed in the dataset's days.
    @discardableResult
    public static func apply(_ incoming: [ScratchEpisode], to d: inout TwinDataset, calendar: Calendar = .current) -> Int {
        var added = 0
        for e in incoming where e.end > e.start {
            var isNew = true
            if let i = d.episodes.firstIndex(where: { $0.id == e.id }) {
                fold(d.episodes[i], into: &d, sign: -1, calendar: calendar)
                d.episodes.remove(at: i)
                isNew = false
            }
            guard e.label != .rejected, covers(e, d, calendar) else { continue }
            fold(e, into: &d, sign: 1, calendar: calendar)
            d.episodes.append(e)
            if isNew { added += 1 }
        }
        d.episodes.sort { $0.start < $1.start }
        return added
    }

    /// Whether the episode starts on one of the dataset's days.
    public static func covers(_ e: ScratchEpisode, _ d: TwinDataset, _ calendar: Calendar) -> Bool {
        d.days.contains { calendar.isDate($0.day, inSameDayAs: e.start) }
    }

    private static func fold(_ e: ScratchEpisode, into d: inout TwinDataset, sign: Double, calendar: Calendar) {
        // Minutes go to the hour(s) they happened in.
        var t = e.start
        while t < e.end {
            guard let hourStart = calendar.dateInterval(of: .hour, for: t) else { break }
            let sliceEnd = min(e.end, hourStart.end)
            let hour = calendar.component(.hour, from: t)
            if let di = d.days.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: t) }), (0..<24).contains(hour) {
                let value = d.days[di].scratchMinutesByHour[hour] + sign * sliceEnd.timeIntervalSince(t) / 60
                d.days[di].scratchMinutesByHour[hour] = max(0, (value * 100).rounded() / 100)
            }
            t = sliceEnd
        }
        if let di = d.days.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: e.start) }) {
            d.days[di].episodeCount = max(0, d.days[di].episodeCount + Int(sign))
            if e.intense { d.days[di].intenseCount = max(0, d.days[di].intenseCount + Int(sign)) }
        }
    }
}
