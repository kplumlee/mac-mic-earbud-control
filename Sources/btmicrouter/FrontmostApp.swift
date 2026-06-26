import AppKit

enum FrontmostApp {
    static func bundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
