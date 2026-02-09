# openclaw-feishu

[简体中文](README.md) | **English**

Enhanced OpenClaw Feishu/Lark plugin, based on the official `@openclaw/feishu` plugin.

## Features

### Probe Status Cache

- On gateway startup, calls Feishu `/open-apis/bot/v3/info` to check bot status and caches the result in memory
- Subsequent status checks read directly from cache, no repeated API calls
- Cache TTL: **24 hours**, auto-refreshes after expiration
- Supports `force: true` to bypass cache
- Error results are also cached to prevent repeated requests to broken endpoints

> 📖 Technical details: [Probe Cache Mechanism Deep Dive](docs/probe-cache-mechanism.md)

### Voice-to-Text (faster-whisper)

Automatically transcribes Feishu voice messages to text via [faster-whisper](https://github.com/SYSTRAN/faster-whisper), so the agent receives plain text.

**Prerequisites:**
```bash
pip3 install faster-whisper
```

**Optional config (`channels.feishu`):**
- `whisperModel` — Whisper model size, default `"base"`, options: `"tiny"` / `"small"` / `"medium"` / `"large-v3"`

**Workflow:**
1. Receive `audio` message → download audio file
2. Call faster-whisper via Python subprocess
3. Transcribed text replaces original message content

> 📖 See [Voice-to-Text Setup Guide](docs/voice-to-text-setup.md)

### Typing Indicator Optimization

Configurable typing status indicator (reaction-based) for Feishu Bot:

- Can be fully disabled to avoid unnecessary API calls
- Customizable refresh interval (default 6s) to reduce API quota usage
- Plugin-layer throttling, no framework changes needed

```jsonc
// ~/.openclaw/openclaw.json → channels.feishu
{
  "typingIndicator": {
    "enabled": false,       // disable typing indicator
    "intervalSeconds": 30   // or increase refresh interval
  }
}
```

> 📖 See [Typing Indicator Configuration](docs/typing-indicator.md)

### Backup & Restore

Full backup of all OpenClaw data (config, chat history, memory, media, etc.) with cross-platform migration support.

```bash
./scripts/openclaw-backup.sh backup           # create backup
./scripts/openclaw-backup.sh restore <file>   # restore
```

> 📖 See [Backup & Restore Guide](docs/backup-restore.md)

## Modified Files

| File | Description |
|------|-------------|
| `src/probe-cache.ts` | New: in-memory cache module (24h TTL) |
| `src/probe.ts` | Modified: integrated cache read/write logic |
| `src/channel.ts` | Modified: cache warm-up on gateway startup |
| `src/voice-transcribe.ts` | New: faster-whisper voice-to-text module |
| `src/bot.ts` | Modified: auto-transcribe audio messages |
| `src/reply-dispatcher.ts` | Modified: typing indicator toggle & throttle |
| `index.ts` | Modified: export cache utility functions |

## Quick Deploy

```bash
git clone https://github.com/haotian2546/openclaw-feishu.git
cd openclaw-feishu
./scripts/deploy-voice.sh
```

The script automatically: creates Python venv → installs faster-whisper → downloads Whisper model → deploys plugin files → restarts Gateway.

To specify model size (default `base`):

```bash
./scripts/deploy-voice.sh large-v3
```

## Based On

- `@openclaw/feishu` v2026.2.6-3
- OpenClaw 2026.2.6-3