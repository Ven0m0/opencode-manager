import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { createBrowserRouter, Outlet, RouterProvider } from "react-router-dom";
import { Toaster } from "sonner";
import {
  EventProvider,
  useEventContext,
  usePermissions,
} from "@/contexts/EventContext";
import { PermissionRequestDialog } from "./components/session/PermissionRequestDialog";
import { SettingsDialog } from "./components/settings/SettingsDialog";
import { SSHHostKeyDialog } from "./components/ssh/SSHHostKeyDialog";
import { AuthProvider } from "./contexts/AuthContext";
import { TTSProvider } from "./contexts/TTSContext";
import { useTheme } from "./hooks/useTheme";
import {
  loginLoader,
  protectedLoader,
  registerLoader,
  setupLoader,
} from "./lib/auth-loaders";
import { Login } from "./pages/Login";
import { Register } from "./pages/Register";
import { RepoDetail } from "./pages/RepoDetail";
import { Repos } from "./pages/Repos";
import { SessionDetail } from "./pages/SessionDetail";
import { Setup } from "./pages/Setup";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 10,
      refetchOnWindowFocus: true,
    },
  },
});

function SSHHostKeyDialogWrapper() {
  const { sshHostKey } = useEventContext();
  return (
    <SSHHostKeyDialog
      request={sshHostKey.request}
      onRespond={async (requestId, response) => {
        await sshHostKey.respond(requestId, response === "accept");
      }}
    />
  );
}

function PermissionDialogWrapper() {
  const {
    current: currentPermission,
    pendingCount,
    respond: respondToPermission,
    showDialog,
    setShowDialog,
  } = usePermissions();

  return (
    <PermissionRequestDialog
      permission={currentPermission}
      pendingCount={pendingCount}
      isFromDifferentSession={false}
      onRespond={respondToPermission}
      open={showDialog}
      onOpenChange={setShowDialog}
      repoDirectory={null}
    />
  );
}

function AppShell() {
  useTheme();

  return (
    <AuthProvider>
      <EventProvider>
        <Outlet />
        <PermissionDialogWrapper />
        <SSHHostKeyDialogWrapper />
        <SettingsDialog />
        <Toaster
          position="bottom-right"
          expand={false}
          richColors
          closeButton
          duration={2500}
        />
      </EventProvider>
    </AuthProvider>
  );
}

const router = createBrowserRouter([
  {
    element: <AppShell />,
    children: [
      {
        path: "/login",
        element: <Login />,
        loader: loginLoader,
      },
      {
        path: "/register",
        element: <Register />,
        loader: registerLoader,
      },
      {
        path: "/setup",
        element: <Setup />,
        loader: setupLoader,
      },
      {
        path: "/",
        element: <Repos />,
        loader: protectedLoader,
      },
      {
        path: "/repos/:id",
        element: <RepoDetail />,
        loader: protectedLoader,
      },
      {
        path: "/repos/:id/sessions/:sessionId",
        element: <SessionDetail />,
        loader: protectedLoader,
      },
    ],
  },
]);

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <TTSProvider>
        <RouterProvider router={router} />
      </TTSProvider>
    </QueryClientProvider>
  );
}

export default App;
