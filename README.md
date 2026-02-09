# openclaw-feishu

OpenClaw 飞书插件（优化版），基于官方 `@openclaw/feishu` 插件改造。

## 优化内容

在原版基础上增加了 **Probe 状态检测缓存机制**：

- Gateway 启动时调用飞书 `/open-apis/bot/v3/info` 接口进行状态检测，并将结果缓存到内存
- 后续的状态检查直接从内存缓存中读取，不再重复调用 API
- 缓存过期时间为 **24 小时**，过期后自动重新调用接口刷新
- 支持 `force: true` 参数强制绕过缓存
- 错误结果同样缓存，避免对故障端点的重复请求

> 📖 技术细节详见 [Probe 缓存机制技术详解](docs/probe-cache-mechanism.md)

## 改动文件

| 文件 | 说明 |
|------|------|
| `src/probe-cache.ts` | 新增：内存缓存模块（24h TTL） |
| `src/probe.ts` | 改造：集成缓存读写逻辑 |
| `src/channel.ts` | 改造：gateway 启动时预热缓存 |
| `index.ts` | 改造：导出缓存工具函数 |

## 基于

- `@openclaw/feishu` v2026.2.6-3
- OpenClaw 2026.2.6-3
