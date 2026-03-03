import { architectAgent } from "./architect";
import { codeAgent } from "./code";
import { codeReviewAgent } from "./code-review";
import { memoryAgent } from "./memory";
import type { AgentDefinition, AgentRole } from "./types";

export const agents: Record<AgentRole, AgentDefinition> = {
  code: codeAgent,
  memory: memoryAgent,
  architect: architectAgent,
  "code-review": codeReviewAgent,
};

export type { AgentConfig, AgentDefinition, AgentRole } from "./types";
