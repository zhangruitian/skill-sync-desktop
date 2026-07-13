#if DEBUG
import SwiftUI

// MARK: - Skill Row (preview-only, for design reference)

/// A sidebar row showing a skill name and its overall sync status.
/// Kept for design reference and SwiftUI preview exploration only;
/// the live app uses the inline hubSkillsTable in ContentView.
struct SkillRow: View {
    let skill: SkillInfo
    let isSelected: Bool
    let onSelect: () -> Void
    private let ds = DesignSystem.self

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundColor(skill.isFullySynced ? ds.Colors.statusSynced : ds.Colors.statusStale)

                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                        .font(ds.Typography.bodyMD)
                        .foregroundColor(ds.Colors.textPrimary)
                        .lineLimit(1)

                    if let date = skill.lastModified {
                        Text(date, style: .relative)
                            .font(ds.Typography.bodySM)
                            .foregroundColor(ds.Colors.textSecondary)
                    }
                }

                Spacer()

                // Overall sync indicator
                Circle()
                    .fill(skill.isFullySynced ? ds.Colors.statusSynced : ds.Colors.statusStale)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected
                ? ds.Colors.primaryContainer.opacity(0.25)
                : Color.clear
        )
        .cornerRadius(5)
        .padding(.horizontal, 6)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        SkillRow(
            skill: SkillInfo(
                name: "my-skill",
                hubPath: "/tmp/my-skill",
                states: ["claude": .link, "codex": .copy],
                staleDetails: [:],
                lastModified: Date()
            ),
            isSelected: true,
            onSelect: {}
        )
        SkillRow(
            skill: SkillInfo(
                name: "old-skill",
                hubPath: "/tmp/old-skill",
                states: ["claude": .outdated, "codex": .notFound],
                staleDetails: [:],
                lastModified: Date().addingTimeInterval(-86400)
            ),
            isSelected: false,
            onSelect: {}
        )
    }
    .frame(width: 200)
    .padding(.vertical, 8)
    .background(DesignSystem.Colors.background)
}
#endif
