import type { FeishuProbeResult } from "./types.js";
import { createFeishuClient, type FeishuClientCredentials } from "./client.js";
import { getCachedProbe, setCachedProbe } from "./probe-cache.js";

/**
 * Probe Feishu bot status with 24h in-memory cache.
 * On gateway startup the first call hits the API and caches the result.
 * Subsequent calls within 24h return the cached result directly.
 * After 24h the cache expires and the API is called again.
 *
 * Pass `force: true` to bypass the cache.
 */
export async function probeFeishu(
  creds?: FeishuClientCredentials,
  opts?: { force?: boolean },
): Promise<FeishuProbeResult> {
  if (!creds?.appId || !creds?.appSecret) {
    return {
      ok: false,
      error: "missing credentials (appId, appSecret)",
    };
  }

  const cacheKey = creds.accountId ?? creds.appId;

  // Check cache unless forced
  if (!opts?.force) {
    const cached = getCachedProbe(cacheKey);
    if (cached) return cached;
  }

  try {
    const client = createFeishuClient(creds);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- SDK generic request method
    const response = await (client as any).request({
      method: "GET",
      url: "/open-apis/bot/v3/info",
      data: {},
    });

    if (response.code !== 0) {
      const result: FeishuProbeResult = {
        ok: false,
        appId: creds.appId,
        error: `API error: ${response.msg || `code ${response.code}`}`,
      };
      setCachedProbe(cacheKey, result);
      return result;
    }

    const bot = response.bot || response.data?.bot;
    const result: FeishuProbeResult = {
      ok: true,
      appId: creds.appId,
      botName: bot?.bot_name,
      botOpenId: bot?.open_id,
    };
    setCachedProbe(cacheKey, result);
    return result;
  } catch (err) {
    const result: FeishuProbeResult = {
      ok: false,
      appId: creds.appId,
      error: err instanceof Error ? err.message : String(err),
    };
    // Cache errors too to avoid hammering a broken endpoint
    setCachedProbe(cacheKey, result);
    return result;
  }
}
