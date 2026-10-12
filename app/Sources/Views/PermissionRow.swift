import SwiftUI

struct PermissionRow: View {
    @ObservedObject var model: AppModel
    let kind: PermissionKind

    var body: some View {
        let granted = model.permissions.isGranted(kind)
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? .green : .secondary)
            VStack(alignment: .leading) {
                Text(kind.title)
                Text(kind.purpose).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(granted ? "已允許" : "未允許").foregroundStyle(.secondary)
            if !granted {
                Button("前往授權") { model.request(kind) }
            }
        }
    }
}
