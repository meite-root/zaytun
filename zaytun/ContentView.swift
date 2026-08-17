import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .reflections
    @State private var didBootstrap = false
    @State private var integrityMessage: String?
    @State private var isIngestingSharedMedia = false

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
            ingestSharedMedia()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                ingestSharedMedia()
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

    private func ingestSharedMedia() {
        guard !isIngestingSharedMedia else { return }
        isIngestingSharedMedia = true
        defer { isIngestingSharedMedia = false }

        do {
            let result = try SharedMediaIngestionService.ingestPending(
                queue: try SharedImportQueue.appGroup(),
                storage: try MediaStorageService.applicationSupport(),
                in: modelContext,
                onImported: { material in
                    guard let storage = try? MediaStorageService.applicationSupport() else {
                        return
                    }
                    MediaUnderstandingService.startAutomaticImageRecognition(
                        for: material,
                        storage: storage,
                        in: modelContext
                    )
                }
            )
            for failure in result.failures {
                print("Shared media import \(failure.importID) failed: \(failure.message)")
            }
        } catch SharedImportQueueError.appGroupUnavailable {
            // The app remains usable if the capability has not yet been registered for signing.
        } catch {
            print("Shared media queue ingestion failed: \(error.localizedDescription)")
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
