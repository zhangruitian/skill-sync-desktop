import SwiftUI

// MARK: - Terminal Page View (inline content, no modal)

/// Copy of TerminalView without the modal Close button and frame constraints,
/// rendered as inline page content instead of a sheet.
struct TerminalPageView: View {
    @ObservedObject var model: SkillHubViewModel
    @State private var output: String = ""
    @State private var isRunning = false
    @State private var selectedCommand: String = "status"

    private let ds = DesignSystem.self

    private let commands = [
        ("status", "Show sync status"),
        ("sync", "Sync all skills"),
        ("diff", "Show differences"),
        ("unlink", "Remove a skill from all agents"),
        ("clean-backups", "Clean backup residuals"),
        ("help", "Show help"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 13))
                    .foregroundColor(ds.Colors.primary)
                Text("Terminal — sync-skills.sh")
                    .font(ds.Typography.headlineMD)
                    .foregroundColor(ds.Colors.textPrimary)
                Spacer()
            }
            .padding(.bottom, 12)

            // Command row
            HStack(spacing: 8) {
                Text("$").font(.system(size: 12, design: .monospaced)).foregroundColor(ds.Colors.primary)
                Text("./sync-skills.sh").font(.system(size: 12, design: .monospaced)).foregroundColor(ds.Colors.textPrimary)
                Picker("", selection: $selectedCommand) {
                    ForEach(commands, id: \.0) { cmd, _ in
                        Text(cmd).tag(cmd)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
                .labelsHidden()

                if !selectedCommand.isEmpty {
                    Text("--hub").font(.system(size: 12, design: .monospaced)).foregroundColor(ds.Colors.textSecondary)
                    Text(model.settings.hubRootPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ds.Colors.outline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 180)
                }

                Spacer()

                Button(action: runCommand) {
                    HStack(spacing: 4) {
                        Image(systemName: isRunning ? "stop.circle" : "play.circle")
                            .font(.system(size: 12))
                        Text(isRunning ? "Stop" : "Run")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(ds.Colors.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(ds.Colors.surfaceHigh)
                    .cornerRadius(ds.Shapes.small)
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(ds.Colors.surfaceContainer)
            .cornerRadius(ds.Shapes.medium)

            // Output area
            ScrollViewReader { proxy in
                ScrollView {
                    if output.isEmpty && !isRunning {
                        VStack(spacing: 8) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 24))
                                .foregroundColor(ds.Colors.textSecondary)
                            Text("Select a command and press Run")
                                .font(ds.Typography.bodySM)
                                .foregroundColor(ds.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        Text(output)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(ds.Colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .textSelection(.enabled)
                    }
                }
                .onChange(of: output) { _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
                Color.clear.frame(height: 1).id("bottom")
            }
        }
    }

    private func runCommand() {
        guard !isRunning else { return }
        let hubPath = (model.settings.hubRootPath as NSString).expandingTildeInPath
        let scriptPath = (hubPath as NSString).appendingPathComponent("sync-skills.sh")
        let fm = FileManager.default

        guard fm.fileExists(atPath: scriptPath) else {
            output = "Error: sync-skills.sh not found at \(scriptPath)"
            return
        }

        isRunning = true
        output += "[\(timestamp())] Running: ./sync-skills.sh --hub \(hubPath) \(selectedCommand)\n"

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [scriptPath, "--hub", hubPath, selectedCommand]
            task.environment = ["PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let str = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self.output += str
                    }
                }
            }

            do {
                try task.run()
                task.waitUntilExit()
                DispatchQueue.main.async {
                    self.output += "\n[\(self.timestamp())] Exit code: \(task.terminationStatus)\n"
                    self.isRunning = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.output += "\nError: \(error.localizedDescription)\n"
                    self.isRunning = false
                }
            }
        }
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}

// MARK: - Preview

#Preview {
    TerminalPageView(model: SkillHubViewModel())
}
