import SwiftUI
import SwiftData
import Charts
import LifeResetCore

extension DataStore {
    /// Estatísticas agregadas (usadas nas conquistas e no ecrã de progresso).
    func lifeStats(streakDays: Set<String>) -> LifeStats {
        var s = LifeStats()
        s.tasksDone = (try? ctx.fetchCount(FetchDescriptor<TaskOccurrence>(predicate: #Predicate { $0.statusRaw == "done" }))) ?? 0
        s.workouts = (try? ctx.fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0
        s.currentStreak = Streaks.current(completedDays: streakDays, today: Date())
        s.bestStreak = Streaks.best(completedDays: streakDays)
        s.waterGoalDays = (try? ctx.fetchCount(FetchDescriptor<XPEvent>(predicate: #Predicate { $0.sourceKey.starts(with: "water:") }))) ?? 0
        s.proteinGoalDays = (try? ctx.fetchCount(FetchDescriptor<XPEvent>(predicate: #Predicate { $0.sourceKey.starts(with: "protein:") }))) ?? 0
        s.weightEntries = (try? ctx.fetchCount(FetchDescriptor<WeightEntry>())) ?? 0
        s.savingsMilestones = (try? ctx.fetchCount(FetchDescriptor<XPEvent>(predicate: #Predicate { $0.sourceKey.starts(with: "savings:") }))) ?? 0
        s.debtsSettled = (try? ctx.fetchCount(FetchDescriptor<Debt>(predicate: #Predicate { $0.settled }))) ?? 0
        s.totalLevel = Progression(store: self).totalLevel()
        s.sundayResets = (try? ctx.fetchCount(FetchDescriptor<WeekPlan>(predicate: #Predicate { $0.confirmed }))) ?? 0
        s.tripsPlanned = (try? ctx.fetchCount(FetchDescriptor<Trip>())) ?? 0
        return s
    }

    /// Regista conquistas novas (para sempre) e devolve-as.
    @discardableResult
    func unlockAchievements(stats: LifeStats) -> [Achievement] {
        let have = Set(((try? ctx.fetch(FetchDescriptor<AchievementUnlock>())) ?? []).map(\.key))
        let new = Achievements.newlyUnlocked(stats: stats, already: have)
        for a in new { ctx.insert(AchievementUnlock(key: a.id)) }
        if !new.isEmpty { save() }
        return new
    }

    func dayRecords(lastDays: Int) -> [Insights.DayRecord] {
        let today = cal.startOfDay(for: Date())
        return (1...lastDays).compactMap { i in
            let d = LRCalendar.addDays(-i, to: today)
            let tasks = tasks(on: d)
            guard !tasks.isEmpty else { return nil }
            let done = tasks.filter { status($0, on: d) == .done }.count
            return Insights.DayRecord(date: d, kind: dayInfo(for: d).info.kind, done: done, total: tasks.count)
        }
    }
}

/// Separador Progress: níveis, áreas, sequências, objetivos, conquistas, estatísticas e observações.
struct ProgressTabView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \XPEvent.date, order: .reverse) private var events: [XPEvent]
    @Query(sort: \AchievementUnlock.date, order: .reverse) private var unlocks: [AchievementUnlock]
    @Query(sort: \Goal.createdAt) private var goals: [Goal]
    @State private var stats = LifeStats()
    @State private var insights: [String] = []
    @State private var records: [Insights.DayRecord] = []
    @State private var newGoal = false

    var body: some View {
        NavigationStack {
            let store = DataStore(ctx: ctx)
            let prog = Progression(store: store)
            let total = prog.totalXP()
            let level = prog.totalLevel()
            ScrollView {
                VStack(spacing: Theme.spacing) {
                    Card(title: "Nível total", systemImage: "chart.line.uptrend.xyaxis") {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(level)").font(.system(size: 44, weight: .bold, design: .rounded))
                            Text("\(total) XP").font(.lrBody).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(stats.currentStreak) dias").font(.lrHeadline)
                                Text("sequência (melhor: \(stats.bestStreak))").font(.lrCaption).foregroundStyle(Theme.textTertiary)
                            }
                        }
                        ThinProgressBar(value: XPRules.progress(forXP: total))
                        Text("Faltam \(max(0, XPRules.xpForLevel(XPRules.level(forXP: total) + 1) - total)) XP para o nível seguinte. Falhar nunca tira XP.")
                            .font(.lrCaption).foregroundStyle(Theme.textTertiary)
                    }

                    Card(title: "Áreas", systemImage: "square.grid.2x2") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(XPArea.allCases, id: \.self) { a in
                                let xp = prog.xp(for: a)
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(a.title, systemImage: a.symbol).font(.lrCaption).foregroundStyle(Theme.textSecondary)
                                    Text("Nível \(prog.level(for: a))").font(.lrHeadline)
                                    ThinProgressBar(value: XPRules.progress(forXP: xp))
                                }
                            }
                        }
                    }

                    if !records.isEmpty { weekChart }

                    if !insights.isEmpty {
                        Card(title: "Observações", systemImage: "lightbulb") {
                            ForEach(insights, id: \.self) { Text($0).font(.lrBody) }
                        }
                    }

                    goalsCard(store)
                    achievementsCard
                    statsCard

                    Card(title: "XP recente", systemImage: "clock.arrow.circlepath") {
                        if events.isEmpty { Text("Conclui tarefas para ganhar XP.").foregroundStyle(Theme.textSecondary) }
                        ForEach(events.prefix(12)) { e in
                            HStack {
                                Image(systemName: (XPArea(rawValue: e.area) ?? .personal).symbol).foregroundStyle(Theme.textTertiary).frame(width: 20)
                                Text(e.source).lineLimit(1)
                                Spacer()
                                Text("+\(e.amount)").monospacedDigit().foregroundStyle(Theme.positive)
                            }.font(.lrBody)
                        }
                    }
                }
                .padding(Theme.pagePadding)
            }
            .lrScreenBackground()
            .navigationTitle("Progress")
            .toolbar { Button { newGoal = true } label: { Image(systemName: "plus") }.accessibilityLabel("Novo objetivo") }
            .sheet(isPresented: $newGoal) { GoalEditView() }
            .task(id: events.count) { @MainActor in refresh() }
        }
    }

    @MainActor private func refresh() {
        let store = DataStore(ctx: ctx)
        let keys = Progression(store: store).completedDayKeys(lastDays: 90)
        stats = store.lifeStats(streakDays: keys)
        store.unlockAchievements(stats: stats)
        records = store.dayRecords(lastDays: 28)
        insights = Insights.messages(records)
        updateAutoGoals(store)
    }

    /// Objetivos ligados a dados (peso, poupança) atualizam-se sozinhos.
    @MainActor private func updateAutoGoals(_ store: DataStore) {
        let lastWeight = (try? ctx.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])))?.first?.kg
        let savings = ((try? ctx.fetch(FetchDescriptor<SavingsContribution>())) ?? []).reduce(Decimal(0)) { $0 + $1.amount }
        for g in goals where !g.completed {
            switch g.autoSource {
            case "weight": if let w = lastWeight { g.currentValue = w }
            case "savings": g.currentValue = savings.double
            case "workouts": g.currentValue = Double(stats.workouts)
            default: break
            }
            let up = g.targetValue >= g.startValue
            if (up && g.currentValue >= g.targetValue) || (!up && g.currentValue <= g.targetValue), g.targetValue != g.startValue {
                g.completed = true
                Progression(store: store).award(40, area: XPArea(rawValue: g.area) ?? .personal, source: "Objetivo: \(g.title)", key: "goal:\(g.uid.uuidString)")
            }
        }
        try? ctx.save()
    }

    private var weekChart: some View {
        Card(title: "Últimas 4 semanas", systemImage: "chart.bar") {
            Chart(records.indices, id: \.self) { i in
                let r = records[i]
                BarMark(x: .value("Dia", r.date, unit: .day), y: .value("%", Double(r.done) / Double(max(1, r.total)) * 100))
                    .foregroundStyle(r.kind.isWork ? Theme.accent : Theme.positive)
            }
            .chartYScale(domain: 0...100)
            .frame(height: 140)
            Text("Azul: dias de trabalho · Verde: folgas e outros").font(.lrCaption).foregroundStyle(Theme.textTertiary)
        }
    }

    private func goalsCard(_ store: DataStore) -> some View {
        Card(title: "Objetivos", systemImage: "target") {
            if goals.isEmpty { Text("Sem objetivos. Toca em + para criar.").foregroundStyle(Theme.textSecondary) }
            ForEach(goals) { g in
                NavigationLink { GoalEditView(goal: g) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(g.title).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if g.completed { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.positive) }
                            Text(GoalEditView.horizons.first { $0.0 == g.horizonRaw }?.1 ?? "").font(.lrCaption).foregroundStyle(Theme.textTertiary)
                        }
                        let span = g.targetValue - g.startValue
                        ThinProgressBar(value: span == 0 ? 0 : (g.currentValue - g.startValue) / span, tint: g.completed ? Theme.positive : Theme.accent)
                        Text("\(Fmt.number(g.currentValue, decimals: 1)) / \(Fmt.number(g.targetValue, decimals: 1)) \(g.metric)")
                            .font(.lrCaption).foregroundStyle(Theme.textSecondary)
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private var achievementsCard: some View {
        let got = Set(unlocks.map(\.key))
        return Card(title: "Conquistas · \(got.count)/\(Achievements.all.count)", systemImage: "rosette") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(Achievements.all) { a in
                    let on = got.contains(a.id)
                    VStack(spacing: 4) {
                        Image(systemName: a.symbol).font(.title3).foregroundStyle(on ? Theme.warning : Theme.textTertiary.opacity(0.5))
                        Text(a.title).font(.lrCaption).multilineTextAlignment(.center).foregroundStyle(on ? Theme.textPrimary : Theme.textTertiary)
                        Text(a.detail).font(.system(size: 10)).multilineTextAlignment(.center).foregroundStyle(Theme.textTertiary).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 86).padding(6)
                    .background(Theme.surfaceRaised.opacity(on ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var statsCard: some View {
        Card(title: "Estatísticas", systemImage: "number") {
            KeyValueRow(key: "Tarefas concluídas", value: "\(stats.tasksDone)")
            KeyValueRow(key: "Treinos", value: "\(stats.workouts)")
            KeyValueRow(key: "Dias com meta de água", value: "\(stats.waterGoalDays)")
            KeyValueRow(key: "Dias com meta de proteína", value: "\(stats.proteinGoalDays)")
            KeyValueRow(key: "Registos de peso", value: "\(stats.weightEntries)")
            KeyValueRow(key: "Sunday Resets", value: "\(stats.sundayResets)")
            let kinds = Insights.completionByKind(records)
            if !kinds.isEmpty {
                Divider().overlay(Theme.separator)
                ForEach(kinds, id: \.0) { k in KeyValueRow(key: "Conclusão · \(k.0.title)", value: "\(Int((k.1 * 100).rounded())) %") }
            }
        }
    }
}

/// Criar ou editar um objetivo (curto, médio ou longo prazo).
struct GoalEditView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let goal: Goal?
    @State private var title = ""
    @State private var area = XPArea.personal
    @State private var horizon = "medium"
    @State private var metric = ""
    @State private var start = ""
    @State private var target = ""
    @State private var current = ""
    @State private var auto = ""
    @State private var hasDeadline = false
    @State private var deadline = Date()

    static let horizons = [("short", "Curto prazo"), ("medium", "Médio prazo"), ("long", "Longo prazo")]
    static let autos = [("", "Manual"), ("weight", "Peso (último registo)"), ("savings", "Total poupado"), ("workouts", "Número de treinos")]

    init(goal: Goal? = nil) { self.goal = goal }

    var body: some View {
        let form = Form {
            Section {
                TextField("Objetivo (ex.: Chegar aos 65 kg)", text: $title)
                Picker("Área", selection: $area) { ForEach(XPArea.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) } }
                Picker("Prazo", selection: $horizon) { ForEach(Self.horizons, id: \.0) { Text($0.1).tag($0.0) } }
                Toggle("Data limite", isOn: $hasDeadline)
                if hasDeadline { DatePicker("Até", selection: $deadline, displayedComponents: .date) }
            }
            Section("Medição") {
                Picker("Atualização", selection: $auto) { ForEach(Self.autos, id: \.0) { Text($0.1).tag($0.0) } }
                TextField("Unidade (kg, CHF, treinos…)", text: $metric)
                TextField("Valor inicial", text: $start).keyboardType(.decimalPad)
                TextField("Valor alvo", text: $target).keyboardType(.decimalPad)
                if auto.isEmpty { TextField("Valor atual", text: $current).keyboardType(.decimalPad) }
            }
            if let goal {
                Section {
                    Button("Apagar objetivo", role: .destructive) { ctx.delete(goal); try? ctx.save(); dismiss() }
                }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle(goal == nil ? "Novo objetivo" : "Objetivo").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Guardar", action: save).disabled(title.isEmpty) }
            if goal == nil { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
        .onAppear(perform: load)

        return Group {
            if goal == nil { NavigationStack { form } } else { form }
        }
    }

    private func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    private func load() {
        guard let g = goal, title.isEmpty else {
            if goal == nil, metric.isEmpty { metric = "" }
            return
        }
        title = g.title; area = XPArea(rawValue: g.area) ?? .personal; horizon = g.horizonRaw; metric = g.metric
        start = Fmt.number(g.startValue, decimals: 1); target = Fmt.number(g.targetValue, decimals: 1)
        current = Fmt.number(g.currentValue, decimals: 1); auto = g.autoSource
        hasDeadline = g.deadline != nil; deadline = g.deadline ?? Date()
    }

    private func save() {
        let g = goal ?? { let n = Goal(title: title, area: area.rawValue); ctx.insert(n); return n }()
        g.title = title; g.area = area.rawValue; g.horizonRaw = horizon; g.metric = metric
        g.startValue = num(start); g.targetValue = num(target); g.autoSource = auto
        g.currentValue = auto.isEmpty ? num(current) : (goal?.currentValue ?? num(start))
        g.deadline = hasDeadline ? deadline : nil
        DataStore(ctx: ctx).save()
        dismiss()
    }
}
