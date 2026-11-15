import SwiftUI
import SwiftData
import LifeResetCore

/// Definições: editar perfil e trabalhos já guardados.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft = SetupDraft.initial
    @State private var original = SetupDraft.initial
    @State private var loaded = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            SetupForm(draft: $draft)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 4) {
                        Text("Os dados ficam guardados apenas neste iPhone.")
                        Text("LIFE RESET \(AppConfiguration.version) (\(AppConfiguration.build))")
                    }
                    .font(.lrCaption).foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Theme.background)
                }
                .navigationTitle("Definições")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Guardar", action: save).disabled(!draft.issues.isEmpty || draft == original)
                    }
                }
                .alert("Não foi possível guardar", isPresented: .constant(saveError != nil)) {
                    Button("OK") { saveError = nil }
                } message: { Text(saveError ?? "") }
                .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        let repo = ProfileRepository(context: context)
        if let p = repo.profile() {
            let jobs = repo.jobs().map(\.settings)
            draft = SetupDraft(profile: p.settings, jobs: jobs.isEmpty ? SetupDraft.initial.jobs : jobs)
            original = draft
        }
        loaded = true
    }

    private func save() {
        do {
            try ProfileRepository(context: context).save(profile: draft.profile, jobs: draft.jobs)
            original = draft
            dismiss()
        } catch { saveError = error.localizedDescription }
    }
}
