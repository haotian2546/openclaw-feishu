#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OpenClaw 完整备份与还原工具
# 支持跨系统迁移，保留所有数据
# ============================================================

VERSION="1.0.0"
OPENCLAW_DIR="${OPENCLAW_HOME:-$HOME/.openclaw}"
BACKUP_DIR="${OPENCLAW_BACKUP_DIR:-$HOME/openclaw-backups}"
DATE_TAG=$(date +%Y%m%d_%H%M%S)

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
  cat <<EOF
OpenClaw 备份还原工具 v${VERSION}

用法:
  $0 backup  [--output <path>]  [--no-media]  [--encrypt]
  $0 restore <backup_file>      [--dry-run]   [--force]
  $0 list
  $0 info    <backup_file>

命令:
  backup   创建完整备份
  restore  从备份还原
  list     列出所有本地备份
  info     查看备份详情

备份选项:
  --output <path>   指定输出路径（默认 ~/openclaw-backups/）
  --no-media        不备份媒体文件（语音、图片等）
  --encrypt         使用密码加密备份（gpg）

还原选项:
  --dry-run         仅预览，不实际还原
  --force           覆盖已有数据（默认会提示确认）

环境变量:
  OPENCLAW_HOME       OpenClaw 数据目录（默认 ~/.openclaw）
  OPENCLAW_BACKUP_DIR 备份存储目录（默认 ~/openclaw-backups）

示例:
  $0 backup                          # 完整备份
  $0 backup --no-media               # 不含媒体文件的轻量备份
  $0 backup --encrypt                # 加密备份
  $0 restore openclaw_20260209.tar.gz  # 还原
  $0 list                            # 查看所有备份
EOF
}

# ============================================================
# 备份
# ============================================================
do_backup() {
  local output_dir="$BACKUP_DIR"
  local include_media=true
  local encrypt=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output)   output_dir="$2"; shift 2 ;;
      --no-media) include_media=false; shift ;;
      --encrypt)  encrypt=true; shift ;;
      *) err "未知选项: $1"; exit 1 ;;
    esac
  done

  if [ ! -d "$OPENCLAW_DIR" ]; then
    err "OpenClaw 目录不存在: $OPENCLAW_DIR"
    exit 1
  fi

  mkdir -p "$output_dir"

  local backup_name="openclaw_${DATE_TAG}"
  local tmp_dir=$(mktemp -d)
  local staging="$tmp_dir/$backup_name"
  mkdir -p "$staging"

  info "开始备份 OpenClaw 数据..."
  info "源目录: $OPENCLAW_DIR"

  # --- 核心配置 ---
  info "备份核心配置..."
  cp "$OPENCLAW_DIR/openclaw.json" "$staging/" 2>/dev/null && ok "openclaw.json" || warn "openclaw.json 不存在"
  for bak in "$OPENCLAW_DIR"/openclaw.json.bak*; do
    [ -f "$bak" ] && cp "$bak" "$staging/"
  done

  # --- Agent 数据（聊天记录、会话、模型配置） ---
  if [ -d "$OPENCLAW_DIR/agents" ]; then
    info "备份 Agent 数据（聊天记录、会话）..."
    cp -r "$OPENCLAW_DIR/agents" "$staging/agents"
    local session_count=$(find "$staging/agents" -name "*.jsonl" 2>/dev/null | wc -l)
    local session_size=$(du -sh "$staging/agents" 2>/dev/null | cut -f1)
    ok "agents ($session_count 个会话, $session_size)"
  fi

  # --- Workspace（记忆、人设、技能） ---
  if [ -d "$OPENCLAW_DIR/workspace" ]; then
    info "备份 Workspace（记忆、人设、技能）..."
    cp -r "$OPENCLAW_DIR/workspace" "$staging/workspace"
    ok "workspace"
  fi

  # --- 设备配对信息 ---
  if [ -d "$OPENCLAW_DIR/devices" ]; then
    info "备份设备配对信息..."
    cp -r "$OPENCLAW_DIR/devices" "$staging/devices"
    ok "devices"
  fi

  # --- 身份认证 ---
  if [ -d "$OPENCLAW_DIR/identity" ]; then
    info "备份身份认证..."
    cp -r "$OPENCLAW_DIR/identity" "$staging/identity"
    ok "identity"
  fi

  # --- 凭据 ---
  if [ -d "$OPENCLAW_DIR/credentials" ]; then
    info "备份凭据..."
    cp -r "$OPENCLAW_DIR/credentials" "$staging/credentials"
    ok "credentials"
  fi

  # --- 定时任务 ---
  if [ -d "$OPENCLAW_DIR/cron" ]; then
    info "备份定时任务..."
    cp -r "$OPENCLAW_DIR/cron" "$staging/cron"
    ok "cron"
  fi

  # --- 执行审批 ---
  [ -f "$OPENCLAW_DIR/exec-approvals.json" ] && cp "$OPENCLAW_DIR/exec-approvals.json" "$staging/"

  # --- Canvas ---
  if [ -d "$OPENCLAW_DIR/canvas" ]; then
    cp -r "$OPENCLAW_DIR/canvas" "$staging/canvas"
    ok "canvas"
  fi

  # --- 媒体文件 ---
  if $include_media && [ -d "$OPENCLAW_DIR/media" ]; then
    info "备份媒体文件..."
    cp -r "$OPENCLAW_DIR/media" "$staging/media"
    local media_size=$(du -sh "$staging/media" 2>/dev/null | cut -f1)
    local media_count=$(find "$staging/media" -type f 2>/dev/null | wc -l)
    ok "media ($media_count 个文件, $media_size)"
  elif ! $include_media; then
    warn "跳过媒体文件（--no-media）"
  fi

  # --- 写入元数据 ---
  cat > "$staging/.backup-meta.json" <<METAEOF
{
  "version": "$VERSION",
  "createdAt": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "os": "$(uname -s)-$(uname -m)",
  "openclawDir": "$OPENCLAW_DIR",
  "includeMedia": $include_media,
  "encrypted": $encrypt
}
METAEOF

  # --- 打包 ---
  local archive="$output_dir/${backup_name}.tar.gz"
  info "打包中..."
  tar -czf "$archive" -C "$tmp_dir" "$backup_name"
  rm -rf "$tmp_dir"

  # --- 加密 ---
  if $encrypt; then
    info "加密备份..."
    if command -v gpg &>/dev/null; then
      gpg --symmetric --cipher-algo AES256 "$archive"
      rm "$archive"
      archive="${archive}.gpg"
      ok "已加密"
    else
      warn "gpg 未安装，跳过加密"
    fi
  fi

  local final_size=$(du -sh "$archive" | cut -f1)
  echo ""
  ok "备份完成！"
  echo -e "  文件: ${GREEN}$archive${NC}"
  echo -e "  大小: $final_size"
  echo ""
}

# ============================================================
# 还原
# ============================================================
do_restore() {
  local backup_file="$1"; shift
  local dry_run=false
  local force=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=true; shift ;;
      --force)   force=true; shift ;;
      *) err "未知选项: $1"; exit 1 ;;
    esac
  done

  if [ ! -f "$backup_file" ]; then
    err "备份文件不存在: $backup_file"
    exit 1
  fi

  # 处理加密文件
  local archive="$backup_file"
  if [[ "$backup_file" == *.gpg ]]; then
    info "检测到加密备份，解密中..."
    archive="${backup_file%.gpg}"
    gpg --decrypt --output "$archive" "$backup_file"
    ok "解密完成"
  fi

  # 解压到临时目录
  local tmp_dir=$(mktemp -d)
  if [[ "$archive" == *.zip ]]; then
    unzip -q "$archive" -d "$tmp_dir"
  else
    tar -xzf "$archive" -C "$tmp_dir"
  fi

  # 找到备份根目录
  local backup_root=$(find "$tmp_dir" -name ".backup-meta.json" -exec dirname {} \; | head -1)
  if [ -z "$backup_root" ]; then
    err "无效的备份文件（缺少元数据）"
    rm -rf "$tmp_dir"
    exit 1
  fi

  # 显示备份信息
  echo ""
  info "备份信息:"
  python3 -c "
import json, sys
with open('$backup_root/.backup-meta.json') as f:
    m = json.load(f)
print(f'  创建时间: {m[\"createdAt\"]}')
print(f'  来源主机: {m[\"hostname\"]}')
print(f'  来源系统: {m[\"os\"]}')
print(f'  含媒体:   {m[\"includeMedia\"]}')
" 2>/dev/null || cat "$backup_root/.backup-meta.json"

  # 列出将还原的内容
  echo ""
  info "将还原以下内容到 $OPENCLAW_DIR:"
  for item in "$backup_root"/*; do
    local name=$(basename "$item")
    [ "$name" = ".backup-meta.json" ] && continue
    if [ -d "$item" ]; then
      local count=$(find "$item" -type f | wc -l)
      local size=$(du -sh "$item" | cut -f1)
      echo "  📁 $name/ ($count 个文件, $size)"
    else
      local size=$(du -sh "$item" | cut -f1)
      echo "  📄 $name ($size)"
    fi
  done

  if $dry_run; then
    echo ""
    warn "预览模式，未执行还原"
    rm -rf "$tmp_dir"
    return
  fi

  # 确认
  if ! $force; then
    echo ""
    echo -e "${YELLOW}⚠️  还原将覆盖 $OPENCLAW_DIR 中的同名文件${NC}"
    read -p "确认还原？(y/N) " confirm
    if [[ "$confirm" != [yY] ]]; then
      info "已取消"
      rm -rf "$tmp_dir"
      return
    fi
  fi

  # 还原前备份当前数据
  if [ -d "$OPENCLAW_DIR" ]; then
    local pre_restore_backup="$BACKUP_DIR/pre_restore_${DATE_TAG}.tar.gz"
    mkdir -p "$BACKUP_DIR"
    info "还原前自动备份当前数据到 $pre_restore_backup ..."
    tar -czf "$pre_restore_backup" -C "$(dirname "$OPENCLAW_DIR")" "$(basename "$OPENCLAW_DIR")" 2>/dev/null || true
    ok "当前数据已备份"
  fi

  # 执行还原
  mkdir -p "$OPENCLAW_DIR"
  info "正在还原..."

  for item in "$backup_root"/*; do
    local name=$(basename "$item")
    [ "$name" = ".backup-meta.json" ] && continue
    if [ -d "$item" ]; then
      rm -rf "$OPENCLAW_DIR/$name"
      cp -r "$item" "$OPENCLAW_DIR/$name"
      ok "$name/"
    else
      cp "$item" "$OPENCLAW_DIR/$name"
      ok "$name"
    fi
  done

  rm -rf "$tmp_dir"

  # 清理加密解压的临时文件
  if [[ "$backup_file" == *.gpg ]] && [ -f "$archive" ]; then
    rm "$archive"
  fi

  echo ""
  ok "还原完成！"
  warn "请重启 OpenClaw Gateway 使配置生效："
  echo "  openclaw gateway restart"
  echo ""
}

# ============================================================
# 列出备份
# ============================================================
do_list() {
  if [ ! -d "$BACKUP_DIR" ]; then
    info "暂无备份（目录 $BACKUP_DIR 不存在）"
    return
  fi

  local files=$(find "$BACKUP_DIR" -maxdepth 1 \( -name "openclaw_*.tar.gz*" -o -name "openclaw_*.zip" \) -type f 2>/dev/null | sort -r)
  if [ -z "$files" ]; then
    info "暂无备份"
    return
  fi

  echo ""
  echo "OpenClaw 备份列表 ($BACKUP_DIR):"
  echo "─────────────────────────────────────────────────"
  printf "%-42s %8s  %s\n" "文件名" "大小" "日期"
  echo "─────────────────────────────────────────────────"

  while IFS= read -r f; do
    local name=$(basename "$f")
    local size=$(du -sh "$f" | cut -f1)
    local date=$(stat -c %y "$f" 2>/dev/null | cut -d. -f1 || stat -f %Sm "$f" 2>/dev/null)
    printf "%-42s %8s  %s\n" "$name" "$size" "$date"
  done <<< "$files"
  echo ""
}

# ============================================================
# 查看备份详情
# ============================================================
do_info() {
  local backup_file="$1"
  if [ ! -f "$backup_file" ]; then
    err "文件不存在: $backup_file"
    exit 1
  fi

  local tmp_dir=$(mktemp -d)

  if [[ "$backup_file" == *.gpg ]]; then
    info "加密备份，需要密码查看"
    local decrypted="${tmp_dir}/decrypted.tar.gz"
    gpg --decrypt --output "$decrypted" "$backup_file"
    tar -xzf "$decrypted" -C "$tmp_dir"
  elif [[ "$backup_file" == *.zip ]]; then
    unzip -q "$backup_file" -d "$tmp_dir"
  else
    tar -xzf "$backup_file" -C "$tmp_dir"
  fi

  local backup_root=$(find "$tmp_dir" -name ".backup-meta.json" -exec dirname {} \; | head -1)
  if [ -z "$backup_root" ]; then
    err "无效的备份文件"
    rm -rf "$tmp_dir"
    exit 1
  fi

  echo ""
  echo "═══════════════════════════════════════"
  echo " 备份详情: $(basename "$backup_file")"
  echo "═══════════════════════════════════════"

  python3 -c "
import json
with open('$backup_root/.backup-meta.json') as f:
    m = json.load(f)
print(f'  版本:     {m[\"version\"]}')
print(f'  创建时间: {m[\"createdAt\"]}')
print(f'  来源主机: {m[\"hostname\"]}')
print(f'  来源系统: {m[\"os\"]}')
print(f'  含媒体:   {m[\"includeMedia\"]}')
print(f'  已加密:   {m[\"encrypted\"]}')
" 2>/dev/null || cat "$backup_root/.backup-meta.json"

  echo ""
  echo "  内容:"
  for item in "$backup_root"/*; do
    local name=$(basename "$item")
    [ "$name" = ".backup-meta.json" ] && continue
    if [ -d "$item" ]; then
      local count=$(find "$item" -type f | wc -l)
      local size=$(du -sh "$item" | cut -f1)
      echo "    📁 $name/ ($count 个文件, $size)"
    else
      local size=$(du -sh "$item" | cut -f1)
      echo "    📄 $name ($size)"
    fi
  done

  local total_size=$(du -sh "$backup_file" | cut -f1)
  echo ""
  echo "  压缩包大小: $total_size"
  echo ""

  rm -rf "$tmp_dir"
}

# ============================================================
# 主入口
# ============================================================
case "${1:-}" in
  backup)  shift; do_backup "$@" ;;
  restore)
    shift
    if [ $# -lt 1 ]; then
      err "请指定备份文件路径"
      echo "用法: $0 restore <backup_file> [--dry-run] [--force]"
      exit 1
    fi
    do_restore "$@"
    ;;
  list)    do_list ;;
  info)
    shift
    if [ $# -lt 1 ]; then
      err "请指定备份文件路径"
      exit 1
    fi
    do_info "$1"
    ;;
  -h|--help|help) usage ;;
  *)
    usage
    exit 1
    ;;
esac
