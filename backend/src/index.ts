import os from "node:os";
import path from "node:path";
import { serve } from "@hono/node-server";
import { serveStatic } from "@hono/node-server/serve-static";
import {
  ENV,
  getAgentsMdPath,
  getConfigPath,
  getDatabasePath,
  getOpenCodeConfigDir,
  getOpenCodeConfigFilePath,
  getReposPath,
  getWorkspacePath,
} from "@opencode-manager/shared/config/env";
import { OpenCodeConfigSchema } from "@opencode-manager/shared/schemas";
import { Hono } from "hono";
import { cors } from "hono/cors";
import stripJsonComments from "strip-json-comments";
import { createAuth } from "./auth";
import { createAuthMiddleware } from "./auth/middleware";
import { initializeDatabase } from "./db/schema";
import { createIPCServer, type IPCServer } from "./ipc/ipcServer";
import {
  createAuthInfoRoutes,
  createAuthRoutes,
  syncAdminFromEnv,
} from "./routes/auth";
import { createFileRoutes } from "./routes/files";
import { createHealthRoutes } from "./routes/health";
import { createNotificationRoutes } from "./routes/notifications";
import { createOAuthRoutes } from "./routes/oauth";
import { createProvidersRoutes } from "./routes/providers";
import { createRepoRoutes } from "./routes/repos";
import { createSettingsRoutes } from "./routes/settings";
import { createSSERoutes } from "./routes/sse";
import { createSSHRoutes } from "./routes/ssh";
import { createSTTRoutes } from "./routes/stt";
import { createTitleRoutes } from "./routes/title";
import { cleanupExpiredCache, createTTSRoutes } from "./routes/tts";
import {
  ensureDirectoryExists,
  fileExists,
  readFileContent,
  writeFileContent,
} from "./services/file-operations";
import { GitAuthService } from "./services/git-auth";
import { NotificationService } from "./services/notification";
import { opencodeServerManager } from "./services/opencode-single-server";
import { proxyRequest } from "./services/proxy";
import { cleanupOrphanedDirectories } from "./services/repo";
import { SettingsService } from "./services/settings";
import { sseAggregator } from "./services/sse-aggregator";
import { logger } from "./utils/logger";

const { PORT, HOST } = ENV.SERVER;
const DB_PATH = getDatabasePath();

const app = new Hono();

app.use(
  "/*",
  cors({
    origin: (origin) => {
      const trustedOrigins = ENV.AUTH.TRUSTED_ORIGINS.split(",").map((o) =>
        o.trim(),
      );
      if (!origin) return trustedOrigins[0];
      if (trustedOrigins.includes(origin)) return origin;
      return trustedOrigins[0];
    },
    allowMethods: ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
    allowHeaders: ["Content-Type", "Authorization"],
    credentials: true,
  }),
);

const db = initializeDatabase(DB_PATH);
const auth = createAuth(db);
const requireAuth = createAuthMiddleware(auth);

import { DEFAULT_AGENTS_MD } from "./constants";

let ipcServer: IPCServer | undefined;
const gitAuthService = new GitAuthService();

async function ensureDefaultConfigExists(): Promise<void> {
  const settingsService = new SettingsService(db);
  const workspaceConfigPath = getOpenCodeConfigFilePath();

  if (await fileExists(workspaceConfigPath)) {
    logger.info(
      `Found workspace config at ${workspaceConfigPath}, syncing to database...`,
    );
    try {
      const rawContent = await readFileContent(workspaceConfigPath);
      const parsed = JSON.parse(stripJsonComments(rawContent));
      const validation = OpenCodeConfigSchema.safeParse(parsed);

      if (!validation.success) {
        logger.warn("Workspace config has invalid structure", validation.error);
      } else {
        const existingDefault =
          settingsService.getOpenCodeConfigByName("default");
        if (existingDefault) {
          settingsService.updateOpenCodeConfig("default", {
            content: rawContent,
            isDefault: true,
          });
          logger.info("Updated database config from workspace file");
        } else {
          settingsService.createOpenCodeConfig({
            name: "default",
            content: rawContent,
            isDefault: true,
          });
          logger.info("Created database config from workspace file");
        }
        return;
      }
    } catch (error) {
      logger.warn("Failed to read workspace config", error);
    }
  }

  const homeConfigPath = path.join(
    os.homedir(),
    ".config/opencode/opencode.json",
  );
  if (await fileExists(homeConfigPath)) {
    logger.info(`Found home config at ${homeConfigPath}, importing...`);
    try {
      const rawContent = await readFileContent(homeConfigPath);
      const parsed = JSON.parse(stripJsonComments(rawContent));
      const validation = OpenCodeConfigSchema.safeParse(parsed);

      if (validation.success) {
        const existingDefault =
          settingsService.getOpenCodeConfigByName("default");
        if (existingDefault) {
          settingsService.updateOpenCodeConfig("default", {
            content: rawContent,
            isDefault: true,
          });
        } else {
          settingsService.createOpenCodeConfig({
            name: "default",
            content: rawContent,
            isDefault: true,
          });
        }

        await writeFileContent(workspaceConfigPath, rawContent);
        logger.info("Imported home config to workspace");
        return;
      }
    } catch (error) {
      logger.warn("Failed to import home config", error);
    }
  }

  const existingDbConfigs = settingsService.getOpenCodeConfigs();
  if (existingDbConfigs.configs.length > 0) {
    const defaultConfig = settingsService.getDefaultOpenCodeConfig();
    if (defaultConfig) {
      await writeFileContent(workspaceConfigPath, defaultConfig.rawContent);
      logger.info("Wrote existing database config to workspace file");
    }
    return;
  }

  logger.info("No existing config found, creating minimal seed config");
  const seedConfig = JSON.stringify(
    { $schema: "https://opencode.ai/config.json" },
    null,
    2,
  );
  settingsService.createOpenCodeConfig({
    name: "default",
    content: seedConfig,
    isDefault: true,
  });
  await writeFileContent(workspaceConfigPath, seedConfig);
  logger.info("Created minimal seed config");
}

async function ensureDefaultAgentsMdExists(): Promise<void> {
  const agentsMdPath = getAgentsMdPath();
  const exists = await fileExists(agentsMdPath);

  if (!exists) {
    await writeFileContent(agentsMdPath, DEFAULT_AGENTS_MD);
    logger.info(`Created default AGENTS.md at: ${agentsMdPath}`);
  }
}

try {
  if (ENV.SERVER.NODE_ENV === "production" && !ENV.AUTH.SECRET) {
    logger.error("AUTH_SECRET is required in production mode");
    logger.error("Generate one with: openssl rand -base64 32");
    logger.error("Set it as environment variable: AUTH_SECRET=your-secret");
    process.exit(1);
  }

  await ensureDirectoryExists(getWorkspacePath());
  await ensureDirectoryExists(getReposPath());
  await ensureDirectoryExists(getConfigPath());
  await ensureDirectoryExists(getOpenCodeConfigDir());
  await ensureDirectoryExists(path.join(getOpenCodeConfigDir(), "skills"));
  await ensureDirectoryExists(
    path.join(getWorkspacePath(), ".opencode", "skills"),
  );
  logger.info("Workspace directories initialized");

  await cleanupOrphanedDirectories(db);
  logger.info("Orphaned directory cleanup completed");

  await cleanupExpiredCache();

  await ensureDefaultConfigExists();
  await ensureDefaultAgentsMdExists();

  const settingsService = new SettingsService(db);
  settingsService.initializeLastKnownGoodConfig();

  ipcServer = await createIPCServer(process.env.STORAGE_PATH || undefined);
  gitAuthService.initialize(ipcServer, db);
  logger.info(`Git IPC server running at ${ipcServer.ipcHandlePath}`);

  opencodeServerManager.setDatabase(db);
  await opencodeServerManager.start();
  logger.info(
    `OpenCode server running on port ${opencodeServerManager.getPort()}`,
  );

  await syncAdminFromEnv(auth, db);
} catch (error) {
  logger.error("Failed to initialize workspace:", error);
}

const notificationService = new NotificationService(db);

if (ENV.VAPID.PUBLIC_KEY && ENV.VAPID.PRIVATE_KEY) {
  if (!ENV.VAPID.SUBJECT) {
    logger.warn(
      "VAPID_SUBJECT is not set — push notifications require a mailto: subject (e.g. mailto:you@example.com)",
    );
  } else if (!ENV.VAPID.SUBJECT.startsWith("mailto:")) {
    logger.warn(
      `VAPID_SUBJECT="${ENV.VAPID.SUBJECT}" does not use mailto: format — iOS/Safari push notifications will fail`,
    );
  }

  notificationService.configureVapid({
    publicKey: ENV.VAPID.PUBLIC_KEY,
    privateKey: ENV.VAPID.PRIVATE_KEY,
    subject: ENV.VAPID.SUBJECT || "mailto:push@localhost",
  });
  sseAggregator.onEvent((directory, event) => {
    notificationService.handleSSEEvent(directory, event).catch((err) => {
      logger.error("Push notification dispatch error:", err);
    });
  });
}

app.route("/api/auth", createAuthRoutes(auth));
app.route("/api/auth-info", createAuthInfoRoutes(auth, db));

app.route("/api/health", createHealthRoutes(db));

const protectedApi = new Hono();
protectedApi.use("/*", requireAuth);

protectedApi.route("/repos", createRepoRoutes(db, gitAuthService));
protectedApi.route("/settings", createSettingsRoutes(db));
protectedApi.route("/files", createFileRoutes());
protectedApi.route("/providers", createProvidersRoutes());
protectedApi.route("/oauth", createOAuthRoutes());
protectedApi.route("/tts", createTTSRoutes(db));
protectedApi.route("/stt", createSTTRoutes(db));
protectedApi.route("/generate-title", createTitleRoutes());
protectedApi.route("/sse", createSSERoutes());
protectedApi.route("/ssh", createSSHRoutes(gitAuthService));
protectedApi.route(
  "/notifications",
  createNotificationRoutes(notificationService),
);

app.route("/api", protectedApi);

app.all("/api/opencode/*", requireAuth, async (c) => {
  const request = c.req.raw;
  return proxyRequest(request);
});

const isProduction = ENV.SERVER.NODE_ENV === "production";

if (isProduction) {
  app.use("/*", serveStatic({ root: "./frontend/dist" }));

  app.get("*", async (c) => {
    if (c.req.path.startsWith("/api/")) {
      return c.notFound();
    }
    const fs = await import("node:fs/promises");
    const path = await import("node:path");
    const indexPath = path.join(process.cwd(), "frontend/dist/index.html");
    const html = await fs.readFile(indexPath, "utf-8");
    return c.html(html);
  });
} else {
  app.get("/", (c) => {
    return c.json({
      name: "OpenCode WebUI",
      version: "2.0.0",
      status: "running",
      endpoints: {
        health: "/api/health",
        repos: "/api/repos",
        settings: "/api/settings",
        sessions: "/api/sessions",
        files: "/api/files",
        providers: "/api/providers",
        opencode_proxy: "/api/opencode/*",
      },
    });
  });

  app.get("/api/network-info", async (c) => {
    const os = await import("node:os");
    const interfaces = os.networkInterfaces();
    const ips = Object.values(interfaces)
      .flat()
      .filter((info) => info && !info.internal && info.family === "IPv4")
      .map((info) => info?.address);

    const requestHost = c.req.header("host") || `localhost:${PORT}`;
    const protocol = c.req.header("x-forwarded-proto") || "http";

    return c.json({
      host: HOST,
      port: PORT,
      requestHost,
      protocol,
      availableIps: ips,
      apiUrls: [
        `${protocol}://localhost:${PORT}`,
        ...ips.map((ip) => `${protocol}://${ip}:${PORT}`),
      ],
    });
  });
}

let isShuttingDown = false;

const shutdown = async (signal: string) => {
  if (isShuttingDown) return;
  isShuttingDown = true;

  logger.info(`${signal} received, shutting down gracefully...`);
  try {
    sseAggregator.shutdown();
    logger.info("SSE Aggregator stopped");
    if (ipcServer) {
      ipcServer.dispose();
      logger.info("Git IPC server stopped");
    }
    await opencodeServerManager.stop();
    logger.info("OpenCode server stopped");
  } catch (error) {
    logger.error("Error during shutdown:", error);
  }
  process.exit(0);
};

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));

serve({
  fetch: app.fetch,
  port: PORT,
  hostname: HOST,
});

logger.info(`🚀 OpenCode WebUI API running on http://${HOST}:${PORT}`);
