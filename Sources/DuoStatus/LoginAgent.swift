import Foundation
import ServiceManagement

/// Starts DuoStatus with the user session through a plain LaunchAgent in
/// ~/Library/LaunchAgents.
///
/// Not `SMAppService.agent`: launchd pins such an agent to a launch constraint
/// that an ad-hoc signed app never satisfies (spawn fails with
/// OS_REASON_CODESIGNING, observed on macOS 27.0.1). Not `SMAppService.mainApp`
/// either: loginwindow starts login items only late. A user LaunchAgent starts
/// as soon as the session does and points at the executable by path, so it
/// survives rebuilds; it only needs rewriting when the app moves.
///
/// Its label differs from the SMAppService agent's on purpose: Background Task
/// Management can keep resubmitting that agent at login even after it was
/// unregistered, and with a shared label the resubmitted job replaced this one
/// and was killed (Launch Constraint Violation, seen on 2026-11-07).
enum LoginAgent {
    /// Label of the SMAppService agent of earlier versions (its plist ships in the
    /// bundle so it can still be unregistered) and of the first plain agent.
    private static let oldLabel = "io.github.zhenweiding-dev.duostatus"
    static let label = oldLabel + ".login"

    private static func plistURL(_ label: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    private static var plistURL: URL { plistURL(label) }

    private static var smAgent: SMAppService { SMAppService.agent(plistName: "\(oldLabel).plist") }

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
        dropOlderRegistrations()
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

    /// Run at every launch: moves older registrations over to this agent and
    /// points the agent at this copy if the app has moved.
    static func migrate() {
        let wanted = isEnabled || dropOlderRegistrations()
        if wanted, installedProgram != executable {
            try? enable()
        }
    }

    /// Removes every earlier way of starting at login: the SMAppService login item,
    /// the SMAppService agent and the first plain agent under the old label.
    /// Returns whether any of them was set up. Failures go to stderr.
    @discardableResult
    private static func dropOlderRegistrations() -> Bool {
        var found = false
        // Not only `.enabled`: an agent awaiting approval or in another state
        // still sits in Background Task Management and gets submitted at login.
        for service in [SMAppService.mainApp, smAgent] where service.status != .notRegistered {
            found = found || service.status == .enabled
            do { try service.unregister() } catch { warn("unregister failed: \(error)") }
        }
        launchctl(["bootout", "\(domain)/\(oldLabel)"])
        let oldPlist = plistURL(oldLabel)
        if FileManager.default.fileExists(atPath: oldPlist.path) {
            found = true
            do { try FileManager.default.trashItem(at: oldPlist, resultingItemURL: nil) }
            catch { warn("could not remove \(oldPlist.path): \(error)") }
        }
        return found
    }

    /// `DuoStatus --login-status`: what is set up to start this app at login.
    static func report() {
        let names: [SMAppService.Status: String] = [
            .notRegistered: "notRegistered", .enabled: "enabled",
            .requiresApproval: "requiresApproval", .notFound: "notFound",
        ]
        print("SMAppService.mainApp: \(names[SMAppService.mainApp.status] ?? "?")")
        print("SMAppService.agent:   \(names[smAgent.status] ?? "?")")
        print("old plain agent plist: \(FileManager.default.fileExists(atPath: plistURL(oldLabel).path))")
        print("plain agent \(label): \(installedProgram ?? "not installed")")
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
