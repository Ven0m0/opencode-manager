const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'backend/src/services/notification.ts');
let content = fs.readFileSync(filePath, 'utf8');

const targetToReplace = `
    let notificationUrl = "/";
    let repoName = "";
    let repoId: number | undefined;

    if (_directory) {
      const reposBasePath = getReposPath();
      const localPath = path.relative(reposBasePath, _directory);
      const repo = getRepoByLocalPath(this.db, localPath);

      if (repo) {
        repoId = repo.id;
        repoName = path.basename(repo.localPath);
        if (sessionId) {
          notificationUrl = \`/repos/\${repo.id}/sessions/\${sessionId}\`;
        } else {
          notificationUrl = \`/repos/\${repo.id}\`;
        }
      }
    }`;

const replacement = `
    const sessionId = event.properties.sessionID as string | undefined;
    if (sessionId && sseAggregator.isSessionBeingViewed(sessionId)) return;

    if (!this.isConfigured()) return;

    let notificationUrl = "/";
    let repoName = "";
    let repoId: number | undefined;

    if (_directory) {
      const reposBasePath = getReposPath();
      const localPath = path.relative(reposBasePath, _directory);
      const repo = getRepoByLocalPath(this.db, localPath);

      if (repo) {
        repoId = repo.id;
        repoName = path.basename(repo.localPath);
        if (sessionId) {
          notificationUrl = \`/repos/\${repo.id}/sessions/\${sessionId}\`;
        } else {
          notificationUrl = \`/repos/\${repo.id}\`;
        }
      }
    }`;

// Actually wait, sessionId is ALREADY defined at line 213:
// const sessionId = event.properties.sessionID as string | undefined;
