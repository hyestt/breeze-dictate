import Foundation

enum Paths {
    static var support: URL {
        if let o = ProcessInfo.processInfo.environment["BREEZE_SUPPORT_DIR"], !o.isEmpty {
            return URL(fileURLWithPath: o, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("BreezeDictate", isDirectory: true)
    }
    static var resources: URL { Bundle.main.resourceURL ?? Bundle.main.bundleURL }
    static var settings: URL { support.appendingPathComponent("settings.json") }
    static var vocabulary: URL { support.appendingPathComponent("vocabulary.json") }
    static var venvPython: URL { support.appendingPathComponent("venv/bin/python") }
    static var model: URL { support.appendingPathComponent("model", isDirectory: true) }
    static var modelWeights: URL { model.appendingPathComponent("model.safetensors") }
    static var punctModel: URL { support.appendingPathComponent("punct-model", isDirectory: true) }
    static var appLog: URL { support.appendingPathComponent("app.log") }
    static var engineLog: URL { support.appendingPathComponent("engine.log") }

    static func ensureSupport() {
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    }
}

/// 只記狀態，不記錄辨識文字或按鍵內容。
enum Log {
    private static let queue = DispatchQueue(label: "breeze.log")
    static func write(_ message: String) {
        queue.async {
            let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let h = try? FileHandle(forWritingTo: Paths.appLog) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: data)
            } else {
                try? data.write(to: Paths.appLog)
            }
        }
    }
}

struct Settings: Codable, Equatable {
    var hotkeyKeyCode = 61
    var hotkeyIsModifier = true
    var hotkeyLabel = "右 Option"
    var launchAtLogin = false
    var playSound = false
    var punctuation = false

    init() {}

    // 缺欄位或格式錯誤時逐欄退回預設值。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        hotkeyKeyCode = (try? c.decodeIfPresent(Int.self, forKey: .hotkeyKeyCode)) ?? d.hotkeyKeyCode
        hotkeyIsModifier = (try? c.decodeIfPresent(Bool.self, forKey: .hotkeyIsModifier)) ?? d.hotkeyIsModifier
        hotkeyLabel = (try? c.decodeIfPresent(String.self, forKey: .hotkeyLabel)) ?? d.hotkeyLabel
        launchAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? d.launchAtLogin
        playSound = (try? c.decodeIfPresent(Bool.self, forKey: .playSound)) ?? d.playSound
        punctuation = (try? c.decodeIfPresent(Bool.self, forKey: .punctuation)) ?? d.punctuation
    }

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: Paths.settings),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return s
    }

    func save() {
        Paths.ensureSupport()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) { try? data.write(to: Paths.settings, options: .atomic) }
    }
}

struct VocabEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var target: String
    var variants: [String]

    enum CodingKeys: String, CodingKey { case target, variants }
}

enum VocabularyStore {
    static func load() -> [VocabEntry] {
        guard let data = try? Data(contentsOf: Paths.vocabulary),
              let v = try? JSONDecoder().decode([VocabEntry].self, from: data) else { return [] }
        return v
    }

    static func save(_ entries: [VocabEntry]) {
        Paths.ensureSupport()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? enc.encode(entries) { try? data.write(to: Paths.vocabulary, options: .atomic) }
    }

    static func seedIfMissing() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: Paths.vocabulary.path) else { return }
        Paths.ensureSupport()
        let seed = Paths.resources.appendingPathComponent("default_vocabulary.json")
        if (try? fm.copyItem(at: seed, to: Paths.vocabulary)) == nil { save([]) }
    }
}
