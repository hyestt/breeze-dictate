import SwiftUI

struct SetupView: View {
    @ObservedObject var model: AppModel

    private var done: Bool { model.engineState == .ready && model.permissions.allGranted }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("① 安裝語音引擎") { engineStep.padding(8).frame(maxWidth: .infinity, alignment: .leading) }
            GroupBox("② 授權") {
                VStack(spacing: 10) {
                    ForEach(PermissionKind.allCases) { PermissionRow(model: model, kind: $0) }
                    Text("授權後若快捷鍵沒反應，結束後重新開啟 App。")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
            }
            GroupBox("③ 試試看") {
                Text("在任何輸入框按住「\(model.settings.hotkeyLabel)」說話，放開後文字會貼到游標處。")
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
            HStack {
                Spacer()
                Button(done ? "完成" : "稍後再說") { model.closeSetup?() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 500)
    }

    @ViewBuilder private var engineStep: some View {
        switch model.engineState {
        case .notInstalled:
            VStack(alignment: .leading, spacing: 8) {
                Text("首次使用要下載語音引擎與模型（約 1 GB），需要幾分鐘。")
                Button("安裝語音引擎") { model.install() }
            }
        case .installing(let step):
            HStack { ProgressView().controlSize(.small); Text(step) }
        case .starting:
            HStack { ProgressView().controlSize(.small); Text("引擎啟動中…") }
        case .ready:
            Label("引擎已就緒", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 8) {
                Text(reason).foregroundStyle(.red).textSelection(.enabled)
                HStack {
                    Button("重試安裝") { model.install() }
                    Button("重新啟動引擎") { model.restartEngine() }
                }
            }
        }
    }
}
