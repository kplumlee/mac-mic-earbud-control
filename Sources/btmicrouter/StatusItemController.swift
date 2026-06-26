import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    init(model: AppModel) {
        super.init()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 560)
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Bluetooth Mic Router")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // Update the menu-bar glyph + tint to reflect state.
    func updateIcon(meeting: Bool, routing: Bool, paused: Bool) {
        guard let button = statusItem.button else { return }
        let symbol: String
        if paused { symbol = "pause.circle" }
        else if meeting { symbol = "record.circle" }
        else if routing { symbol = "mic.fill" }
        else { symbol = "mic" }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Bluetooth Mic Router")
        button.contentTintColor = meeting ? .systemRed : nil
    }
}
