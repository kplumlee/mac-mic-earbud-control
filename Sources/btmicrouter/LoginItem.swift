import Foundation
import os

private let loginItemLog = Logger(subsystem: "com.kplumlee.btmicrouter", category: "LoginItem")

enum LoginItem {
    static let label = "com.kplumlee.btmicrouter"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            install()
        } else {
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    private static func install() {
        let rawPath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let binaryPath = URL(fileURLWithPath: rawPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        if binaryPath.contains("/.build/") || binaryPath.contains("/DerivedData/") {
            loginItemLog.warning(
                "Login item points at a non-stable build path: \(binaryPath, privacy: .public). Run the app from a stable location (e.g. ~/Applications) as described in the README."
            )
        }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [binaryPath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
        ]
        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: plistURL, options: .atomic)
        }
    }
}
