import type { components } from "@/api/opencode-types";
import { useSessionTodosForSession } from "@/stores/sessionTodosStore";
import { TodoListDisplay } from "./TodoListDisplay";

export type Todo = components["schemas"]["Todo"];

interface SessionTodoDisplayProps {
  sessionID: string | undefined;
}

export function SessionTodoDisplay({ sessionID }: SessionTodoDisplayProps) {
  const todos = useSessionTodosForSession(sessionID);

  if (!sessionID || !todos || todos.length === 0) {
    return null;
  }

  return (
    <div className="mb-2">
      <TodoListDisplay
        todos={todos}
        title="Task List"
        showCompleted={true}
        scrollCurrentOnly={true}
        isLoading={false}
      />
    </div>
  );
}
