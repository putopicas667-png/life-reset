import Foundation

/// Números agregados usados para conquistas e estatísticas.
public struct LifeStats: Equatable, Sendable {
    public var tasksDone = 0
    public var workouts = 0
    public var currentStreak = 0
    public var bestStreak = 0
    public var waterGoalDays = 0
    public var proteinGoalDays = 0
    public var weightEntries = 0
    public var savingsMilestones = 0
    public var debtsSettled = 0
    public var totalLevel = 1
    public var sundayResets = 0
    public var tripsPlanned = 0
    public init() {}
}

public struct Achievement: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    let rule: @Sendable (LifeStats) -> Bool

    init(id: String, title: String, detail: String, symbol: String, rule: @escaping @Sendable (LifeStats) -> Bool) {
        self.id = id; self.title = title; self.detail = detail; self.symbol = symbol; self.rule = rule
    }

    public static func == (a: Achievement, b: Achievement) -> Bool { a.id == b.id }
    public func isMet(_ s: LifeStats) -> Bool { rule(s) }
}

public enum Achievements {
    public static let all: [Achievement] = [
        .init(id: "first-task", title: "Primeiro passo", detail: "Concluir a primeira tarefa", symbol: "checkmark.circle") { $0.tasksDone >= 1 },
        .init(id: "tasks-50", title: "Ritmo", detail: "50 tarefas concluídas", symbol: "checklist") { $0.tasksDone >= 50 },
        .init(id: "tasks-250", title: "Rotina sólida", detail: "250 tarefas concluídas", symbol: "checklist.checked") { $0.tasksDone >= 250 },
        .init(id: "tasks-1000", title: "Mil", detail: "1000 tarefas concluídas", symbol: "seal") { $0.tasksDone >= 1000 },
        .init(id: "streak-7", title: "Uma semana", detail: "7 dias seguidos com pelo menos 80 % das tarefas", symbol: "flame") { $0.bestStreak >= 7 },
        .init(id: "streak-30", title: "Um mês", detail: "30 dias seguidos com pelo menos 80 % das tarefas", symbol: "flame.fill") { $0.bestStreak >= 30 },
        .init(id: "workout-1", title: "Primeiro treino", detail: "Registar um treino", symbol: "dumbbell") { $0.workouts >= 1 },
        .init(id: "workout-25", title: "Consistência", detail: "25 treinos registados", symbol: "figure.strengthtraining.traditional") { $0.workouts >= 25 },
        .init(id: "workout-100", title: "Cem treinos", detail: "100 treinos registados", symbol: "trophy") { $0.workouts >= 100 },
        .init(id: "water-7", title: "Hidratado", detail: "Meta de água em 7 dias", symbol: "drop") { $0.waterGoalDays >= 7 },
        .init(id: "protein-14", title: "Proteína em dia", detail: "Meta de proteína em 14 dias", symbol: "fork.knife") { $0.proteinGoalDays >= 14 },
        .init(id: "weight-10", title: "A acompanhar", detail: "10 registos de peso", symbol: "scalemass") { $0.weightEntries >= 10 },
        .init(id: "savings-1", title: "Primeiro marco", detail: "Atingir um marco de poupança", symbol: "banknote") { $0.savingsMilestones >= 1 },
        .init(id: "debt-1", title: "Sem esta dívida", detail: "Liquidar uma dívida", symbol: "creditcard") { $0.debtsSettled >= 1 },
        .init(id: "reset-4", title: "Planeador", detail: "4 Sunday Resets", symbol: "calendar.badge.clock") { $0.sundayResets >= 4 },
        .init(id: "level-5", title: "Nível 5", detail: "Chegar ao nível total 5", symbol: "star") { $0.totalLevel >= 5 },
        .init(id: "level-10", title: "Nível 10", detail: "Chegar ao nível total 10", symbol: "star.fill") { $0.totalLevel >= 10 },
        .init(id: "trip-1", title: "Viajante organizado", detail: "Planear uma viagem", symbol: "airplane") { $0.tripsPlanned >= 1 },
    ]

    /// Conquistas novas (ainda não desbloqueadas). Desbloqueios nunca se perdem.
    public static func newlyUnlocked(stats: LifeStats, already: Set<String>) -> [Achievement] {
        all.filter { !already.contains($0.id) && $0.isMet(stats) }
    }
}

/// Observações simples e verificáveis a partir do histórico (sem juízos).
public enum Insights {
    public struct DayRecord: Sendable {
        public let date: Date
        public let kind: DayKind
        public let done: Int
        public let total: Int
        public init(date: Date, kind: DayKind, done: Int, total: Int) { self.date = date; self.kind = kind; self.done = done; self.total = total }
    }

    public static func completionByKind(_ records: [DayRecord]) -> [(DayKind, Double)] {
        var acc: [DayKind: (Int, Int)] = [:]
        for r in records where r.total > 0 {
            let a = acc[r.kind] ?? (0, 0); acc[r.kind] = (a.0 + r.done, a.1 + r.total)
        }
        return acc.filter { $0.value.1 > 0 }.map { ($0.key, Double($0.value.0) / Double($0.value.1)) }.sorted { $0.1 > $1.1 }
    }

    public static func messages(_ records: [DayRecord], calendar: Calendar = LRCalendar.current) -> [String] {
        var out: [String] = []
        let byKind = completionByKind(records)
        if byKind.count >= 2, let best = byKind.first, let worst = byKind.last, best.1 - worst.1 >= 0.15 {
            out.append("Completas \(Int((best.1 * 100).rounded())) % das tarefas em dias de \(best.0.title.lowercased()) e \(Int((worst.1 * 100).rounded())) % em dias de \(worst.0.title.lowercased()).")
        }
        var byWeekday: [Int: (Int, Int)] = [:]
        for r in records where r.total > 0 {
            let w = calendar.component(.weekday, from: r.date)
            let a = byWeekday[w] ?? (0, 0); byWeekday[w] = (a.0 + r.done, a.1 + r.total)
        }
        let ranked = byWeekday.map { ($0.key, Double($0.value.0) / Double($0.value.1)) }.sorted { $0.1 > $1.1 }
        if ranked.count >= 4, let b = ranked.first, let w = ranked.last, b.1 - w.1 >= 0.15 {
            out.append("O teu dia mais consistente é \(LRCalendar.weekdayName(b.0).lowercased()); o mais difícil é \(LRCalendar.weekdayName(w.0).lowercased()).")
        }
        let recent = records.sorted { $0.date > $1.date }
        if recent.count >= 14 {
            func rate(_ s: ArraySlice<DayRecord>) -> Double {
                let t = s.reduce(0) { $0 + $1.total }
                return t == 0 ? 0 : Double(s.reduce(0) { $0 + $1.done }) / Double(t)
            }
            let last = rate(recent[0..<7]), prev = rate(recent[7..<14])
            if last - prev >= 0.1 {
                out.append("Esta semana estás melhor do que na anterior (\(Int((last * 100).rounded())) % vs \(Int((prev * 100).rounded())) %).")
            } else if prev - last >= 0.1 {
                out.append("Esta semana está a custar mais (\(Int((last * 100).rounded())) % vs \(Int((prev * 100).rounded())) % na anterior). Considera um dia de Recovery.")
            }
        }
        return out
    }
}
