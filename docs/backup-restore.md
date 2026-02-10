# OpenClaw 备份与还原指南

## 概述

完整备份 OpenClaw 的所有数据，支持跨系统迁移（Linux ↔ macOS ↔ Windows）。

- Linux / macOS：使用 `scripts/openclaw-backup.sh`（备份为 `.tar.gz`）
- Windows：使用 `scripts\openclaw-backup.bat`（备份为 `.zip`）
- 两种格式**互相兼容**，还原时自动识别 `.tar.gz` 和 `.zip`

### 备份内容

| 数据 | 路径 | 说明 |
|------|------|------|
| 核心配置 | `openclaw.json` | 频道配置、模型配置、插件设置 |
| Agent 会话 | `agents/` | 聊天记录（.jsonl）、会话索引、模型绑定、认证配置 |
| Workspace | `workspace/` | 记忆（MEMORY.md）、人设（SOUL.md、IDENTITY.md）、技能、工具 |
| 设备配对 | `devices/` | 飞书等渠道的设备配对信息 |
| 身份认证 | `identity/` | 设备身份、OAuth 认证 |
| 凭据 | `credentials/` | API 密钥等凭据 |
| 定时任务 | `cron/` | 定时任务配置 |
| Canvas | `canvas/` | Canvas 页面 |
| 媒体文件 | `media/` | 语音、图片等收发的媒体文件 |

## 快速使用

### 备份

```bash
# 完整备份（含媒体文件）
./scripts/openclaw-backup.sh backup

# 轻量备份（不含媒体）
./scripts/openclaw-backup.sh backup --no-media

# 加密备份
./scripts/openclaw-backup.sh backup --encrypt

# 指定输出目录
./scripts/openclaw-backup.sh backup --output /mnt/usb/backups
```

### 还原

```bash
# 预览还原内容（不实际执行）
./scripts/openclaw-backup.sh restore openclaw_20260209_230000.tar.gz --dry-run

# 执行还原
./scripts/openclaw-backup.sh restore openclaw_20260209_230000.tar.gz

# 强制还原（跳过确认）
./scripts/openclaw-backup.sh restore openclaw_20260209_230000.tar.gz --force
```

### 管理备份

```bash
# 列出所有备份
./scripts/openclaw-backup.sh list

# 查看备份详情
./scripts/openclaw-backup.sh info openclaw_20260209_230000.tar.gz
```

## Windows 使用

```cmd
:: 完整备份
scripts\openclaw-backup.bat backup

:: 不含媒体的轻量备份
scripts\openclaw-backup.bat backup --no-media

:: 还原（支持 .zip 和 .tar.gz）
scripts\openclaw-backup.bat restore %USERPROFILE%\openclaw-backups\openclaw_20260209.zip

:: 预览还原内容
scripts\openclaw-backup.bat restore backup.zip --dry-run

:: 列出备份 / 查看详情
scripts\openclaw-backup.bat list
scripts\openclaw-backup.bat info backup.zip
```

Windows 版说明：
- 备份格式为 `.zip`（通过 PowerShell 压缩）
- 还原时同时支持 `.zip` 和 `.tar.gz`（Win10+ 自带 tar）
- 数据目录默认 `%USERPROFILE%\.openclaw`
- 备份目录默认 `%USERPROFILE%\openclaw-backups`
- 不支持 `--encrypt`（Windows 无内置 gpg，如需加密请单独安装 Gpg4win）

## 跨系统迁移流程

### Linux/macOS → Windows

```bash
# 旧机器（Linux/macOS）
./scripts/openclaw-backup.sh backup
# 将 ~/openclaw-backups/openclaw_*.tar.gz 拷贝到 Windows
```

```cmd
:: 新机器（Windows）—— 直接还原 tar.gz
scripts\openclaw-backup.bat restore C:\Users\you\openclaw_20260209.tar.gz
openclaw gateway restart
```

### Windows → Linux/macOS

```cmd
:: 旧机器（Windows）
scripts\openclaw-backup.bat backup
:: 将 %USERPROFILE%\openclaw-backups\openclaw_*.zip 拷贝到 Linux
```

```bash
# 新机器（Linux/macOS）—— 直接还原 zip
./scripts/openclaw-backup.sh restore ~/openclaw_20260209.zip
openclaw gateway restart
```

### 同系统迁移

```bash
# Linux/macOS
./scripts/openclaw-backup.sh backup
scp ~/openclaw-backups/openclaw_*.tar.gz user@new-machine:~/
# 新机器
./scripts/openclaw-backup.sh restore ~/openclaw_*.tar.gz
```

## 安全说明

- 备份包含敏感信息（API 密钥、OAuth Token），请妥善保管
- 建议使用 `--encrypt` 选项加密备份（需要 gpg）
- 还原前会自动备份当前数据到 `~/openclaw-backups/pre_restore_*.tar.gz`，可随时回滚
- 不备份 `completions/`（shell 补全，自动生成）和 `extensions/`（插件，通过 npm 安装）

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `OPENCLAW_HOME` | `~/.openclaw` | OpenClaw 数据目录 |
| `OPENCLAW_BACKUP_DIR` | `~/openclaw-backups` | 备份存储目录 |

## 还原后注意事项

1. **重启 Gateway**：`openclaw gateway restart`
2. **OAuth Token 可能过期**：如果迁移间隔较长，可能需要重新授权模型提供商
3. **飞书 WebSocket**：飞书连接会自动重建，无需额外操作
4. **插件**：需要在新机器上重新安装插件（`openclaw extension install feishu`）
