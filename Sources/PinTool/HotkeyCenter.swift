import Carbon.HIToolbox
import Foundation

enum HotkeyID {
    static let region: UInt32 = 1
    static let longCapture: UInt32 = 2
}

final class HotkeyCenter {
    var onPress: ((UInt32) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var installed = false

    func install() {
        guard !installed else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            pinToolHotkeyHandler,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        installed = true
    }

    func suspend() {
        clear()
    }

    @discardableResult
    func replace(region: Shortcut, longCapture: Shortcut) -> Bool {
        install()
        clear()
        let first = register(id: HotkeyID.region, shortcut: region)
        let second = register(id: HotkeyID.longCapture, shortcut: longCapture)
        if first && second { return true }
        clear()
        return false
    }

    private func register(id: UInt32, shortcut: Shortcut) -> Bool {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: 0x50494E54, id: id) // 'PINT'
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        refs.append(ref)
        return true
    }

    private func clear() {
        for ref in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        onPress?(id)
    }
}

private func pinToolHotkeyHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
    let id = hotKeyID.id
    DispatchQueue.main.async {
        center.fire(id)
    }
    return noErr
}
