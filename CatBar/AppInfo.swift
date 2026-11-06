import Foundation

/// The app's identity: its version, its author, and when it was built.
enum AppInfo {

    /// The version number, shown in the settings window.
    static let version = "1.0"

    /// Who made it.
    static let author = "龙少"

    /// Which settings tab to open on.
    ///
    /// Read from a `--tab` argument, which makes it possible to open a
    /// particular page straight from the command line.
    static let initialTab: Int = {
        guard let index = CommandLine.arguments.firstIndex(of: "--tab"),
              index + 1 < CommandLine.arguments.count,
              let value = Int(CommandLine.arguments[index + 1]) else {
            return 0
        }
        return value
    }()

    /// The build date, so the window shows when this copy was made.
    ///
    /// It is read from the bundle's modification date rather than kept as a
    /// literal, so it never goes stale.
    static let buildDate: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let url = Bundle.main.bundleURL
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let date = attributes?[.modificationDate] as? Date ?? Date()
        return formatter.string(from: date)
    }()
}
