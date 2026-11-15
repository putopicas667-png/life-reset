import Foundation
import SwiftData
import LifeResetCore

/// Trabalho feito ao abrir a app: dados iniciais e tarefas que ficaram por fazer (nada é apagado).
@MainActor
enum Maintenance {
    static func run(_ ctx: ModelContext) {
        let store = DataStore(ctx: ctx)
        Seeder.seedIfNeeded(store)
        processRollover(store)
        store.ensureMonthlyReport()
        store.save()
    }

    /// Dias passados: marca como falhadas as ocorrências pendentes e cria propostas de reagendamento.
    static func processRollover(_ store: DataStore) {
        let cal = store.cal
        let today = cal.startOfDay(for: Date())
        let yesterday = LRCalendar.addDays(-1, to: today)
        var day: Date
        if let last = store.meta("rollover.last"), let d = ISO8601DateFormatter.dayOnly.date(from: last) {
            day = LRCalendar.addDays(1, to: d)
        } else {
            day = yesterday
        }
        day = max(day, LRCalendar.addDays(-7, to: today))
        guard day <= yesterday else { return }
        let upcoming = store.weekInfos(from: today, days: 10)

        while day <= yesterday {
            let info = store.dayInfo(for: day).info
            for t in store.tasks(on: day) where store.status(t, on: day) == .pending {
                // Durante viagens, tarefas de casa não contam como falhadas.
                if info.kind == .travel && t.location == .home { continue }
                if case .weeklyFlexible = t.recurrence, cal.component(.weekday, from: day) != 1 { continue }
                if info.isRecovery && !t.essential { continue }
                switch Rollover.decide(policy: t.failurePolicy, deadline: t.deadline, today: today) {
                case .keepPending:
                    continue
                case .markFailed:
                    store.ctx.insert(TaskOccurrence(taskUID: t.uid, date: day, status: OccurrenceStatus.failed.rawValue))
                case .markFailedAndPropose:
                    store.ctx.insert(TaskOccurrence(taskUID: t.uid, date: day, status: OccurrenceStatus.failed.rawValue))
                    let target = Rollover.suggestDay(after: today.addingTimeInterval(-1), preferDaysOff: t.preferDayOff || t.category == "household",
                                                     upcoming: upcoming)
                    store.ctx.insert(RescheduleSuggestion(taskUID: t.uid, title: t.title, fromDate: day, suggestedDate: target,
                                                          reason: "Ficou por fazer"))
                }
            }
            day = LRCalendar.addDays(1, to: day)
        }
        store.setMeta("rollover.last", ISO8601DateFormatter.dayOnly.string(from: yesterday))
    }
}

extension ISO8601DateFormatter {
    static let dayOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = .current
        return f
    }()
}

/// Dados iniciais da especificação (higiene, manutenção pessoal, casa, finanças, treino…). Tudo editável.
@MainActor
enum Seeder {
    static func seedIfNeeded(_ store: DataStore) {
        guard store.meta("seed.v2") == nil else { return }
        seedTasks(store)
        seedNutrition(store)
        seedTraining(store)
        seedFinance(store)
        seedTravel(store)
        store.setMeta("seed.v2", "1")
    }

    private static func add(_ store: DataStore, _ title: String, category: String, minutes: Int, timing: TaskTiming,
                            recurrence: Recurrence, location: TaskLocation = .home, essential: Bool = false,
                            priority: Int = 3, policy: FailurePolicy = .carryToNextPeriod, shared: Bool = false,
                            preferDayOff: Bool = false, heavy: Bool = false) {
        let t = TaskItem(title: title)
        t.category = category; t.durationMinutes = minutes; t.timing = timing; t.recurrence = recurrence
        t.locationRaw = location.rawValue; t.essential = essential; t.priority = priority; t.failureRaw = policy.rawValue
        t.sharingRaw = shared ? Sharing.shared.rawValue : Sharing.personal.rawValue
        t.preferDayOff = preferDayOff; t.heavy = heavy; t.xpArea = XPArea.forCategory(category).rawValue
        store.ctx.insert(t)
    }

    static func seedTasks(_ s: DataStore) {
        let today = Calendar.current.startOfDay(for: Date())
        // Higiene — manhã
        for (title, min) in [("Lavar a cara", 2), ("Produto de limpeza facial", 2), ("Aplicar hidratante", 1), ("Escovar dentes", 3),
                             ("Limpar língua", 1), ("Elixir", 1), ("Desodorizante", 1), ("Perfume", 1), ("Pentear cabelo", 2),
                             ("Tratar da barba", 5), ("Creme corporal", 3), ("Cuidados dos lábios", 1)] {
            add(s, title, category: "hygiene", minutes: min, timing: .anchored(.morning), recurrence: .daily, essential: true)
        }
        // Após almoço
        add(s, "Escovar dentes (após almoço)", category: "hygiene", minutes: 3, timing: .anchored(.afterLunch), recurrence: .daily,
            location: .anywhere, essential: true)
        // Noite
        for (title, min) in [("Lavar a cara (noite)", 2), ("Hidratante (noite)", 1), ("Escovar dentes (noite)", 3), ("Limpar língua (noite)", 1),
                             ("Preparar roupa para amanhã", 5), ("Duche", 15)] {
            add(s, title, category: "hygiene", minutes: min, timing: .anchored(.evening), recurrence: .daily, essential: true)
        }
        // Manutenção pessoal
        let flex = TaskTiming.flexible(earliest: TimeOfDay(8), latest: TimeOfDay(23, 30))
        add(s, "Cortar unhas", category: "hygiene", minutes: 10, timing: flex, recurrence: .everyNDays(n: 7, anchor: today), policy: .proposeReschedule)
        add(s, "Aparar barba", category: "hygiene", minutes: 15, timing: flex, recurrence: .everyNDays(n: 4, anchor: today), policy: .proposeReschedule)
        add(s, "Mudar toalhas", category: "household", minutes: 5, timing: flex, recurrence: .weeklyFlexible, policy: .proposeReschedule)
        add(s, "Mudar lençóis", category: "household", minutes: 15, timing: flex, recurrence: .everyNDays(n: 14, anchor: today), policy: .proposeReschedule, preferDayOff: true)
        add(s, "Limpar o exterior das orelhas", category: "hygiene", minutes: 3, timing: flex, recurrence: .everyNDays(n: 7, anchor: today))
        add(s, "Limpar escova de dentes", category: "hygiene", minutes: 3, timing: flex, recurrence: .everyNDays(n: 7, anchor: today))
        // Casa
        add(s, "Fazer a cama", category: "household", minutes: 3, timing: .anchored(.morning), recurrence: .daily, essential: true)
        add(s, "Lavar loiça", category: "household", minutes: 15, timing: .anchored(.evening), recurrence: .daily, shared: true)
        add(s, "Pequena limpeza diária", category: "household", minutes: 10, timing: flex, recurrence: .daily)
        let weekly: [(String, Int, Bool)] = [("Limpeza geral", 90, true), ("Aspirar", 20, true), ("Lavar o chão", 25, true),
                                             ("Limpar casa de banho", 25, true), ("Limpar cozinha", 25, true), ("Limpar pó", 15, false),
                                             ("Arrumar quarto", 15, false), ("Organizar secretária", 10, false), ("Limpar espelhos", 10, false),
                                             ("Lavandaria", 60, true)]
        for (title, min, shared) in weekly {
            add(s, title, category: "household", minutes: min, timing: flex, recurrence: .weeklyFlexible,
                policy: .proposeReschedule, shared: shared, preferDayOff: true)
        }
        add(s, "Deitar lixo fora", category: "household", minutes: 5, timing: flex, recurrence: .everyNDays(n: 2, anchor: today), location: .home, shared: true)
        add(s, "Limpar micro-ondas", category: "household", minutes: 10, timing: flex, recurrence: .everyNDays(n: 14, anchor: today), policy: .proposeReschedule, shared: true, preferDayOff: true)
        add(s, "Limpar frigorífico", category: "household", minutes: 30, timing: flex, recurrence: .monthly(day: 15), policy: .proposeReschedule, shared: true, preferDayOff: true)
        add(s, "Organizar guarda-roupa", category: "household", minutes: 30, timing: flex, recurrence: .monthly(day: 1), policy: .proposeReschedule, preferDayOff: true)
        // Pequenas tarefas compatíveis com a pausa
        add(s, "Registar refeição da pausa", category: "nutrition", minutes: 2,
            timing: .flexible(earliest: TimeOfDay(10), latest: TimeOfDay(22, 30)), recurrence: .daily, location: .breakCompatible)
    }

    static func seedNutrition(_ s: DataStore) {
        let foods: [(String, Double, Double, String)] = [
            ("Massa (cozida)", 158, 5.8, "100 g"), ("Arroz (cozido)", 130, 2.7, "100 g"), ("Ovo", 72, 6.3, "unidade"),
            ("Peito de frango", 165, 31, "100 g"), ("Cogumelos", 22, 3.1, "100 g"), ("Leite meio-gordo", 46, 3.3, "100 ml"),
            ("Banana", 105, 1.3, "unidade"), ("Atum (lata, escorrido)", 116, 26, "100 g"), ("Queijo", 350, 25, "100 g"),
            ("Pão", 265, 9, "100 g"), ("Carne de vaca (picada)", 250, 26, "100 g"), ("Maçã", 80, 0.4, "unidade"),
        ]
        for f in foods { s.ctx.insert(FoodItem(name: f.0, kcal: f.1, protein: f.2, unit: f.3)) }
        let recipes: [(String, [String], Double, Double)] = [
            ("Massa com frango e cogumelos", ["Massa", "Frango", "Cogumelos", "Queijo"], 850, 60),
            ("Arroz com atum e ovo", ["Arroz", "Atum", "Ovo"], 650, 45),
            ("Omelete de queijo com pão", ["Ovo", "Queijo", "Pão"], 600, 35),
            ("Batido de banana e leite", ["Banana", "Leite"], 350, 12),
            ("Arroz com carne de vaca", ["Arroz", "Carne de vaca", "Cogumelos"], 800, 50),
            ("Tosta de atum", ["Pão", "Atum", "Queijo"], 500, 35),
        ]
        for r in recipes {
            let rec = Recipe(name: r.0); rec.ingredientsData = Coding.encode(r.1); rec.kcal = r.2; rec.protein = r.3
            s.ctx.insert(rec)
        }
        for p in ["Champô", "Gel de banho", "Pasta de dentes", "Creme facial", "Hidratante", "Desodorizante", "Perfume",
                  "Elixir", "Produto de limpeza facial", "Creme corporal", "Bálsamo para lábios"] {
            s.ctx.insert(PersonalProduct(name: p))
        }
    }

    static func seedTraining(_ s: DataStore) {
        let ex: [(String, [String], String)] = [
            ("Supino com barra", ["Peito", "Tríceps", "Ombros"], "Banco + barra"),
            ("Supino com halteres", ["Peito", "Tríceps"], "Banco + halteres"),
            ("Elevações", ["Costas", "Bíceps", "Antebraços"], "Barra de elevações"),
            ("Remada curvada com barra", ["Costas", "Bíceps"], "Barra"),
            ("Remada unilateral com halter", ["Costas"], "Banco + halteres"),
            ("Press de ombros com halteres", ["Ombros", "Tríceps"], "Halteres"),
            ("Elevações laterais", ["Ombros"], "Halteres"),
            ("Curl de bíceps com barra", ["Bíceps", "Antebraços"], "Barra"),
            ("Curl martelo", ["Bíceps", "Antebraços"], "Halteres"),
            ("Extensão de tríceps (francês)", ["Tríceps"], "Banco + barra"),
            ("Mergulhos no banco", ["Tríceps", "Peito"], "Banco"),
            ("Roda abdominal", ["Abdominais"], "Roda abdominal"),
            ("Elevação de pernas na barra", ["Abdominais"], "Barra de elevações"),
            ("Curl de pulso", ["Antebraços"], "Halteres"),
            ("Flexões", ["Peito", "Tríceps"], "Peso corporal"),
        ]
        for e in ex { s.ctx.insert(Exercise(name: e.0, muscles: e.1, equipment: e.2)) }
        let templates: [(String, [TemplateItem], Bool)] = [
            ("A — Peito, ombros e tríceps", [.init(exercise: "Supino com barra", sets: 4, reps: 8), .init(exercise: "Press de ombros com halteres", sets: 3, reps: 10),
                                             .init(exercise: "Elevações laterais", sets: 3, reps: 12), .init(exercise: "Extensão de tríceps (francês)", sets: 3, reps: 10),
                                             .init(exercise: "Roda abdominal", sets: 3, reps: 10)], false),
            ("B — Costas, bíceps e antebraços", [.init(exercise: "Elevações", sets: 4, reps: 6), .init(exercise: "Remada curvada com barra", sets: 4, reps: 8),
                                                 .init(exercise: "Curl de bíceps com barra", sets: 3, reps: 10), .init(exercise: "Curl martelo", sets: 3, reps: 10),
                                                 .init(exercise: "Curl de pulso", sets: 3, reps: 15)], false),
            ("Curto — dia de trabalho (20 min)", [.init(exercise: "Flexões", sets: 3, reps: 15), .init(exercise: "Elevações", sets: 3, reps: 5),
                                                  .init(exercise: "Roda abdominal", sets: 2, reps: 10)], true),
        ]
        for t in templates {
            let w = WorkoutTemplate(name: t.0); w.itemsData = Coding.encode(t.1); w.short = t.2
            s.ctx.insert(w)
        }
    }

    static func seedFinance(_ s: DataStore) {
        for (name, icon) in [("Casa", "house"), ("Saúde", "cross.case"), ("Telemóvel e internet", "wifi"), ("Transportes", "tram"),
                             ("Alimentação", "cart"), ("Restaurantes", "fork.knife"), ("Higiene", "sparkles"), ("Lazer", "gamecontroller"),
                             ("Roupa", "tshirt"), ("Dívidas", "creditcard"), ("Outros", "tag")] {
            s.ctx.insert(ExpenseCategory(name: name, icon: icon))
        }
        let fixed: [(String, Decimal, Bool, Int, String)] = [
            ("Renda", 550, false, 1, "Casa"), ("Seguro de saúde", 600, false, 1, "Saúde"), ("Telemóvel", 70, false, 5, "Telemóvel e internet"),
            ("Internet", 50, false, 5, "Telemóvel e internet"), ("Transportes", 125, false, 1, "Transportes"), ("Eletricidade (estimativa)", 60, true, 20, "Casa"),
        ]
        for f in fixed { s.ctx.insert(FixedExpense(name: f.0, amount: f.1, isEstimate: f.2, dayOfMonth: f.3, category: f.4)) }
    }

    static func seedTravel(_ s: DataStore) {
        let items: [ChecklistEntry] = [
            .init(category: "Documentos", text: "Passaporte / cartão de cidadão"), .init(category: "Documentos", text: "Cartão de embarque"),
            .init(category: "Documentos", text: "Seguro de viagem"), .init(category: "Higiene", text: "Escova e pasta de dentes"),
            .init(category: "Higiene", text: "Desodorizante"), .init(category: "Higiene", text: "Hidratante"),
            .init(category: "Roupa", text: "Roupa para cada dia"), .init(category: "Roupa", text: "Roupa interior e meias"),
            .init(category: "Tecnologia", text: "Carregador do telemóvel"), .init(category: "Tecnologia", text: "Adaptador de tomada"),
            .init(category: "Tecnologia", text: "Auscultadores"), .init(category: "Medicamentos", text: "Medicação habitual"),
            .init(category: "Acessórios", text: "Óculos de sol"), .init(category: "Acessórios", text: "Carteira e dinheiro"),
        ]
        let t = ChecklistTemplate(name: "Viagem padrão"); t.itemsData = Coding.encode(items)
        s.ctx.insert(t)
    }
}

struct TemplateItem: Codable, Hashable { var exercise: String; var sets: Int; var reps: Int }
struct SetLog: Codable, Hashable { var exercise: String; var set: Int; var reps: Int; var kg: Double }
struct ChecklistEntry: Codable, Hashable { var category: String; var text: String }
