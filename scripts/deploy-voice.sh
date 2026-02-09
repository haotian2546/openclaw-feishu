#!/usr/bin/env bash
set -euo pipefail

# OpenClaw 飞书语音转文字 - 一键部署脚本

VENV_PATH="${WHISPER_VENV:-$HOME/.openclaw-whisper-venv}"
PLUGIN_DIR="${OPENCLAW_FEISHU_DIR:-/usr/lib/node_modules/openclaw/extensions/feishu}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_SIZE="${1:-base}"

echo "=== OpenClaw 飞书语音转文字部署 ==="
echo "虚拟环境: $VENV_PATH"
echo "插件目录: $PLUGIN_DIR"
echo "Whisper 模型: $MODEL_SIZE"
echo ""

# 1. 创建虚拟环境
if [ ! -f "$VENV_PATH/bin/python3" ]; then
  echo "[1/4] 创建 Python 虚拟环境..."
  python3 -m venv "$VENV_PATH"
else
  echo "[1/4] 虚拟环境已存在，跳过"
fi

# 2. 安装 faster-whisper
echo "[2/4] 安装 faster-whisper..."
"$VENV_PATH/bin/pip" install -q faster-whisper

# 3. 预下载模型
echo "[3/4] 预下载 Whisper $MODEL_SIZE 模型..."
HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}" "$VENV_PATH/bin/python3" -c "
from faster_whisper import WhisperModel
WhisperModel('$MODEL_SIZE', device='auto', compute_type='auto')
print('模型就绪')
"

# 4. 部署插件文件
echo "[4/4] 部署插件文件到 $PLUGIN_DIR ..."
if [ -d "$PLUGIN_DIR/src" ]; then
  sudo cp "$SCRIPT_DIR/src/voice-transcribe.ts" "$PLUGIN_DIR/src/voice-transcribe.ts"
  sudo cp "$SCRIPT_DIR/src/bot.ts" "$PLUGIN_DIR/src/bot.ts"
  echo "文件已部署，正在重启 gateway..."
  openclaw gateway restart
  echo ""
  echo "=== 部署完成 ==="
else
  echo "警告: 插件目录 $PLUGIN_DIR/src 不存在"
  echo "请设置 OPENCLAW_FEISHU_DIR 环境变量指向正确路径后重试"
  exit 1
fi
