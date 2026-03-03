export type {
  CompactionConfig,
  CreateMemoryInput,
  ListMemoriesFilter,
  Memory,
  MemoryScope,
  MemorySearchResult,
  MemoryStats,
  PlanningState,
  PreCompactionSnapshot,
  SessionState,
  UpdateMemoryInput,
} from "../types";
export { closeDatabase, initializeDatabase, resolveDataDir, resolveLogPath } from "./database";
export { createMemoryQuery } from "./memory-queries";
export { createMetadataQuery } from "./metadata-queries";
export { createSessionStateQueries } from "./session-state-queries";
export { createVecService } from "./vec";
export type { VecSearchResult, VecService } from "./vec-types";
export type { TableDimensionsResult } from "./vec-utils";
export { getTableDimensions, recreateVecTable } from "./vec-utils";
