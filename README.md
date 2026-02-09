# openclaw-feishu

OpenClaw 飞书插件（优化版），基于官方 `@openclaw/feishu` 插件改造。

## 优化内容

### Probe 状态检测缓存

- Gateway 启动时调用飞书 `/open-apis/bot/v3/info` 接口进行状态检测，并将结果缓存到内存
- 后续的状态检查直接从内存缓存中读取，不再重复调用 API
- 缓存过期时间为 **24 小时**，过期后自动重新调用接口刷新
- 支持 `force: true` 参数强制绕过缓存

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

## 改动文件

| 文件 | 说明 |
|------|------|
| `src/probe-cache.ts` | 新增：内存缓存模块（24h TTL） |
| `src/probe.ts` | 改造：集成缓存读写逻辑 |
| `src/channel.ts` | 改造：gateway 启动时预热缓存 |
| `src/voice-transcribe.ts` | 新增：faster-whisper 语音转文字模块 |
| `src/bot.ts` | 改造：audio 消息自动转写为文本 |
| `index.ts` | 改造：导出缓存工具函数 |

## 基于

- `@openclaw/feishu` v2026.2.6-3
- OpenClaw 2026.2.6-3
