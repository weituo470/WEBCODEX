# Codex Web Terminal Lite

The simplest reusable way to expose Codex in a browser on another Linux server.

## What it installs

- `gotty` service on `127.0.0.1:8765`
- `tmux`-backed Codex wrapper
- persistent main session: `codex-main`
- optional custom UI page if `index.html` exists next to `install.sh`

## Prerequisites

- `codex` already installed in `PATH`
- `tmux` installed
- `gotty` installed at `/usr/local/bin/gotty`
- nginx already available if you want public access

## Install

```bash
cd /root/codex-web-terminal-lite
chmod +x install.sh
./install.sh
```

## Public access

Add the content of [nginx.codex.conf.example](/root/codex-web-terminal-lite/nginx.codex.conf.example) into your nginx server block, then:

```bash
printf "codex:$(openssl passwd -6 'YOUR_PASSWORD')\n" > /etc/nginx/.codex-htpasswd
nginx -t && systemctl reload nginx
```

Then open:

```text
http://YOUR_HOST/codex/
```

## How session persistence works

- the default long-lived Codex conversation lives in `tmux` session `codex-main`
- reconnecting to the same web entry returns to that same main session
- extra tabs create independent `tmux` sessions named `codex-tab-*`
