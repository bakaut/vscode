#!/usr/bin/env bash
set -euo pipefail
deb="$1"
test "$(dpkg-deb -f "$deb" Package)" = code-offline
test "$(dpkg-deb -f "$deb" Architecture)" = amd64
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
dpkg-deb -e "$deb" "$tmp/control"
if grep -Ei 'packages\.microsoft\.com|apt-key|vscode\.sources|vscode_copilot_link|curl|wget' "$tmp/control/postinst" "$tmp/control/postrm"; then exit 1; fi
dpkg-deb -x "$deb" "$tmp/root"
app="$tmp/root/usr/share/code-offline/resources/app"
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
# Test the actual APT installation, not only extraction.
apt_snapshot() { sudo find /etc/apt/sources.list.d /etc/apt/keyrings /usr/share/keyrings -type f -print0 | sort -z | sudo xargs -0 -r sha256sum; }
apt_snapshot > "$tmp/apt-before"
sudo apt-get install -y "$(realpath "$deb")"
apt_snapshot > "$tmp/apt-after"
diff -u "$tmp/apt-before" "$tmp/apt-after"
bin=/usr/bin/code-offline
mkdir -p "$tmp/vsix/extension" "$tmp/data" "$tmp/extensions"
printf '%s\n' '{"name":"offline-smoke","displayName":"Offline Smoke","publisher":"offline-test","version":"1.0.0","engines":{"vscode":"^1.0.0"},"contributes":{"snippets":[{"language":"plaintext","path":"./snippets.json"}]}}' > "$tmp/vsix/extension/package.json"
printf '%s\n' '{}' > "$tmp/vsix/extension/snippets.json"
printf '%s\n' '<?xml version="1.0" encoding="utf-8"?><PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011"><Metadata><Identity Id="offline-smoke" Version="1.0.0" Publisher="offline-test"/><DisplayName>Offline Smoke</DisplayName></Metadata><Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation><Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets></PackageManifest>' > "$tmp/vsix/extension.vsixmanifest"
printf '%s\n' '<?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="json" ContentType="application/json"/><Default Extension="vsixmanifest" ContentType="text/xml"/></Types>' > "$tmp/vsix/[Content_Types].xml"
(cd "$tmp/vsix" && zip -qr "$tmp/test.vsix" .)
args=(--user-data-dir "$tmp/data" --extensions-dir "$tmp/extensions")
"$bin" --version
"$bin" "${args[@]}" --install-extension "$tmp/test.vsix"
"$bin" "${args[@]}" --list-extensions | grep -Fx offline-test.offline-smoke
if "$bin" "${args[@]}" --install-extension github.copilot; then
  echo 'Unexpected gallery installation success'; exit 1
fi
