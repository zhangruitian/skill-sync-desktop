import Foundation

/// Represents the sync state of a skill on a specific agent platform.
enum SyncState: String, CaseIterable, Codable {
    /// Symbolic link pointing to the correct hub source
    case link
    /// Symbolic link but pointing to a wrong/non-hub location
    case linkStale
    /// Copied directory, content matches hub
    case copy
    /// Copied directory, content differs from hub
    case outdated
    /// Not installed on this agent
    case notFound
    /// Unable to determine state
    case error

    /// Human-readable label (matching script output)
    var label: String {
        switch self {
        case .link:      return "link"
        case .linkStale: return "link(stale)"
        case .copy:      return "copy"
        case .outdated:  return "outdated"
        case .notFound:  return "-"
        case .error:     return "?"
        }
    }

    /// SF Symbol name for the status icon
    var iconName: String {
        switch self {
        case .link:      return "link"
        case .linkStale: return "link.badge.exclamationmark"
        case .copy:      return "doc.on.doc"
        case .outdated:  return "clock.badge.exclamationmark"
        case .notFound:  return "circle.dashed"
        case .error:     return "exclamationmark.triangle"
        }
    }
}

/// Detail information for a stale symbolic link.
struct StaleLinkDetail: Codable, Equatable {
    /// The raw symlink target (may be relative)
    let currentTarget: String
    /// Fully resolved current target path
    let resolvedTarget: String
    /// Expected symlink target (hub source path)
    let expectedTarget: String
    /// Fully resolved expected path
    let resolvedExpected: String
}

/// Installation mode for syncing skills.
enum InstallMode: String, CaseIterable, Codable {
    case link = "link"
    case copy = "copy"

    var displayName: String {
        switch self {
        case .link: return "软链 (推荐开发)"
        case .copy: return "复制 (推荐分发)"
        }
    }
}
