import Foundation

/// Resumo do dia partilhado entre a app e os widgets (só leitura nos widgets).
struct WidgetSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable, Hashable {
        var start: Date
        var end: Date
        var title: String
        var isTask: Bool
    }
    struct Priority: Codable, Equatable, Hashable {
        var title: String
        var done: Bool
    }

    var generatedAt: Date
    var dayTitle: String
    var items: [Item]
    var priorities: [Priority]
    var done: Int
    var total: Int
    var leaveHome: Date?
    var level: Int
    var xpToday: Int
    var warning: String?

    static let empty = WidgetSnapshot(generatedAt: .distantPast, dayTitle: "Abre a app", items: [], priorities: [], done: 0, total: 0,
                                      leaveHome: nil, level: 1, xpToday: 0, warning: nil)

    /// Próximo item ainda não terminado num instante.
    func next(at date: Date) -> Item? { items.first { $0.end > date } }

    var isStale: Bool { !Calendar.current.isDateInToday(generatedAt) }
}

enum SharedStore {
    static let fileName = "widget-snapshot.json"
    static let baseGroup = "group.com.lifereset.app"

    /// O sideload (AltStore/SideStore) pode acrescentar um sufixo ao identificador; tenta as variantes possíveis.
    static var containerURL: URL? {
        var candidates: [String] = []
        if let id = Bundle.main.bundleIdentifier {
            let appID = id.hasSuffix(".widgets") ? String(id.dropLast(".widgets".count)) : id
            candidates.append("group." + appID)
        }
        candidates.append(baseGroup)
        for c in candidates {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: c) { return url }
        }
        return nil
    }

    static func write(_ s: WidgetSnapshot) {
        guard let url = containerURL?.appendingPathComponent(fileName) else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        if let data = try? enc.encode(s) { try? data.write(to: url, options: [.atomic]) }
    }

    static func read() -> WidgetSnapshot {
        guard let url = containerURL?.appendingPathComponent(fileName), let data = try? Data(contentsOf: url) else { return .empty }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return (try? dec.decode(WidgetSnapshot.self, from: data)) ?? .empty
    }
}
