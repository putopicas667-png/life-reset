import SwiftUI
import SwiftData
import Charts
import LifeResetCore

extension DataStore {
    /// Séries da última sessão em que o exercício foi feito.
    func lastSets(for exercise: String) -> [SetLog] {
        let d = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        for s in (try? ctx.fetch(d)) ?? [] {
            let sets = (Coding.decode([SetLog].self, s.setsData) ?? []).filter { $0.exercise == exercise }
            if !sets.isEmpty { return sets }
        }
        return []
    }
}

/// Treino: modelos A/B/curto, registo de séries e evolução de cargas.
struct TrainingView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @State private var active: WorkoutTemplate?

    var body: some View {
        let store = DataStore(ctx: ctx)
        let p = store.profile()
        let week = store.workouts(inWeekOf: Date()).count
        let today = store.dayInfo(for: Date()).info
        return List {
            Section {
                KeyValueRow(key: "Esta semana", value: "\(week) / \(p.workoutsPerWeek) treinos")
                ThinProgressBar(value: Double(week) / Double(max(1, p.workoutsPerWeek)), tint: week >= p.workoutsPerWeek ? Theme.positive : Theme.accent)
                if today.kind.isWork { Text("Hoje é dia de trabalho: o treino curto é o mais realista.").font(.lrCaption).foregroundStyle(Theme.textSecondary) }
                if today.isRecovery { Text("Recovery Mode: hoje é para descansar ou mobilidade leve.").font(.lrCaption).foregroundStyle(Theme.warning) }
            }
            Section("Começar treino") {
                ForEach(templates) { t in
                    Button { active = t } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(t.name).foregroundStyle(Theme.textPrimary)
                                Text((Coding.decode([TemplateItem].self, t.itemsData) ?? []).map(\.exercise).joined(separator: " · "))
                                    .font(.lrCaption).foregroundStyle(Theme.textTertiary).lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "play.circle").foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            Section("Evolução") {
                NavigationLink("Cargas por exercício") { ExerciseProgressView() }
            }
            Section("Histórico") {
                if sessions.isEmpty { Text("Ainda sem treinos registados.").foregroundStyle(Theme.textSecondary) }
                ForEach(sessions.prefix(30)) { s in
                    let sets = Coding.decode([SetLog].self, s.setsData) ?? []
                    VStack(alignment: .leading) {
                        Text(s.templateName)
                        Text("\(Fmt.shortDate(s.date)) · \(s.durationMinutes) min · \(sets.count) séries · \(Int(TrainingRules.volume(sets.map { .init(reps: $0.reps, kg: $0.kg) }))) kg de volume")
                            .font(.lrCaption).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle("Treino")
        .fullScreenCover(item: $active) { WorkoutLogView(template: $0) }
    }
}

struct WorkoutLogView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let template: WorkoutTemplate
    @State private var sets: [SetLog] = []
    @State private var targets: [String: Int] = [:]
    @State private var started = Date()
    @State private var notes = ""
    @State private var confirmQuit = false

    var body: some View {
        NavigationStack {
            List {
                let groups = Dictionary(grouping: sets.indices, by: { sets[$0].exercise })
                ForEach(order, id: \.self) { ex in
                    Section {
                        ForEach(groups[ex] ?? [], id: \.self) { i in
                            HStack {
                                Text("Série \(sets[i].set)").font(.lrCaption).foregroundStyle(Theme.textSecondary).frame(width: 60, alignment: .leading)
                                Stepper("\(sets[i].reps) reps", value: $sets[i].reps, in: 0...50).font(.lrBody)
                                Stepper("\(Fmt.number(sets[i].kg, decimals: 1)) kg", value: $sets[i].kg, in: 0...300, step: 1.25).font(.lrBody)
                            }
                        }
                        Button("+ Série") {
                            let last = sets.last { $0.exercise == ex }
                            sets.append(SetLog(exercise: ex, set: (last?.set ?? 0) + 1, reps: last?.reps ?? 8, kg: last?.kg ?? 0))
                        }.font(.lrCaption)
                    } header: {
                        Text(ex + (targets[ex].map { " · alvo \($0) reps" } ?? ""))
                    }
                }
                Section("Notas") { TextField("Como correu", text: $notes, axis: .vertical) }
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle(template.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Sair") { confirmQuit = true } }
                ToolbarItem(placement: .confirmationAction) { Button("Terminar", action: finish) }
            }
            .confirmationDialog("Sair sem guardar?", isPresented: $confirmQuit, titleVisibility: .visible) {
                Button("Sair sem guardar", role: .destructive) { dismiss() }
            }
            .onAppear(perform: prepare)
        }
    }

    private var order: [String] { (Coding.decode([TemplateItem].self, template.itemsData) ?? []).map(\.exercise) }

    /// Pré-preenche com as cargas sugeridas (progressão a partir do último treino).
    private func prepare() {
        guard sets.isEmpty else { return }
        let store = DataStore(ctx: ctx)
        for item in Coding.decode([TemplateItem].self, template.itemsData) ?? [] {
            targets[item.exercise] = item.reps
            let last = store.lastSets(for: item.exercise)
            let kg = TrainingRules.suggestedKg(last: last.map { .init(reps: $0.reps, kg: $0.kg) }, targetReps: item.reps) ?? 0
            for n in 1...max(1, item.sets) { sets.append(SetLog(exercise: item.exercise, set: n, reps: item.reps, kg: kg)) }
        }
    }

    private func finish() {
        let store = DataStore(ctx: ctx)
        let s = WorkoutSession(date: started, templateName: template.name)
        s.durationMinutes = max(1, Int(Date().timeIntervalSince(started) / 60))
        s.notes = notes
        s.setsData = Coding.encode(sets.filter { $0.reps > 0 })
        ctx.insert(s)
        Progression(store: store).award(XPRules.workoutXP, area: .physical, source: "Treino: \(template.name)",
                                        key: "workout:\(Int(started.timeIntervalSince1970))")
        store.save()
        dismiss()
    }
}

struct ExerciseProgressView: View {
    @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var selected = ""

    var body: some View {
        let points: [(Date, Double)] = sessions.compactMap { s in
            let sets = (Coding.decode([SetLog].self, s.setsData) ?? []).filter { $0.exercise == selected }
            guard let best = sets.map(\.kg).max() else { return nil }
            return (s.date, best)
        }
        return List {
            Picker("Exercício", selection: $selected) {
                ForEach(exercises) { Text($0.name).tag($0.name) }
            }
            if points.count >= 2 {
                Chart(points.indices, id: \.self) { i in
                    LineMark(x: .value("Data", points[i].0), y: .value("kg", points[i].1)).foregroundStyle(Theme.accent)
                    PointMark(x: .value("Data", points[i].0), y: .value("kg", points[i].1)).foregroundStyle(Theme.accent)
                }
                .frame(height: 200)
            } else {
                Text(points.isEmpty ? "Sem registos para este exercício." : "Precisa de pelo menos dois treinos para mostrar a evolução.")
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(points.indices.reversed(), id: \.self) { i in
                KeyValueRow(key: Fmt.shortDate(points[i].0), value: "\(Fmt.number(points[i].1, decimals: 1)) kg")
            }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle("Evolução")
        .onAppear { if selected.isEmpty { selected = exercises.first?.name ?? "" } }
    }
}
