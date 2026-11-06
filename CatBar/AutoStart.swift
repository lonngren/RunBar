import Foundation

/// Manages the "launch at login" behaviour via a LaunchAgent plist.
///
/// A LaunchAgent is used rather than `SMAppService` because this app is often
/// run straight out of the build directory, where a login item would not be
/// permitted anyway.
enum AutoStart {

    private static let label = "com.workbuddy.catbar"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            enable()
        } else {
            disable()
        }
    }

    private static func enable() {
        let executable = Bundle.main.executableURL?.path ?? ""
        let dictionary: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive"
        ]

        let data = try? PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )

        guard let data else { return }
        try? FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? data.write(to: plistURL)

        // Ask launchd to pick it up straight away.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", "-w", plistURL.path]
        try? process.run()
        process.waitUntilExit()
    }

    private static func disable() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", "-w", plistURL.path]
        try? process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(at: plistURL)
    }
}
