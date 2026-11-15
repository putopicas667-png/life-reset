import Foundation

/// Calendário da app: gregoriano, semana a começar à segunda, português de Portugal.
public enum LRCalendar {
    public static var current: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.locale = Locale(identifier: "pt_PT")
        c.timeZone = .current
        return c
    }

    /// Segunda-feira da semana de `date`.
    public static func weekStart(for date: Date, calendar: Calendar = current) -> Date {
        let d = calendar.startOfDay(for: date)
        let wd = calendar.component(.weekday, from: d) // 1=dom … 7=sáb
        let back = (wd + 5) % 7 // segunda → 0, domingo → 6
        return calendar.date(byAdding: .day, value: -back, to: d)!
    }

    /// Os 7 dias (segunda → domingo) da semana que começa em `start`.
    public static func days(ofWeekStarting start: Date, calendar: Calendar = current) -> [Date] {
        (0..<7).map { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: start))! }
    }

    public static func addDays(_ n: Int, to date: Date, calendar: Calendar = current) -> Date {
        calendar.date(byAdding: .day, value: n, to: calendar.startOfDay(for: date))!
    }

    public static func dayKey(_ date: Date, calendar: Calendar = current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func monthKey(_ date: Date, calendar: Calendar = current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    public static func weekdayName(_ weekday: Int) -> String {
        ["", "Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"][max(0, min(7, weekday))]
    }

    public static func shortWeekdayName(_ weekday: Int) -> String {
        ["", "Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"][max(0, min(7, weekday))]
    }
}
