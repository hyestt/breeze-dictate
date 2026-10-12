import AVFoundation

/// 錄成 16 kHz、單聲道、PCM16 的暫存 wav，格式符合引擎要求。
@MainActor
final class Recorder {
    private var recorder: AVAudioRecorder?
    private var url: URL?
    private var prepared: (recorder: AVAudioRecorder, url: URL)?

    var isRecording: Bool { recorder?.isRecording ?? false }

    /// 先建好錄音器並準備緩衝，按下快捷鍵時 record() 幾乎立即開始，不會吃掉開頭的字。
    func prepare() {
        guard prepared == nil else { return }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("breeze-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        guard let r = try? AVAudioRecorder(url: file, settings: settings), r.prepareToRecord() else { return }
        prepared = (r, file)
    }

    func start() -> Bool {
        prepare()
        guard let p = prepared, p.recorder.record() else { return false }
        prepared = nil
        recorder = p.recorder
        url = p.url
        return true
    }

    func stop() -> (url: URL, duration: TimeInterval)? {
        guard let r = recorder, let u = url else { return nil }
        let d = r.currentTime
        r.stop()
        recorder = nil
        url = nil
        prepare()
        return (u, d)
    }
}
