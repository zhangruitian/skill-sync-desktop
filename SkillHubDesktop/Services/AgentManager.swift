import Foundation

// MARK: - Agent Manager

/// Manages agent platform configurations: CRUD operations and validation.
final class AgentManager: @unchecked Sendable {
    private let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    /// All configured agents.
    var allAgents: [AgentConfig] {
        settings.agents
    }

    /// Only agents whose directory exists on disk.
    var activeAgents: [AgentConfig] {
        settings.agents.filter { $0.exists }
    }

    /// Add a new agent configuration.
    func addAgent(label: String, path: String) {
        let config = AgentConfig(label: label, path: path)
        settings.agents.append(config)
    }

    /// Remove an agent configuration by label.
    func removeAgent(label: String) {
        settings.agents.removeAll { $0.label == label }
    }

    /// Update an existing agent's path.
    func updateAgent(label: String, path: String) {
        if let index = settings.agents.firstIndex(where: { $0.label == label }) {
            settings.agents[index] = AgentConfig(label: label, path: path)
        }
    }

    /// Get the absolute skill path on a specific agent.
    func skillPath(for skillName: String, agent: AgentConfig) -> String {
        (agent.path as NSString).appendingPathComponent(skillName)
    }

    /// List all skill names installed on a specific agent.
    /// Excludes backup residuals and hidden files.
    func listSkills(in agent: AgentConfig) -> [String] {
        let agentPath = agent.path
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: agentPath) else { return [] }

        guard let contents = try? fileManager.contentsOfDirectory(atPath: agentPath) else { return [] }

        return contents.filter { name in
            guard !name.hasPrefix(".") else { return false }
            guard !name.hasPrefix("backup-") && !name.contains(".backup-") else { return false }

            var isDir: ObjCBool = false
            let fullPath = (agentPath as NSString).appendingPathComponent(name)
            return fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) && isDir.boolValue
        }
    }
}
