import Foundation

enum EngineState: Equatable {
    case notInstalled
    case installing(String)
    case starting
    case ready
    case failed(String)
}

struct EngineError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 子行程的 stdout 以位元組到達，這裡切成完整行。
final class LineBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        var lines: [String] = []
        while let i = data.firstIndex(of: 0x0A) {
            lines.append(String(decoding: data[data.startIndex..<i], as: UTF8.self))
            data.removeSubrange(data.startIndex...i)
        }
        return lines
    }
}

@MainActor
final class Engine {
    var onState: ((EngineState) -> Void)?
    private(set) var state: EngineState = .notInstalled {
        didSet { if state != oldValue { onState?(state) } }
    }

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var pending: [Int: CheckedContinuation<String, Error>] = [:]
    private var nextID = 1
    private var restartCount = 0
    private var generation = 0
    private var stopping = false

    static var isInstalled: Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: Paths.venvPython.path) && fm.fileExists(atPath: Paths.modelWeights.path)
    }

    func setInstalling(_ step: String) { state = .installing(step) }
    func setFailed(_ reason: String) { state = .failed(reason) }

    func start() {
        guard process == nil else { return }
        guard Self.isInstalled else { state = .notInstalled; return }
        stopping = false
        launch()
    }

    func restart() {
        stop()
        restartCount = 0
        start()
    }

    func stop() {
        stopping = true
        generation += 1
        let p = process
        process = nil
        stdinHandle = nil
        p?.terminate()
        failPending(EngineError(message: "引擎已停止"))
    }

    private func launch() {
        generation += 1
        let gen = generation
        state = .starting

        let p = Process()
        p.executableURL = Paths.venvPython
        p.arguments = ["-u", Paths.resources.appendingPathComponent("engine.py").path,
                       "--model", Paths.model.path, "--vocab", Paths.vocabulary.path]
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env

        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        FileManager.default.createFile(atPath: Paths.engineLog.path, contents: nil)
        p.standardError = (try? FileHandle(forWritingTo: Paths.engineLog)) ?? FileHandle.nullDevice

        let buffer = LineBuffer()
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            for line in buffer.append(d) {
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(line, gen: gen) } }
            }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.terminated(gen: gen) } }
        }

        do {
            try p.run()
        } catch {
            state = .failed("無法啟動引擎：\(error.localizedDescription)")
            return
        }
        process = p
        stdinHandle = inPipe.fileHandleForWriting
        Log.write("engine launched pid=\(p.processIdentifier)")
    }

    private func handle(_ line: String, gen: Int) {
        guard gen == generation,
              let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return }
        if obj["ready"] as? Bool == true {
            restartCount = 0
            state = .ready
            Log.write("engine ready")
            return
        }
        guard let id = obj["id"] as? Int, let cont = pending.removeValue(forKey: id) else { return }
        if let err = obj["error"] as? String {
            cont.resume(throwing: EngineError(message: err))
        } else {
            cont.resume(returning: obj["text"] as? String ?? "")
        }
    }

    private func terminated(gen: Int) {
        guard gen == generation else { return }
        process = nil
        stdinHandle = nil
        failPending(EngineError(message: "引擎中斷"))
        guard !stopping else { return }
        restartCount += 1
        Log.write("engine exited, restart \(restartCount)/3")
        guard restartCount <= 3 else {
            state = .failed("引擎連續中斷 3 次，詳見 engine.log")
            return
        }
        state = .starting
        let delay = Double(restartCount) * 2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.process == nil, !self.stopping, self.generation == gen else { return }
                self.launch()
            }
        }
    }

    private func failPending(_ error: Error) {
        let all = pending
        pending = [:]
        all.values.forEach { $0.resume(throwing: error) }
    }

    func transcribe(_ wav: URL) async throws -> String {
        guard state == .ready, let handle = stdinHandle else { throw EngineError(message: "引擎尚未就緒") }
        let id = nextID
        nextID += 1
        let req = try JSONSerialization.data(withJSONObject: ["id": id, "wav": wav.path])
        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            do {
                try handle.write(contentsOf: req + Data("\n".utf8))
            } catch {
                pending.removeValue(forKey: id)?.resume(throwing: EngineError(message: "無法送出請求給引擎"))
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                MainActor.assumeIsolated {
                    self?.pending.removeValue(forKey: id)?.resume(throwing: EngineError(message: "辨識逾時"))
                }
            }
        }
    }
}

/// 執行 bootstrap.sh，逐行回報 STEP 進度。
@MainActor
final class Installer {
    private(set) var isRunning = false

    func run(progress: @escaping (String) -> Void, completion: @escaping (String?) -> Void) {
        guard !isRunning else { return }
        isRunning = true
        Paths.ensureSupport()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [Paths.resources.appendingPathComponent("bootstrap.sh").path,
                       Paths.support.path, Paths.resources.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        let last = LastLine()
        let group = DispatchGroup()
        let buffer = LineBuffer()
        group.enter()
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; group.leave(); return }
            for line in buffer.append(d) {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty else { continue }
                last.set(t)
                if t.hasPrefix("STEP") { DispatchQueue.main.async { progress(t) } }
            }
        }
        group.enter()
        p.terminationHandler = { _ in group.leave() }

        do { try p.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            isRunning = false
            completion("無法執行安裝腳本：\(error.localizedDescription)")
            return
        }
        group.notify(queue: .main) { [weak self] in
            MainActor.assumeIsolated {
                self?.isRunning = false
                let ok = p.terminationStatus == 0
                completion(ok ? nil : (last.get() ?? "安裝失敗（結束碼 \(p.terminationStatus)）"))
            }
        }
    }
}

private final class LastLine: @unchecked Sendable {
    private var value: String?
    private let lock = NSLock()
    func set(_ s: String) { lock.lock(); value = s; lock.unlock() }
    func get() -> String? { lock.lock(); defer { lock.unlock() }; return value }
}
