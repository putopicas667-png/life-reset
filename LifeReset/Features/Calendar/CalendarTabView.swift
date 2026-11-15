import SwiftUI
import SwiftData
import LifeResetCore

extension DayKind {
    var color: Color {
        switch self {
        case .burgerShift: return Theme.accent
        case .cafeShift: return Color(red: 0.62, green: 0.52, blue: 0.80)
        case .dayOff: return Theme.positive
        case .travel: return Theme.warning
        case .custom: return Theme.textTertiary
        }
    }
    var symbol: String {
        switch self {
        case .burgerShift: return "briefcase"
        case .cafeShift: return "cup.and.saucer"
        case .dayOff: return "sun.max"
        case .travel: return "airplane"
        case .custom: return "circle"
        }
    }
}

/// Separador Calendar: dia, semana e mês com turnos, folgas, viagens, tarefas, treinos e compromissos.
struct CalendarTabView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var assignments: [DayAssignment]
    @Query private var events: [CalendarEvent]
    @Query private var trips: [Trip]
    @Query private var occurrences: [TaskOccurrence]
    @State private var mode = 1
    @State private var selected = Calendar.current.startOfDay(for: Date())
    @State private var newEvent = false
    @State private var editDay: DayRef?
    @State private var showTrips = false
    @State private var sundayReset = false

    private var store: DataStore { DataStore(ctx: ctx) }

    var body: some View {
        NavigationStack {
            let _ = assignments.count + events.count + trips.count + occurrences.count
            VStack(spacing: 0) {
                Picker("", selection: $mode) { Text("Dia").tag(0); Text("Semana").tag(1); Text("Mês").tag(2) }
                    .pickerStyle(.segmented).padding(.horizontal, Theme.pagePadding).padding(.vertical, 8)
                ScrollView {
                    VStack(spacing: Theme.spacing) {
                        switch mode {
                        case 0: dayView(selected)
                        case 1: weekView
                        default: monthView
                        }
                    }
                    .padding(Theme.pagePadding)
                }
            }
            .lrScreenBackground()
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showTrips = true } label: { Image(systemName: "airplane") }.accessibilityLabel("Viagens")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { sundayReset = true } label: { Image(systemName: "calendar.badge.clock") }.accessibilityLabel("Sunday Reset")
                    Button { newEvent = true } label: { Image(systemName: "plus") }.accessibilityLabel("Novo compromisso")
                }
            }
            .sheet(isPresented: $newEvent) { EventEditView(day: selected) }
            .sheet(item: $editDay) { DayEditView(date: $0.date) }
            .sheet(isPresented: $sundayReset) { SundayResetView() }
            .navigationDestination(isPresented: $showTrips) { TripsView() }
        }
    }

    private func nav(_ unit: Calendar.Component, _ n: Int) {
        selected = Calendar.current.date(byAdding: unit, value: n, to: selected).map { Calendar.current.startOfDay(for: $0) } ?? selected
    }

    private func header(_ title: String, unit: Calendar.Component) -> some View {
        HStack {
            Button { nav(unit, -1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(title).font(.lrHeadline)
            Spacer()
            Button { nav(unit, 1) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.plain)
    }

    // MARK: Dia
    @ViewBuilder
    private func dayView(_ day: Date) -> some View {
        let plan = store.plan(for: day)
        let dayEvents = store.events(on: day)
        let workouts = (try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        header(Fmt.longDate(day), unit: .day)
        Card(title: plan.context.info.kind.title + (plan.context.isRecovery ? " · Recovery" : ""), systemImage: plan.context.info.kind.symbol) {
            if let t = store.activeTrip(on: day) { Label("Viagem: \(t.destination)", systemImage: "airplane").foregroundStyle(Theme.warning) }
            ForEach(dayEvents.filter(\.allDay)) { e in Label(e.title, systemImage: "calendar") }
            ForEach(plan.blocks) { b in
                HStack(alignment: .top) {
                    Text(b.range.start.description).font(.lrCaption.monospacedDigit()).foregroundStyle(Theme.textTertiary).frame(width: 44, alignment: .leading)
                    Rectangle().fill(color(b)).frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(b.title).strikethrough(b.done).foregroundStyle(b.done ? Theme.textTertiary : Theme.textPrimary)
                        if b.range.duration >= 10 { Text("até \(b.range.end.description)").font(.lrCaption).foregroundStyle(Theme.textTertiary) }
                    }
                    Spacer()
                    if b.isConflict { Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.negative) }
                }.font(.lrBody)
            }
            let done = workouts.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            ForEach(done) { w in Label("Treino feito: \(w.templateName)", systemImage: "dumbbell").foregroundStyle(Theme.positive) }
            Button("Editar este dia") { editDay = DayRef(date: day) }.font(.lrCaption)
        }
        if !dayEvents.isEmpty {
            Card(title: "Compromissos", systemImage: "calendar") {
                ForEach(dayEvents) { e in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(e.title)
                            Text(e.allDay ? "Dia inteiro" : "\(e.start.formatted(date: .omitted, time: .shortened))–\(e.end.formatted(date: .omitted, time: .shortened))\(e.location.isEmpty ? "" : " · \(e.location)")")
                                .font(.lrCaption).foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        Button(role: .destructive) { ctx.delete(e); store.save() } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func color(_ b: PlanBlock) -> Color {
        switch b.kind {
        case .work, .preShift, .workBreak: return Theme.accent
        case .commute: return Theme.textTertiary
        case .meal: return Theme.warning
        default: return Theme.positive
        }
    }

    // MARK: Semana
    @ViewBuilder
    private var weekView: some View {
        let start = LRCalendar.weekStart(for: selected)
        let end = LRCalendar.addDays(6, to: start)
        header("\(Fmt.shortDate(start)) – \(Fmt.shortDate(end))", unit: .weekOfYear)
        ForEach(LRCalendar.days(ofWeekStarting: start), id: \.self) { d in
            let info = store.dayInfo(for: d)
            let tasks = store.tasks(on: d)
            let done = tasks.filter { store.status($0, on: d) == .done }.count
            let ev = store.events(on: d)
            Button { selected = d; mode = 0 } label: {
                HStack(spacing: 12) {
                    VStack {
                        Text(LRCalendar.shortWeekdayName(Calendar.current.component(.weekday, from: d))).font(.lrCaption).foregroundStyle(Theme.textTertiary)
                        Text("\(Calendar.current.component(.day, from: d))").font(.lrTitle)
                    }
                    .frame(width: 44)
                    .foregroundStyle(Calendar.current.isDateInToday(d) ? Theme.accent : Theme.textPrimary)
                    Rectangle().fill(info.info.kind.color).frame(width: 4).clipShape(Capsule())
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(info.info.kind.title + (info.info.isRecovery ? " · Recovery" : "")).font(.lrHeadline)
                            if !info.configured { Text("por configurar").font(.lrCaption).foregroundStyle(Theme.warning) }
                        }
                        if let s = info.info.shift {
                            Text("\(s.start.description)–\((info.info.effectiveEnd ?? s.end).description)\(info.info.overtimeMinutes > 0 ? " (+\(info.info.overtimeMinutes) min)" : "")")
                                .font(.lrCaption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                        }
                        Text("\(done)/\(tasks.count) tarefas\(ev.isEmpty ? "" : " · \(ev.count) compromisso(s)")").font(.lrCaption).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Mês
    @ViewBuilder
    private var monthView: some View {
        let cal = LRCalendar.current
        let range = store.monthRange(selected)
        let mStart = range.0, mEnd = range.1
        let gridStart = LRCalendar.weekStart(for: mStart)
        let count = (cal.dateComponents([.day], from: gridStart, to: mEnd).day ?? 35)
        let cells = Int(ceil(Double(count) / 7.0)) * 7
        header(Fmt.monthTitle(selected), unit: .month)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { Text(LRCalendar.shortWeekdayName($0)).font(.lrCaption).foregroundStyle(Theme.textTertiary) }
            ForEach(0..<cells, id: \.self) { i in
                let d = LRCalendar.addDays(i, to: gridStart)
                let inMonth = d >= mStart && d < mEnd
                let info = store.dayInfo(for: d)
                let isSel = cal.isDate(d, inSameDayAs: selected)
                Button { selected = d } label: {
                    VStack(spacing: 3) {
                        Text("\(cal.component(.day, from: d))").font(.lrBody.monospacedDigit())
                            .foregroundStyle(cal.isDateInToday(d) ? Theme.accent : (inMonth ? Theme.textPrimary : Theme.textTertiary.opacity(0.5)))
                        Circle().fill(info.configured ? info.info.kind.color : Color.clear).frame(width: 6, height: 6)
                        if info.info.isRecovery { Capsule().fill(Theme.warning).frame(width: 12, height: 2) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(isSel ? Theme.surfaceRaised : Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        HStack(spacing: 12) {
            ForEach([DayKind.burgerShift, .cafeShift, .dayOff, .travel], id: \.self) { k in
                HStack(spacing: 4) { Circle().fill(k.color).frame(width: 6, height: 6); Text(k.title).font(.lrCaption).foregroundStyle(Theme.textSecondary) }
            }
        }
        dayView(selected)
    }
}

struct DayRef: Identifiable { let date: Date; var id: TimeInterval { date.timeIntervalSince1970 } }

/// Novo compromisso (consulta, encontro…). Entra no plano do dia como bloco fixo.
struct EventEditView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let day: Date
    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var allDay = false
    @State private var location = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Título", text: $title)
                TextField("Local (opcional)", text: $location)
                Toggle("Dia inteiro", isOn: $allDay)
                DatePicker("Início", selection: $start, displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                if !allDay { DatePicker("Fim", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute]) }
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("Compromisso").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let s = allDay ? Calendar.current.startOfDay(for: start) : start
                        let e = allDay ? s.addingTimeInterval(86_399) : max(end, start.addingTimeInterval(300))
                        let ev = CalendarEvent(title: title, start: s, end: e); ev.allDay = allDay; ev.location = location
                        ctx.insert(ev); DataStore(ctx: ctx).save(); dismiss()
                    }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                let base = Calendar.current.isDateInToday(day) ? Date() : Calendar.current.date(byAdding: .hour, value: 10, to: day) ?? day
                start = base; end = base.addingTimeInterval(3600)
            }
        }
    }
}
