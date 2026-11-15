import Foundation
import SwiftData
import LifeResetCore

/// Acesso aos dados e regras da app (ponte entre SwiftData e o LifeResetCore).
@MainActor
struct DataStore {
    let ctx: ModelContext
    var cal: Calendar { LRCalendar.current }

    func save() { try? ctx.save(); ChangeCoordinator.shared.didChange(ctx) }

    // MARK: Perfil
    func profile() -> ProfileSettings { ProfileRepository(context: ctx).profile()?.settings ?? .initial }
    func jobs() -> [JobSettings] { ProfileRepository(context: ctx).jobs().map(\.settings) }
    func job(_ kind: JobKind) -> JobSettings {
        jobs().first { $0.kind == kind } ?? (kind == .cafe ? .cafeInitial : .burgerInitial)
    }

    // MARK: Meta
    func meta(_ key: String) -> String? {
        let d = FetchDescriptor<AppMeta>(predicate: #Predicate { $0.key == key })
        return (try? ctx.fetch(d))?.first?.value
    }
    func setMeta(_ key: String, _ value: String) {
        let d = FetchDescriptor<AppMeta>(predicate: #Predicate { $0.key == key })
        if let m = (try? ctx.fetch(d))?.first { m.value = value } else { ctx.insert(AppMeta(key: key, value: value)) }
    }

    var burgerDinner: BurgerDinnerPlacement {
        BurgerDinnerPlacement(rawValue: meta("pref.burgerDinner") ?? "") ?? .atHome
    }

    // MARK: Dias
    func assignment(for date: Date) -> DayAssignment? {
        let s = cal.startOfDay(for: date), e = LRCalendar.addDays(1, to: s)
        let d = FetchDescriptor<DayAssignment>(predicate: #Predicate { $0.date >= s && $0.date < e })
        return (try? ctx.fetch(d))?.first
    }

    func activeTrip(on date: Date) -> Trip? {
        let s = cal.startOfDay(for: date), e = LRCalendar.addDays(1, to: s)
        let d = FetchDescriptor<Trip>(predicate: #Predicate { $0.departure < e && $0.returnDate >= s })
        return (try? ctx.fetch(d))?.first
    }

    /// Dia configurado (ou folga provisória se ainda não houver Sunday Reset para essa semana).
    func dayInfo(for date: Date) -> (info: DayInfo, configured: Bool) {
        let day = cal.startOfDay(for: date)
        var result: (DayInfo, Bool)
        if let a = assignment(for: day) { result = (a.info, true) }
        else { result = (DayInfo(date: day, kind: .dayOff), false) }
        if activeTrip(on: day) != nil {
            var i = result.0; i.kind = .travel; i.shift = nil; i.breakStart = nil; i.leaveHome = nil; i.returnHome = nil
            result = (i, true)
        }
        return result
    }

    func weekInfos(from start: Date, days: Int = 7) -> [DayInfo] {
        (0..<days).map { dayInfo(for: LRCalendar.addDays($0, to: start)).info }
    }

    // MARK: Tarefas
    func allTasks() -> [TaskItem] {
        let d = FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.archived }, sortBy: [SortDescriptor(\.title)])
        return (try? ctx.fetch(d)) ?? []
    }

    func task(_ uid: UUID) -> TaskItem? {
        let d = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.uid == uid })
        return (try? ctx.fetch(d))?.first
    }

    func occurrences(on date: Date) -> [TaskOccurrence] {
        let s = cal.startOfDay(for: date), e = LRCalendar.addDays(1, to: s)
        let d = FetchDescriptor<TaskOccurrence>(predicate: #Predicate { $0.date >= s && $0.date < e })
        return (try? ctx.fetch(d)) ?? []
    }

    func occurrence(_ task: TaskItem, on date: Date) -> TaskOccurrence? {
        let uid = task.uid
        let s = cal.startOfDay(for: date), e = LRCalendar.addDays(1, to: s)
        let d = FetchDescriptor<TaskOccurrence>(predicate: #Predicate { $0.taskUID == uid && $0.date >= s && $0.date < e })
        return (try? ctx.fetch(d))?.first
    }

    func status(_ task: TaskItem, on date: Date) -> OccurrenceStatus {
        OccurrenceStatus(rawValue: occurrence(task, on: date)?.statusRaw ?? "") ?? .pending
    }

    /// Concluída alguma vez nesta semana (para tarefas "1× por semana").
    func doneThisWeek(_ task: TaskItem, week date: Date) -> Bool {
        let uid = task.uid
        let s = LRCalendar.weekStart(for: date), e = LRCalendar.addDays(7, to: s)
        let d = FetchDescriptor<TaskOccurrence>(predicate: #Predicate { $0.taskUID == uid && $0.date >= s && $0.date < e && $0.statusRaw == "done" })
        return ((try? ctx.fetchCount(d)) ?? 0) > 0
    }

    /// Tarefas que acontecem num dia (respeitando "1× por semana" e viagens).
    func tasks(on date: Date) -> [TaskItem] {
        let info = dayInfo(for: date).info
        return allTasks().filter { t in
            guard t.parentUID == nil else { return false }
            let r = t.recurrence
            if case .weeklyFlexible = r {
                if doneThisWeek(t, week: date) { return status(t, on: date) == .done }
                // aparece nas folgas; se a semana não tiver folgas configuradas, aparece todos os dias
                let week = weekInfos(from: LRCalendar.weekStart(for: date))
                let hasOff = week.contains { $0.kind == .dayOff }
                return !hasOff || info.kind == .dayOff || status(t, on: date) != .pending
            }
            return r.occurs(on: date)
        }
    }

    func subtasks(of task: TaskItem) -> [TaskItem] {
        let uid = task.uid
        let d = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.parentUID == uid })
        return (try? ctx.fetch(d)) ?? []
    }

    /// Muda o estado de uma ocorrência. Concluir dá XP; desmarcar no próprio dia retira apenas esse XP.
    func setStatus(_ task: TaskItem, on date: Date, to status: OccurrenceStatus) {
        let day = cal.startOfDay(for: date)
        let occ = occurrence(task, on: day) ?? {
            let o = TaskOccurrence(taskUID: task.uid, date: day, status: "pending"); ctx.insert(o); return o
        }()
        let previous = OccurrenceStatus(rawValue: occ.statusRaw) ?? .pending
        occ.statusRaw = status.rawValue
        let key = "task:\(task.uid.uuidString):\(LRCalendar.dayKey(day))"
        if status == .done, previous != .done {
            occ.completedAt = Date()
            var xp = XPRules.taskXP(priority: task.priority)
            if priorities(on: day).contains(task.uid) { xp += XPRules.priorityBonus }
            occ.xpAwarded = xp
            Progression(store: self).award(xp, area: XPArea(rawValue: task.xpArea) ?? XPArea.forCategory(task.category),
                                           source: task.title, key: key, date: day)
            Progression(store: self).checkAllEssentialsBonus(on: day)
        } else if previous == .done, status != .done, cal.isDateInToday(day) {
            Progression(store: self).revoke(key: key)
            occ.xpAwarded = 0; occ.completedAt = nil
        }
        save()
    }

    // MARK: Prioridades
    func priorities(on date: Date) -> [UUID] {
        let s = cal.startOfDay(for: date), e = LRCalendar.addDays(1, to: s)
        let d = FetchDescriptor<DailyPriority>(predicate: #Predicate { $0.date >= s && $0.date < e })
        return (try? ctx.fetch(d))?.first?.taskUIDs ?? []
    }

    func setPriorities(_ ids: [UUID], on date: Date) {
        let s = cal.startOfDay(for: date), e = LRCalendar.addDays(1, to: s)
        let d = FetchDescriptor<DailyPriority>(predicate: #Predicate { $0.date >= s && $0.date < e })
        if let p = (try? ctx.fetch(d))?.first { p.taskUIDs = Array(ids.prefix(3)) }
        else { ctx.insert(DailyPriority(date: s, taskUIDs: Array(ids.prefix(3)))) }
        save()
    }

    func suggestedPriorities(on date: Date) -> [UUID] {
        let candidates = tasks(on: date).filter { status($0, on: date) == .pending && $0.category != "hygiene" }
            .map { PrioritySuggester.Candidate(id: $0.uid, priority: $0.priority, deadline: $0.deadline, essential: $0.essential) }
        return PrioritySuggester.suggest(candidates)
    }

    // MARK: Plano do dia
    func planTasks(on date: Date) -> [PlanTask] {
        tasks(on: date).compactMap { t in
            let st = status(t, on: date)
            if st == .skippedToday || st == .rescheduled { return nil }
            return PlanTask(id: t.uid, title: t.title, minutes: t.durationMinutes, priority: t.priority, timing: t.timing,
                            location: t.location, essential: t.essential, heavy: t.heavy, done: st == .done)
        }
    }

    func plan(for date: Date, overriding info: DayInfo? = nil) -> DayPlan {
        let day = cal.startOfDay(for: date)
        let today = info ?? dayInfo(for: day).info
        let next = dayInfo(for: LRCalendar.addDays(1, to: day)).info
        let p = profile()
        let ctx = DayContextBuilder.build(today, next: next, profile: p)
        let meals = MealTiming.slots(for: ctx, mainMeals: p.mainMeals, burgerDinner: burgerDinner)
        return DayPlanner.plan(context: ctx, tasks: planTasks(on: day), meals: meals)
    }

    // MARK: Por reagendar
    func openSuggestions() -> [RescheduleSuggestion] {
        let d = FetchDescriptor<RescheduleSuggestion>(predicate: #Predicate { !$0.resolved }, sortBy: [SortDescriptor(\.fromDate)])
        return (try? ctx.fetch(d)) ?? []
    }

    /// Aceitar uma sugestão cria uma tarefa única nessa data (a original e o histórico mantêm-se).
    func accept(_ s: RescheduleSuggestion, on date: Date) {
        if let t = task(s.taskUID) {
            if t.recurrence.isOneOff {
                t.recurrence = .once(day: cal.startOfDay(for: date))
                if let o = occurrence(t, on: s.fromDate) { o.statusRaw = OccurrenceStatus.rescheduled.rawValue }
            } else {
                let copy = TaskItem(title: t.title)
                copy.notes = t.notes; copy.category = t.category; copy.priority = t.priority
                copy.durationMinutes = t.durationMinutes; copy.timingData = t.timingData
                copy.recurrence = .once(day: cal.startOfDay(for: date))
                copy.locationRaw = t.locationRaw; copy.sharingRaw = t.sharingRaw; copy.failureRaw = FailurePolicy.proposeReschedule.rawValue
                copy.xpArea = t.xpArea; copy.notify = t.notify; copy.notifyLeadMinutes = t.notifyLeadMinutes
                ctx.insert(copy)
            }
        }
        s.resolved = true
        save()
    }
}
