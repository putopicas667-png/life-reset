import Foundation

public enum MealType: String, Codable, CaseIterable, Sendable {
    case breakfast, lunch, dinner, snack

    public var title: String {
        switch self {
        case .breakfast: return "Pequeno-almoço"
        case .lunch: return "Almoço"
        case .dinner: return "Jantar"
        case .snack: return "Snack"
        }
    }
}

public struct MealSlot: Equatable, Sendable {
    public let type: MealType
    public let range: TimeRange
    public let note: String
}

/// Onde jantar nos dias de hambúrgueres (configurável).
public enum BurgerDinnerPlacement: String, Codable, CaseIterable, Sendable {
    case atHome, inBreak
    public var title: String { self == .atHome ? "Em casa, ao regressar" : "Na pausa" }
}

/// Horários das refeições conforme o tipo de dia (ARCHITECTURE §9.1).
public enum MealTiming {
    public static func slots(for ctx: DayContext, mainMeals: Int = 3,
                             burgerDinner: BurgerDinnerPlacement = .atHome) -> [MealSlot] {
        var out: [MealSlot] = []
        let wake = ctx.wake
        switch ctx.info.kind {
        case .burgerShift:
            // Pequeno-almoço em casa se houver tempo, senão nos 30 min antes do turno.
            if let leave = ctx.commuteOut?.start, wake.minutes(until: leave) >= 50 {
                out.append(MealSlot(type: .breakfast, range: TimeRange(wake.adding(minutes: 20), wake.adding(minutes: 40)), note: "Em casa"))
            } else if let pre = ctx.preShift {
                out.append(MealSlot(type: .breakfast, range: TimeRange(pre.start, min(pre.end, pre.start.adding(minutes: 20))), note: "Antes de entrar"))
            }
            if let b = ctx.workBreak {
                let lunchEnd = burgerDinner == .inBreak ? b.start.adding(minutes: b.duration / 2) : b.end
                out.append(MealSlot(type: .lunch, range: TimeRange(b.start, min(b.end, lunchEnd)), note: "Na pausa"))
                if burgerDinner == .inBreak {
                    out.append(MealSlot(type: .dinner, range: TimeRange(min(b.end, lunchEnd), b.end), note: "Na pausa"))
                }
            }
            if burgerDinner == .atHome, let back = ctx.commuteBack?.end {
                out.append(MealSlot(type: .dinner, range: TimeRange(back, back.adding(minutes: 25)), note: "Ao regressar"))
            }
        case .cafeShift:
            out.append(MealSlot(type: .breakfast, range: TimeRange(wake.adding(minutes: 20), wake.adding(minutes: 40)), note: "Em casa"))
            if let leave = ctx.commuteOut?.start {
                let s = leave.adding(minutes: -45)
                out.append(MealSlot(type: .lunch, range: TimeRange(s, s.adding(minutes: 30)), note: "Antes de sair"))
            }
            if let back = ctx.commuteBack?.end {
                out.append(MealSlot(type: .dinner, range: TimeRange(back, back.adding(minutes: 30)), note: "Ao regressar"))
            }
        case .dayOff, .custom, .travel:
            out.append(MealSlot(type: .breakfast, range: TimeRange(wake.adding(minutes: 30), wake.adding(minutes: 50)), note: ctx.isTravel ? "Flexível" : ""))
            out.append(MealSlot(type: .lunch, range: TimeRange(TimeOfDay(13, 0), TimeOfDay(13, 40)), note: ctx.isTravel ? "Flexível" : ""))
            out.append(MealSlot(type: .dinner, range: TimeRange(TimeOfDay(20, 0), TimeOfDay(20, 40)), note: ctx.isTravel ? "Flexível" : ""))
        }
        return Array(out.prefix(max(1, mainMeals)))
    }
}
