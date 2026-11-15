import Foundation
import SwiftData
import UserNotifications
import WidgetKit
import LifeResetCore

/// Preferências de notificações (guardadas no AppMeta).
struct NotificationPrefs: Equatable {
    var enabled = false
    var tasks = true
    var leaveHome = true
    var morning = true
    var evening = true
    var finance = true
    var travel = true

    @MainActor init(store: DataStore) {
        func b(_ k: String, _ d: Bool) -> Bool { store.meta("notif.\(k)").map { $0 == "1" } ?? d }
        enabled = b("enabled", false); tasks = b("tasks", true); leaveHome = b("leave", true)
        morning = b("morning", true); evening = b("evening", true); finance = b("finance", true); travel = b("travel", true)
    }
    init() {}

    @MainActor func save(_ store: DataStore) {
        func s(_ k: String, _ v: Bool) { store.setMeta("notif.\(k)", v ? "1" : "0") }
        s("enabled", enabled); s("tasks", tasks); s("leave", leaveHome); s("morning", morning)
        s("evening", evening); s("finance", finance); s("travel", travel)
        store.save()
    }
}

/// Agenda "rolante": a cada alteração, apaga e volta a criar as notificações das próximas 48 h (limite do iOS: 64).
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    static let taskCategory = "LR_TASK"
    var container: ModelContainer?

    func configure(container: ModelContainer) {
        self.container = container
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let done = UNNotificationAction(identifier: "DONE", title: "Concluir", options: [])
        let snooze = UNNotificationAction(identifier: "SNOOZE", title: "Adiar 15 min", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.taskCategory, actions: [done, snooze], intentIdentifiers: [])])
        ChangeCoordinator.shared.hooks = [
            { ctx in NotificationService.shared.reschedule(DataStore(ctx: ctx)) },
            { ctx in WidgetSnapshotWriter.write(DataStore(ctx: ctx)) },
        ]
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func reschedule(_ store: DataStore) {
        let prefs = NotificationPrefs(store: store)
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard prefs.enabled else { return }

        var requests: [(Date, UNNotificationRequest)] = []
        let now = Date()
        let cal = Calendar.current
        func add(_ id: String, _ title: String, _ body: String, at date: Date, task: UUID? = nil) {
            guard date > now, date < now.addingTimeInterval(48 * 3600) else { return }
            let c = UNMutableNotificationContent()
            c.title = title; c.body = body; c.sound = .default
            if let task { c.categoryIdentifier = Self.taskCategory; c.userInfo = ["task": task.uuidString, "day": date.timeIntervalSince1970] }
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            requests.append((date, UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))))
        }

        for offset in 0...1 {
            let day = LRCalendar.addDays(offset, to: cal.startOfDay(for: now))
            let plan = store.plan(for: day)
            let key = LRCalendar.dayKey(day)

            if prefs.morning {
                let prio = store.priorities(on: day).compactMap { store.task($0)?.title }
                let body = prio.isEmpty ? "\(plan.taskBlocks.count) tarefas planeadas. Escolhe as 3 prioridades." : "Prioridades: " + prio.joined(separator: ", ")
                add("morning-\(key)", "\(plan.context.info.kind.title) · bom dia", body, at: plan.context.wake.date(on: day))
            }
            if prefs.leaveHome, let out = plan.context.commuteOut {
                add("leave-\(key)", "Sair de casa às \(out.start.description)", "Faltam 15 minutos.", at: out.start.adding(minutes: -15).date(on: day))
            }
            if prefs.tasks {
                for b in plan.taskBlocks where !b.done {
                    guard let id = b.taskId, let t = store.task(id), t.notify else { continue }
                    add("task-\(id.uuidString)-\(key)", t.title, "Às \(b.range.start.description) · \(t.durationMinutes) min",
                        at: b.range.start.adding(minutes: -t.notifyLeadMinutes).date(on: day), task: id)
                }
            }
            if prefs.evening {
                let next = store.plan(for: LRCalendar.addDays(1, to: day))
                var body = "Amanhã: \(next.context.info.kind.title)"
                if let o = next.context.commuteOut { body += ", sair às \(o.start.description)" }
                let pending = store.tasks(on: day).filter { store.status($0, on: day) == .pending }.count
                if pending > 0 { body += ". Hoje ainda tens \(pending) tarefa(s) por fazer." }
                add("evening-\(key)", "Resumo do dia", body, at: plan.context.bed.adding(minutes: -60).date(on: day))
            }
            if prefs.finance {
                let dom = cal.component(.day, from: day)
                for f in store.fixedExpenses() where f.dayOfMonth == dom && !store.isPaid(f, in: day) {
                    add("fixed-\(f.name)-\(key)", "Pagamento hoje: \(f.name)", Fmt.chf(f.amount) + (f.isEstimate ? " (estimativa)" : ""),
                        at: cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day)
                }
            }
        }
        if prefs.travel {
            let trips = (try? store.ctx.fetch(FetchDescriptor<Trip>())) ?? []
            for t in trips where t.returnDate >= cal.startOfDay(for: now) {
                for r in store.reminders(for: t) { add("trip-\(t.uid.uuidString)-\(r.key)", "Viagem: \(t.destination)", r.title, at: r.date) }
            }
        }
        for (_, r) in requests.sorted(by: { $0.0 < $1.0 }).prefix(60) { center.add(r) }
    }

    // MARK: Delegado

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let content = response.notification.request.content
        Task { @MainActor in
            defer { completionHandler() }
            guard let container = NotificationService.shared.container,
                  let raw = info["task"] as? String, let uid = UUID(uuidString: raw) else { return }
            let store = DataStore(ctx: container.mainContext)
            let day = (info["day"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
            switch action {
            case "DONE":
                if let t = store.task(uid) { store.setStatus(t, on: day, to: .done) }
            case "SNOOZE":
                let c = content.mutableCopy() as? UNMutableNotificationContent ?? UNMutableNotificationContent()
                let req = UNNotificationRequest(identifier: "snooze-\(raw)-\(Int(Date().timeIntervalSince1970))", content: c,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false))
                try? await UNUserNotificationCenter.current().add(req)
            default: break
            }
        }
    }
}

/// Escreve o resumo do dia para os widgets e pede-lhes que se atualizem.
enum WidgetSnapshotWriter {
    @MainActor static func write(_ store: DataStore) {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        let plan = store.plan(for: today)
        let items = plan.blocks.filter { $0.kind != .free && !$0.done }.map {
            WidgetSnapshot.Item(start: $0.range.start.date(on: today), end: $0.range.end.date(on: today), title: $0.title, isTask: $0.kind == .task)
        }
        let prio = store.priorities(on: today).compactMap { id -> WidgetSnapshot.Priority? in
            guard let t = store.task(id) else { return nil }
            return .init(title: t.title, done: store.status(t, on: today) == .done)
        }
        let tasks = store.tasks(on: today)
        let done = tasks.filter { store.status($0, on: today) == .done }.count
        let xpToday = Progression(store: store).events().filter { Calendar.current.isDate($0.date, inSameDayAs: today) }.reduce(0) { $0 + $1.amount }
        let snap = WidgetSnapshot(generatedAt: now, dayTitle: plan.context.info.kind.title + (plan.context.isRecovery ? " · Recovery" : ""),
                                  items: items, priorities: prio, done: done, total: tasks.count,
                                  leaveHome: plan.context.commuteOut.map { $0.start.date(on: today) },
                                  level: Progression(store: store).totalLevel(), xpToday: xpToday,
                                  warning: (plan.warnings + plan.conflicts).first)
        SharedStore.write(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
