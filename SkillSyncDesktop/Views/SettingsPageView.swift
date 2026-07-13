import SwiftUI

// MARK: - Settings Page View (inline content, 3-layer tab structure)

/// Settings page with a clean tab structure:
///   General: Paths & Agents | Sync Rules | Advanced
struct SettingsPageView: View {
    @ObservedObject var settings: AppSettings
    let onHubChanged: () -> Void

    @State private var generalSubTab: String = "paths"

    // Form state
    @State private var hubPathInput: String
    @State private var newAgentLabel = ""
    @State private var newAgentPath = ""
    @State private var showResetAlert = false

    private let ds = DesignSystem.self

    init(settings: AppSettings, onHubChanged: @escaping () -> Void) {
        self.settings = settings
        self.onHubChanged = onHubChanged
        _hubPathInput = State(initialValue: settings.hubRootPath)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sub-tab sidebar
            VStack(alignment: .leading, spacing: 0) {
                subTabButton("Paths & Agents", icon: "folder.badge.gearshape", tag: "paths")
                subTabButton("Sync Rules", icon: "arrow.triangle.swap", tag: "syncRules")
                subTabButton("Advanced", icon: "ellipsis.curlybraces", tag: "advanced")
                Spacer()
            }
            .frame(width: 200)
            .background(ds.Colors.surface.opacity(0.5))
            .padding(.top, 8)

            Divider().overlay(ds.Colors.borderSubtle)

            // Sub-tab content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch generalSubTab {
                    case "paths":
                        pathsAndAgentsContent
                    case "syncRules":
                        syncRulesContent
                    case "advanced":
                        advancedContent
                    default:
                        pathsAndAgentsContent
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: — Sub-tab Buttons

    private func subTabButton(_ label: String, icon: String, tag: String) -> some View {
        Button(action: { generalSubTab = tag }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 13))
                Spacer()
            }
            .foregroundColor(generalSubTab == tag ? ds.Colors.textPrimary : ds.Colors.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                generalSubTab == tag
                    ? ds.Colors.primaryContainer.opacity(0.2)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: — Paths & Agents Sub-tab

    private var pathsAndAgentsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Hub Path section
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Hub Path")
                Text("The primary local directory where central agent skills are stored.")
                    .font(.system(size: 11))
                    .foregroundColor(ds.Colors.textSecondary)
                    .padding(.bottom, 2)

                Text("LOCAL DIRECTORY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(ds.Colors.textSecondary.opacity(0.7))
                    .padding(.bottom, 4)

                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundColor(ds.Colors.outline)
                    TextField("Skill Sync path (e.g. ~/skill-hub)", text: $hubPathInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(7)
                        .background(ds.Colors.surfaceContainer)
                        .cornerRadius(ds.Shapes.small)
                        .overlay(
                            RoundedRectangle(cornerRadius: ds.Shapes.small)
                                .stroke(ds.Colors.borderSubtle, lineWidth: 1)
                        )

                    Button("Choose...") { browseForHub() }
                        .font(.system(size: 11))
                        .foregroundColor(ds.Colors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(ds.Colors.surfaceHigh)
                        .cornerRadius(ds.Shapes.small)
                        .buttonStyle(.plain)

                    Button("Apply") {
                        settings.hubRootPath = hubPathInput
                        onHubChanged()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(ds.Colors.actionPrimary)
                    .cornerRadius(ds.Shapes.small)
                    .buttonStyle(.plain)
                }
            }

            Divider().overlay(ds.Colors.borderSubtle).opacity(0.3)

            // Agent Platforms section
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Agent Platforms")
                Text("External platform directories that synchronize with the Hub.")
                    .font(.system(size: 11))
                    .foregroundColor(ds.Colors.textSecondary)
                    .padding(.bottom, 4)

                // Platform table
                VStack(spacing: 0) {
                    // Table header
                    HStack(spacing: 0) {
                        Text("PLATFORM NAME")
                            .font(ds.Typography.labelCaps)
                            .foregroundColor(ds.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("TARGET PATH")
                            .font(ds.Typography.labelCaps)
                            .foregroundColor(ds.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("ACTIONS")
                            .font(ds.Typography.labelCaps)
                            .foregroundColor(ds.Colors.textSecondary)
                            .frame(width: 60)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider().overlay(ds.Colors.borderSubtle)

                    // Platform rows
                    ForEach(Array(settings.agents.enumerated()), id: \.offset) { index, agent in
                        HStack(spacing: 0) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(agent.exists ? ds.Colors.statusSynced : ds.Colors.outline)
                                    .frame(width: 6, height: 6)
                                Text(agent.label)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(ds.Colors.textPrimary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text(agent.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(ds.Colors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 8) {
                                Button(action: {
                                    newAgentLabel = agent.label
                                    newAgentPath = agent.path
                                }) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 11))
                                        .foregroundColor(ds.Colors.textSecondary)
                                }
                                .buttonStyle(.plain)

                                Button(action: { settings.agents.remove(at: index) }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(ds.Colors.statusError)
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(width: 60)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        if index < settings.agents.count - 1 {
                            Divider()
                                .overlay(ds.Colors.borderSubtle)
                                .opacity(0.3)
                                .padding(.leading, 12)
                        }
                    }

                    if settings.agents.isEmpty {
                        HStack {
                            Text("No platforms configured")
                                .font(.system(size: 11))
                                .foregroundColor(ds.Colors.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                }
                .background(ds.Colors.surfaceContainer)
                .cornerRadius(ds.Shapes.medium)

                // Add Platform button
                Button(action: {
                    // Scroll to add form...
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                        Text("Add Platform")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(ds.Colors.actionPrimary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .sheet(isPresented: .constant(false)) { EmptyView() } // placeholder

                // Add platform form
                HStack(spacing: 8) {
                    TextField("Platform Name", text: $newAgentLabel)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(7)
                        .background(ds.Colors.surfaceContainer)
                        .cornerRadius(ds.Shapes.small)
                        .overlay(
                            RoundedRectangle(cornerRadius: ds.Shapes.small)
                                .stroke(ds.Colors.borderSubtle, lineWidth: 1)
                        )

                    TextField("Target Path (e.g. ~/.claude/skills)", text: $newAgentPath)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(7)
                        .background(ds.Colors.surfaceContainer)
                        .cornerRadius(ds.Shapes.small)
                        .overlay(
                            RoundedRectangle(cornerRadius: ds.Shapes.small)
                                .stroke(ds.Colors.borderSubtle, lineWidth: 1)
                        )

                    Button("Add") {
                        let label = newAgentLabel.trimmingCharacters(in: .whitespaces)
                        let path = newAgentPath.trimmingCharacters(in: .whitespaces)
                        if !label.isEmpty && !path.isEmpty {
                            settings.agents.append(AgentConfig(label: label, path: path))
                            newAgentLabel = ""
                            newAgentPath = ""
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(ds.Colors.actionPrimary)
                    .cornerRadius(ds.Shapes.small)
                    .buttonStyle(.plain)
                }
            }

            Divider().overlay(ds.Colors.borderSubtle).opacity(0.3)

            // Install Mode section
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Default Install Mode")

                Picker("", selection: Binding(
                    get: { settings.defaultInstallMode },
                    set: { settings.defaultInstallMode = $0 }
                )) {
                    Text("Link (Dev)").tag(InstallMode.link)
                    Text("Copy (Stable)").tag(InstallMode.copy)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Text("Link = symlinks that follow hub changes. Copy = independent snapshot.")
                    .font(.system(size: 11))
                    .foregroundColor(ds.Colors.textSecondary)
            }

            Divider().overlay(ds.Colors.borderSubtle).opacity(0.3)

            // Hub Profiles section
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Hub Profiles")

                VStack(spacing: 0) {
                    ForEach(Array(settings.hubProfiles.enumerated()), id: \.element.id) { index, profile in
                        HStack(spacing: 10) {
                            Image(systemName: "externaldrive")
                                .font(.system(size: 11))
                                .foregroundColor(ds.Colors.outline)
                            Text(profile.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(ds.Colors.textPrimary)
                            Text(profile.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(ds.Colors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(action: { settings.hubProfiles.remove(at: index) }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundColor(ds.Colors.statusError)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)

                        if index < settings.hubProfiles.count - 1 {
                            Divider()
                                .overlay(ds.Colors.borderSubtle)
                                .opacity(0.3)
                                .padding(.leading, 32)
                        }
                    }

                    if settings.hubProfiles.isEmpty {
                        Text("No profiles saved. Add profiles from the sidebar.")
                            .font(.system(size: 11))
                            .foregroundColor(ds.Colors.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
                .background(ds.Colors.surfaceContainer)
                .cornerRadius(ds.Shapes.medium)
            }

            Divider().overlay(ds.Colors.borderSubtle).opacity(0.3)

            // Auto-backup section
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(
                    get: { settings.autoBackup },
                    set: { settings.autoBackup = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-backup before sync")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(ds.Colors.textPrimary)
                        Text("Create a zip archive of target directories before applying Hub changes.")
                            .font(.system(size: 11))
                            .foregroundColor(ds.Colors.textSecondary)
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }

    // MARK: — Sync Rules Sub-tab

    private var syncRulesContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Sync Ignore Patterns")
            Text("Specify files and directories to exclude during synchronization.")
                .font(.system(size: 11))
                .foregroundColor(ds.Colors.textSecondary)

            // Textarea-style editor
            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: Binding(
                    get: { settings.ignoreGlobs.joined(separator: "\n") },
                    set: { newValue in
                        settings.ignoreGlobs = newValue
                            .components(separatedBy: "\n")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    }
                ))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(ds.Colors.textPrimary)
                .frame(height: 150)
                .padding(8)
                .background(ds.Colors.surfaceContainer)
                .cornerRadius(ds.Shapes.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: ds.Shapes.medium)
                        .stroke(ds.Colors.borderSubtle, lineWidth: 1)
                )
                .scrollContentBackground(.hidden)

                Text("Standard glob patterns supported.")
                    .font(.system(size: 10))
                    .foregroundColor(ds.Colors.textSecondary)
                    .padding(.top, 4)
                    .padding(.leading, 4)
            }

            Divider().overlay(ds.Colors.borderSubtle).opacity(0.3)

            sectionHeader("Hub Scan Excludes (Regex)")

            Text("Regex patterns applied to directory names in the hub root. Matching directories are not scanned for skills.")
                .font(.system(size: 11))
                .foregroundColor(ds.Colors.textSecondary)

            // Regex text editor
            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: Binding(
                    get: { settings.excludePatterns.joined(separator: "\n") },
                    set: { newValue in
                        settings.excludePatterns = newValue
                            .components(separatedBy: "\n")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    }
                ))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(ds.Colors.textPrimary)
                .frame(height: 100)
                .padding(8)
                .background(ds.Colors.surfaceContainer)
                .cornerRadius(ds.Shapes.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: ds.Shapes.medium)
                        .stroke(ds.Colors.borderSubtle, lineWidth: 1)
                )
                .scrollContentBackground(.hidden)

                Text("Standard regex patterns, one per line. Applied as `grep -E` filter.")
                    .font(.system(size: 10))
                    .foregroundColor(ds.Colors.textSecondary)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: — Advanced Sub-tab

    private var advancedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Reset Settings")

            Text("Restore all settings to their factory defaults. This action cannot be undone.")
                .font(.system(size: 11))
                .foregroundColor(ds.Colors.textSecondary)

            Button("Reset to Defaults") { showResetAlert = true }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ds.Colors.statusError)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(ds.Colors.surfaceHigh)
                .cornerRadius(ds.Shapes.small)
                .buttonStyle(.plain)
                .alert("Reset Settings?", isPresented: $showResetAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        settings.hubRootPath = {
                            let home = NSHomeDirectory()
                            return (home as NSString).appendingPathComponent("skill-hub")
                        }()
                        settings.agents = [
                            AgentConfig(label: "claude", path: "~/.claude/skills"),
                            AgentConfig(label: "codex", path: "~/.codex/skills"),
                            AgentConfig(label: "agents", path: "~/.agents/skills"),
                        ]
                        settings.defaultInstallMode = .link
                        settings.autoBackup = true
                        settings.ignoreGlobs = [
                            ".git", ".gitattributes", ".DS_Store", "LICENSE",
                            "README.md", "CHANGELOG.md", "docs", "agents",
                            ".github", ".vscode", ".idea",
                        ]
                        settings.excludePatterns = [
                            "^docs$", "^scripts$", "^backup-", "\\.backup-", "^\\..*", "^node_modules$",
                        ]
                        hubPathInput = settings.hubRootPath
                        onHubChanged()
                    }
                } message: {
                    Text("This will restore all settings to their defaults.")
                }

            Divider().overlay(ds.Colors.borderSubtle).opacity(0.3)

            sectionHeader("Tech Stack")

            VStack(alignment: .leading, spacing: 4) {
                techRow("Language", "Swift 5.9")
                techRow("UI Framework", "SwiftUI + AppKit")
                techRow("Minimum OS", "macOS 13.0 Ventura")
                techRow("Architecture", "MVVM + Services")
                techRow("Design", "Terminal Catalyst / Professional Utility")
            }

            Divider().overlay(ds.Colors.borderSubtle).opacity(0.3)

            sectionHeader("About")

            VStack(alignment: .leading, spacing: 8) {
                Text("SkillSyncDesktop v1.0")
                    .font(ds.Typography.headlineMD)
                    .foregroundColor(ds.Colors.textPrimary)

                Text("macOS native desktop application for managing AI agent skills. Sync, diff, and monitor skills across Claude Code, Codex CLI, OpenAI Agents SDK, and custom agent directories.")
                    .font(.system(size: 12))
                    .foregroundColor(ds.Colors.textSecondary)
                    .lineLimit(nil)
            }
        }
    }

    // MARK: — Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(ds.Typography.labelCaps)
            .foregroundColor(ds.Colors.textSecondary)
            .padding(.top, 4)
    }

    private func techRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.system(size: 12))
                .foregroundColor(ds.Colors.textSecondary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ds.Colors.textPrimary)
        }
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
    SettingsPageView(settings: AppSettings.shared, onHubChanged: {})
}
