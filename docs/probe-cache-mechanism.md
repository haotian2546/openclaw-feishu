# Probe 缓存机制技术详解

## 背景问题

OpenClaw 飞书插件在运行过程中需要频繁检测飞书 Bot 的在线状态（Probe），原始实现每次检测都会调用飞书 API：

```
GET /open-apis/bot/v3/info
```

这带来几个问题：

1. **API 频率限制**：飞书对 API 调用有频率限制，频繁 probe 可能触发限流
2. **不必要的延迟**：每次状态查询都需要等待网络往返（RTT），在网络不稳定时尤为明显
3. **故障放大**：当飞书 API 暂时不可用时，重复请求会加重故障影响

## 解决方案概览

引入一个 **24 小时 TTL 的内存缓存层**，拦截在 `probeFeishu()` 和飞书 API 之间：

```
调用方
  │
  ▼
probeFeishu(creds, opts?)
  │
  ├─ opts.force = true ──────────────────┐
  │                                      │
  ├─ 检查缓存 ──→ 命中且未过期 → 返回    │
  │                                      │
  └─ 缓存未命中/已过期 ─────────────────→ │
                                         ▼
                              飞书 API /bot/v3/info
                                         │
                                         ▼
                                  写入缓存 + 返回
```

## 核心代码解析

### 1. 缓存模块 `probe-cache.ts`

```typescript
interface CacheEntry {
  result: FeishuProbeResult;
  cachedAt: number;
}

const CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24 小时
const cache = new Map<string, CacheEntry>();
```

缓存使用 `Map<string, CacheEntry>` 结构，key 为 `accountId`（支持多账号），value 包含探测结果和缓存时间戳。

**三个操作函数：**

| 函数 | 作用 |
|------|------|
| `getCachedProbe(key)` | 读取缓存，过期则自动删除并返回 `null` |
| `setCachedProbe(key, result)` | 写入缓存，记录当前时间戳 |
| `invalidateProbeCache(key?)` | 手动失效，传 key 删单条，不传清空全部 |

**过期判断逻辑：**

```typescript
export function getCachedProbe(key: string): FeishuProbeResult | null {
  const entry = cache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.cachedAt > CACHE_TTL_MS) {
    cache.delete(key);  // 惰性删除：访问时才清理过期条目
    return null;
  }
  return entry.result;
}
```

采用**惰性过期**策略——不设定时器，只在读取时检查是否过期。这避免了定时器的额外开销，对于低频访问的 probe 场景非常合适。

### 2. 探测函数 `probe.ts`

`probeFeishu()` 是对外的核心接口，整合了缓存读写和 API 调用：

```typescript
export async function probeFeishu(
  creds?: FeishuClientCredentials,
  opts?: { force?: boolean },
): Promise<FeishuProbeResult> {
```

**参数设计：**
- `creds` — 飞书应用凭据（appId、appSecret、domain），同时用 `accountId` 作为缓存 key
- `opts.force` — 强制绕过缓存，直接调用 API

**执行流程：**

```typescript
// 1. 凭据校验
if (!creds?.appId || !creds?.appSecret) {
  return { ok: false, error: "missing credentials" };
}

// 2. 缓存 key 确定（优先 accountId，回退 appId）
const cacheKey = creds.accountId ?? creds.appId;

// 3. 非强制模式下检查缓存
if (!opts?.force) {
  const cached = getCachedProbe(cacheKey);
  if (cached) return cached;
}

// 4. 调用飞书 API
const response = await client.request({
  method: "GET",
  url: "/open-apis/bot/v3/info",
});

// 5. 写入缓存（成功和失败都缓存）
setCachedProbe(cacheKey, result);
return result;
```

**关键设计决策——错误结果也缓存：**

```typescript
catch (err) {
  const result: FeishuProbeResult = {
    ok: false,
    appId: creds.appId,
    error: err instanceof Error ? err.message : String(err),
  };
  setCachedProbe(cacheKey, result);  // ← 错误也缓存
  return result;
}
```

这是有意为之的设计。当飞书 API 不可用时（网络故障、服务宕机），如果不缓存错误结果，每次 probe 都会重试并等待超时，造成：
- 请求堆积
- 响应延迟传导到上层
- 对已故障的端点持续施压

缓存错误结果后，24 小时内不会重复请求故障端点。如果需要立即重试，可以用 `force: true`。

### 3. Gateway 启动预热 `channel.ts`

```typescript
gateway: {
  startAccount: async (ctx) => {
    // ... 初始化 ...

    // 启动时强制调用 API，预热缓存
    ctx.log?.info(`probing feishu[${ctx.accountId}] on startup to warm cache…`);
    const probeResult = await probeFeishu(account, { force: true });

    if (probeResult.ok) {
      ctx.log?.info(`feishu[${ctx.accountId}] probe ok: bot=${probeResult.botName}`);
    } else {
      ctx.log?.warn(`feishu[${ctx.accountId}] probe failed: ${probeResult.error}`);
    }

    // ... 启动 WebSocket/Webhook 监听 ...
  },
}
```

Gateway 启动时使用 `force: true` 强制调用 API，确保：
1. 获取最新的 Bot 状态（而非可能残留的旧缓存）
2. 预热缓存，后续 24 小时内的 probe 请求直接命中缓存
3. 启动日志中记录 Bot 名称，便于运维确认

### 4. 状态查询入口 `channel.ts`

```typescript
status: {
  probeAccount: async ({ cfg, accountId }) => {
    const account = resolveFeishuAccount({ cfg, accountId });
    return await probeFeishu(account);  // 不传 force，走缓存
  },
}
```

日常状态查询不传 `force`，直接读缓存。只有 Gateway 重启时才强制刷新。

### 5. 外部导出 `index.ts`

```typescript
export { probeFeishu } from "./src/probe.js";
export { getCachedProbe, setCachedProbe, invalidateProbeCache } from "./src/probe-cache.js";
```

缓存操作函数也对外导出，允许外部代码：
- 读取缓存状态（`getCachedProbe`）
- 手动注入缓存（`setCachedProbe`）
- 强制失效（`invalidateProbeCache`）

## 多账号支持

缓存 key 使用 `accountId ?? appId`，天然支持多账号场景：

```
cache: Map {
  "default"    → { result: { ok: true, botName: "主Bot" }, cachedAt: ... },
  "account-2"  → { result: { ok: true, botName: "副Bot" }, cachedAt: ... },
}
```

每个账号独立缓存，互不影响。

## 数据流时序图

```
Gateway 启动
    │
    ▼
startAccount()
    │
    ├─ probeFeishu(account, { force: true })
    │       │
    │       ├─ 跳过缓存（force=true）
    │       ├─ GET /open-apis/bot/v3/info
    │       ├─ setCachedProbe("default", { ok: true, botName: "南柯Bot" })
    │       └─ 返回结果，日志输出 "probe ok"
    │
    ▼
正常运行中...
    │
    ├─ 用户查看状态 → probeAccount()
    │       │
    │       ├─ probeFeishu(account)  // 无 force
    │       ├─ getCachedProbe("default") → 命中！
    │       └─ 直接返回缓存结果（0ms，无 API 调用）
    │
    ├─ ... 24 小时后 ...
    │
    ├─ 用户查看状态 → probeAccount()
    │       │
    │       ├─ getCachedProbe("default") → 过期，返回 null
    │       ├─ GET /open-apis/bot/v3/info
    │       ├─ setCachedProbe("default", { ok: true, ... })
    │       └─ 返回新结果
```

## 设计取舍

| 决策 | 选择 | 理由 |
|------|------|------|
| 缓存位置 | 进程内存（Map） | probe 数据量极小，无需外部存储；进程重启时自动通过预热恢复 |
| 过期策略 | 惰性过期（读时检查） | 避免定时器开销，probe 访问频率低，惰性清理足够 |
| TTL 时长 | 24 小时 | Bot 状态变化极少，24h 是合理的平衡点 |
| 错误缓存 | 是 | 防止对故障端点的重复请求风暴 |
| 预热时机 | Gateway 启动时 | 确保首次查询零延迟，同时获取最新状态 |
| force 参数 | 可选 | 日常走缓存，特殊场景（启动、手动刷新）可绕过 |
