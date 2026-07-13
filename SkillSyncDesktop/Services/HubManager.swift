import Foundation

// MARK: - Hub Manager

/// Manages the skill hub directory: scanning for skills and applying exclusion rules.
final class HubManager {
    private let settings: AppSettings
    private let fileManager = FileManager.default

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    /// Returns the absolute path to the hub root directory.
    var hubRoot: String {
        (settings.hubRootPath as NSString).expandingTildeInPath
    }

    /// Whether the hub root directory exists on disk.
    var hubExists: Bool {
        fileManager.fileExists(atPath: hubRoot)
    }

    /// Scans the hub directory and returns all valid skill names (alphabetically sorted).
    /// A valid skill is a subdirectory containing a `SKILL.md` file, not matching exclusion patterns.
    /// Result is deduplicated so the same name never appears twice (guards against inode aliasing
    /// from deeply nested symlinks inside the hub).
    func scanSkills() -> [String] {
        guard hubExists else { return [] }

        guard let contents = try? fileManager.contentsOfDirectory(atPath: hubRoot) else {
            return []
        }

        var seen = Set<String>()

        return contents
            .filter { name in
                guard !seen.contains(name) else { return false }
                // Must be a directory
                var isDir: ObjCBool = false
                let fullPath = (hubRoot as NSString).appendingPathComponent(name)
                guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else {
                    return false
                }

                // Must not match any exclude pattern
                for pattern in settings.excludePatterns {
                    if name.range(of: pattern, options: .regularExpression) != nil {
                        return false
                    }
                }

                // Must contain SKILL.md
                let skillMDPath = (fullPath as NSString).appendingPathComponent("SKILL.md")
                guard fileManager.fileExists(atPath: skillMDPath) else { return false }

                seen.insert(name)
                return true
            }
            .sorted()
    }

    /// Returns the absolute path for a given skill in the hub.
    func skillPath(for name: String) -> String {
        (hubRoot as NSString).appendingPathComponent(name)
    }
}
