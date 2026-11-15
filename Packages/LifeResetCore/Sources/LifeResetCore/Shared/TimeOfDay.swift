import Foundation

/// Hora do dia independente da data, guardada em minutos desde a meia-noite.
/// Usada em turnos, pausas, deslocações, refeições e horas de referência.
/// Valores ≥ 24:00 representam a madrugada do dia seguinte (ex.: regresso às 00:30 = 24*60+30).
public struct TimeOfDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let minutes: Int

    public init(minutes: Int) {
        precondition(minutes >= 0, "TimeOfDay não pode ser negativo")
        self.minutes = minutes
    }

    public init(_ hour: Int, _ minute: Int = 0) {
        self.init(minutes: hour * 60 + minute)
    }

    /// Interpreta "HH:mm" (aceita também "H:mm" e "HHhmm").
    public init?(parsing text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "h", with: ":")
        let parts = cleaned.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              let h = Int(parts[0]), (0...47).contains(h) else { return nil }
        var m = 0
        if parts.count == 2, !parts[1].isEmpty {
            guard let mm = Int(parts[1]), (0...59).contains(mm) else { return nil }
            m = mm
        }
        self.init(h, m)
    }

    public var hour: Int { minutes / 60 }
    public var minute: Int { minutes % 60 }

    /// Normalizado para 0..<24h (ex.: 24:30 → 00:30).
    public var wrapped: TimeOfDay { TimeOfDay(minutes: minutes % (24 * 60)) }

    public func adding(minutes delta: Int) -> TimeOfDay { TimeOfDay(minutes: max(0, minutes + delta)) }

    /// Minutos entre duas horas (negativo se `other` for anterior).
    public func minutes(until other: TimeOfDay) -> Int { other.minutes - minutes }

    public var description: String { String(format: "%02d:%02d", wrapped.hour, minute) }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool { lhs.minutes < rhs.minutes }

    /// Data concreta num dia de calendário, no fuso indicado.
    public func date(on day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
    }
}

/// Intervalo de tempo dentro de um dia (fim exclusivo).
public struct TimeRange: Hashable, Codable, Sendable, CustomStringConvertible {
    public let start: TimeOfDay
    public let end: TimeOfDay

    public init(_ start: TimeOfDay, _ end: TimeOfDay) {
        precondition(end >= start, "TimeRange com fim antes do início")
        self.start = start
        self.end = end
    }

    public var duration: Int { end.minutes - start.minutes }
    public func contains(_ t: TimeOfDay) -> Bool { t >= start && t < end }
    public func overlaps(_ other: TimeRange) -> Bool { start < other.end && other.start < end }
    public func contains(_ other: TimeRange) -> Bool { other.start >= start && other.end <= end }
    public var description: String { "\(start)–\(end)" }
}
