import SwiftUI

/// Ortak kategori/grup seçici — hem M3U hem Xtream ekranları kullanır.
/// Aramalı liste, her satırda içerik sayısı chip'i. Seçimde `onSelect(id)` çağrılır.
struct CategoryPickerSheet: View {
    struct Entry: Identifiable, Equatable {
        let id: String
        let name: String
        let count: Int
    }

    let title: String
    let entries: [Entry]
    let onSelect: (String) -> Void

    @ObservedObject private var locale = LocalizationManager.shared

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private var filtered: [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter { CatalogTextSearch.matches(search: q, text: $0.name) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        L("category_picker.not_found.title"),
                        systemImage: "magnifyingglass",
                        description: Text(L("category_picker.not_found.message"))
                    )
                } else {
                    List(filtered) { entry in
                        Button {
                            onSelect(entry.id)
                        } label: {
                            HStack {
                                Text(entry.name)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(entry.count)")
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: L("category_picker.search_placeholder")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
