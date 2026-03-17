# Codex Web Terminal Lite

The fastest reusable way to expose Codex in a browser on another Linux server.

If you hand this repository URL to Codex on another server, Codex should follow the deployment instructions in [AGENTS.md](/root/codex-web-terminal-lite/AGENTS.md) and execute the install instead of only explaining it.

## What it does

- runs Codex through `tmux` for persistent sessions
- exposes it through `gotty`
- optionally writes nginx config and basic auth automatically
- keeps the default main conversation in `codex-main`
- includes the current multi-tab mobile-friendly web UI

## One-command bootstrap

If `codex` is already installed and logged in on the target server:

```bash
curl -fsSL https://raw.githubusercontent.com/weituo470/WEBCODEX/main/bootstrap.sh | \
WEB_PASSWORD='ChangeThisNow123!' \
SERVER_NAME='_' \
bash
```

Then open:

```text
http://YOUR_HOST/codex/
```

Default username:

```text
codex
```

## For another server's Codex

If you only provide the repository URL to Codex, the expected behavior is:

- check that `codex` is installed
- if login is missing, ask you to run `codex login`
- otherwise run this repository's installer directly
- return the final access URL, username, password, and service status

The repo-level automation instructions live in [AGENTS.md](/root/codex-web-terminal-lite/AGENTS.md).

## What the installer handles

- installs missing base packages: `tmux`, `nginx`, `curl`, `openssl`, `tar`
- downloads the latest compatible `gotty` release if missing
- writes `/usr/local/bin/codex-web-shell`
- writes `codex-web-terminal.service`
- writes nginx site config when `AUTO_NGINX=1`
- writes `/etc/nginx/.codex-htpasswd`, auto-generating a password when needed

## Required prerequisite

`codex` itself must already be installed and authenticated on the target server.

If not, run:

```bash
codex login
```

## Useful environment variables

```bash
WEB_PASSWORD='YourPassword'
WEB_USER='codex'
SERVER_NAME='_'
PATH_PREFIX='/codex'
AUTO_NGINX='1'
PORT='8765'
```

## Manual install

```bash
git clone https://github.com/weituo470/WEBCODEX.git
cd WEBCODEX
chmod +x install.sh
WEB_PASSWORD='ChangeThisNow123!' ./install.sh
```

## Session persistence

- reconnecting to the same web entry returns to `codex-main`
- extra tabs create separate `tmux` sessions named `codex-tab-*`
