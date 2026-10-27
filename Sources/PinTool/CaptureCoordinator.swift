import AppKit
import os
import PinToolCore

final class CaptureCoordinator {
    let pins = PinBoard()
    let guide = GuideController()
    let hotkeys = HotkeyCenter()
    let selection = SelectionSession()
    let hud = StatusHUD()
    private let viewport = LongViewport()
    private let finishMark = FinishMark()
    let recorder = ShortcutRecorder()
    var onStatusTitle: ((String?) -> Void)?

    private let logger = Logger(subsystem: "local.pintool.Pin", category: "capture")
    private var mode: SelectionMode = .region
    private var longRunning = false
    private var longGeneration = 0
    private var escMonitors: [Any] = []
    private var session: LongStitchSession?
    private var growing: PinPanel?
    private var longRect: CGRect = .zero
    private var longScale: CGFloat = 2
    private var longScreen: NSScreen?
    private var hiddenDuringLong: [PinPanel] = []
    private var hudToken = 0
    private var notes: [String] = []
    private var hotkeysReady = false

    func start() {
        hotkeys.onPress = { [weak self] id in
            Task { @MainActor in
                self?.hotkey(id)
            }
        }
        selection.onComplete = { [weak self] rect in
            self?.selected(rect)
        }
        guide.shortcutText = { [weak self] in
            self?.shortcutLines() ?? ("⌃⌥A", "⌃⌥S")
        }
        applyHotkeys()
        if !Permissions.screenRecordingGranted || !ShortcutStore.didShowGuide {
            guide.show()
        }
    }

    @MainActor
    func beginRegion() {
        hotkey(HotkeyID.region)
    }

    @MainActor
    func beginLong() {
        hotkey(HotkeyID.longCapture)
    }

    func suspendHotkeys() {
        hotkeys.suspend()
    }

    func applyHotkeys() {
        let region = ShortcutStore.load(.region)
        let longCapture = ShortcutStore.load(.long)
        hotkeysReady = hotkeys.replace(region: region, longCapture: longCapture)
        if !hotkeysReady {
            note("快捷键注册失败，可能被其他软件占用。")
        }
        guide.refresh()
    }

    @MainActor
    func updateShortcut(_ kind: ShortcutKind, to shortcut: Shortcut) {
        let other: ShortcutKind = kind == .region ? .long : .region
        if ShortcutStore.load(other) == shortcut {
            flash("两个快捷键不能一样。")
            return
        }
        let previous = ShortcutStore.load(kind)
        ShortcutStore.save(kind, shortcut)
        if hotkeys.replace(region: ShortcutStore.load(.region), longCapture: ShortcutStore.load(.long)) {
            hotkeysReady = true
            guide.refresh()
            flash("快捷键已改为 \(shortcut.display)")
        } else {
            ShortcutStore.save(kind, previous)
            hotkeysReady = hotkeys.replace(region: ShortcutStore.load(.region), longCapture: ShortcutStore.load(.long))
            flash("这个快捷键没法用，可能被系统或其他软件占用。")
        }
    }

    func shortcutLines() -> (region: String, long: String) {
        (ShortcutStore.load(.region).display, ShortcutStore.load(.long).display)
    }

    func diagnosticText() -> String {
        let arch: String
        #if arch(arm64)
        arch = "arm64"
        #elseif arch(x86_64)
        arch = "x86_64"
        #else
        arch = "未知架构"
        #endif
        let history = notes.isEmpty ? "无" : notes.joined(separator: "\n")
        return """
        钉图 \(AppInfo.version)
        \(ProcessInfo.processInfo.operatingSystemVersionString) \(arch)
        屏幕录制 \(Permissions.screenRecordingGranted ? "已允许" : "未允许")
        辅助功能 \(Permissions.accessibilityGranted ? "已允许" : "未允许")
        钉住选区 \(ShortcutStore.load(.region).display)\(hotkeysReady ? "" : "（注册失败）")
        长截图 \(ShortcutStore.load(.long).display)
        最近记录：
        \(history)
        """
    }

    @MainActor
    private func hotkey(_ id: UInt32) {
        if longRunning {
            if id == HotkeyID.longCapture {
                finishLong("已钉住")
            } else {
                flash("长截图还在进行。再按一次长截图快捷键，或按 Esc 结束。")
            }
            return
        }
        guard Permissions.screenRecordingGranted else {
            Permissions.requestScreenRecording()
            guide.show()
            flash("还没有屏幕录制权限。系统设置里的开关如果已经开着，先删掉旧的 PinTool 再打开，然后重新打开钉图。")
            return
        }
        let next: SelectionMode = id == HotkeyID.longCapture ? .longCapture : .region
        mode = next
        guide.orderOut()
        selection.begin(mode: next)
    }

    private func selected(_ rect: CGRect) {
        let chosen = mode
        let previous = selection.previousApplication
        Task { @MainActor in
            await self.restore(previous)
            if chosen == .region {
                await self.pinRegion(rect)
            } else {
                await self.pinLong(rect)
            }
        }
    }

    @MainActor
    private func restore(_ previous: NSRunningApplication?) async {
        guard let previous, previous.processIdentifier != NSRunningApplication.current.processIdentifier else { return }
        _ = previous.activate(from: .current, options: [])
        try? await Task.sleep(nanoseconds: 90_000_000)
    }

    @MainActor
    private func pinRegion(_ rect: CGRect) async {
        do {
            let grabbed = try await ScreenGrabber.grab(rect: rect)
            pins.add(image: grabbed.image, scale: grabbed.scale, aligningTopLeftTo: rect)
            note("已钉住选区")
        } catch {
            note(error.localizedDescription)
            flash(error.localizedDescription)
            if !Permissions.screenRecordingGranted {
                guide.show()
            }
        }
    }

    @MainActor
    private func pinLong(_ rect: CGRect) async {
        if longRunning {
            finishLong("已钉住")
        }
        longGeneration += 1
        let generation = longGeneration
        longRunning = true
        longRect = rect
        longScreen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }
        viewport.show(rect: rect)
        finishMark.onConfirm = { [weak self] in
            guard let self else { return }
            self.finishLong(self.growing == nil ? nil : "已钉住")
        }
        finishMark.show(near: rect, on: longScreen)
        installEsc()
        hiddenDuringLong = pins.suspendIntersecting(rect)
        hud.show("正在截第一段…", avoiding: rect, on: longScreen)
        onStatusTitle?("…")

        let target: CaptureTarget
        do {
            target = try await ScreenGrabber.prepare(rect: rect)
        } catch {
            guard generation == longGeneration else { return }
            note(error.localizedDescription)
            flash(error.localizedDescription, avoiding: rect, on: longScreen)
            finishLong(nil)
            return
        }
        guard generation == longGeneration else { return }
        longScale = target.scale
        let live = LongStitchSession()
        live.onPreview = { [weak self] image in
            Task { @MainActor in
                guard let self, generation == self.longGeneration else { return }
                self.showLongFrame(image)
            }
        }
        live.onCapped = { [weak self] in
            Task { @MainActor in
                guard let self, generation == self.longGeneration else { return }
                self.hud.update("已经到最长了。点绿勾钉住这一段。")
            }
        }
        live.onLost = { [weak self] in
            Task { @MainActor in
                guard let self, generation == self.longGeneration, self.growing != nil else { return }
                self.hud.update("画面跟上停了。点绿勾钉住已经接上的部分。")
            }
        }
        session = live
        do {
            try await live.start(target)
        } catch {
            guard generation == longGeneration else { return }
            note(error.localizedDescription)
            flash(error.localizedDescription, avoiding: rect, on: longScreen)
            finishLong(nil)
        }
    }

    @MainActor
    private func showLongFrame(_ image: CGImage) {
        guard longRunning else { return }
        if let growing, !pins.stillHas(growing) {
            finishLong("已钉住")
            return
        }
        if growing == nil {
            growing = pins.add(image: image, scale: longScale, aligningTopLeftTo: longRect)
            growing?.setPassThrough(true)
            hud.show("在框里向下滚。点绿勾钉住。", avoiding: longRect, on: longScreen)
        } else {
            growing?.replace(image: image, scale: longScale)
        }
        growing?.layoutLeft(of: longRect)
    }

    @MainActor
    private func finishLong(_ message: String?) {
        guard longRunning else { return }
        longGeneration += 1
        longRunning = false
        let ending = session
        session = nil
        let panel = growing
        let scale = longScale
        let rect = longRect
        removeEsc()
        finishMark.hide()
        viewport.hide()
        panel?.setPassThrough(false)
        pins.resume(hiddenDuringLong)
        hiddenDuringLong = []
        growing = nil
        onStatusTitle?(nil)
        if let message, panel != nil {
            note(message)
            flash(message, avoiding: rect.isEmpty ? nil : rect, on: longScreen)
        } else {
            hud.hide()
        }
        guard let ending, let panel else { return }
        Task { @MainActor in
            guard let image = await ending.end() else { return }
            guard self.pins.stillHas(panel) else { return }
            panel.replace(image: image, scale: scale)
            panel.layoutLeft(of: rect)
        }
    }

    @MainActor
    private func installEsc() {
        removeEsc()
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            Task { @MainActor in
                self?.finishLong("已钉住")
            }
            return nil
        }) {
            escMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in
                self?.finishLong("已钉住")
            }
        }) {
            escMonitors.append(global)
        }
    }

    @MainActor
    private func removeEsc() {
        escMonitors.forEach { NSEvent.removeMonitor($0) }
        escMonitors.removeAll()
    }

    @MainActor
    private func flash(_ text: String, avoiding: CGRect? = nil, on screen: NSScreen? = nil) {
        hudToken += 1
        let token = hudToken
        hud.show(text, avoiding: avoiding, on: screen)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if token == self.hudToken {
                self.hud.hide()
            }
        }
    }

    private func note(_ text: String) {
        notes.append(text)
        if notes.count > 12 { notes.removeFirst() }
        logger.info("\(text, privacy: .public)")
    }
}
