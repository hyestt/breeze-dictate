import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            GeneralTab(model: model).tabItem { Label("一般", systemImage: "gearshape") }
            VocabularyTab(model: model).tabItem { Label("詞彙", systemImage: "text.book.closed") }
            AboutTab().tabItem { Label("關於", systemImage: "info.circle") }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 400)
    }
}

private struct GeneralTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            LabeledContent("快捷鍵") {
                HStack {
                    Text(model.settings.hotkeyLabel).font(.body.monospaced())
                    if model.isCapturingHotkey {
                        Text("請按下新的鍵（Esc 取消）").foregroundStyle(.secondary)
                        Button("取消") { model.cancelCapture() }
                    } else {
                        Button("錄製快捷鍵") { model.captureHotkey() }
                    }
                }
            }
            Toggle("開機自動啟動", isOn: $model.settings.launchAtLogin)
            if let e = model.loginItemError { Text(e).font(.caption).foregroundStyle(.red) }
            Toggle("錄音開始與結束播放音效", isOn: $model.settings.playSound)
            PunctuationRow(model: model)
            Section("授權狀態") {
                ForEach(PermissionKind.allCases) { PermissionRow(model: model, kind: $0) }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PunctuationRow: View {
    @ObservedObject var model: AppModel

    private var installing: String? {
        if case .installing(let s) = model.punctuationInstall { return s }
        return nil
    }

    var body: some View {
        let isOn = Binding(get: { model.settings.punctuation || installing != nil },
                           set: { model.setPunctuation($0) })
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("自動加標點", isOn: isOn).disabled(installing != nil)
                if !model.punctuationInstalled && installing == nil {
                    Text("需額外下載約 1 GB").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let s = installing {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text(s).font(.caption) }
            }
            if case .failed(let reason) = model.punctuationInstall {
                Text("安裝失敗：\(reason)").font(.caption).foregroundStyle(.red)
            }
            if model.punctuationInstalled && installing == nil {
                Button("移除標點模型（釋放約 1 GB）") { model.removePunctuationModel() }
            }
            Text("模型只加標點，若偵測到有字被改動會自動退回沒有標點的版本。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct VocabularyTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("例：Claude ← cloud, 克勞德。左欄是正確寫法，右欄是常聽錯的寫法，用逗號分隔。")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach($model.vocabulary) { $entry in
                    VocabularyRow(entry: $entry) {
                        model.vocabulary.removeAll { $0.id == entry.id }
                    }
                }
            }
            HStack {
                Button("新增", systemImage: "plus") {
                    model.vocabulary.append(VocabEntry(target: "", variants: []))
                }
                Spacer()
                Text("\(model.vocabulary.count) 筆").foregroundStyle(.secondary)
            }
        }
    }
}

/// 此環境的 SDK 把 @State 做成巨集，純 swiftc 找不到外掛，所以用 StateObject 保存編輯中的文字。
private final class TextEditor: ObservableObject {
    @Published var text: String
    init(_ text: String) { self.text = text }
}

private struct VocabularyRow: View {
    @Binding var entry: VocabEntry
    let onDelete: () -> Void
    @StateObject private var editor: TextEditor

    init(entry: Binding<VocabEntry>, onDelete: @escaping () -> Void) {
        _entry = entry
        self.onDelete = onDelete
        _editor = StateObject(wrappedValue: TextEditor(entry.wrappedValue.variants.joined(separator: ", ")))
    }

    var body: some View {
        HStack {
            TextField("正確寫法", text: $entry.target).frame(width: 150)
            Text("←").foregroundStyle(.secondary)
            // 用本地字串編輯，否則輸入逗號時會被即時重新排版吃掉。
            TextField("常聽錯的寫法，逗號分隔", text: $editor.text)
                .onChange(of: editor.text) { _, new in
                    entry.variants = new.split(whereSeparator: { ",，、".contains($0) })
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
    }
}

private struct AboutTab: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "開發版"
    }

    var body: some View {
        Form {
            LabeledContent("版本", value: version)
            LabeledContent("語音模型", value: "Breeze-ASR-25（MLX 5-bit）")
            LabeledContent("模型授權", value: "Apache-2.0")
            LabeledContent("專案網址") {
                Link("github.com/hyestt/breeze-dictate",
                     destination: URL(string: "https://github.com/hyestt/breeze-dictate")!)
            }
        }
        .formStyle(.grouped)
    }
}
