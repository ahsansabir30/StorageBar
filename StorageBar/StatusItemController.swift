import AppKit
import Observation
import SwiftUI

/// Owns the menu bar status item, its popover, the right-click menu and the Preferences window.
///
/// Uses `NSStatusItem` rather than `MenuBarExtra` because it gives the item a stable
/// `autosaveName` (so macOS persists its position under a StorageBar-specific key instead of the
/// generic `Item-0`), lets a transient popover close itself on outside clicks, and supports a
/// right-click menu.
@MainActor
final class StatusItemController: NSObject {
    static let autosaveName = "StorageBar"

    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var preferencesWindow: NSWindow?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.autosaveName = Self.autosaveName
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.setAccessibilityIdentifier("menuBarLabel")
        }

        let content = NSHostingController(rootView: PopupView(
            model: model,
            openPreferences: { [weak self] in self?.showPreferences() },
            dismiss: { [weak self] in self?.popover.performClose(nil) }
        ))
        content.sizingOptions = [.preferredContentSize]
        popover.contentViewController = content
        popover.behavior = .transient

        trackModel()
    }

    // MARK: Status item appearance

    /// Re-renders the button whenever anything it reads changes (Observation, no polling).
    private func trackModel() {
        withObservationTracking {
            updateButton()
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackModel() }
        }
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let preferences = model.preferences
        let snapshot = model.monitor.snapshot

        button.title = snapshot.map { preferences.displayFormat.text(for: $0) } ?? "-- GB"
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        button.image = preferences.effectiveShowIcon
            ? NSImage(systemSymbolName: "internaldrive", accessibilityDescription: nil)
            : nil
        button.setAccessibilityLabel(snapshot.map { preferences.displayFormat.spokenText(for: $0) } ?? "Storage, reading")
    }

    // MARK: Actions

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    /// Public so a relaunch of the running app can reveal the item.
    func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate()
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "About StorageBar", action: #selector(about), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Preferences…", action: #selector(preferences), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit StorageBar", action: #selector(quit), keyEquivalent: "q").target = self
        // Attaching the menu only for this click keeps left-click opening the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func about() { AppInfo.showAbout() }
    @objc private func preferences() { showPreferences() }
    @objc private func quit() { NSApp.terminate(nil) }

    /// Removes the item from the menu bar (used by tests and on termination).
    func tearDown() {
        popover.performClose(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    var isPreferencesVisible: Bool { preferencesWindow?.isVisible == true }

    func showPreferences() {
        popover.performClose(nil)
        if preferencesWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView(model: model)))
            window.title = "StorageBar Preferences"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("preferences")
            window.center()
            preferencesWindow = window
        }
        NSApp.activate()
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }
}
