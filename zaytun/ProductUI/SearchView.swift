import SwiftData
import SwiftUI

struct SearchView: View {
    @Query(sort: \Material.capturedAt, order: .reverse) private var materials: [Material]
    @Query(sort: \Person.createdAt) private var people: [Person]
    @Query(sort: \Topic.title) private var topics: [Topic]

    @State private var query = ""

    private var results: ZaytunSearchResults {
        SearchService.search(
            query: query,
            materials: materials,
            people: people,
            topics: topics
        )
    }

    var body: some View {
        Group {
            if query.trimmedNonempty == nil {
                ContentUnavailableView(
                    "Search Zaytun",
                    systemImage: "magnifyingglass",
                    description: Text("Find People, Topics, and Materials.")
                )
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List {
                    if !results.people.isEmpty {
                        Section("People") {
                            ForEach(results.people) { person in
                                NavigationLink {
                                    PersonDetailView(person: person)
                                } label: {
                                    PersonListRow(person: person)
                                }
                            }
                        }
                    }

                    if !results.topics.isEmpty {
                        Section("Topics") {
                            ForEach(results.topics) { topic in
                                NavigationLink {
                                    TopicEditorView(topic: topic)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(topic.title)
                                            .font(.headline)
                                        Text(topic.materials.count == 1 ? "1 Material" : "\(topic.materials.count) Materials")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    if !results.materials.isEmpty {
                        Section("Materials") {
                            ForEach(results.materials) { result in
                                NavigationLink {
                                    MaterialDetailView(material: result.material)
                                } label: {
                                    SearchMaterialRow(result: result)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "People, Topics, or Materials")
    }
}

private struct SearchMaterialRow: View {
    let result: MaterialSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(result.material.displayTitle)
                .font(.headline)
                .lineLimit(2)

            if result.material.title?.trimmedNonempty != nil,
               let text = result.material.text?.trimmedNonempty {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let provenance = result.provenanceSummary {
                Text(provenance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if let source = result.material.source?.trimmedNonempty {
                Text(source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !result.material.topics.isEmpty {
                Text(result.material.topics.map(\.title).sorted().joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}
