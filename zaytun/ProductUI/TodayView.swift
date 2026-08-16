import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var materials: [Material]

    @State private var session = MaterialReviewQueue()
    @State private var errorMessage: String?

    private var currentMaterial: Material? {
        guard let currentID = session.currentID else { return nil }
        return materials.first { $0.id == currentID }
    }

    var body: some View {
        Group {
            if let material = currentMaterial {
                reviewCard(material)
            } else {
                ContentUnavailableView(
                    "You’re caught up for today.",
                    systemImage: "checkmark.circle",
                    description: Text("New and returning Materials will appear here when they are due.")
                )
            }
        }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshSession)
        .errorAlert(message: $errorMessage)
    }

    private func reviewCard(_ material: Material) -> some View {
        VStack(spacing: 0) {
            Text("\(session.remainingCount) remaining")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let title = material.title?.trimmedNonempty {
                        Text(title)
                            .font(.title2.weight(.semibold))
                    }

                    if let text = material.text?.trimmedNonempty {
                        Text(text)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else if material.title?.trimmedNonempty == nil {
                        Text(material.displayTitle)
                            .font(.title2.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
            }

            HStack(spacing: 14) {
                Button(action: markAgain) {
                    Text("Again")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(action: markGood) {
                    Text("Good")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(20)
            .background(.bar)
        }
    }

    private func refreshSession() {
        let refreshedAt = Date.now
        let dueIDs = ResurfacingService.dueMaterials(
            from: materials,
            now: refreshedAt
        ).map(\.id)
        session.refresh(with: dueIDs)
    }

    private func markGood() {
        guard let material = currentMaterial else { return }
        do {
            let reviewedAt = Date.now
            try ResurfacingService.markGood(material, at: reviewedAt)
            try modelContext.save()
            session.markCurrentGood()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func markAgain() {
        guard let material = currentMaterial else { return }
        do {
            let reviewedAt = Date.now
            ResurfacingService.markAgain(material, at: reviewedAt)
            try modelContext.save()
            session.markCurrentAgain()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

struct MaterialResurfacingMenu: View {
    @Environment(\.modelContext) private var modelContext

    let material: Material

    @State private var isChoosingDate = false
    @State private var customDate = Date.now
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            Button("Due Now", systemImage: "arrow.counterclockwise") {
                performSave {
                    ResurfacingService.makeDueNow(material)
                }
            }

            Button("Schedule Date", systemImage: "calendar") {
                customDate = proposedCustomDate()
                isChoosingDate = true
            }
        } label: {
            Label("Resurface", systemImage: "clock.arrow.circlepath")
        }
        .sheet(isPresented: $isChoosingDate) {
            NavigationStack {
                Form {
                    DatePicker(
                        "Review date",
                        selection: $customDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
                .navigationTitle("Schedule Review")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isChoosingDate = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Schedule", action: scheduleCustomDate)
                    }
                }
            }
        }
        .errorAlert(message: $errorMessage)
    }

    private func scheduleCustomDate() {
        if performSave({
            ResurfacingService.schedule(material, on: customDate)
        }) {
            isChoosingDate = false
        }
    }

    private func proposedCustomDate() -> Date {
        let current = Date.now
        if let scheduled = material.nextReviewAt, scheduled > current {
            return scheduled
        }
        return Calendar.current.date(byAdding: .day, value: 1, to: current) ?? current
    }

    @discardableResult
    private func performSave(_ changes: () throws -> Void) -> Bool {
        errorMessage = nil
        do {
            try changes()
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
            return false
        }
    }
}
