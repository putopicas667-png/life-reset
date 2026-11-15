import SwiftUI
import SwiftData
import LifeResetCore

/// Despensa: o que há em casa, validade e receitas possíveis.
struct PantryView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \PantryItem.name) private var items: [PantryItem]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @State private var name = ""
    @State private var qty = 1.0
    @State private var unit = "un"
    @State private var hasExpiry = false
    @State private var expiry = Date()

    var body: some View {
        let store = DataStore(ctx: ctx)
        let matches = RecipeMatcher.rank(recipes.map { (name: $0.name, ingredients: Coding.decode([String].self, $0.ingredientsData) ?? []) },
                                         pantry: items.filter { $0.quantity > 0 }.map(\.name))
        let soon = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        return List {
            Section("Adicionar") {
                TextField("Produto", text: $name)
                Stepper("Quantidade: \(Fmt.number(qty, decimals: qty.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)) \(unit)", value: $qty, in: 0.5...100, step: 0.5)
                Picker("Unidade", selection: $unit) { ForEach(["un", "g", "kg", "ml", "L", "pacote", "lata"], id: \.self) { Text($0) } }
                Toggle("Tem validade", isOn: $hasExpiry)
                if hasExpiry { DatePicker("Validade", selection: $expiry, displayedComponents: .date) }
                Button("Guardar") {
                    let i = PantryItem(name: name.trimmingCharacters(in: .whitespaces), quantity: qty, unit: unit)
                    i.expiry = hasExpiry ? expiry : nil
                    ctx.insert(i); store.save(); name = ""; qty = 1; hasExpiry = false
                }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("Em casa") {
                if items.isEmpty { Text("A despensa está vazia.").foregroundStyle(Theme.textSecondary) }
                ForEach(items) { i in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(i.name)
                            if let e = i.expiry {
                                Text("Validade \(Fmt.shortDate(e))").font(.lrCaption)
                                    .foregroundStyle(e < soon ? Theme.warning : Theme.textTertiary)
                            }
                        }
                        Spacer()
                        Stepper("\(Fmt.number(i.quantity, decimals: 1)) \(i.unit)", value: Binding(get: { i.quantity }, set: { i.quantity = max(0, $0); store.save() }), in: 0...1000, step: i.unit == "g" || i.unit == "ml" ? 50 : 1)
                            .fixedSize()
                    }
                    .swipeActions {
                        Button("Acabou") {
                            ctx.insert(ShoppingItem(name: i.name, quantity: ""))
                            ctx.delete(i); store.save()
                        }.tint(Theme.warning)
                        Button("Apagar", role: .destructive) { ctx.delete(i); store.save() }
                    }
                }
            }

            Section("Receitas possíveis") {
                ForEach(matches.prefix(6), id: \.name) { m in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(m.name)
                            Spacer()
                            Text("\(m.have.count)/\(m.have.count + m.missing.count)").font(.lrCaption.monospacedDigit())
                                .foregroundStyle(m.missing.isEmpty ? Theme.positive : Theme.textSecondary)
                        }
                        if !m.missing.isEmpty {
                            HStack {
                                Text("Falta: " + m.missing.joined(separator: ", ")).font(.lrCaption).foregroundStyle(Theme.textTertiary)
                                Spacer()
                                Button("Para a lista") {
                                    for x in m.missing { ctx.insert(ShoppingItem(name: x, quantity: "")) }
                                    store.save()
                                }.font(.lrCaption).buttonStyle(.borderless)
                            }
                        }
                    }
                }
                NavigationLink("Gerir receitas") { RecipesView() }
            }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle("Despensa")
    }
}

struct RecipesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @State private var name = ""
    @State private var ingredients = ""
    @State private var kcal = ""
    @State private var protein = ""

    var body: some View {
        List {
            Section("Nova receita") {
                TextField("Nome", text: $name)
                TextField("Ingredientes (separados por vírgulas)", text: $ingredients, axis: .vertical)
                TextField("kcal", text: $kcal).keyboardType(.numberPad)
                TextField("Proteína (g)", text: $protein).keyboardType(.numberPad)
                Button("Guardar") {
                    let r = Recipe(name: name)
                    r.ingredientsData = Coding.encode(ingredients.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
                    r.kcal = Double(kcal) ?? 0; r.protein = Double(protein) ?? 0
                    ctx.insert(r); DataStore(ctx: ctx).save(); name = ""; ingredients = ""; kcal = ""; protein = ""
                }.disabled(name.isEmpty)
            }
            Section("Receitas") {
                ForEach(recipes) { r in
                    VStack(alignment: .leading) {
                        Text(r.name)
                        Text((Coding.decode([String].self, r.ingredientsData) ?? []).joined(separator: ", ") + " · \(Int(r.kcal)) kcal · \(Int(r.protein)) g")
                            .font(.lrCaption).foregroundStyle(Theme.textTertiary)
                    }
                }
                .onDelete { idx in for i in idx { ctx.delete(recipes[i]) }; DataStore(ctx: ctx).save() }
            }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle("Receitas")
    }
}

/// Lista de compras: marcar comprado passa para a despensa.
struct ShoppingView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \ShoppingItem.createdAt) private var items: [ShoppingItem]
    @State private var name = ""
    @State private var qty = ""

    var body: some View {
        let store = DataStore(ctx: ctx)
        let pending = items.filter { !$0.bought }, bought = items.filter(\.bought)
        return List {
            Section {
                HStack {
                    TextField("Adicionar", text: $name).onSubmit(add)
                    TextField("Qtd.", text: $qty).frame(width: 60)
                    Button(action: add) { Image(systemName: "plus.circle.fill") }.disabled(name.isEmpty)
                }
            }
            Section("Por comprar (\(pending.count))") {
                ForEach(pending) { i in
                    Button {
                        i.bought = true
                        let p = PantryItem(name: i.name, quantity: Double(i.quantity.replacingOccurrences(of: ",", with: ".")) ?? 1, unit: "un")
                        ctx.insert(p); store.save()
                    } label: {
                        HStack {
                            Image(systemName: "circle").foregroundStyle(Theme.textTertiary)
                            Text(i.name).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(i.quantity).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .onDelete { idx in for i in idx { ctx.delete(pending[i]) }; store.save() }
            }
            if !bought.isEmpty {
                Section {
                    ForEach(bought) { i in
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positive)
                            Text(i.name).strikethrough().foregroundStyle(Theme.textTertiary)
                        }
                    }
                    Button("Limpar comprados") { for i in bought { ctx.delete(i) }; store.save() }
                } header: { Text("Comprados") } footer: { Text("Os comprados já foram para a despensa.") }
            }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle("Compras")
    }

    private func add() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        ctx.insert(ShoppingItem(name: n, quantity: qty)); DataStore(ctx: ctx).save(); name = ""; qty = ""
    }
}

/// Produtos pessoais (higiene e cuidado): marcar "acabou" põe na lista de compras.
struct ProductsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \PersonalProduct.name) private var products: [PersonalProduct]
    @State private var name = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Novo produto", text: $name)
                    Button("Adicionar") { ctx.insert(PersonalProduct(name: name)); DataStore(ctx: ctx).save(); name = "" }.disabled(name.isEmpty)
                }
            }
            Section("Produtos") {
                ForEach(products) { p in
                    HStack {
                        Text(p.name)
                        Spacer()
                        Button(p.have ? "Tenho" : "Acabou") {
                            p.have.toggle()
                            if !p.have { ctx.insert(ShoppingItem(name: p.name, quantity: "")) }
                            DataStore(ctx: ctx).save()
                        }
                        .buttonStyle(.bordered)
                        .tint(p.have ? Theme.positive : Theme.warning)
                    }
                }
                .onDelete { idx in for i in idx { ctx.delete(products[i]) }; DataStore(ctx: ctx).save() }
            }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle("Produtos pessoais")
    }
}
