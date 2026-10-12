import AppKit
import Combine
import SwiftUI

@main
struct BreezeDictateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // 視窗由 AppDelegate 自行管理，以便切換 activation policy。
        SwiftUI.Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var cancellable: AnyCancellable?
    private var setupWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "設定…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "結束", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu

        model.showSetup = { [weak self] in self?.openSetup() }
        model.closeSetup = { [weak self] in self?.setupWindow?.close() }
        cancellable = model.objectWillChange.sink { [weak self] _ in
            // objectWillChange 在值改變前觸發，等下一輪再讀新值。
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refreshStatusItem() } }
        }
        refreshStatusItem()
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    private func refreshStatusItem() {
        statusMenuItem.title = model.statusText
        let recording = model.status == .recording
        var config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        if recording { config = config.applying(.init(paletteColors: [.systemRed])) }
        let image = NSImage(systemSymbolName: model.iconName, accessibilityDescription: model.statusText)?
            .withSymbolConfiguration(config)
        image?.isTemplate = !recording
        statusItem.button?.image = image
    }

    @objc private func openSettings() {
        settingsWindow = show(settingsWindow, title: "BreezeDictate 設定", size: NSSize(width: 560, height: 460)) {
            SettingsView(model: model)
        }
    }

    private func openSetup() {
        setupWindow = show(setupWindow, title: "BreezeDictate 首次設定", size: NSSize(width: 520, height: 560)) {
            SetupView(model: model)
        }
    }

    private func show<V: View>(_ existing: NSWindow?, title: String, size: NSSize,
                               @ViewBuilder content: () -> V) -> NSWindow {
        NSApp.setActivationPolicy(.regular)
        let w = existing ?? {
            let w = NSWindow(contentViewController: NSHostingController(rootView: content()))
            w.title = title
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.setContentSize(size)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            return w
        }()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return w
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelCapture()
        let closing = notification.object as? NSWindow
        let stillOpen = [setupWindow, settingsWindow].contains { $0 !== closing && $0?.isVisible == true }
        if !stillOpen { NSApp.setActivationPolicy(.accessory) }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
