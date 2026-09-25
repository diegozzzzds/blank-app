import SwiftUI

/// Horizontal chips to pick which source to show.
struct SourceFilterBar: View {
    @Binding var filter: SourceFilter
    let sources: [SourceID]
    var counts: [SourceID: Int] = [:]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "全部", isSelected: filter == .all) {
                    filter = .all
                }
                ForEach(sources, id: \.self) { source in
                    chip(title: title(for: source), isSelected: filter == .only(source)) {
                        filter = .only(source)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func title(for source: SourceID) -> String {
        if let count = counts[source], count > 0 {
            return "\(source.displayName) \(count)"
        }
        return source.displayName
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
