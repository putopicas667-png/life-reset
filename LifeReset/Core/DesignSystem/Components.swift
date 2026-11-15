import SwiftUI

/// Cartão base: superfície ligeiramente elevada, cantos arredondados.
struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Label {
                    Text(title).font(.lrCaption).textCase(.uppercase).tracking(0.6)
                } icon: {
                    if let systemImage { Image(systemName: systemImage) }
                }
                .foregroundStyle(Theme.textSecondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.separator, lineWidth: 1))
    }
}

/// Valor numérico com legenda (ex.: "2800 kcal / dia").
struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.lrNumber).foregroundStyle(Theme.textPrimary)
            Text(label).font(.lrCaption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Barra de progresso fina e discreta.
struct ThinProgressBar: View {
    let value: Double // 0...1
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceRaised)
                Capsule().fill(tint).frame(width: max(4, geo.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.35), value: value)
    }
}

/// Linha "rótulo …… valor".
struct KeyValueRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack {
            Text(key).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).foregroundStyle(Theme.textPrimary).monospacedDigit()
        }
        .font(.lrBody)
    }
}

/// Estado vazio honesto para separadores cujos módulos chegam numa fase posterior.
struct PlannedModuleView: View {
    let title: String
    let systemImage: String
    let phase: String
    let summary: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(summary + "\n\nPrevisto na \(phase) do plano de desenvolvimento.")
        }
        .foregroundStyle(Theme.textSecondary)
    }
}

extension View {
    /// Fundo de página padrão.
    func lrScreenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}
