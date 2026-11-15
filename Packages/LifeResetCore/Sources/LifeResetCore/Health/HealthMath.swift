import Foundation

/// Regras simples de treino: progressão de carga e contagem semanal.
public enum TrainingRules {
    public struct SetResult: Sendable {
        public let reps: Int
        public let kg: Double
        public init(reps: Int, kg: Double) { self.reps = reps; self.kg = kg }
    }

    /// Se todas as séries atingiram as repetições alvo, sugere +2,5 kg (barra) ou +1 kg (halteres leves); senão mantém.
    public static func suggestedKg(last: [SetResult], targetReps: Int) -> Double? {
        guard !last.isEmpty else { return nil }
        let kg = last.map(\.kg).max() ?? 0
        guard last.allSatisfy({ $0.reps >= targetReps }) else { return kg }
        if kg == 0 { return 0 }
        return kg + (kg >= 20 ? 2.5 : 1)
    }

    /// Volume total (repetições × kg).
    public static func volume(_ sets: [SetResult]) -> Double { sets.reduce(0) { $0 + Double($1.reps) * $1.kg } }
}

/// Sugestão de receitas a partir da despensa.
public enum RecipeMatcher {
    public struct Match: Sendable, Equatable {
        public let name: String
        public let have: [String]
        public let missing: [String]
        public var ratio: Double { have.isEmpty && missing.isEmpty ? 0 : Double(have.count) / Double(have.count + missing.count) }
    }

    public static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_PT")).trimmingCharacters(in: .whitespaces)
    }

    /// Um ingrediente conta como disponível se algum item da despensa o contém (ou vice-versa).
    public static func match(recipe: String, ingredients: [String], pantry: [String]) -> Match {
        let p = pantry.map(normalize)
        var have: [String] = [], missing: [String] = []
        for i in ingredients {
            let n = normalize(i)
            if p.contains(where: { $0.contains(n) || n.contains($0) }) { have.append(i) } else { missing.append(i) }
        }
        return Match(name: recipe, have: have, missing: missing)
    }

    public static func rank(_ recipes: [(name: String, ingredients: [String])], pantry: [String]) -> [Match] {
        recipes.map { match(recipe: $0.name, ingredients: $0.ingredients, pantry: pantry) }
            .sorted { ($0.ratio, -$0.missing.count) > ($1.ratio, -$1.missing.count) }
    }
}

/// Peso: média móvel e tendência semanal.
public enum WeightMath {
    public static func movingAverage(_ values: [Double], window: Int = 7) -> [Double] {
        guard window > 0 else { return values }
        return values.indices.map { i in
            let s = max(0, i - window + 1)
            let slice = values[s...i]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    /// kg por semana entre o primeiro e o último registo (nil com menos de 2 registos ou < 1 dia).
    public static func weeklyTrend(_ entries: [(date: Date, kg: Double)]) -> Double? {
        let sorted = entries.sorted { $0.date < $1.date }
        guard let f = sorted.first, let l = sorted.last else { return nil }
        let days = l.date.timeIntervalSince(f.date) / 86_400
        guard days >= 1 else { return nil }
        return (l.kg - f.kg) / days * 7
    }
}
