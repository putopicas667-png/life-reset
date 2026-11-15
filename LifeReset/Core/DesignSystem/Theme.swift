import SwiftUI

/// Design system do LIFE RESET: escuro, minimalista, uma cor de destaque discreta.
enum Theme {
    // Superfícies (do fundo para a frente)
    static let background = Color(red: 0.055, green: 0.059, blue: 0.071)   // #0E0F12
    static let surface = Color(red: 0.090, green: 0.098, blue: 0.118)      // #17191E
    static let surfaceRaised = Color(red: 0.122, green: 0.133, blue: 0.157) // #1F2228
    static let separator = Color.white.opacity(0.07)

    // Texto
    static let textPrimary = Color(white: 0.94)
    static let textSecondary = Color(white: 0.62)
    static let textTertiary = Color(white: 0.42)

    // Destaque e estados (tons sóbrios, sem neon)
    static let accent = Color(red: 0.55, green: 0.64, blue: 0.86)   // azul acinzentado
    static let positive = Color(red: 0.45, green: 0.72, blue: 0.58)
    static let warning = Color(red: 0.86, green: 0.70, blue: 0.42)
    static let negative = Color(red: 0.86, green: 0.47, blue: 0.47)

    // Medidas
    static let radius: CGFloat = 16
    static let spacing: CGFloat = 12
    static let pagePadding: CGFloat = 16
}

extension Font {
    static let lrLargeTitle = Font.system(size: 30, weight: .bold, design: .rounded)
    static let lrTitle = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let lrHeadline = Font.system(size: 16, weight: .semibold)
    static let lrBody = Font.system(size: 15)
    static let lrCaption = Font.system(size: 12, weight: .medium)
    static let lrNumber = Font.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit()
}
