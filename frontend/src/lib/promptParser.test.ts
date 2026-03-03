import { describe, expect, it } from "vitest";
import type { FileInfo, ImageAttachment } from "@/api/types";
import {
  detectMentionTrigger,
  filterAgentsByQuery,
  getDirectory,
  getFilename,
  parsePromptToParts,
} from "./promptParser";

describe("promptParser", () => {
  describe("detectMentionTrigger", () => {
    it("should detect mention at the beginning of the string", () => {
      expect(detectMentionTrigger("@", 1)).toEqual({
        start: 0,
        end: 1,
        query: "",
      });
    });

    it("should detect mention after a space", () => {
      expect(detectMentionTrigger("hello @", 7)).toEqual({
        start: 6,
        end: 7,
        query: "",
      });
    });

    it("should detect mention with query", () => {
      expect(detectMentionTrigger("@fil", 4)).toEqual({
        start: 0,
        end: 4,
        query: "fil",
      });
    });

    it("should return null if not a mention trigger", () => {
      expect(detectMentionTrigger("email@domain.com", 6)).toBeNull();
    });

    it("should detect mention trigger in the middle of text", () => {
      expect(detectMentionTrigger("hello @fil world", 10)).toEqual({
        start: 6,
        end: 10,
        query: "fil",
      });
    });

    it("should return null if cursor is at the '@' but preceded by non-space", () => {
      expect(detectMentionTrigger("no@trigger", 3)).toBeNull();
    });
  });

  describe("filterAgentsByQuery", () => {
    const agents = [
      { name: "Researcher", description: "Search the web" },
      { name: "Coder", description: "Write code" },
    ];

    it("should filter agents by query", () => {
      expect(filterAgentsByQuery(agents, "Res")).toEqual([agents[0]]);
    });

    it("should be case-insensitive", () => {
      expect(filterAgentsByQuery(agents, "coder")).toEqual([agents[1]]);
    });

    it("should return all agents if query is empty", () => {
      expect(filterAgentsByQuery(agents, "")).toEqual(agents);
    });

    it("should return empty array if no match", () => {
      expect(filterAgentsByQuery(agents, "xyz")).toEqual([]);
    });
  });

  describe("parsePromptToParts", () => {
    const fileMap = new Map<string, FileInfo>([
      ["file1.ts", { path: "src/file1.ts", name: "file1.ts" }],
      ["dir/file2.js", { path: "src/dir/file2.js", name: "file2.js" }],
    ]);

    it("should parse plain text", () => {
      expect(parsePromptToParts("Hello world", fileMap)).toEqual([
        { type: "text", content: "Hello world" },
      ]);
    });

    it("should parse mentions of existing files", () => {
      expect(parsePromptToParts("Check @file1.ts", fileMap)).toEqual([
        { type: "text", content: "Check " },
        { type: "file", path: "src/file1.ts", name: "file1.ts" },
      ]);
    });

    it("should handle multiple mentions", () => {
      expect(parsePromptToParts("@file1.ts and @dir/file2.js", fileMap)).toEqual([
        { type: "file", path: "src/file1.ts", name: "file1.ts" },
        { type: "text", content: " and " },
        { type: "file", path: "src/dir/file2.js", name: "file2.js" },
      ]);
    });

    it("should handle non-existing file mentions as plain text", () => {
      expect(parsePromptToParts("Contact @someone", fileMap)).toEqual([
        { type: "text", content: "Contact " },
        { type: "text", content: "@someone" },
      ]);
    });

    it("should be case-insensitive for file mentions", () => {
      expect(parsePromptToParts("Check @FILE1.TS", fileMap)).toEqual([
        { type: "text", content: "Check " },
        { type: "file", path: "src/file1.ts", name: "file1.ts" },
      ]);
    });

    it("should handle image attachments", () => {
      const images: ImageAttachment[] = [
        {
          id: "img1",
          filename: "test.png",
          mime: "image/png",
          dataUrl: "data:image/png;base64,...",
        },
      ];
      expect(parsePromptToParts("See image", fileMap, images)).toEqual([
        { type: "text", content: "See image" },
        {
          type: "image",
          id: "img1",
          filename: "test.png",
          mime: "image/png",
          dataUrl: "data:image/png;base64,...",
        },
      ]);
    });

    it("should return empty text part for empty input", () => {
      expect(parsePromptToParts("", fileMap)).toEqual([{ type: "text", content: "" }]);
    });

    it("should return only images if text is empty", () => {
      const images: ImageAttachment[] = [
        {
          id: "img1",
          filename: "test.png",
          mime: "image/png",
          dataUrl: "data:image/png;base64,...",
        },
      ];
      expect(parsePromptToParts("", fileMap, images)).toEqual([
        {
          type: "image",
          id: "img1",
          filename: "test.png",
          mime: "image/png",
          dataUrl: "data:image/png;base64,...",
        },
      ]);
    });

    it("should skip whitespace-only text parts", () => {
      // current implementation behavior
      expect(parsePromptToParts("  @file1.ts  ", fileMap)).toEqual([
        { type: "file", path: "src/file1.ts", name: "file1.ts" },
      ]);
    });
  });

  describe("path utilities", () => {
    describe("getFilename", () => {
      it("should return filename from path", () => {
        expect(getFilename("src/lib/utils.ts")).toBe("utils.ts");
        expect(getFilename("file.txt")).toBe("file.txt");
        expect(getFilename("/abs/path/file")).toBe("file");
      });
    });

    describe("getDirectory", () => {
      it("should return directory from path", () => {
        expect(getDirectory("src/lib/utils.ts")).toBe("src/lib");
        expect(getDirectory("file.txt")).toBe(".");
        expect(getDirectory("/abs/path/file")).toBe("/abs/path");
      });
    });
  });
});
