import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var didBootstrap = false
    @State private var integrityMessage: String?

    var body: some View {
        NavigationStack {
            MaterialsListView()
        }
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            do {
                _ = try SelfPersonBootstrap.ensureSelfPerson(in: modelContext)
            } catch {
                integrityMessage = error.localizedDescription
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

#Preview {
    ContentView()
        .modelContainer(try! ZaytunPersistence.makeContainer(isStoredInMemoryOnly: true))
}
