import SwiftUI
import SwiftData
import LifeResetCore

/// Sunday Reset: configurar a semana (turnos, folgas, Recovery, horas extra), prioridades e notas.
struct SundayResetView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var weekStart: Date = SundayResetView.defaultWeek()
    @State private var days: [DayDraft] = []
    @State private var expanded: Date?
    @State private var priorities = ["", "", ""]
    @State private var training = ""
    @State private var shopping = ""
    @State private var cleaning = ""
    @State private var mealPrep = ""
    @State private var changes: [PlanChange] = []
    @State private var showProposals = false

    private var store: DataStore { DataStore(ctx: ctx) }

    /// Ao domingo prepara a semana seguinte; nos outros dias, a semana atual.
    static func defaultWeek() -> Date {
        let today = Date()
        let start = LRCalendar.weekStart(for: today)
        return LRCalendar.current.component(.weekday, from: today) == 1 ? LRCalendar.addDays(7, to: start) : start
    }

    private var issues: [WeekValidator.Issue] {
        let jobs = store.jobs()
        let burger = jobs.first { $0.kind == .burger }?.shiftsPerWeek ?? 4
        let cafe = jobs.first { $0.kind == .cafe }?.shiftsPerWeek ?? 1
        let p = store.profile()
        return WeekValidator.validate(days.map(\.info), expectedBurger: burger, expectedCafe: cafe,
                                      expectedOff: p.daysOffPerWeek, maxRecovery: p.maxRecoveryDays)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Button { load(LRCalendar.addDays(-7, to: weekStart)) } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        Text("Semana de \(Fmt.shortDate(weekStart))").font(.lrHeadline)
                        Spacer()
                        Button { load(LRCalendar.addDays(7, to: weekStart)) } label: { Image(systemName: "chevron.right") }
                    }.buttonStyle(.plain)
                    Button("Copiar a semana anterior") { copyPrevious() }
                }

                Section("Dias") {
                    ForEach(days.indices, id: \.self) { i in
                        dayRow(i)
                    }
                }

                let list = issues
                if !list.isEmpty {
                    Section("Verificação") {
                        ForEach(list, id: \.self) { issue in
                            Label(issue.message, systemImage: issue.level == .error ? "xmark.octagon" : "exclamationmark.triangle")
                                .foregroundStyle(issue.level == .error ? Theme.negative : Theme.warning)
                                .font(.lrBody)
                        }
                    }
                }

                Section("Prioridades da semana") {
                    ForEach(0..<3, id: \.self) { i in TextField("Prioridade \(i + 1)", text: $priorities[i]) }
                }
                Section("Notas") {
                    TextField("Treinos", text: $training, axis: .vertical)
                    TextField("Compras", text: $shopping, axis: .vertical)
                    TextField("Limpezas", text: $cleaning, axis: .vertical)
                    TextField("Preparação de refeições", text: $mealPrep, axis: .vertical)
                }
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("Sunday Reset").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: review).disabled(WeekValidator.hasErrors(issues))
                }
            }
            .onAppear { if days.isEmpty { load(weekStart) } }
            .sheet(isPresented: $showProposals) {
                ProposalsSheet(changes: changes, warnings: []) { save() }.presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private func dayRow(_ i: Int) -> some View {
        let d = days[i]
        let wd = LRCalendar.current.component(.weekday, from: d.date)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(LRCalendar.weekdayName(wd)).font(.lrHeadline).frame(width: 110, alignment: .leading)
                Picker("", selection: Binding(get: { days[i].kind }, set: { days[i].setKind($0, store: store) })) {
                    ForEach(DayKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                Spacer()
                if d.kind.isWork {
                    Button { expanded = expanded == d.date ? nil : d.date } label: {
                        Image(systemName: expanded == d.date ? "chevron.up" : "slider.horizontal.3")
                    }.buttonStyle(.plain)
                }
            }
            if d.kind.isWork {
                Text("\(d.shiftStart.description)–\(d.shiftEnd.description)\(d.overtime > 0 ? " +\(d.overtime) min" : "") · sair \(d.leaveHome.description)")
                    .font(.lrCaption).foregroundStyle(Theme.textSecondary)
            }
            Toggle("Recovery", isOn: $days[i].recovery).font(.lrCaption)
        }
        if expanded == d.date && d.kind.isWork {
            DayFields(draft: $days[i])
        }
    }

    private func load(_ start: Date) {
        weekStart = start
        let existing = LRCalendar.days(ofWeekStarting: start).map { store.assignment(for: $0) }
        if existing.allSatisfy({ $0 == nil }) {
            days = template(for: start)
        } else {
            days = LRCalendar.days(ofWeekStarting: start).map { DayDraft(store.dayInfo(for: $0).info) }
        }
        let s = start, e = LRCalendar.addDays(1, to: start)
        let plan = (try? ctx.fetch(FetchDescriptor<WeekPlan>(predicate: #Predicate { $0.weekStart >= s && $0.weekStart < e })))?.first
        let p = plan?.priorities ?? []
        priorities = (0..<3).map { $0 < p.count ? p[$0] : "" }
        training = plan?.trainingNotes ?? ""; shopping = plan?.shoppingNotes ?? ""
        cleaning = plan?.cleaningNotes ?? ""; mealPrep = plan?.mealPrepNotes ?? ""
    }

    /// Semana base: café ao domingo, folgas a quarta e sábado, hambúrgueres nos restantes (ajustável).
    private func template(for start: Date) -> [DayDraft] {
        LRCalendar.days(ofWeekStarting: start).map { date in
            var d = DayDraft(DayInfo(date: date, kind: .dayOff))
            let wd = LRCalendar.current.component(.weekday, from: date)
            switch wd {
            case 1: d.setKind(.cafeShift, store: store)
            case 4, 7: d.setKind(.dayOff, store: store)
            default: d.setKind(.burgerShift, store: store)
            }
            return d
        }
    }

    private func copyPrevious() {
        let prev = LRCalendar.addDays(-7, to: weekStart)
        days = LRCalendar.days(ofWeekStarting: prev).enumerated().map { i, date in
            var info = store.dayInfo(for: date).info
            info.date = LRCalendar.addDays(7, to: date); info.overtimeMinutes = 0; info.isRecovery = false
            if info.kind == .travel { info.kind = .dayOff }
            _ = i
            return DayDraft(info)
        }
    }

    private func review() {
        // Mostrar o impacto em hoje, se hoje faz parte da semana editada.
        let today = Calendar.current.startOfDay(for: Date())
        if let d = days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
            changes = PlanDiff.changes(from: store.plan(for: today), to: store.plan(for: today, overriding: d.info))
        } else { changes = [] }
        if changes.isEmpty { save() } else { showProposals = true }
    }

    private func save() {
        for d in days { store.saveDay(d.info) }
        let s = weekStart, e = LRCalendar.addDays(1, to: weekStart)
        let plan = (try? ctx.fetch(FetchDescriptor<WeekPlan>(predicate: #Predicate { $0.weekStart >= s && $0.weekStart < e })))?.first
            ?? { let n = WeekPlan(weekStart: weekStart); ctx.insert(n); return n }()
        plan.priorities = priorities.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        plan.trainingNotes = training; plan.shoppingNotes = shopping; plan.cleaningNotes = cleaning; plan.mealPrepNotes = mealPrep
        plan.confirmed = true; plan.updatedAt = Date()
        store.setMeta("sundayReset.last", LRCalendar.dayKey(Date()))
        store.save()
        dismiss()
    }
}
