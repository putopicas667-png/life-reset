import SwiftUI
import SwiftData

/// Decide entre o onboarding (primeira utilização) e a navegação principal.
struct RootView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if profiles.first?.onboardingCompleted == true {
                RootTabView()
            } else {
                OnboardingView()
            }
        }
        .task { @MainActor in Maintenance.run(ctx) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Maintenance.run(ctx) } }
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

            CalendarTabView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(Tab.calendar)

            TasksView()
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(Tab.tasks)

            ProgressTabView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.progress)

            FinanceView()
                .tabItem { Label("Finance", systemImage: "francsign.circle") }
                .tag(Tab.finance)
        }
        .tint(Theme.accent)
    }
}
