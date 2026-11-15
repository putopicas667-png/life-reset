import SwiftUI
import SwiftData
import Charts
import LifeResetCore

/// Separador Finance: resumo do mês, previsão (estimativa), gastos por categoria, orçamentos e movimentos.
struct FinanceView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var incomesQ: [IncomeEntry]
    @Query private var expensesQ: [Expense]
    @Query private var budgetsQ: [Budget]
    @Query private var fixedQ: [FixedExpense]
    @State private var month = Date()
    @State private var addExpense = false
    @State private var addIncome = false

    private var store: DataStore { DataStore(ctx: ctx) }

    var body: some View {
        NavigationStack {
            let _ = incomesQ.count + expensesQ.count + budgetsQ.count + fixedQ.count
            let inc = store.incomes(in: month), exp = store.expenses(in: month)
            let totalIn = inc.reduce(Decimal(0)) { $0 + $1.amount }, totalOut = exp.reduce(Decimal(0)) { $0 + $1.amount }
            let f = store.forecast(for: month)
            let byCat = store.spendingByCategory(in: month)
            ScrollView {
                VStack(spacing: Theme.spacing) {
                    HStack {
                        Button { month = Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month } label: { Image(systemName: "chevron.left") }
                        Spacer(); Text(Fmt.monthTitle(month)).font(.lrHeadline); Spacer()
                        Button { month = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.right") }
                    }.buttonStyle(.plain).padding(.horizontal, 4)

                    Card(title: "Resumo", systemImage: "francsign.circle") {
                        HStack {
                            StatTile(value: Fmt.chf(totalIn), label: "entradas")
                            StatTile(value: Fmt.chf(totalOut), label: "saídas")
                        }
                        KeyValueRow(key: "Saldo do mês", value: Fmt.chf(totalIn - totalOut, sign: true))
                        Divider().overlay(Theme.separator)
                        Text("Previsão para o fim do mês (estimativa)").font(.lrCaption).foregroundStyle(Theme.textSecondary)
                        KeyValueRow(key: "Fixas por pagar", value: Fmt.chf(f.fixedPending))
                        KeyValueRow(key: "Gastos variáveis previstos", value: Fmt.chf(f.variableProjection))
                        KeyValueRow(key: "Saldo previsto", value: Fmt.chf(f.endBalance, sign: true))
                            .foregroundStyle(f.endBalance < 0 ? Theme.negative : Theme.textPrimary)
                        Text("Baseado no ritmo de gastos até hoje e nas despesas fixas ainda não pagas.")
                            .font(.lrCaption).foregroundStyle(Theme.textTertiary)
                    }

                    HStack {
                        Button { addExpense = true } label: { Label("Despesa", systemImage: "minus.circle") }.buttonStyle(.borderedProminent)
                        Button { addIncome = true } label: { Label("Entrada", systemImage: "plus.circle") }.buttonStyle(.bordered)
                    }

                    if !byCat.isEmpty {
                        Card(title: "Gastos por categoria", systemImage: "chart.bar") {
                            Chart(byCat, id: \.0) { c in
                                BarMark(x: .value("CHF", c.1.double), y: .value("Categoria", c.0)).foregroundStyle(Theme.accent)
                            }
                            .frame(height: CGFloat(max(1, byCat.count)) * 28 + 20)
                        }
                    }

                    budgetsCard

                    Card(title: "Despesas fixas", systemImage: "repeat") {
                        ForEach(store.fixedExpenses()) { fx in
                            let paid = store.isPaid(fx, in: month)
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(fx.name).font(.lrBody)
                                    Text("Dia \(fx.dayOfMonth)\(fx.isEstimate ? " · estimativa" : "")").font(.lrCaption).foregroundStyle(Theme.textTertiary)
                                }
                                Spacer()
                                Text(Fmt.chf(fx.amount)).font(.lrBody.monospacedDigit())
                                Button(paid ? "Paga" : "Marcar") { if !paid { store.markPaid(fx, on: min(Date(), store.monthRange(month).1.addingTimeInterval(-60))) } }
                                    .buttonStyle(.bordered).tint(paid ? Theme.positive : Theme.accent).disabled(paid)
                            }
                        }
                    }

                    VStack(spacing: 1) {
                        nav("Movimentos do mês", "list.bullet") { TransactionsView(month: month) }
                        nav("Poupanças", "banknote") { SavingsView() }
                        nav("Dívidas", "creditcard") { DebtsView() }
                        nav("Orçamentos", "gauge.with.dots.needle.33percent") { BudgetsView() }
                        nav("Despesas fixas", "repeat") { FixedExpensesView() }
                        nav("Contas", "building.columns") { AccountsView() }
                        nav("Relatórios mensais", "doc.text") { ReportsView() }
                        nav("Importar extrato (CSV)", "square.and.arrow.down") { CSVImportView() }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                }
                .padding(Theme.pagePadding)
            }
            .lrScreenBackground()
            .navigationTitle("Finance")
            .sheet(isPresented: $addExpense) { AddExpenseSheet() }
            .sheet(isPresented: $addIncome) { AddIncomeSheet() }
        }
    }

    private var budgetsCard: some View {
        let byCat = Dictionary(uniqueKeysWithValues: store.spendingByCategory(in: month).map { ($0.0, $0.1) })
        return Group {
            if !budgetsQ.isEmpty {
                Card(title: "Orçamentos", systemImage: "gauge.with.dots.needle.33percent") {
                    ForEach(budgetsQ) { b in
                        let spent = byCat[b.category] ?? 0
                        let ratio = b.monthlyLimit > 0 ? spent.double / b.monthlyLimit.double : 0
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(b.category)
                                Spacer()
                                Text("\(Fmt.chf(spent)) / \(Fmt.chf(b.monthlyLimit))").monospacedDigit()
                            }.font(.lrBody)
                            ThinProgressBar(value: ratio, tint: ratio > 1 ? Theme.negative : ratio > 0.8 ? Theme.warning : Theme.positive)
                        }
                    }
                }
            }
        }
    }

    private func nav<D: View>(_ title: String, _ icon: String, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink(destination: destination) {
            HStack {
                Image(systemName: icon).frame(width: 26).foregroundStyle(Theme.accent)
                Text(title).foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
            }
            .padding(14).background(Theme.surface)
        }.buttonStyle(.plain)
    }
}

// MARK: - Adicionar

struct AmountField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        HStack {
            Text("CHF").foregroundStyle(Theme.textSecondary)
            TextField(title, text: $text).keyboardType(.decimalPad)
        }
    }
}

struct AddExpenseSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ExpenseCategory.name) private var cats: [ExpenseCategory]
    @Query(sort: \Account.name) private var accounts: [Account]
    @State private var amount = ""
    @State private var desc = ""
    @State private var category = "Alimentação"
    @State private var payment = "Cartão"
    @State private var account = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                AmountField(title: "Valor", text: $amount)
                TextField("Descrição", text: $desc)
                Picker("Categoria", selection: $category) { ForEach(cats) { Label($0.name, systemImage: $0.icon).tag($0.name) } }
                Picker("Pagamento", selection: $payment) { ForEach(["Cartão", "Dinheiro", "Twint", "Transferência", "Débito direto"], id: \.self) { Text($0) } }
                if !accounts.isEmpty {
                    Picker("Conta", selection: $account) { Text("—").tag(""); ForEach(accounts) { Text($0.name).tag($0.name) } }
                }
                DatePicker("Data", selection: $date, displayedComponents: .date)
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("Nova despesa").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        guard let v = FinanceMath.parseAmount(amount), v > 0 else { return }
                        let e = Expense(amount: v, date: date, category: category, desc: desc)
                        e.paymentType = payment; e.accountName = account
                        ctx.insert(e); DataStore(ctx: ctx).save(); dismiss()
                    }.disabled(FinanceMath.parseAmount(amount) == nil)
                }
            }
        }
    }
}

struct AddIncomeSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var accounts: [Account]
    @State private var amount = ""
    @State private var note = ""
    @State private var kind = "salary"
    @State private var account = ""
    @State private var date = Date()

    static let kinds = [("salary", "Salário"), ("tips", "Gorjetas"), ("extra", "Horas extra"), ("other", "Outro")]

    var body: some View {
        NavigationStack {
            Form {
                AmountField(title: "Valor", text: $amount)
                Picker("Tipo", selection: $kind) { ForEach(Self.kinds, id: \.0) { Text($0.1).tag($0.0) } }
                TextField("Nota (ex.: Hambúrgueres, novembro)", text: $note)
                if !accounts.isEmpty {
                    Picker("Conta", selection: $account) { Text("—").tag(""); ForEach(accounts) { Text($0.name).tag($0.name) } }
                }
                DatePicker("Data", selection: $date, displayedComponents: .date)
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("Nova entrada").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        guard let v = FinanceMath.parseAmount(amount), v > 0 else { return }
                        let i = IncomeEntry(amount: v, date: date, kind: kind, note: note); i.accountName = account
                        ctx.insert(i); DataStore(ctx: ctx).save(); dismiss()
                    }.disabled(FinanceMath.parseAmount(amount) == nil)
                }
            }
        }
    }
}

// MARK: - Movimentos

struct TransactionsView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var incomesQ: [IncomeEntry]
    @Query private var expensesQ: [Expense]
    let month: Date

    var body: some View {
        let store = DataStore(ctx: ctx)
        let _ = incomesQ.count + expensesQ.count
        let inc = store.incomes(in: month), exp = store.expenses(in: month)
        return List {
            Section("Entradas") {
                if inc.isEmpty { Text("Sem entradas.").foregroundStyle(Theme.textSecondary) }
                ForEach(inc) { i in
                    row(AddIncomeSheet.kinds.first { $0.0 == i.kindRaw }?.1 ?? "Entrada", i.note, i.date, Fmt.chf(i.amount, sign: true), Theme.positive)
                }
                .onDelete { idx in for x in idx { ctx.delete(inc[x]) }; store.save() }
            }
            Section("Despesas") {
                if exp.isEmpty { Text("Sem despesas.").foregroundStyle(Theme.textSecondary) }
                ForEach(exp) { e in
                    row(e.desc.isEmpty ? e.category : e.desc, "\(e.category) · \(e.paymentType)\(e.isFixed ? " · fixa" : "")", e.date, Fmt.chf(-e.amount), Theme.textPrimary)
                }
                .onDelete { idx in for x in idx { ctx.delete(exp[x]) }; store.save() }
            }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle(Fmt.monthTitle(month))
    }

    private func row(_ title: String, _ sub: String, _ date: Date, _ value: String, _ color: Color) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                Text("\(Fmt.shortDate(date))\(sub.isEmpty ? "" : " · \(sub)")").font(.lrCaption).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(color)
        }
    }
}
