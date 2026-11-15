import Foundation

/// Regra de repetição de uma tarefa.
public enum Recurrence: Codable, Equatable, Hashable, Sendable {
    /// Uma única vez, num dia.
    case once(day: Date)
    case daily
    /// Dias da semana (1 = domingo … 7 = sábado).
    case weekly(weekdays: [Int])
    /// Dia do mês (0 = último dia do mês).
    case monthly(day: Int)
    /// A cada N dias a partir de uma data.
    case everyNDays(n: Int, anchor: Date)
    /// Uma vez por semana, no melhor dia (normalmente uma folga). A app esconde-a depois de concluída nessa semana.
    case weeklyFlexible

    public func occurs(on day: Date, calendar: Calendar = LRCalendar.current) -> Bool {
        let d = calendar.startOfDay(for: day)
        switch self {
        case .once(let x):
            return calendar.isDate(x, inSameDayAs: d)
        case .daily:
            return true
        case .weekly(let w):
            return w.contains(calendar.component(.weekday, from: d))
        case .monthly(let n):
            let dom = calendar.component(.day, from: d)
            let last = calendar.range(of: .day, in: .month, for: d)?.count ?? 31
            return n <= 0 ? dom == last : dom == min(n, last)
        case .everyNDays(let n, let anchor):
            let a = calendar.startOfDay(for: anchor)
            guard n > 0, d >= a else { return false }
            let diff = calendar.dateComponents([.day], from: a, to: d).day ?? 0
            return diff % n == 0
        case .weeklyFlexible:
            return true
        }
    }

    /// Datas em que ocorre, entre `from` e `to` (inclusive).
    public func dates(from: Date, to: Date, calendar: Calendar = LRCalendar.current) -> [Date] {
        var out: [Date] = []
        var d = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        while d <= end {
            if occurs(on: d, calendar: calendar) { out.append(d) }
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        }
        return out
    }

    /// Próxima data em que ocorre a partir de `day` (inclusive), até 400 dias à frente.
    public func next(onOrAfter day: Date, calendar: Calendar = LRCalendar.current) -> Date? {
        var d = calendar.startOfDay(for: day)
        for _ in 0..<400 {
            if occurs(on: d, calendar: calendar) { return d }
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        }
        return nil
    }

    public var isOneOff: Bool { if case .once = self { return true }; return false }

    public var summary: String {
        switch self {
        case .once(let d):
            let f = DateFormatter(); f.locale = Locale(identifier: "pt_PT"); f.setLocalizedDateFormatFromTemplate("EEEdMMM")
            return "Uma vez · \(f.string(from: d))"
        case .daily: return "Todos os dias"
        case .weekly(let w):
            let order = [2, 3, 4, 5, 6, 7, 1]
            let names = order.filter { w.contains($0) }.map { LRCalendar.shortWeekdayName($0) }
            return names.count == 7 ? "Todos os dias" : names.joined(separator: ", ")
        case .monthly(let n): return n <= 0 ? "Último dia do mês" : "Mensal · dia \(n)"
        case .everyNDays(let n, _): return n == 1 ? "Todos os dias" : "A cada \(n) dias"
        case .weeklyFlexible: return "1× por semana (dia livre)"
        }
    }
}
