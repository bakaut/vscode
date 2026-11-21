#!/usr/bin/env node
// Local-only, opt-in VSIX importer. Never fetches extensions or dependencies.
import { readFileSync, existsSync, lstatSync, realpathSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
const here = path.dirname(fileURLToPath(import.meta.url));
const catalog = JSON.parse(readFileSync(path.join(here, 'starter-extensions.json'), 'utf8'));
const args = process.argv.slice(2);
if (args.length === 1 && args[0] === '--list') {
  for (const entry of catalog.extensions) console.log(`${entry.id}\t${entry.name}`);
  process.exit(0);
}
if (args.length !== 1) {
  console.error('Usage: node scripts/offline/install-starter-vsix.mjs --list | /path/to/local-vsix-directory');
  process.exit(2);
}
const directory = realpathSync(args[0]);
const executable = process.env.CODE_OFFLINE_BIN || (process.platform === 'darwin'
  ? '/Applications/Code Offline.app/Contents/Resources/app/bin/code' : 'code-offline');
if (!existsSync(directory) || !lstatSync(directory).isDirectory()) throw Error('Not a local VSIX directory');
const checked = [];
let failed = false;
for (const entry of catalog.extensions) {
  const file = path.join(directory, entry.id + '.vsix');
  try {
    if (!existsSync(file) || !lstatSync(file).isFile() || lstatSync(file).isSymbolicLink()) throw Error('VSIX file missing or not regular');
    // Validate local archive layout and actual publisher/name, not just the filename.
    const entries = execFileSync('unzip', ['-Z', '-1', file], { encoding: 'utf8', timeout: 15000, maxBuffer: 8*1024*1024 }).split(/\r?\n/).filter(Boolean);
    if (entries.some(name => name.startsWith('/') || name.split('/').includes('..') || name.includes('\\'))) throw Error('Unsafe ZIP paths');
    const content = execFileSync('unzip', ['-p', file, 'extension/package.json'], { encoding: 'utf8', timeout: 15000, maxBuffer: 8*1024*1024 });
    const manifest = JSON.parse(content);
    const actual = `${manifest.publisher}.${manifest.name}`.toLowerCase();
    if (actual !== entry.id.toLowerCase()) throw Error(`Wrong extension identity: ${actual}`);
    const digest = createHash('sha256').update(readFileSync(file)).digest('hex');
    console.log(`VERIFIED ${entry.id} ${manifest.version} SHA256=${digest}`);
    checked.push({ entry, file });
  } catch (error) {
    failed = true;
    console.error(`MISSING / INVALID ${entry.id}: ${error.message}`);
  }
}
if (failed) {
  console.error('Nothing installed. Provide all reviewed, trustworthy VSIX files locally and retry.');
  process.exit(1);
}
for (const { entry, file } of checked) {
  console.log(`Installing local VSIX: ${entry.id}`);
  execFileSync(executable, ['--install-extension', file], { stdio: 'inherit', timeout: 120000 });
}
console.log('All starter extensions installed from local files. No store access was requested.');
