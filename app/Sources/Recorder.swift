import AVFoundation

/// 錄成 16 kHz、單聲道、PCM16 的暫存 wav，格式符合引擎要求。
@MainActor
final class Recorder {
    private var recorder: AVAudioRecorder?
    private var url: URL?

    var isRecording: Bool { recorder?.isRecording ?? false }

    func start() -> Bool {
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
        guard let r = try? AVAudioRecorder(url: file, settings: settings), r.record() else { return false }
        recorder = r
        url = file
        return true
    }

    func stop() -> (url: URL, duration: TimeInterval)? {
        guard let r = recorder, let u = url else { return nil }
        let d = r.currentTime
        r.stop()
        recorder = nil
        url = nil
        return (u, d)
    }
}
