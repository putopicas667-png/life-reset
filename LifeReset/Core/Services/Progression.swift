import Foundation
import SwiftData
import LifeResetCore

/// Livro de XP (só acrescenta; a única remoção é anular uma marcação feita por engano no próprio dia).
@MainActor
struct Progression {
    let store: DataStore
    var ctx: ModelContext { store.ctx }

    func events() -> [XPEvent] { (try? ctx.fetch(FetchDescriptor<XPEvent>(sortBy: [SortDescriptor(\.date)]))) ?? [] }

    func totalXP() -> Int { events().reduce(0) { $0 + $1.amount } }

    func xp(for area: XPArea) -> Int {
        let raw = area.rawValue
        let d = FetchDescriptor<XPEvent>(predicate: #Predicate { $0.area == raw })
        return ((try? ctx.fetch(d)) ?? []).reduce(0) { $0 + $1.amount }
    }

    func maxLevel(_ key: String) -> Int { Int(store.meta("maxLevel.\(key)") ?? "1") ?? 1 }

    func level(for area: XPArea) -> Int { XPRules.displayedLevel(xp: xp(for: area), maxEverReached: maxLevel(area.rawValue)) }
    func totalLevel() -> Int { XPRules.displayedLevel(xp: totalXP(), maxEverReached: maxLevel("total")) }

    func award(_ amount: Int, area: XPArea, source: String, key: String, date: Date = Date()) {
        guard amount > 0 else { return }
        let d = FetchDescriptor<XPEvent>(predicate: #Predicate { $0.sourceKey == key })
        if ((try? ctx.fetchCount(d)) ?? 0) > 0 { return } // nunca duplicar
        ctx.insert(XPEvent(date: date, area: area.rawValue, amount: amount, source: source, sourceKey: key))
        recordMaxLevels(area: area)
    }

    func revoke(key: String) {
        let d = FetchDescriptor<XPEvent>(predicate: #Predicate { $0.sourceKey == key })
        for e in (try? ctx.fetch(d)) ?? [] { ctx.delete(e) }
    }

    /// Bónus quando todas as tarefas essenciais do dia estão feitas.
    func checkAllEssentialsBonus(on day: Date) {
        let essentials = store.tasks(on: day).filter(\.essential)
        guard !essentials.isEmpty, essentials.allSatisfy({ store.status($0, on: day) == .done }) else { return }
        award(XPRules.allEssentialsBonus, area: .health, source: "Todas as tarefas essenciais",
              key: "essentials:\(LRCalendar.dayKey(day))", date: day)
    }

    private func recordMaxLevels(area: XPArea) {
        let total = XPRules.level(forXP: totalXP())
        if total > maxLevel("total") { store.setMeta("maxLevel.total", String(total)) }
        let a = XPRules.level(forXP: xp(for: area))
        if a > maxLevel(area.rawValue) { store.setMeta("maxLevel.\(area.rawValue)", String(a)) }
    }

    /// Dias com pelo menos 80% das tarefas concluídas (para sequências).
    func completedDayKeys(lastDays: Int = 120) -> Set<String> {
        var out = Set<String>()
        let today = Calendar.current.startOfDay(for: Date())
        for i in 0..<lastDays {
            let d = LRCalendar.addDays(-i, to: today)
            let tasks = store.tasks(on: d)
            guard !tasks.isEmpty else { continue }
            let done = tasks.filter { store.status($0, on: d) == .done }.count
            if Double(done) / Double(tasks.count) >= 0.8 { out.insert(LRCalendar.dayKey(d)) }
        }
        return out
    }
}
