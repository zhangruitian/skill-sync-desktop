import SwiftUI

// MARK: - Settings View (Terminal Catalyst style, 3-layer tab structure)

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onHubChanged: () -> Void

    // Layer 1
    @State private var topTab: String = "general"

    // Layer 2 (General sub-tabs)
    @State private var generalSubTab: String = "paths"

    // Form state
    @State private var hubPathInput: String
    @State private var newAgentLabel = ""
    @State private var newAgentPath = ""
    @State private var showResetAlert = false

    @Environment(\.dismiss) private var dismiss
    private let ds = DesignSystem.self

    init(settings: AppSettings, onHubChanged: @escaping () -> Void) {
        self.settings = settings
        self.onHubChanged = onHubChanged
        _hubPathInput = State(initialValue: settings.hubRootPath)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Settings")
                    .font(ds.Typography.headlineMD)
                    .foregroundColor(ds.Colors.textPrimary)

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ds.Colors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(ds.Colors.surfaceHigh)
                .cornerRadius(ds.Shapes.small)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(ds.Colors.background)

            Divider().overlay(ds.Colors.borderSubtle)

            // Layer 1: Top tab bar
            topTabBar

            Divider().overlay(ds.Colors.borderSubtle)

            // Content
            switch topTab {
            case "general":
                generalSheetContent
            case "configuration":
                configurationSheetContent
            case "network":
                networkSheetContent
            default:
                generalSheetContent
            }
        }
        .frame(width: 560, height: 480)
        .background(ds.Colors.background)
        .preferredColorScheme(.dark)
    }

    // MARK: — Top Tab Bar

    private var topTabBar: some View {
        HStack(spacing: 0) {
            sheetTabButton("General", icon: "gearshape", tag: "general")
            sheetTabButton("Configuration", icon: "slider.horizontal.3", tag: "configuration")
            sheetTabButton("Network", icon: "network", tag: "network")
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func sheetTabButton(_ label: String, icon: String, tag: String) -> some View {
        Button(action: { topTab = tag }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 11, weight: topTab == tag ? .semibold : .regular))
            }
            .foregroundColor(topTab == tag ? ds.Colors.primary : ds.Colors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(topTab == tag ? ds.Colors.primary.opacity(0.1) : Color.clear)
            .cornerRadius(ds.Shapes.medium)
        }
        .buttonStyle(.plain)
    }

    // MARK: — General Tab (with sub-tabs)

    private var generalSheetContent: some View {
        HStack(spacing: 0) {
            // Sub-tab sidebar
            VStack(alignment: .leading, spacing: 0) {
                sheetSubButton("Paths & Agents", icon: "folder.badge.gearshape", tag: "paths")
                sheetSubButton("Sync Rules", icon: "arrow.triangle.swap", tag: "syncRules")
                sheetSubButton("Advanced", icon: "ellipsis.curlybraces", tag: "advanced")
                Spacer()
            }
            .frame(width: 170)
            .background(ds.Colors.surface.opacity(0.5))

            Divider().overlay(ds.Colors.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch generalSubTab {
                    case "paths":
                        pathsContent
                    case "syncRules":
                        syncRulesContent
                    case "advanced":
                        advancedContent
                    default:
                        pathsContent
                    }
                }
                .padding(14)
            }
        }
    }

    private func sheetSubButton(_ label: String, icon: String, tag: String) -> some View {
        Button(action: { generalSubTab = tag }) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundColor(generalSubTab == tag ? ds.Colors.textPrimary : ds.Colors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(generalSubTab == tag ? ds.Colors.primaryContainer.opacity(0.2) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: — Shared content groups (used by both sheet and inline)

    @ViewBuilder
    private var pathsContent: some View {
        Group {
            sectionHeader("Hub Path")
            Text("The primary local directory where central agent skills are stored.")
                .font(.system(size: 11)).foregroundColor(ds.Colors.textSecondary)

            Text("LOCAL DIRECTORY")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(ds.Colors.textSecondary.opacity(0.7))

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11)).foregroundColor(ds.Colors.outline)
                TextField("", text: $hubPathInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(6)
                    .background(ds.Colors.surfaceContainer)
                    .cornerRadius(ds.Shapes.small)
                    .overlay(RoundedRectangle(cornerRadius: ds.Shapes.small).stroke(ds.Colors.borderSubtle, lineWidth: 1))

                Button("Choose...") { browseForHub() }
                    .font(.system(size: 10))
                    .foregroundColor(ds.Colors.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(ds.Colors.surfaceHigh)
                    .cornerRadius(ds.Shapes.small)
                    .buttonStyle(.plain)

                Button("Apply") {
                    settings.hubRootPath = hubPathInput
                    onHubChanged()
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(ds.Colors.actionPrimary)
                .cornerRadius(ds.Shapes.small)
                .buttonStyle(.plain)
            }

            sectionHeader("Agent Platforms")
            Text("External platform directories that synchronize with the Hub.")
                .font(.system(size: 11)).foregroundColor(ds.Colors.textSecondary)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("PLATFORM NAME").font(ds.Typography.labelCaps).foregroundColor(ds.Colors.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                    Text("TARGET PATH").font(ds.Typography.labelCaps).foregroundColor(ds.Colors.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                    Text("").font(ds.Typography.labelCaps).frame(width: 40)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)

                Divider().overlay(ds.Colors.borderSubtle)

                ForEach(Array(settings.agents.enumerated()), id: \.offset) { index, agent in
                    HStack(spacing: 0) {
                        HStack(spacing: 5) {
                            Circle().fill(agent.exists ? ds.Colors.statusSynced : ds.Colors.outline).frame(width: 5, height: 5)
                            Text(agent.label).font(.system(size: 11, weight: .medium)).foregroundColor(ds.Colors.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(agent.path).font(.system(size: 10, design: .monospaced)).foregroundColor(ds.Colors.textSecondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                        Button(action: { settings.agents.remove(at: index) }) {
                            Image(systemName: "trash").font(.system(size: 10)).foregroundColor(ds.Colors.statusError)
                        }
                        .buttonStyle(.plain).frame(width: 40)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    if index < settings.agents.count - 1 {
                        Divider().overlay(ds.Colors.borderSubtle).opacity(0.3).padding(.leading, 10)
                    }
                }
            }
            .background(ds.Colors.surfaceContainer).cornerRadius(ds.Shapes.medium)

            HStack(spacing: 6) {
                TextField("Platform Name", text: $newAgentLabel)
                    .textFieldStyle(.plain).font(.system(size: 11)).padding(5)
                    .background(ds.Colors.surfaceContainer).cornerRadius(ds.Shapes.small)
                    .overlay(RoundedRectangle(cornerRadius: ds.Shapes.small).stroke(ds.Colors.borderSubtle, lineWidth: 1))

                TextField("Target Path", text: $newAgentPath)
                    .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced)).padding(5)
                    .background(ds.Colors.surfaceContainer).cornerRadius(ds.Shapes.small)
                    .overlay(RoundedRectangle(cornerRadius: ds.Shapes.small).stroke(ds.Colors.borderSubtle, lineWidth: 1))

                Button("Add") {
                    let l = newAgentLabel.trimmingCharacters(in: .whitespaces)
                    let p = newAgentPath.trimmingCharacters(in: .whitespaces)
                    if !l.isEmpty && !p.isEmpty {
                        settings.agents.append(AgentConfig(label: l, path: p))
                        newAgentLabel = ""; newAgentPath = ""
                    }
                }
                .font(.system(size: 10, weight: .medium)).foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(ds.Colors.actionPrimary).cornerRadius(ds.Shapes.small).buttonStyle(.plain)
            }

            sectionHeader("Default Install Mode")
            Picker("", selection: $settings.defaultInstallMode) {
                Text("Link (Dev)").tag(InstallMode.link)
                Text("Copy (Stable)").tag(InstallMode.copy)
            }
            .pickerStyle(.segmented).frame(width: 180)

            sectionHeader("Auto-backup")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-backup before sync").font(.system(size: 11, weight: .medium)).foregroundColor(ds.Colors.textPrimary)
                    Text("Archive targets before applying Hub changes.").font(.system(size: 10)).foregroundColor(ds.Colors.textSecondary)
                }
                Spacer()
                Toggle("", isOn: $settings.autoBackup).toggleStyle(.switch)
            }
        }
    }

    @ViewBuilder
    private var syncRulesContent: some View {
        Group {
            sectionHeader("Sync Ignore Patterns")
            Text("Specify files and directories to exclude during synchronization.")
                .font(.system(size: 11)).foregroundColor(ds.Colors.textSecondary)

            TextEditor(text: Binding(
                get: { settings.ignoreGlobs.joined(separator: "\n") },
                set: { settings.ignoreGlobs = $0.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            ))
            .font(.system(size: 11, design: .monospaced))
            .frame(height: 100).padding(6)
            .background(ds.Colors.surfaceContainer).cornerRadius(ds.Shapes.medium)
            .overlay(RoundedRectangle(cornerRadius: ds.Shapes.medium).stroke(ds.Colors.borderSubtle, lineWidth: 1))
            .scrollContentBackground(.hidden)

            Text("Standard glob patterns supported.")
                .font(.system(size: 10)).foregroundColor(ds.Colors.textSecondary).padding(.leading, 2)

            sectionHeader("Hub Scan Excludes (Regex)")
            Text("Regex patterns applied to directory names in the hub root.")
                .font(.system(size: 11)).foregroundColor(ds.Colors.textSecondary)

            TextEditor(text: Binding(
                get: { settings.excludePatterns.joined(separator: "\n") },
                set: { settings.excludePatterns = $0.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            ))
            .font(.system(size: 11, design: .monospaced))
            .frame(height: 80).padding(6)
            .background(ds.Colors.surfaceContainer).cornerRadius(ds.Shapes.medium)
            .overlay(RoundedRectangle(cornerRadius: ds.Shapes.medium).stroke(ds.Colors.borderSubtle, lineWidth: 1))
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var advancedContent: some View {
        Group {
            sectionHeader("Hub Profiles")
            VStack(spacing: 0) {
                ForEach(Array(settings.hubProfiles.enumerated()), id: \.element.id) { index, profile in
                    HStack(spacing: 8) {
                        Text(profile.name).font(.system(size: 11, weight: .medium)).foregroundColor(ds.Colors.textPrimary)
                        Text(profile.path).font(.system(size: 10, design: .monospaced)).foregroundColor(ds.Colors.textSecondary).lineLimit(1)
                        Spacer()
                        Button(action: { settings.hubProfiles.remove(at: index) }) {
                            Image(systemName: "trash").font(.system(size: 10)).foregroundColor(ds.Colors.statusError)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    if index < settings.hubProfiles.count - 1 {
                        Divider().overlay(ds.Colors.borderSubtle).opacity(0.3).padding(.leading, 24)
                    }
                }
            }
            .background(ds.Colors.surfaceContainer).cornerRadius(ds.Shapes.medium)

            sectionHeader("Reset")
            Button("Reset to Defaults") { showResetAlert = true }
                .font(.system(size: 10, weight: .medium)).foregroundColor(ds.Colors.statusError)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(ds.Colors.surfaceHigh).cornerRadius(ds.Shapes.small).buttonStyle(.plain)
                .alert("Reset Settings?", isPresented: $showResetAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        settings.hubRootPath = { let h = NSHomeDirectory(); return (h as NSString).appendingPathComponent("skill-hub") }()
                        settings.agents = [
                            AgentConfig(label: "claude", path: "~/.claude/skills"),
                            AgentConfig(label: "codex", path: "~/.codex/skills"),
                            AgentConfig(label: "agents", path: "~/.agents/skills"),
                        ]
                        settings.defaultInstallMode = .link; settings.autoBackup = true
                        settings.ignoreGlobs = [".git", ".gitattributes", ".DS_Store", "LICENSE", "README.md", "CHANGELOG.md", "docs", "agents", ".github", ".vscode", ".idea"]
                        settings.excludePatterns = ["^docs$", "^scripts$", "^backup-", "\\.backup-", "^\\..*", "^node_modules$"]
                        hubPathInput = settings.hubRootPath
                        onHubChanged()
                    }
                } message: { Text("This will restore all settings to their defaults.") }

            sectionHeader("About")
            VStack(alignment: .leading, spacing: 4) {
                Text("SkillHubDesktop v1.0").font(ds.Typography.headlineMD).foregroundColor(ds.Colors.textPrimary)
                Text("macOS native desktop application for managing AI agent skills. Sync, diff, and monitor skills across Claude Code, Codex CLI, OpenAI Agents SDK, and custom agent directories.")
                    .font(.system(size: 11)).foregroundColor(ds.Colors.textSecondary).lineLimit(nil)
            }
        }
    }

    // MARK: — Configuration Tab

    private var configurationSheetContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Sync Configuration")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Default Install Mode").font(.system(size: 11, weight: .medium)).foregroundColor(ds.Colors.textPrimary)
                    Picker("", selection: $settings.defaultInstallMode) {
                        Text("Link (Dev)").tag(InstallMode.link)
                        Text("Copy (Stable)").tag(InstallMode.copy)
                    }
                    .pickerStyle(.segmented).frame(width: 180)
                    Text("Link: symlinks follow hub changes. Copy: independent snapshots.")
                        .font(.system(size: 10)).foregroundColor(ds.Colors.textSecondary)
                }

                HStack {
                    Text("Auto-backup before sync").font(.system(size: 11, weight: .medium)).foregroundColor(ds.Colors.textPrimary)
                    Spacer()
                    Toggle("", isOn: $settings.autoBackup).toggleStyle(.switch)
                }

                sectionHeader("Ignore Patterns")
                TextEditor(text: Binding(
                    get: { settings.ignoreGlobs.joined(separator: "\n") },
                    set: { settings.ignoreGlobs = $0.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                ))
                .font(.system(size: 11, design: .monospaced)).frame(height: 100).padding(6)
                .background(ds.Colors.surfaceContainer).cornerRadius(ds.Shapes.medium)
                .overlay(RoundedRectangle(cornerRadius: ds.Shapes.medium).stroke(ds.Colors.borderSubtle, lineWidth: 1))
                .scrollContentBackground(.hidden)
            }
            .padding(14)
        }
    }

    // MARK: — Network Tab

    private var networkSheetContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Agent Platforms")
                Text("External platform directories that synchronize with the Hub.")
                    .font(.system(size: 11)).foregroundColor(ds.Colors.textSecondary)

                VStack(spacing: 0) {
                    ForEach(Array(settings.agents.enumerated()), id: \.offset) { index, agent in
                        HStack(spacing: 10) {
                            Circle().fill(agent.exists ? ds.Colors.statusSynced : ds.Colors.outline).frame(width: 5, height: 5)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(agent.label).font(.system(size: 11, weight: .medium)).foregroundColor(ds.Colors.textPrimary)
                                Text(agent.path).font(.system(size: 10, design: .monospaced)).foregroundColor(ds.Colors.textSecondary).lineLimit(1)
                            }
                            Spacer()
                            if agent.exists {
                                Text("Connected").font(.system(size: 10)).foregroundColor(ds.Colors.statusSynced).padding(.horizontal, 5).padding(.vertical, 1).background(ds.Colors.statusSynced.opacity(0.1)).cornerRadius(3)
                            } else {
                                Text("Missing").font(.system(size: 10)).foregroundColor(ds.Colors.statusStale).padding(.horizontal, 5).padding(.vertical, 1).background(ds.Colors.statusStale.opacity(0.1)).cornerRadius(3)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        if index < settings.agents.count - 1 {
                            Divider().overlay(ds.Colors.borderSubtle).opacity(0.3).padding(.leading, 10)
                        }
                    }
                }
                .background(ds.Colors.surfaceContainer).cornerRadius(ds.Shapes.medium)

                sectionHeader("Add Platform")
                HStack(spacing: 6) {
                    TextField("Name", text: $newAgentLabel).textFieldStyle(.plain).font(.system(size: 11)).padding(5).background(ds.Colors.surfaceContainer).cornerRadius(ds.Shapes.small).overlay(RoundedRectangle(cornerRadius: ds.Shapes.small).stroke(ds.Colors.borderSubtle, lineWidth: 1))
                    TextField("Path", text: $newAgentPath).textFieldStyle(.plain).font(.system(size: 11, design: .monospaced)).padding(5).background(ds.Colors.surfaceContainer).cornerRadius(ds.Shapes.small).overlay(RoundedRectangle(cornerRadius: ds.Shapes.small).stroke(ds.Colors.borderSubtle, lineWidth: 1))
                    Button("Add") {
                        let l = newAgentLabel.trimmingCharacters(in: .whitespaces)
                        let p = newAgentPath.trimmingCharacters(in: .whitespaces)
                        if !l.isEmpty && !p.isEmpty {
                            settings.agents.append(AgentConfig(label: l, path: p))
                            newAgentLabel = ""; newAgentPath = ""
                        }
                    }
                    .font(.system(size: 10, weight: .medium)).foregroundColor(.white).padding(.horizontal, 10).padding(.vertical, 5).background(ds.Colors.actionPrimary).cornerRadius(ds.Shapes.small).buttonStyle(.plain)
                }
            }
            .padding(14)
        }
    }

    // MARK: — Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(ds.Typography.labelCaps)
            .foregroundColor(ds.Colors.textSecondary)
            .padding(.top, 4)
    }

    private func browseForHub() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Hub Directory"
        if panel.runModal() == .OK {
            hubPathInput = panel.url?.path ?? hubPathInput
        }
    }
}

// MARK: — Preview

#Preview {
    SettingsView(settings: AppSettings.shared, onHubChanged: {})
}
