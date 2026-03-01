import path from 'path';

function checkPath(normalizedInputPath) {
    const getReposPath = () => '/tmp/repos';
    const repoLocalPath = normalizedInputPath;
    const targetPath = path.resolve(getReposPath(), repoLocalPath);
    const resolvedReposPath = path.resolve(getReposPath());

    const relativePath = path.relative(resolvedReposPath, targetPath);
    if (relativePath.startsWith('..') || path.isAbsolute(relativePath)) {
        return `Invalid path: ${targetPath} (relative: ${relativePath})`;
    }
    if (relativePath === '') {
        return `Invalid path (workspace root): ${targetPath}`;
    }
    return `Valid path: ${targetPath} (relative: ${relativePath})`;
}

console.log(checkPath('../something'));
console.log(checkPath('something'));
console.log(checkPath('./something'));
console.log(checkPath('something/..'));
console.log(checkPath('.'));
console.log(checkPath('../repos/something'));
console.log(checkPath('org/repo'));
