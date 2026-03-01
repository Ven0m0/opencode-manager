import path from 'path';

function checkPath(normalizedInputPath) {
    const getReposPath = () => '/tmp/repos';
    const repoLocalPath = normalizedInputPath;
    const targetPath = path.join(getReposPath(), repoLocalPath);

    const resolvedTargetPath = path.resolve(targetPath);
    const resolvedReposPath = path.resolve(getReposPath());
    if (!resolvedTargetPath.startsWith(resolvedReposPath + path.sep)) {
      return `Invalid path: ${targetPath}`;
    }
    return `Valid path: ${targetPath}`;
}

console.log(checkPath('../something'));
console.log(checkPath('something'));
console.log(checkPath('./something'));
console.log(checkPath('something/..'));
console.log(checkPath('.'));
console.log(checkPath('../repos/something'));
