import SwiftUI

enum Theme {
    // MARK: - Dimensions
    static let cornerRadius: CGFloat = 10
    static let spacing: CGFloat = 12
    static let cardPadding: CGFloat = 16

    // MARK: - Typography
    static let largeTitle = Font.largeTitle.bold()
    static let title = Font.title2.bold()
    static let headline = Font.headline
    static let body = Font.body
    static let callout = Font.callout
    static let caption = Font.caption
    static let mono = Font.system(.body, design: .monospaced)
    static let monoLarge = Font.system(.title, design: .monospaced).bold()
    static let monoCaption = Font.system(.caption, design: .monospaced)

    // MARK: - Status Colors
    static let success = Color.green
    static let failure = Color.red
    static let warning = Color.orange
    static let active = Color.blue
    static let idle = Color.secondary
}

// MARK: - Card Style

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.cardPadding)
            #if os(macOS)
            .background(.background.secondary)
            #else
            .background(.ultraThinMaterial)
            #endif
            .cornerRadius(Theme.cornerRadius)
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}

// MARK: - Stat Card

struct StatCard: View {
    let icon: String
    let value: String
    let title: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold().monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .cardStyle()
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            Text(title)
                .font(Theme.headline)
            Text(message)
                .font(Theme.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
