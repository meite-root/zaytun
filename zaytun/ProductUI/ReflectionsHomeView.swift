import SwiftData
import SwiftUI

struct ReflectionsHomeView: View {
    @Query private var reflections: [Reflection]
    @State private var isCreatingReflection = false

    private var orderedReflections: [Reflection] {
        ReflectionService.allReflectionsRecentFirst(reflections)
    }

    var body: some View {
        Group {
            if orderedReflections.isEmpty {
                ContentUnavailableView(
                    "No Reflections yet",
                    systemImage: "text.bubble",
                    description: Text(
                        "Reflections are your thoughts, questions, and syntheses about what you collect."
                    )
                )
            } else {
                List(orderedReflections) { reflection in
                    NavigationLink {
                        ReflectionDetailView(reflection: reflection)
                    } label: {
                        ReflectionRow(reflection: reflection)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Reflections")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    SearchView()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreatingReflection = true
                } label: {
                    Label("New Reflection", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreatingReflection) {
            NavigationStack {
                ReflectionEditorView()
            }
        }
    }
}
