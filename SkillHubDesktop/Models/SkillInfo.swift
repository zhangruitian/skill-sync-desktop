import Foundation

/// Represents a single skill in the hub, with its sync state across all agents.
struct SkillInfo: Identifiable {
    var id: String { name }

    /// Skill directory name
    let name: String
    /// Absolute path to the skill in the hub
    let hubPath: String
    /// Sync state per agent (keyed by agent label)
    var states: [String: SyncState]
    /// Stale link detail per agent (keyed by agent label), only present when linkStale
    var staleDetails: [String: StaleLinkDetail]
    /// Last modification time of the hub skill
    var lastModified: Date?

    /// Whether this skill is synced consistently across all active agents
    var isFullySynced: Bool {
        states.values.allSatisfy { $0 == .link || $0 == .copy }
    }
}
