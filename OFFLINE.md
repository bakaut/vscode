# Code Offline — initial Linux build

Local-first fork of Code OSS. Retains Monaco, Workbench, terminal, local Git, built-in language extensions and local VSIX management. No built-in Copilot extension or packaged Copilot runtime; product telemetry, crash uploads, public gallery configuration, AI endpoints and core HTTP request paths are disabled. Desktop default-session HTTP(S)/WebSocket requests are cancelled.

## Build and installation

GitHub Actions uses GitHub-hosted Ubuntu 24.04 amd64, pinned Node and pnpm from upstream, and upstream Linux packaging tasks. CI uploads DEB, RPM, tar.gz, a local APT Packages index and SHA256SUMS. Install the DEB with `sudo apt install ./code-offline_..._amd64.deb`. No Microsoft APT source or key is installed. The local APT index is unsigned and intended for offline/local distribution; it is not a hosted signed APT service.

Install extensions using **Extensions: Install from VSIX** or `code-offline --install-extension ./example.vsix`. Install dependencies separately. Third-party extensions can execute arbitrary code including network access; this build is not a network sandbox. Terminal commands also retain their own networking. Only trusted VSIX files should be installed.

## Scope and remaining acceptance gates

This first PR is deliberately incremental: upstream AI service interfaces and shared registrations remain for compatibility; some dormant AI UI and code may remain. It does not claim complete AI code removal or zero network at the OS level. The build uses upstream dependencies (including some build-only AI dependencies) from the network. Verify package contents, desktop startup, local extension install, no external core connections under tracing, and audit third-party extensions separately before declaring full offline certification.

The effective configuration locks telemetry off, AI features off, extension updates/recommendations off, Git autofetch off, automatic JSON schema and TypeScript type acquisition off. The extension search box searches installed extensions. These restrictions do not disable local language analysis, shell commands or explicit external applications.
