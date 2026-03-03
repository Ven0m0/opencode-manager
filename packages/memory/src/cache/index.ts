import { InMemoryCacheService } from "./memory-cache";
import type { CacheService } from "./types";

export type { CacheService } from "./types";

export function createCacheService(): CacheService {
  return new InMemoryCacheService();
}
