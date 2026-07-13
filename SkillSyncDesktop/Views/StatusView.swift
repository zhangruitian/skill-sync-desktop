#if DEBUG
import SwiftUI

// MARK: - Status View (preview-only, for design reference)

/// Alternate status-table view originally designed as a sidebar.
/// Kept for design reference and SwiftUI preview exploration only;
/// the live app uses the inline hubSkillsView in ContentView.
struct StatusView: View {
    @ObservedObject var model: SkillSyncViewModel
    let onRefresh: () -> Void

    @State private var showDiffForSkill: SkillInfo?

    private let ds = DesignSystem.self

    var body: some View {
        VStack(spacing: 0) {
            if model.isScanning {
                ProgressView("Scanning hub directory...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.skills.isEmpty {
                emptyState
            } else {
                skillTable
            }
        }
        .background(ds.Colors.background)
        .sheet(item: $showDiffForSkill) { skill in
            DiffView(skill: skill, model: model)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 36))
                .foregroundColor(ds.Colors.textSecondary)
            Text("No Skills Found")
                .font(ds.Typography.headlineMD)
                .foregroundColor(ds.Colors.textPrimary)
            Text("Configure your hub directory in Settings to scan for skills.")
                .font(ds.Typography.bodySM)
                .foregroundColor(ds.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var skillTable: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    Text("SKILL NAME")
                        .font(ds.Typography.labelCaps)
                        .foregroundColor(ds.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(model.agents.filter { $0.exists }) { agent in
                        Text(agent.label.uppercased())
                            .font(ds.Typography.labelCaps)
                            .foregroundColor(ds.Colors.textSecondary)
                            .frame(width: 100, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider().overlay(ds.Colors.borderSubtle)

                ForEach(model.skills) { skill in
                    HStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 12))
                                .foregroundColor(ds.Colors.outline)
                            Text(skill.name)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(ds.Colors.textPrimary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 7)

                        ForEach(model.agents.filter { $0.exists }) { agent in
                            StatusBadge(state: skill.states[agent.label] ?? .notFound)
                                .frame(width: 100, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                    .onTapGesture { showDiffForSkill = skill }
                    .contextMenu {
                        ForEach(model.agents) { agent in
                            Button("Sync (Link)") {
                                model.syncSkill(skill.name, to: agent, mode: .link)
                            }
                            Button("Sync (Copy)") {
                                model.syncSkill(skill.name, to: agent, mode: .copy)
                            }
                            Divider()
                            Button("Remove from \(agent.label)") {
                                model.unlinkSkill(skill.name, from: agent)
                            }
                        }
                    }

                    if skill.id != model.skills.last?.id {
                        Divider()
                            .overlay(ds.Colors.borderSubtle)
                            .opacity(0.5)
                            .padding(.leading, 12)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
#endif
