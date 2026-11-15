import SwiftUI
import SwiftData
import UIKit

/// Ponto de entrada: abre a base de dados local e mostra o onboarding ou a navegação principal.
@main
struct LifeResetApp: App {
    private let containerResult: Result<ModelContainer, Error>

    init() {
        containerResult = Result { try Persistence.makeContainer() }
        if case .success(let c) = containerResult { NotificationService.shared.configure(container: c) }
        configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch containerResult {
                case .success(let container):
                    RootView().modelContainer(container)
                case .failure(let error):
                    StorageErrorView(error: error)
                }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
        }
    }

    private func configureAppearance() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Theme.surface)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.background)
        nav.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }
}

/// Mostrado só se a base de dados não abrir (nunca apaga dados automaticamente).
struct StorageErrorView: View {
    let error: Error

    var body: some View {
        ContentUnavailableView {
            Label("Não foi possível abrir os dados", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Os teus dados não foram apagados. Fecha e volta a abrir a app; se o problema continuar, envia esta mensagem ao programador:\n\n\(error.localizedDescription)")
        }
        .lrScreenBackground()
    }
}
