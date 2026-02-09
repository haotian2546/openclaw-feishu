# OpenClaw 飞书语音转文字配置指南

## 功能概述

飞书用户发送语音消息后，插件自动通过 [faster-whisper](https://github.com/SYSTRAN/faster-whisper) 将语音转写为文本，agent 直接收到文字内容进行处理。

**工作流程：**

```
飞书语音消息 → 下载 .ogg 音频 → faster-whisper 转写 → 文本发给 agent
```

## 环境要求

| 依赖 | 最低版本 | 说明 |
|------|---------|------|
| Python | 3.9+ | 运行 faster-whisper |
| faster-whisper | 1.0+ | 语音识别引擎（基于 CTranslate2） |
| OpenClaw | 2026.2.6+ | 宿主平台 |

**硬件建议：**
- CPU 可用，但 NVIDIA GPU 会显著加速（自动检测 CUDA）
- 内存：base 模型约需 1GB，large-v3 约需 4GB

## 安装步骤

### 1. 创建 Python 虚拟环境并安装 faster-whisper

```bash
# 创建专用虚拟环境
python3 -m venv ~/.openclaw-whisper-venv

# 安装 faster-whisper
~/.openclaw-whisper-venv/bin/pip install faster-whisper
```

### 2. 预下载 Whisper 模型

首次转写时会自动下载模型，也可以提前下载避免等待：

```bash
# 国内网络需要设置 HuggingFace 镜像
export HF_ENDPOINT=https://hf-mirror.com

~/.openclaw-whisper-venv/bin/python3 -c "
from faster_whisper import WhisperModel
model = WhisperModel('base', device='auto', compute_type='auto')
print('模型下载完成')
"
```

### 3. 部署插件文件到 OpenClaw

将修改后的文件复制到 OpenClaw 的系统插件目录：

```bash
# 找到 OpenClaw 的飞书插件目录（通常是以下路径之一）
# 全局安装：/usr/lib/node_modules/openclaw/extensions/feishu/
# 用户安装：~/.openclaw/extensions/feishu/

PLUGIN_DIR=/usr/lib/node_modules/openclaw/extensions/feishu

# 复制文件
sudo cp src/voice-transcribe.ts $PLUGIN_DIR/src/voice-transcribe.ts
sudo cp src/bot.ts $PLUGIN_DIR/src/bot.ts
```

### 4. 重启 OpenClaw Gateway

```bash
openclaw gateway restart
```

## 配置选项

在 `~/.openclaw/openclaw.json` 的 `channels.feishu` 中可配置：

```jsonc
{
  "channels": {
    "feishu": {
      // ... 其他飞书配置 ...
      "whisperModel": "base"  // 可选，默认 "base"
    }
  }
}
```

### 可用模型

| 模型 | 大小 | 速度 | 精度 | 适用场景 |
|------|------|------|------|---------|
| `tiny` | ~75MB | 最快 | 较低 | 简单短语、低延迟场景 |
| `base` | ~150MB | 快 | 中等 | **推荐默认**，日常对话 |
| `small` | ~500MB | 中等 | 较高 | 需要更好识别效果 |
| `medium` | ~1.5GB | 较慢 | 高 | 专业内容、多语言混合 |
| `large-v3` | ~3GB | 慢 | 最高 | 最高精度需求 |

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `WHISPER_PYTHON` | `~/.openclaw-whisper-venv/bin/python3` | Python 解释器路径 |
| `HF_ENDPOINT` | `https://hf-mirror.com` | HuggingFace 镜像地址（国内网络） |

如需自定义 Python 路径，可在 OpenClaw 的 systemd service 中添加环境变量：

```bash
sudo systemctl edit openclaw-gateway
```

```ini
[Service]
Environment="WHISPER_PYTHON=/path/to/your/python3"
Environment="HF_ENDPOINT=https://hf-mirror.com"
```

## 涉及文件说明

| 文件 | 类型 | 说明 |
|------|------|------|
| `src/voice-transcribe.ts` | 新增 | faster-whisper 转写模块，通过 Python 子进程调用 |
| `src/bot.ts` | 修改 | `handleFeishuMessage` 中新增 audio 消息拦截和转写逻辑 |

### voice-transcribe.ts 核心逻辑

- 内嵌一段 Python 脚本，运行时写入 `/tmp/openclaw_whisper_transcribe.py`
- 通过 `child_process.execFile` 调用 Python 子进程执行转写
- 超时保护：默认 120 秒
- 输出 JSON 格式：`{"text": "转写文本", "language": "zh"}`

### bot.ts 修改点

在 `handleFeishuMessage` 函数中，media 下载完成后、构建 messageBody 之前，新增：

```typescript
// 当消息类型为 audio 且成功下载了媒体文件时
if (event.message.message_type === "audio" && mediaList.length > 0) {
  // 调用 faster-whisper 转写
  const result = await transcribeAudio({ audioPath: audioMedia.path });
  // 用转写文本替换原始消息内容
  ctx = { ...ctx, content: result.text, contentType: "text" };
}
```

## 故障排查

### 转写失败，日志显示 "Whisper transcription failed"

1. 检查 Python 环境：
   ```bash
   ~/.openclaw-whisper-venv/bin/python3 -c "from faster_whisper import WhisperModel; print('OK')"
   ```

2. 手动测试转写：
   ```bash
   ~/.openclaw-whisper-venv/bin/python3 -c "
   from faster_whisper import WhisperModel
   model = WhisperModel('base', device='auto', compute_type='auto')
   segments, info = model.transcribe('/path/to/audio.ogg')
   print(''.join(seg.text for seg in segments))
   "
   ```

### 模型下载失败（网络超时）

设置 HuggingFace 镜像：
```bash
export HF_ENDPOINT=https://hf-mirror.com
```

### 语音内容显示 "..." 或 "[语音消息，转写失败]"

- 确认插件文件已部署到正确目录
- 确认 gateway 已重启：`openclaw gateway restart`
- 查看日志：`journalctl -u openclaw-gateway -f`
