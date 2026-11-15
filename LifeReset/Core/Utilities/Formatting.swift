import Foundation
import SwiftUI
import LifeResetCore

enum Fmt {
    static let locale = Locale(identifier: AppConfiguration.localeIdentifier)

    static func longDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f.string(from: date).capitalizedFirst
    }

    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f.string(from: date)
    }

    static func number(_ value: Double, decimals: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)).locale(locale))
    }

    static func liters(fromMl ml: Int) -> String {
        number(Double(ml) / 1000, decimals: ml % 1000 == 0 ? 0 : 1) + " L"
    }

    static func time(_ t: TimeOfDay) -> String { t.description }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

extension TimeOfDay {
    /// Converte para `Date` (hoje) para usar em `DatePicker`.
    var asDateToday: Date { date(on: Date()) }

    /// A partir de um `Date` escolhido num `DatePicker` (só hora e minuto).
    init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        self.init(c.hour ?? 0, c.minute ?? 0)
    }
}

extension Binding where Value == TimeOfDay {
    /// Ponte para `DatePicker(.hourAndMinute)`. Horas depois da meia-noite (ex.: 24:00) são mostradas como 00:00
    /// e, se a hora escolhida for antes das 05:00 e o valor original já era "noite", mantém-se no dia seguinte.
    var asDate: Binding<Date> {
        Binding<Date>(
            get: { wrappedValue.wrapped.asDateToday },
            set: { newValue in
                let t = TimeOfDay(date: newValue)
                wrappedValue = (wrappedValue.minutes >= 24 * 60 && t.hour < 5) ? t.adding(minutes: 24 * 60) : t
            }
        )
    }
}

extension Fmt {
    static func chf(_ v: Decimal, sign: Bool = false) -> String {
        let n = NSDecimalNumber(decimal: v).doubleValue
        let s = abs(n).formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "de_CH")))
        let prefix = n < 0 ? "−" : (sign && n > 0 ? "+" : "")
        return "\(prefix)CHF \(s)"
    }

    static func monthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return f.string(from: date).capitalizedFirst
    }
}

extension Decimal {
    var double: Double { NSDecimalNumber(decimal: self).doubleValue }
}

extension Fmt {
    static func shortMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f.string(from: date)
    }
}
