import SwiftUI
import SwiftData
import LifeResetCore

/// Primeira configuração: mostra os valores iniciais conhecidos para o utilizador confirmar ou editar.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var draft = SetupDraft.initial
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            SetupForm(draft: $draft)
                .safeAreaInset(edge: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LIFE RESET").font(.lrLargeTitle)
                        Text("Confirma os teus valores de partida. Podes alterá-los a qualquer momento nas definições.")
                            .font(.lrBody).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.pagePadding)
                    .background(Theme.background)
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Começar", action: save).disabled(!draft.issues.isEmpty)
                    }
                }
                .alert("Não foi possível guardar", isPresented: .constant(saveError != nil)) {
                    Button("OK") { saveError = nil }
                } message: { Text(saveError ?? "") }
        }
    }

    private func save() {
        do { try ProfileRepository(context: context).save(profile: draft.profile, jobs: draft.jobs) }
        catch { saveError = error.localizedDescription }
    }
}
