import Foundation

/// Configuration for a single AI agent platform target.
struct AgentConfig: Identifiable, Codable, Equatable {
    var id: String { label }

    /// Display name (e.g. "claude", "codex", "agents")
    var label: String
    /// Absolute path to the agent's skills directory
    var path: String

    init(label: String, path: String) {
        self.label = label
        self.path = (path as NSString).expandingTildeInPath
    }

    /// Whether the agent directory currently exists on disk.
    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
