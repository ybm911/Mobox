import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.mlxServer.isRunning ? "墨匣 · 模型已启动" : "墨匣 · 模型未启动")
        Divider()
        Button("打开翻译窗口") { openWindow(id: "main") }
        Button(model.mlxServer.isRunning ? "停止模型" : "启动模型") {
            model.mlxServer.isRunning ? model.stopModel() : model.startModel()
        }
        Menu("对外翻译接口") {
            ForEach(ServerExposure.allCases) { exposure in
                Button {
                    model.applyExposure(exposure)
                } label: {
                    if model.exposure == exposure { Label(exposure.title, systemImage: "checkmark") }
                    else { Text(exposure.title) }
                }
            }
            if model.exposure != .disabled {
                Divider()
                Text("端口 \(model.apiPort) · 需令牌")
            }
        }
        Divider()
        SettingsLink { Text("偏好设置…") }
        Button("退出墨匣") { NSApp.terminate(nil) }
    }
}
