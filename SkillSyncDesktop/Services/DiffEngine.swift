import Foundation

// MARK: - Diff Engine

/// Computes file-level and content-level differences between hub source and agent copy.
final class DiffEngine {
    private let settings = AppSettings.shared
    private let fileManager = FileManager.default

    /// A single file difference entry.
    struct FileDiff: Identifiable {
        var id: String { relativePath }

        /// Path relative to the skill root
        let relativePath: String
        /// Type of difference
        let type: DiffType
        /// Optional description (e.g. "Files differ")
        let description: String
        /// Content-level diff hunks (only for .different type)
        let hunks: [DiffHunk]
    }

    /// A single hunk of diff output, analogous to unified diff hunks.
    struct DiffHunk: Identifiable, Codable {
        var id: String { "\(oldStart)-\(newStart)" }

        let oldStart: Int
        let oldCount: Int
        let newStart: Int
        let newCount: Int
        let header: String
        let lines: [DiffLine]
    }

    /// A single line within a diff hunk.
    struct DiffLine: Identifiable, Codable {
        var id: String { "\(type):\(content.hashValue)" }

        enum LineType: String, Codable {
            case context   // unchanged
            case added     // + (only in agent / added line)
            case removed   // - (only in hub / removed line)
            case header    // hunk header
        }

        let type: LineType
        let content: String
        let oldLineNumber: Int?
        let newLineNumber: Int?
    }

    enum DiffType: String {
        case onlyInHub   = "仅在Hub"
        case onlyInAgent = "仅在Agent端"
        case different   = "内容不同"
        case identical   = "完全相同"
    }

    /// Diff a skill between hub and an agent.
    /// Returns a list of file differences, empty if identical.
    func diff(skillName: String, hubPath: String, agentPath: String) -> [FileDiff] {
        var diffs: [FileDiff] = []

        guard fileManager.fileExists(atPath: agentPath) else {
            return [FileDiff(relativePath: skillName, type: .onlyInHub, description: "Agent端不存在", hunks: [])]
        }

        // Check if symlink
        if let _ = try? fileManager.destinationOfSymbolicLink(atPath: agentPath) {
            return [] // Symlinks don't need diff
        }

        let hubFiles = collectFiles(in: hubPath)
        let agentFiles = collectFiles(in: agentPath)

        // Files only in hub
        for file in hubFiles {
            if !agentFiles.contains(file) {
                if !shouldIgnore(file) {
                    diffs.append(FileDiff(relativePath: file, type: .onlyInHub, description: "Agent端缺失", hunks: []))
                }
            }
        }

        // Files only in agent
        for file in agentFiles {
            if !hubFiles.contains(file) {
                diffs.append(FileDiff(relativePath: file, type: .onlyInAgent, description: "Hub中不存在", hunks: []))
            }
        }

        // Files that differ — compute content-level diff
        for file in hubFiles {
            if agentFiles.contains(file) && !shouldIgnore(file) {
                let hubFile = (hubPath as NSString).appendingPathComponent(file)
                let agentFile = (agentPath as NSString).appendingPathComponent(file)
                if !filesEqual(hubFile, agentFile) {
                    let hunks = computeContentDiff(hubFile: hubFile, agentFile: agentFile)
                    diffs.append(FileDiff(relativePath: file, type: .different, description: "文件内容不同", hunks: hunks))
                }
            }
        }

        return diffs.sorted { $0.relativePath < $1.relativePath }
    }

    /// Compute unified-diff-style hunks between two text files.
    func computeContentDiff(hubFile: String, agentFile: String) -> [DiffHunk] {
        guard let hubLines = try? String(contentsOfFile: hubFile, encoding: .utf8).components(separatedBy: .newlines),
              let agentLines = try? String(contentsOfFile: agentFile, encoding: .utf8).components(separatedBy: .newlines) else {
            return []
        }

        // Strip trailing empty line from components(separatedBy:)
        let a = hubLines.last?.isEmpty == true ? Array(hubLines.dropLast()) : hubLines
        let b = agentLines.last?.isEmpty == true ? Array(agentLines.dropLast()) : agentLines

        let ops = computeLCSDiff(a: a, b: b)
        return buildHunks(ops: ops, a: a, b: b)
    }

    // MARK: — Content Diff Implementation (LCS-based, Myers-like)

    /// Simple LCS-based diff producing edit operations.
    private func computeLCSDiff(a: [String], b: [String]) -> [DiffOp] {
        let m = a.count
        let n = b.count

        // Build LCS table
        var dp = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to produce edit script
        var ops: [DiffOp] = []
        var i = m, j = n
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && a[i - 1] == b[j - 1] {
                ops.append(.equal(i - 1, j - 1))
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                ops.append(.insert(j - 1))
                j -= 1
            } else {
                ops.append(.delete(i - 1))
                i -= 1
            }
        }
        return ops.reversed()
    }

    private enum DiffOp {
        case equal(Int, Int)
        case delete(Int)
        case insert(Int)
    }

    /// Group edit operations into unified-diff-style hunks with 3 lines of context.
    private func buildHunks(ops: [DiffOp], a: [String], b: [String]) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var changes: [(type: DiffLine.LineType, aIdx: Int?, bIdx: Int?, content: String)] = []

        for (idx, op) in ops.enumerated() {
            switch op {
            case .equal(let ai, let bi):
                // Check if within context window of a change
                let nearChange = isNearChange(ops: ops, currentIdx: idx, window: 3)
                if nearChange {
                    changes.append((.context, ai, bi, a[ai]))
                } else if !changes.isEmpty {
                    // Consumed by hunk grouping below
                }
            case .delete(let ai):
                changes.append((.removed, ai, nil, a[ai]))
            case .insert(let bi):
                changes.append((.added, nil, bi, b[bi]))
            }
        }

        // Build hunks from accumulated changes
        guard !changes.isEmpty else { return hunks }

        // Split changes into groups separated by >6 lines of context gap
        var currentGroup: [(type: DiffLine.LineType, aIdx: Int?, bIdx: Int?, content: String)] = []
        for change in changes {
            if currentGroup.isEmpty {
                currentGroup.append(change)
            } else {
                let lastA = currentGroup.last?.aIdx ?? 0
                let thisA = change.aIdx ?? lastA
                if thisA - lastA > 6 {
                    if !currentGroup.allSatisfy({ $0.type == .context }) {
                        hunks.append(makeHunk(changes: currentGroup, a: a, b: b))
                    }
                    currentGroup = [change]
                } else {
                    currentGroup.append(change)
                }
            }
        }
        if !currentGroup.isEmpty && !currentGroup.allSatisfy({ $0.type == .context }) {
            hunks.append(makeHunk(changes: currentGroup, a: a, b: b))
        }

        return hunks
    }

    private func isNearChange(ops: [DiffOp], currentIdx: Int, window: Int) -> Bool {
        let start = max(0, currentIdx - window)
        let end = min(ops.count - 1, currentIdx + window)
        for i in start...end {
            switch ops[i] {
            case .delete, .insert: return true
            default: continue
            }
        }
        return false
    }

    private func makeHunk(changes: [(type: DiffLine.LineType, aIdx: Int?, bIdx: Int?, content: String)], a: [String], b: [String]) -> DiffHunk {
        let aIndices = changes.compactMap(\.aIdx)
        let bIndices = changes.compactMap(\.bIdx)
        let oldStart = (aIndices.min() ?? 0) + 1  // 1-indexed
        let oldCount = ((aIndices.max() ?? 0) - (aIndices.min() ?? 0) + 1)
        let newStart = (bIndices.min() ?? 0) + 1  // 1-indexed
        let newCount = ((bIndices.max() ?? 0) - (bIndices.min() ?? 0) + 1)

        let lines: [DiffLine] = changes.map { c in
            DiffLine(
                type: c.type,
                content: c.content,
                oldLineNumber: c.aIdx.map { $0 + 1 },
                newLineNumber: c.bIdx.map { $0 + 1 }
            )
        }

        return DiffHunk(
            oldStart: oldStart,
            oldCount: oldCount,
            newStart: newStart,
            newCount: newCount,
            header: "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@",
            lines: lines
        )
    }

    /// Collect relative file paths from a directory, ignoring patterns.
    private func collectFiles(in root: String) -> Set<String> {
        var files = Set<String>()

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return files
        }

        for case let fileURL as URL in enumerator {
            let relative = fileURL.path.replacingOccurrences(of: root + "/", with: "")
            if shouldIgnore(relative) {
                enumerator.skipDescendants()
                continue
            }

            files.insert(relative)
        }

        return files
    }

    /// Check if a relative file/folder path matches any ignore pattern.
    /// Patterns are matched against each path component, matching shell
    /// glob semantics — a pattern like "docs" matches a component named
    /// "docs" at any depth.
    private func shouldIgnore(_ relativePath: String) -> Bool {
        let components = relativePath.components(separatedBy: "/")
        for pattern in settings.ignoreGlobs {
            for component in components {
                if component == pattern {
                    return true
                }
            }
        }
        return false
    }

    private func filesEqual(_ path1: String, _ path2: String) -> Bool {
        guard let data1 = try? Data(contentsOf: URL(fileURLWithPath: path1)),
              let data2 = try? Data(contentsOf: URL(fileURLWithPath: path2)) else {
            return false
        }
        return data1 == data2
    }
}
