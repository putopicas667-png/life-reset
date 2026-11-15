import Foundation

/// Constantes globais da app.
enum AppConfiguration {
    static let appGroup = "group.com.lifereset.app"
    static let currencyCode = "CHF"
    static let localeIdentifier = "pt_PT"

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
}
