import SwiftUI
import SwiftData
import LifeResetCore

/// Rascunho editável de um dia (usado no Sunday Reset e na edição de um dia).
struct DayDraft: Equatable, Identifiable {
    var id: Date { date }
    var date: Date
    var kind: DayKind
    var shiftStart = TimeOfDay(10, 30)
    var shiftEnd = TimeOfDay(22, 30)
    var breakStart = TimeOfDay(16)
    var breakMinutes = 60
    var overtime = 0
    var leaveHome = TimeOfDay(9, 20)
    var arrival = TimeOfDay(10)
    var returnHome = TimeOfDay(23)
    var recovery = false

    init(_ info: DayInfo) {
        date = info.date; kind = info.kind; overtime = info.overtimeMinutes; recovery = info.isRecovery
        if let s = info.shift { shiftStart = s.start; shiftEnd = s.end }
        if let b = info.breakStart { breakStart = b }
        breakMinutes = info.breakMinutes
        if let l = info.leaveHome { leaveHome = l }
        if let a = info.arrival { arrival = a }
        if let r = info.returnHome { returnHome = r }
    }

    /// Muda o tipo de dia e aplica os horários por omissão do trabalho correspondente.
    mutating func setKind(_ k: DayKind, store: DataStore) {
        kind = k
        if k.isWork {
            let job = store.job(k == .cafeShift ? .cafe : .burger)
            let d = DayInfo.work(job, on: date)
            shiftStart = d.shift?.start ?? shiftStart; shiftEnd = d.shift?.end ?? shiftEnd
            breakStart = d.breakStart ?? breakStart; breakMinutes = d.breakMinutes
            leaveHome = d.leaveHome ?? leaveHome; arrival = d.arrival ?? arrival; returnHome = d.returnHome ?? returnHome
        } else {
            overtime = 0
        }
    }

    var info: DayInfo {
        guard kind.isWork else { return DayInfo(date: date, kind: kind, isRecovery: recovery) }
        return DayInfo(date: date, kind: kind, shift: TimeRange(shiftStart, max(shiftStart, shiftEnd)), breakStart: breakStart,
                       breakMinutes: breakMinutes, overtimeMinutes: overtime, leaveHome: leaveHome, arrival: arrival,
                       returnHome: returnHome, isRecovery: recovery)
    }
}

extension DataStore {
    /// Grava a configuração de um dia.
    func saveDay(_ info: DayInfo) {
        let a = assignment(for: info.date) ?? { let n = DayAssignment(date: cal.startOfDay(for: info.date)); ctx.insert(n); return n }()
        a.apply(info)
    }

    func recoveryCount(inWeekOf date: Date, excluding day: Date? = nil) -> Int {
        weekInfos(from: LRCalendar.weekStart(for: date)).filter { d in
            d.isRecovery && (day.map { !cal.isDate($0, inSameDayAs: d.date) } ?? true)
        }.count
    }
}

/// Campos de horário de um dia de trabalho.
struct DayFields: View {
    @Binding var draft: DayDraft
    var compact = false

    var body: some View {
        if draft.kind.isWork {
            DatePicker("Entrada", selection: $draft.shiftStart.asDate, displayedComponents: .hourAndMinute)
            DatePicker("Saída", selection: $draft.shiftEnd.asDate, displayedComponents: .hourAndMinute)
            DatePicker("Início da pausa", selection: $draft.breakStart.asDate, displayedComponents: .hourAndMinute)
            Stepper("Pausa: \(draft.breakMinutes) min", value: $draft.breakMinutes, in: 0...120, step: 5)
            Stepper("Horas extra: \(draft.overtime) min", value: $draft.overtime, in: 0...300, step: 15)
            if !compact {
                DatePicker("Sair de casa", selection: $draft.leaveHome.asDate, displayedComponents: .hourAndMinute)
                DatePicker("Chegada", selection: $draft.arrival.asDate, displayedComponents: .hourAndMinute)
                DatePicker("Regresso a casa", selection: $draft.returnHome.asDate, displayedComponents: .hourAndMinute)
            }
        }
    }
}

/// Editar um dia (horas extra, mudança de turno, Recovery). Mostra as alterações ao plano antes de aplicar.
struct DayEditView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let date: Date
    @State private var draft: DayDraft?
    @State private var changes: [PlanChange] = []
    @State private var showProposals = false
    @State private var error: String?

    private var store: DataStore { DataStore(ctx: ctx) }

    var body: some View {
        NavigationStack {
            Form {
                if let binding = Binding($draft) {
                    Section {
                        Picker("Tipo de dia", selection: Binding(get: { binding.wrappedValue.kind },
                                                                 set: { binding.wrappedValue.setKind($0, store: store) })) {
                            ForEach(DayKind.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        Toggle("Recovery Mode", isOn: binding.recovery)
                    } footer: {
                        Text("Recovery mantém só o essencial e retira tarefas de esforço intenso. Máximo de 2 dias por semana.")
                    }
                    if binding.wrappedValue.kind.isWork {
                        Section("Horário") { DayFields(draft: binding) }
                    }
                    if let error { Section { Text(error).foregroundStyle(Theme.negative) } }
                }
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle(Fmt.longDate(date)).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Rever", action: review) }
            }
            .onAppear { if draft == nil { draft = DayDraft(store.dayInfo(for: date).info) } }
            .sheet(isPresented: $showProposals) {
                ProposalsSheet(changes: changes, warnings: draft.map { store.plan(for: date, overriding: $0.info).warnings } ?? []) {
                    apply()
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func review() {
        guard let d = draft else { return }
        if d.recovery && store.recoveryCount(inWeekOf: date, excluding: date) >= store.profile().maxRecoveryDays {
            error = "Já tens \(store.profile().maxRecoveryDays) dias de Recovery esta semana."; return
        }
        if let b = d.info.breakRange, let s = d.info.shift, !s.contains(b) {
            error = "A pausa está fora do turno."; return
        }
        error = nil
        changes = PlanDiff.changes(from: store.plan(for: date), to: store.plan(for: date, overriding: d.info))
        showProposals = true
    }

    private func apply() {
        guard let d = draft else { return }
        store.saveDay(d.info)
        store.save()
        dismiss()
    }
}

/// Propostas de alteração ao plano — nada muda sem aprovação.
struct ProposalsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let changes: [PlanChange]
    let warnings: [String]
    let onAccept: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if changes.isEmpty {
                    Text("O plano das tarefas não muda.").foregroundStyle(Theme.textSecondary)
                } else {
                    Section("Alterações propostas") {
                        ForEach(changes) { c in
                            Label(c.description, systemImage: c.after == nil ? "minus.circle" : "arrow.right.circle")
                        }
                    }
                }
                if !warnings.isEmpty {
                    Section("Avisos") {
                        ForEach(warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warning) }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("Rever alterações").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Rejeitar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Aceitar") { dismiss(); onAccept() } }
            }
        }
    }
}
