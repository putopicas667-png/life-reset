import SwiftUI
import SwiftData
import LifeResetCore

/// Home: o que interessa agora — próximo compromisso, hora de saída, prioridades, progresso e avisos.
struct HomeView: View {
    @Environment(\.modelContext) private var ctx
    // Observados só para o ecrã se atualizar quando os dados mudam.
    @Query private var occurrences: [TaskOccurrence]
    @Query private var assignments: [DayAssignment]
    @Query private var dailyPriorities: [DailyPriority]
    @Query private var xpEvents: [XPEvent]
    @Query private var tasksQ: [TaskItem]

    @State private var showSettings = false
    @State private var showSundayReset = false
    @State private var showPriorities = false
    @State private var editDay = false
    @State private var editingTask: TaskItem?

    private var store: DataStore { DataStore(ctx: ctx) }

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { tl in
                let _ = occurrences.count + assignments.count + dailyPriorities.count + xpEvents.count + tasksQ.count
                let now = tl.date
                let today = Calendar.current.startOfDay(for: now)
                let nowT = TimeOfDay(date: now)
                let period = DayPeriod.at(nowT)
                let configured = store.dayInfo(for: today).configured
                let plan = store.plan(for: today)
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.spacing) {
                        header(now: now, period: period)
                        if !configured { sundayResetPrompt }
                        nowCard(plan: plan, now: nowT)
                        prioritiesCard(today: today, plan: plan)
                        progressCard(today: today)
                        if !plan.warnings.isEmpty || !plan.conflicts.isEmpty { warningsCard(plan) }
                        dayCard(plan: plan)
                        if period == .evening || period == .night { tomorrowCard(today: today) }
                    }
                    .padding(Theme.pagePadding)
                }
            }
            .lrScreenBackground()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSundayReset = true } label: { Image(systemName: "calendar.badge.clock") }
                        .accessibilityLabel("Sunday Reset")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Definições")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showSundayReset) { SundayResetView() }
            .sheet(isPresented: $showPriorities) { PrioritiesPicker(day: Date()) }
            .sheet(isPresented: $editDay) { DayEditView(date: Date()) }
            .sheet(item: $editingTask) { TaskEditView(task: $0) }
        }
    }

    private func header(now: Date, period: DayPeriod) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Fmt.longDate(now)).font(.lrCaption).foregroundStyle(Theme.textSecondary).textCase(.uppercase).tracking(0.6)
            Text(period.greeting).font(.lrLargeTitle).foregroundStyle(Theme.textPrimary)
        }
        .padding(.bottom, 4)
    }

    private var sundayResetPrompt: some View {
        Card(title: "Semana por configurar", systemImage: "calendar.badge.exclamationmark") {
            Text("Define os turnos e folgas desta semana para o plano ficar certo.").font(.lrBody)
            Button("Abrir Sunday Reset") { showSundayReset = true }.buttonStyle(.borderedProminent)
        }
    }

    // MARK: Agora / a seguir
    private func nowCard(plan: DayPlan, now: TimeOfDay) -> some View {
        Card(title: "Agora", systemImage: "clock") {
            if let out = plan.context.commuteOut, now < out.start {
                let mins = now.minutes(until: out.start)
                HStack(alignment: .firstTextBaseline) {
                    Text(mins >= 60 ? "\(mins / 60) h \(mins % 60) min" : "\(mins) min").font(.lrNumber)
                    Text("até saíres de casa (\(out.start.description))").font(.lrCaption).foregroundStyle(Theme.textSecondary)
                }
            }
            if let current = plan.blocks.first(where: { $0.range.contains(now) && $0.kind != .task && $0.kind != .meal }) {
                Text("\(current.title) até às \(current.range.end.description)").font(.lrBody).foregroundStyle(Theme.textSecondary)
            }
            if let next = plan.next(after: now) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("A seguir").font(.lrCaption).foregroundStyle(Theme.textTertiary)
                        Text(next.title).font(.lrHeadline)
                        Text(next.range.start <= now ? "Agora · até \(next.range.end.description)" : "Às \(next.range.start.description)")
                            .font(.lrCaption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if let id = next.taskId, let t = store.task(id) {
                        Button { store.setStatus(t, on: Date(), to: .done) } label: {
                            Image(systemName: "checkmark.circle").font(.title2)
                        }.buttonStyle(.plain).foregroundStyle(Theme.positive).accessibilityLabel("Concluir")
                    }
                }
            } else {
                Text("Nada mais planeado para hoje.").font(.lrBody).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: Prioridades
    private func prioritiesCard(today: Date, plan: DayPlan) -> some View {
        let ids = store.priorities(on: today)
        return Card(title: "Prioridades", systemImage: "star") {
            if ids.isEmpty {
                Text("Ainda não escolheste as 3 prioridades de hoje.").font(.lrBody).foregroundStyle(Theme.textSecondary)
                Button("Escolher") { showPriorities = true }.buttonStyle(.bordered)
            } else {
                ForEach(ids, id: \.self) { id in
                    if let t = store.task(id) {
                        let done = store.status(t, on: today) == .done
                        HStack {
                            Button { store.setStatus(t, on: today, to: done ? .pending : .done) } label: {
                                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(done ? Theme.positive : Theme.textTertiary)
                            }.buttonStyle(.plain)
                            Text(t.title).strikethrough(done).foregroundStyle(done ? Theme.textTertiary : Theme.textPrimary)
                                .onTapGesture { editingTask = t }
                            Spacer()
                            if let s = plan.start(of: id) { Text(s.description).font(.lrCaption.monospacedDigit()).foregroundStyle(Theme.textTertiary) }
                        }.font(.lrBody)
                    }
                }
            }
        }
    }

    // MARK: Progresso
    private func progressCard(today: Date) -> some View {
        let tasks = store.tasks(on: today)
        let done = tasks.filter { store.status($0, on: today) == .done }.count
        let xpToday = xpEvents.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }.reduce(0) { $0 + $1.amount }
        let prog = Progression(store: store)
        let total = prog.totalXP()
        let level = prog.totalLevel()
        return Card(title: "Progresso de hoje", systemImage: "chart.bar") {
            HStack {
                StatTile(value: "\(done)/\(tasks.count)", label: "tarefas")
                StatTile(value: "+\(xpToday)", label: "XP hoje")
                StatTile(value: "\(level)", label: "nível")
            }
            ThinProgressBar(value: XPRules.progress(forXP: total))
        }
    }

    private func warningsCard(_ plan: DayPlan) -> some View {
        Card(title: "Avisos", systemImage: "exclamationmark.triangle") {
            ForEach(plan.warnings + plan.conflicts, id: \.self) {
                Text($0).font(.lrBody).foregroundStyle(Theme.warning)
            }
        }
    }

    // MARK: Dia
    private func dayCard(plan: DayPlan) -> some View {
        let c = plan.context
        return Card(title: "Hoje · \(c.info.kind.title)\(c.isRecovery ? " · Recovery" : "")", systemImage: "calendar.day.timeline.left") {
            if let w = c.work {
                KeyValueRow(key: "Turno", value: w.description)
                if let o = c.commuteOut { KeyValueRow(key: "Sair de casa", value: o.start.description) }
                if let b = c.workBreak { KeyValueRow(key: "Pausa", value: b.description) }
                if let r = c.commuteBack { KeyValueRow(key: "Em casa", value: r.end.description) }
            } else {
                KeyValueRow(key: "Acordar", value: c.wake.description)
                KeyValueRow(key: "Deitar", value: c.bed.description)
            }
            let meals = plan.blocks.filter { $0.kind == .meal }
            if !meals.isEmpty {
                Divider().overlay(Theme.separator)
                ForEach(meals) { m in KeyValueRow(key: m.title, value: m.range.start.description) }
            }
            Button("Editar o dia (horas extra, turno, Recovery)") { editDay = true }.font(.lrCaption)
        }
    }

    private func tomorrowCard(today: Date) -> some View {
        let tomorrow = LRCalendar.addDays(1, to: today)
        let plan = store.plan(for: tomorrow)
        let c = plan.context
        return Card(title: "Amanhã", systemImage: "moon") {
            KeyValueRow(key: "Dia", value: c.info.kind.title + (c.isRecovery ? " · Recovery" : ""))
            KeyValueRow(key: "Acordar", value: c.wake.description)
            if let o = c.commuteOut { KeyValueRow(key: "Sair de casa", value: o.start.description) }
            let n = store.tasks(on: tomorrow).count
            KeyValueRow(key: "Tarefas", value: "\(n)")
        }
    }
}
