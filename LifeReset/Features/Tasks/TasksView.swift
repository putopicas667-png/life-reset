import SwiftUI
import SwiftData
import LifeResetCore

/// Separador Tasks: hoje (prioridades + plano), todas as tarefas e propostas de reagendamento.
struct TasksView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<TaskItem> { !$0.archived }, sort: \TaskItem.title) private var allTasks: [TaskItem]
    @Query private var occurrences: [TaskOccurrence]
    @Query(filter: #Predicate<RescheduleSuggestion> { !$0.resolved }) private var suggestions: [RescheduleSuggestion]
    @Query private var priorities: [DailyPriority]

    @State private var segment = 0
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var editing: TaskItem?
    @State private var showNew = false
    @State private var showQuick = false
    @State private var showPriorities = false
    @State private var showSundayReset = false
    @State private var filter: TaskCategory?

    private var store: DataStore { DataStore(ctx: ctx) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $segment) {
                    Text("Dia").tag(0); Text("Todas").tag(1)
                    Text(suggestions.isEmpty ? "Reagendar" : "Reagendar (\(suggestions.count))").tag(2)
                }
                .pickerStyle(.segmented).padding(.horizontal, Theme.pagePadding).padding(.vertical, 8)
                switch segment {
                case 0: dayList
                case 1: allList
                default: suggestionList
                }
            }
            .lrScreenBackground()
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSundayReset = true } label: { Label("Sunday Reset", systemImage: "calendar.badge.clock") }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showQuick = true } label: { Image(systemName: "text.badge.plus") }.accessibilityLabel("Entrada rápida")
                    Button { showNew = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nova tarefa")
                }
            }
            .sheet(item: $editing) { TaskEditView(task: $0) }
            .sheet(isPresented: $showNew) { TaskEditView(prefill: { () -> TaskDraftForm in var f = TaskDraftForm(); f.onceDay = day; return f }()) }
            .sheet(isPresented: $showQuick) { QuickEntryView() }
            .sheet(isPresented: $showPriorities) { PrioritiesPicker(day: day) }
            .sheet(isPresented: $showSundayReset) { SundayResetView() }
        }
    }

    // MARK: Dia
    private var dayList: some View {
        let _ = occurrences.count + priorities.count + allTasks.count // atualiza quando os dados mudam
        let plan = store.plan(for: day)
        let prio = store.priorities(on: day)
        let tasks = store.tasks(on: day)
        let done = tasks.filter { store.status($0, on: day) == .done }.count
        return List {
            Section {
                HStack {
                    Button { day = LRCalendar.addDays(-1, to: day) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    VStack {
                        Text(Fmt.longDate(day)).font(.lrHeadline)
                        Text("\(plan.context.info.kind.title)\(plan.context.isRecovery ? " · Recovery" : "") · \(done)/\(tasks.count) feitas")
                            .font(.lrCaption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button { day = LRCalendar.addDays(1, to: day) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.plain)
                ThinProgressBar(value: tasks.isEmpty ? 0 : Double(done) / Double(tasks.count))
            }
            .listRowBackground(Theme.surface)

            Section {
                if prio.isEmpty {
                    Button("Escolher as 3 prioridades do dia") { showPriorities = true }
                } else {
                    ForEach(prio, id: \.self) { id in
                        if let t = store.task(id) { taskRow(t, time: plan.start(of: id), highlight: true) }
                    }
                    Button("Alterar prioridades") { showPriorities = true }.font(.lrCaption)
                }
            } header: { Text("Prioridades") }
            .listRowBackground(Theme.surface)

            if !plan.warnings.isEmpty || !plan.conflicts.isEmpty {
                Section("Avisos") {
                    ForEach(plan.warnings + plan.conflicts, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warning).font(.lrBody) }
                }.listRowBackground(Theme.surface)
            }

            Section("Plano") {
                ForEach(plan.blocks) { b in
                    if let id = b.taskId, let t = store.task(id) {
                        if !prio.contains(id) { taskRow(t, time: b.range.start, highlight: false, conflict: b.isConflict) }
                    } else {
                        HStack {
                            Text(b.range.start.description).font(.lrCaption.monospacedDigit()).foregroundStyle(Theme.textTertiary).frame(width: 44, alignment: .leading)
                            Image(systemName: icon(b.kind)).foregroundStyle(Theme.textTertiary)
                            Text(b.title).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text("até \(b.range.end.description)").font(.lrCaption.monospacedDigit()).foregroundStyle(Theme.textTertiary)
                        }.font(.lrBody)
                    }
                }
            }.listRowBackground(Theme.surface)

            if !plan.unplaced.isEmpty {
                Section("Fora do plano de hoje") {
                    ForEach(plan.unplaced, id: \.taskId) { u in
                        if let t = store.task(u.taskId) {
                            VStack(alignment: .leading, spacing: 2) {
                                taskRow(t, time: nil, highlight: false)
                                Text(u.reason).font(.lrCaption).foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }.listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func icon(_ k: BlockKind) -> String {
        switch k {
        case .commute: return "tram"
        case .work: return "briefcase"
        case .workBreak: return "cup.and.saucer"
        case .preShift: return "clock"
        case .meal: return "fork.knife"
        default: return "circle"
        }
    }

    @ViewBuilder
    private func taskRow(_ t: TaskItem, time: TimeOfDay?, highlight: Bool, conflict: Bool = false) -> some View {
        let st = store.status(t, on: day)
        HStack(spacing: 10) {
            Button {
                store.setStatus(t, on: day, to: st == .done ? .pending : .done)
            } label: {
                Image(systemName: st == .done ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(st == .done ? Theme.positive : Theme.textTertiary)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).strikethrough(st == .done).foregroundStyle(st == .done ? Theme.textTertiary : Theme.textPrimary)
                HStack(spacing: 6) {
                    if let time { Text(time.description).monospacedDigit() }
                    Text("\(t.durationMinutes) min")
                    if t.sharing == .shared { Image(systemName: "person.2") }
                    if st == .waiting { Text("à espera") }
                    if st == .skippedToday { Text("ignorada hoje") }
                    if conflict { Text("conflito").foregroundStyle(Theme.negative) }
                }.font(.lrCaption).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            if highlight { Image(systemName: "star.fill").foregroundStyle(Theme.warning).font(.caption) }
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = t }
        .swipeActions(edge: .trailing) {
            Button("Ignorar hoje") { store.setStatus(t, on: day, to: .skippedToday) }.tint(.gray)
            if t.sharing == .shared { Button("À espera") { store.setStatus(t, on: day, to: .waiting) }.tint(Theme.warning) }
        }
        .swipeActions(edge: .leading) {
            Button("Concluir") { store.setStatus(t, on: day, to: .done) }.tint(Theme.positive)
        }
    }

    // MARK: Todas
    private var allList: some View {
        let list = allTasks.filter { $0.parentUID == nil && (filter == nil || $0.category == filter!.rawValue) }
        return List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        chip("Todas", selected: filter == nil) { filter = nil }
                        ForEach(TaskCategory.allCases) { c in chip(c.title, selected: filter == c) { filter = c } }
                    }
                }
            }.listRowBackground(Color.clear)
            ForEach(list) { t in
                Button { editing = t } label: {
                    HStack {
                        Image(systemName: TaskCategory.of(t.category).symbol).foregroundStyle(Theme.accent).frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(t.title).foregroundStyle(Theme.textPrimary)
                            Text(t.recurrence.summary).font(.lrCaption).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.lrCaption).padding(.horizontal, 10).padding(.vertical, 6)
                .background(selected ? Theme.accent.opacity(0.35) : Theme.surfaceRaised, in: Capsule())
        }.buttonStyle(.plain)
    }

    // MARK: Reagendar
    private var suggestionList: some View {
        List {
            if suggestions.isEmpty {
                Text("Nada por reagendar.").foregroundStyle(Theme.textSecondary)
            }
            ForEach(suggestions) { s in
                SuggestionRow(suggestion: s)
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct SuggestionRow: View {
    @Environment(\.modelContext) private var ctx
    let suggestion: RescheduleSuggestion
    @State private var date: Date

    init(suggestion: RescheduleSuggestion) {
        self.suggestion = suggestion
        _date = State(initialValue: suggestion.suggestedDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(suggestion.title).font(.lrHeadline)
            Text("\(suggestion.reason) em \(Fmt.longDate(suggestion.fromDate)).").font(.lrCaption).foregroundStyle(Theme.textSecondary)
            DatePicker("Nova data", selection: $date, displayedComponents: .date)
            HStack {
                Button("Reagendar") { DataStore(ctx: ctx).accept(suggestion, on: date) }.buttonStyle(.borderedProminent)
                Button("Dispensar") { suggestion.resolved = true; DataStore(ctx: ctx).save() }.buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Escolher (até) 3 prioridades do dia, com sugestão automática para confirmar.
struct PrioritiesPicker: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let day: Date
    @State private var selected: [UUID] = []

    var body: some View {
        let store = DataStore(ctx: ctx)
        let tasks = store.tasks(on: day).filter { $0.category != "hygiene" }
        NavigationStack {
            List {
                Section {
                    Button("Usar sugestão") { selected = store.suggestedPriorities(on: day) }
                } footer: { Text("A sugestão considera prioridade e prazos. Tu decides.") }
                Section("Escolhe até 3") {
                    ForEach(tasks) { t in
                        Button {
                            if let i = selected.firstIndex(of: t.uid) { selected.remove(at: i) }
                            else if selected.count < 3 { selected.append(t.uid) }
                        } label: {
                            HStack {
                                Text(t.title).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if let i = selected.firstIndex(of: t.uid) { Text("\(i + 1)").font(.lrHeadline).foregroundStyle(Theme.accent) }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("Prioridades").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { store.setPriorities(selected, on: day); dismiss() } }
            }
            .onAppear { selected = store.priorities(on: day) }
        }
    }
}

/// Entrada rápida em linguagem natural — mostra a interpretação antes de criar.
struct QuickEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var draft: TaskDraft?
    @State private var showForm = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ex.: Comprar champô amanhã", text: $text)
                        .onSubmit { draft = QuickEntryParser.parse(text) }
                    Button("Interpretar") { draft = QuickEntryParser.parse(text) }.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                } footer: { Text("Nada é criado sem confirmares.") }
                if let d = draft {
                    Section("Entendi") {
                        KeyValueRow(key: "Nome", value: d.title)
                        KeyValueRow(key: "Dia", value: d.day.map { Fmt.longDate($0) } ?? "—")
                        KeyValueRow(key: "Hora", value: d.time?.description ?? "—")
                        KeyValueRow(key: "Categoria", value: TaskCategory.of(d.category).title)
                        Button("Confirmar e rever") { showForm = true }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("Entrada rápida").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
            .sheet(isPresented: $showForm, onDismiss: { dismiss() }) {
                TaskEditView(prefill: prefill())
            }
        }
    }

    private func prefill() -> TaskDraftForm {
        var f = TaskDraftForm()
        guard let d = draft else { return f }
        f.title = d.title; f.category = TaskCategory.of(d.category)
        f.recurrenceKind = 0; f.onceDay = d.day ?? Date()
        if let t = d.time { f.timingKind = 0; f.fixedTime = t }
        if f.category == .shopping { f.location = .anywhere }
        return f
    }
}
