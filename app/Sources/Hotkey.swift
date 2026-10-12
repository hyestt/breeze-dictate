import AppKit

/// 全域快捷鍵：單一修飾鍵（左右分開）或一般鍵。全域監聽需要「輸入監控」授權。
@MainActor
final class HotkeyMonitor {
    var keyCode = 61
    var isModifier = true
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var monitors: [Any] = []
    private var isDown = false
    private var captureHandler: ((Int, Bool, String) -> Void)?

    // 修飾鍵 keyCode 對應 NSEvent 的裝置相依位元，才能分辨左右。
    private static let deviceMasks: [Int: UInt] = [
        54: 0x10, 55: 0x08, 56: 0x02, 60: 0x04, 58: 0x20, 61: 0x40, 59: 0x01, 62: 0x2000,
    ]
    private static let modifierNames: [Int: String] = [
        54: "右 Command", 55: "左 Command", 56: "左 Shift", 60: "右 Shift", 58: "左 Option",
        61: "右 Option", 59: "左 Control", 62: "右 Control", 63: "fn", 57: "Caps Lock",
    ]
    private static let keyNames: [Int: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        49: "空白鍵", 36: "Return", 48: "Tab", 51: "Delete",
    ]

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in
            MainActor.assumeIsolated { _ = self?.handle(e) }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.handle(e) ?? e }
        }) { monitors.append(l) }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        isDown = false
    }

    /// 進入錄製狀態：下一個按下的鍵成為快捷鍵，Esc 取消（回傳 keyCode -1）。
    func capture(_ done: @escaping (_ keyCode: Int, _ isModifier: Bool, _ label: String) -> Void) {
        isDown = false
        captureHandler = done
    }

    func cancelCapture() {
        captureHandler = nil
    }

    private func modifierIsDown(_ e: NSEvent, keyCode: Int) -> Bool {
        if let m = Self.deviceMasks[keyCode] { return e.modifierFlags.rawValue & m != 0 }
        switch keyCode {
        case 63: return e.modifierFlags.contains(.function)
        case 57: return e.modifierFlags.contains(.capsLock)
        default: return false
        }
    }

    private func handle(_ e: NSEvent) -> NSEvent? {
        let code = Int(e.keyCode)
        if let done = captureHandler {
            switch e.type {
            case .flagsChanged:
                guard Self.modifierNames[code] != nil, modifierIsDown(e, keyCode: code) else { return e }
                captureHandler = nil
                done(code, true, Self.modifierNames[code] ?? "修飾鍵")
            case .keyDown:
                captureHandler = nil
                if code == 53 { done(-1, false, "") } else {
                    let label = Self.keyNames[code]
                        ?? (e.charactersIgnoringModifiers?.uppercased()).flatMap { $0.isEmpty ? nil : $0 }
                        ?? "鍵碼 \(code)"
                    done(code, false, label)
                }
                return nil
            default: break
            }
            return e
        }

        if isModifier {
            guard e.type == .flagsChanged, code == keyCode else { return e }
            let down = modifierIsDown(e, keyCode: code)
            if down && !isDown { isDown = true; onPress?() }
            else if !down && isDown { isDown = false; onRelease?() }
        } else {
            guard code == keyCode else { return e }
            if e.type == .keyDown, !e.isARepeat, !isDown { isDown = true; onPress?() }
            else if e.type == .keyUp, isDown { isDown = false; onRelease?() }
        }
        return e
    }
}
