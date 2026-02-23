# openclaw-feishu

**简体中文** | [English](README.en.md)

OpenClaw 飞书插件（优化版），基于官方 `@openclaw/feishu` 插件改造。

## 优化内容

### Probe 状态检测缓存

- Gateway 启动时调用飞书 `/open-apis/bot/v3/info` 接口进行状态检测，并将结果缓存到内存
- 后续的状态检查直接从内存缓存中读取，不再重复调用 API
- 缓存过期时间为 **24 小时**，过期后自动重新调用接口刷新
- 支持 `force: true` 参数强制绕过缓存
- 错误结果同样缓存，避免对故障端点的重复请求

> 📖 技术细节详见 [Probe 缓存机制技术详解](docs/probe-cache-mechanism.md)

### 语音消息自动转文字（faster-whisper）

收到飞书语音消息后，自动通过 [faster-whisper](https://github.com/SYSTRAN/faster-whisper) 转写为文本，agent 直接收到文字内容。

**前置依赖：**
```bash
pip3 install faster-whisper
```

**可选配置（`channels.feishu`）：**
- `whisperModel` — whisper 模型大小，默认 `"base"`，可选 `"tiny"` / `"small"` / `"medium"` / `"large-v3"` 等

**工作流程：**
1. 收到 `audio` 类型消息 → 下载音频文件
2. 调用 Python 子进程执行 faster-whisper 转写
3. 转写结果替换原始消息内容，agent 收到纯文本

> 📖 详细说明见 [语音转文字配置指南](docs/voice-to-text-setup.md)

### Typing Indicator 优化

飞书 Bot 处理消息时的"正在输入"状态指示器（基于 reaction），支持配置化控制：

- 可完全关闭，避免不必要的 API 调用
- 可自定义刷新间隔（默认 6 秒），降低 API 配额消耗
- 插件层节流，不依赖框架修改

```jsonc
// ~/.openclaw/openclaw.json → channels.feishu
{
  "typingIndicator": {
    "enabled": false,       // 关闭 typing indicator
    "intervalSeconds": 30   // 或调大刷新间隔
  }
}
```

> 📖 详细说明见 [Typing Indicator 配置说明](docs/typing-indicator.md)

### 流式卡片（Streaming Card）

基于飞书 Card Kit 流式 API，实现实时文本输出效果：

- 回复时先显示"⏳ Thinking..."占位卡片
- 模型生成过程中增量更新卡片内容
- 生成完成后关闭流式模式，显示最终结果
- 自动节流（100ms），避免 API 限流

通过 `channels.feishu.streaming` 配置开关（默认开启）。

### 备份与还原

完整备份 OpenClaw 所有数据（配置、聊天记录、记忆、媒体文件等），支持跨系统迁移。

```bash
./scripts/openclaw-backup.sh backup           # 创建备份
./scripts/openclaw-backup.sh restore <file>   # 还原
```

> 📖 详细说明见 [备份与还原指南](docs/backup-restore.md)

## v2026.2.22 合并的上游变更

本版本合并了官方 `@openclaw/feishu` v2026.2.22 的所有变更：

- **持久化消息去重**（`dedup.ts`）：基于内存 + 磁盘的 24h TTL 去重，重启后不会重复处理消息
- **外部 Key 校验**（`external-keys.ts`）：对飞书 API 返回的 image_key/file_key 进行安全校验
- **发送结果辅助**（`send-result.ts`）：统一的 API 响应断言和结果转换
- **流式卡片**（`streaming-card.ts`）：Card Kit 流式 API 实时文本输出
- **安全加固**：
  - `mention.ts`：`escapeRegExp` 防止正则注入
  - `policy.ts`：移除 senderName 匹配，仅基于 ID 的 allowlist 检查，使用 SDK `AllowlistMatch`
  - `monitor.ts`：Webhook 请求体大小限制、超时、速率限制、Content-Type 校验
- **SDK 对齐**：
  - `channel.ts`：使用 `buildBaseChannelStatusSummary`、`createDefaultChannelRuntimeState`、`resolveAllowlistProviderRuntimeGroupPolicy`
  - `bot.ts`：使用 `resolveOpenProviderRuntimeGroupPolicy`、`buildAgentMediaPayload`、增强的 `checkBotMentioned`（支持 post 消息）、完整的 DM pairing 流程
  - `types.ts`：使用 `BaseProbeResult`
  - `config-schema.ts`：`StreamingModeSchema`、`webhookHost`、`FeishuSharedConfigShape` 提取、webhook `verificationToken` 校验

## 改动文件

| 文件 | 说明 |
|------|------|
| `src/dedup.ts` | 新增：持久化消息去重（上游） |
| `src/external-keys.ts` | 新增：外部 Key 安全校验（上游） |
| `src/send-result.ts` | 新增：发送结果辅助函数（上游） |
| `src/streaming-card.ts` | 新增：Card Kit 流式卡片（上游） |
| `src/probe-cache.ts` | 自定义：内存缓存模块（24h TTL） |
| `src/probe.ts` | 自定义：集成缓存读写逻辑 |
| `src/voice-transcribe.ts` | 自定义：faster-whisper 语音转文字模块 |
| `src/channel.ts` | 合并：上游 SDK 对齐 + 自定义 probe 缓存预热 |
| `src/bot.ts` | 合并：上游重写 + 自定义语音转写集成 |
| `src/reply-dispatcher.ts` | 合并：上游流式卡片 + 自定义 typing 节流 |
| `src/config-schema.ts` | 上游：StreamingMode、webhookHost、superRefine |
| `src/mention.ts` | 上游：escapeRegExp 安全修复 |
| `src/policy.ts` | 上游：ID-only allowlist、senderIds |
| `src/send.ts` | 上游：使用 send-result 辅助 |
| `src/monitor.ts` | 上游：Webhook 安全加固 |
| `src/types.ts` | 上游：BaseProbeResult |
| `index.ts` | 合并：上游导出 + 自定义 probe-cache 导出 |

## 快速部署

```bash
git clone https://github.com/haotian2546/openclaw-feishu.git
cd openclaw-feishu
./scripts/deploy-voice.sh
```

脚本会自动完成：创建 Python 虚拟环境 → 安装 faster-whisper → 下载 Whisper 模型 → 部署插件文件 → 重启 Gateway。

如需指定模型大小（默认 `base`）：

```bash
./scripts/deploy-voice.sh large-v3
```

## 基于

- `@openclaw/feishu` v2026.2.22
- OpenClaw 2026.2.22
