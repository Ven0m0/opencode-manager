import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { logger } from "../utils/logger";
import { migrate } from "./migration-runner";
import { allMigrations } from "./migrations";

export function initializeDatabase(dbPath: string = "./data/opencode.db"): Database {
  mkdirSync(dirname(dbPath), { recursive: true });
  const db = new Database(dbPath);

  migrate(db, allMigrations);

  db.prepare(
    "INSERT OR IGNORE INTO user_preferences (user_id, preferences, updated_at) VALUES (?, ?, ?)",
  ).run("default", "{}", Date.now());

  logger.info("Database initialized successfully");

  return db;
}
