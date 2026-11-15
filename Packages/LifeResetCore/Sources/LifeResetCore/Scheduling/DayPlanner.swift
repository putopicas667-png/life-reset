import Foundation

public enum TaskTiming: Codable, Equatable, Hashable, Sendable {
    case fixed(TimeOfDay)
    case anchored(DayAnchor)
    case flexible(earliest: TimeOfDay, latest: TimeOfDay)
}

public enum TaskLocation: String, Codable, CaseIterable, Sendable {
    case home, anywhere, breakCompatible

    public var title: String {
        switch self {
        case .home: return "Em casa"
        case .anywhere: return "Em qualquer sítio"
        case .breakCompatible: return "Compatível com a pausa"
        }
    }
}

/// Tarefa já reduzida ao que o planeador precisa.
public struct PlanTask: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var minutes: Int
    /// 1 = muito alta … 4 = baixa
    public var priority: Int
    public var timing: TaskTiming
    public var location: TaskLocation
    public var essential: Bool
    public var heavy: Bool
    public var done: Bool

    public init(id: UUID = UUID(), title: String, minutes: Int, priority: Int = 3, timing: TaskTiming,
                location: TaskLocation = .home, essential: Bool = false, heavy: Bool = false, done: Bool = false) {
        self.id = id; self.title = title; self.minutes = max(1, minutes); self.priority = priority
        self.timing = timing; self.location = location; self.essential = essential; self.heavy = heavy; self.done = done
    }
}

public enum BlockKind: String, Sendable {
    case commute, work, workBreak, preShift, meal, task, free
}

public struct PlanBlock: Equatable, Sendable, Identifiable {
    public var id: String { "\(kind.rawValue)-\(taskId?.uuidString ?? title)-\(range.start.minutes)" }
    public let kind: BlockKind
    public let title: String
    public let range: TimeRange
    public let taskId: UUID?
    public let isConflict: Bool
    public let done: Bool
}

public struct UnplacedTask: Equatable, Sendable {
    public let taskId: UUID
    public let title: String
    public let reason: String
}

public struct DayPlan: Equatable, Sendable {
    public let context: DayContext
    public let blocks: [PlanBlock]
    public let unplaced: [UnplacedTask]
    public let conflicts: [String]

    public var warnings: [String] { context.warnings }
    public var taskBlocks: [PlanBlock] { blocks.filter { $0.kind == .task } }

    /// Próximo bloco relevante a partir de `now` (tarefas, refeições, deslocações, trabalho).
    public func next(after now: TimeOfDay) -> PlanBlock? {
        blocks.first { $0.range.end > now && !$0.done && $0.kind != .free }
    }

    public func start(of taskId: UUID) -> TimeOfDay? { blocks.first { $0.taskId == taskId }?.range.start }
}

/// Distribui tarefas pelo dia respeitando turnos, deslocações, pausas e refeições (ARCHITECTURE §7.3).
public enum DayPlanner {
    public static func plan(context ctx: DayContext, tasks: [PlanTask], meals: [MealSlot] = []) -> DayPlan {
        var blocks: [PlanBlock] = []
        var occupied: [TimeRange] = []
        var unplaced: [UnplacedTask] = []
        var conflicts: [String] = []

        func add(_ kind: BlockKind, _ title: String, _ r: TimeRange, task: PlanTask? = nil, conflict: Bool = false) {
            blocks.append(PlanBlock(kind: kind, title: title, range: r, taskId: task?.id, isConflict: conflict, done: task?.done ?? false))
            if kind != .preShift && kind != .workBreak { occupied.append(r) }
        }

        // 1. Estrutura do dia
        if let c = ctx.commuteOut { add(.commute, "Deslocação para o trabalho", c) }
        if let p = ctx.preShift { add(.preShift, "Tempo antes de entrar", p) }
        if let w = ctx.work { add(.work, ctx.info.kind.title, w) }
        if let b = ctx.workBreak { add(.workBreak, "Pausa", b) }
        if let c = ctx.commuteBack { add(.commute, "Regresso a casa", c) }
        for m in meals {
            blocks.append(PlanBlock(kind: .meal, title: m.type.title + (m.note.isEmpty ? "" : " · \(m.note)"), range: m.range,
                                    taskId: nil, isConflict: false, done: false))
        }
        let workAndCommute = occupied

        // 2. Filtros: viagem e recuperação
        var candidates: [PlanTask] = []
        for t in tasks {
            if ctx.isTravel && t.location == .home {
                unplaced.append(UnplacedTask(taskId: t.id, title: t.title, reason: "Em viagem")); continue
            }
            if ctx.isRecovery && (!t.essential || t.heavy) {
                unplaced.append(UnplacedTask(taskId: t.id, title: t.title, reason: "Recovery Mode")); continue
            }
            candidates.append(t)
        }

        // 3. Fixas (nunca movidas)
        for t in candidates {
            guard case .fixed(let at) = t.timing else { continue }
            let r = TimeRange(at, at.adding(minutes: t.minutes))
            let clash = workAndCommute.contains { $0.overlaps(r) } && t.location != .anywhere
            if clash { conflicts.append("\(t.title) às \(at.description) coincide com o trabalho ou a deslocação.") }
            add(.task, t.title, r, task: t, conflict: clash)
        }

        // 4. Ancoradas, por âncora e prioridade
        for anchor in DayAnchor.allCases {
            let window = ctx.anchorWindow(anchor)
            var cursor = window.start
            let group = candidates.filter { $0.timing == .anchored(anchor) }.sorted { $0.priority < $1.priority }
            for t in group {
                let windows: [TimeRange]
                if anchor == .afterLunch && ctx.workBreak != nil { windows = [window] }
                else if t.location == .home && !ctx.homeWindows.contains(where: { $0.overlaps(window) }) {
                    unplaced.append(UnplacedTask(taskId: t.id, title: t.title, reason: "Sem tempo em casa neste momento do dia")); continue
                } else { windows = [window] }
                if let r = firstGap(in: windows, after: cursor, minutes: t.minutes, avoiding: occupied, softEnd: true) {
                    add(.task, t.title, r, task: t); cursor = r.end
                } else {
                    unplaced.append(UnplacedTask(taskId: t.id, title: t.title, reason: "Não cabe em \(anchor.title.lowercased())"))
                }
            }
        }

        // 5. Flexíveis: prioridade, depois duração (maiores primeiro)
        let flexible = candidates.filter { if case .flexible = $0.timing { return true }; return false }
            .sorted { ($0.priority, -$0.minutes) < ($1.priority, -$1.minutes) }
        for t in flexible {
            guard case .flexible(let e, let l) = t.timing else { continue }
            let limit = TimeRange(e, max(e, l))
            let base: [TimeRange]
            switch t.location {
            case .home: base = ctx.homeWindows
            case .breakCompatible: base = ctx.breakWindows + ctx.homeWindows
            case .anywhere: base = ctx.isTravel ? [ctx.awake] : ctx.homeWindows + ctx.breakWindows
            }
            let windows = base.compactMap { intersect($0, limit) }
            if let r = firstGap(in: windows, after: TimeOfDay(0), minutes: t.minutes, avoiding: occupied, softEnd: false) {
                add(.task, t.title, r, task: t)
            } else {
                unplaced.append(UnplacedTask(taskId: t.id, title: t.title, reason: "Sem janela livre compatível hoje"))
            }
        }

        let sorted = blocks.sorted { ($0.range.start, $0.range.end) < ($1.range.start, $1.range.end) }
        return DayPlan(context: ctx, blocks: sorted, unplaced: unplaced, conflicts: conflicts)
    }

    static func intersect(_ a: TimeRange, _ b: TimeRange) -> TimeRange? {
        let s = max(a.start, b.start), e = min(a.end, b.end)
        return e > s ? TimeRange(s, e) : nil
    }

    /// Primeiro intervalo livre com `minutes` dentro das janelas. Com `softEnd`, pode passar ligeiramente o fim
    /// da janela (âncoras como "Manhã" são indicativas), mas nunca sobrepor trabalho/deslocação.
    static func firstGap(in windows: [TimeRange], after: TimeOfDay, minutes: Int, avoiding occupied: [TimeRange],
                         softEnd: Bool) -> TimeRange? {
        for w in windows.sorted(by: { $0.start < $1.start }) {
            var s = max(w.start, after)
            let hardEnd = softEnd ? w.end.adding(minutes: 15) : w.end
            while s.adding(minutes: minutes) <= hardEnd {
                let r = TimeRange(s, s.adding(minutes: minutes))
                if let clash = occupied.filter({ $0.overlaps(r) }).max(by: { $0.end < $1.end }) {
                    s = clash.end
                } else {
                    return r
                }
            }
        }
        return nil
    }
}
