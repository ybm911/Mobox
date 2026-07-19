import SwiftUI

@MainActor
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("墨匣")
                        .font(.title2.weight(.semibold))
                    Text("离线 \(model.direction.title) · Hy-MT2 / MLX")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                serverStatus
            }
            .padding(24)

            HStack(spacing: 0) {
                TranslationEditor(
                    title: model.direction.sourceLabel,
                    text: $model.sourceText,
                    placeholder: model.direction.sourcePlaceholder,
                    footer: "\(model.sourceText.count) 个字符",
                    clear: { model.sourceText = "" }
                )

                Divider()

                Button {
                    model.toggleDirection()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .help("切换中英翻译方向")

                Divider()

                TranslationEditor(
                    title: model.direction.targetLabel,
                    text: $model.translatedText,
                    placeholder: model.direction.targetPlaceholder,
                    footer: model.activityMessage ?? "由本机模型生成",
                    isEditable: false,
                    clear: { model.translatedText = "" }
                )
            }
            .frame(maxHeight: .infinity)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 24)

            HStack {
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                } else {
                    Text(model.activityMessage ?? "⌘↵ 可快速翻译")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.translate() }
                } label: {
                    Label(model.isTranslating ? "翻译中…" : "翻译", systemImage: "arrow.right")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(model.isTranslating || model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(24)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(model.mlxServer.isRunning ? "停止模型" : "启动模型") {
                    model.mlxServer.isRunning ? model.stopModel() : model.startModel()
                }
            }
        }
        .onAppear { model.restoreSavedService() }
        .task { await model.checkForUpdatesAtLaunch() }
        .alert(
            "发现新版本 \(model.updater.latestRelease?.tagName ?? "")",
            isPresented: Binding(
                get: { model.updater.updateAvailable },
                set: { if !$0 { model.updater.dismissUpdate() } }
            )
        ) {
            Button(model.updater.isInstalling ? "正在安装…" : "下载并安装") {
                Task { await model.updater.downloadAndInstall() }
            }
            .disabled(model.updater.isInstalling)
            Button("稍后", role: .cancel) { model.updater.dismissUpdate() }
        } message: {
            Text("新版本会下载并安装到 ~/Applications/Mobox.app。")
        }
    }

    private var serverStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.mlxServer.isRunning ? .green : .secondary)
                .frame(width: 8, height: 8)
            Text(model.mlxServer.isRunning ? "模型服务运行中" : "模型服务未启动")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TranslationEditor: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let footer: String
    var isEditable = true
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button(action: clear) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("清空")
            }
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
                AlignedTextEditor(text: $text, isEditable: isEditable)
            }
            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
