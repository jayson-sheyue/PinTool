import AppKit

final class GuideController: NSObject, NSWindowDelegate {
    let window: NSWindow
    var shortcutText: () -> (region: String, long: String) = { ("⌃⌥A", "⌃⌥S") }

    private let regionLine = NSTextField(wrappingLabelWithString: "")
    private let longLine = NSTextField(wrappingLabelWithString: "")
    private let screenStatus = NSTextField(labelWithString: "")
    private let accessStatus = NSTextField(labelWithString: "")
    private let screenDetail = NSTextField(wrappingLabelWithString: "")
    private let accessDetail = NSTextField(wrappingLabelWithString: "")
    private let screenButton = NSButton(title: "打开设置", target: nil, action: nil)
    private let accessButton = NSButton(title: "打开设置", target: nil, action: nil)
    private let reopenButton = NSButton(title: "重新打开钉图", target: nil, action: nil)
    private let doneButton = NSButton(title: "好", target: nil, action: nil)
    private var watch: Timer?

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "钉图"
        window.isReleasedWhenClosed = false
        window.level = .floating
        super.init()
        window.delegate = self
        build()
        refresh()
    }

    func show() {
        refresh()
        window.layoutIfNeeded()
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        startWatching()
    }

    func orderOut() {
        stopWatching()
        window.orderOut(nil)
    }

    func refresh() {
        let shortcuts = shortcutText()
        regionLine.stringValue = "钉住选区（\(shortcuts.region)）：拖出范围，松开就钉住。"
        longLine.stringValue = "长截图（\(shortcuts.long)）：框是基准。松开后由你在框里向下滚，左边跟着变长。滚完点绿勾钉住，不用再按快捷键。"

        let screenGranted = Permissions.screenRecordingGranted
        screenStatus.stringValue = screenGranted ? "已允许" : "未允许"
        screenButton.title = screenGranted ? "已允许" : "打开设置"
        screenButton.isEnabled = !screenGranted
        screenDetail.stringValue = screenGranted
            ? "截图可以用了。"
            : "截图需要。列表里的名字是 PinTool。开关如果已经开着这里仍是未允许，先选中它点减号删掉，再打开一次。然后点「重新打开钉图」，这次运行才会拿到权限。"

        let accessGranted = Permissions.accessibilityGranted
        accessStatus.stringValue = accessGranted ? "已允许" : "未允许"
        accessButton.title = accessGranted ? "已允许" : "打开设置"
        accessButton.isEnabled = !accessGranted
        accessDetail.stringValue = "长截图不用这项。页面由你自己滚动，钉图跟着变长。"

        let waiting = !screenGranted
        reopenButton.isHidden = !waiting
        reopenButton.keyEquivalent = waiting ? "\r" : ""
        doneButton.keyEquivalent = waiting ? "" : "\r"
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refresh()
    }

    func windowWillClose(_ notification: Notification) {
        stopWatching()
        ShortcutStore.didShowGuide = true
    }

    private func startWatching() {
        stopWatching()
        watch = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func stopWatching() {
        watch?.invalidate()
        watch = nil
    }

    private func build() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(title("把一块屏幕钉在最前面", size: 20, weight: .semibold, color: .labelColor))
        stack.addArrangedSubview(body("框选你正在看的内容，它会留在所有窗口之上。按住拖到一边，就能对照另一个页面，不用来回切换。"))
        stack.addArrangedSubview(rule())
        stack.addArrangedSubview(title("怎么用", size: 13, weight: .semibold, color: .labelColor))
        stack.addArrangedSubview(configure(regionLine))
        stack.addArrangedSubview(configure(longLine))
        stack.addArrangedSubview(body("移动：按住钉图拖动。放大：在图上滚动或捏合，光标对准哪里就放大哪里。放大后拖动是查看其它部分，按住 Option 再拖可以移动整张图。"))
        stack.addArrangedSubview(body("关闭：移上去点右上角的 ×，也可以右键关闭。菜单栏能一次关掉全部。钉图不写入磁盘，退出后就没了。"))
        stack.addArrangedSubview(rule())
        stack.addArrangedSubview(title("需要的权限", size: 13, weight: .semibold, color: .labelColor))
        stack.addArrangedSubview(permissionRow(
            "屏幕录制",
            detail: screenDetail,
            status: screenStatus,
            button: screenButton,
            action: #selector(openScreen)
        ))
        stack.addArrangedSubview(permissionRow(
            "辅助功能",
            detail: accessDetail,
            status: accessStatus,
            button: accessButton,
            action: #selector(openAccessibility)
        ))

        reopenButton.target = self
        reopenButton.action = #selector(reopenApp)
        reopenButton.bezelStyle = .push
        doneButton.target = self
        doneButton.action = #selector(closeGuide)
        doneButton.bezelStyle = .push
        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttonRow.addArrangedSubview(spacer)
        buttonRow.addArrangedSubview(reopenButton)
        buttonRow.addArrangedSubview(doneButton)
        stack.addArrangedSubview(buttonRow)
        buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let version = NSTextField(labelWithString: "钉图 \(AppInfo.version) · 画面只留在这台 Mac 的内存里")
        version.font = .systemFont(ofSize: 12)
        version.textColor = Self.readableSecondary
        stack.addArrangedSubview(version)

        guard let content = window.contentView else { return }
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            content.widthAnchor.constraint(equalToConstant: 460)
        ])
        stack.setContentHuggingPriority(.required, for: .vertical)
        for view in stack.arrangedSubviews {
            view.setContentHuggingPriority(.required, for: .vertical)
        }
        [regionLine, longLine].forEach { $0.preferredMaxLayoutWidth = 412 }
        refresh()
        content.layoutSubtreeIfNeeded()
        let height = stack.fittingSize.height + 36
        window.setContentSize(NSSize(width: 460, height: max(height, 280)))
    }

    private func title(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }

    private func body(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 13)
        field.textColor = Self.readableSecondary
        field.preferredMaxLayoutWidth = 412
        return field
    }

    private func configure(_ field: NSTextField) -> NSTextField {
        field.font = .systemFont(ofSize: 13)
        field.textColor = .labelColor
        field.preferredMaxLayoutWidth = 412
        return field
    }

    private func rule() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 1).isActive = true
        box.widthAnchor.constraint(equalToConstant: 412).isActive = true
        return box
    }

    private func permissionRow(
        _ title: String,
        detail: NSTextField,
        status: NSTextField,
        button: NSButton,
        action: Selector
    ) -> NSView {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 4
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 13, weight: .medium)
        status.font = .systemFont(ofSize: 13)
        status.textColor = Self.readableSecondary
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        let header = NSStackView(views: [heading, status, button])
        header.orientation = .horizontal
        header.spacing = 8
        column.addArrangedSubview(header)
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = Self.readableSecondary
        detail.preferredMaxLayoutWidth = 412
        column.addArrangedSubview(detail)
        return column
    }

    @objc private func reopenApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            DispatchQueue.main.async {
                if error == nil {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    @objc private func openScreen() {
        Permissions.requestScreenRecording()
        if !Permissions.screenRecordingGranted {
            Permissions.openScreenRecordingSettings()
        }
        refresh()
    }

    @objc private func openAccessibility() {
        Permissions.requestAccessibility()
        if !Permissions.accessibilityGranted {
            Permissions.openAccessibilitySettings()
        }
        refresh()
    }

    @objc private func closeGuide() {
        ShortcutStore.didShowGuide = true
        window.close()
    }
}

extension GuideController {
    /// Softer than the title, still at least 4.5:1 on the system window background.
    static let readableSecondary = NSColor(name: "PinToolSecondary") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(srgbRed: dark ? 0.88 : 0.32, green: dark ? 0.88 : 0.32, blue: dark ? 0.90 : 0.34, alpha: 1)
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}
