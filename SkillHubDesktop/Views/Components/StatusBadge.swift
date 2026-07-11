import SwiftUI

// MARK: - Status Badge (Terminal Catalyst style)

/// Status chip in the "dot + label" pattern from the Stitch design system.
/// A small colored circle followed by a text label in the matching color.
struct StatusBadge: View {
    let state: SyncState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)

            Text(labelFor(state))
                .font(DesignSystem.Typography.bodySM)
                .fontWeight(.medium)
                .foregroundColor(labelColor)
        }
    }

    // MARK: - Dot color

    private var dotColor: Color {
        switch state {
        case .link:      return DesignSystem.Colors.statusSynced
        case .copy:      return DesignSystem.Colors.statusSynced
        case .linkStale: return DesignSystem.Colors.statusStale
        case .outdated:  return DesignSystem.Colors.statusStale
        case .notFound:  return DesignSystem.Colors.outline
        case .error:     return DesignSystem.Colors.statusError
        }
    }

    // MARK: - Label color

    private var labelColor: Color {
        switch state {
        case .link:      return DesignSystem.Colors.statusSynced
        case .copy:      return DesignSystem.Colors.statusSynced
        case .linkStale: return DesignSystem.Colors.statusStale
        case .outdated:  return DesignSystem.Colors.statusStale
        case .notFound:  return DesignSystem.Colors.textSecondary
        case .error:     return DesignSystem.Colors.statusError
        }
    }

    // MARK: - Label text (matches Stitch labels)

    private func labelFor(_ state: SyncState) -> String {
        switch state {
        case .link:      return "Synced"
        case .copy:      return "Copied"
        case .linkStale: return "Stale"
        case .outdated:  return "Outdated"
        case .notFound:  return "Unlinked"
        case .error:     return "Error"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        ForEach(SyncState.allCases, id: \.self) { state in
            StatusBadge(state: state)
        }
    }
    .padding()
    .background(DesignSystem.Colors.background)
}
