import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: AppTab = .reflections
    @State private var didBootstrap = false
    @State private var integrityMessage: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ReflectionsHomeView()
            }
            .tabItem {
                Label("Reflections", systemImage: "text.bubble")
            }
            .tag(AppTab.reflections)

            NavigationStack {
                TodayView()
            }
            .tabItem {
                Label("Today", systemImage: "sun.max")
            }
            .tag(AppTab.today)

            NavigationStack {
                InboxView()
            }
            .tabItem {
                Label("Inbox", systemImage: "tray")
            }
            .tag(AppTab.inbox)

            NavigationStack {
                OrganizeView()
            }
            .tabItem {
                Label("Organize", systemImage: "square.grid.2x2")
            }
            .tag(AppTab.organize)
        }
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            do {
                _ = try SelfPersonBootstrap.ensureSelfPerson(in: modelContext)
            } catch {
                modelContext.rollback()
                integrityMessage = error.localizedDescription
            }
            do {
                _ = try MaterialOrganizationService.reconcilePersistedStatuses(
                    in: modelContext
                )
            } catch {
                modelContext.rollback()
                if integrityMessage == nil {
                    integrityMessage = error.localizedDescription
                }
            }
            do {
                _ = try ResurfacingService.reconcileUnscheduledMaterials(
                    in: modelContext
                )
            } catch {
                modelContext.rollback()
                if integrityMessage == nil {
                    integrityMessage = error.localizedDescription
                }
            }
        }
        .alert(
            "Data Integrity Problem",
            isPresented: Binding(
                get: { integrityMessage != nil },
                set: { if !$0 { integrityMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(integrityMessage ?? "")
        }
    }
}

private enum AppTab: Hashable {
    case reflections
    case today
    case inbox
    case organize
}

#Preview {
    ContentView()
        .modelContainer(try! ZaytunPersistence.makeContainer(isStoredInMemoryOnly: true))
}
