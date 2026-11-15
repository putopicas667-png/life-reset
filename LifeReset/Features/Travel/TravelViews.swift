import SwiftUI
import SwiftData
import LifeResetCore

/// Lembretes calculados de uma viagem (as notificações usam a mesma lista).
struct TripReminder: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let title: String
    let date: Date
}

extension DataStore {
    func flights(of trip: Trip) -> [Flight] {
        let uid = trip.uid
        return (try? ctx.fetch(FetchDescriptor<Flight>(predicate: #Predicate { $0.tripUID == uid }, sortBy: [SortDescriptor(\.departure)]))) ?? []
    }

    func checklist(of trip: Trip) -> [TripChecklistItem] {
        let uid = trip.uid
        return (try? ctx.fetch(FetchDescriptor<TripChecklistItem>(predicate: #Predicate { $0.tripUID == uid }))) ?? []
    }

    func reminders(for trip: Trip) -> [TripReminder] {
        var out: [TripReminder] = []
        let cal = Calendar.current
        if let eve = cal.date(bySettingHour: 20, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -1, to: trip.departure) ?? trip.departure) {
            out.append(TripReminder(key: "pack", title: "Fazer a mala para \(trip.destination)", date: eve))
        }
        for f in flights(of: trip) {
            out.append(TripReminder(key: "checkin-\(f.number)", title: "Check-in online do voo \(f.number)", date: f.departure.addingTimeInterval(-24 * 3600)))
            let leave = f.departure.addingTimeInterval(-Double(120 + trip.minutesToAirport) * 60)
            out.append(TripReminder(key: "leave-\(f.number)", title: "Sair para o aeroporto (\(f.fromAirport)) — voo \(f.number)", date: leave))
        }
        return out.sorted { $0.date < $1.date }
    }

    func createTrip(destination: String, departure: Date, returnDate: Date) -> Trip {
        let t = Trip(destination: destination, departure: cal.startOfDay(for: departure), returnDate: cal.startOfDay(for: returnDate))
        ctx.insert(t)
        if let tpl = (try? ctx.fetch(FetchDescriptor<ChecklistTemplate>()))?.first {
            for e in Coding.decode([ChecklistEntry].self, tpl.itemsData) ?? [] {
                ctx.insert(TripChecklistItem(tripUID: t.uid, category: e.category, text: e.text))
            }
        }
        save()
        return t
    }
}

enum TZFormat {
    static func time(_ d: Date, tz: String) -> String {
        let f = DateFormatter()
        f.locale = Fmt.locale
        f.timeZone = TimeZone(identifier: tz) ?? .current
        f.dateFormat = "d MMM, HH:mm"
        return f.string(from: d)
    }
    static func label(_ tz: String) -> String {
        let z = TimeZone(identifier: tz) ?? .current
        let h = Double(z.secondsFromGMT()) / 3600
        let city = tz.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? tz
        return "\(city) (UTC\(h >= 0 ? "+" : "")\(h == h.rounded() ? String(Int(h)) : String(h)))"
    }
}

/// Lista de viagens.
struct TripsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Trip.departure, order: .reverse) private var trips: [Trip]
    @State private var showNew = false

    var body: some View {
        List {
            Section {
                Text("Durante uma viagem, o plano diário deixa de propor tarefas de casa e mantém só o essencial.")
                    .font(.lrCaption).foregroundStyle(Theme.textSecondary)
            }
            if trips.isEmpty { Text("Sem viagens.").foregroundStyle(Theme.textSecondary) }
            ForEach(trips) { t in
                NavigationLink { TripDetailView(trip: t) } label: {
                    VStack(alignment: .leading) {
                        Text(t.destination).font(.lrHeadline)
                        Text("\(Fmt.shortDate(t.departure)) – \(Fmt.shortDate(t.returnDate))").font(.lrCaption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .onDelete { idx in
                let store = DataStore(ctx: ctx)
                for i in idx {
                    let t = trips[i]
                    for f in store.flights(of: t) { ctx.delete(f) }
                    for c in store.checklist(of: t) { ctx.delete(c) }
                    ctx.delete(t)
                }
                store.save()
            }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle("Viagens")
        .toolbar { Button { showNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showNew) { NewTripSheet() }
    }
}

struct NewTripSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var destination = ""
    @State private var departure = Date()
    @State private var back = Date().addingTimeInterval(4 * 86_400)

    var body: some View {
        NavigationStack {
            Form {
                TextField("Destino", text: $destination)
                DatePicker("Partida", selection: $departure, displayedComponents: .date)
                DatePicker("Regresso", selection: $back, in: departure..., displayedComponents: .date)
                Text("A lista de bagagem padrão é copiada para esta viagem.").font(.lrCaption).foregroundStyle(Theme.textSecondary)
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("Nova viagem").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Criar") { _ = DataStore(ctx: ctx).createTrip(destination: destination, departure: departure, returnDate: back); dismiss() }
                        .disabled(destination.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct TripDetailView: View {
    @Environment(\.modelContext) private var ctx
    @Bindable var trip: Trip
    @Query private var flightsQ: [Flight]
    @Query private var itemsQ: [TripChecklistItem]
    @State private var addFlight = false
    @State private var newItem = ""
    @State private var newCategory = "Outros"

    var body: some View {
        let store = DataStore(ctx: ctx)
        let _ = flightsQ.count + itemsQ.count
        let flights = store.flights(of: trip)
        let items = store.checklist(of: trip)
        let groups = Dictionary(grouping: items, by: \.category).sorted { $0.key < $1.key }
        let checked = items.filter(\.checked).count
        return List {
            Section("Viagem") {
                TextField("Destino", text: $trip.destination)
                DatePicker("Partida", selection: $trip.departure, displayedComponents: .date)
                DatePicker("Regresso", selection: $trip.returnDate, in: trip.departure..., displayedComponents: .date)
                TextField("Alojamento", text: $trip.lodging)
                TextField("Transporte até ao aeroporto", text: $trip.transportToAirport)
                Stepper("Até ao aeroporto: \(trip.minutesToAirport) min", value: $trip.minutesToAirport, in: 10...240, step: 5)
            }
            Section("Voos") {
                ForEach(flights) { f in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(f.number) · \(f.fromAirport) → \(f.toAirport)").font(.lrHeadline)
                        Text("Parte \(TZFormat.time(f.departure, tz: f.departureTZ)) (hora local de \(TZFormat.label(f.departureTZ)))").font(.lrCaption)
                        Text("Chega \(TZFormat.time(f.arrival, tz: f.arrivalTZ)) (hora local de \(TZFormat.label(f.arrivalTZ)))").font(.lrCaption)
                        Text("Duração: \(Int(f.arrival.timeIntervalSince(f.departure) / 3600)) h \(Int(f.arrival.timeIntervalSince(f.departure) / 60) % 60) min")
                            .font(.lrCaption).foregroundStyle(Theme.textTertiary)
                    }
                }
                .onDelete { idx in for i in idx { ctx.delete(flights[i]) }; store.save() }
                Button("Adicionar voo") { addFlight = true }
            }
            Section("Lembretes") {
                ForEach(store.reminders(for: trip)) { r in
                    KeyValueRow(key: r.title, value: r.date.formatted(date: .abbreviated, time: .shortened))
                }
                Text("Recebes notificações destes lembretes se as notificações estiverem ativas.").font(.lrCaption).foregroundStyle(Theme.textTertiary)
            }
            Section("Bagagem · \(checked)/\(items.count)") {
                ThinProgressBar(value: items.isEmpty ? 0 : Double(checked) / Double(items.count), tint: Theme.positive)
                HStack {
                    TextField("Novo item", text: $newItem)
                    Picker("", selection: $newCategory) {
                        ForEach(["Documentos", "Higiene", "Roupa", "Tecnologia", "Medicamentos", "Acessórios", "Outros"], id: \.self) { Text($0) }
                    }.labelsHidden()
                    Button { ctx.insert(TripChecklistItem(tripUID: trip.uid, category: newCategory, text: newItem)); store.save(); newItem = "" } label: {
                        Image(systemName: "plus.circle.fill")
                    }.disabled(newItem.isEmpty)
                }
            }
            ForEach(groups, id: \.key) { g in
                Section(g.key) {
                    ForEach(g.value) { i in
                        Button { i.checked.toggle(); store.save() } label: {
                            HStack {
                                Image(systemName: i.checked ? "checkmark.square.fill" : "square").foregroundStyle(i.checked ? Theme.positive : Theme.textTertiary)
                                Text(i.text).foregroundStyle(i.checked ? Theme.textTertiary : Theme.textPrimary)
                            }
                        }
                    }
                    .onDelete { idx in for x in idx { ctx.delete(g.value[x]) }; store.save() }
                }
            }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle(trip.destination)
        .onDisappear { store.save() }
        .sheet(isPresented: $addFlight) { FlightEditView(trip: trip) }
    }
}

struct FlightEditView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    @State private var number = ""
    @State private var from = "GVA"
    @State private var to = ""
    @State private var depTZ = TimeZone.current.identifier
    @State private var arrTZ = TimeZone.current.identifier
    @State private var dep = Date()
    @State private var arr = Date().addingTimeInterval(7200)

    var body: some View {
        NavigationStack {
            Form {
                Section("Voo") {
                    TextField("Número (ex.: TP943)", text: $number).textInputAutocapitalization(.characters)
                    TextField("De (aeroporto)", text: $from).textInputAutocapitalization(.characters)
                    TextField("Para (aeroporto)", text: $to).textInputAutocapitalization(.characters)
                }
                Section {
                    TimeZonePicker(title: "Fuso da partida", selection: $depTZ)
                    LocalDateTimePicker(title: "Partida (hora local)", date: $dep, tz: depTZ)
                }
                Section {
                    TimeZonePicker(title: "Fuso da chegada", selection: $arrTZ)
                    LocalDateTimePicker(title: "Chegada (hora local)", date: $arr, tz: arrTZ)
                } footer: { Text("Introduz as horas tal como aparecem no bilhete (hora local de cada aeroporto).") }
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("Voo").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let f = Flight(tripUID: trip.uid)
                        f.number = number; f.fromAirport = from; f.toAirport = to
                        f.departure = dep; f.arrival = max(arr, dep); f.departureTZ = depTZ; f.arrivalTZ = arrTZ
                        ctx.insert(f); DataStore(ctx: ctx).save(); dismiss()
                    }.disabled(number.isEmpty)
                }
            }
            .onAppear { dep = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: trip.departure) ?? trip.departure; arr = dep.addingTimeInterval(7200) }
        }
    }
}

/// Escolhe data e hora como "hora local" de um fuso, guardando o instante absoluto correto.
struct LocalDateTimePicker: View {
    let title: String
    @Binding var date: Date
    let tz: String

    var body: some View {
        DatePicker(title, selection: Binding(get: { shift(date, to: .current) }, set: { date = shift($0, from: .current) }),
                   displayedComponents: [.date, .hourAndMinute])
    }

    private var zone: TimeZone { TimeZone(identifier: tz) ?? .current }
    /// Mostra o instante como se o relógio do iPhone estivesse no fuso do aeroporto.
    private func shift(_ d: Date, to local: TimeZone) -> Date {
        d.addingTimeInterval(TimeInterval(zone.secondsFromGMT(for: d) - local.secondsFromGMT(for: d)))
    }
    private func shift(_ d: Date, from local: TimeZone) -> Date {
        d.addingTimeInterval(TimeInterval(local.secondsFromGMT(for: d) - zone.secondsFromGMT(for: d)))
    }
}

struct TimeZonePicker: View {
    let title: String
    @Binding var selection: String
    static let common = ["Europe/Zurich", "Europe/Lisbon", "Atlantic/Azores", "Atlantic/Madeira", "Europe/London", "Europe/Paris",
                         "Europe/Madrid", "Europe/Rome", "Europe/Berlin", "Europe/Athens", "Europe/Istanbul", "Africa/Casablanca",
                         "America/Sao_Paulo", "America/New_York", "America/Los_Angeles", "Asia/Dubai", "Asia/Bangkok", "Asia/Tokyo"]

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(Array(Set(Self.common + [selection, TimeZone.current.identifier])).sorted(), id: \.self) { Text(TZFormat.label($0)).tag($0) }
        }
    }
}
