import Foundation

/// O que fazer quando uma tarefa não é concluída (ARCHITECTURE §7.5).
public enum FailurePolicy: String, Codable, CaseIterable, Sendable {
    /// Hábitos diários (higiene): fica registada como falhada; a próxima ocorrência mantém-se.
    case carryToNextPeriod
    /// Compras, limpeza, treino: fica falhada e é proposta uma nova data (requer aprovação).
    case proposeReschedule
    /// Tarefas com prazo: mantêm-se pendentes até ao prazo.
    case keepDeadline

    public var title: String {
        switch self {
        case .carryToNextPeriod: return "Segue para o próximo período"
        case .proposeReschedule: return "Propor nova data"
        case .keepDeadline: return "Manter até ao prazo"
        }
    }
}

public enum RolloverDecision: Equatable, Sendable {
    case markFailed
    case markFailedAndPropose
    case keepPending
}

public enum Rollover {
    /// Decisão para uma ocorrência que ficou por fazer no dia `missedDay`.
    public static func decide(policy: FailurePolicy, deadline: Date?, today: Date,
                              calendar: Calendar = LRCalendar.current) -> RolloverDecision {
        switch policy {
        case .carryToNextPeriod: return .markFailed
        case .proposeReschedule: return .markFailedAndPropose
        case .keepDeadline:
            guard let dl = deadline else { return .markFailedAndPropose }
            return calendar.startOfDay(for: dl) >= calendar.startOfDay(for: today) ? .keepPending : .markFailed
        }
    }

    /// Próximo dia adequado para reagendar (prefere folgas para tarefas de casa).
    public static func suggestDay(after day: Date, preferDaysOff: Bool, upcoming: [DayInfo],
                                  calendar: Calendar = LRCalendar.current) -> Date {
        let start = calendar.startOfDay(for: day)
        let future = upcoming.filter { calendar.startOfDay(for: $0.date) > start }.sorted { $0.date < $1.date }
        if preferDaysOff, let off = future.first(where: { $0.kind == .dayOff && !$0.isRecovery }) { return off.date }
        if let any = future.first(where: { !$0.isRecovery && $0.kind != .travel }) { return any.date }
        return LRCalendar.addDays(1, to: start, calendar: calendar)
    }
}

/// Alteração proposta pelo motor; só é aplicada com aprovação do utilizador.
public struct PlanChange: Equatable, Sendable, Identifiable {
    public var id: UUID { taskId }
    public let taskId: UUID
    public let title: String
    public let before: TimeOfDay?
    public let after: TimeOfDay?

    public var description: String {
        switch (before, after) {
        case let (b?, a?): return "\(title): \(b.description) → \(a.description)"
        case let (nil, a?): return "\(title): passa a caber às \(a.description)"
        case let (b?, nil): return "\(title): deixa de caber (estava às \(b.description))"
        default: return title
        }
    }
}

public enum PlanDiff {
    /// Diferenças de horário entre dois planos do mesmo dia (para mostrar antes/depois de mudar um turno).
    public static func changes(from old: DayPlan, to new: DayPlan) -> [PlanChange] {
        var ids = Set(old.taskBlocks.compactMap(\.taskId))
        ids.formUnion(new.taskBlocks.compactMap(\.taskId))
        ids.formUnion(old.unplaced.map(\.taskId)); ids.formUnion(new.unplaced.map(\.taskId))
        var out: [PlanChange] = []
        for id in ids {
            let b = old.start(of: id), a = new.start(of: id)
            if b != a {
                let title = new.taskBlocks.first { $0.taskId == id }?.title ?? old.taskBlocks.first { $0.taskId == id }?.title
                    ?? new.unplaced.first { $0.taskId == id }?.title ?? old.unplaced.first { $0.taskId == id }?.title ?? "Tarefa"
                out.append(PlanChange(taskId: id, title: title, before: b, after: a))
            }
        }
        return out.sorted { ($0.after ?? $0.before ?? TimeOfDay(0)) < ($1.after ?? $1.before ?? TimeOfDay(0)) }
    }
}

/// Sugestão das 3 prioridades do dia (o utilizador confirma).
public enum PrioritySuggester {
    public struct Candidate: Sendable {
        public let id: UUID
        public let priority: Int
        public let deadline: Date?
        public let essential: Bool
        public init(id: UUID, priority: Int, deadline: Date?, essential: Bool) {
            self.id = id; self.priority = priority; self.deadline = deadline; self.essential = essential
        }
    }

    public static func suggest(_ c: [Candidate], count: Int = 3) -> [UUID] {
        c.sorted {
            let d0 = $0.deadline ?? .distantFuture, d1 = $1.deadline ?? .distantFuture
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            if d0 != d1 { return d0 < d1 }
            return !$0.essential && $1.essential ? false : $0.essential && !$1.essential
        }
        .prefix(count).map(\.id)
    }
}
