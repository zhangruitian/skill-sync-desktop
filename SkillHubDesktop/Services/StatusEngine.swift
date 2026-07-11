import Foundation

// MARK: - Status Engine

/// Computes the sync state of each skill on each agent platform.
final class StatusEngine: @unchecked Sendable {
    private let hubManager: HubManager
    private let agentManager: AgentManager
    private let fileManager = FileManager.default

    init(hubManager: HubManager, agentManager: AgentManager) {
        self.hubManager = hubManager
        self.agentManager = agentManager
    }

    /// Compute the full skill × agent state matrix.
    /// Returns an array of SkillInfo with states populated for all agents.
    func computeAllStates() -> [SkillInfo] {
        let skills = hubManager.scanSkills()
        let agents = agentManager.allAgents

        return skills.map { skillName in
            let hubPath = hubManager.skillPath(for: skillName)
            var states: [String: SyncState] = [:]
            var staleDetails: [String: StaleLinkDetail] = [:]

            for agent in agents {
                let agentSkillPath = agentManager.skillPath(for: skillName, agent: agent)
                let (state, detail) = computeStateWithDetail(
                    hubPath: hubPath,
                    agentPath: agentSkillPath
                )
                states[agent.label] = state
                if let d = detail { staleDetails[agent.label] = d }
            }

            // Get last modified date
            let lastModified = try? fileManager.attributesOfItem(atPath: hubPath)[.modificationDate] as? Date

            return SkillInfo(
                name: skillName,
                hubPath: hubPath,
                states: states,
                staleDetails: staleDetails,
                lastModified: lastModified
            )
        }
    }

    /// Compute external skills — skills present on agents but not in the hub.
    /// Returns a dictionary mapping agent label to list of skill names.
    func computeExternalSkills(hubSkillNames: Set<String>? = nil) -> [String: [(name: String, path: String, isSymlink: Bool)]] {
        let hubSkills = hubSkillNames ?? Set(hubManager.scanSkills())
        var result: [String: [(name: String, path: String, isSymlink: Bool)]] = [:]

        for agent in agentManager.activeAgents {
            let agentSkills = agentManager.listSkills(in: agent)
            let externals = agentSkills.filter { !hubSkills.contains($0) }

            if !externals.isEmpty {
                let details: [(name: String, path: String, isSymlink: Bool)] = externals.map { name in
                    let fullPath = (agent.path as NSString).appendingPathComponent(name)
                    let isSymlink = (try? fileManager.destinationOfSymbolicLink(atPath: fullPath)) != nil
                    return (name: name, path: fullPath, isSymlink: isSymlink)
                }
                result[agent.label] = details
            }
        }

        return result
    }

    /// Determine the sync state for a single skill + agent combination,
    /// returning both the state and optional stale-link detail.
    func computeStateWithDetail(hubPath: String, agentPath: String) -> (SyncState, StaleLinkDetail?) {
        // 1. Check if it's a symbolic link
        if let linkTarget = try? fileManager.destinationOfSymbolicLink(atPath: agentPath) {
            let resolvedLink = resolvePath(linkTarget, relativeTo: agentPath)
            let resolvedHub = resolveAbsolute(hubPath)

            if resolvedLink == resolvedHub {
                return (.link, nil)
            } else {
                let detail = StaleLinkDetail(
                    currentTarget: linkTarget,
                    resolvedTarget: resolvedLink,
                    expectedTarget: hubPath,
                    resolvedExpected: resolvedHub
                )
                return (.linkStale, detail)
            }
        }

        // 2. Check if directory exists (not a symlink)
        var isDir: ObjCBool = false
        let exists = fileManager.fileExists(atPath: agentPath, isDirectory: &isDir)

        if !exists {
            return (.notFound, nil)
        }

        guard isDir.boolValue else {
            return (.error, nil)
        }

        // 3. Compare content
        if directoriesEquivalent(hubPath, agentPath) {
            return (.copy, nil)
        } else {
            return (.outdated, nil)
        }
    }

    // MARK: - Helpers

    /// Convenience: compute just the state (backward compatibility).
    func computeState(hubPath: String, agentPath: String) -> SyncState {
        let (state, _) = computeStateWithDetail(hubPath: hubPath, agentPath: agentPath)
        return state
    }

    /// Resolve an absolute path (expand tilde, resolve symlinks).
    private func resolveAbsolute(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return (expanded as NSString).resolvingSymlinksInPath
    }

    /// Resolve a possibly-relative path against a base directory.
    private func resolvePath(_ target: String, relativeTo base: String) -> String {
        let baseDir = (base as NSString).deletingLastPathComponent
        let expanded = (target as NSString).expandingTildeInPath

        if (target as NSString).isAbsolutePath {
            return (expanded as NSString).resolvingSymlinksInPath
        }

        let absolute = (baseDir as NSString).appendingPathComponent(expanded)
        return (absolute as NSString).resolvingSymlinksInPath
    }

    /// Quick comparison: first SKILL.md, then full directory (ignoring dev files).
    private func directoriesEquivalent(_ hubPath: String, _ agentPath: String) -> Bool {
        let settings = AppSettings.shared
        let hubSkillMD = (hubPath as NSString).appendingPathComponent("SKILL.md")
        let agentSkillMD = (agentPath as NSString).appendingPathComponent("SKILL.md")

        guard fileManager.fileExists(atPath: agentSkillMD) else { return false }

        // Quick check: SKILL.md
        if !filesEqual(hubSkillMD, agentSkillMD) { return false }

        // Full comparison with exclusions
        return directoriesEqual(hubPath, agentPath, ignore: settings.ignoreGlobs)
    }

    /// Compare two files byte-for-byte.
    private func filesEqual(_ path1: String, _ path2: String) -> Bool {
        guard let data1 = try? Data(contentsOf: URL(fileURLWithPath: path1)),
              let data2 = try? Data(contentsOf: URL(fileURLWithPath: path2)) else {
            return false
        }
        return data1 == data2
    }

    /// Compare two directories ignoring specified patterns.
    private func directoriesEqual(_ dir1: String, _ dir2: String, ignore: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
        var args = ["-rq"]
        for pattern in ignore {
            args.append("-x")
            args.append(pattern)
        }
        args.append(dir1)
        args.append(dir2)
        task.arguments = args

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        try? task.run()
        task.waitUntilExit()

        return task.terminationStatus == 0
    }
}
