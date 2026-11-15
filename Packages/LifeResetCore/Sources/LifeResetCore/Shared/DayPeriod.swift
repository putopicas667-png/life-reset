import Foundation

/// Período do dia usado para adaptar o ecrã principal (manhã, tarde, noite).
public enum DayPeriod: String, Sendable, CaseIterable {
    case night, morning, afternoon, evening

    public static func at(_ time: TimeOfDay) -> DayPeriod {
        switch time.wrapped.hour {
        case 5..<12: return .morning
        case 12..<19: return .afternoon
        case 19..<24: return .evening
        default: return .night
        }
    }

    public var greeting: String {
        switch self {
        case .morning: return "Bom dia"
        case .afternoon: return "Boa tarde"
        case .evening, .night: return "Boa noite"
        }
    }
}
