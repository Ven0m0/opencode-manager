import { describe, it, expect, beforeEach, afterEach, mock } from "bun:test";
import { Database } from "bun:sqlite";
import path from "node:path";
import { NotificationService } from "../../src/services/notification";
import { getReposPath } from "@opencode-manager/shared/config/env";
import { NotificationEventType } from "@opencode-manager/shared/schemas";

mock.module("web-push", () => {
  return {
    default: {
      setVapidDetails: () => {},
      sendNotification: async () => {},
    },
  };
});

describe("NotificationService Performance", () => {
  let db: Database;
  let service: NotificationService;

  beforeEach(() => {
    db = new Database(":memory:");

    // Create repos table
    db.run(`
      CREATE TABLE repos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        repo_url TEXT,
        local_path TEXT NOT NULL UNIQUE,
        branch TEXT,
        default_branch TEXT NOT NULL,
        clone_status TEXT NOT NULL,
        cloned_at INTEGER NOT NULL,
        last_pulled INTEGER,
        opencode_config_name TEXT,
        is_worktree INTEGER DEFAULT 0,
        is_local INTEGER DEFAULT 0
      )
    `);

    // Create user_preferences table for SettingsService
    db.run(`
      CREATE TABLE IF NOT EXISTS user_preferences (
        user_id TEXT PRIMARY KEY,
        preferences TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    `);

    // Insert a dummy repo
    db.run(`
      INSERT INTO repos (local_path, default_branch, clone_status, cloned_at)
      VALUES ('dummy-repo', 'main', 'cloned', ?)
    `, [Date.now()]);

    service = new NotificationService(db);

    service.configureVapid({
      publicKey: "test-pub",
      privateKey: "test-priv",
      subject: "mailto:test@test.com"
    });

    // We'll create 1000 dummy subscriptions to simulate a large loop
    const subStmt = db.prepare(`
      INSERT INTO push_subscriptions (user_id, endpoint, p256dh, auth, created_at, last_used_at)
      VALUES (?, ?, 'dummy-p256dh', 'dummy-auth', ?, ?)
    `);

    db.transaction(() => {
      for (let i = 0; i < 1000; i++) {
        subStmt.run(`user_${i}`, `endpoint_${i}`, Date.now(), Date.now());
      }
    })();
  });

  afterEach(() => {
    db.close();
  });

  it("measures performance of handleSSEEvent", async () => {
    const reposBasePath = getReposPath();
    const directory = path.join(reposBasePath, "dummy-repo");

    const event = {
      type: NotificationEventType.SESSION_IDLE,
      properties: {
        sessionID: "test-session"
      }
    };

    const start = performance.now();
    await service.handleSSEEvent(directory, event as any);
    const end = performance.now();

    const duration = end - start;
    console.log(`handleSSEEvent took ${duration.toFixed(2)}ms for 1000 users`);

    expect(duration).toBeGreaterThan(0);
  });
});
