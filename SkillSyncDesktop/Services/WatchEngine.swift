import Foundation
import Combine

// MARK: - Watch Engine

/// Watches the hub directory for changes using FSEvents and auto-syncs to agents.
final class WatchEngine: ObservableObject {
    private let hubManager: HubManager
    private let agentManager: AgentManager
    private let syncEngine: SyncEngine
    private let settings = AppSettings.shared

    @Published var isRunning = false
    @Published var lastEvent: String = ""
    @Published var lastSyncTime: Date?
    @Published var logEntries: [String] = []

    /// Called when a sync completes; delivers results.
    var onSync: (([SyncEngine.SyncResult]) -> Void)?

    private var stream: FileSystemEventStream?
    private var debounceTimers: [String: DispatchWorkItem] = [:]
    private let debounceQueue = DispatchQueue(label: "skillsync.watch.debounce")
    private let debounceInterval: TimeInterval = 2.0

    init(hubManager: HubManager, agentManager: AgentManager) {
        self.hubManager = hubManager
        self.agentManager = agentManager
        self.syncEngine = SyncEngine(hubManager: hubManager, agentManager: agentManager)
    }

    /// Start watching the hub directory.
    func start() {
        guard !isRunning, hubManager.hubExists else { return }

        isRunning = true
        lastEvent = "开始监听: \(hubManager.hubRoot)"
        logEntries.append("[INFO] Watch started: \(hubManager.hubRoot)")

        // Initial full sync (matches shell script: cmd_watch runs cmd_sync --yes first)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let results = self.syncEngine.sync(
                skills: self.hubManager.scanSkills(),
                mode: self.settings.defaultInstallMode,
                agents: self.agentManager.allAgents
            )
            DispatchQueue.main.async {
                self.lastEvent = "[\(Date().formatted(date: .omitted, time: .standard))] 初始全量同步完成 (\(results.count) actions)"
                self.lastSyncTime = Date()
                self.logEntries.append("[SYNC] Initial sync done: \(results.count) actions")
                self.onSync?(results)
            }
        }

        stream = FileSystemEventStream(
            pathsToWatch: [hubManager.hubRoot],
            latency: 1.0
        )

        stream?.setEventHandler { [weak self] in
            self?.handleEvents()
        }

        stream?.setDispatchQueue(debounceQueue)
        stream?.start()
    }

    /// Stop watching.
    func stop() {
        isRunning = false
        stream?.stop()
        stream = nil
        debounceTimers.values.forEach { $0.cancel() }
        debounceTimers.removeAll()
        lastEvent = "监听已停止"
        logEntries.append("[INFO] Watch stopped")
    }

    // MARK: - Private

    /// Check if a path should be ignored during watch (matches shell script fswatch excludes).
    private func shouldWatch(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        let settings = self.settings

        // Exclude hidden files/dirs
        if name.hasPrefix(".") { return false }
        // Exclude backup residues
        if name.hasPrefix("backup-") || name.contains(".backup-") { return false }
        // Exclude sync ignore globs
        for pattern in settings.ignoreGlobs {
            if name == pattern { return false }
        }
        // Exclude regex patterns from excludePatterns
        for pattern in settings.excludePatterns {
            if name.range(of: pattern, options: .regularExpression) != nil { return false }
        }
        return true
    }

    private func handleEvents() {
        let hubRoot = hubManager.hubRoot
        let skills = hubManager.scanSkills()

        var changedSkills = Set<String>()

        for skill in skills {
            let skillPath = (hubRoot as NSString).appendingPathComponent(skill)
            guard shouldWatch(skillPath) else { continue }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: skillPath),
               let modDate = attrs[.modificationDate] as? Date {
                if Date().timeIntervalSince(modDate) < 5 {
                    changedSkills.insert(skill)
                }
            }

            let skillMDPath = (skillPath as NSString).appendingPathComponent("SKILL.md")
            if let attrs = try? FileManager.default.attributesOfItem(atPath: skillMDPath),
               let modDate = attrs[.modificationDate] as? Date {
                if Date().timeIntervalSince(modDate) < 5 {
                    changedSkills.insert(skill)
                }
            }
        }

        for skill in changedSkills {
            debounceQueue.async { [weak self] in
                self?.scheduleSync(for: skill)
            }
        }

        if changedSkills.isEmpty {
            // No skills changed within the 5s window. Skip — do NOT fall back
            // to a full sync, which would be catastrophic in watch mode
            // (any FSEvents noise would trigger sync-all).
            return
        }
    }

    private func scheduleSync(for skill: String) {
        debounceTimers[skill]?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.performSync(for: skill)
        }

        debounceTimers[skill] = workItem
        debounceQueue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func performSync(for skill: String) {
        let mode = settings.defaultInstallMode
        let results = syncEngine.sync(
            skills: [skill],
            mode: mode,
            agents: agentManager.allAgents
        )

        DispatchQueue.main.async { [weak self] in
            let msg = "[\(Date().formatted(date: .omitted, time: .standard))] \(skill) 已同步"
            self?.lastEvent = msg
            self?.lastSyncTime = Date()
            self?.logEntries.append("[SYNC] \(skill) synced successfully")
            self?.onSync?(results)
        }
    }

    deinit {
        stop()
    }
}

// MARK: - FSEvents wrapper

/// Minimal FSEvents wrapper for Swift using CoreFoundation C API.
private final class FileSystemEventStream {
    private var stream: FSEventStreamRef?
    private let pathsToWatch: [String]
    private let latency: CFTimeInterval
    private let flags: FSEventStreamCreateFlags

    private var callback: (() -> Void)?

    init(
        pathsToWatch: [String],
        sinceEventIdentifier: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        latency: CFTimeInterval = 1.0,
        flags: FSEventStreamCreateFlags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
    ) {
        self.pathsToWatch = pathsToWatch
        self.latency = latency
        self.flags = flags
    }

    func setEventHandler(_ handler: @escaping () -> Void) {
        callback = handler
    }

    func setDispatchQueue(_ queue: DispatchQueue) {
        guard let stream = stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
    }

    func start() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { (_, info, _, _, _, _) in
            guard let info = info else { return }
            let watcher = Unmanaged<FileSystemEventStream>.fromOpaque(info).takeUnretainedValue()
            watcher.callback?()
        }

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        )

        // Use the non-deprecated DispatchQueue-based scheduling
        FSEventStreamSetDispatchQueue(stream!, DispatchQueue.main)
        FSEventStreamStart(stream!)
    }

    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}
