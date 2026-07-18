# 墨匣（Mobox）

“匣”代表本地容器：模型封存在本机，翻译内容无需发送到第三方云端。墨匣是一个运行在 Apple Silicon Mac 上的离线中英翻译器，使用 MLX 与 [Hy-MT2 MLX](https://huggingface.co/collections/mlx-community/hy-mt2) 系列模型，并可选地为本机或局域网设备提供兼容 OpenAI Chat Completions 的翻译接口。

## 功能

- 中译英、英译中；点击中间的双箭头或按 **⌘⇧F** 切换方向。
- 按 **⌘↵** 翻译；主窗口会在模型加载、连接和翻译过程中显示状态。
- 在设置中下载、检测与重新下载模型，并显示下载进度。
- 选择 Hy-MT2 的全部 8 个 MLX 变体：1.8B / 7B 的默认 bf16、显式 bf16、8-bit 和 4-bit；联网时可刷新 Hugging Face 集合以获取新增项。
- 菜单栏控制模型及接口范围：关闭、仅本机、局域网。
- 退出应用时自动关闭 HTTP 端口、停止 MLX 子进程并取消模型下载。

## 首次使用

1. 创建虚拟环境并安装 MLX。不要把依赖装进 Homebrew 管理的系统 Python：

   ```bash
   python3 -m venv ~/.venvs/lingyi-mlx
   ~/.venvs/lingyi-mlx/bin/python -m pip install -U pip mlx-lm
   ```

2. 打开应用的“偏好设置”，将“Python 命令”设为：

   ```text
   ~/.venvs/lingyi-mlx/bin/python
   ```

3. 在“选择模型”中挑选合适的版本（1.8B 8-bit 为默认平衡选项），点击“下载所选模型”，完成后点击“启动模型”。已存在的模型会自动标记为“已下载”。
4. 在主窗口输入文字，按 **⌘↵** 或点击“翻译”。

模型缓存位置为：

```text
~/Library/Application Support/LingyiTranslate/HuggingFace
```

## 翻译接口

菜单栏的“对外翻译接口”可选择：

- **仅本机提供**：`http://127.0.0.1:8787/v1/chat/completions`
- **对局域网提供**：`http://<本机局域网IP>:8787/v1/chat/completions`

每个请求必须包含 `Authorization: Bearer <接口令牌>` 或 `X-API-Key: <接口令牌>`。

### 外部工具（沉浸式翻译等）配置

选择“仅本机提供”并启动模型后，在外部工具中填写：

```text
API 地址: http://127.0.0.1:8787/v1/chat/completions
API Key:  从墨匣设置复制“接口令牌”
```

该地址是 OpenAI Chat Completions 兼容端点；不要将外部工具配置为 `/translate`，因为外部工具会发送 Chat 消息格式。

模型名字段可填写任意 Hy-MT2 名称，服务会使用灵译当前已启动的本地模型。

### `POST /translate`

```json
{
  "text": "Good morning. How are you?"
}
```

响应：

```json
{
  "translation": "早上好。你好吗？",
  "translations": ["早上好。你好吗？"]
}
```

应用也提供 OpenAI 风格的 `POST /v1/chat/completions`。

## 本地构建

在项目根目录执行：

```bash
./script/build_and_run.sh
```

该命令会构建应用、生成 `dist/LingyiTranslate.app`，并启动它。应用图标资源为 `Resources/AppIcon.icns`。

## 开源说明

仓库只包含应用源码与构建资源；模型权重会在用户本机下载至应用支持目录，不会被提交到 Git。生成的应用包、Swift 构建缓存和本地 Codex 配置均已忽略。
