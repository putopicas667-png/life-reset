import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers
import LifeResetCore

// MARK: - Poupanças

struct SavingsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \SavingsGoal.name) private var goals: [SavingsGoal]
    @Query private var contributions: [SavingsContribution]
    @State private var name = ""
    @State private var target = ""
    @State private var amounts: [UUID: String] = [:]

    var body: some View {
        let store = DataStore(ctx: ctx)
        let _ = contributions.count
        return List {
            Section("Nova poupança") {
                TextField("Nome (ex.: Fundo de emergência)", text: $name)
                AmountField(title: "Objetivo", text: $target)
                Button("Criar") {
                    guard let t = FinanceMath.parseAmount(target), t > 0 else { return }
                    ctx.insert(SavingsGoal(name: name, target: t)); store.save(); name = ""; target = ""
                }.disabled(name.isEmpty || FinanceMath.parseAmount(target) == nil)
            }
            ForEach(goals) { g in
                let s = store.saved(g)
                Section(g.name) {
                    KeyValueRow(key: "Poupado", value: "\(Fmt.chf(s)) de \(Fmt.chf(g.target))")
                    ThinProgressBar(value: g.target > 0 ? s.double / g.target.double : 0, tint: s >= g.target ? Theme.positive : Theme.accent)
                    HStack {
                        AmountField(title: "Valor", text: Binding(get: { amounts[g.uid] ?? "" }, set: { amounts[g.uid] = $0 }))
                        Button("Juntar") {
                            if let v = FinanceMath.parseAmount(amounts[g.uid] ?? ""), v > 0 { store.contribute(v, to: g); amounts[g.uid] = "" }
                        }.buttonStyle(.bordered)
                    }
                    Text("Cada marco (25, 50, 75 e 100 %) dá XP de finanças.").font(.lrCaption).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle("Poupanças")
    }
}

// MARK: - Dívidas

struct DebtsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Debt.date) private var debts: [Debt]
    @Query private var payments: [DebtPayment]
    @State private var creditor = ""
    @State private var amount = ""
    @State private var hasDue = false
    @State private var due = Date()
    @State private var pay: [UUID: String] = [:]

    var body: some View {
        let store = DataStore(ctx: ctx)
        let _ = payments.count
        let open = debts.filter { !$0.settled }
        let total = open.reduce(Decimal(0)) { $0 + store.debtRemaining($1) }
        return List {
            Section { KeyValueRow(key: "Total em dívida", value: Fmt.chf(total)) }
            Section("Nova dívida") {
                TextField("A quem", text: $creditor)
                AmountField(title: "Valor inicial", text: $amount)
                Toggle("Tem prazo", isOn: $hasDue)
                if hasDue { DatePicker("Prazo", selection: $due, displayedComponents: .date) }
                Button("Guardar") {
                    guard let v = FinanceMath.parseAmount(amount), v > 0 else { return }
                    let d = Debt(creditor: creditor, initialAmount: v); d.dueDate = hasDue ? due : nil
                    ctx.insert(d); store.save(); creditor = ""; amount = ""
                }.disabled(creditor.isEmpty || FinanceMath.parseAmount(amount) == nil)
            }
            ForEach(debts) { d in
                let rem = store.debtRemaining(d)
                Section(d.creditor + (d.settled ? " · liquidada" : "")) {
                    KeyValueRow(key: "Em falta", value: "\(Fmt.chf(rem)) de \(Fmt.chf(d.initialAmount))")
                    ThinProgressBar(value: d.initialAmount > 0 ? 1 - rem.double / d.initialAmount.double : 1, tint: Theme.positive)
                    if let due = d.dueDate { KeyValueRow(key: "Prazo", value: Fmt.shortDate(due)) }
                    if !d.settled {
                        HStack {
                            AmountField(title: "Pagamento", text: Binding(get: { pay[d.uid] ?? "" }, set: { pay[d.uid] = $0 }))
                            Button("Pagar") {
                                if let v = FinanceMath.parseAmount(pay[d.uid] ?? ""), v > 0 { store.pay(min(v, rem), debt: d); pay[d.uid] = "" }
                            }.buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle("Dívidas")
    }
}

// MARK: - Orçamentos

struct BudgetsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Budget.category) private var budgets: [Budget]
    @Query(sort: \ExpenseCategory.name) private var cats: [ExpenseCategory]
    @State private var category = "Alimentação"
    @State private var limit = ""

    var body: some View {
        List {
            Section("Novo orçamento mensal") {
                Picker("Categoria", selection: $category) { ForEach(cats) { Text($0.name).tag($0.name) } }
                AmountField(title: "Limite por mês", text: $limit)
                Button("Guardar") {
                    guard let v = FinanceMath.parseAmount(limit), v > 0 else { return }
                    if let b = budgets.first(where: { $0.category == category }) { b.monthlyLimit = v }
                    else { ctx.insert(Budget(category: category, monthlyLimit: v)) }
                    DataStore(ctx: ctx).save(); limit = ""
                }
            }
            Section("Orçamentos") {
                ForEach(budgets) { b in KeyValueRow(key: b.category, value: Fmt.chf(b.monthlyLimit)) }
                    .onDelete { idx in for i in idx { ctx.delete(budgets[i]) }; DataStore(ctx: ctx).save() }
            }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle("Orçamentos")
    }
}

// MARK: - Despesas fixas

struct FixedExpensesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \FixedExpense.dayOfMonth) private var fixed: [FixedExpense]
    @Query(sort: \ExpenseCategory.name) private var cats: [ExpenseCategory]
    @State private var name = ""
    @State private var amount = ""
    @State private var day = 1
    @State private var estimate = false
    @State private var category = "Casa"

    var body: some View {
        let total = fixed.filter(\.active).reduce(Decimal(0)) { $0 + $1.amount }
        return List {
            Section { KeyValueRow(key: "Total por mês", value: Fmt.chf(total)) }
            Section("Nova despesa fixa") {
                TextField("Nome", text: $name)
                AmountField(title: "Valor", text: $amount)
                Stepper("Dia \(day) do mês", value: $day, in: 1...31)
                Picker("Categoria", selection: $category) { ForEach(cats) { Text($0.name).tag($0.name) } }
                Toggle("Valor estimado", isOn: $estimate)
                Button("Guardar") {
                    guard let v = FinanceMath.parseAmount(amount) else { return }
                    ctx.insert(FixedExpense(name: name, amount: v, isEstimate: estimate, dayOfMonth: day, category: category))
                    DataStore(ctx: ctx).save(); name = ""; amount = ""
                }.disabled(name.isEmpty || FinanceMath.parseAmount(amount) == nil)
            }
            Section("Fixas") {
                ForEach(fixed) { f in
                    Toggle(isOn: Binding(get: { f.active }, set: { f.active = $0; DataStore(ctx: ctx).save() })) {
                        VStack(alignment: .leading) {
                            Text(f.name)
                            Text("\(Fmt.chf(f.amount)) · dia \(f.dayOfMonth)\(f.isEstimate ? " · estimativa" : "")").font(.lrCaption).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .onDelete { idx in for i in idx { ctx.delete(fixed[i]) }; DataStore(ctx: ctx).save() }
            }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle("Despesas fixas")
    }
}

// MARK: - Contas

struct AccountsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query private var incomesQ: [IncomeEntry]
    @Query private var expensesQ: [Expense]
    @State private var name = ""
    @State private var opening = ""

    var body: some View {
        let store = DataStore(ctx: ctx)
        let _ = incomesQ.count + expensesQ.count
        return List {
            Section {
                TextField("Nome (ex.: Conta principal)", text: $name)
                AmountField(title: "Saldo inicial", text: $opening)
                Button("Adicionar") {
                    ctx.insert(Account(name: name, openingBalance: FinanceMath.parseAmount(opening) ?? 0)); store.save(); name = ""; opening = ""
                }.disabled(name.isEmpty)
            } header: { Text("Nova conta") } footer: {
                Text("Só registos manuais ou importados de CSV. A app nunca pede credenciais bancárias.")
            }
            Section("Contas") {
                ForEach(accounts) { a in KeyValueRow(key: a.name, value: Fmt.chf(store.accountBalance(a))) }
                    .onDelete { idx in for i in idx { ctx.delete(accounts[i]) }; store.save() }
            }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle("Contas")
    }
}

// MARK: - Relatórios

struct ReportsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \MonthlyReport.monthKey, order: .reverse) private var reports: [MonthlyReport]

    var body: some View {
        let store = DataStore(ctx: ctx)
        let cal = Calendar.current
        let months: [Date] = (0..<6).reversed().compactMap { cal.date(byAdding: .month, value: -$0, to: Date()) }
        let series: [(String, String, Double)] = months.flatMap { m -> [(String, String, Double)] in
            let label = Fmt.shortMonth(m)
            return [(label, "Entradas", store.incomes(in: m).reduce(Decimal(0)) { $0 + $1.amount }.double),
                    (label, "Saídas", store.expenses(in: m).reduce(Decimal(0)) { $0 + $1.amount }.double)]
        }
        return List {
            Section("Últimos 6 meses") {
                Chart(series.indices, id: \.self) { i in
                    BarMark(x: .value("Mês", series[i].0), y: .value("CHF", series[i].2))
                        .foregroundStyle(by: .value("Tipo", series[i].1))
                        .position(by: .value("Tipo", series[i].1))
                }
                .chartForegroundStyleScale(["Entradas": Theme.positive, "Saídas": Theme.negative])
                .frame(height: 200)
            }
            Section("Relatórios") {
                if reports.isEmpty { Text("O primeiro relatório aparece no início do próximo mês.").foregroundStyle(Theme.textSecondary) }
                ForEach(reports) { r in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.monthKey).font(.lrHeadline)
                        KeyValueRow(key: "Entradas", value: Fmt.chf(r.income))
                        KeyValueRow(key: "Saídas", value: Fmt.chf(r.expenses))
                        KeyValueRow(key: "Das quais fixas", value: Fmt.chf(r.fixed))
                        KeyValueRow(key: "Poupado", value: Fmt.chf(r.saved))
                        KeyValueRow(key: "Saldo", value: Fmt.chf(r.income - r.expenses, sign: true))
                        if !r.topCategory.isEmpty { KeyValueRow(key: "Maior categoria", value: r.topCategory) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle("Relatórios")
    }
}

// MARK: - Importar CSV

struct CSVImportView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \ExpenseCategory.name) private var cats: [ExpenseCategory]
    @State private var picking = false
    @State private var rows: [CSVImport.Row] = []
    @State private var categories: [String] = []
    @State private var include: [Bool] = []
    @State private var skipped = 0
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Button("Escolher ficheiro CSV") { picking = true }
            } footer: {
                Text("Exporta o extrato no site/app do banco e abre-o aqui. As linhas repetidas são ignoradas.")
            }
            if let message { Section { Text(message).foregroundStyle(Theme.positive) } }
            if !rows.isEmpty {
                Section("Pré-visualização (\(rows.count) linhas\(skipped > 0 ? ", \(skipped) ignoradas" : ""))") {
                    ForEach(rows.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Toggle("", isOn: $include[i]).labelsHidden()
                                VStack(alignment: .leading) {
                                    Text(rows[i].description.isEmpty ? "—" : rows[i].description).lineLimit(1)
                                    Text(Fmt.shortDate(rows[i].date)).font(.lrCaption).foregroundStyle(Theme.textTertiary)
                                }
                                Spacer()
                                Text(Fmt.chf(rows[i].amount, sign: true)).monospacedDigit()
                                    .foregroundStyle(rows[i].amount > 0 ? Theme.positive : Theme.textPrimary)
                            }
                            if rows[i].amount < 0 {
                                Picker("Categoria", selection: $categories[i]) { ForEach(cats) { Text($0.name).tag($0.name) } }
                                    .font(.lrCaption)
                            }
                        }
                    }
                }
                Section { Button("Importar selecionadas", action: importRows).buttonStyle(.borderedProminent) }
            }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle("Importar CSV")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { message = "Não foi possível ler o ficheiro."; return }
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            let r = CSVImport.parse(text)
            rows = r.rows; skipped = r.skipped
            categories = r.rows.map { CSVImport.suggestCategory($0.description) }
            include = Array(repeating: true, count: r.rows.count)
            message = nil
        }
    }

    private func importRows() {
        let store = DataStore(ctx: ctx)
        var added = 0, dup = 0
        for (i, r) in rows.enumerated() where include[i] {
            let h = r.hash
            let e = (try? ctx.fetchCount(FetchDescriptor<Expense>(predicate: #Predicate { $0.importHash == h }))) ?? 0
            let n = (try? ctx.fetchCount(FetchDescriptor<IncomeEntry>(predicate: #Predicate { $0.importHash == h }))) ?? 0
            if e + n > 0 { dup += 1; continue }
            if r.amount < 0 {
                let x = Expense(amount: -r.amount, date: r.date, category: categories[i], desc: r.description)
                x.importHash = h; x.paymentType = "Importado"; ctx.insert(x)
            } else {
                let x = IncomeEntry(amount: r.amount, date: r.date, kind: "other", note: r.description)
                x.importHash = h; ctx.insert(x)
            }
            added += 1
        }
        store.save()
        message = "Importadas \(added) linhas\(dup > 0 ? " (\(dup) repetidas ignoradas)" : "")."
        rows = []; include = []; categories = []
    }
}
