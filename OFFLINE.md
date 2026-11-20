# Code Offline — Linux and macOS builds

Local-first fork of Code OSS. Retains Monaco, Workbench, terminal, local Git, built-in language extensions and local VSIX management. No built-in Copilot extension or packaged Copilot runtime; product telemetry, crash uploads, public gallery configuration, AI endpoints and core HTTP request paths are disabled. Desktop default-session HTTP(S)/WebSocket requests are cancelled.

## Build and installation

GitHub Actions uses GitHub-hosted Ubuntu 24.04 amd64, pinned Node and pnpm from upstream, and upstream Linux packaging tasks. CI uploads DEB, RPM, tar.gz, a local APT Packages index and SHA256SUMS. Install the DEB with `sudo apt install ./code-offline_..._amd64.deb`. No Microsoft APT source or key is installed. The local APT index is unsigned and intended for offline/local distribution; it is not a hosted signed APT service.

Install extensions using **Extensions: Install from VSIX** or `code-offline --install-extension ./example.vsix`. Install dependencies separately. Third-party extensions can execute arbitrary code including network access; this build is not a network sandbox. Terminal commands also retain their own networking. Only trusted VSIX files should be installed.

## Scope and remaining acceptance gates

This first PR is deliberately incremental: upstream AI service interfaces and shared registrations remain for compatibility; some dormant AI UI and code may remain. It does not claim complete AI code removal or zero network at the OS level. The build uses upstream dependencies (including some build-only AI dependencies) from the network. Verify package contents, desktop startup, local extension install, no external core connections under tracing, and audit third-party extensions separately before declaring full offline certification.

The effective configuration locks telemetry off, AI features off, extension updates/recommendations off, Git autofetch off, automatic JSON schema and TypeScript type acquisition off. The extension search box searches installed extensions. These restrictions do not disable local language analysis, shell commands or explicit external applications.

## macOS packages

Native GitHub-hosted macOS 15 runners build arm64 (Apple Silicon) and x64 (Intel) DMG files separately. The app has its own bundle identifier. CI verifies the native executable architecture, ad-hoc signature, package contents, local VSIX installation and activation, and forced offline settings. Each DMG and SHA256 checksum is uploaded as a raw artifact. These builds are ad-hoc signed for testing, not Developer ID signed or Apple-notarized; normal Gatekeeper requirements still apply. The macOS smoke test does not constitute an OS-level network audit.

## Local identity, startup, and optional extensions

The Code Offline desktop application suppresses its GitHub/Default Account sign-in command, keeps the Accounts UI hidden, rejects new authentication sessions via the core service, keeps Settings Sync unconditionally off and does not show sign-in/onboarding on first launch. Settings, workspaces and profiles continue to persist **locally**. Git commands and third-party VSIX tools remain independent: external Git credential prompts and extensions that implement their own login/network functionality require separate policy.

The requested optional starter set and its offline importer are documented in [scripts/offline/STARTER-EXTENSIONS.md](scripts/offline/STARTER-EXTENSIONS.md). External VSIX binaries are not shipped by default and require local review before installation.

## Reproducible bundled language and Git extensions

GitHub Actions downloads 12 stable, pinned Open VSX VSIX packages **at build time** and embeds them in the three native installers: GitLens Community, Python, Go, XML, YAML, Rainbow CSV, indent-rainbow, Bash IDE, Ansible, HashiCorp Terraform, Python Environments and Python Debugger. Each artifact's SHA256, publisher, version and ZIP safety are verified before packaging. Only allowed open-source licenses (MIT/EPL-2.0/MPL-2.0) are accepted. Package smoke tests confirm all 12 are present. Runtime never contacts Open VSX.

See `scripts/offline/bundled-extensions.lock.json` and `scripts/offline/bundle-extensions.py`. No Pylance binary is shipped, and separate local system tools may be needed for full Go/Ansible/Bash/XML features. GitLens Pro/AI, Red Hat telemetry, Terraform MCP/telemetry and Ansible MCP are disabled by effective editor policy. Third-party VSIX code still has direct network capability if it ignores settings, therefore **this is not an extension network sandbox**.
