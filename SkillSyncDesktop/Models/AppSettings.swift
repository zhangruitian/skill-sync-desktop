import Foundation
import Combine

/// Persisted application settings using UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var hubRootPath: String {
        didSet { UserDefaults.standard.set(hubRootPath, forKey: "hubRootPath") }
    }

    @Published var agents: [AgentConfig] {
        didSet {
            if let data = try? JSONEncoder().encode(agents) {
                UserDefaults.standard.set(data, forKey: "agents")
            }
        }
    }

    @Published var defaultInstallMode: InstallMode {
        didSet { UserDefaults.standard.set(defaultInstallMode.rawValue, forKey: "defaultInstallMode") }
    }

    @Published var autoBackup: Bool {
        didSet { UserDefaults.standard.set(autoBackup, forKey: "autoBackup") }
    }

    /// Glob patterns to skip during sync (mapped from SYNC_IGNORE_GLOBS)
    @Published var ignoreGlobs: [String] {
        didSet { UserDefaults.standard.set(ignoreGlobs, forKey: "ignoreGlobs") }
    }

    /// Regex patterns for directories to exclude from hub scan
    @Published var excludePatterns: [String] {
        didSet { UserDefaults.standard.set(excludePatterns, forKey: "excludePatterns") }
    }

    /// Saved hub profiles (name → path), persisted as JSON.
    @Published var hubProfiles: [HubProfile] {
        didSet {
            if let data = try? JSONEncoder().encode(hubProfiles) {
                UserDefaults.standard.set(data, forKey: "hubProfiles")
            }
        }
    }

    private init() {
        let defaults = UserDefaults.standard

        // hub root: default to ~/skill-hub (the conventional location).
        // Must be explicitly configured by the user if different.
        self.hubRootPath = defaults.string(forKey: "hubRootPath") ?? {
            let home = NSHomeDirectory()
            return (home as NSString).appendingPathComponent("skill-hub")
        }()

        // agents: load saved or use defaults
        if let data = defaults.data(forKey: "agents"),
           let decoded = try? JSONDecoder().decode([AgentConfig].self, from: data) {
            self.agents = decoded
        } else {
            self.agents = [
                AgentConfig(label: "claude", path: "~/.claude/skills"),
                AgentConfig(label: "codex", path: "~/.codex/skills"),
                AgentConfig(label: "agents", path: "~/.agents/skills"),
            ]
        }

        self.defaultInstallMode = InstallMode(rawValue: defaults.string(forKey: "defaultInstallMode") ?? "link") ?? .link
        self.autoBackup = defaults.object(forKey: "autoBackup") == nil ? true : defaults.bool(forKey: "autoBackup")

        self.ignoreGlobs = defaults.stringArray(forKey: "ignoreGlobs") ?? [
            ".git", ".gitattributes", ".DS_Store", "LICENSE",
            "README.md", "CHANGELOG.md", "docs", "agents",
            ".github", ".vscode", ".idea",
        ]

        self.excludePatterns = defaults.stringArray(forKey: "excludePatterns") ?? [
            "^docs$", "^scripts$", "^backup-", "\\.backup-", "^\\..*", "^node_modules$",
        ]

        // Hub profiles
        if let data = defaults.data(forKey: "hubProfiles"),
           let decoded = try? JSONDecoder().decode([HubProfile].self, from: data) {
            self.hubProfiles = decoded
        } else {
            self.hubProfiles = []
        }
    }
}
