import SwiftData
import SwiftUI

struct DisciplinesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Discipline.name) private var disciplines: [Discipline]

    @State private var isAddingDiscipline = false
    @State private var disciplineToDelete: Discipline?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if disciplines.isEmpty {
                ContentUnavailableView(
                    "No Disciplines",
                    systemImage: "square.stack.3d.up",
                    description: Text("Create broad contexts for your Topics.")
                )
            } else {
                List(disciplines) { discipline in
                    NavigationLink {
                        DisciplineEditorView(discipline: discipline)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(discipline.name)
                                .font(.headline)
                            Text("\(discipline.topics.count) topic(s)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            disciplineToDelete = discipline
                        }
                    }
                }
            }
        }
        .navigationTitle("Disciplines")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingDiscipline = true
                } label: {
                    Label("New Discipline", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingDiscipline) {
            NavigationStack { NewDisciplineView() }
        }
        .confirmationDialog(
            "Delete this Discipline?",
            isPresented: Binding(
                get: { disciplineToDelete != nil },
                set: { if !$0 { disciplineToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Discipline", role: .destructive, action: deleteDiscipline)
            Button("Cancel", role: .cancel) { disciplineToDelete = nil }
        } message: {
            Text("Topics, Materials, and provenance will remain.")
        }
        .errorAlert(message: $errorMessage)
    }

    private func deleteDiscipline() {
        guard let disciplineToDelete else { return }
        do {
            modelContext.delete(disciplineToDelete)
            try modelContext.save()
            self.disciplineToDelete = nil
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct NewDisciplineView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("Discipline name", text: $name)
                .textInputAutocapitalization(.words)
        }
        .navigationTitle("New Discipline")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
        .errorAlert(message: $errorMessage)
    }

    private func save() {
        do {
            _ = try DisciplineService.create(name: name, in: modelContext)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct DisciplineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let discipline: Discipline

    @State private var name: String
    @State private var isDeleting = false
    @State private var errorMessage: String?

    init(discipline: Discipline) {
        self.discipline = discipline
        _name = State(initialValue: discipline.name)
    }

    var body: some View {
        Form {
            Section("Discipline") {
                TextField("Discipline name", text: $name)
            }

            Section("Topics") {
                if discipline.topics.isEmpty {
                    Text("No Topics assigned")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(discipline.topics.sorted { $0.title < $1.title }) { topic in
                        Text(topic.title)
                    }
                }
            }

            Section {
                Button("Delete Discipline", role: .destructive) { isDeleting = true }
            }
        }
        .navigationTitle(discipline.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
        .confirmationDialog("Delete this Discipline?", isPresented: $isDeleting) {
            Button("Delete Discipline", role: .destructive, action: deleteDiscipline)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its Topics and their Materials will remain.")
        }
        .errorAlert(message: $errorMessage)
    }

    private func save() {
        do {
            try DisciplineService.rename(discipline, to: name)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func deleteDiscipline() {
        do {
            modelContext.delete(discipline)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
