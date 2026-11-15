import SwiftUI
import LifeResetCore

/// Rascunho editável do perfil e dos trabalhos (usado no onboarding e nas definições).
struct SetupDraft: Equatable {
    var profile: ProfileSettings
    var jobs: [JobSettings]

    static let initial = SetupDraft(profile: .initial, jobs: [.burgerInitial, .cafeInitial])

    var issues: [String] { profile.validationIssues() + jobs.flatMap { $0.validationIssues() } }
}

/// Formulário partilhado: descanso, corpo e nutrição, treino e trabalhos.
struct SetupForm: View {
    @Binding var draft: SetupDraft

    var body: some View {
        Form {
            Section {
                DatePicker("Acordar", selection: $draft.profile.wake.asDate, displayedComponents: .hourAndMinute)
                DatePicker("Deitar", selection: $draft.profile.bed.asDate, displayedComponents: .hourAndMinute)
            } header: {
                Text("Descanso (referência)")
            } footer: {
                Text("A app ajusta a hora de acordar sugerida conforme o turno seguinte. Não regista o sono.")
            }

            Section("Corpo e nutrição") {
                LabeledContent("Peso atual") {
                    TextField("kg", value: $draft.profile.startWeightKg, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                    Text("kg").foregroundStyle(.secondary)
                }
                LabeledContent("Objetivo de peso") {
                    TextField("kg", value: $draft.profile.targetWeightKg, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                    Text("kg").foregroundStyle(.secondary)
                }
                Stepper("Calorias: \(draft.profile.dailyKcal) kcal", value: $draft.profile.dailyKcal, in: 1000...6000, step: 50)
                Stepper("Proteína: \(draft.profile.dailyProteinG) g", value: $draft.profile.dailyProteinG, in: 0...400, step: 5)
                Stepper("Água: \(Fmt.liters(fromMl: draft.profile.dailyWaterMl))", value: $draft.profile.dailyWaterMl, in: 500...8000, step: 250)
                Stepper("Refeições principais: \(draft.profile.mainMeals)", value: $draft.profile.mainMeals, in: 1...6)
            }

            Section("Treino") {
                Stepper("Treinos por semana: \(draft.profile.workoutsPerWeek)", value: $draft.profile.workoutsPerWeek, in: 0...7)
            }

            // Índices estáveis: editar o nome não pode mudar a identidade da secção (senão o campo perde o foco).
            ForEach(draft.jobs.indices, id: \.self) { i in
                JobSection(job: $draft.jobs[i])
            }

            if !draft.issues.isEmpty {
                Section("A corrigir") {
                    ForEach(draft.issues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warning)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }
}

/// Secção de um trabalho (horários por omissão de cada turno).
private struct JobSection: View {
    @Binding var job: JobSettings

    var body: some View {
        Section {
            TextField("Nome", text: $job.name)
            DatePicker("Saída de casa", selection: $job.leaveHome.asDate, displayedComponents: .hourAndMinute)
            DatePicker("Chegada ao trabalho", selection: $job.arrival.asDate, displayedComponents: .hourAndMinute)
            DatePicker("Entrada", selection: $job.start.asDate, displayedComponents: .hourAndMinute)
            DatePicker("Saída prevista", selection: $job.end.asDate, displayedComponents: .hourAndMinute)
            DatePicker("Regresso a casa", selection: $job.returnHome.asDate, displayedComponents: .hourAndMinute)
            Stepper("Pausa: \(job.breakMinutes) min", value: $job.breakMinutes, in: 0...120, step: 5)
            Stepper("Turnos por semana: \(job.shiftsPerWeek)", value: $job.shiftsPerWeek, in: 0...7)
        } header: {
            Text(job.kind == .cafe ? "Trabalho — \(job.name) (domingo)" : "Trabalho — \(job.name)")
        } footer: {
            Text("Deslocação: \(job.commuteToWork) min de ida, \(job.commuteHome) min de regresso. Tempo livre antes de entrar: \(job.preShiftWindow) min. A hora da pausa define-se em cada turno no Sunday Reset.")
        }
    }
}
