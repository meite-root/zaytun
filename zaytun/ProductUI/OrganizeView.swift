import SwiftData
import SwiftUI

struct OrganizeView: View {
    var body: some View {
        List {
            Section("Library") {
                NavigationLink {
                    OrganizedMaterialsView()
                } label: {
                    Label("Organized Materials", systemImage: "books.vertical")
                }
            }

            Section("Intellectual Structure") {
                NavigationLink {
                    TopicsView()
                } label: {
                    Label("Topics", systemImage: "point.3.connected.trianglepath.dotted")
                }
                NavigationLink {
                    DisciplinesView()
                } label: {
                    Label("Disciplines", systemImage: "square.stack.3d.up")
                }
            }

            Section("Find & Context") {
                NavigationLink {
                    SearchView()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                NavigationLink {
                    PeopleView()
                } label: {
                    Label("People", systemImage: "person.2")
                }
            }

            #if DEBUG
            Section("Development") {
                NavigationLink {
                    MaterialsListView()
                } label: {
                    Label("Stage A Test Harness", systemImage: "wrench.and.screwdriver")
                }
            }
            #endif
        }
        .navigationTitle("Organize")
    }
}

struct OrganizedMaterialsView: View {
    @Query(
        filter: #Predicate<Material> { $0.statusRawValue == "organized" },
        sort: \Material.updatedAt,
        order: .reverse
    ) private var materials: [Material]

    var body: some View {
        Group {
            if materials.isEmpty {
                ContentUnavailableView(
                    "No Organized Materials",
                    systemImage: "books.vertical",
                    description: Text("Materials you process from Inbox will remain here.")
                )
            } else {
                List(materials) { material in
                    NavigationLink {
                        MaterialDetailView(material: material)
                    } label: {
                        ProductMaterialRow(material: material)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Organized")
    }
}
