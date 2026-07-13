import SwiftUI

// MARK: - Content View (Terminal Catalyst Design)

struct ContentView: View {
    @StateObject private var model = SkillSyncViewModel()
    @State private var selectedSkill: SkillInfo?
    @State private var showCleanAlert = false
    @State private var selectedTab: String = "overview"
    @State private var searchQuery = ""
    @State private var showNewHubSheet = false
    @State private var newHubName = ""
    @State private var newHubPath = ""
    @State private var showSyncPreview = false
    @State private var syncPreviewData: SyncPreview?
    @State private var showUnlinkConfirm = false
    @State private var unlinkTarget: (skillName: String, agent: AgentConfig)?
    @State private var unlinkConfirmStep = 0  // 0 = first confirm, 1 = second confirm
    @State private var showDiffSheetForSkill: SkillInfo?

    // Pagination state
    @State private var currentPage = 0
    private let pageSize = 15

    private let s = DesignSystem.self

    /// Skills filtered by the current search query.
    private var filteredSkills: [SkillInfo] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return model.skills }
        return model.skills.filter { skill in
            skill.name.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        ZStack {
            // Full-window dark background
            s.Colors.background
                .ignoresSafeArea()

            HStack(spacing: 0) {
                // MARK: — Sidebar (240px, glass)
                sidebarView
                    .frame(width: s.Layout.sidebarWidth)
                    .background(
                        s.Colors.surface
                            .opacity(0.85)
                            .background(.ultraThinMaterial)
                    )
                    .overlay(
                        Rectangle()
                            .fill(s.Colors.borderSubtle)
                            .frame(width: 1),
                        alignment: .trailing
                    )

                // MARK: — Main Content
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 780, minHeight: 520)
        .preferredColorScheme(.dark)
        .alert("清理备份", isPresented: $showCleanAlert) {
            Button("取消", role: .cancel) {}
            Button("清理") {
                let count = model.cleanBackups()
                model.lastError = count > 0 ? "已清理 \(count) 个备份目录" : nil
            }
        } message: {
            Text("共发现 \(model.backupCount) 个备份残留，确认清理？")
        }
        .sheet(item: $showDiffSheetForSkill) { skill in
            DiffView(skill: skill, model: model)
        }
        // Sync preview sheet
        .sheet(isPresented: $showSyncPreview) {
            syncPreviewPanel
        }
        .sheet(isPresented: $showUnlinkConfirm) {
            unlinkConfirmPanel
        }
    }

    // MARK: — Sidebar

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // App header
            sidebarHeader

            Divider()
                .overlay(s.Colors.borderSubtle)
                .padding(.horizontal, 12)

            // New Hub — prominent CTA button
            Button(action: { showNewHubSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text("New Hub")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(s.Colors.actionPrimary)
                .cornerRadius(s.Shapes.medium)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()
                .overlay(s.Colors.borderSubtle)
                .padding(.horizontal, 12)

            // Hub selector (moved below New Hub)
            hubSelector

            Divider()
                .overlay(s.Colors.borderSubtle)
                .padding(.horizontal, 12)

            // Navigation items
            sidebarNav

            Spacer()

            // Footer controls
            sidebarFooter
        }
        .padding(.vertical, s.Layout.gutter)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            // App icon
            ZStack {
                RoundedRectangle(cornerRadius: s.Shapes.medium)
                    .fill(s.Colors.primaryContainer)
                    .frame(width: 28, height: 28)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(s.Colors.textOnPrimary)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("Skill Sync")
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundColor(s.Colors.textPrimary)
                Text("AI Management Tool")
                    .font(.system(size: 11))
                    .foregroundColor(s.Colors.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, s.Layout.gutter)
    }

    private var sidebarNav: some View {
        VStack(spacing: 2) {
            SidebarNavItem(
                icon: "square.grid.2x2.fill",
                label: "Overview",
                isSelected: selectedTab == "overview",
                action: { selectedTab = "overview" }
            )

            SidebarNavItem(
                icon: "folder.fill",
                label: "Hub Skills",
                isSelected: selectedTab == "hub",
                badge: model.skills.count,
                action: { selectedTab = "hub" }
            )

            SidebarNavItem(
                icon: "globe",
                label: "External Platforms",
                isSelected: selectedTab == "external",
                action: { selectedTab = "external" }
            )

            SidebarNavItem(
                icon: "clock.arrow.circlepath",
                label: "Sync History",
                isSelected: selectedTab == "history",
                action: { selectedTab = "history" }
            )

            SidebarNavItem(
                icon: "gearshape",
                label: "Settings",
                isSelected: selectedTab == "settings",
                action: { selectedTab = "settings" }
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    // MARK: — Hub Selector

    private var hubSelector: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "externaldrive.connected.to.line.below.fill")
                    .font(.system(size: 10))
                    .foregroundColor(s.Colors.textSecondary)

                Picker("", selection: Binding(
                    get: { model.settings.hubRootPath },
                    set: { newPath in
                        model.settings.hubRootPath = newPath
                        model.refresh()
                    }
                )) {
                    ForEach(model.settings.hubProfiles) { profile in
                        Text(profile.name).tag(profile.path)
                    }
                    if !model.settings.hubRootPath.isEmpty,
                       !model.settings.hubProfiles.contains(where: { $0.path == model.settings.hubRootPath }) {
                        Text(displayNameForHub(model.settings.hubRootPath)).tag(model.settings.hubRootPath)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $showNewHubSheet) {
            newHubPanel
        }
    }

    private func displayNameForHub(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let name = (expanded as NSString).lastPathComponent
        return (!name.isEmpty && name != "/") ? name : expanded
    }

    private var newHubPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Hub Profile")
                    .font(s.Typography.headlineMD)
                    .foregroundColor(s.Colors.textPrimary)
                Spacer()
                Button("Cancel") { showNewHubSheet = false }
                    .font(.system(size: 12))
                    .foregroundColor(s.Colors.textSecondary)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(s.Colors.surfaceContainer)

            Divider().overlay(s.Colors.borderSubtle)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hub Name").font(s.Typography.bodySM).foregroundColor(s.Colors.textSecondary)
                    TextField("e.g. skill-hub", text: $newHubName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(s.Colors.textPrimary)
                        .padding(8)
                        .background(s.Colors.surfaceHigh)
                        .cornerRadius(s.Shapes.small)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Hub Path").font(s.Typography.bodySM).foregroundColor(s.Colors.textSecondary)
                    HStack {
                        TextField("e.g. ~/skill-hub", text: $newHubPath)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(s.Colors.textPrimary)
                            .padding(8)
                            .background(s.Colors.surfaceHigh)
                            .cornerRadius(s.Shapes.small)
                        Button("Browse...") { browseForNewHub() }
                            .font(.system(size: 11))
                            .foregroundColor(s.Colors.textSecondary)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(s.Colors.surfaceHigh)
                            .cornerRadius(s.Shapes.small)
                            .buttonStyle(.plain)
                    }
                }

                HStack {
                    Spacer()
                    Button("Add") {
                        let name = newHubName.trimmingCharacters(in: .whitespaces)
                        let path = newHubPath.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty, !path.isEmpty else { return }
                        let profile = HubProfile(name: name, path: path)
                        // Deduplicate: replace an existing profile with the same path,
                        // otherwise append. This prevents the picker from showing the
                        // same hub path under two different names.
                        if let idx = model.settings.hubProfiles.firstIndex(where: { $0.path == profile.path }) {
                            model.settings.hubProfiles[idx] = profile
                        } else if !model.settings.hubProfiles.contains(where: { $0.name == name }) {
                            model.settings.hubProfiles.append(profile)
                        }
                        model.settings.hubRootPath = profile.path
                        model.refresh()
                        newHubName = ""; newHubPath = ""; showNewHubSheet = false
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(s.Colors.actionPrimary)
                    .cornerRadius(s.Shapes.small)
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            Spacer()
        }
        .frame(width: 380, height: 240)
        .background(s.Colors.background)
        .preferredColorScheme(.dark)
    }

    private func browseForNewHub() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Hub Directory"
        if panel.runModal() == .OK { newHubPath = panel.url?.path ?? newHubPath }
    }

    // MARK: — Sidebar Footer

    private var sidebarFooter: some View {
        VStack(spacing: 2) {
            Divider()
                .overlay(s.Colors.borderSubtle)
                .padding(.horizontal, 12)

            VStack(spacing: 2) {
                SidebarNavItem(
                    icon: "terminal",
                    label: "Terminal",
                    isSelected: selectedTab == "terminal",
                    action: { selectedTab = "terminal" }
                )
                SidebarNavItem(
                    icon: "list.bullet.rectangle",
                    label: "Logs",
                    isSelected: selectedTab == "logs",
                    action: {
                        selectedTab = "logs"
                    }
                )
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            // Watch Sync All — prominent CTA button
            Button(action: {
                if model.watchEngine.isRunning {
                    model.stopWatching()
                } else {
                    model.startWatching()
                    selectedTab = "logs"
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: model.watchEngine.isRunning ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 14))
                    Text(model.watchEngine.isRunning ? "Stop Watching" : "Watch Sync All")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(model.watchEngine.isRunning ? s.Colors.statusStale : s.Colors.actionPrimary)
                .cornerRadius(s.Shapes.medium)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            // Watch mode indicator
            HStack {
                Circle()
                    .fill(model.watchEngine.isRunning ? s.Colors.statusSynced : s.Colors.outline)
                    .frame(width: 6, height: 6)

                Text(model.watchEngine.isRunning ? "Watching" : "Watch Mode Off")
                    .font(.system(size: 11))
                    .foregroundColor(model.watchEngine.isRunning ? s.Colors.statusSynced : s.Colors.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }

    // MARK: — Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Top toolbar
            topToolbar

            // Content area
            ScrollView {
                VStack(spacing: s.Layout.gutter) {
                    switch selectedTab {
                    case "overview":
                        overviewDashboard
                    case "hub":
                        hubSkillsView
                    case "activity":
                        activityFeedView
                    case "external":
                        externalSkillsView
                    case "history":
                        activityFeedView
                    case "logs":
                        watchLogsView
                    case "terminal":
                        terminalPageContent
                    case "settings":
                        settingsPageContent
                    case "docs":
                        documentationView
                    default:
                        overviewDashboard
                    }
                }
                .padding(s.Layout.edgeMargin)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: — Top Toolbar

    private var topToolbar: some View {
        HStack(spacing: 0) {
            // Left: tabs
            HStack(spacing: 24) {
                ToolbarTab(label: "Dashboard", isSelected: selectedTab == "overview") {
                    selectedTab = "overview"
                }
                ToolbarTab(label: "Activity", isSelected: selectedTab == "activity") {
                    selectedTab = "activity"
                }
                ToolbarTab(label: "Documentation", isSelected: selectedTab == "docs") {
                    selectedTab = "docs"
                }
            }

            Spacer()

            // Center: Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(s.Colors.textSecondary)
                TextField("Search skills...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(s.Colors.textPrimary)
                    .frame(width: 180)
                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(s.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(s.Colors.surfaceContainer)
            .cornerRadius(s.Shapes.medium)
            .overlay(
                RoundedRectangle(cornerRadius: s.Shapes.medium)
                    .stroke(s.Colors.borderSubtle, lineWidth: 1)
            )

            Spacer()

            // Right: Watch and Sync All action buttons
            HStack(spacing: 8) {
                // Watch button
                Button(action: {
                    if model.watchEngine.isRunning {
                        model.stopWatching()
                    } else {
                        model.startWatching()
                        selectedTab = "logs"
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: model.watchEngine.isRunning ? "stop.circle.fill" : "eye.fill")
                            .font(.system(size: 12))
                        Text(model.watchEngine.isRunning ? "Stop" : "Watch")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(model.watchEngine.isRunning ? s.Colors.statusStale : s.Colors.primary)
                    .cornerRadius(s.Shapes.small)
                }
                .buttonStyle(.plain)

                // Sync All button
                Button(action: {
                    syncPreviewData = model.computeSyncPreview()
                    showSyncPreview = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 12))
                        Text("Sync All")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(s.Colors.actionPrimary)
                    .cornerRadius(s.Shapes.small)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, s.Layout.edgeMargin)
        .padding(.vertical, 10)
        .background(s.Colors.background.opacity(0.9))
        .overlay(
            Rectangle()
                .fill(s.Colors.borderSubtle)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: — Overview Dashboard

    private var overviewDashboard: some View {
        VStack(spacing: s.Layout.gutter) {
            // Stats cards row — 3 cards per Stitch design
            HStack(spacing: s.Layout.gutter) {
                // Card 1: Total Skills
                StatCard(
                    title: "TOTAL SKILLS",
                    value: "\(model.skills.count)",
                    icon: "folder.fill",
                    trend: nil
                )
                .frame(maxWidth: .infinity)

                // Card 2: Sync Health (ring only)
                SyncHealthRingCard(model: model)
                    .frame(maxWidth: .infinity)

                // Card 3: Synced / Stale / Errors breakdown
                StatusBreakdownCard(model: model)
                    .frame(maxWidth: .infinity)
            }

            // Hub skills table
            hubSkillsView
        }
    }

    // MARK: — Activity Feed

    private var activityFeedView: some View {
        GlassPanel {
            VStack(spacing: 0) {
                HStack {
                    Text("Activity Feed")
                        .font(s.Typography.headlineMD)
                        .foregroundColor(s.Colors.textPrimary)
                    Spacer()
                    if !model.syncResults.isEmpty {
                        Button("Clear") {
                            model.syncResults.removeAll()
                        }
                        .font(.system(size: 11))
                        .foregroundColor(s.Colors.textSecondary)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, s.Layout.componentPadding)
                .padding(.vertical, 12)

                Divider().overlay(s.Colors.borderSubtle)

                if model.syncResults.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 28))
                            .foregroundColor(s.Colors.textSecondary)
                        Text("No activity yet")
                            .font(s.Typography.bodyMD)
                            .foregroundColor(s.Colors.textSecondary)
                        Text("Sync operations will appear here.")
                            .font(s.Typography.bodySM)
                            .foregroundColor(s.Colors.outline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(model.syncResults.reversed()) { result in
                                HStack(spacing: 10) {
                                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(result.success ? s.Colors.statusSynced : s.Colors.statusError)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(result.skillName) → \(result.agentLabel)")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(s.Colors.textPrimary)
                                        Text(result.message)
                                            .font(s.Typography.bodySM)
                                            .foregroundColor(s.Colors.textSecondary)
                                    }

                                    Spacer()

                                    Text(result.action.rawValue)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(result.success ? s.Colors.statusSynced : s.Colors.statusError)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            (result.success ? s.Colors.statusSynced : s.Colors.statusError)
                                                .opacity(0.1)
                                        )
                                        .cornerRadius(4)
                                }
                                .padding(.horizontal, s.Layout.componentPadding)
                                .padding(.vertical, 8)

                                if result.id != model.syncResults.first?.id {
                                    Divider()
                                        .overlay(s.Colors.borderSubtle)
                                        .opacity(0.5)
                                        .padding(.leading, 28)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: — Hub Skills Panel

    private var hubSkillsView: some View {
        GlassPanel {
            VStack(spacing: 0) {
                // Panel header
                HStack {
                    Text(searchQuery.isEmpty ? "Hub Skills" : "Hub Skills — \"\(searchQuery)\"")
                        .font(s.Typography.headlineMD)
                        .foregroundColor(s.Colors.textPrimary)

                    Spacer()

                    HStack(spacing: 8) {
                        // Filter toggle: clear or show all
                        Button(action: {
                            searchQuery = searchQuery.isEmpty ? "" : ""
                            // Sort skills by name (default view)
                        }) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(s.Colors.textSecondary)
                        .help("Sort / filter skills")

                        // More actions menu
                        Menu {
                            Button("Clean Backups") { showCleanAlert = true }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(s.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, s.Layout.componentPadding)
                .padding(.vertical, 12)

                Divider().overlay(s.Colors.borderSubtle)

                // Table
                skillStatusTable
                    .padding(.horizontal, s.Layout.componentPadding)
            }
        }
    }

    // MARK: — Skill Status Table

    private var paginatedSkills: [SkillInfo] {
        let start = currentPage * pageSize
        let all = filteredSkills
        guard start < all.count else {
            DispatchQueue.main.async { currentPage = 0 }
            return []
        }
        return Array(all.dropFirst(start).prefix(pageSize))
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(filteredSkills.count) / Double(pageSize))))
    }

    private var pagingRangeText: String {
        let total = filteredSkills.count
        guard total > 0 else { return "No skills" }
        let start = currentPage * pageSize + 1
        let end = min(start + pageSize - 1, total)
        return "Showing \(start)–\(end) of \(total) skills"
    }

    private var skillStatusTable: some View {
        VStack(spacing: 0) {
            if model.isScanning {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.7)
                    Spacer()
                }
                .padding(.vertical, 24)
            } else if filteredSkills.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 32))
                        .foregroundColor(s.Colors.textSecondary)
                    Text(searchQuery.isEmpty ? "No skills found in hub directory" : "No skills match \"\(searchQuery)\"")
                        .font(s.Typography.bodyMD)
                        .foregroundColor(s.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                // Header row
                HStack(spacing: 0) {
                    Text("SKILL NAME")
                        .font(s.Typography.labelCaps)
                        .foregroundColor(s.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)

                    ForEach(model.agents.filter { $0.exists }) { agent in
                        Text(agent.label.uppercased())
                            .font(s.Typography.labelCaps)
                            .foregroundColor(s.Colors.textSecondary)
                            .frame(width: 100, alignment: .leading)
                    }

                    Text("UPDATED")
                        .font(s.Typography.labelCaps)
                        .foregroundColor(s.Colors.textSecondary)
                        .frame(width: 80)
                }
                .padding(.vertical, 4)

                Divider().overlay(s.Colors.borderSubtle)

                // Data rows (paginated)
                ForEach(paginatedSkills) { skill in
                    skillTableRow(skill)
                    if skill.id != paginatedSkills.last?.id {
                        Divider()
                            .overlay(s.Colors.borderSubtle)
                            .opacity(0.5)
                    }
                }

                // Pagination controls
                if filteredSkills.count > pageSize {
                    Divider().overlay(s.Colors.borderSubtle)

                    HStack(spacing: 12) {
                        Text(pagingRangeText)
                            .font(s.Typography.bodySM)
                            .foregroundColor(s.Colors.textSecondary)

                        Spacer()

                        HStack(spacing: 4) {
                            Button(action: {
                                if currentPage > 0 { currentPage -= 1 }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 10, weight: .medium))
                                    Text("Previous")
                                        .font(.system(size: 11))
                                }
                                .foregroundColor(currentPage > 0 ? s.Colors.textPrimary : s.Colors.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(currentPage > 0 ? s.Colors.surfaceHigh : s.Colors.surfaceContainer)
                                .cornerRadius(s.Shapes.small)
                            }
                            .buttonStyle(.plain)
                            .disabled(currentPage <= 0)

                            // Page indicator
                            Text("\(currentPage + 1) / \(totalPages)")
                                .font(s.Typography.codeSM)
                                .foregroundColor(s.Colors.textSecondary)

                            Button(action: {
                                if currentPage < totalPages - 1 { currentPage += 1 }
                            }) {
                                HStack(spacing: 4) {
                                    Text("Next")
                                        .font(.system(size: 11))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(currentPage < totalPages - 1 ? s.Colors.textPrimary : s.Colors.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(currentPage < totalPages - 1 ? s.Colors.surfaceHigh : s.Colors.surfaceContainer)
                                .cornerRadius(s.Shapes.small)
                            }
                            .buttonStyle(.plain)
                            .disabled(currentPage >= totalPages - 1)
                        }
                    }
                    .padding(.horizontal, s.Layout.componentPadding)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private func skillTableRow(_ skill: SkillInfo) -> some View {
        HStack(spacing: 0) {
            // Skill name (monospaced)
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundColor(s.Colors.outline)

                Text(skill.name)
                    .font(s.Typography.codeSM)
                    .foregroundColor(s.Colors.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 7)

            // Status columns
            ForEach(model.agents.filter { $0.exists }) { agent in
                StatusBadge(state: skill.states[agent.label] ?? .notFound)
                    .frame(width: 100, alignment: .leading)
            }

            // Last updated
            Text(relativeTime(for: skill.lastModified))
                .font(s.Typography.codeSM)
                .foregroundColor(s.Colors.textSecondary)
                .frame(width: 80)
        }
        .contentShape(Rectangle())
        .contextMenu {
            ForEach(model.agents) { agent in
                Button("Sync to \(agent.label) (Link)") {
                    model.syncSkill(skill.name, to: agent, mode: .link)
                }
                Button("Sync to \(agent.label) (Copy)") {
                    model.syncSkill(skill.name, to: agent, mode: .copy)
                }
            }
            Divider()
            Button("View Diff") {
                showDiffSheetForSkill = skill
            }
            Divider()
            ForEach(model.agents) { agent in
                Button("Remove from \(agent.label)") {
                    unlinkTarget = (skillName: skill.name, agent: agent)
                    unlinkConfirmStep = 0
                    showUnlinkConfirm = true
                }
            }
        }
    }

    // MARK: — External Skills View

    private var externalSkillsView: some View {
        VStack(spacing: s.Layout.gutter) {
            // Stale links detail section
            let staleSkills = model.skills.filter { skill in
                skill.states.values.contains(.linkStale)
            }

            if !staleSkills.isEmpty {
                staleLinksDetailPanel(staleSkills: staleSkills)
            }

            // External skills per agent
            if model.externalSkills.isEmpty {
                GlassPanel {
                    VStack(spacing: 12) {
                        Image(systemName: "globe")
                            .font(.system(size: 32))
                            .foregroundColor(s.Colors.textSecondary)
                        Text("No External Skills")
                            .font(s.Typography.headlineMD)
                            .foregroundColor(s.Colors.textPrimary)
                        Text("All skills on agents originate from the hub.")
                            .font(s.Typography.bodySM)
                            .foregroundColor(s.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else {
                ForEach(Array(model.externalSkills.keys.sorted()), id: \.self) { agentLabel in
                    if let skills = model.externalSkills[agentLabel], !skills.isEmpty {
                        externalSkillCard(agentLabel: agentLabel, skills: skills)
                    }
                }
            }

            // Backup residue hint per agent
            if !model.backupByAgent.isEmpty {
                backupResiduePanel
            }
        }
    }

    private func staleLinksDetailPanel(staleSkills: [SkillInfo]) -> some View {
        GlassPanel {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "link.badge.exclamationmark")
                        .foregroundColor(s.Colors.statusStale)
                    Text("Stale Links Detail")
                        .font(s.Typography.headlineMD)
                        .foregroundColor(s.Colors.statusStale)
                    Spacer()
                    Text("\(staleSkills.count) issues")
                        .font(s.Typography.bodySM)
                        .foregroundColor(s.Colors.textSecondary)
                }
                .padding(.horizontal, s.Layout.componentPadding)
                .padding(.vertical, 12)

                Divider().overlay(s.Colors.borderSubtle)

                ForEach(staleSkills) { skill in
                    ForEach(Array(skill.staleDetails.keys.sorted()), id: \.self) { agentLabel in
                        if let detail = skill.staleDetails[agentLabel] {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(skill.name)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(s.Colors.textPrimary)
                                    Text("→")
                                        .foregroundColor(s.Colors.textSecondary)
                                    Text(agentLabel)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(s.Colors.primary)
                                    Spacer()
                                    Button("Fix") {
                                        if let agent = model.agents.first(where: { $0.label == agentLabel }) {
                                            model.syncSkill(skill.name, to: agent, mode: .link)
                                        }
                                    }
                                    .font(.system(size: 10))
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .tint(s.Colors.actionPrimary)
                                }
                                Divider().overlay(s.Colors.textSecondary.opacity(0.2))
                                lineView(label: "Current target", value: detail.currentTarget, dim: true)
                                lineView(label: "Resolved to", value: detail.resolvedTarget, dim: true)
                                lineView(label: "Expected target", value: detail.expectedTarget, dim: false)
                                lineView(label: "Resolved to", value: detail.resolvedExpected, dim: false)
                            }
                            .padding(.horizontal, s.Layout.componentPadding)
                            .padding(.vertical, 8)

                            if skill.id != staleSkills.last?.id ||
                               agentLabel != Array(skill.staleDetails.keys.sorted()).last {
                                Divider()
                                    .overlay(s.Colors.borderSubtle)
                                    .opacity(0.3)
                                    .padding(.leading, s.Layout.componentPadding)
                            }
                        }
                    }
                }
            }
        }
    }

    private func lineView(label: String, value: String, dim: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(s.Colors.textSecondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(dim ? s.Colors.textSecondary : s.Colors.textPrimary)
                .lineLimit(1)
        }
    }

    private func externalSkillCard(agentLabel: String, skills: [(name: String, path: String, isSymlink: Bool)]) -> some View {
        GlassPanel {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "server.rack")
                        .foregroundColor(s.Colors.primary)
                    Text(agentLabel)
                        .font(s.Typography.headlineMD)
                        .foregroundColor(s.Colors.textPrimary)
                    Spacer()
                    Text("\(skills.count) external skill(s)")
                        .font(s.Typography.bodySM)
                        .foregroundColor(s.Colors.textSecondary)
                }
                .padding(.horizontal, s.Layout.componentPadding)
                .padding(.vertical, 12)

                Divider().overlay(s.Colors.borderSubtle)

                ForEach(skills, id: \.name) { skill in
                    HStack(spacing: 10) {
                        Image(systemName: skill.isSymlink ? "link" : "folder")
                            .font(.system(size: 12))
                            .foregroundColor(skill.isSymlink ? s.Colors.primary : s.Colors.outline)
                        Text(skill.name)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(s.Colors.textPrimary)
                        if skill.isSymlink {
                            Text("(symlink)")
                                .font(.system(size: 10))
                                .foregroundColor(s.Colors.textSecondary)
                        }
                        Spacer()
                        Text(skill.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(s.Colors.textSecondary.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    .padding(.horizontal, s.Layout.componentPadding)
                    .padding(.vertical, 8)

                    if skill.name != skills.last?.name {
                        Divider()
                            .overlay(s.Colors.borderSubtle)
                            .opacity(0.5)
                            .padding(.leading, s.Layout.componentPadding)
                    }
                }
            }
        }
    }

    private var backupResiduePanel: some View {
        GlassPanel {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "archivebox")
                        .foregroundColor(s.Colors.statusStale)
                    Text("Backup Residues")
                        .font(s.Typography.headlineMD)
                        .foregroundColor(s.Colors.textPrimary)
                    Spacer()
                    Button("Clean All") {
                        showCleanAlert = true
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, s.Layout.componentPadding)
                .padding(.vertical, 12)

                Divider().overlay(s.Colors.borderSubtle)

                ForEach(Array(model.backupByAgent.keys.sorted()), id: \.self) { agentLabel in
                    if let count = model.backupByAgent[agentLabel], count > 0 {
                        HStack {
                            Image(systemName: "archivebox.fill")
                                .font(.system(size: 11))
                                .foregroundColor(s.Colors.textSecondary)
                            Text(agentLabel)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(s.Colors.textPrimary)
                            Spacer()
                            Text("\(count) backup file(s)")
                                .font(s.Typography.bodySM)
                                .foregroundColor(s.Colors.textSecondary)
                        }
                        .padding(.horizontal, s.Layout.componentPadding)
                        .padding(.vertical, 8)

                        if agentLabel != model.backupByAgent.keys.sorted().last {
                            Divider()
                                .overlay(s.Colors.borderSubtle)
                                .opacity(0.3)
                                .padding(.leading, s.Layout.componentPadding)
                        }
                    }
                }
            }
        }
    }

    // MARK: — Watch Logs View

    private var watchLogsView: some View {
        VStack(spacing: s.Layout.gutter) {
            // Watch status panel
            GlassPanel {
                VStack(spacing: 0) {
                    HStack {
                        Circle()
                            .fill(model.watchEngine.isRunning ? s.Colors.statusSynced : s.Colors.outline)
                            .frame(width: 8, height: 8)
                        Text(model.watchEngine.isRunning ? "Watch Mode Active" : "Watch Mode Stopped")
                            .font(s.Typography.headlineMD)
                            .foregroundColor(s.Colors.textPrimary)
                        Spacer()
                        Button(model.watchEngine.isRunning ? "Stop" : "Start") {
                            if model.watchEngine.isRunning {
                                model.stopWatching()
                            } else {
                                model.startWatching()
                            }
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(model.watchEngine.isRunning ? s.Colors.statusError : s.Colors.statusSynced)
                    }
                    .padding(.horizontal, s.Layout.componentPadding)
                    .padding(.vertical, 12)

                    Divider().overlay(s.Colors.borderSubtle)

                    // Watching info
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Watching").font(s.Typography.labelCaps).foregroundColor(s.Colors.textSecondary)
                            Text(model.settings.hubRootPath)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(s.Colors.textPrimary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let lastSync = model.watchEngine.lastSyncTime {
                            Text("Last sync: \(lastSync, style: .relative) ago")
                                .font(s.Typography.bodySM)
                                .foregroundColor(s.Colors.textSecondary)
                        }
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Debounce").font(s.Typography.labelCaps).foregroundColor(s.Colors.textSecondary)
                            Text("2s").font(.system(size: 13, weight: .medium)).foregroundColor(s.Colors.textPrimary)
                        }
                    }
                    .padding(.horizontal, s.Layout.componentPadding)
                    .padding(.vertical, 10)
                }
            }

            // Actively watching skills
            GlassPanel {
                VStack(spacing: 0) {
                    HStack {
                        Text("ACTIVELY WATCHING")
                            .font(s.Typography.labelCaps)
                            .foregroundColor(s.Colors.textSecondary)
                        Spacer()
                        Text("\(model.skills.count) skills")
                            .font(s.Typography.bodySM)
                            .foregroundColor(s.Colors.textSecondary)
                    }
                    .padding(.horizontal, s.Layout.componentPadding)
                    .padding(.vertical, 12)

                    Divider().overlay(s.Colors.borderSubtle)

                    if model.skills.isEmpty {
                        Text(model.watchEngine.isRunning ? "No skills found in hub directory" : "Start watch mode to monitor skills")
                            .font(s.Typography.bodySM)
                            .foregroundColor(s.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, s.Layout.componentPadding)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(model.skills.prefix(20)) { skill in
                            watchSkillCard(skill)

                            if skill.id != model.skills.prefix(20).last?.id {
                                Divider()
                                    .overlay(s.Colors.borderSubtle)
                                    .opacity(0.3)
                                    .padding(.leading, s.Layout.componentPadding)
                            }
                        }
                    }
                }
            }

            // Log stream
            GlassPanel {
                VStack(spacing: 0) {
                    HStack {
                        Text("EVENT LOG")
                            .font(s.Typography.labelCaps)
                            .foregroundColor(s.Colors.textSecondary)
                        Spacer()
                        if !model.watchEngine.logEntries.isEmpty {
                            Button("Clear") {
                                model.watchEngine.logEntries.removeAll()
                                model.watchEngine.lastEvent = ""
                            }
                            .font(.system(size: 10))
                            .foregroundColor(s.Colors.textSecondary)
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, s.Layout.componentPadding)
                    .padding(.vertical, 12)

                    Divider().overlay(s.Colors.borderSubtle)

                    if model.watchEngine.logEntries.isEmpty && model.watchEngine.lastEvent.isEmpty {
                        Text("Events will appear here when watch mode is active.")
                            .font(s.Typography.bodySM)
                            .foregroundColor(s.Colors.textSecondary)
                            .padding(.horizontal, s.Layout.componentPadding)
                            .padding(.vertical, 12)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(model.watchEngine.logEntries.enumerated()), id: \.offset) { _, entry in
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(logColor(for: entry))
                                            .frame(width: 6, height: 6)
                                        Text(entry)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(s.Colors.textPrimary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, s.Layout.componentPadding)
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .frame(maxHeight: 150)
                    }
                }
            }
        }
    }

    // MARK: — Watch Skill Card (with TARGETS badges)

    private func watchSkillCard(_ skill: SkillInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 13))
                    .foregroundColor(s.Colors.primary)
                Text(skill.name)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(s.Colors.textPrimary)
                    .lineLimit(1)

                Spacer()

                if let lastMod = skill.lastModified {
                    Text(lastMod, style: .relative)
                        .font(.system(size: 10))
                        .foregroundColor(s.Colors.textSecondary)
                }
            }

            // Path line
            Text(skill.hubPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(s.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            // TARGETS badges
            HStack(spacing: 6) {
                Text("TARGETS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(s.Colors.textSecondary)
                    .tracking(0.5)

                ForEach(model.agents.filter { $0.exists }) { agent in
                    let state = skill.states[agent.label] ?? .notFound
                    HStack(spacing: 3) {
                        Circle()
                            .fill(badgeColor(for: state))
                            .frame(width: 5, height: 5)
                        Text(agent.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(state == .notFound ? s.Colors.textSecondary : s.Colors.textPrimary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(s.Colors.surfaceHigh)
                    .cornerRadius(s.Shapes.small)
                }
            }
        }
        .padding(.horizontal, s.Layout.componentPadding)
        .padding(.vertical, 10)
    }

    private func badgeColor(for state: SyncState) -> Color {
        switch state {
        case .link, .copy:    return s.Colors.statusSynced
        case .linkStale:      return s.Colors.statusStale
        case .outdated:       return s.Colors.statusStale
        case .notFound:       return s.Colors.outline
        case .error:          return s.Colors.statusError
        }
    }

    private func logColor(for entry: String) -> Color {
        if entry.contains("[SYNC]") { return s.Colors.statusSynced }
        if entry.contains("[INFO]") { return s.Colors.primary }
        if entry.contains("[WATCH]") { return s.Colors.statusStale }
        if entry.contains("[SUCCESS]") { return s.Colors.statusSynced }
        if entry.contains("[WARN]") { return s.Colors.statusError }
        return s.Colors.textSecondary
    }

    private func eventColor(for event: String) -> Color {
        if event.contains("同步") || event.contains("Synced") { return s.Colors.statusSynced }
        if event.contains("Error") || event.contains("失败") { return s.Colors.statusError }
        if event.contains("监听") || event.contains("Watching") { return s.Colors.primary }
        return s.Colors.textSecondary
    }

    // MARK: — Settings Page Content

    private var settingsPageContent: some View {
        SettingsPageView(settings: model.settings) {
            model.refresh()
        }
    }

    // MARK: — Terminal Page Content

    private var terminalPageContent: some View {
        TerminalPageView(model: model)
    }

    // MARK: — Sync Preview Panel

    private var syncPreviewPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.swap")
                    .foregroundColor(s.Colors.primary)
                Text("Sync Preview")
                    .font(s.Typography.headlineMD)
                    .foregroundColor(s.Colors.textPrimary)
                Spacer()
                Button("Cancel") { showSyncPreview = false }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundColor(s.Colors.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(s.Colors.surfaceContainer)

            Divider().overlay(s.Colors.borderSubtle)

            // Content area — fills available space
            if let preview = syncPreviewData {
                if preview.items.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 28))
                            .foregroundColor(s.Colors.statusSynced)
                        Text("All skills are already in sync")
                            .font(s.Typography.bodyMD)
                            .foregroundColor(s.Colors.textSecondary)
                    }
                    Spacer()
                } else {
                    VStack(spacing: 0) {
                        // Summary
                        VStack(spacing: 8) {
                            HStack(spacing: 20) {
                                previewStat(color: s.Colors.statusSynced, label: "新增 (Created)", count: preview.totalCreate)
                                previewStat(color: s.Colors.statusStale, label: "覆盖 (Updated)", count: preview.totalUpdate)
                                previewStat(color: s.Colors.primary, label: "修正 (Fixing)", count: preview.totalFix)
                            }
                            .padding(.horizontal)
                            .padding(.top, 12)
                        }

                        Divider().overlay(s.Colors.borderSubtle).padding(.horizontal)

                        // Items list
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(preview.items) { item in
                                    HStack(spacing: 10) {
                                        Image(systemName: {
                                            switch item.action {
                                            case .created: return "plus.circle"
                                            case .updated: return "arrow.triangle.swap"
                                            case .fixed: return "wrench"
                                            default: return "minus"
                                            }
                                        }())
                                            .font(.system(size: 12))
                                            .foregroundColor({
                                                switch item.action {
                                                case .created: return s.Colors.statusSynced
                                                case .updated: return s.Colors.statusStale
                                                case .fixed: return s.Colors.primary
                                                default: return s.Colors.textSecondary
                                                }
                                            }())

                                        Text(item.skillName)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(s.Colors.textPrimary)
                                        Text("→")
                                            .foregroundColor(s.Colors.textSecondary)
                                        Text(item.agentLabel)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(s.Colors.textPrimary)
                                        Spacer()
                                        Text(item.action.rawValue)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor({
                                                switch item.action {
                                                case .created: return s.Colors.statusSynced
                                                case .updated: return s.Colors.statusStale
                                                case .fixed: return s.Colors.primary
                                                default: return s.Colors.textSecondary
                                                }
                                            }())
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(s.Colors.surfaceHigh)
                                            .cornerRadius(4)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 5)

                                    if item.id != preview.items.last?.id {
                                        Divider()
                                            .overlay(s.Colors.borderSubtle)
                                            .opacity(0.3)
                                            .padding(.leading, 12)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 350)
                    }
                }
            } else {
                Spacer()
                ProgressView()
                    .progressViewStyle(.circular)
                Spacer()
            }

            Spacer(minLength: 0)

            Divider().overlay(s.Colors.borderSubtle)

            // Footer actions
            HStack {
                Spacer()
                Button("Cancel") { showSyncPreview = false }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Confirm Sync") {
                    showSyncPreview = false
                    model.syncAll()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(s.Colors.actionPrimary)
                .disabled(syncPreviewData?.items.isEmpty ?? true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 580)
        .frame(minHeight: 300, idealHeight: 420, maxHeight: 520)
        .background(s.Colors.background)
        .preferredColorScheme(.dark)
    }

    private func previewStat(color: Color, label: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(s.Typography.bodySM)
                .foregroundColor(s.Colors.textSecondary)
            Text("\(count)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
        }
    }

    // MARK: — Unlink Confirm Panel

    private var unlinkConfirmPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "trash")
                    .foregroundColor(s.Colors.statusError)
                Text("Remove Skill from Agent")
                    .font(s.Typography.headlineMD)
                    .foregroundColor(s.Colors.statusError)
                Spacer()
                Button("Cancel") {
                    showUnlinkConfirm = false
                    unlinkConfirmStep = 0
                }
                .font(.system(size: 12))
                .buttonStyle(.plain)
                .foregroundColor(s.Colors.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(s.Colors.surfaceContainer)

            Divider().overlay(s.Colors.borderSubtle)

            if let target = unlinkTarget {
                VStack(alignment: .leading, spacing: 16) {
                    // Warning
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(s.Colors.statusStale)
                        Text("This will remove the skill from the agent. Hub source files will NOT be deleted.")
                            .font(s.Typography.bodySM)
                            .foregroundColor(s.Colors.textSecondary)
                    }
                    .padding(12)
                    .background(s.Colors.statusStale.opacity(0.08))
                    .cornerRadius(s.Shapes.small)

                    // Preview
                    VStack(alignment: .leading, spacing: 8) {
                        detailRow("Skill", target.skillName)
                        detailRow("Agent", target.agent.label)
                        detailRow("Path", (target.agent.path as NSString).appendingPathComponent(target.skillName))
                        let preview = model.computeUnlinkPreview(target.skillName, from: target.agent)
                        detailRow("Type", preview.isSymlink ? "Symbolic Link" : "Directory")
                    }
                    .padding(12)
                    .background(s.Colors.surfaceContainer)
                    .cornerRadius(s.Shapes.small)

                    if unlinkConfirmStep == 0 {
                        // First confirmation
                        Text("First confirmation required")
                            .font(s.Typography.bodySM)
                            .foregroundColor(s.Colors.statusStale)
                    } else {
                        // Second (final) confirmation
                        Text("⚠️ FINAL confirmation — this cannot be undone")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(s.Colors.statusError)
                    }
                }
                .padding(20)
            }

            Divider().overlay(s.Colors.borderSubtle)

            HStack {
                Spacer()
                Button("Cancel") {
                    showUnlinkConfirm = false
                    unlinkConfirmStep = 0
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if unlinkConfirmStep == 0 {
                    Button("Confirm (1/2)") {
                        unlinkConfirmStep = 1
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(s.Colors.statusStale)
                } else {
                    Button("REMOVE (Final)") {
                        if let target = unlinkTarget {
                            model.unlinkSkill(target.skillName, from: target.agent)
                        }
                        showUnlinkConfirm = false
                        unlinkConfirmStep = 0
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(s.Colors.statusError)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 480, height: 380)
        .background(s.Colors.background)
        .preferredColorScheme(.dark)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(s.Colors.textSecondary)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(s.Colors.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: — Helpers

    private func relativeTime(for date: Date?) -> String {
        guard let date = date else { return "-" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 604800 { return "\(Int(interval / 86400))d ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    // MARK: — Documentation View

    private var documentationView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Documentation")
                        .font(s.Typography.headlineLG)
                        .foregroundColor(s.Colors.textPrimary)
                    Text("Learn how to use Skill Sync for managing AI agent skills.")
                        .font(s.Typography.bodySM)
                        .foregroundColor(s.Colors.textSecondary)
                }
                Spacer()
            }
            .padding(.bottom, s.Layout.gutter)

            Divider().overlay(s.Colors.borderSubtle).padding(.bottom, s.Layout.gutter)

            // Quick-start cards
            LazyVGrid(columns: [GridItem(.flexible(), spacing: s.Layout.gutter),
                                 GridItem(.flexible(), spacing: s.Layout.gutter)]) {
                docCard(
                    icon: "arrow.triangle.swap",
                    title: "Sync Skills",
                    body: "Use \"Link\" mode during development (symlinks follow hub changes). Switch to \"Copy\" for stable snapshots. All sync operations back up targets automatically when auto-backup is on."
                )
                docCard(
                    icon: "eye",
                    title: "Watch Mode",
                    body: "Click \"Watch Sync All\" in the sidebar to monitor the hub directory. When files change, Skill Sync auto-syncs affected skills to all configured agent platforms."
                )
                docCard(
                    icon: "arrow.left.arrow.right",
                    title: "Diff Viewer",
                    body: "Click any skill in the Hub Skills table that shows a \"Stale\" or \"Outdated\" status to inspect differences side-by-side before applying changes."
                )
                docCard(
                    icon: "gearshape",
                    title: "Settings",
                    body: "Manage hub paths, agent platforms, sync rules (ignore patterns), and advanced options through the Settings sidebar page or the sheet accessible from the sidebar."
                )
                docCard(
                    icon: "folder.badge.plus",
                    title: "Create a Hub",
                    body: "Click \"New Hub\" in the sidebar, give it a name and choose a directory. Any directory with Markdown files at the root (or one level deeper) is a valid hub."
                )
                docCard(
                    icon: "terminal",
                    title: "Shell Script",
                    body: "The Termnial tab mirrors the original sync-skills.sh script. Use the command dropdown to run individual subcommands: status, sync, clean, diff, scan."
                )
            }

            Spacer().frame(height: s.Layout.gutter + 4)

            Divider().overlay(s.Colors.borderSubtle).padding(.bottom, s.Layout.gutter)

            // CLI reference
            VStack(alignment: .leading, spacing: 8) {
                Text("QUICK REFERENCE".uppercased())
                    .font(s.Typography.labelCaps)
                    .foregroundColor(s.Colors.textSecondary)

                VStack(spacing: 0) {
                    cliRow("./sync-skills.sh sync", "Sync all skills to agents using default mode")
                    cliRow("./sync-skills.sh sync --mode link", "Sync with symlink mode (dev)")
                    cliRow("./sync-skills.sh status", "Print full status matrix")
                    cliRow("./sync-skills.sh diff <skill>", "Show per-file diff for a skill")
                    cliRow("./sync-skills.sh watch", "Start watch mode (Ctrl+C to stop)")
                    cliRow("./sync-skills.sh clean", "Remove stale backup archives")
                }
            }
        }
        .padding(s.Layout.edgeMargin)
    }

    private func docCard(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(s.Colors.primary)
                    .frame(width: 20)
                Text(title)
                    .font(s.Typography.headlineMD)
                    .foregroundColor(s.Colors.textPrimary)
            }
            Text(body)
                .font(s.Typography.bodySM)
                .foregroundColor(s.Colors.textSecondary)
                .lineLimit(nil)
            Spacer()
        }
        .padding(14)
        .frame(height: 140)
        .background(s.Colors.surfaceContainer)
        .cornerRadius(s.Shapes.medium)
    }

    private func cliRow(_ cmd: String, _ desc: String) -> some View {
        HStack(spacing: 12) {
            Text(cmd)
                .font(s.Typography.codeSM)
                .foregroundColor(s.Colors.primary)
                .frame(width: 240, alignment: .leading)
            Text(desc)
                .font(s.Typography.bodySM)
                .foregroundColor(s.Colors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(s.Colors.surfaceContainer.opacity(0.5))
    }
}

// MARK: — Sidebar Nav Item

struct SidebarNavItem: View {
    let icon: String
    let label: String
    let isSelected: Bool
    var badge: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .frame(width: 18)

                Text(label)
                    .font(.system(size: 13))

                if let badge = badge {
                    Spacer()
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.surfaceHigh)
                        .cornerRadius(4)
                } else {
                    Spacer()
                }
            }
            .foregroundColor(isSelected ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? DesignSystem.Colors.primaryContainer.opacity(0.3)
                    : Color.clear
            )
            .cornerRadius(DesignSystem.Shapes.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: — Toolbar Tab

struct ToolbarTab: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.textSecondary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: — Glass Panel

struct GlassPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Shapes.large)
                    .fill(DesignSystem.Colors.surface.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Shapes.large)
                    .stroke(DesignSystem.Colors.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Shapes.large))
    }
}

// MARK: — Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let trend: String?

    private let s = DesignSystem.self

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title)
                        .font(s.Typography.labelCaps)
                        .foregroundColor(s.Colors.textSecondary)
                    Spacer()
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(s.Colors.outline)
                }

                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .default))
                    .foregroundColor(s.Colors.textPrimary)

                if let trend = trend {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10))
                        Text(trend)
                            .font(s.Typography.bodySM)
                    }
                    .foregroundColor(s.Colors.statusSynced)
                }
            }
            .padding(16)
        }
    }
}

// MARK: — Sync Health Ring Card (Card 2: ring chart only)

struct SyncHealthRingCard: View {
    @ObservedObject var model: SkillSyncViewModel
    private let s = DesignSystem.self

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("SYNC HEALTH")
                    .font(s.Typography.labelCaps)
                    .foregroundColor(s.Colors.textSecondary)

                HStack(alignment: .center, spacing: 20) {
                    // Donut chart
                    ZStack {
                        Circle()
                            .stroke(s.Colors.surfaceHighest, lineWidth: 4)
                            .frame(width: 56, height: 56)

                        Circle()
                            .trim(from: 0, to: syncRatio)
                            .stroke(s.Colors.statusSynced, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 56, height: 56)
                            .rotationEffect(.degrees(-90))

                        Text("\(Int(syncRatio * 100))%")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(s.Colors.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Overall sync health")
                            .font(s.Typography.bodySM)
                            .foregroundColor(s.Colors.textSecondary)
                        Text("\(syncedCount) of \(model.skills.count) skills in sync")
                            .font(.system(size: 11))
                            .foregroundColor(s.Colors.textSecondary)
                    }
                }
            }
            .padding(16)
        }
    }

    private var syncedCount: Int {
        model.skills.filter { $0.states.values.contains(where: { $0 == .link || $0 == .copy }) }.count
    }

    private var syncRatio: CGFloat {
        model.skills.isEmpty ? 0 : CGFloat(syncedCount) / CGFloat(model.skills.count)
    }
}

// MARK: — Status Breakdown Card (Card 3: Synced / Stale / Errors)

struct StatusBreakdownCard: View {
    @ObservedObject var model: SkillSyncViewModel
    private let s = DesignSystem.self

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("STATUS BREAKDOWN")
                        .font(s.Typography.labelCaps)
                        .foregroundColor(s.Colors.textSecondary)
                    Spacer()
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 14))
                        .foregroundColor(s.Colors.outline)
                }

                HStack(spacing: 24) {
                    breakdownItem(color: s.Colors.statusSynced, label: "Synced", count: syncedCount)
                    breakdownItem(color: s.Colors.statusStale, label: "Stale", count: staleCount)
                    breakdownItem(color: s.Colors.statusError, label: "Errors", count: errorCount)
                }
            }
            .padding(16)
        }
    }

    private var syncedCount: Int {
        model.skills.filter { $0.states.values.contains(where: { $0 == .link || $0 == .copy }) }.count
    }

    private var staleCount: Int {
        model.skills.filter { $0.states.values.contains(where: { $0 == .outdated || $0 == .linkStale }) }.count
    }

    private var errorCount: Int {
        model.skills.filter { $0.states.values.contains(where: { $0 == .error || $0 == .notFound }) }.count
    }

    private func breakdownItem(color: Color, label: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label)
                    .font(s.Typography.bodySM)
                    .foregroundColor(s.Colors.textSecondary)
            }
            Text("\(count)")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(color)
        }
    }
}

// MARK: — Sync Health Card (original, kept for compatibility)

struct SyncHealthCard: View {
    @ObservedObject var model: SkillSyncViewModel
    private let s = DesignSystem.self

    var body: some View {
        GlassPanel {
            HStack(alignment: .center, spacing: 20) {
                // Donut chart placeholder
                ZStack {
                    Circle()
                        .stroke(s.Colors.surfaceHighest, lineWidth: 4)
                        .frame(width: 56, height: 56)

                    Circle()
                        .trim(from: 0, to: syncRatio)
                        .stroke(s.Colors.statusSynced, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(syncRatio * 100))%")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(s.Colors.textPrimary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("SYNC HEALTH OVERVIEW")
                        .font(s.Typography.labelCaps)
                        .foregroundColor(s.Colors.textSecondary)

                    HStack(spacing: 20) {
                        healthItem(color: s.Colors.statusSynced, label: "Synced", count: syncedCount)
                        healthItem(color: s.Colors.statusStale, label: "Stale", count: staleCount)
                        healthItem(color: s.Colors.statusError, label: "Errors", count: errorCount)
                    }
                }
            }
            .padding(16)
        }
    }

    private var syncedCount: Int {
        model.skills.filter { $0.states.values.contains(where: { $0 == .link || $0 == .copy }) }.count
    }

    private var staleCount: Int {
        model.skills.filter { $0.states.values.contains(where: { $0 == .outdated || $0 == .linkStale }) }.count
    }

    private var errorCount: Int {
        model.skills.filter { $0.states.values.contains(where: { $0 == .error || $0 == .notFound }) }.count
    }

    private var syncRatio: CGFloat {
        model.skills.isEmpty ? 0 : CGFloat(syncedCount) / CGFloat(model.skills.count)
    }

    private func healthItem(color: Color, label: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label)
                    .font(s.Typography.bodySM)
                    .foregroundColor(s.Colors.textSecondary)
            }
            Text("\(count)")
                .font(s.Typography.headlineMD)
                .foregroundColor(s.Colors.textPrimary)
        }
    }

}

// MARK: — Preview

#Preview {
    ContentView()
}
