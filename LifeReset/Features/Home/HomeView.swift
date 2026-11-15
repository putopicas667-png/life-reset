import SwiftUI
import SwiftData
import LifeResetCore

/// Home (Fase 1): data, saudação contextual, metas diárias e trabalhos configurados.
/// O plano do dia (próximo compromisso, prioridades, hora de saída) chega com o motor de planeamento na Fase 2.
struct HomeView: View {
    @Query private var profiles: [UserProfile]
    @Query(sort: \Job.sortOrder) private var jobs: [Job]
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { ctx in
                let now = ctx.date
                let period = DayPeriod.at(TimeOfDay(date: now))
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.spacing) {
                        header(now: now, period: period)
                        if let p = profiles.first { targets(p.settings) }
                        planCard(period: period)
                        if !jobs.isEmpty { jobsCard }
                    }
                    .padding(Theme.pagePadding)
                }
            }
            .lrScreenBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Definições")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private func header(now: Date, period: DayPeriod) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Fmt.longDate(now)).font(.lrCaption).foregroundStyle(Theme.textSecondary).textCase(.uppercase).tracking(0.6)
            Text(period.greeting).font(.lrLargeTitle).foregroundStyle(Theme.textPrimary)
        }
        .padding(.bottom, 4)
    }

    private func targets(_ s: ProfileSettings) -> some View {
        Card(title: "Metas diárias", systemImage: "target") {
            HStack {
                StatTile(value: "\(s.dailyKcal)", label: "kcal")
                StatTile(value: "\(s.dailyProteinG) g", label: "proteína")
                StatTile(value: Fmt.liters(fromMl: s.dailyWaterMl), label: "água")
            }
            Divider().overlay(Theme.separator)
            KeyValueRow(key: "Refeições principais", value: "\(s.mainMeals)")
            KeyValueRow(key: "Treinos por semana", value: "\(s.workoutsPerWeek)")
            KeyValueRow(key: "Peso", value: "\(Fmt.number(s.startWeightKg, decimals: 1)) → \(Fmt.number(s.targetWeightKg, decimals: 1)) kg")
        }
    }

    /// Mensagem honesta: o planeamento diário ainda não está implementado.
    private func planCard(period: DayPeriod) -> some View {
        Card(title: "Plano de hoje", systemImage: "calendar.day.timeline.left") {
            Text("Ainda não há turnos definidos para esta semana.")
                .font(.lrBody).foregroundStyle(Theme.textPrimary)
            Text("O Sunday Reset e o motor de planeamento (horário, prioridades, hora de saída e refeições) chegam na Fase 2.")
                .font(.lrCaption).foregroundStyle(Theme.textSecondary)
        }
    }

    private var jobsCard: some View {
        Card(title: "Trabalhos", systemImage: "briefcase") {
            ForEach(jobs) { job in
                let s = job.settings
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(s.name).font(.lrHeadline)
                        Spacer()
                        Text("\(s.start.description)–\(s.end.description)").font(.lrBody.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                    Text("Sai de casa \(s.leaveHome.description) · regressa \(s.returnHome.description) · pausa \(s.breakMinutes) min · \(s.shiftsPerWeek)×/semana")
                        .font(.lrCaption).foregroundStyle(Theme.textSecondary)
                }
                if job.id != jobs.last?.id { Divider().overlay(Theme.separator) }
            }
        }
    }
}
