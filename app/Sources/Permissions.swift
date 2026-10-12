import AVFoundation
import AppKit
import ApplicationServices
import CoreGraphics

enum PermissionKind: CaseIterable, Identifiable {
    case microphone, accessibility, inputMonitoring
    var id: Self { self }

    var title: String {
        switch self {
        case .microphone: "麥克風"
        case .accessibility: "輔助使用"
        case .inputMonitoring: "輸入監控"
        }
    }

    var purpose: String {
        switch self {
        case .microphone: "錄下你說的話"
        case .accessibility: "把文字貼到游標處"
        case .inputMonitoring: "偵測快捷鍵"
        }
    }

    fileprivate var settingsPane: String {
        switch self {
        case .microphone: "Privacy_Microphone"
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        }
    }
}

struct PermissionState: Equatable {
    var microphone = false
    var accessibility = false
    var inputMonitoring = false

    var allGranted: Bool { microphone && accessibility && inputMonitoring }

    func isGranted(_ k: PermissionKind) -> Bool {
        switch k {
        case .microphone: microphone
        case .accessibility: accessibility
        case .inputMonitoring: inputMonitoring
        }
    }

    static func current() -> PermissionState {
        PermissionState(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: CGPreflightListenEventAccess())
    }
}

enum Permissions {
    static func request(_ kind: PermissionKind) {
        switch kind {
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
            } else {
                openSettings(kind)
            }
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            openSettings(kind)
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
            openSettings(kind)
        }
    }

    private static func openSettings(_ kind: PermissionKind) {
        let url = "x-apple.systempreferences:com.apple.preference.security?\(kind.settingsPane)"
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}
