import SwiftUI

// MARK: - Diff View

/// Shows file-level differences between hub and agent versions of a skill.
/// Implements side-by-side content diff view matching the Stitch design.
struct DiffView: View {
    let skill: SkillInfo
    @ObservedObject var model: SkillSyncViewModel

    @State private var selectedAgent: String
    @State private var fileDiffs: [DiffEngine.FileDiff] = []
    @State private var selectedFile: DiffEngine.FileDiff?
    @State private var isLoading = true

    @Environment(\.dismiss) private var dismiss
    private let ds = DesignSystem.self

    init(skill: SkillInfo, model: SkillSyncViewModel) {
        self.skill = skill
        self.model = model
        let firstWithState = skill.states.first { $0.value != .notFound && $0.value != .error }
        _selectedAgent = State(initialValue: firstWithState?.key ?? model.agents.first?.label ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            diffHeader

            Divider().overlay(ds.Colors.borderSubtle)

            if isLoading {
                ProgressView("计算差异中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if fileDiffs.isEmpty {
                noDiffView
            } else if let file = selectedFile {
                contentDiffView(file: file)
            } else {
                fileListView
            }

            // Footer
            if !isLoading {
                Divider().overlay(ds.Colors.borderSubtle)
                diffFooter
            }
        }
        .frame(minWidth: 800, minHeight: 550)
        .background(ds.Colors.background)
        .preferredColorScheme(.dark)
        .onAppear(perform: computeDiff)
        .onChange(of: selectedAgent) { _ in computeDiff() }
    }

    // MARK: - Header

    private var diffHeader: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(ds.Colors.primary)

            VStack(alignment: .leading, spacing: 1) {
                Text("差异对比: \(skill.name)")
                    .font(ds.Typography.headlineMD)
                    .foregroundColor(ds.Colors.textPrimary)
                if let file = selectedFile {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                            .foregroundColor(ds.Colors.textSecondary)
                        Text(skill.name)
                            .font(.system(size: 11))
                            .foregroundColor(ds.Colors.textSecondary)
                        Text("/")
                            .foregroundColor(ds.Colors.outline)
                        Text(file.relativePath)
                            .font(.system(size: 11))
                            .foregroundColor(ds.Colors.textPrimary)
                    }
                }
            }

            Spacer()

            if selectedFile != nil {
                Button(action: { selectedFile = nil }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12))
                    Text("Back to File List")
                        .font(.system(size: 12))
                }
                .foregroundColor(ds.Colors.textSecondary)
                .buttonStyle(.plain)
            }

            Picker("对比目标", selection: $selectedAgent) {
                ForEach(model.agents) { agent in
                    Text(agent.label).tag(agent.label)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - No Diff

    private var noDiffView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(ds.Colors.statusSynced)
            Text("内容完全一致")
                .font(ds.Typography.headlineMD)
                .foregroundColor(ds.Colors.textPrimary)
            Text("hub 与 \(selectedAgent) 端的 \(skill.name) 无差异")
                .font(ds.Typography.bodySM)
                .foregroundColor(ds.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ds.Colors.surfaceContainer)
    }

    // MARK: - File List View

    private var fileListView: some View {
        List(fileDiffs) { diff in
            HStack(spacing: 12) {
                Image(systemName: diffIcon(for: diff.type))
                    .font(.system(size: 14))
                    .foregroundColor(diffColor(for: diff.type))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(diff.relativePath)
                        .font(ds.Typography.codeSM)
                        .foregroundColor(ds.Colors.textPrimary)
                    Text(diff.description)
                        .font(ds.Typography.bodySM)
                        .foregroundColor(ds.Colors.textSecondary)
                }

                Spacer()

                Text(diff.type.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(diffColor(for: diff.type))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(diffColor(for: diff.type).opacity(0.1))
                    .cornerRadius(4)

                if diff.type == .different {
                    Text("\(diff.hunks.reduce(0) { $0 + $1.lines.filter { $0.type != .context }.count }) changes")
                        .font(.system(size: 10))
                        .foregroundColor(ds.Colors.textSecondary)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedFile = diff
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Content Diff View (Side-by-Side)

    private func contentDiffView(file: DiffEngine.FileDiff) -> some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(ds.Colors.statusStale).frame(width: 6, height: 6)
                    Text("HUB SOURCE (LOCAL)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ds.Colors.textSecondary)
                    Text(hubModTime(for: file.relativePath))
                        .font(.system(size: 10))
                        .foregroundColor(ds.Colors.textSecondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(ds.Colors.surfaceContainer)

                Rectangle()
                    .fill(ds.Colors.borderSubtle)
                    .frame(width: 1)

                HStack(spacing: 8) {
                    Circle().fill(ds.Colors.primary).frame(width: 6, height: 6)
                    Text("\(selectedAgent.uppercased()) AGENT (INSTALLED)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ds.Colors.textSecondary)
                    Text(agentModTime(for: file.relativePath))
                        .font(.system(size: 10))
                        .foregroundColor(ds.Colors.textSecondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(ds.Colors.surfaceContainer)
            }

            Divider().overlay(ds.Colors.borderSubtle)

            // Diff content
            ScrollView([.vertical, .horizontal]) {
                if file.hunks.isEmpty {
                    // Simple file-level diff for non-text or missing files
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(file.relativePath)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(ds.Colors.textPrimary)
                            Spacer()
                        }
                        .padding(12)
                        Text("Binary or non-text file — cannot show content diff.")
                            .font(ds.Typography.bodySM)
                            .foregroundColor(ds.Colors.textSecondary)
                            .padding(.horizontal, 12)
                    }
                    .padding(.vertical, 20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(file.hunks.enumerated()), id: \.element.id) { hunkIdx, hunk in
                            // Hunk header
                            Text(hunk.header)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(ds.Colors.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(ds.Colors.primary.opacity(0.08))
                                .padding(.top, hunkIdx == 0 ? 0 : 4)

                            // Hunk lines
                            ForEach(Array(hunk.lines.enumerated()), id: \.element.id) { _, line in
                                HStack(spacing: 0) {
                                    // Left side
                                    diffLineCell(
                                        text: line.type == .added ? "" : line.content,
                                        lineNum: line.oldLineNumber.map(String.init) ?? "",
                                        type: line.type == .removed ? .removed : .context,
                                        side: .left
                                    )

                                    Rectangle()
                                        .fill(ds.Colors.borderSubtle)
                                        .frame(width: 1)

                                    // Right side
                                    diffLineCell(
                                        text: line.type == .removed ? "" : line.content,
                                        lineNum: line.newLineNumber.map(String.init) ?? "",
                                        type: line.type == .added ? .added : .context,
                                        side: .right
                                    )
                                }
                                .frame(minHeight: 22)
                            }
                        }
                    }
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Button("Keep Current") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Spacer()

                Button(action: {
                    if let agent = model.agents.first(where: { $0.label == selectedAgent }) {
                        model.syncSkill(skill.name, to: agent, mode: .copy)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            computeDiff()
                        }
                    }
                }) {
                    Label("Sync Overwrite", systemImage: "arrow.triangle.swap")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(ds.Colors.actionPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(ds.Colors.surfaceContainer)
        }
    }

    private enum DiffSide { case left, right }

    private func diffLineCell(text: String, lineNum: String, type: DiffEngine.DiffLine.LineType, side: DiffSide) -> some View {
        let bgColor: Color = {
            switch type {
            case .added:   return ds.Colors.statusSynced.opacity(0.08)
            case .removed: return ds.Colors.statusError.opacity(0.08)
            case .context: return .clear
            case .header:  return .clear
            }
        }()

        let prefix: String = {
            switch (type, side) {
            case (.added, .right): return "+"
            case (.removed, .left): return "-"
            default: return " "
            }
        }()

        let linePrefixColor: Color = {
            switch type {
            case .added:   return side == .right ? ds.Colors.statusSynced : .clear
            case .removed: return side == .left ? ds.Colors.statusError : .clear
            default: return .clear
            }
        }()

        return HStack(spacing: 8) {
            // Line number
            Text(lineNum)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(ds.Colors.textSecondary.opacity(0.5))
                .frame(width: 36, alignment: .trailing)

            // Changemarker (+, -, or space)
            Text(prefix)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(linePrefixColor)
                .frame(width: 10)

            // Content
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(ds.Colors.textPrimary)
                .lineLimit(nil)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bgColor)
    }

    // MARK: - Footer

    private var diffFooter: some View {
        HStack(spacing: 12) {
            if let file = selectedFile {
                Text("\(file.relativePath): \(file.hunks.count) hunks")
                    .font(ds.Typography.bodySM)
                    .foregroundColor(ds.Colors.textSecondary)
            } else {
                Text("共 \(fileDiffs.count) 处差异")
                    .font(ds.Typography.bodySM)
                    .foregroundColor(ds.Colors.textSecondary)
            }

            Spacer()

            Button("关闭") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func findAgentPath() -> String {
        guard let agent = model.agents.first(where: { $0.label == selectedAgent })
                ?? model.agents.first else {
            // If no agents are configured, return a fallback path based on
            // the agent manager's skill-path logic with an empty agent.
            // This is defensive: the DiffView sheet shouldn't be openable
            // when there are no agents, but guard against it anyway.
            return ""
        }
        return model.agentManager.skillPath(for: skill.name, agent: agent)
    }

    private func hubModTime(for relativePath: String) -> String {
        let full = (skill.hubPath as NSString).appendingPathComponent(relativePath)
        return modTimeString(path: full)
    }

    private func agentModTime(for relativePath: String) -> String {
        let full = (findAgentPath() as NSString).appendingPathComponent(relativePath)
        return modTimeString(path: full)
    }

    private func modTimeString(path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date else {
            return "-"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func computeDiff() {
        isLoading = true

        let engine = model.diffEngine
        let mgr = model.agentManager
        let currentAgents = model.agents
        let currentSelectedAgent = selectedAgent
        let currentSkill = skill

        DispatchQueue.global(qos: .userInitiated).async {
            let agentPath = mgr.skillPath(
                for: currentSkill.name,
                agent: currentAgents.first(where: { $0.label == currentSelectedAgent }) ?? currentAgents[0]
            )

            let result = engine.diff(
                skillName: currentSkill.name,
                hubPath: currentSkill.hubPath,
                agentPath: agentPath
            )

            DispatchQueue.main.async {
                fileDiffs = result
                selectedFile = nil
                isLoading = false
            }
        }
    }

    private func diffIcon(for type: DiffEngine.DiffType) -> String {
        switch type {
        case .onlyInHub:   return "arrow.right.to.line"
        case .onlyInAgent: return "arrow.left.to.line"
        case .different:   return "arrow.triangle.swap"
        case .identical:   return "checkmark"
        }
    }

    private func diffColor(for type: DiffEngine.DiffType) -> Color {
        switch type {
        case .onlyInHub:   return ds.Colors.statusStale
        case .onlyInAgent: return ds.Colors.primary
        case .different:   return ds.Colors.statusError
        case .identical:   return ds.Colors.statusSynced
        }
    }
}
