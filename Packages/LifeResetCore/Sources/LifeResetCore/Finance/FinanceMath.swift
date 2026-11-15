import Foundation

/// Previsão do fim do mês (é sempre uma estimativa e é apresentada como tal).
public struct MonthForecast: Equatable, Sendable {
    public let incomeSoFar: Decimal
    public let spentSoFar: Decimal
    public let fixedPending: Decimal
    public let variableProjection: Decimal
    public let expectedIncomePending: Decimal
    /// Saldo previsto no fim do mês = rendimentos (+ previstos) − gastos − fixas por pagar − projeção variável.
    public var endBalance: Decimal { incomeSoFar + expectedIncomePending - spentSoFar - fixedPending - variableProjection }
}

public enum FinanceMath {
    public struct FixedItem: Sendable {
        public let amount: Decimal
        public let dayOfMonth: Int
        public let paid: Bool
        public init(amount: Decimal, dayOfMonth: Int, paid: Bool) { self.amount = amount; self.dayOfMonth = dayOfMonth; self.paid = paid }
    }

    /// - Parameters:
    ///   - variableSpent: gastos não fixos até hoje neste mês.
    ///   - day/daysInMonth: dia atual e número de dias do mês.
    public static func forecast(income: Decimal, spent: Decimal, variableSpent: Decimal, fixed: [FixedItem],
                                expectedIncomePending: Decimal = 0, day: Int, daysInMonth: Int) -> MonthForecast {
        let pending = fixed.filter { !$0.paid }.reduce(Decimal(0)) { $0 + $1.amount }
        let d = max(1, min(day, daysInMonth))
        let dailyVariable = variableSpent / Decimal(d)
        let projection = dailyVariable * Decimal(daysInMonth - d)
        return MonthForecast(incomeSoFar: income, spentSoFar: spent, fixedPending: pending,
                             variableProjection: round(projection), expectedIncomePending: expectedIncomePending)
    }

    public static func round(_ v: Decimal, scale: Int = 2) -> Decimal {
        var input = v, out = Decimal()
        NSDecimalRound(&out, &input, scale, .plain)
        return out
    }

    /// Marcos de poupança atingidos (25/50/75/100 %).
    public static func milestonesReached(saved: Decimal, target: Decimal) -> Int {
        guard target > 0 else { return 0 }
        let ratio = ((saved / target) as NSDecimalNumber).doubleValue
        return [0.25, 0.5, 0.75, 1.0].filter { ratio >= $0 }.count
    }

    /// Dívida restante (nunca negativa).
    public static func remaining(initial: Decimal, payments: [Decimal]) -> Decimal {
        max(0, initial - payments.reduce(0, +))
    }

    /// Converte texto em valor ("12,50", "1'234.50", "-8.90 CHF").
    public static func parseAmount(_ text: String) -> Decimal? {
        var s = text.replacingOccurrences(of: "CHF", with: "").replacingOccurrences(of: "Fr.", with: "")
            .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00A0}", with: "")
        guard !s.isEmpty else { return nil }
        if s.contains(",") && s.contains(".") {
            // o último separador é o decimal
            if s.lastIndex(of: ",")! > s.lastIndex(of: ".")! { s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
            else { s = s.replacingOccurrences(of: ",", with: "") }
        } else {
            s = s.replacingOccurrences(of: ",", with: ".")
        }
        return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// Importação de extratos em CSV (exportados do banco pelo utilizador — a app nunca acede ao banco).
public enum CSVImport {
    public struct Row: Equatable, Sendable {
        public let date: Date
        public let amount: Decimal
        public let description: String
        /// Identificador estável para não importar a mesma linha duas vezes.
        public var hash: String { "\(Int(date.timeIntervalSince1970))|\(amount)|\(description.lowercased())" }
    }

    public struct Result: Sendable {
        public let rows: [Row]
        public let skipped: Int
    }

    public static func parse(_ text: String, calendar: Calendar = LRCalendar.current) -> Result {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = lines.first else { return Result(rows: [], skipped: 0) }
        let delimiter: Character = first.filter { $0 == ";" }.count >= first.filter { $0 == "," }.count ? ";" : ","
        var rows: [Row] = [], skipped = 0
        var dateCol: Int?, amountCol: Int?, descCol: Int?, debitCol: Int?, creditCol: Int?

        for (i, line) in lines.enumerated() {
            let cols = split(line, by: delimiter)
            if i == 0 {
                let lower = cols.map { $0.lowercased() }
                dateCol = lower.firstIndex { $0.contains("dat") }
                amountCol = lower.firstIndex { $0.contains("montante") || $0.contains("amount") || $0.contains("betrag") || $0.contains("valor") }
                debitCol = lower.firstIndex { $0.contains("débito") || $0.contains("debito") || $0.contains("debit") || $0.contains("belastung") }
                creditCol = lower.firstIndex { $0.contains("crédito") || $0.contains("credito") || $0.contains("credit") || $0.contains("gutschrift") }
                descCol = lower.firstIndex { $0.contains("desc") || $0.contains("text") || $0.contains("buchung") || $0.contains("movimento") }
                if dateCol != nil { continue } // linha de cabeçalho
            }
            let dc = dateCol ?? 0
            guard dc < cols.count, let date = parseDate(cols[dc], calendar: calendar) else { skipped += 1; continue }
            var amount: Decimal?
            if let a = amountCol, a < cols.count { amount = FinanceMath.parseAmount(cols[a]) }
            if amount == nil, let d = debitCol, d < cols.count, let v = FinanceMath.parseAmount(cols[d]), v != 0 { amount = -abs(v) }
            if amount == nil, let c = creditCol, c < cols.count, let v = FinanceMath.parseAmount(cols[c]), v != 0 { amount = abs(v) }
            if amount == nil, amountCol == nil, debitCol == nil {
                amount = cols.enumerated().filter { $0.offset != dc }.compactMap { FinanceMath.parseAmount($0.element) }.first
            }
            guard let value = amount else { skipped += 1; continue }
            let desc: String
            if let d = descCol, d < cols.count { desc = cols[d] }
            else { desc = cols.enumerated().filter { $0.offset != dc && FinanceMath.parseAmount($0.element) == nil }.map(\.element).first ?? "" }
            rows.append(Row(date: date, amount: value, description: desc.trimmingCharacters(in: .whitespaces)))
        }
        return Result(rows: rows, skipped: skipped)
    }

    static func split(_ line: String, by d: Character) -> [String] {
        var out: [String] = [], cur = "", quoted = false
        for ch in line {
            if ch == "\"" { quoted.toggle(); continue }
            if ch == d && !quoted { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" } else { cur.append(ch) }
        }
        out.append(cur.trimmingCharacters(in: .whitespaces))
        return out
    }

    static func parseDate(_ s: String, calendar: Calendar) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        for f in ["dd.MM.yyyy", "dd/MM/yyyy", "yyyy-MM-dd", "dd-MM-yyyy", "dd.MM.yy"] {
            let df = DateFormatter()
            df.calendar = calendar; df.timeZone = calendar.timeZone
            df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = f; df.isLenient = false
            if let d = df.date(from: t) { return calendar.startOfDay(for: d) }
        }
        return nil
    }

    /// Categoria sugerida a partir da descrição (o utilizador pode alterar antes de importar).
    public static func suggestCategory(_ description: String) -> String {
        let d = description.lowercased()
        let rules: [(String, [String])] = [
            ("Alimentação", ["migros", "coop", "lidl", "aldi", "denner", "spar", "volg"]),
            ("Restaurantes", ["mcdonald", "burger", "restaurant", "pizza", "kebab", "café", "cafe", "starbucks"]),
            ("Transportes", ["sbb", "cff", "tpg", "tl ", "zvv", "uber", "bus", "parking"]),
            ("Telemóvel e internet", ["swisscom", "salt", "sunrise", "wingo", "yallo"]),
            ("Saúde", ["pharm", "apotheke", "farm", "assura", "css", "helsana", "groupe mutuel", "médecin", "arzt"]),
            ("Higiene", ["manor", "müller", "muller", "dm ", "douglas", "sephora"]),
            ("Lazer", ["netflix", "spotify", "steam", "playstation", "cinema", "kino"]),
            ("Roupa", ["zara", "h&m", "uniqlo", "zalando", "nike", "adidas"]),
            ("Casa", ["ikea", "loyer", "miete", "renda", "romande energie", "ewz", "sig "]),
        ]
        for (cat, keys) in rules where keys.contains(where: { d.contains($0) }) { return cat }
        return "Outros"
    }
}
