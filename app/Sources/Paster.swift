import AppKit
import ApplicationServices

enum Paster {
    /// 回傳 false 表示沒有輔助使用授權：文字已留在剪貼簿，但沒有送出貼上。
    @MainActor
    static func paste(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }
        pb.clearContents()
        pb.setString(text, forType: .string)
        let ours = pb.changeCount
        guard AXIsProcessTrusted() else { return false }

        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let ev = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: down)  // 9 = V
            ev?.flags = .maskCommand
            ev?.post(tap: .cgAnnotatedSessionEventTap)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // 使用者在這 0.3 秒內自己複製了東西就不覆蓋。
            guard pb.changeCount == ours else { return }
            pb.clearContents()
            let items = saved.map { entries -> NSPasteboardItem in
                let item = NSPasteboardItem()
                entries.forEach { item.setData($0.1, forType: $0.0) }
                return item
            }
            if !items.isEmpty { pb.writeObjects(items) }
        }
        return true
    }
}
