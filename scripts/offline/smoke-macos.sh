#!/usr/bin/env bash
set -euo pipefail
bundle="$1"
arch="$2"
app="$bundle/Contents/Resources/app"
bin="$app/bin/code"
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Contents/Info.plist")
electron="$bundle/Contents/MacOS/$executable"
expected_arch="$arch"
if [[ "$arch" == x64 ]]; then expected_arch=x86_64; fi
lipo "$electron" -verify_arch "$expected_arch"
codesign --verify --deep --strict "$bundle"
python3 scripts/offline/bundle-extensions.py verify --platform "darwin-$arch" --app "$app"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")" = io.github.bakaut.CodeOffline
tmp=$(mktemp -d)
diagnostics="${OFFLINE_DIAGNOSTICS_DIR:-$PWD/offline-diagnostics}"
mkdir -p "$diagnostics"
pid=''
cleanup() {
  status=$?
  if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  if (( status != 0 )); then
    if [[ -f "$tmp/desktop.log" ]]; then cp "$tmp/desktop.log" "$diagnostics/"; tail -n 150 "$tmp/desktop.log"; fi
    if [[ -d "$tmp/data/logs" ]]; then
      cp -R "$tmp/data/logs" "$diagnostics/workbench-logs"
      find "$tmp/data/logs" -name '*.log' -type f -print -exec tail -n 80 {} \;
    fi
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
test -f "$app/product.json"
test ! -d "$app/extensions/copilot"
node - "$app/product.json" <<'NODE'
const p = require(process.argv[2]);
if (p.applicationName !== 'code-offline' || p.enableTelemetry !== false || p.extensionsGallery || p.voiceWsUrl || p.appCenter) throw Error('Invalid offline product');
if (Object.entries(p.defaultChatAgent).some(([k,v]) => k.endsWith('Url') && v)) throw Error('AI endpoint in product');
NODE
if find "$app" -type f -path '*/@microsoft/copilot-sdk*/*' -print -quit | grep -q .; then
  echo 'Copilot runtime present in package'; exit 1
fi
node - "$app/node_modules.asar" <<'NODE'
const fs = require('node:fs');
const fd = fs.openSync(process.argv[2], 'r');
const header = Buffer.alloc(16);
fs.readSync(fd, header, 0, 16, 0);
const length = header.readUInt32LE(12);
if (!length || length > 100000000) throw Error('Invalid ASAR header');
const json = Buffer.alloc(length);
fs.readSync(fd, json, 0, length, 16);
fs.closeSync(fd);
const tree = JSON.parse(json.toString());
function walk(node, path = '') {
  for (const [name, entry] of Object.entries(node.files || {})) {
    const full = path + '/' + name;
    if (/\/(?:@microsoft\/copilot-sdk(?:-[^/]+)?|@anthropic-ai\/sdk|@vscode\/copilot-api)(?:\/|$)/.test(full)) throw Error('AI SDK shipped: ' + full);
    walk(entry, full);
  }
}
walk(tree);
NODE
mkdir -p "$tmp/vsix/extension" "$tmp/data" "$tmp/extensions"
printf '%s\n' '{"name":"offline-smoke","displayName":"Offline Smoke","publisher":"offline-test","version":"1.0.0","engines":{"vscode":"^1.0.0"},"main":"./main.js","activationEvents":["onStartupFinished"],"capabilities":{"untrustedWorkspaces":{"supported":true}},"contributes":{"snippets":[{"language":"plaintext","path":"./snippets.json"}]}}' > "$tmp/vsix/extension/package.json"
printf '%s\n' '{}' > "$tmp/vsix/extension/snippets.json"
cat > "$tmp/vsix/extension/main.js" <<'JS'
const vscode = require('vscode');
const fs = require('node:fs');
exports.activate = async (context) => {
  const bundled = ["eamodio.gitlens","ms-python.python","ms-python.vscode-python-envs","ms-python.debugpy","golang.Go","redhat.vscode-xml","redhat.vscode-yaml","mechatroner.rainbow-csv","oderwat.indent-rainbow","mads-hartmann.bash-ide-vscode","redhat.ansible","hashicorp.terraform"];
  const extensionIds = new Set(vscode.extensions.all.map(e => e.id.toLowerCase()));
  const missing = bundled.filter(id => !extensionIds.has(id.toLowerCase()));
  if (missing.length) throw Error('Bundled extensions not registered in Extension Host: ' + missing.join(', '));
  // Local settings must remain writable without any account or cloud sync.
  await vscode.workspace.getConfiguration('editor').update('fontSize', 17, vscode.ConfigurationTarget.Global);
  if (vscode.workspace.getConfiguration('editor').get('fontSize') !== 17) throw Error('Local settings were not saved');
  const cfg = vscode.workspace.getConfiguration();
  const values = Object.fromEntries(['chat.disableAIFeatures','chat.mcp.access','telemetry.telemetryLevel','extensions.autoUpdate','git.autofetch'].map(k => [k, cfg.get(k)]));
  fs.writeFileSync(require('node:path').join(context.extensionPath, 'activated.json'), JSON.stringify(values));
};
JS
printf '%s\n' '<?xml version="1.0" encoding="utf-8"?><PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011"><Metadata><Identity Id="offline-smoke" Version="1.0.0" Publisher="offline-test"/><DisplayName>Offline Smoke</DisplayName></Metadata><Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation><Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets></PackageManifest>' > "$tmp/vsix/extension.vsixmanifest"
printf '%s\n' '<?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="json" ContentType="application/json"/><Default Extension="vsixmanifest" ContentType="text/xml"/></Types>' > "$tmp/vsix/[Content_Types].xml"
(cd "$tmp/vsix" && zip -qr "$tmp/test.vsix" .)
args=(--user-data-dir "$tmp/data" --extensions-dir "$tmp/extensions")
"$bin" --version
"$bin" "${args[@]}" --install-extension "$tmp/test.vsix"
"$bin" "${args[@]}" --list-extensions | grep -Fx offline-test.offline-smoke
# Verify that even deliberately conflicting user settings cannot re-enable online features.
mkdir -p "$tmp/data/User" "$tmp/workspace"
printf '%s\n' '{"chat.disableAIFeatures":false,"chat.mcp.access":"all","telemetry.telemetryLevel":"all","extensions.autoUpdate":"on","git.autofetch":true}' > "$tmp/data/User/settings.json"
export CODE_OFFLINE_SMOKE_MARKER="$tmp/extensions/offline-test.offline-smoke-1.0.0/activated.json"

unset NODE_OPTIONS
"$electron" --user-data-dir "$tmp/data" --extensions-dir "$tmp/extensions" --new-window --skip-welcome --skip-release-notes --verbose --log trace "$tmp/workspace" > "$tmp/desktop.log" 2>&1 &
pid=$!
for i in $(seq 1 120); do
  if [[ -s "$CODE_OFFLINE_SMOKE_MARKER" ]]; then break; fi
  if ! kill -0 "$pid" 2>/dev/null; then echo 'Desktop exited before activation'; exit 1; fi
  sleep 1
done
test -s "$CODE_OFFLINE_SMOKE_MARKER"
node - "$CODE_OFFLINE_SMOKE_MARKER" <<'NODE'
const v = require(process.argv[2]);
const expected = {'chat.disableAIFeatures':true,'chat.mcp.access':'none','telemetry.telemetryLevel':'off','extensions.autoUpdate':'off','git.autofetch':false};
for (const [k, x] of Object.entries(expected)) {
  if (v[k] !== x) throw Error('Offline setting mismatch: ' + k + ': ' + v[k]);
}
NODE

kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
pid=''
if "$bin" "${args[@]}" --install-extension github.copilot; then
  echo 'Unexpected gallery installation success'; exit 1
fi
