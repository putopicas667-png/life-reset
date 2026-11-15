import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import LifeResetCore

/// Definições: perfil e trabalhos, notificações, refeições, cópia de segurança.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { ProfileSettingsView() } label: { Label("Perfil e trabalhos", systemImage: "person.crop.circle") }
                    NavigationLink { NotificationSettingsView() } label: { Label("Notificações", systemImage: "bell") }
                    NavigationLink { MealSettingsView() } label: { Label("Refeições", systemImage: "fork.knife") }
                    NavigationLink { LeisureView() } label: { Label("Tempo livre e ecrã", systemImage: "hourglass") }
                }
                Section {
                    NavigationLink { BackupView() } label: { Label("Cópia de segurança", systemImage: "lock.doc") }
                } footer: { Text("Os dados ficam guardados apenas neste iPhone. Faz uma cópia cifrada de vez em quando.") }
                Section("Sobre") {
                    KeyValueRow(key: "Versão", value: "\(AppConfiguration.version) (\(AppConfiguration.build))")
                    Text("Sideload com Apple ID gratuito: renova a assinatura no SideStore/AltStore a cada 7 dias. Os dados mantêm-se ao renovar.")
                        .font(.lrCaption).foregroundStyle(Theme.textSecondary)
                }
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("Definições").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
        }
    }
}

/// Editar perfil e trabalhos já guardados.
struct ProfileSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft = SetupDraft.initial
    @State private var original = SetupDraft.initial
    @State private var loaded = false
    @State private var saveError: String?

    var body: some View {
        SetupForm(draft: $draft)
            .navigationTitle("Perfil e trabalhos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save).disabled(!draft.issues.isEmpty || draft == original)
                }
            }
            .alert("Não foi possível guardar", isPresented: .constant(saveError != nil)) {
                Button("OK") { saveError = nil }
            } message: { Text(saveError ?? "") }
            .onAppear(perform: load)
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
            DataStore(ctx: context).save()
            dismiss()
        } catch { saveError = error.localizedDescription }
    }
}

struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var ctx
    @State private var prefs = NotificationPrefs()
    @State private var loaded = false
    @State private var denied = false

    var body: some View {
        Form {
            Section {
                Toggle("Ativar notificações", isOn: Binding(get: { prefs.enabled }, set: { v in
                    if v {
                        Task { @MainActor in
                            let ok = await NotificationService.shared.requestAuthorization()
                            prefs.enabled = ok; denied = !ok; persist()
                        }
                    } else { prefs.enabled = false; persist() }
                }))
                if denied {
                    Text("As notificações estão bloqueadas. Ativa-as em Definições do iPhone › LIFE RESET › Notificações.")
                        .font(.lrCaption).foregroundStyle(Theme.warning)
                }
            } footer: { Text("Agendadas para as próximas 48 horas e atualizadas sempre que alteras o plano.") }
            if prefs.enabled {
                Section("Tipos") {
                    Toggle("Tarefas com notificação", isOn: bind(\.tasks))
                    Toggle("Hora de sair de casa (15 min antes)", isOn: bind(\.leaveHome))
                    Toggle("Resumo da manhã", isOn: bind(\.morning))
                    Toggle("Resumo da noite e dia seguinte", isOn: bind(\.evening))
                    Toggle("Pagamentos fixos", isOn: bind(\.finance))
                    Toggle("Lembretes de viagem", isOn: bind(\.travel))
                }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("Notificações").navigationBarTitleDisplayMode(.inline)
        .onAppear { if !loaded { prefs = NotificationPrefs(store: DataStore(ctx: ctx)); loaded = true } }
    }

    private func bind(_ kp: WritableKeyPath<NotificationPrefs, Bool>) -> Binding<Bool> {
        Binding(get: { prefs[keyPath: kp] }, set: { prefs[keyPath: kp] = $0; persist() })
    }

    private func persist() { prefs.save(DataStore(ctx: ctx)) }
}

struct MealSettingsView: View {
    @Environment(\.modelContext) private var ctx
    @State private var placement = BurgerDinnerPlacement.atHome

    var body: some View {
        Form {
            Section {
                Picker("Jantar nos dias de hambúrgueres", selection: $placement) {
                    ForEach(BurgerDinnerPlacement.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } footer: { Text("Define onde aparece o jantar no plano dos dias em que trabalhas até tarde.") }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("Refeições").navigationBarTitleDisplayMode(.inline)
        .onAppear { placement = DataStore(ctx: ctx).burgerDinner }
        .onChange(of: placement) { _, v in let s = DataStore(ctx: ctx); s.setMeta("pref.burgerDinner", v.rawValue); s.save() }
    }
}

struct BackupView: View {
    @Environment(\.modelContext) private var ctx
    @State private var password = ""
    @State private var confirm = ""
    @State private var includePhotos = true
    @State private var exported: URL?
    @State private var restorePassword = ""
    @State private var picking = false
    @State private var message: String?
    @State private var error: String?
    @State private var working = false

    var body: some View {
        Form {
            Section {
                SecureField("Palavra-passe (mín. 8 caracteres)", text: $password)
                SecureField("Repetir", text: $confirm)
                Toggle("Incluir fotos de progresso", isOn: $includePhotos)
                Button(working ? "A cifrar…" : "Criar cópia cifrada") { export() }
                    .disabled(password.count < 8 || password != confirm || working)
                if let exported {
                    ShareLink(item: exported) { Label("Guardar ou partilhar o ficheiro", systemImage: "square.and.arrow.up") }
                }
            } header: { Text("Exportar") } footer: {
                Text("Sem a palavra-passe não é possível recuperar a cópia. Guarda o ficheiro em Ficheiros ou no iCloud Drive.")
            }
            Section {
                SecureField("Palavra-passe da cópia", text: $restorePassword)
                Button("Escolher ficheiro e restaurar") { picking = true }.disabled(restorePassword.isEmpty)
            } header: { Text("Restaurar") } footer: {
                Text("O restauro substitui todos os dados atuais. Depois de preparado, fecha a app (desliza para cima no seletor de apps) e volta a abri-la.")
            }
            if let message { Section { Text(message).foregroundStyle(Theme.positive) } }
            if let error { Section { Text(error).foregroundStyle(Theme.negative) } }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("Cópia de segurança").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data, .item]) { result in
            guard case .success(let url) = result else { return }
            do {
                let n = try Backup.prepareRestore(from: url, password: restorePassword)
                message = "Cópia válida (\(n) ficheiros). Fecha e volta a abrir a app para concluir o restauro."; error = nil
            } catch let e { error = e.localizedDescription; message = nil }
        }
    }

    private func export() {
        working = true
        defer { working = false }
        do {
            exported = try Backup.export(password: password, includePhotos: includePhotos, context: ctx)
            message = "Cópia criada. Toca em \"Guardar ou partilhar\"."; error = nil
        } catch let e { error = e.localizedDescription }
    }
}
