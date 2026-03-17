#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-codex-web-terminal}"
PATH_PREFIX="${PATH_PREFIX:-/codex}"
PORT="${PORT:-8765}"
WORKDIR="${WORKDIR:-/root}"
INSTALL_DIR="${INSTALL_DIR:-/opt/codex-web-terminal}"
WRAPPER_PATH="${WRAPPER_PATH:-/usr/local/bin/codex-web-shell}"
GOTTY_BIN="${GOTTY_BIN:-/usr/local/bin/gotty}"
TMUX_BIN="${TMUX_BIN:-/usr/bin/tmux}"
CODEX_BIN="${CODEX_BIN:-$(command -v codex || true)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INDEX_SRC="${INDEX_SRC:-$SCRIPT_DIR/index.html}"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "please run as root"
    exit 1
  fi
}

require_bin() {
  local name="$1"
  local path="$2"
  if [[ -z "$path" || ! -x "$path" ]]; then
    echo "missing required binary: ${name} (${path})"
    exit 1
  fi
}

write_wrapper() {
  cat >"$WRAPPER_PATH" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export TERM="${TERM:-xterm-256color}"
export COLORTERM="${COLORTERM:-truecolor}"
export FORCE_COLOR="${FORCE_COLOR:-1}"
export CLICOLOR_FORCE="${CLICOLOR_FORCE:-1}"
export TERM_PROGRAM="${TERM_PROGRAM:-tmux}"

cd /root

raw_session="${1:-codex-main}"
session_name="$(printf '%s' "$raw_session" | tr -cd '[:alnum:]-_' | cut -c1-48)"
session_name="${session_name:-codex-main}"

if ! /usr/bin/tmux has-session -t "$session_name" 2>/dev/null; then
  /usr/bin/tmux new-session -d -s "$session_name" -c /root 'bash -lc "codex"'
fi

exec /usr/bin/tmux attach-session -t "$session_name"
EOF
  chmod 0755 "$WRAPPER_PATH"
}

write_service() {
  local index_args=""
  if [[ -f "$INSTALL_DIR/index.html" ]]; then
    index_args="--index $INSTALL_DIR/index.html"
  fi

  cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=Codex Web Terminal
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WORKDIR
Environment=HOME=$WORKDIR
Environment=TERM=xterm-256color
ExecStart=$GOTTY_BIN --address 127.0.0.1 --port $PORT --path $PATH_PREFIX --permit-write --permit-arguments --reconnect --reconnect-time 30 --title-format "Codex Web Terminal" $index_args $WRAPPER_PATH
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
}

copy_assets() {
  mkdir -p "$INSTALL_DIR"
  if [[ -f "$INDEX_SRC" ]]; then
    cp "$INDEX_SRC" "$INSTALL_DIR/index.html"
  fi
}

print_summary() {
  cat <<EOF

installed:
- wrapper: $WRAPPER_PATH
- service: $SERVICE_FILE
- ui dir : $INSTALL_DIR

service:
  systemctl status $SERVICE_NAME

next step:
1. put the nginx snippet from nginx.codex.conf.example into your server block
2. create basic auth if needed:
   printf "codex:\$(openssl passwd -6 'YOUR_PASSWORD')\n" > /etc/nginx/.codex-htpasswd
3. reload nginx:
   nginx -t && systemctl reload nginx

access path:
  http://YOUR_HOST$PATH_PREFIX/

notes:
- the main persistent codex conversation is tmux session: codex-main
- duplicated tabs create independent tmux sessions named codex-tab-*
- if you copy this directory with index.html, you keep the current multi-tab mobile-friendly UI
EOF
}

main() {
  require_root
  require_bin "gotty" "$GOTTY_BIN"
  require_bin "tmux" "$TMUX_BIN"
  require_bin "codex" "$CODEX_BIN"

  copy_assets
  write_wrapper
  write_service

  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"

  print_summary
}

main "$@"
