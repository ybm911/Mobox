import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("MLX 模型") {
                HStack {
                    Picker("选择模型", selection: $model.modelIdentifier) {
                        ForEach(model.modelCatalog.models) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    .onChange(of: model.modelIdentifier) { _, identifier in model.selectModel(identifier) }
                    Button {
                        Task { await model.modelCatalog.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.modelCatalog.isRefreshing)
                    .help("刷新 Hy-MT2 模型列表")
                }
                if let selected = model.modelCatalog.model(for: model.modelIdentifier) {
                    Text(selected.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextField("模型名称或本地路径", text: $model.modelIdentifier)
                HStack {
                    if let url = model.modelDownloader.repositoryURL {
                        Link("查看模型页面", destination: url)
                    }
                    Spacer()
                    if model.modelDownloader.isDownloading {
                        Button("取消下载", role: .destructive) { model.modelDownloader.cancel() }
                    } else if model.modelDownloader.isDownloaded {
                        Label("已下载", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("重新下载") { model.redownloadSelectedModel() }
                    } else {
                        Button("下载所选模型") { model.downloadSelectedModel() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if model.modelDownloader.isDownloading {
                    ProgressView(value: model.modelDownloader.progress ?? 0)
                }
                if model.modelDownloader.isDownloading {
                    Text(model.modelDownloader.progressLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(model.modelDownloader.statusMessage)
                    .font(.caption)
                    .foregroundStyle(model.modelDownloader.isDownloading ? .secondary : .primary)
                    .lineLimit(2)
                TextField("Python 命令", text: $model.pythonCommand)
                Text("推荐填入虚拟环境解释器，例如 ~/.venvs/lingyi-mlx/bin/python。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("模型服务端口：\(model.modelPort)", value: $model.modelPort, in: 1024...65535)
                HStack {
                    Text(model.mlxServer.statusMessage)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button(model.mlxServer.isRunning ? "停止" : "启动") {
                        model.mlxServer.isRunning ? model.stopModel() : model.startModel()
                    }
                }
            }

            Section("翻译接口") {
                Picker("提供范围", selection: $model.exposure) {
                    ForEach(ServerExposure.allCases) { exposure in
                        Text(exposure.title).tag(exposure)
                    }
                }
                .onChange(of: model.exposure) { _, value in model.applyExposure(value) }

                Stepper("接口端口：\(model.apiPort)", value: $model.apiPort, in: 1024...65535)
                HStack {
                    SecureField("接口令牌", text: $model.apiKey)
                    CopyButton(value: model.apiKey, label: "复制令牌")
                }
                Text(model.exposure.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.exposure != .disabled {
                    LabeledContent("本机地址") {
                        HStack(spacing: 8) {
                            Text(model.localAPIURL).textSelection(.enabled)
                            CopyButton(value: model.localAPIURL, label: "复制本机地址")
                        }
                    }
                    if model.exposure == .localNetwork {
                        LabeledContent("局域网地址") {
                            HStack(spacing: 8) {
                                Text(model.networkAPIURL).textSelection(.enabled)
                                CopyButton(value: model.networkAPIURL, label: "复制局域网地址")
                            }
                        }
                    }
                    Text(model.apiServer.statusMessage)
                        .font(.caption)
                        .foregroundStyle(model.apiServer.isRunning ? .green : .orange)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560)
        .onDisappear { model.savePreferences() }
        .task { await model.modelCatalog.refresh() }
    }
}

private struct CopyButton: View {
    let value: String
    let label: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } label: {
            Label(copied ? "已复制" : label, systemImage: copied ? "checkmark" : "doc.on.doc")
                .labelStyle(.iconOnly)
        }
        .help(copied ? "已复制" : label)
        .disabled(value.isEmpty)
    }
}
