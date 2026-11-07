import AppKit

if CommandLine.arguments.contains("--login-status") {
    LoginAgent.report()
    exit(0)
}

// `QuadStatus --register-login` (build.sh --install): start at login from this copy.
if CommandLine.arguments.contains("--register-login") {
    do { try LoginAgent.enable() } catch { print("register failed: \(error)"); exit(1) }
    exit(0)
}

// One copy only: a second launch (agent plus a manual open, say) would add a second icon.
if let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id)
       .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)     // keeps it out of the Dock and Cmd-Tab

let delegate = AppDelegate()            // top-level bindings in main.swift are globals, so this holds a strong reference
app.delegate = delegate
app.run()
