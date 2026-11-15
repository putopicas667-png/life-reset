import Foundation

/// Áreas de progressão (sem personagens nem avatares).
public enum XPArea: String, Codable, CaseIterable, Sendable {
    case physical, health, finance, appearance, productivity, personal

    public var title: String {
        switch self {
        case .physical: return "Físico"
        case .health: return "Saúde"
        case .finance: return "Finanças"
        case .appearance: return "Aparência"
        case .productivity: return "Produtividade"
        case .personal: return "Vida pessoal"
        }
    }

    public var symbol: String {
        switch self {
        case .physical: return "figure.strengthtraining.traditional"
        case .health: return "heart"
        case .finance: return "francsign.circle"
        case .appearance: return "sparkles"
        case .productivity: return "checkmark.circle"
        case .personal: return "person"
        }
    }

    /// Área por omissão para uma categoria de tarefa.
    public static func forCategory(_ c: String) -> XPArea {
        switch c {
        case "training": return .physical
        case "health", "nutrition": return .health
        case "finance": return .finance
        case "hygiene": return .appearance
        case "household", "shopping", "admin": return .productivity
        default: return .personal
        }
    }
}

/// Regras de XP: nunca há perda por falhar; os níveis nunca descem (ARCHITECTURE §9.3).
public enum XPRules {
    public static func taskXP(priority: Int) -> Int {
        switch priority { case 1: return 20; case 2: return 15; case 3: return 10; default: return 5 }
    }
    public static let priorityBonus = 5
    public static let allEssentialsBonus = 10
    public static let workoutXP = 25
    public static let savingsMilestoneXP = 30

    /// XP total necessário para atingir o nível `n` (nível 1 = 0 XP).
    public static func xpForLevel(_ n: Int) -> Int {
        guard n > 1 else { return 0 }
        return (1..<n).reduce(0) { $0 + Int((100.0 * pow(Double($1), 1.5)).rounded()) }
    }

    public static func level(forXP xp: Int) -> Int {
        var n = 1
        while xpForLevel(n + 1) <= xp { n += 1 }
        return n
    }

    /// Progresso (0…1) dentro do nível atual.
    public static func progress(forXP xp: Int) -> Double {
        let n = level(forXP: xp)
        let a = xpForLevel(n), b = xpForLevel(n + 1)
        return b > a ? Double(xp - a) / Double(b - a) : 0
    }

    /// Nível mostrado: o máximo alguma vez atingido (nunca desce).
    public static func displayedLevel(xp: Int, maxEverReached: Int) -> Int { max(level(forXP: xp), maxEverReached) }
}

/// Sequências calculadas a partir de dias cumpridos (não apagam o progresso geral).
public enum Streaks {
    /// Dias consecutivos cumpridos que terminam hoje ou ontem.
    public static func current(completedDays: Set<String>, today: Date, calendar: Calendar = LRCalendar.current) -> Int {
        var d = calendar.startOfDay(for: today)
        if !completedDays.contains(LRCalendar.dayKey(d, calendar: calendar)) { d = LRCalendar.addDays(-1, to: d, calendar: calendar) }
        var n = 0
        while completedDays.contains(LRCalendar.dayKey(d, calendar: calendar)) {
            n += 1; d = LRCalendar.addDays(-1, to: d, calendar: calendar)
        }
        return n
    }

    public static func best(completedDays: Set<String>, calendar: Calendar = LRCalendar.current) -> Int {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.calendar = calendar; f.timeZone = calendar.timeZone
        let dates = completedDays.compactMap { f.date(from: $0) }.sorted()
        var best = 0, run = 0
        var prev: Date?
        for d in dates {
            if let p = prev, calendar.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            best = max(best, run); prev = d
        }
        return best
    }
}
