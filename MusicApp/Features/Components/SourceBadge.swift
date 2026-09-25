import SwiftUI

struct SourceBadge: View {
    let source: SourceID
    var isPreview = false

    var body: some View {
        Text(isPreview ? "试听" : source.shortName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
            .accessibilityLabel(isPreview ? "30 秒试听" : "来源：\(source.displayName)")
    }

    private var color: Color {
        switch source {
        case .itunes: return .pink
        case .openverse: return .blue
        case .internetArchive: return .brown
        case .jamendo: return .orange
        case .local: return .green
        }
    }
}

struct LicenseBadge: View {
    let license: LicenseInfo

    var body: some View {
        Text(license.displayName)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .foregroundStyle(license.isNonCommercial ? Color.orange : Color.secondary)
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.5))
            .accessibilityLabel("授权：\(license.displayName)")
    }
}
