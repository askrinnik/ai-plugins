// Shared paths for the jobsearch-kit scripts: the workspace root and the npm dependency folder.
//
// Workspace root (the folder that holds MyProfile/), in this order:
//   1. --root <dir> on the command line;
//   2. the JOBSEARCH_ROOT environment variable;
//   3. the nearest folder, from the start folder upwards, that contains MyProfile/cv/cv_master.yaml; the start
//      folder is the current directory, or the folder of the input file if the caller gives one;
//   4. the current directory.
//
// npm packages are kept outside the plugin and the workspace (a workspace may live in a synced folder such as
// OneDrive): in node_modules under JOBSEARCH_DEPS, default %LOCALAPPDATA%\ai-plugins\jobsearch-kit.
// Install them with scripts/install-deps.ps1.
const fs = require('fs');
const os = require('os');
const path = require('path');

const MASTER_REL = path.join('MyProfile', 'cv', 'cv_master.yaml');

const depsDir = process.env.JOBSEARCH_DEPS
  || path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local'), 'ai-plugins', 'jobsearch-kit');

// Loads an npm package from the dependency folder (or from next to the scripts, for development).
function requireDep(name) {
  let resolved;
  try {
    resolved = require.resolve(name, { paths: [depsDir, __dirname] });
  } catch {
    console.error(`ERROR: npm package "${name}" not found in ${path.join(depsDir, 'node_modules')}.`
      + ` Run: pwsh -File "${path.join(__dirname, 'install-deps.ps1')}"`);
    process.exit(1);
  }
  return require(resolved);
}

// Removes "--root <dir>" from args (in place) and returns <dir>, or undefined.
function takeRootArg(args) {
  const i = args.indexOf('--root');
  if (i < 0) return undefined;
  const dir = args[i + 1];
  if (!dir) throw new Error('--root needs a folder');
  args.splice(i, 2);
  return dir;
}

function findRoot(explicit, startDirs = [process.cwd()]) {
  const given = explicit || process.env.JOBSEARCH_ROOT;
  if (given) return path.resolve(given);
  for (const start of startDirs) {
    for (let dir = path.resolve(start); ; dir = path.dirname(dir)) {
      if (fs.existsSync(path.join(dir, MASTER_REL))) return dir;
      if (path.dirname(dir) === dir) break;
    }
  }
  return process.cwd();
}

module.exports = { depsDir, requireDep, takeRootArg, findRoot, MASTER_REL };
