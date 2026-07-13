import Foundation

// MARK: - Backup Cleaner

/// Scans agent directories for stale backup residuals and cleans them up.
final class BackupCleaner: @unchecked Sendable {
    private let agentManager: AgentManager
    private let fileManager = FileManager.default

    init(agentManager: AgentManager) {
        self.agentManager = agentManager
    }

    /// Represents a single backup residual found.
    struct BackupEntry: Identifiable {
        var id: String { path }
        let skillName: String
        let agentLabel: String
        let path: String
        let size: Int64
    }

    /// Scan all agent directories for backup residuals (*.backup-*).
    func scanBackups() -> [BackupEntry] {
        var entries: [BackupEntry] = []

        for agent in agentManager.allAgents {
            guard agent.exists else { continue }

            guard let contents = try? fileManager.contentsOfDirectory(atPath: agent.path) else {
                continue
            }

            for item in contents {
                if item.contains(".backup-") {
                    let fullPath = (agent.path as NSString).appendingPathComponent(item)
                    let size = (try? fileManager.attributesOfItem(atPath: fullPath)[.size] as? Int64) ?? 0

                    // Extract original skill name (strip .backup-TIMESTAMP suffix).
                    // Matches both old ISO8601-derived format (20260711T143052Z) and
                    // new DateFormatter format (20260711-143052) which uses local time.
                    let originalName = item.replacingOccurrences(
                        of: "\\.backup-\\d{8}[-T]\\d{6}.*",
                        with: "",
                        options: .regularExpression
                    )

                    entries.append(BackupEntry(
                        skillName: originalName,
                        agentLabel: agent.label,
                        path: fullPath,
                        size: size
                    ))
                }
            }
        }

        return entries.sorted { $0.agentLabel < $1.agentLabel }
    }

    /// Count total backups per agent.
    func backupCountPerAgent() -> [(agent: String, count: Int)] {
        var counts: [(String, Int)] = []
        for agent in agentManager.allAgents {
            guard agent.exists else { continue }
            let contents = (try? fileManager.contentsOfDirectory(atPath: agent.path)) ?? []
            let count = contents.filter { $0.contains(".backup-") }.count
            if count > 0 {
                counts.append((agent.label, count))
            }
        }
        return counts
    }

    /// Delete all backup residuals.
    func deleteAll() -> Int {
        let backups = scanBackups()
        var deleted = 0

        for backup in backups {
            do {
                try fileManager.removeItem(atPath: backup.path)
                deleted += 1
            } catch {
                print("Failed to delete \(backup.path): \(error)")
            }
        }

        return deleted
    }

    /// Delete backups for a specific agent.
    func deleteForAgent(_ agent: AgentConfig) -> Int {
        guard agent.exists else { return 0 }
        var deleted = 0

        guard let contents = try? fileManager.contentsOfDirectory(atPath: agent.path) else {
            return 0
        }

        for item in contents where item.contains(".backup-") {
            let fullPath = (agent.path as NSString).appendingPathComponent(item)
            do {
                try fileManager.removeItem(atPath: fullPath)
                deleted += 1
            } catch {
                print("Failed to delete \(fullPath): \(error)")
            }
        }

        return deleted
    }
}
