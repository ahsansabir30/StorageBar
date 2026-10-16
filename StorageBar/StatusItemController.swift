import AppKit
import Observation
import SwiftUI

/// Hosting view that accepts the click that opens a menu item, so the first click on a row works.
private final class MenuHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the menu bar status item, the popup and the Preferences window.
///
/// Uses `NSStatusItem` rather than `MenuBarExtra` because it gives the item a stable
/// `autosaveName` (so macOS persists its position under a StorageBar-specific key instead of the
/// generic `Item-0`) and control over how the popup is presented.
///
/// The popup is the SwiftUI view hosted inside an `NSMenu` item, not a popover: a real menu keeps
/// an auto-hidden menu bar revealed while it is open (a popover does not), and closes natively on
/// outside clicks and Esc.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    static let autosaveName = "StorageBar"

    private let model: AppModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let popupView: MenuHostingView<PopupView>
    private var preferencesWindow: NSWindow?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // The closures need `self`, which does not exist until super.init; route through a box.
        let actions = PopupActions()
        popupView = MenuHostingView(rootView: PopupView(
            model: model,
            openPreferences: { actions.openPreferences() },
            dismiss: { actions.dismiss() }
        ))
        super.init()
        actions.openPreferences = { [weak self] in
            // Let the menu finish closing before a window takes focus.
            self?.menu.cancelTracking()
            DispatchQueue.main.async { self?.showPreferences() }
        }
        actions.dismiss = { [weak self] in self?.menu.cancelTracking() }

        statusItem.autosaveName = Self.autosaveName
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.setAccessibilityIdentifier("menuBarLabel")
        }

        let item = NSMenuItem()
        item.view = popupView
        menu.addItem(item)
        menu.delegate = self
        statusItem.menu = menu

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

        let style = MenuBarStyle(
            snapshot: snapshot,
            thresholds: preferences.thresholds,
            iconPreferred: preferences.effectiveShowIcon
        )
        let text = snapshot.map { preferences.displayFormat.text(for: $0) } ?? "-- GB"
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)

        button.font = font
        if style.isCritical {
            // Template images and plain titles follow the menu bar tint; colour needs explicit
            // non-template rendering, used only for this warning state.
            button.attributedTitle = NSAttributedString(
                string: text, attributes: [.font: font, .foregroundColor: NSColor.systemRed])
        } else {
            button.attributedTitle = NSAttributedString()
            button.title = text
        }

        if style.showsIcon, let symbol = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: nil) {
            if style.isCritical {
                let red = symbol.withSymbolConfiguration(.init(paletteColors: [.systemRed]))
                red?.isTemplate = false
                button.image = red
            } else {
                button.image = symbol
            }
        } else {
            button.image = nil
        }

        var spoken = snapshot.map { preferences.displayFormat.spokenText(for: $0) } ?? "Storage, reading"
        if style.isCritical { spoken += ". Storage is almost full." }
        button.setAccessibilityLabel(spoken)
    }

    /// The status item's button, for tests.
    var statusButton: NSStatusBarButton? { statusItem.button }

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) {
        // A menu measures its custom view once when it opens, so size it to the current content.
        popupView.layoutSubtreeIfNeeded()
        popupView.frame.size = popupView.fittingSize
        Task { await model.monitor.refresh() }
    }

    /// Opens the menu, e.g. when the running app is launched again, to reveal the item.
    func showMenu() {
        guard let button = statusItem.button, button.window?.isVisible == true else { return }
        button.performClick(nil)
    }

    /// Removes the item from the menu bar (used by tests and on termination).
    func tearDown() {
        menu.cancelTracking()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: Preferences

    var isPreferencesVisible: Bool { preferencesWindow?.isVisible == true }

    func showPreferences() {
        if preferencesWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView(model: model)))
            window.title = "StorageBar Preferences"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()                          // first-run position...
            window.setFrameAutosaveName("preferences")  // ...replaced by the user's saved frame, if any
            preferencesWindow = window
        }
        NSApp.activate()
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }
}

/// Late-bound closures for the popup, set once the controller exists.
@MainActor
private final class PopupActions {
    var openPreferences: () -> Void = {}
    var dismiss: () -> Void = {}
}
