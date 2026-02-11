import { FolderOpen, Plus } from "lucide-react";
import { useState } from "react";
import { FileBrowserSheet } from "@/components/file-browser/FileBrowserSheet";
import { PendingActionsGroup } from "@/components/notifications/PendingActionsGroup";
import { AddRepoDialog } from "@/components/repo/AddRepoDialog";
import { RepoList } from "@/components/repo/RepoList";
import { Button } from "@/components/ui/button";
import { Header } from "@/components/ui/header";

export function Repos() {
  const [addRepoOpen, setAddRepoOpen] = useState(false);
  const [fileBrowserOpen, setFileBrowserOpen] = useState(false);

  const handleCloseFileBrowser = () => {
    setFileBrowserOpen(false);
  };

  return (
    <div className="h-dvh max-h-dvh overflow-hidden bg-gradient-to-br from-background via-background to-background flex flex-col">
      <Header>
        <div className="flex items-center gap-3">
          <Header.Title logo>OpenCode</Header.Title>
        </div>
        <Header.Actions>
          <PendingActionsGroup />
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setFileBrowserOpen(true)}
            className="text-muted-foreground hover:text-foreground hover:bg-accent transition-all duration-200 h-8 w-8"
          >
            <FolderOpen className="w-4 h-4" />
          </Button>
          <Button onClick={() => setAddRepoOpen(true)} size="sm">
            <Plus className="w-4 h-4 mr-1" />
            Repo
          </Button>
          <Header.Settings />
        </Header.Actions>
      </Header>
      <div className="container mx-auto flex-1 pt-2 px-2 min-h-0 overflow-auto">
        <RepoList />
      </div>
      <AddRepoDialog open={addRepoOpen} onOpenChange={setAddRepoOpen} />
      <FileBrowserSheet
        isOpen={fileBrowserOpen}
        onClose={handleCloseFileBrowser}
        basePath=""
        repoName="Workspace Root"
      />
    </div>
  );
}
