import Foundation
import SwiftData
import LifeResetCore

/// Consultas e regras de finanças (valores sempre em CHF, nunca liga ao banco).
extension DataStore {
    func monthRange(_ date: Date) -> (Date, Date) {
        let s = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
        return (s, cal.date(byAdding: .month, value: 1, to: s) ?? s)
    }

    func incomes(in month: Date) -> [IncomeEntry] {
        let (s, e) = monthRange(month)
        let d = FetchDescriptor<IncomeEntry>(predicate: #Predicate { $0.date >= s && $0.date < e }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? ctx.fetch(d)) ?? []
    }

    func expenses(in month: Date) -> [Expense] {
        let (s, e) = monthRange(month)
        let d = FetchDescriptor<Expense>(predicate: #Predicate { $0.date >= s && $0.date < e }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? ctx.fetch(d)) ?? []
    }

    func fixedExpenses() -> [FixedExpense] {
        let d = FetchDescriptor<FixedExpense>(predicate: #Predicate { $0.active }, sortBy: [SortDescriptor(\.dayOfMonth)])
        return (try? ctx.fetch(d)) ?? []
    }

    /// Uma despesa fixa conta como paga quando há uma despesa marcada como fixa com o mesmo nome nesse mês.
    func isPaid(_ f: FixedExpense, in month: Date) -> Bool {
        expenses(in: month).contains { $0.isFixed && $0.desc == f.name }
    }

    func markPaid(_ f: FixedExpense, amount: Decimal? = nil, on date: Date = Date()) {
        let e = Expense(amount: amount ?? f.amount, date: date, category: f.category, desc: f.name)
        e.isFixed = true; e.paymentType = "Débito direto"
        ctx.insert(e)
        save()
    }

    func forecast(for month: Date) -> MonthForecast {
        let inc = incomes(in: month).reduce(Decimal(0)) { $0 + $1.amount }
        let exp = expenses(in: month)
        let spent = exp.reduce(Decimal(0)) { $0 + $1.amount }
        let variable = exp.filter { !$0.isFixed }.reduce(Decimal(0)) { $0 + $1.amount }
        let fixed = fixedExpenses().map { FinanceMath.FixedItem(amount: $0.amount, dayOfMonth: $0.dayOfMonth, paid: isPaid($0, in: month)) }
        let (s, e) = monthRange(month)
        let days = cal.dateComponents([.day], from: s, to: e).day ?? 30
        let now = Date()
        let day: Int
        if now < s { day = 1 } else if now >= e { day = days } else { day = cal.component(.day, from: now) }
        return FinanceMath.forecast(income: inc, spent: spent, variableSpent: variable, fixed: fixed, day: day, daysInMonth: days)
    }

    func spendingByCategory(in month: Date) -> [(String, Decimal)] {
        var out: [String: Decimal] = [:]
        for e in expenses(in: month) { out[e.category.isEmpty ? "Outros" : e.category, default: 0] += e.amount }
        return out.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    func categories() -> [ExpenseCategory] {
        (try? ctx.fetch(FetchDescriptor<ExpenseCategory>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    func debtRemaining(_ d: Debt) -> Decimal {
        let uid = d.uid
        let p = (try? ctx.fetch(FetchDescriptor<DebtPayment>(predicate: #Predicate { $0.debtUID == uid }))) ?? []
        return FinanceMath.remaining(initial: d.initialAmount, payments: p.map(\.amount))
    }

    func saved(_ g: SavingsGoal) -> Decimal {
        let uid = g.uid
        let c = (try? ctx.fetch(FetchDescriptor<SavingsContribution>(predicate: #Predicate { $0.goalUID == uid }))) ?? []
        return c.reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Contribuição para uma poupança; cada marco novo (25/50/75/100 %) dá XP de finanças.
    func contribute(_ amount: Decimal, to g: SavingsGoal) {
        let before = saved(g)
        ctx.insert(SavingsContribution(goalUID: g.uid, amount: amount, date: Date()))
        let reached = FinanceMath.milestonesReached(saved: before + amount, target: g.target)
        if reached > g.milestonesAwarded {
            for m in (g.milestonesAwarded + 1)...reached {
                Progression(store: self).award(XPRules.savingsMilestoneXP, area: .finance, source: "\(g.name): \(m * 25)%",
                                               key: "savings:\(g.uid.uuidString):\(m)")
            }
            g.milestonesAwarded = reached
        }
        save()
    }

    func pay(_ amount: Decimal, debt: Debt) {
        let before = debtRemaining(debt)
        ctx.insert(DebtPayment(debtUID: debt.uid, amount: amount, date: Date()))
        let e = Expense(amount: amount, date: Date(), category: "Dívidas", desc: "Pagamento: \(debt.creditor)")
        ctx.insert(e)
        if before - amount <= 0 {
            debt.settled = true
            Progression(store: self).award(50, area: .finance, source: "Dívida liquidada: \(debt.creditor)", key: "debt:\(debt.uid.uuidString)")
        }
        save()
    }

    func accountBalance(_ a: Account) -> Decimal {
        let name = a.name
        let inc = (try? ctx.fetch(FetchDescriptor<IncomeEntry>(predicate: #Predicate { $0.accountName == name }))) ?? []
        let exp = (try? ctx.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.accountName == name }))) ?? []
        return a.openingBalance + inc.reduce(Decimal(0)) { $0 + $1.amount } - exp.reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Relatório do mês anterior (criado uma vez, ao abrir a app no mês seguinte).
    func ensureMonthlyReport() {
        let prev = cal.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let key = LRCalendar.monthKey(prev)
        let d = FetchDescriptor<MonthlyReport>(predicate: #Predicate { $0.monthKey == key })
        guard ((try? ctx.fetchCount(d)) ?? 0) == 0 else { return }
        let inc = incomes(in: prev), exp = expenses(in: prev)
        guard !inc.isEmpty || !exp.isEmpty else { return }
        let r = MonthlyReport(monthKey: key)
        r.income = inc.reduce(0) { $0 + $1.amount }
        r.expenses = exp.reduce(0) { $0 + $1.amount }
        r.fixed = exp.filter(\.isFixed).reduce(0) { $0 + $1.amount }
        let (s, e) = monthRange(prev)
        let contrib = (try? ctx.fetch(FetchDescriptor<SavingsContribution>(predicate: #Predicate { $0.date >= s && $0.date < e }))) ?? []
        r.saved = contrib.reduce(0) { $0 + $1.amount }
        r.topCategory = spendingByCategory(in: prev).first?.0 ?? ""
        ctx.insert(r)
    }
}
