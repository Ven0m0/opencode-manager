const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'backend/src/services/notification.ts');
let content = fs.readFileSync(filePath, 'utf8');

const targetToReplace = `
    const userIds = this.getAllUserIds();

    for (const userId of userIds) {
      const settings = this.settingsService.getSettings(userId);
      const notifPrefs =
        settings.preferences.notifications ?? DEFAULT_NOTIFICATION_PREFERENCES;

      if (!notifPrefs.enabled) continue;
      if (!notifPrefs.events[config.preferencesKey]) continue;

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
      }

      const body = config.bodyFn(event.properties);`;

const replacement = `
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
    }

    const userIds = this.getAllUserIds();

    for (const userId of userIds) {
      const settings = this.settingsService.getSettings(userId);
      const notifPrefs =
        settings.preferences.notifications ?? DEFAULT_NOTIFICATION_PREFERENCES;

      if (!notifPrefs.enabled) continue;
      if (!notifPrefs.events[config.preferencesKey]) continue;

      const body = config.bodyFn(event.properties);`;

if (content.includes(targetToReplace.trim())) {
  content = content.replace(targetToReplace.trim(), replacement.trim());
  fs.writeFileSync(filePath, content, 'utf8');
  console.log("Successfully updated the file.");
} else {
  console.error("Could not find the target string in the file.");
}
