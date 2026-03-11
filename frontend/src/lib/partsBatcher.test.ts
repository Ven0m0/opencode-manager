import { describe, it, expect, beforeEach, mock } from "bun:test";
import { createPartsBatcher } from "./partsBatcher";
import type { MessageWithParts } from "@/api/types";

describe("partsBatcher", () => {
  let queryClient: any;
  const opcodeUrl = "http://localhost:5003";
  const sessionID = "session-1";
  const queryKey = ["opencode", "messages", opcodeUrl, sessionID, undefined];

  beforeEach(() => {
    queryClient = {
      getQueryData: mock(() => null),
      setQueryData: mock(() => {}),
    };
    // @ts-ignore
    global.requestAnimationFrame = (cb: any) => {
      return setTimeout(cb, 0);
    };
    // @ts-ignore
    global.cancelAnimationFrame = (id: any) => {
      clearTimeout(id);
    };
  });

  it("should batch upserts correctly", async () => {
    const batcher = createPartsBatcher(queryClient as any, opcodeUrl);

    const initialData: MessageWithParts[] = [
      {
        info: { id: "msg-1" } as any,
        parts: [{ id: "part-1", messageID: "msg-1", content: "old" } as any],
      },
    ];

    queryClient.getQueryData.mockReturnValue(initialData);

    batcher.queuePartUpdate(sessionID, { id: "part-1", messageID: "msg-1", content: "new" } as any);
    batcher.queuePartUpdate(sessionID, { id: "part-2", messageID: "msg-1", content: "added" } as any);

    batcher.flush();

    expect(queryClient.setQueryData).toHaveBeenCalledWith(queryKey, [
      {
        info: { id: "msg-1" } as any,
        parts: [
          { id: "part-1", messageID: "msg-1", content: "new" },
          { id: "part-2", messageID: "msg-1", content: "added" },
        ],
      },
    ]);
  });

  it("should handle multiple messages", () => {
    const batcher = createPartsBatcher(queryClient as any, opcodeUrl);

    const initialData: MessageWithParts[] = [
      {
        info: { id: "msg-1" } as any,
        parts: [{ id: "part-1", messageID: "msg-1" } as any],
      },
      {
        info: { id: "msg-2" } as any,
        parts: [],
      },
    ];

    queryClient.getQueryData.mockReturnValue(initialData);

    batcher.queuePartUpdate(sessionID, { id: "part-1", messageID: "msg-1", content: "updated" } as any);
    batcher.queuePartUpdate(sessionID, { id: "part-3", messageID: "msg-2", content: "new" } as any);

    batcher.flush();

    expect(queryClient.setQueryData).toHaveBeenCalledWith(queryKey, [
      {
        info: { id: "msg-1" } as any,
        parts: [{ id: "part-1", messageID: "msg-1", content: "updated" }],
      },
      {
        info: { id: "msg-2" } as any,
        parts: [{ id: "part-3", messageID: "msg-2", content: "new" }],
      },
    ]);
  });

  it("should handle removals", () => {
    const batcher = createPartsBatcher(queryClient as any, opcodeUrl);

    const initialData: MessageWithParts[] = [
      {
        info: { id: "msg-1" } as any,
        parts: [
          { id: "part-1", messageID: "msg-1" } as any,
          { id: "part-2", messageID: "msg-1" } as any,
        ],
      },
    ];

    queryClient.getQueryData.mockReturnValue(initialData);

    batcher.queuePartRemoval(sessionID, "msg-1", "part-1");

    batcher.flush();

    expect(queryClient.setQueryData).toHaveBeenCalledWith(queryKey, [
      {
        info: { id: "msg-1" } as any,
        parts: [{ id: "part-2", messageID: "msg-1" }],
      },
    ]);
  });
});
