import AppKit
import ServiceManagement

enum DictationStatus: Equatable {
    case idle, recording, transcribing
    case error(String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            applySettings(old: oldValue)
        }
    }
    @Published var vocabulary: [VocabEntry] {
        didSet { if vocabulary != oldValue { VocabularyStore.save(vocabulary) } }
    }
    @Published private(set) var status: DictationStatus = .idle
    @Published private(set) var engineState: EngineState = .notInstalled
    @Published private(set) var permissions = PermissionState.current()
    @Published private(set) var isCapturingHotkey = false
    @Published private(set) var loginItemError: String?

    var showSetup: (() -> Void)?
    var closeSetup: (() -> Void)?

    private let engine = Engine()
    private let installer = Installer()
    private let hotkey = HotkeyMonitor()
    private let recorder = Recorder()
    private var pollTimer: Timer?

    init() {
        Paths.ensureSupport()
        VocabularyStore.seedIfMissing()
        settings = Settings.load()
        vocabulary = VocabularyStore.load()
        engine.onState = { [weak self] s in self?.engineState = s }
        hotkey.onPress = { [weak self] in self?.beginRecording() }
        hotkey.onRelease = { [weak self] in self?.endRecording() }
        configureHotkey()
    }

    func start() {
        Log.write("app start")
        hotkey.start()
        engine.start()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        if needsSetup { showSetup?() }
    }

    func shutdown() {
        engine.stop()
        pollTimer?.invalidate()
    }

    var needsSetup: Bool {
        switch engineState {
        case .notInstalled, .failed: return true
        default: return !permissions.allGranted
        }
    }

    var canDictate: Bool { engineState == .ready && permissions.allGranted }

    // MARK: 狀態顯示

    var statusText: String {
        switch status {
        case .recording: return "錄音中…"
        case .transcribing: return "辨識中…"
        case .error(let m): return "錯誤：\(m)"
        case .idle:
            switch engineState {
            case .notInstalled: return "語音引擎尚未安裝"
            case .installing(let s): return s
            case .starting: return "引擎啟動中…"
            case .failed(let m): return "引擎失敗：\(m)"
            case .ready:
                if !permissions.allGranted { return "缺少授權，請開啟設定" }
                return "待機中，按住 \(settings.hotkeyLabel) 說話"
            }
        }
    }

    var iconName: String {
        switch status {
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .error: return "exclamationmark.triangle"
        case .idle: return canDictate ? "mic" : "exclamationmark.triangle"
        }
    }

    // MARK: 錄音流程

    private func beginRecording() {
        guard status == .idle else { return }
        guard canDictate else { showSetup?(); return }
        guard recorder.start() else { fail("無法開始錄音"); return }
        status = .recording
        play("Tink")
    }

    private func endRecording() {
        guard status == .recording, let rec = recorder.stop() else { return }
        play("Pop")
        guard rec.duration >= 0.3 else {
            try? FileManager.default.removeItem(at: rec.url)
            status = .idle
            return
        }
        status = .transcribing
        Task {
            defer { try? FileManager.default.removeItem(at: rec.url) }
            do {
                let text = try await engine.transcribe(rec.url)
                if !text.isEmpty, !Paster.paste(text) {
                    fail("缺少輔助使用授權，文字已複製到剪貼簿")
                    return
                }
                status = .idle
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    private func fail(_ message: String) {
        let s = DictationStatus.error(message)
        status = s
        Log.write("error: \(message)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            MainActor.assumeIsolated { if self?.status == s { self?.status = .idle } }
        }
    }

    private func play(_ name: String) {
        if settings.playSound { NSSound(named: NSSound.Name(name))?.play() }
    }

    // MARK: 引擎安裝

    func install() {
        guard !installer.isRunning else { return }
        engine.stop()
        engine.setInstalling("準備安裝…")
        installer.run(progress: { [weak self] step in
            self?.engine.setInstalling(step)
        }, completion: { [weak self] failure in
            guard let self else { return }
            if let failure {
                Log.write("install failed")
                self.engine.setFailed(failure)
            } else {
                Log.write("install done")
                self.engine.start()
            }
        })
    }

    func restartEngine() { engine.restart() }

    // MARK: 授權與設定

    func request(_ kind: PermissionKind) {
        Permissions.request(kind)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
    }

    private func refreshPermissions() {
        let now = PermissionState.current()
        guard now != permissions else { return }
        let gainedInput = now.inputMonitoring && !permissions.inputMonitoring
        permissions = now
        // 授權之前建立的全域監聽可能一直收不到事件，授權後重建。
        if gainedInput { hotkey.start() }
    }

    func captureHotkey() {
        isCapturingHotkey = true
        hotkey.capture { [weak self] code, isMod, label in
            guard let self else { return }
            self.isCapturingHotkey = false
            guard code >= 0 else { return }
            self.settings.hotkeyKeyCode = code
            self.settings.hotkeyIsModifier = isMod
            self.settings.hotkeyLabel = label
        }
    }

    func cancelCapture() {
        hotkey.cancelCapture()
        isCapturingHotkey = false
    }

    private func configureHotkey() {
        hotkey.keyCode = settings.hotkeyKeyCode
        hotkey.isModifier = settings.hotkeyIsModifier
    }

    private func applySettings(old: Settings) {
        configureHotkey()
        guard settings.launchAtLogin != old.launchAtLogin else { return }
        do {
            if settings.launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = "無法變更開機自動啟動：\(error.localizedDescription)"
            settings.launchAtLogin = old.launchAtLogin
        }
    }
}
