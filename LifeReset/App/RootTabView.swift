import SwiftUI
import SwiftData

/// Decide entre o onboarding (primeira utilização) e a navegação principal.
struct RootView: View {
    @Query private var profiles: [UserProfile]

    var body: some View {
        if profiles.first?.onboardingCompleted == true {
            RootTabView()
        } else {
            OnboardingView()
        }
    }
}

/// Navegação principal: cinco separadores.
struct RootTabView: View {
    enum Tab: Hashable { case home, calendar, tasks, progress, finance }
    @State private var selection: Tab = .home

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Tab.home)

            NavigationStack {
                PlannedModuleView(title: "Calendar", systemImage: "calendar", phase: "Fase 6",
                                  summary: "Vistas de dia, semana e mês com turnos, folgas, tarefas, treinos, refeições, férias e voos.")
                    .navigationTitle("Calendar")
            }
            .lrScreenBackground()
            .tabItem { Label("Calendar", systemImage: "calendar") }
            .tag(Tab.calendar)

            NavigationStack {
                PlannedModuleView(title: "Tasks", systemImage: "checklist", phase: "Fase 2",
                                  summary: "Tarefas fixas e flexíveis, recorrências, três prioridades diárias, higiene e casa.")
                    .navigationTitle("Tasks")
            }
            .lrScreenBackground()
            .tabItem { Label("Tasks", systemImage: "checklist") }
            .tag(Tab.tasks)

            NavigationStack {
                PlannedModuleView(title: "Progress", systemImage: "chart.line.uptrend.xyaxis", phase: "Fase 5",
                                  summary: "XP, níveis, atributos, objetivos, conquistas, sequências e estatísticas.")
                    .navigationTitle("Progress")
            }
            .lrScreenBackground()
            .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(Tab.progress)

            NavigationStack {
                PlannedModuleView(title: "Finance", systemImage: "francsign.circle", phase: "Fase 4",
                                  summary: "Rendimentos, despesas, dívidas, poupanças, orçamentos e previsão do mês em CHF.")
                    .navigationTitle("Finance")
            }
            .lrScreenBackground()
            .tabItem { Label("Finance", systemImage: "francsign.circle") }
            .tag(Tab.finance)
        }
        .tint(Theme.accent)
    }
}
