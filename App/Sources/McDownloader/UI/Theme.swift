import SwiftUI

/// Central place for the handful of visual decisions the app makes, so the
/// "one accent" rule (DESIGN.md §5) is enforced in code, not repeated by hand.
enum Theme {
    /// The single accent: the live progress of the one thing that is running.
    static let accent = Color(nsColor: .controlAccentColor)

    /// Neutral state tints. Kept few and semantic.
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)

    static func tint(for state: TransferState) -> Color {
        switch state {
        case .downloading, .connecting, .seeding, .queued: return accent
        case .completed: return Color(nsColor: .secondaryLabelColor)
        case .paused: return Color(nsColor: .secondaryLabelColor)
        case .error: return warning
        }
    }

    static func symbol(for transfer: Transfer) -> String {
        switch transfer.state {
        case .completed: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        case .paused: return "pause.circle"
        default:
            return transfer.kind == .torrent
                ? "point.3.connected.trianglepath.dotted"
                : "arrow.down.circle"
        }
    }
}

/// A small badge showing a state as icon + text (never colour alone).
struct StateBadge: View {
    var transfer: Transfer

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: Theme.symbol(for: transfer))
            Text(transfer.state.label)
        }
        .font(.caption)
        .foregroundStyle(Theme.tint(for: transfer))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(transfer.name), \(transfer.state.label)")
    }
}
