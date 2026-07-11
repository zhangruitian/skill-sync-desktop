import Foundation

// MARK: - Sync Engine

/// Executes sync operations: link (symlink) or copy, with optional backup.
final class SyncEngine {
    private let hubManager: HubManager
    private let agentManager: AgentManager
    private let statusEngine: StatusEngine
    private let fileManager = FileManager.default
    private let settings = AppSettings.shared

    init(hubManager: HubManager, agentManager: AgentManager) {
        self.hubManager = hubManager
        self.agentManager = agentManager
        self.statusEngine = StatusEngine(hubManager: hubManager, agentManager: agentManager)
    }

    // MARK: - Sync

    /// Result of a single sync operation.
    struct SyncResult: Identifiable, Codable {
        var id: String { "\(skillName)@\(agentLabel)" }
        let skillName: String
        let agentLabel: String
        let action: SyncAction
        let success: Bool
        let message: String
    }

    enum SyncAction: String, Codable {
        case created   = "新增"
        case updated   = "覆盖"
        case fixed     = "修正"
        case skipped   = "跳过"
        case error     = "失败"
    }

    /// Sync a list of skills to all agents.
    func sync(skills: [String], mode: InstallMode, agents: [AgentConfig]? = nil) -> [SyncResult] {
        let targets = agents ?? agentManager.allAgents
        var results: [SyncResult] = []

        for skillName in skills {
            for agent in targets {
                let result = syncSkill(skillName, to: agent, mode: mode)
                results.append(result)
            }
        }

        return results
    }

    /// Sync a single skill to a single agent.
    func syncSkill(_ skillName: String, to agent: AgentConfig, mode: InstallMode) -> SyncResult {
        let hubPath = hubManager.skillPath(for: skillName)
        let agentPath = agentManager.skillPath(for: skillName, agent: agent)
        let currentState = statusEngine.computeState(hubPath: hubPath, agentPath: agentPath)

        // Already up to date
        if mode == .link && currentState == .link {
            return SyncResult(
                skillName: skillName,
                agentLabel: agent.label,
                action: .skipped,
                success: true,
                message: "已是最新软链，跳过"
            )
        }

        if mode == .copy && currentState == .copy {
            return SyncResult(
                skillName: skillName,
                agentLabel: agent.label,
                action: .skipped,
                success: true,
                message: "内容已一致，跳过"
            )
        }

        // Backup existing
        if fileManager.fileExists(atPath: agentPath) || (try? fileManager.destinationOfSymbolicLink(atPath: agentPath)) != nil {
            if settings.autoBackup {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyyMMdd-HHmmss"
                fmt.locale = Locale(identifier: "en_US_POSIX")
                let timestamp = fmt.string(from: Date())
                let backupPath = agentPath + ".backup-" + timestamp
                try? fileManager.moveItem(atPath: agentPath, toPath: backupPath)
            }

            // Remove old
            try? fileManager.removeItem(atPath: agentPath)
        }

        // Ensure parent directory exists
        let parentDir = (agentPath as NSString).deletingLastPathComponent
        try? fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        // Install
        do {
            switch mode {
            case .link:
                try fileManager.createSymbolicLink(atPath: agentPath, withDestinationPath: hubPath)
                return SyncResult(
                    skillName: skillName,
                    agentLabel: agent.label,
                    action: currentState == .linkStale ? .fixed : .created,
                    success: true,
                    message: currentState == .linkStale ? "软链已修正" : "软链安装完成"
                )

            case .copy:
                try fileManager.copyItem(atPath: hubPath, toPath: agentPath)
                // Clean dev files
                cleanSyncIgnores(at: agentPath)
                return SyncResult(
                    skillName: skillName,
                    agentLabel: agent.label,
                    action: currentState == .outdated ? .updated : .created,
                    success: true,
                    message: currentState == .outdated ? "已更新" : "复制安装完成"
                )
            }
        } catch {
            return SyncResult(
                skillName: skillName,
                agentLabel: agent.label,
                action: .error,
                success: false,
                message: error.localizedDescription
            )
        }
    }

    /// Remove a skill from the agent (unlink). Does NOT touch hub source.
    func unlink(_ skillName: String, from agent: AgentConfig) throws {
        let agentPath = agentManager.skillPath(for: skillName, agent: agent)

        if fileManager.fileExists(atPath: agentPath) {
            try fileManager.removeItem(atPath: agentPath)
        }
    }

    // MARK: - Helpers

    /// Remove dev files from a copied skill directory.
    /// Matches both files and directories whose name equals any ignoreGlobs pattern.
    private func cleanSyncIgnores(at path: String) {
        let ignoreSet = Set(settings.ignoreGlobs)
        let url = URL(fileURLWithPath: path)
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else { return }

        var toRemove: [URL] = []
        for case let fileURL as URL in enumerator {
            if ignoreSet.contains(fileURL.lastPathComponent) {
                toRemove.append(fileURL)
                // If it's a directory, skip its contents entirely
                let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir {
                    enumerator.skipDescendants()
                }
            }
        }
        for url in toRemove {
            try? fileManager.removeItem(at: url)
        }
    }
}
