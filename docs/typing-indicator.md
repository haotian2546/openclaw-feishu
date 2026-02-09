# Typing Indicator（输入状态指示器）配置说明

## 背景

飞书没有原生的"正在输入"API。OpenClaw 飞书插件通过给用户消息添加 **emoji reaction**（表情回应）来模拟输入状态指示，让用户知道 Bot 正在处理消息。

### 默认行为

OpenClaw SDK 内置了一个 typing controller，默认行为：
- 收到消息后，立即给该消息添加一个 reaction（表示"正在处理"）
- **每 6 秒**重新调用一次，刷新 reaction 状态
- Agent 回复完成后，移除 reaction

这意味着如果 Agent 思考 30 秒，会产生约 5 次 `POST /open-apis/im/v1/messages/{message_id}/reactions` API 调用。

### 问题

- 对于响应较慢的模型（如 large reasoning model），一次对话可能产生 10-20 次 reactions API 调用
- 飞书 API 有频率限制，大量 typing 心跳会消耗配额
- 在飞书开放平台的 API 调用日志中表现为大量重复的 reactions 请求

## 配置选项

在 `~/.openclaw/openclaw.json` 的 `channels.feishu` 中配置：

```jsonc
{
  "channels": {
    "feishu": {
      // ... 其他配置 ...
      "typingIndicator": {
        "enabled": true,         // 是否启用，默认 true
        "intervalSeconds": 30    // 刷新间隔（秒），默认 6
      }
    }
  }
}
```

### 参数说明

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enabled` | boolean | `true` | 是否启用 typing indicator。设为 `false` 完全关闭，不再调用 reactions API |
| `intervalSeconds` | number | `6` | reaction 刷新间隔（秒）。增大此值可减少 API 调用频率 |

### 配置示例

**完全关闭 typing indicator（推荐用于 API 配额紧张的场景）：**

```json
{
  "channels": {
    "feishu": {
      "typingIndicator": {
        "enabled": false
      }
    }
  }
}
```

**降低刷新频率（每 30 秒刷新一次）：**

```json
{
  "channels": {
    "feishu": {
      "typingIndicator": {
        "intervalSeconds": 30
      }
    }
  }
}
```

**保持默认（每 6 秒刷新，与原版行为一致）：**

不配置 `typingIndicator` 即可，或：

```json
{
  "channels": {
    "feishu": {
      "typingIndicator": {
        "enabled": true,
        "intervalSeconds": 6
      }
    }
  }
}
```

## 实现原理

### 架构

```
OpenClaw SDK (createTypingController)
  │
  │  每 6 秒调用 onReplyStart
  ▼
飞书插件 (reply-dispatcher.ts)
  │
  ├─ enabled=false → 直接返回，不调用 API
  │
  ├─ 节流检查：距上次调用 < intervalSeconds → 跳过
  │
  └─ 通过节流 → addTypingIndicator()
                    │
                    ▼
              POST /open-apis/im/v1/messages/{id}/reactions
```

### 节流机制

SDK 的 typing controller 固定每 6 秒触发一次回调，这个频率在框架层面无法通过插件配置修改。插件通过**回调层节流**实现自定义间隔：

```typescript
// SDK 每 6 秒调用一次 start 回调
start: async () => {
  if (!typingEnabled) return;           // 开关控制

  const intervalMs = (intervalSeconds ?? 6) * 1000;
  const now = Date.now();
  if (typingState && now - lastTypingCallAt < intervalMs) {
    return;                              // 节流：未到间隔，跳过
  }
  lastTypingCallAt = now;
  typingState = await addTypingIndicator(...);  // 实际 API 调用
}
```

例如配置 `intervalSeconds: 30`：
- SDK 仍然每 6 秒触发回调（第 0s、6s、12s、18s、24s、30s...）
- 但只有第 0s 和第 30s 的回调会真正调用 API
- 中间的 4 次回调被节流跳过

### API 调用对比

以 Agent 思考 60 秒为例：

| 配置 | reactions API 调用次数 |
|------|----------------------|
| 默认（6s） | ~10 次 |
| intervalSeconds: 15 | ~4 次 |
| intervalSeconds: 30 | ~2 次 |
| enabled: false | 0 次 |

## 修改的文件

| 文件 | 说明 |
|------|------|
| `src/reply-dispatcher.ts` | 读取 `typingIndicator` 配置，实现开关和节流逻辑 |

## 生效方式

修改配置后需要重启 Gateway：

```bash
openclaw gateway restart
```
