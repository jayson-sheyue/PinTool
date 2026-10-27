import AppKit

final class ShortcutRecorder: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var monitor: Any?
    private var completion: ((Shortcut?) -> Void)?
    private var finished = false

    func begin(title: String, completion: @escaping (Shortcut?) -> Void) {
        finish(nil)
        finished = false
        self.completion = completion

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 128),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.level = .floating

        let label = NSTextField(wrappingLabelWithString: "按下新的快捷键。需要包含 ⌃、⌥ 或 ⌘。Esc 取消。")
        label.font = .systemFont(ofSize: 13)
        label.preferredMaxLayoutWidth = 312
        label.translatesAutoresizingMaskIntoConstraints = false
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        cancel.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(label)
        content.addSubview(cancel)
        panel.contentView = content
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            cancel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 16),
            cancel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20)
        ])

        self.panel = panel
        if let screen = NSScreen.main?.visibleFrame {
            panel.center()
            _ = screen
        }
        panel.center()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.finish(nil)
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let hasPrimary = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
            guard hasPrimary, !self.isModifierKey(event.keyCode) else { return nil }
            let shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: Shortcut.carbonModifiers(flags))
            self.finish(shortcut)
            return nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        finish(nil)
    }

    @objc private func cancel() {
        finish(nil)
    }

    private func finish(_ shortcut: Shortcut?) {
        guard !finished else { return }
        finished = true
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
        let callback = completion
        completion = nil
        callback?(shortcut)
    }

    private func isModifierKey(_ keyCode: UInt16) -> Bool {
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(Int(keyCode))
    }
}
