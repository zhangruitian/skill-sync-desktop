import Foundation
import Combine

// MARK: - Sync Preview

/// Summary computed before executing a batch sync.
struct SyncPreview {
    struct Item: Identifiable {
        var id: String { "\(skillName)@\(agentLabel)" }
        let skillName: String
        let agentLabel: String
        let action: SyncEngine.SyncAction
    }

    let items: [Item]
    let totalCreate: Int
    let totalUpdate: Int
    let totalSkip: Int
    let totalFix: Int
}

/// Central view model that coordinates all services and provides data to views.
@MainActor
final class SkillSyncViewModel: ObservableObject {
    // MARK: - Published State

    @Published var skills: [SkillInfo] = []
    @Published var externalSkills: [String: [(name: String, path: String, isSymlink: Bool)]] = [:]
    @Published var agents: [AgentConfig] = []
    @Published var isScanning = false
    @Published var lastError: String?
    @Published var syncResults: [SyncEngine.SyncResult] = [] {
        didSet { saveHistory() }
    }
    @Published var errors: [AppError] = []
    @Published var backupCount: Int = 0
    @Published var backupByAgent: [String: Int] = [:]

    // MARK: - Services

    var settings = AppSettings.shared
    let hubManager: HubManager
    let agentManager: AgentManager
    let statusEngine: StatusEngine
    let syncEngine: SyncEngine
    let diffEngine: DiffEngine
    let watchEngine: WatchEngine
    let backupCleaner: BackupCleaner

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        hubManager = HubManager(settings: settings)
        agentManager = AgentManager(settings: settings)
        statusEngine = StatusEngine(hubManager: hubManager, agentManager: agentManager)
        syncEngine = SyncEngine(hubManager: hubManager, agentManager: agentManager)
        diffEngine = DiffEngine()
        watchEngine = WatchEngine(hubManager: hubManager, agentManager: agentManager)
        backupCleaner = BackupCleaner(agentManager: agentManager)

        // Bind to settings changes
        settings.$hubRootPath
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        settings.$agents
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] agents in
                self?.agents = agents
                self?.refresh()
            }
            .store(in: &cancellables)

        // Watch engine sync callback
        watchEngine.onSync = { [weak self] results in
            Task { @MainActor in
                self?.syncResults = results
                self?.refresh()
            }
        }

        // Forward watch engine isRunning changes so views update
        watchEngine.$isRunning
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Initial load
        loadHistory()
        refresh()
    }

    // MARK: - Actions

    /// Refresh the full status matrix.
    func refresh() {
        isScanning = true
        lastError = nil

        let engine = self.statusEngine
        let mgr = self.agentManager
        let cleaner = self.backupCleaner

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let computedSkills = engine.computeAllStates()
            let currentAgents = mgr.allAgents
            let externals = engine.computeExternalSkills()
            let backupEntries = cleaner.scanBackups()

            // Per-agent backup counts
            var perAgent: [String: Int] = [:]
            for entry in backupEntries {
                perAgent[entry.agentLabel, default: 0] += 1
            }

            DispatchQueue.main.async {
                self?.skills = computedSkills
                self?.externalSkills = externals
                self?.agents = currentAgents
                self?.isScanning = false
                self?.backupCount = backupEntries.count
                self?.backupByAgent = perAgent
            }
        }
    }

    /// Sync a single skill to a single agent.
    func syncSkill(_ skillName: String, to agent: AgentConfig, mode: InstallMode) {
        let result = syncEngine.syncSkill(skillName, to: agent, mode: mode)
        syncResults.append(result)
        refresh()
    }

    /// Sync selected skills to all agents.
    func syncSelected(_ skillNames: [String], mode: InstallMode? = nil) {
        let installMode = mode ?? settings.defaultInstallMode
        let results = syncEngine.sync(
            skills: skillNames,
            mode: installMode,
            agents: agentManager.allAgents
        )
        syncResults = results
        refresh()
    }

    /// Sync all skills to all agents.
    func syncAll(mode: InstallMode? = nil) {
        let installMode = mode ?? settings.defaultInstallMode
        let results = syncEngine.sync(
            skills: hubManager.scanSkills(),
            mode: installMode,
            agents: agentManager.allAgents
        )
        syncResults = results
        refresh()
    }

    /// Compute a preview of what would happen without actually syncing.
    func computeSyncPreview(mode: InstallMode? = nil) -> SyncPreview {
        let installMode = mode ?? settings.defaultInstallMode
        let skillNames = hubManager.scanSkills()
        let agents = agentManager.allAgents
        var items: [SyncPreview.Item] = []

        let engine = statusEngine
        for skillName in skillNames {
            for agent in agents {
                let hubPath = hubManager.skillPath(for: skillName)
                let agentPath = agentManager.skillPath(for: skillName, agent: agent)
                let state = engine.computeState(hubPath: hubPath, agentPath: agentPath)

                let action: SyncEngine.SyncAction
                if installMode == .link && state == .link {
                    action = .skipped
                } else if installMode == .copy && state == .copy {
                    action = .skipped
                } else if state == .linkStale {
                    action = .fixed
                } else if state == .outdated {
                    action = .updated
                } else if state == .notFound {
                    action = .created
                } else {
                    action = .skipped
                }

                if action != .skipped {
                    items.append(SyncPreview.Item(
                        skillName: skillName,
                        agentLabel: agent.label,
                        action: action
                    ))
                }
            }
        }

        return SyncPreview(
            items: items,
            totalCreate: items.filter { $0.action == .created }.count,
            totalUpdate: items.filter { $0.action == .updated }.count,
            totalSkip: 0,
            totalFix: items.filter { $0.action == .fixed }.count
        )
    }

    /// Compute a preview of what unwinding would remove.
    func computeUnlinkPreview(_ skillName: String, from agent: AgentConfig) -> (exists: Bool, isSymlink: Bool, path: String) {
        let agentPath = agentManager.skillPath(for: skillName, agent: agent)
        let fileManager = FileManager.default
        let exists = fileManager.fileExists(atPath: agentPath)
        let isSymlink = (try? fileManager.destinationOfSymbolicLink(atPath: agentPath)) != nil
        return (exists: exists, isSymlink: isSymlink, path: agentPath)
    }

    /// Unlink (remove) a skill from an agent.
    func unlinkSkill(_ skillName: String, from agent: AgentConfig) {
        do {
            try syncEngine.unlink(skillName, from: agent)
            refresh()
        } catch {
            lastError = error.localizedDescription
            errors.append(AppError(
                domain: "SyncEngine",
                message: "Failed to unlink \(skillName) from \(agent.label)",
                underlyingError: error.localizedDescription
            ))
        }
    }

    /// Clean all backup residuals.
    func cleanBackups() -> Int {
        let deleted = backupCleaner.deleteAll()
        backupCount = 0
        errors.append(AppError.info("BackupCleaner", "Cleaned \(deleted) backup residual(s)"))
        return deleted
    }

    /// Start watching hub for changes.
    func startWatching() {
        watchEngine.start()
    }

    /// Stop watching.
    func stopWatching() {
        watchEngine.stop()
    }

    // MARK: - History Persistence

    private let historyKey = "syncHistory"
    private let maxHistoryEntries = 200

    private func saveHistory() {
        let recent = Array(syncResults.suffix(maxHistoryEntries))
        if let data = try? JSONEncoder().encode(recent) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([SyncEngine.SyncResult].self, from: data) else {
            return
        }
        syncResults = decoded
    }
}
