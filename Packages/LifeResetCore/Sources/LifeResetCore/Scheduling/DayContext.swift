import Foundation

/// Momentos do dia a que as tarefas ancoradas se prendem (higiene, por exemplo).
public enum DayAnchor: String, Codable, CaseIterable, Sendable {
    case morning, afterLunch, evening, beforeBed

    public var title: String {
        switch self {
        case .morning: return "Manhã"
        case .afterLunch: return "Após almoço"
        case .evening: return "Noite"
        case .beforeBed: return "Antes de deitar"
        }
    }
}

/// Linha do tempo de um dia: quando acorda, sai, trabalha, pausa, regressa e deita-se.
public struct DayContext: Equatable, Sendable {
    public let info: DayInfo
    public let wake: TimeOfDay
    public let bed: TimeOfDay
    public let commuteOut: TimeRange?
    public let preShift: TimeRange?
    public let work: TimeRange?
    public let workBreak: TimeRange?
    public let commuteBack: TimeRange?
    /// Janelas em casa (livres de trabalho e deslocações).
    public let homeWindows: [TimeRange]
    /// Janelas fora de casa compatíveis com pequenas tarefas (antes do turno e pausa).
    public let breakWindows: [TimeRange]
    public let warnings: [String]

    public var isTravel: Bool { info.kind == .travel }
    public var isRecovery: Bool { info.isRecovery }
    /// Todo o tempo acordado (para tarefas "em qualquer sítio").
    public var awake: TimeRange { TimeRange(wake, max(wake, bed)) }

    public func anchorWindow(_ a: DayAnchor) -> TimeRange {
        switch a {
        case .morning:
            let end = commuteOut?.start ?? wake.adding(minutes: 120)
            return TimeRange(wake, max(wake, end))
        case .afterLunch:
            if let b = workBreak { return b }
            return TimeRange(TimeOfDay(13, 30), TimeOfDay(14, 30))
        case .evening:
            let s = commuteBack?.end ?? TimeOfDay(20, 30)
            let e = bed.adding(minutes: -30)
            return TimeRange(min(s, e), max(s, e))
        case .beforeBed:
            return TimeRange(bed.adding(minutes: -30), bed)
        }
    }
}

public enum DayContextBuilder {
    /// Tempo de preparação em casa antes de sair (higiene, vestir, comer).
    public static let defaultPrepMinutes = 60

    public static func build(_ day: DayInfo, next: DayInfo?, profile: ProfileSettings,
                             prepMinutes: Int = defaultPrepMinutes) -> DayContext {
        var warnings: [String] = []
        var wake = profile.wake
        let bed = profile.bed

        var commuteOut: TimeRange?, preShift: TimeRange?, work: TimeRange?, brk: TimeRange?, commuteBack: TimeRange?

        if day.kind.isWork, let shift = day.shift {
            let end = day.effectiveEnd ?? shift.end
            work = TimeRange(shift.start, end)
            brk = day.breakRange
            let arrival = day.arrival ?? shift.start
            if let leave = day.leaveHome, leave <= arrival {
                commuteOut = TimeRange(leave, arrival)
                let needed = leave.adding(minutes: -prepMinutes)
                if needed < wake { wake = needed }
            }
            if arrival < shift.start { preShift = TimeRange(arrival, shift.start) }
            if let back = day.effectiveReturn, back >= end { commuteBack = TimeRange(end, back) }
            if day.overtimeMinutes > 0 {
                warnings.append("Horas extra: +\(day.overtimeMinutes) min; regresso previsto às \((day.effectiveReturn ?? end).description).")
            }
            if let back = commuteBack?.end, back.minutes + 30 > bed.minutes {
                warnings.append("Chegas a casa às \(back.description): pouco tempo até à hora de deitar (\(bed.description)).")
            }
        }

        // Aviso sobre o dia seguinte
        if let n = next, n.kind.isWork, let leave = n.leaveHome {
            let needed = leave.adding(minutes: -prepMinutes)
            if needed < profile.wake {
                warnings.append("Amanhã tens de acordar às \(needed.description) para saíres às \(leave.description).")
            }
        }

        var home: [TimeRange] = []
        var breaks: [TimeRange] = []
        if day.kind == .travel {
            home = []
        } else if let out = commuteOut, let back = commuteBack {
            if out.start > wake { home.append(TimeRange(wake, out.start)) }
            if bed > back.end { home.append(TimeRange(back.end, bed)) }
        } else if let w = work {
            if w.start > wake { home.append(TimeRange(wake, w.start)) }
            if bed > w.end { home.append(TimeRange(w.end, bed)) }
        } else {
            home.append(TimeRange(wake, max(wake, bed)))
        }
        if let p = preShift { breaks.append(p) }
        if let b = brk { breaks.append(b) }

        return DayContext(info: day, wake: wake, bed: bed, commuteOut: commuteOut, preShift: preShift, work: work,
                          workBreak: brk, commuteBack: commuteBack, homeWindows: home, breakWindows: breaks, warnings: warnings)
    }
}
