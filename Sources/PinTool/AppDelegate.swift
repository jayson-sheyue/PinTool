import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let coordinator = CaptureCoordinator()
    private let regionItem = NSMenuItem(title: "钉住选区", action: #selector(startRegion), keyEquivalent: "")
    private let longItem = NSMenuItem(title: "长截图钉住", action: #selector(startLong), keyEquivalent: "")
    private let closeItem = NSMenuItem(title: "关闭全部钉图", action: #selector(closePins), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Read before the status item is created. With no saved rank, a full
        // right-hand menu bar parks a new icon left of the notch, on top of
        // window navigation. A rank in the hundreds keeps it with the other
        // status icons. Leave an existing value alone so a later Command-drag
        // is remembered. Moving the window frame does not change the slot.
        let positionKey = "NSStatusItem Preferred Position PinTool"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(1000.0, forKey: positionKey)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "PinTool"
        statusItem.behavior = []
        statusItem.isVisible = true
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "钉图")
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "钉图"
        }
        let menu = NSMenu()
        menu.delegate = self
        regionItem.target = self
        longItem.target = self
        closeItem.target = self
        menu.addItem(regionItem)
        menu.addItem(longItem)
        menu.addItem(.separator())
        menu.addItem(closeItem)
        menu.addItem(.separator())
        menu.addItem(item("使用说明…", #selector(showGuide)))
        menu.addItem(item("更改钉住选区快捷键…", #selector(recordRegion)))
        menu.addItem(item("更改长截图快捷键…", #selector(recordLong)))
        menu.addItem(item("拷贝诊断信息", #selector(copyDiagnostics)))
        menu.addItem(.separator())
        menu.addItem(item("退出钉图", #selector(quit)))
        statusItem.menu = menu

        coordinator.onStatusTitle = { [weak self] title in
            self?.statusItem.button?.title = title ?? ""
            self?.statusItem.length = title == nil ? NSStatusItem.squareLength : NSStatusItem.variableLength
        }
        coordinator.start()
        // The status item can be created already marked occluded.
        statusItem.button?.window?.orderFrontRegardless()
    }

    func menuWillOpen(_ menu: NSMenu) {
        let lines = coordinator.shortcutLines()
        regionItem.title = "钉住选区（\(lines.region)）"
        longItem.title = "长截图钉住（\(lines.long)）"
        closeItem.isEnabled = !coordinator.pins.isEmpty
    }

    @objc private func startRegion() {
        Task { @MainActor in
            coordinator.beginRegion()
        }
    }

    @objc private func startLong() {
        Task { @MainActor in
            coordinator.beginLong()
        }
    }

    @objc private func closePins() {
        coordinator.pins.closeAll()
    }

    @objc private func showGuide() {
        coordinator.guide.show()
    }

    @objc private func recordRegion() {
        record(.region, title: "钉住选区的快捷键")
    }

    @objc private func recordLong() {
        record(.long, title: "长截图的快捷键")
    }

    @objc private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(coordinator.diagnosticText(), forType: .string)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func record(_ kind: ShortcutKind, title: String) {
        coordinator.suspendHotkeys()
        coordinator.recorder.begin(title: title) { [weak self] shortcut in
            guard let self else { return }
            if let shortcut {
                Task { @MainActor in
                    self.coordinator.updateShortcut(kind, to: shortcut)
                }
            } else {
                self.coordinator.applyHotkeys()
            }
        }
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
}
