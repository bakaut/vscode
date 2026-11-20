# Optional starter extensions — local VSIX only

Code Offline has **no Marketplace, account login, automatic VSIX download or extension update**. This catalog describes the requested set; it does **not** embed, download or redistribute third-party binaries. Each package must be independently reviewed for redistribution permissions, authenticity, license and background network activity.

## Extensions

- `eamodio.gitlens` — **GitLens Community**. Бесплатная часть; Pro/AI/integrations отключены политикой
- `ms-python.python` — **Python**. Дополнительные языковые серверы и debugger должны быть доступны локально
- `golang.go` — **Go**. gopls установить отдельно из локальных средств
- `redhat.vscode-xml` — **XML**. Поддержка XML; Java/runtime при необходимости локально
- `redhat.vscode-yaml` — **YAML**. Отключена Red Hat telemetry
- `mechatroner.rainbow-csv` — **Rainbow CSV**. Локальное отображение CSV/TSV
- `oderwat.indent-rainbow` — **Indent Rainbow**. Подсветка уровней отступов в YAML/Ansible/Bash
- `mads-hartmann.bash-ide-vscode` — **Bash IDE**. Shell language server и инструменты устанавливаются локально
- `redhat.ansible` — **Ansible**. Ansible language server и ansible-lint локально; телеметрия отключена

## Local installation

Collect the trusted VSIX archives on a machine allowed to download them. Copy them via a trusted medium into one directory named exactly by extension ID, e.g. `eamodio.gitlens.vsix`, `golang.go.vsix`. Check the license and checksum from a trustworthy source. Then, on the target computer with the source tree and Node.js installed:

```bash
node scripts/offline/install-starter-vsix.mjs --list
node scripts/offline/install-starter-vsix.mjs ./trusted-vsix
```

The importer validates ZIP paths and the publisher/name in each `extension/package.json` before installing anything, prints SHA256 and invokes only the **local** editor CLI. To override its location, use `CODE_OFFLINE_BIN=/path/to/code-offline`. A missing package stops the import rather than triggering any network download. Third-party extension dependencies and language servers must be provided separately; some third-party extensions may try their own network connections. Installing local VSIX does not guarantee network isolation; review each extension before using it.

GitLens Community remains free without signing in, but advanced GitKraken functionality needs an account and is disabled by the Code Offline policy. Additional sign-in prompts generated directly by third-party extensions cannot be suppressed by the core account UI policy. The application does not run this installer automatically at startup.
