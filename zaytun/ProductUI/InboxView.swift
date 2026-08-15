import SwiftData
import SwiftUI

struct InboxView: View {
    @Query(
        filter: #Predicate<Material> { $0.statusRawValue == "inbox" },
        sort: \Material.capturedAt,
        order: .reverse
    ) private var materials: [Material]

    @State private var captureMode: MaterialCaptureMode?

    var body: some View {
        Group {
            if materials.isEmpty {
                ContentUnavailableView {
                    Label("Inbox is clear", systemImage: "tray")
                } description: {
                    Text("Capture something worth returning to.")
                } actions: {
                    Button("Quick Note") { captureMode = .quick }
                        .buttonStyle(.borderedProminent)
                }
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
        .navigationTitle("Inbox")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    SearchView()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                MaterialCaptureMenu(captureMode: $captureMode)

                Button {
                    captureMode = .quick
                } label: {
                    Label("Quick Note", systemImage: "square.and.pencil")
                }
            }
        }
        .sheet(item: $captureMode) { mode in
            NavigationStack {
                MaterialCaptureSheetContent(mode: mode)
            }
        }
    }
}

enum MaterialCaptureMode: String, Identifiable {
    case quick
    case full

    var id: String { rawValue }
}

struct MaterialCaptureMenu: View {
    @Binding var captureMode: MaterialCaptureMode?

    var body: some View {
        Menu {
            Button {
                captureMode = .quick
            } label: {
                Label("Quick Note", systemImage: "bolt")
            }
            Button {
                captureMode = .full
            } label: {
                Label("Full Note", systemImage: "list.bullet.rectangle")
            }
        } label: {
            Label("Capture", systemImage: "plus")
        }
    }
}

struct MaterialCaptureSheetContent: View {
    let mode: MaterialCaptureMode

    var body: some View {
        switch mode {
        case .quick:
            QuickNoteCaptureView()
        case .full:
            FullNoteCaptureView()
        }
    }
}

struct ProductMaterialRow: View {
    let material: Material

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(material.displayTitle)
                .font(.headline)
                .lineLimit(2)

            if material.title?.trimmedNonempty != nil,
               let text = material.text?.trimmedNonempty {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let source = material.source?.trimmedNonempty {
                Label(source, systemImage: "arrow.down.to.line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if !material.topics.isEmpty {
                    Text(material.topics.map(\.title).sorted().joined(separator: " · "))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(material.capturedAt, style: .relative)
                    .fixedSize()
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
    }
}
