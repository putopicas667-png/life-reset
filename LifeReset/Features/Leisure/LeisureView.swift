import SwiftUI
import SwiftData
import Charts
import LifeResetCore

/// Tempo livre e tempo de ecrã (registo manual; o iOS não deixa ler o Tempo de Ecrã sem permissões especiais).
struct LeisureView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \TimeLog.date, order: .reverse) private var logs: [TimeLog]
    @State private var activity = "Leitura"
    @State private var minutes = 30
    @State private var screenH = 3
    @State private var screenM = 0

    static let activities = ["Leitura", "Passeio", "Jogos", "Séries / filmes", "Amigos e família", "Desporto", "Aprender algo", "Descanso", "Outro"]

    var body: some View {
        let cal = Calendar.current
        let week = LRCalendar.weekStart(for: Date())
        let thisWeek = logs.filter { $0.date >= week }
        let free = thisWeek.filter { $0.kindRaw == "free" }
        let screen = logs.filter { $0.kindRaw == "screen" }
        let lastScreen = (0..<14).reversed().map { i -> (Date, Int) in
            let d = LRCalendar.addDays(-i, to: cal.startOfDay(for: Date()))
            return (d, screen.first { cal.isDate($0.date, inSameDayAs: d) }?.minutes ?? 0)
        }
        return List {
            Section {
                Picker("Atividade", selection: $activity) { ForEach(Self.activities, id: \.self) { Text($0) } }
                Stepper("\(minutes) min", value: $minutes, in: 5...600, step: 5)
                Button("Registar tempo livre") {
                    ctx.insert(TimeLog(date: Date(), kind: "free", minutes: minutes, activity: activity))
                    DataStore(ctx: ctx).save()
                }
            } header: { Text("Tempo livre") } footer: {
                Text("Esta semana: \(free.reduce(0) { $0 + $1.minutes } / 60) h \(free.reduce(0) { $0 + $1.minutes } % 60) min.")
            }

            Section {
                Stepper("\(screenH) h", value: $screenH, in: 0...20)
                Stepper("\(screenM) min", value: $screenM, in: 0...55, step: 5)
                Button("Guardar tempo de ecrã de hoje") {
                    let today = cal.startOfDay(for: Date())
                    if let e = screen.first(where: { cal.isDate($0.date, inSameDayAs: today) }) { e.minutes = screenH * 60 + screenM }
                    else { ctx.insert(TimeLog(date: Date(), kind: "screen", minutes: screenH * 60 + screenM, activity: "")) }
                    DataStore(ctx: ctx).save()
                }
                if screen.count >= 2 {
                    Chart(lastScreen, id: \.0) { p in
                        BarMark(x: .value("Dia", p.0, unit: .day), y: .value("h", Double(p.1) / 60)).foregroundStyle(Theme.accent)
                    }
                    .frame(height: 140)
                }
            } header: { Text("Tempo de ecrã") } footer: {
                Text("Copia o valor de Definições › Tempo de ecrã no fim do dia.")
            }

            Section("Registos") {
                ForEach(logs.prefix(40)) { l in
                    KeyValueRow(key: l.kindRaw == "screen" ? "Ecrã · \(Fmt.shortDate(l.date))" : "\(l.activity) · \(Fmt.shortDate(l.date))",
                                value: "\(l.minutes / 60) h \(l.minutes % 60) min")
                }
                .onDelete { idx in let arr = Array(logs.prefix(40)); for i in idx { ctx.delete(arr[i]) }; DataStore(ctx: ctx).save() }
            }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle("Tempo livre e ecrã")
    }
}
