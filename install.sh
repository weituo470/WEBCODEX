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
AUTO_NGINX="${AUTO_NGINX:-1}"
SERVER_NAME="${SERVER_NAME:-_}"
WEB_USER="${WEB_USER:-codex}"
WEB_PASSWORD="${WEB_PASSWORD:-}"
NGINX_SITE_FILE="${NGINX_SITE_FILE:-/etc/nginx/conf.d/${SERVICE_NAME}.conf}"
HTPASSWD_FILE="${HTPASSWD_FILE:-/etc/nginx/.codex-htpasswd}"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "please run as root"
    exit 1
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

detect_pkg_manager() {
  if command_exists apt-get; then
    echo apt
    return
  fi
  if command_exists dnf; then
    echo dnf
    return
  fi
  if command_exists yum; then
    echo yum
    return
  fi
  echo ""
}

install_packages() {
  local manager
  manager="$(detect_pkg_manager)"
  if [[ -z "$manager" ]]; then
    echo "no supported package manager found, please install tmux nginx curl openssl tar manually"
    exit 1
  fi

  case "$manager" in
    apt)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y tmux nginx curl openssl tar ca-certificates
      ;;
    dnf)
      dnf install -y tmux nginx curl openssl tar ca-certificates
      ;;
    yum)
      yum install -y epel-release || true
      yum install -y tmux nginx curl openssl tar ca-certificates
      ;;
  esac
}

ensure_base_dependencies() {
  local missing=0
  for bin in tmux nginx curl openssl tar; do
    if ! command_exists "$bin"; then
      missing=1
      break
    fi
  done
  if [[ "$missing" -eq 1 ]]; then
    install_packages
  fi
}

detect_gotty_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      echo linux_amd64
      ;;
    aarch64|arm64)
      echo linux_arm64
      ;;
    *)
      echo ""
      ;;
  esac
}

install_gotty() {
  local arch latest_url version tmpdir asset api_url
  arch="$(detect_gotty_arch)"
  if [[ -z "$arch" ]]; then
    echo "unsupported architecture for automatic gotty install: $(uname -m)"
    exit 1
  fi

  api_url="https://api.github.com/repos/yudai/gotty/releases/latest"
  asset="$(curl -fsSL "$api_url" | tr -d '\r' | grep -o "https://[^\"]*gotty_[^\"]*_${arch}\\.tar\\.gz" | head -n 1)"
  if [[ -z "$asset" ]]; then
    echo "failed to locate latest gotty release asset"
    exit 1
  fi

  tmpdir="$(mktemp -d)"
  curl -fsSL "$asset" -o "$tmpdir/gotty.tgz"
  tar -xzf "$tmpdir/gotty.tgz" -C "$tmpdir"
  install -m 0755 "$tmpdir/gotty" "$GOTTY_BIN"
  rm -rf "$tmpdir"
}

ensure_gotty() {
  if [[ -x "$GOTTY_BIN" ]]; then
    return
  fi
  install_gotty
}

ensure_codex() {
  CODEX_BIN="${CODEX_BIN:-$(command -v codex || true)}"
  if [[ -z "$CODEX_BIN" || ! -x "$CODEX_BIN" ]]; then
    cat <<'EOF'
codex is not installed.

install codex first, then rerun this script.
EOF
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

write_htpasswd() {
  if [[ -z "$WEB_PASSWORD" ]]; then
    WEB_PASSWORD="$(openssl rand -base64 18 | tr -d '\n' | tr '/+' 'ab' | cut -c1-20)"
  fi
  umask 077
  printf "%s:%s\n" "$WEB_USER" "$(openssl passwd -6 "$WEB_PASSWORD")" > "$HTPASSWD_FILE"
}

write_nginx_config() {
  if [[ "$AUTO_NGINX" != "1" ]]; then
    return
  fi

  mkdir -p "$(dirname "$NGINX_SITE_FILE")"
  cat >"$NGINX_SITE_FILE" <<EOF
server {
    listen 80;
    server_name $SERVER_NAME;

    location = $PATH_PREFIX {
        return 302 $PATH_PREFIX/;
    }

    location ^~ $PATH_PREFIX/ {
        auth_basic "Codex Web Terminal";
        auth_basic_user_file $HTPASSWD_FILE;

        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
    }
}
EOF
}

reload_services() {
  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
  if [[ "$AUTO_NGINX" == "1" ]]; then
    systemctl enable nginx >/dev/null 2>&1 || true
    nginx -t
    systemctl restart nginx
  fi
}

print_summary() {
  cat <<EOF

installed:
- wrapper: $WRAPPER_PATH
- service: $SERVICE_FILE
- ui dir : $INSTALL_DIR
- gotty  : $GOTTY_BIN

service:
  systemctl status $SERVICE_NAME

access:
  http://$(hostname -I | awk '{print $1}')$PATH_PREFIX/

auth:
  username: $WEB_USER
EOF

  if [[ -n "$WEB_PASSWORD" ]]; then
    printf "  password: %s\n" "$WEB_PASSWORD"
  else
    printf "  password: not set by script\n"
  fi

  cat <<EOF

notes:
- the main persistent codex conversation is tmux session: codex-main
- duplicated tabs create independent tmux sessions named codex-tab-*
- if you copy this directory with index.html, you keep the current multi-tab mobile-friendly UI
EOF
}

main() {
  require_root
  ensure_base_dependencies
  ensure_gotty
  ensure_codex
  copy_assets
  write_wrapper
  write_service
  write_htpasswd
  write_nginx_config
  reload_services
  print_summary
}

main "$@"
