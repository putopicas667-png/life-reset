import SwiftUI
import SwiftData
import LifeResetCore

extension DataStore {
    func dayRange(_ date: Date) -> (Date, Date) { let s = cal.startOfDay(for: date); return (s, LRCalendar.addDays(1, to: s)) }

    func waterMl(on date: Date) -> Int {
        let (s, e) = dayRange(date)
        let d = FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.date >= s && $0.date < e })
        return ((try? ctx.fetch(d)) ?? []).reduce(0) { $0 + $1.ml }
    }

    func meals(on date: Date) -> [MealEntry] {
        let (s, e) = dayRange(date)
        let d = FetchDescriptor<MealEntry>(predicate: #Predicate { $0.date >= s && $0.date < e }, sortBy: [SortDescriptor(\.date)])
        return (try? ctx.fetch(d)) ?? []
    }

    func addWater(_ ml: Int) {
        ctx.insert(WaterEntry(date: Date(), ml: ml))
        let target = profile().dailyWaterMl
        if waterMl(on: Date()) >= target {
            Progression(store: self).award(10, area: .health, source: "Meta de água", key: "water:\(LRCalendar.dayKey(Date()))")
        }
        save()
    }

    func workouts(inWeekOf date: Date) -> [WorkoutSession] {
        let s = LRCalendar.weekStart(for: date), e = LRCalendar.addDays(7, to: s)
        let d = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.date >= s && $0.date < e })
        return (try? ctx.fetch(d)) ?? []
    }
}

/// Saúde e rotina: nutrição, água, corpo, treino, despensa e compras.
struct HealthHubView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var water: [WaterEntry]
    @Query private var meals: [MealEntry]
    @Query private var sessions: [WorkoutSession]
    @Query(filter: #Predicate<ShoppingItem> { !$0.bought }) private var shopping: [ShoppingItem]

    var body: some View {
        let store = DataStore(ctx: ctx)
        let p = store.profile()
        let _ = water.count + meals.count
        let today = Date()
        let todayMeals = store.meals(on: today)
        let kcal = todayMeals.reduce(0) { $0 + $1.kcal }
        let protein = todayMeals.reduce(0) { $0 + $1.protein }
        let ml = store.waterMl(on: today)
        let workouts = store.workouts(inWeekOf: today).count
        return ScrollView {
            VStack(spacing: Theme.spacing) {
                Card(title: "Hoje", systemImage: "heart.text.square") {
                    metric("Calorias", value: kcal, target: Double(p.dailyKcal), unit: "kcal")
                    metric("Proteína", value: protein, target: Double(p.dailyProteinG), unit: "g")
                    metric("Água", value: Double(ml) / 1000, target: Double(p.dailyWaterMl) / 1000, unit: "L", decimals: 1)
                    HStack {
                        ForEach([250, 500], id: \.self) { v in
                            Button("+\(v) ml") { store.addWater(v) }.buttonStyle(.bordered)
                        }
                    }
                }
                VStack(spacing: 1) {
                    link("Nutrição", "fork.knife", "\(Int(kcal)) / \(p.dailyKcal) kcal") { NutritionView() }
                    link("Água", "drop", Fmt.liters(fromMl: ml)) { WaterView() }
                    link("Treino", "dumbbell", "\(workouts)/\(p.workoutsPerWeek) esta semana") { TrainingView() }
                    link("Peso e corpo", "scalemass", "Peso, medidas e fotos") { BodyView() }
                    link("Despensa", "refrigerator", "O que há em casa e receitas") { PantryView() }
                    link("Lista de compras", "cart", shopping.isEmpty ? "Vazia" : "\(shopping.count) por comprar") { ShoppingView() }
                    link("Produtos pessoais", "sparkles", "Higiene e cuidado") { ProductsView() }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            }
            .padding(Theme.pagePadding)
        }
        .lrScreenBackground()
        .navigationTitle("Saúde e rotina")
    }

    private func metric(_ name: String, value: Double, target: Double, unit: String, decimals: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(Fmt.number(value, decimals: decimals)) / \(Fmt.number(target, decimals: decimals)) \(unit)").monospacedDigit()
            }.font(.lrBody)
            ThinProgressBar(value: target > 0 ? value / target : 0, tint: value >= target ? Theme.positive : Theme.accent)
        }
    }

    private func link<D: View>(_ title: String, _ icon: String, _ detail: String, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink(destination: destination) {
            HStack {
                Image(systemName: icon).frame(width: 26).foregroundStyle(Theme.accent)
                VStack(alignment: .leading) {
                    Text(title).foregroundStyle(Theme.textPrimary)
                    Text(detail).font(.lrCaption).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .background(Theme.surface)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Água

struct WaterView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \WaterEntry.date, order: .reverse) private var entries: [WaterEntry]

    var body: some View {
        let store = DataStore(ctx: ctx)
        let today = entries.filter { Calendar.current.isDateInToday($0.date) }
        let total = today.reduce(0) { $0 + $1.ml }
        let target = store.profile().dailyWaterMl
        return List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(Fmt.liters(fromMl: total)) de \(Fmt.liters(fromMl: target))").font(.lrNumber)
                    ThinProgressBar(value: Double(total) / Double(max(1, target)), tint: total >= target ? Theme.positive : Theme.accent)
                    HStack {
                        ForEach([150, 250, 330, 500], id: \.self) { v in Button("+\(v)") { store.addWater(v) }.buttonStyle(.bordered) }
                    }
                }
            }
            Section("Hoje") {
                if today.isEmpty { Text("Ainda nada registado.").foregroundStyle(Theme.textSecondary) }
                ForEach(today) { e in
                    KeyValueRow(key: e.date.formatted(date: .omitted, time: .shortened), value: "\(e.ml) ml")
                }
                .onDelete { idx in for i in idx { ctx.delete(today[i]) }; store.save() }
            }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle("Água")
    }
}

// MARK: - Nutrição

struct NutritionView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var allMeals: [MealEntry]
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var adding: MealType?
    @State private var showFoods = false

    var body: some View {
        let store = DataStore(ctx: ctx)
        let _ = allMeals.count
        let meals = store.meals(on: day)
        let p = store.profile()
        let kcal = meals.reduce(0) { $0 + $1.kcal }, protein = meals.reduce(0) { $0 + $1.protein }
        let plan = store.plan(for: day)
        let slots = plan.blocks.filter { $0.kind == .meal }
        return List {
            Section {
                HStack {
                    Button { day = LRCalendar.addDays(-1, to: day) } label: { Image(systemName: "chevron.left") }
                    Spacer(); Text(Fmt.longDate(day)).font(.lrHeadline); Spacer()
                    Button { day = LRCalendar.addDays(1, to: day) } label: { Image(systemName: "chevron.right") }
                }.buttonStyle(.plain)
                KeyValueRow(key: "Calorias", value: "\(Int(kcal)) / \(p.dailyKcal) kcal")
                ThinProgressBar(value: kcal / Double(max(1, p.dailyKcal)))
                KeyValueRow(key: "Proteína", value: "\(Int(protein)) / \(p.dailyProteinG) g")
                ThinProgressBar(value: protein / Double(max(1, p.dailyProteinG)))
                if kcal < Double(p.dailyKcal) {
                    Text("Faltam \(p.dailyKcal - Int(kcal)) kcal e \(max(0, p.dailyProteinG - Int(protein))) g de proteína.")
                        .font(.lrCaption).foregroundStyle(Theme.textSecondary)
                }
            }
            if !slots.isEmpty {
                Section("Horários sugeridos para hoje") {
                    ForEach(slots) { s in KeyValueRow(key: s.title, value: s.range.start.description) }
                }
            }
            ForEach(MealType.allCases, id: \.self) { type in
                let items = meals.filter { $0.mealRaw == type.rawValue }
                Section {
                    ForEach(items) { m in
                        HStack {
                            Text(m.name)
                            Spacer()
                            Text("\(Int(m.kcal)) kcal · \(Int(m.protein)) g").font(.lrCaption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .onDelete { idx in for i in idx { ctx.delete(items[i]) }; store.save() }
                    Button("Adicionar") { adding = type }.font(.lrCaption)
                } header: {
                    Text("\(type.title) · \(Int(items.reduce(0) { $0 + $1.kcal })) kcal")
                }
            }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle("Nutrição")
        .toolbar { Button("Alimentos") { showFoods = true } }
        .sheet(item: $adding) { AddMealSheet(type: $0, day: day) }
        .sheet(isPresented: $showFoods) { FoodsView() }
    }
}

extension MealType: Identifiable { public var id: String { rawValue } }

struct AddMealSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodItem.name) private var foods: [FoodItem]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    let type: MealType
    let day: Date
    @State private var food: FoodItem?
    @State private var quantity = 1.0
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Da lista de alimentos") {
                    Picker("Alimento", selection: $food) {
                        Text("—").tag(FoodItem?.none)
                        ForEach(foods) { Text("\($0.name) (\($0.unit))").tag(Optional($0)) }
                    }
                    if let f = food {
                        Stepper("Quantidade: \(Fmt.number(quantity, decimals: 1)) × \(f.unit)", value: $quantity, in: 0.5...20, step: 0.5)
                        Text("\(Int(f.kcalPerUnit * quantity)) kcal · \(Fmt.number(f.proteinPerUnit * quantity, decimals: 1)) g proteína")
                            .font(.lrCaption).foregroundStyle(Theme.textSecondary)
                        Button("Adicionar \(f.name)") { add(f.name, f.kcalPerUnit * quantity, f.proteinPerUnit * quantity) }
                    }
                }
                Section("Receita") {
                    ForEach(recipes) { r in
                        Button("\(r.name) · \(Int(r.kcal)) kcal") { add(r.name, r.kcal, r.protein) }
                    }
                }
                Section("Manual") {
                    TextField("Nome", text: $name)
                    TextField("kcal", text: $kcal).keyboardType(.decimalPad)
                    TextField("Proteína (g)", text: $protein).keyboardType(.decimalPad)
                    Button("Adicionar") {
                        add(name, Double(kcal.replacingOccurrences(of: ",", with: ".")) ?? 0, Double(protein.replacingOccurrences(of: ",", with: ".")) ?? 0)
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle(type.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
        }
    }

    private func add(_ n: String, _ k: Double, _ p: Double) {
        let cal = Calendar.current
        let date = cal.isDateInToday(day) ? Date() : cal.date(byAdding: .hour, value: 12, to: cal.startOfDay(for: day)) ?? day
        ctx.insert(MealEntry(date: date, meal: type, name: n, quantity: quantity, kcal: k, protein: p))
        let store = DataStore(ctx: ctx)
        let total = store.meals(on: day).reduce(0) { $0 + $1.protein } + p
        if total >= Double(store.profile().dailyProteinG) {
            Progression(store: store).award(10, area: .health, source: "Meta de proteína", key: "protein:\(LRCalendar.dayKey(day))", date: day)
        }
        store.save()
        dismiss()
    }
}

struct FoodsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodItem.name) private var foods: [FoodItem]
    @State private var name = ""
    @State private var unit = "100 g"
    @State private var kcal = ""
    @State private var protein = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Novo alimento") {
                    TextField("Nome", text: $name)
                    TextField("Unidade (ex.: 100 g, unidade)", text: $unit)
                    TextField("kcal por unidade", text: $kcal).keyboardType(.decimalPad)
                    TextField("Proteína por unidade (g)", text: $protein).keyboardType(.decimalPad)
                    Button("Guardar") {
                        ctx.insert(FoodItem(name: name, kcal: Double(kcal.replacingOccurrences(of: ",", with: ".")) ?? 0,
                                            protein: Double(protein.replacingOccurrences(of: ",", with: ".")) ?? 0, unit: unit))
                        DataStore(ctx: ctx).save(); name = ""; kcal = ""; protein = ""
                    }.disabled(name.isEmpty)
                }
                Section("Alimentos") {
                    ForEach(foods) { f in
                        KeyValueRow(key: f.name, value: "\(Int(f.kcalPerUnit)) kcal · \(Fmt.number(f.proteinPerUnit, decimals: 1)) g / \(f.unit)")
                    }
                    .onDelete { idx in for i in idx { ctx.delete(foods[i]) }; DataStore(ctx: ctx).save() }
                }
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("Alimentos").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
        }
    }
}
