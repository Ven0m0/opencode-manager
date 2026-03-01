const path = require('path');
const getReposPath = () => '/tmp/repos';

const normalizedInputPath = '../repos';
const reposPath = path.resolve(getReposPath());
const targetPath = path.resolve(reposPath, normalizedInputPath);

console.log(targetPath.startsWith(reposPath + path.sep));
