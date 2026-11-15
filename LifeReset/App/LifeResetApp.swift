import SwiftUI
import LifeResetCore

/// Ponto de entrada da app.
/// Fase 0: apenas confirma que o projeto, o pacote Core e o build compilam.
/// A navegação (5 separadores), o design system e a persistência chegam na Fase 1.
@main
struct LifeResetApp: App {
    var body: some Scene {
        WindowGroup {
            BuildCheckView()
                .preferredColorScheme(.dark)
        }
    }
}

/// Ecrã técnico temporário da Fase 0 (sem botões nem ações).
struct BuildCheckView: View {
    private let now = Date()

    var body: some View {
        VStack(spacing: 12) {
            Text("LIFE RESET")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Fase 0 · estrutura do projeto")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Core: \(TimeOfDay(9, 20).description) → \(TimeOfDay(10, 30).description)")
                .font(.footnote.monospaced())
                .foregroundStyle(.tertiary)
            Text("Versão \(AppConfiguration.version) (\(AppConfiguration.build))")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
    }
}
