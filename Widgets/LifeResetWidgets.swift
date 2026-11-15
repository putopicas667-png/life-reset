import WidgetKit
import SwiftUI

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snap: .preview) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let s = SharedStore.read()
        completion(SnapshotEntry(date: Date(), snap: context.isPreview && s.items.isEmpty ? .preview : s))
    }

    /// Uma entrada por cada mudança de "próximo item", para o widget avançar sozinho ao longo do dia.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let s = SharedStore.read()
        let now = Date()
        var dates = [now]
        dates += s.items.map(\.end).filter { $0 > now }.prefix(20)
        if let l = s.leaveHome, l > now { dates.append(l) }
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        dates.append(midnight)
        let entries = Array(Set(dates)).sorted().map { SnapshotEntry(date: $0, snap: s) }
        completion(Timeline(entries: entries, policy: .after(min(midnight, now.addingTimeInterval(3600)))))
    }
}

extension WidgetSnapshot {
    static let preview: WidgetSnapshot = {
        let now = Date()
        return WidgetSnapshot(generatedAt: now, dayTitle: "Hambúrgueres",
                              items: [.init(start: now.addingTimeInterval(600), end: now.addingTimeInterval(1800), title: "Treino curto", isTask: true)],
                              priorities: [.init(title: "Pagar a renda", done: true), .init(title: "Treino A", done: false), .init(title: "Lavar roupa", done: false)],
                              done: 4, total: 9, leaveHome: now.addingTimeInterval(3600), level: 3, xpToday: 45, warning: nil)
    }()
}

private let accent = Color(red: 0.55, green: 0.64, blue: 0.86)
private let positive = Color(red: 0.45, green: 0.72, blue: 0.58)
private let bg = Color(red: 0.09, green: 0.098, blue: 0.118)

private func hm(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

// MARK: - 1. A seguir

struct NextUpView: View {
    @Environment(\.widgetFamily) var family
    let entry: SnapshotEntry

    var body: some View {
        let next = entry.snap.next(at: entry.date)
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(next.map { "\(hm($0.start)) · A seguir" } ?? entry.snap.dayTitle).font(.caption2).widgetAccentable()
                Text(next?.title ?? "Nada mais hoje").font(.headline).lineLimit(2)
            }
        case .accessoryInline:
            Text(next.map { "\(hm($0.start)) \($0.title)" } ?? "LIFE RESET · nada mais hoje")
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.snap.dayTitle.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("A seguir").font(.caption).foregroundStyle(.secondary)
                Text(next?.title ?? "Nada mais planeado").font(.headline).lineLimit(family == .systemSmall ? 3 : 2)
                if let n = next {
                    Text(n.start <= entry.date ? "Agora · até \(hm(n.end))" : "Às \(hm(n.start))").font(.caption).foregroundStyle(accent)
                }
                if family == .systemMedium, let w = entry.snap.warning { Text(w).font(.caption2).foregroundStyle(.orange).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct NextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextUp", provider: SnapshotProvider()) { e in
            NextUpView(entry: e).containerBackground(bg, for: .widget)
        }
        .configurationDisplayName("A seguir")
        .description("O próximo compromisso ou tarefa do dia.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - 2. Prioridades

struct PrioritiesView: View {
    let entry: SnapshotEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PRIORIDADES").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            if entry.snap.priorities.isEmpty {
                Text("Escolhe as 3 prioridades de hoje na app.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(entry.snap.priorities, id: \.self) { p in
                HStack(spacing: 6) {
                    Image(systemName: p.done ? "checkmark.circle.fill" : "circle").foregroundStyle(p.done ? positive : .secondary)
                    Text(p.title).font(.callout).strikethrough(p.done).lineLimit(1).foregroundStyle(p.done ? .secondary : .primary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PrioritiesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Priorities", provider: SnapshotProvider()) { e in
            PrioritiesView(entry: e).containerBackground(bg, for: .widget)
        }
        .configurationDisplayName("Prioridades")
        .description("As 3 prioridades do dia.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - 3. Progresso do dia

struct ProgressViewW: View {
    @Environment(\.widgetFamily) var family
    let entry: SnapshotEntry
    var body: some View {
        let s = entry.snap
        let v = s.total == 0 ? 0 : Double(s.done) / Double(s.total)
        if family == .accessoryCircular {
            Gauge(value: v) { Text("Dia") } currentValueLabel: { Text("\(s.done)") }
                .gaugeStyle(.accessoryCircularCapacity)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("HOJE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text("\(s.done)/\(s.total)").font(.system(size: 30, weight: .bold, design: .rounded))
                Text("tarefas feitas").font(.caption).foregroundStyle(.secondary)
                ProgressView(value: v).tint(positive)
                Text("Nível \(s.level) · +\(s.xpToday) XP").font(.caption2).foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DayProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DayProgress", provider: SnapshotProvider()) { e in
            ProgressViewW(entry: e).containerBackground(bg, for: .widget)
        }
        .configurationDisplayName("Progresso do dia")
        .description("Tarefas concluídas hoje e XP.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

// MARK: - 4. Sair de casa

struct LeaveView: View {
    @Environment(\.widgetFamily) var family
    let entry: SnapshotEntry
    var body: some View {
        let leave = entry.snap.leaveHome.flatMap { $0 > entry.date ? $0 : nil }
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 1) {
                Text("Sair de casa").font(.caption2).widgetAccentable()
                if let l = leave { Text(l, style: .relative).font(.headline); Text("às \(hm(l))").font(.caption2) }
                else { Text("Hoje não há turno por iniciar").font(.caption).lineLimit(2) }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("SAIR DE CASA").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let l = leave {
                    Text(l, style: .timer).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("às \(hm(l))").font(.caption).foregroundStyle(accent)
                } else {
                    Text(entry.snap.dayTitle).font(.headline)
                    Text("Sem saída pendente").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct LeaveHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LeaveHome", provider: SnapshotProvider()) { e in
            LeaveView(entry: e).containerBackground(bg, for: .widget)
        }
        .configurationDisplayName("Sair de casa")
        .description("Contagem decrescente até à hora de sair para o trabalho.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

// MARK: - 5. Agenda de hoje

struct AgendaView: View {
    let entry: SnapshotEntry
    var body: some View {
        let upcoming = entry.snap.items.filter { $0.end > entry.date }.prefix(6)
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(entry.snap.dayTitle.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.snap.done)/\(entry.snap.total)").font(.caption2).foregroundStyle(.secondary)
            }
            if upcoming.isEmpty { Text("Nada mais planeado para hoje.").font(.callout).foregroundStyle(.secondary) }
            ForEach(Array(upcoming), id: \.self) { i in
                HStack(spacing: 8) {
                    Text(hm(i.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 42, alignment: .leading)
                    Rectangle().fill(i.isTask ? positive : accent).frame(width: 2, height: 14)
                    Text(i.title).font(.callout).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AgendaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Agenda", provider: SnapshotProvider()) { e in
            AgendaView(entry: e).containerBackground(bg, for: .widget)
        }
        .configurationDisplayName("Agenda de hoje")
        .description("Os próximos blocos do dia: trabalho, refeições e tarefas.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct LifeResetWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextUpWidget()
        PrioritiesWidget()
        DayProgressWidget()
        LeaveHomeWidget()
        AgendaWidget()
    }
}
