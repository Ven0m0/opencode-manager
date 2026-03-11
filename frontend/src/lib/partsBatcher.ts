import type { QueryClient } from "@tanstack/react-query";
import type { MessageWithParts, Part } from "@/api/types";

interface PartsBatcher {
  queuePartUpdate: (sessionID: string, part: Part) => void;
  queuePartRemoval: (sessionID: string, messageID: string, partID: string) => void;
  flush: () => void;
  destroy: () => void;
}

export function createPartsBatcher(
  queryClient: QueryClient,
  opcodeUrl: string,
  directory?: string,
): PartsBatcher {
  const pendingUpserts = new Map<string, Map<string, Part>>();
  const pendingRemovals = new Map<string, Map<string, Set<string>>>();
  let pendingFrameId: number | null = null;

  const scheduleFlush = () => {
    if (pendingFrameId !== null) return;
    pendingFrameId = requestAnimationFrame(() => {
      pendingFrameId = null;
      flush();
    });
  };

  const flush = () => {
    if (pendingUpserts.size === 0 && pendingRemovals.size === 0) return;

    const sessionsToUpdate = new Set([...pendingUpserts.keys(), ...pendingRemovals.keys()]);

    for (const sessionID of sessionsToUpdate) {
      const queryKey = ["opencode", "messages", opcodeUrl, sessionID, directory];
      const currentData = queryClient.getQueryData<MessageWithParts[]>(queryKey);

      if (!currentData) continue;

      let updatedData = [...currentData];

      const sessionUpserts = pendingUpserts.get(sessionID);
      const sessionRemovals = pendingRemovals.get(sessionID);

      const upsertsByMessageID = new Map<string, Part[]>();
      if (sessionUpserts) {
        for (const part of sessionUpserts.values()) {
          if (!upsertsByMessageID.has(part.messageID)) {
            upsertsByMessageID.set(part.messageID, []);
          }
          upsertsByMessageID.get(part.messageID)!.push(part);
        }
      }

      updatedData = updatedData.map((msgWithParts) => {
        const partsToUpsert = upsertsByMessageID.get(msgWithParts.info.id);
        const partsToRemove = sessionRemovals?.get(msgWithParts.info.id);

        if (!partsToUpsert && !partsToRemove) {
          return msgWithParts;
        }

        let msgParts = [...msgWithParts.parts];

        if (partsToRemove) {
          msgParts = msgParts.filter((p) => !partsToRemove.has(p.id));
        }

        if (partsToUpsert) {
          const partMap = new Map(msgParts.map((p, i) => [p.id, i]));
          for (const part of partsToUpsert) {
            const existingIdx = partMap.get(part.id);
            if (existingIdx !== undefined) {
              msgParts[existingIdx] = part;
            } else {
              msgParts.push(part);
              partMap.set(part.id, msgParts.length - 1);
            }
          }
        }

        return {
          ...msgWithParts,
          parts: msgParts,
        };
      });

      queryClient.setQueryData(queryKey, updatedData);
    }

    pendingUpserts.clear();
    pendingRemovals.clear();
  };

  const queuePartUpdate = (sessionID: string, part: Part) => {
    if (!pendingUpserts.has(sessionID)) {
      pendingUpserts.set(sessionID, new Map());
    }
    const sessionUpserts = pendingUpserts.get(sessionID)!;
    sessionUpserts.set(part.id, part);
    scheduleFlush();
  };

  const queuePartRemoval = (sessionID: string, messageID: string, partID: string) => {
    if (!pendingRemovals.has(sessionID)) {
      pendingRemovals.set(sessionID, new Map());
    }
    const sessionRemovals = pendingRemovals.get(sessionID)!;
    if (!sessionRemovals.has(messageID)) {
      sessionRemovals.set(messageID, new Set());
    }
    const messageRemovals = sessionRemovals.get(messageID)!;
    messageRemovals.add(partID);
    scheduleFlush();
  };

  const destroy = () => {
    if (pendingFrameId !== null) {
      cancelAnimationFrame(pendingFrameId);
      pendingFrameId = null;
    }
    pendingUpserts.clear();
    pendingRemovals.clear();
  };

  return {
    queuePartUpdate,
    queuePartRemoval,
    flush,
    destroy,
  };
}
