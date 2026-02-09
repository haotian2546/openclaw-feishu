import type { FeishuProbeResult } from "./types.js";

interface CacheEntry {
  result: FeishuProbeResult;
  cachedAt: number;
}

const CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours
const cache = new Map<string, CacheEntry>();

export function getCachedProbe(key: string): FeishuProbeResult | null {
  const entry = cache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.cachedAt > CACHE_TTL_MS) {
    cache.delete(key);
    return null;
  }
  return entry.result;
}

export function setCachedProbe(key: string, result: FeishuProbeResult): void {
  cache.set(key, { result, cachedAt: Date.now() });
}

export function invalidateProbeCache(key?: string): void {
  if (key) {
    cache.delete(key);
  } else {
    cache.clear();
  }
}
