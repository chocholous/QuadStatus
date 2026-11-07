import Foundation

/// Starts QuadStatus with the user session through a plain LaunchAgent in
/// ~/Library/LaunchAgents.
///
/// Not `SMAppService.agent`: launchd pins such an agent to a launch constraint
/// that an ad-hoc signed app never satisfies (killed with "Launch Constraint
/// Violation", observed on macOS 27.0.1). Not `SMAppService.mainApp` either:
/// loginwindow starts login items only late. A user LaunchAgent starts as soon
/// as the session does and points at the executable by path, so it survives
/// rebuilds; it only needs rewriting when the app moves.
enum LoginAgent {
    static let label = "io.github.chocholous.quadstatus.login"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    private static var executable: String? { Bundle.main.executablePath }

    private static var domain: String { "gui/\(getuid())" }

    /// The program the installed plist starts, if there is one.
    private static var installedProgram: String? {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let args = plist["ProgramArguments"] as? [String] else { return nil }
        return args.first
    }

    static var isEnabled: Bool { installedProgram != nil }

    static func enable() throws {
        guard let exe = executable else { throw CocoaError(.fileNoSuchFile) }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exe],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
        // Load it now as well, so the setting does not wait for the next login. RunAtLoad
        // starts a second copy, which the single-instance check in main.swift ends at once.
        launchctl(["bootout", "\(domain)/\(label)"])
        try runLaunchctl(["bootstrap", domain, plistURL.path], check: true)
    }

    static func disable() throws {
        launchctl(["bootout", "\(domain)/\(label)"])
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.trashItem(at: plistURL, resultingItemURL: nil)
        }
    }

    /// Run at every launch: points the agent at this copy if the app has moved.
    static func migrate() {
        if isEnabled, installedProgram != executable {
            do { try enable() } catch { warn("could not update the login agent: \(error)") }
        }
    }

    /// `QuadStatus --login-status`: what is set up to start this app at login.
    static func report() {
        print("login agent \(label): \(installedProgram ?? "not installed")")
    }

    private static func warn(_ message: String) {
        FileHandle.standardError.write(Data("LoginAgent: \(message)\n".utf8))
    }

    @discardableResult
    private static func runLaunchctl(_ args: [String], check: Bool) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        if check, p.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "launchctl", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "launchctl \(args.joined(separator: " ")): \(msg)"])
        }
        return p.terminationStatus
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        (try? runLaunchctl(args, check: false)) ?? -1
    }
}
