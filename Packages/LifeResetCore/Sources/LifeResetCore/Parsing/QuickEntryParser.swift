import Foundation

/// Rascunho interpretado da entrada rápida — mostrado ao utilizador para confirmação.
public struct TaskDraft: Equatable, Sendable {
    public var title: String
    public var day: Date?
    public var time: TimeOfDay?
    public var category: String
    public var understood: [String]
}

/// Interpreta frases curtas em português, por exemplo "Comprar champô amanhã" ou "Pagar renda dia 1 às 18h".
/// Regras locais e simples; nunca cria a tarefa sem confirmação.
public enum QuickEntryParser {
    static let categories: [(String, [String])] = [
        ("shopping", ["comprar", "compras", "supermercado", "encomendar"]),
        ("household", ["limpar", "aspirar", "lavar", "arrumar", "lixo", "loiça", "lençóis", "toalhas", "lavandaria"]),
        ("finance", ["pagar", "transferir", "fatura", "renda", "seguro", "poupar"]),
        ("training", ["treino", "treinar", "ginásio", "correr", "flexões"]),
        ("health", ["médico", "dentista", "farmácia", "consulta", "suplemento"]),
        ("admin", ["ligar", "email", "marcar", "enviar", "renovar", "documento"]),
    ]

    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = LRCalendar.current) -> TaskDraft {
        var words = text.split(separator: " ").map(String.init)
        var understood: [String] = []
        var day: Date?
        var time: TimeOfDay?
        let today = calendar.startOfDay(for: now)

        func remove(_ i: Int, count: Int = 1) { words.removeSubrange(i..<min(words.count, i + count)) }
        func lower(_ i: Int) -> String { words[i].lowercased().trimmingCharacters(in: .punctuationCharacters) }

        var i = 0
        while i < words.count {
            let w = lower(i)
            if w == "hoje" { day = today; understood.append("hoje"); remove(i); continue }
            if w == "amanhã" || w == "amanha" { day = LRCalendar.addDays(1, to: today); understood.append("amanhã"); remove(i); continue }
            if w == "depois", i + 2 < words.count, lower(i + 1) == "de", ["amanhã", "amanha"].contains(lower(i + 2)) {
                day = LRCalendar.addDays(2, to: today); understood.append("depois de amanhã"); remove(i, count: 3); continue
            }
            if let wd = weekday(w) {
                let cur = calendar.component(.weekday, from: today)
                var delta = (wd - cur + 7) % 7
                if delta == 0 { delta = 7 }
                day = LRCalendar.addDays(delta, to: today); understood.append(LRCalendar.weekdayName(wd).lowercased())
                let hasPrefix = i > 0 && ["no", "na", "próximo", "próxima", "proximo", "proxima"].contains(lower(i - 1))
                if hasPrefix { remove(i - 1, count: 2); i -= 1 } else { remove(i) }
                continue
            }
            if w == "dia", i + 1 < words.count, let n = Int(lower(i + 1)), (1...31).contains(n) {
                var comps = calendar.dateComponents([.year, .month], from: today); comps.day = n
                if var d = calendar.date(from: comps) {
                    if d < today { d = calendar.date(byAdding: .month, value: 1, to: d) ?? d }
                    day = d; understood.append("dia \(n)")
                }
                remove(i, count: 2); continue
            }
            if (w == "às" || w == "as" || w == "pelas"), i + 1 < words.count, let t = TimeOfDay(parsing: lower(i + 1)), t.minutes < 24 * 60 {
                time = t; understood.append("às \(t.description)"); remove(i, count: 2); continue
            }
            if w.hasSuffix("h") || w.contains(":"), let t = TimeOfDay(parsing: w), t.minutes < 24 * 60, w.count <= 5 {
                time = t; understood.append("às \(t.description)"); remove(i); continue
            }
            i += 1
        }

        var title = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if title.isEmpty { title = text.trimmingCharacters(in: .whitespaces) }
        title = title.prefix(1).uppercased() + title.dropFirst()
        let lowerTitle = title.lowercased()
        let category = categories.first { $0.1.contains { lowerTitle.contains($0) } }?.0 ?? "personal"
        return TaskDraft(title: title, day: day, time: time, category: category, understood: understood)
    }

    static func weekday(_ w: String) -> Int? {
        let map: [String: Int] = ["domingo": 1, "segunda": 2, "segunda-feira": 2, "terça": 3, "terca": 3, "terça-feira": 3,
                                  "quarta": 4, "quarta-feira": 4, "quinta": 5, "quinta-feira": 5, "sexta": 6, "sexta-feira": 6,
                                  "sábado": 7, "sabado": 7]
        return map[w]
    }
}
