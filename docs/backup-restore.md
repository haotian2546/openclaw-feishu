# OpenClaw 备份与还原指南

## 概述

完整备份 OpenClaw 的所有数据，支持跨系统迁移（Linux ↔ macOS ↔ Windows WSL）。

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

## 跨系统迁移流程

### 从旧机器导出

```bash
# 1. 创建完整备份
./scripts/openclaw-backup.sh backup

# 2. 备份文件在 ~/openclaw-backups/ 下
ls ~/openclaw-backups/

# 3. 传输到新机器（任选一种方式）
scp ~/openclaw-backups/openclaw_*.tar.gz user@new-machine:~/
# 或 U盘、网盘等
```

### 在新机器还原

```bash
# 1. 安装 OpenClaw（如果还没装）
# npm install -g openclaw

# 2. 克隆工具仓库
git clone https://github.com/haotian2546/openclaw-feishu.git
cd openclaw-feishu

# 3. 还原数据
./scripts/openclaw-backup.sh restore ~/openclaw_20260209_230000.tar.gz

# 4. 重启 Gateway
openclaw gateway restart
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
