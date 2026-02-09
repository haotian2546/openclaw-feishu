# 爆款标题（五选一）

1. **飞书 API 配额一天就炸了？我用 Claude Opus 4.6 溯源代码，揪出了两个"隐形杀手"**
2. **从被迫转 QQ 到重回飞书：一次 API 调用风暴的排查与根治全记录**
3. **OpenClaw + 飞书踩坑实录：每 6 秒一次的幽灵请求，差点让我放弃**
4. **让 AI 帮 AI 看病：用 Opus 4.6 给 OpenClaw 飞书插件做了一次"手术"**
5. **飞书 Bot API 配额告急？三个优化让调用量直降 99%，附完整代码**

---

# 从 API 配额爆炸到三重优化：OpenClaw 飞书插件的一次深度复盘

## 前言

最近在折腾 OpenClaw —— 一个开源的 AI Agent 框架，可以把大模型接入各种 IM 渠道。我第一时间接的飞书，毕竟日常办公早就飞书化了，能在飞书里直接跟 AI 对话，想想就很美好。

结果没美好几天，飞书开放平台的 API 调用量就拉满了。

## 一、问题发现：API 配额怎么一天就没了？

飞书开放平台对 API 调用有频率限制。我的使用量其实不大——每天也就几十条消息的交互，但后台的 API 调用日志却触目惊心，调用量远超预期。

当时没时间细查，先绕了个路：基于 OneBot 协议搓了一个 QQ 本地化方案。腾讯官方的 QQ 机器人需要服务器固定 IP 配置白名单，不满足我本地化部署的需求，所以走了非官方路线。

但用着总归不习惯。飞书才是我的主力工具，消息、文档、日程全在上面。

不死心，回头翻飞书的 API 调用日志，这一翻，翻出了问题。

## 二、问题定位：两个"隐形杀手"

### 杀手一：Probe 状态检测——每次查状态都打一枪

API 日志里，`GET /open-apis/bot/v3/info` 这个接口被反复调用。这是一个 Bot 状态探测接口，用来确认机器人是否在线、获取 Bot 名称等信息。

问题是：**每次状态查询都会直接调用飞书 API，没有任何缓存。**

Bot 的在线状态几乎不会变化，但 OpenClaw 的状态面板、Gateway 启动、健康检查等场景都会触发 probe，导致这个接口被无意义地反复调用。

### 杀手二：Typing Indicator——每 6 秒一次的"幽灵请求"

这个更隐蔽。API 日志里，`POST /open-apis/im/v1/messages/{message_id}/reactions` 接口的调用频率高得离谱——**每 6 秒一次**，而且全部指向同一条消息。

飞书没有原生的"正在输入"API，OpenClaw 的解决方案是：用 emoji reaction 来模拟输入状态。SDK 内置了一个 typing controller，默认每 6 秒刷新一次 reaction，告诉用户"Bot 正在思考"。

初衷是好的，但代价太大了。如果模型思考 60 秒，就是 10 次 API 调用；用 reasoning model 思考 2 分钟，就是 20 次。一条消息还没回复，API 配额已经在燃烧了。

## 三、问题解决：让 AI 给 AI 看病

定位到问题后，我直接让 Claude Opus 4.6 去分析 OpenClaw 飞书插件的源码，溯源到具体的代码逻辑，然后逐个击破。

### 优化一：Probe 状态检测缓存（24h TTL）

**核心思路**：Bot 状态几乎不变，缓存 24 小时完全合理。

新增了一个内存缓存模块 `probe-cache.ts`，采用惰性过期策略：

```typescript
const CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24 小时
const cache = new Map<string, CacheEntry>();

export function getCachedProbe(key: string): FeishuProbeResult | null {
  const entry = cache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.cachedAt > CACHE_TTL_MS) {
    cache.delete(key);  // 惰性删除：访问时才清理
    return null;
  }
  return entry.result;
}
```

改造后的 `probeFeishu()` 函数在调用 API 前先查缓存，命中则直接返回：

```typescript
export async function probeFeishu(creds, opts?) {
  const cacheKey = creds.accountId ?? creds.appId;

  // 非强制模式下检查缓存
  if (!opts?.force) {
    const cached = getCachedProbe(cacheKey);
    if (cached) return cached;
  }

  // 缓存未命中，调用 API
  const response = await client.request({
    method: "GET",
    url: "/open-apis/bot/v3/info",
  });

  // 成功和失败都缓存（防止对故障端点的请求风暴）
  setCachedProbe(cacheKey, result);
  return result;
}
```

一个关键设计：**错误结果也缓存**。当飞书 API 不可用时，如果不缓存错误，每次 probe 都会重试并等待超时，造成请求堆积。缓存错误后，24 小时内不会重复请求故障端点。

Gateway 启动时用 `force: true` 强制刷新一次，预热缓存：

```typescript
// gateway 启动时预热
const probeResult = await probeFeishu(account, { force: true });
```

**效果**：probe 相关的 API 调用从每次查询都请求，降到每 24 小时仅 1 次。

### 优化二：Typing Indicator 配置化 + 节流

**核心思路**：SDK 的 6 秒心跳频率在框架层面无法修改，但插件可以在回调层做节流。

SDK 的 `createTypingController` 每 6 秒调用一次插件提供的 `start` 回调。我在回调内部加了两层控制：

```typescript
const typingCfg = feishuCfg?.typingIndicator;
const typingEnabled = typingCfg?.enabled !== false; // 默认开启

start: async () => {
  // 第一层：开关控制
  if (!typingEnabled) return;

  // 第二层：节流——SDK 每 6 秒调用，但只在达到配置间隔时才真正请求
  const intervalMs = (typingCfg?.intervalSeconds ?? 6) * 1000;
  const now = Date.now();
  if (typingState && now - lastTypingCallAt < intervalMs) {
    return; // 未到间隔，跳过
  }
  lastTypingCallAt = now;
  typingState = await addTypingIndicator(...); // 实际 API 调用
}
```

配置示例（`~/.openclaw/openclaw.json`）：

```json
{
  "channels": {
    "feishu": {
      "typingIndicator": {
        "enabled": true,
        "intervalSeconds": 120
      }
    }
  }
}
```

**效果对比**（以 Agent 思考 60 秒为例）：

| 配置 | reactions API 调用次数 |
|------|----------------------|
| 原版（6s） | ~10 次 |
| intervalSeconds: 30 | ~2 次 |
| intervalSeconds: 120 | ~1 次 |
| enabled: false | 0 次 |

我最终设置为 120 秒间隔，基本上每次对话只会产生 1 次 reaction 调用。

### 优化三：语音消息自动转文字（faster-whisper）

这个优化的起因略有不同。飞书的语音消息发到 OpenClaw 后，Agent 只能看到"收到一条语音消息，时长 9 秒"，但拿不到具体内容。

解决方案是集成 [faster-whisper](https://github.com/SYSTRAN/faster-whisper)（基于 CTranslate2 的高性能 Whisper 实现），在插件层自动完成语音转文字：

```typescript
// bot.ts - 在消息处理流程中拦截 audio 类型
if (event.message.message_type === "audio" && mediaList.length > 0) {
  const result = await transcribeAudio({
    audioPath: audioMedia.path,
    modelSize: whisperModel ?? "base",
  });
  if (result.text) {
    ctx = { ...ctx, content: result.text, contentType: "text" };
  }
}
```

转写模块通过 Python 子进程调用 faster-whisper，支持 GPU 加速：

```typescript
// voice-transcribe.ts - 内嵌 Python 脚本
const PYTHON_SCRIPT = `
from faster_whisper import WhisperModel
model = WhisperModel(model_size, device="auto", compute_type="auto")
segments, info = model.transcribe(audio_path)
text = "".join(seg.text for seg in segments).strip()
print(json.dumps({"text": text, "language": info.language}))
`;
```

说实话，这个功能有点锦上添花。飞书 App 端自带的语音转文字效果已经很好了，用户完全可以在发送前就转成文本。但换个角度想，这个能力的价值不止于即时语音消息——比如刚通完一个电话，把录音丢给 Bot 让它分析总结，这个场景就很实用了。而且有了这个基础，后续扩展音频分析、会议纪要生成等能力也就水到渠成。

## 四、部署与验证

所有改动都以 OpenClaw 飞书插件的形式实现，不需要修改 OpenClaw 框架本身。部署只需要把修改后的文件复制到系统插件目录，重启 Gateway 即可。

语音转文字还需要额外安装 faster-whisper 环境，我写了一键部署脚本：

```bash
git clone https://github.com/haotian2546/openclaw-feishu.git
cd openclaw-feishu
./scripts/deploy-voice.sh
```

验证效果：用之前那条导致"语音内容: ..."的 9 秒语音消息测试，转写结果完全正确——"你是不是解析不了我发的语音消息内容啊"。

## 五、复盘总结

| 问题 | 根因 | 解决方案 | 效果 |
|------|------|---------|------|
| API 配额快速耗尽 | probe 无缓存 + typing 6s 心跳 | 24h 缓存 + 回调层节流 | API 调用量降低 99%+ |
| 语音消息无法识别 | 插件未处理 audio 类型 | 集成 faster-whisper | 语音自动转文字 |

几个值得记住的点：

1. **先看日志再看代码**。API 调用日志是最直接的线索，比猜测高效得多。
2. **插件层能解决的问题，不要动框架**。三个优化全部在插件层完成，不依赖上游改动，升级无忧。
3. **错误也要缓存**。这是 probe 缓存的一个关键设计——不缓存错误会导致对故障端点的请求风暴。
4. **让 AI 分析 AI 的代码**。用 Opus 4.6 直接读 OpenClaw 的源码定位问题，比自己翻代码快了一个数量级。这大概就是"用魔法打败魔法"吧。

完整代码和文档已开源：[github.com/haotian2546/openclaw-feishu](https://github.com/haotian2546/openclaw-feishu)
