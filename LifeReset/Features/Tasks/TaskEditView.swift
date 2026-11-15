import SwiftUI
import SwiftData
import LifeResetCore

enum TaskCategory: String, CaseIterable, Identifiable {
    case personal, hygiene, household, shopping, health, nutrition, training, finance, admin
    var id: String { rawValue }
    var title: String {
        switch self {
        case .personal: return "Pessoal"
        case .hygiene: return "Higiene"
        case .household: return "Casa"
        case .shopping: return "Compras"
        case .health: return "Saúde"
        case .nutrition: return "Nutrição"
        case .training: return "Treino"
        case .finance: return "Finanças"
        case .admin: return "Administrativo"
        }
    }
    var symbol: String {
        switch self {
        case .personal: return "person"
        case .hygiene: return "drop"
        case .household: return "house"
        case .shopping: return "cart"
        case .health: return "cross.case"
        case .nutrition: return "fork.knife"
        case .training: return "dumbbell"
        case .finance: return "francsign.circle"
        case .admin: return "doc.text"
        }
    }
    static func of(_ raw: String) -> TaskCategory { TaskCategory(rawValue: raw) ?? .personal }
}

/// Rascunho editável de uma tarefa.
struct TaskDraftForm: Equatable {
    var title = ""
    var notes = ""
    var category = TaskCategory.personal
    var priority = 3
    var duration = 15
    var timingKind = 2 // 0 fixa, 1 ancorada, 2 flexível
    var fixedTime = TimeOfDay(18)
    var anchor = DayAnchor.morning
    var earliest = TimeOfDay(8)
    var latest = TimeOfDay(22)
    var recurrenceKind = 0 // 0 uma vez, 1 diária, 2 dias da semana, 3 mensal, 4 a cada N dias, 5 1×/semana
    var onceDay = Date()
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var monthDay = 1
    var everyN = 2
    var location = TaskLocation.home
    var sharing = Sharing.personal
    var failure = FailurePolicy.proposeReschedule
    var hasDeadline = false
    var deadline = Date()
    var notify = false
    var lead = 0
    var essential = false
    var heavy = false
    var preferDayOff = false

    var timing: TaskTiming {
        switch timingKind {
        case 0: return .fixed(fixedTime)
        case 1: return .anchored(anchor)
        default: return .flexible(earliest: earliest, latest: max(earliest, latest))
        }
    }

    var recurrence: Recurrence {
        let cal = LRCalendar.current
        switch recurrenceKind {
        case 1: return .daily
        case 2: return .weekly(weekdays: Array(weekdays).sorted())
        case 3: return .monthly(day: monthDay)
        case 4: return .everyNDays(n: max(1, everyN), anchor: cal.startOfDay(for: onceDay))
        case 5: return .weeklyFlexible
        default: return .once(day: cal.startOfDay(for: onceDay))
        }
    }

    init() {}

    init(_ t: TaskItem) {
        title = t.title; notes = t.notes; category = .of(t.category); priority = t.priority; duration = t.durationMinutes
        switch t.timing {
        case .fixed(let at): timingKind = 0; fixedTime = at
        case .anchored(let a): timingKind = 1; anchor = a
        case .flexible(let e, let l): timingKind = 2; earliest = e; latest = l
        }
        switch t.recurrence {
        case .once(let d): recurrenceKind = 0; onceDay = d
        case .daily: recurrenceKind = 1
        case .weekly(let w): recurrenceKind = 2; weekdays = Set(w)
        case .monthly(let d): recurrenceKind = 3; monthDay = d
        case .everyNDays(let n, let a): recurrenceKind = 4; everyN = n; onceDay = a
        case .weeklyFlexible: recurrenceKind = 5
        }
        location = t.location; sharing = t.sharing; failure = t.failurePolicy
        hasDeadline = t.deadline != nil; deadline = t.deadline ?? Date()
        notify = t.notify; lead = t.notifyLeadMinutes; essential = t.essential; heavy = t.heavy; preferDayOff = t.preferDayOff
    }

    func apply(to t: TaskItem) {
        t.title = title.trimmingCharacters(in: .whitespaces); t.notes = notes; t.category = category.rawValue
        t.priority = priority; t.durationMinutes = max(1, duration); t.timing = timing; t.recurrence = recurrence
        t.locationRaw = location.rawValue; t.sharingRaw = sharing.rawValue; t.failureRaw = failure.rawValue
        t.deadline = hasDeadline ? deadline : nil; t.notify = notify; t.notifyLeadMinutes = lead
        t.essential = essential; t.heavy = heavy; t.preferDayOff = preferDayOff
        t.xpArea = XPArea.forCategory(category.rawValue).rawValue
    }
}

/// Criar ou editar uma tarefa.
struct TaskEditView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem?
    @State var form: TaskDraftForm
    @State private var newSubtask = ""
    @State private var confirmArchive = false

    init(task: TaskItem? = nil, prefill: TaskDraftForm = TaskDraftForm()) {
        self.task = task
        _form = State(initialValue: task.map { TaskDraftForm($0) } ?? prefill)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome", text: $form.title)
                    TextField("Descrição (opcional)", text: $form.notes, axis: .vertical)
                    Picker("Categoria", selection: $form.category) {
                        ForEach(TaskCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    Picker("Prioridade", selection: $form.priority) {
                        Text("Muito alta").tag(1); Text("Alta").tag(2); Text("Normal").tag(3); Text("Baixa").tag(4)
                    }
                    Stepper("Duração: \(form.duration) min", value: $form.duration, in: 1...480, step: form.duration < 15 ? 1 : 5)
                }

                Section("Quando") {
                    Picker("Tipo", selection: $form.timingKind) {
                        Text("Hora fixa").tag(0); Text("Momento do dia").tag(1); Text("Janela flexível").tag(2)
                    }.pickerStyle(.segmented)
                    switch form.timingKind {
                    case 0: DatePicker("Hora", selection: $form.fixedTime.asDate, displayedComponents: .hourAndMinute)
                    case 1: Picker("Momento", selection: $form.anchor) { ForEach(DayAnchor.allCases, id: \.self) { Text($0.title).tag($0) } }
                    default:
                        DatePicker("A partir de", selection: $form.earliest.asDate, displayedComponents: .hourAndMinute)
                        DatePicker("Até", selection: $form.latest.asDate, displayedComponents: .hourAndMinute)
                    }
                    Picker("Onde", selection: $form.location) { ForEach(TaskLocation.allCases, id: \.self) { Text($0.title).tag($0) } }
                }

                Section("Repetição") {
                    Picker("Frequência", selection: $form.recurrenceKind) {
                        Text("Uma vez").tag(0); Text("Diária").tag(1); Text("Dias da semana").tag(2)
                        Text("Mensal").tag(3); Text("A cada N dias").tag(4); Text("1× por semana").tag(5)
                    }
                    switch form.recurrenceKind {
                    case 0: DatePicker("Dia", selection: $form.onceDay, displayedComponents: .date)
                    case 2: WeekdayPicker(selection: $form.weekdays)
                    case 3: Stepper(form.monthDay == 0 ? "Último dia do mês" : "Dia \(form.monthDay)", value: $form.monthDay, in: 0...31)
                    case 4:
                        Stepper("A cada \(form.everyN) dias", value: $form.everyN, in: 1...90)
                        DatePicker("A partir de", selection: $form.onceDay, displayedComponents: .date)
                    case 5: Text("Aparece nas folgas até ser feita nessa semana.").font(.lrCaption).foregroundStyle(.secondary)
                    default: EmptyView()
                    }
                }

                Section("Comportamento") {
                    Picker("Se ficar por fazer", selection: $form.failure) { ForEach(FailurePolicy.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Toggle("Tem prazo", isOn: $form.hasDeadline)
                    if form.hasDeadline { DatePicker("Prazo", selection: $form.deadline, displayedComponents: .date) }
                    Picker("Partilha", selection: $form.sharing) { ForEach(Sharing.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Toggle("Essencial (mantém-se em Recovery e viagem)", isOn: $form.essential)
                    Toggle("Esforço físico intenso", isOn: $form.heavy)
                    Toggle("Preferir dias de folga", isOn: $form.preferDayOff)
                }

                Section("Notificação") {
                    Toggle("Notificar", isOn: $form.notify)
                    if form.notify { Stepper("Antecedência: \(form.lead) min", value: $form.lead, in: 0...240, step: 5) }
                }

                if let task {
                    Section("Subtarefas") {
                        ForEach(DataStore(ctx: ctx).subtasks(of: task)) { sub in
                            Text(sub.title)
                        }
                        HStack {
                            TextField("Nova subtarefa", text: $newSubtask)
                            Button("Adicionar") {
                                let s = TaskItem(title: newSubtask); s.parentUID = task.uid; s.recurrenceData = task.recurrenceData
                                ctx.insert(s); newSubtask = ""; DataStore(ctx: ctx).save()
                            }.disabled(newSubtask.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    Section {
                        Button("Arquivar tarefa", role: .destructive) { confirmArchive = true }
                    } footer: { Text("Arquivar esconde a tarefa; o histórico e o XP mantêm-se.") }
                }
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle(task == nil ? "Nova tarefa" : "Editar tarefa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save).disabled(form.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Arquivar esta tarefa?", isPresented: $confirmArchive, titleVisibility: .visible) {
                Button("Arquivar", role: .destructive) { task?.archived = true; DataStore(ctx: ctx).save(); dismiss() }
            }
        }
    }

    private func save() {
        let t = task ?? { let n = TaskItem(title: form.title); ctx.insert(n); return n }()
        form.apply(to: t)
        DataStore(ctx: ctx).save()
        dismiss()
    }
}

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    private let order = [2, 3, 4, 5, 6, 7, 1]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { d in
                let on = selection.contains(d)
                Button { if on { selection.remove(d) } else { selection.insert(d) } } label: {
                    Text(LRCalendar.shortWeekdayName(d)).font(.lrCaption)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(on ? Theme.accent.opacity(0.35) : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
        }
    }
}
