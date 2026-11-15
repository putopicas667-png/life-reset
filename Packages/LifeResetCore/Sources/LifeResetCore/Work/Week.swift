import Foundation

/// Tipo de dia na semana de trabalho.
public enum DayKind: String, Codable, CaseIterable, Sendable {
    case burgerShift, cafeShift, dayOff, travel, custom

    public var title: String {
        switch self {
        case .burgerShift: return "Hambúrgueres"
        case .cafeShift: return "Café"
        case .dayOff: return "Folga"
        case .travel: return "Viagem"
        case .custom: return "Outro"
        }
    }

    public var isWork: Bool { self == .burgerShift || self == .cafeShift }
}

/// Configuração concreta de um dia (vem do Sunday Reset).
public struct DayInfo: Equatable, Sendable {
    public var date: Date
    public var kind: DayKind
    /// Turno (entrada–saída prevista), sem horas extra.
    public var shift: TimeRange?
    public var breakStart: TimeOfDay?
    public var breakMinutes: Int
    public var overtimeMinutes: Int
    public var leaveHome: TimeOfDay?
    public var arrival: TimeOfDay?
    public var returnHome: TimeOfDay?
    public var isRecovery: Bool

    public init(date: Date, kind: DayKind, shift: TimeRange? = nil, breakStart: TimeOfDay? = nil, breakMinutes: Int = 0,
                overtimeMinutes: Int = 0, leaveHome: TimeOfDay? = nil, arrival: TimeOfDay? = nil, returnHome: TimeOfDay? = nil,
                isRecovery: Bool = false) {
        self.date = date; self.kind = kind; self.shift = shift; self.breakStart = breakStart
        self.breakMinutes = breakMinutes; self.overtimeMinutes = overtimeMinutes
        self.leaveHome = leaveHome; self.arrival = arrival; self.returnHome = returnHome; self.isRecovery = isRecovery
    }

    /// Dia de trabalho com os horários por omissão do trabalho.
    public static func work(_ job: JobSettings, on date: Date, breakStart: TimeOfDay? = nil, overtime: Int = 0) -> DayInfo {
        let kind: DayKind = job.kind == .cafe ? .cafeShift : .burgerShift
        let defaultBreak = breakStart ?? TimeOfDay(minutes: job.start.minutes + job.shiftDuration / 2 - job.breakMinutes / 2)
        return DayInfo(date: date, kind: kind, shift: TimeRange(job.start, job.end), breakStart: defaultBreak,
                       breakMinutes: job.breakMinutes, overtimeMinutes: overtime, leaveHome: job.leaveHome,
                       arrival: job.arrival, returnHome: job.returnHome)
    }

    /// Fim efetivo do turno (com horas extra).
    public var effectiveEnd: TimeOfDay? { shift.map { $0.end.adding(minutes: overtimeMinutes) } }
    /// Regresso efetivo (empurrado pelas horas extra).
    public var effectiveReturn: TimeOfDay? { returnHome.map { $0.adding(minutes: overtimeMinutes) } }
    public var breakRange: TimeRange? {
        guard let b = breakStart, breakMinutes > 0 else { return nil }
        return TimeRange(b, b.adding(minutes: breakMinutes))
    }
}

/// Validação da semana configurada no Sunday Reset.
public enum WeekValidator {
    public struct Issue: Equatable, Sendable, Hashable {
        public enum Level: Sendable { case warning, error }
        public let level: Level
        public let message: String
    }

    public static func validate(_ days: [DayInfo], expectedBurger: Int = 4, expectedCafe: Int = 1, expectedOff: Int = 2,
                                maxRecovery: Int = 2) -> [Issue] {
        var out: [Issue] = []
        let burger = days.filter { $0.kind == .burgerShift }.count
        let cafe = days.filter { $0.kind == .cafeShift }.count
        let off = days.filter { $0.kind == .dayOff }.count
        let travel = days.filter { $0.kind == .travel }.count
        let recovery = days.filter(\.isRecovery).count

        if recovery > maxRecovery {
            out.append(Issue(level: .error, message: "Recovery Mode: máximo de \(maxRecovery) dias por semana (tens \(recovery))."))
        }
        if travel == 0 {
            if burger != expectedBurger { out.append(Issue(level: .warning, message: "Hambúrgueres: \(burger) turnos (habitual: \(expectedBurger)).")) }
            if cafe != expectedCafe { out.append(Issue(level: .warning, message: "Café: \(cafe) turnos (habitual: \(expectedCafe), ao domingo).")) }
            if off != expectedOff { out.append(Issue(level: .warning, message: "Folgas: \(off) (habitual: \(expectedOff)).")) }
        }
        for d in days {
            let name = LRCalendar.weekdayName(LRCalendar.current.component(.weekday, from: d.date))
            if d.kind == .cafeShift, LRCalendar.current.component(.weekday, from: d.date) != 1 {
                out.append(Issue(level: .warning, message: "\(name): o café costuma ser ao domingo."))
            }
            if d.kind == .dayOff, LRCalendar.current.component(.weekday, from: d.date) == 1 {
                out.append(Issue(level: .warning, message: "Domingo marcado como folga (normalmente há café)."))
            }
            if let s = d.shift, let b = d.breakRange, !s.contains(b) {
                out.append(Issue(level: .error, message: "\(name): a pausa (\(b)) está fora do turno (\(s))."))
            }
            if d.kind.isWork, d.shift == nil {
                out.append(Issue(level: .error, message: "\(name): falta o horário do turno."))
            }
        }
        return out
    }

    public static func hasErrors(_ issues: [Issue]) -> Bool { issues.contains { $0.level == .error } }
}
