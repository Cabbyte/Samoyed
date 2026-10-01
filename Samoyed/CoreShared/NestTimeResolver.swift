import Foundation

public enum NestTimeResolver {
    /// Resolve a civil time against offsets on both sides of a timezone transition.
    /// A fold picks the earliest instant; a gap moves forward by the exact gap,
    /// including non-hour transitions such as Australia/Lord_Howe.
    public static func instant(on day: LocalDay, minute: Int, timeZoneID: String) throws -> Date {
        guard let zone = TimeZone(identifier: timeZoneID), (0...1440).contains(minute) else { throw CocoaError(.coderInvalidValue) }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let midnight = utc.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) else { throw CocoaError(.coderInvalidValue) }
        let civil = midnight.addingTimeInterval(Double(minute * 60))
        let offsets = Set(stride(from: -48, through: 48, by: 6).map { zone.secondsFromGMT(for: civil.addingTimeInterval(Double($0 * 3600))) })
        var candidates: [(instant: Date, delta: TimeInterval)] = []
        for offset in offsets {
            let candidate = civil.addingTimeInterval(-Double(offset))
            let representedCivil = candidate.addingTimeInterval(Double(zone.secondsFromGMT(for: candidate)))
            let delta = representedCivil.timeIntervalSince(civil)
            if delta >= 0 { candidates.append((candidate, delta)) }
        }
        guard let result = candidates.min(by: { $0.delta == $1.delta ? $0.instant < $1.instant : $0.delta < $1.delta }) else { throw CocoaError(.coderInvalidValue) }
        return result.instant
    }
}
