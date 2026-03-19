#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-codex-web-terminal}"
HELPER_SERVICE_NAME="${HELPER_SERVICE_NAME:-codex-web-helper}"
MAIN_SERVICE_NAME="${MAIN_SERVICE_NAME:-codex-main}"
WEB_USER="${WEB_USER:-codex}"
WEB_PASSWORD="${WEB_PASSWORD:-}"
SERVER_NAME="${SERVER_NAME:-_}"
WORKDIR="${WORKDIR:-/root}"
TERMINAL_PORT="${TERMINAL_PORT:-8765}"
HELPER_PORT="${HELPER_PORT:-8780}"
UI_DIR="${UI_DIR:-/opt/codex-web-ui}"
INDEX_SRC="${INDEX_SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/index.html}"
NGINX_SITE_FILE="${NGINX_SITE_FILE:-/etc/nginx/conf.d/${SERVICE_NAME}.conf}"
HELPER_ENV_FILE="${HELPER_ENV_FILE:-/etc/codex-web-helper.env}"
MAIN_BOOTSTRAP_PATH="${MAIN_BOOTSTRAP_PATH:-/usr/local/bin/codex-main-bootstrap}"
WRAPPER_PATH="${WRAPPER_PATH:-/usr/local/bin/codex-web-shell}"
TERMINAL_WRAPPER_PATH="${TERMINAL_WRAPPER_PATH:-/usr/local/bin/codex-web-terminal}"
HELPER_BIN_PATH="${HELPER_BIN_PATH:-/usr/local/bin/codex-web-helper}"
MAIN_SERVICE_FILE="/etc/systemd/system/${MAIN_SERVICE_NAME}.service"
HELPER_SERVICE_FILE="/etc/systemd/system/${HELPER_SERVICE_NAME}.service"
TERMINAL_SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
CODEX_BIN="${CODEX_BIN:-$(command -v codex || true)}"
CODEX_BIN_DIR=""
SESSION_SECRET=""
COOKIE_NAME=""
CONFIG_FILE="${CONFIG_FILE:-/etc/codex-web-terminal.env}"
CODEX_MAIN_RESUME_ID="${CODEX_MAIN_RESUME_ID:-}"

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
    echo "apt"
    return
  fi
  if command_exists dnf; then
    echo "dnf"
    return
  fi
  if command_exists yum; then
    echo "yum"
    return
  fi
  echo ""
}

install_packages() {
  local manager
  manager="$(detect_pkg_manager)"
  if [[ -z "$manager" ]]; then
    echo "no supported package manager found, please install tmux nginx curl openssl tar python3 ttyd manually"
    exit 1
  fi

  case "$manager" in
    apt)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y tmux nginx curl openssl tar ca-certificates python3 ttyd
      ;;
    dnf)
      dnf install -y tmux nginx curl openssl tar ca-certificates python3 ttyd
      ;;
    yum)
      yum install -y epel-release || true
      yum install -y tmux nginx curl openssl tar ca-certificates python3 ttyd
      ;;
  esac
}

ensure_dependencies() {
  local missing=0
  for bin in tmux nginx curl openssl tar python3 ttyd; do
    if ! command_exists "$bin"; then
      missing=1
      break
    fi
  done
  if [[ "$missing" -eq 1 ]]; then
    install_packages
  fi
  for bin in tmux nginx curl openssl tar python3 ttyd; do
    if ! command_exists "$bin"; then
      echo "missing required dependency after install attempt: $bin"
      exit 1
    fi
  done
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
  CODEX_BIN_DIR="$(dirname "$CODEX_BIN")"
}

generate_secrets() {
  if [[ -z "$WEB_PASSWORD" ]]; then
    WEB_PASSWORD="$(openssl rand -base64 18 | tr -d '\n' | tr '/+' 'ab' | cut -c1-20)"
  fi
  SESSION_SECRET="$(openssl rand -hex 32)"
  COOKIE_NAME="codex_session_$(printf '%s' "$SESSION_SECRET" | sha256sum | awk '{print substr($1,1,8)}')"
}

copy_ui() {
  mkdir -p "$UI_DIR"
  install -m 0644 "$INDEX_SRC" "$UI_DIR/index.html"
}

write_main_bootstrap() {
  cat >"$MAIN_BOOTSTRAP_PATH" <<EOF
#!/usr/bin/env bash
set -euo pipefail

export HOME=$WORKDIR
export TERM="\${TERM:-xterm-256color}"
export COLORTERM="\${COLORTERM:-truecolor}"
export FORCE_COLOR="\${FORCE_COLOR:-1}"
export CLICOLOR_FORCE="\${CLICOLOR_FORCE:-1}"
export TERM_PROGRAM="\${TERM_PROGRAM:-tmux}"
export PATH="$CODEX_BIN_DIR:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:$WORKDIR/bin:\${PATH:-}"
CONFIG_FILE="\${CODEX_WEB_CONFIG_FILE:-$CONFIG_FILE}"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

raw_session="${1:-codex-main}"
session_name="$(printf '%s' "$raw_session" | tr -cd '[:alnum:]-_' | cut -c1-48)"
session_name="${session_name:-codex-main}"
main_resume_id="${CODEX_MAIN_RESUME_ID:-}"

build_launch_command() {
  if [[ "$session_name" == "codex-main" && -n "$main_resume_id" ]]; then
    printf "exec codex resume %q" "$main_resume_id"
    return
  fi
  printf "exec codex"
}

ensure_session_running() {
  local launch_command pane_dead
  launch_command="$(build_launch_command)"

  if ! /usr/bin/tmux has-session -t "$session_name" 2>/dev/null; then
    /usr/bin/tmux new-session -d -s "$session_name" -c /root "bash -lc '$launch_command'"
    return
  fi

  pane_dead="$(/usr/bin/tmux display-message -p -t "${session_name}:0.0" '#{pane_dead}' 2>/dev/null || printf '1')"
  if [[ "$pane_dead" == "1" ]]; then
    /usr/bin/tmux respawn-pane -k -t "${session_name}:0.0" -c /root "bash -lc '$launch_command'"
  fi
}

ensure_session_running
EOF
  chmod 0755 "$MAIN_BOOTSTRAP_PATH"
}

write_shell_wrapper() {
  cat >"$WRAPPER_PATH" <<EOF
#!/usr/bin/env bash
set -euo pipefail

export HOME=$WORKDIR
export TERM="\${TERM:-xterm-256color}"
export COLORTERM="\${COLORTERM:-truecolor}"
export FORCE_COLOR="\${FORCE_COLOR:-1}"
export CLICOLOR_FORCE="\${CLICOLOR_FORCE:-1}"
export TERM_PROGRAM="\${TERM_PROGRAM:-tmux}"
export PATH="$CODEX_BIN_DIR:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:$WORKDIR/bin:\${PATH:-}"

raw_session="\${1:-codex-main}"
session_name="\$(printf '%s' "\$raw_session" | tr -cd '[:alnum:]-_' | cut -c1-48)"
session_name="\${session_name:-codex-main}"

$MAIN_BOOTSTRAP_PATH "\$session_name"
exec /usr/bin/tmux attach-session -t "\$session_name"
EOF
  chmod 0755 "$WRAPPER_PATH"
}

write_codex_config() {
  if [[ -z "$CODEX_MAIN_RESUME_ID" ]]; then
    return
  fi
  umask 077
  cat >"$CONFIG_FILE" <<EOF
CODEX_MAIN_RESUME_ID=$CODEX_MAIN_RESUME_ID
EOF
}

write_terminal_wrapper() {
  cat >"$TERMINAL_WRAPPER_PATH" <<EOF
#!/usr/bin/env bash
set -euo pipefail

exec /usr/bin/ttyd \\
  -i 127.0.0.1 \\
  -p $TERMINAL_PORT \\
  -W \\
  -a \\
  -w $WORKDIR \\
  -T xterm-256color \\
  -t rendererType=canvas \\
  -b /codex-terminal \\
  $WRAPPER_PATH
EOF
  chmod 0755 "$TERMINAL_WRAPPER_PATH"
}

write_helper_env() {
  cat >"$HELPER_ENV_FILE" <<EOF
CODEX_HELPER_HOST=127.0.0.1
CODEX_HELPER_PORT=$HELPER_PORT
CODEX_USER=$WEB_USER
CODEX_PASSWORD=$WEB_PASSWORD
CODEX_SESSION_SECRET=$SESSION_SECRET
CODEX_SESSION_TTL=2592000
CODEX_COOKIE_NAME=$COOKIE_NAME
EOF
  chmod 0600 "$HELPER_ENV_FILE"
}

write_helper() {
  cat >"$HELPER_BIN_PATH" <<'EOF'
#!/usr/bin/env python3
import hashlib
import hmac
import html
import json
import os
import shutil
import socket
import subprocess
import time
import urllib.parse
from socketserver import ThreadingMixIn
from http import HTTPStatus
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, HTTPServer


HOST = os.environ.get("CODEX_HELPER_HOST", "127.0.0.1")
PORT = int(os.environ.get("CODEX_HELPER_PORT", "8780"))
CODEX_USER = os.environ.get("CODEX_USER", "codex")
CODEX_PASSWORD = os.environ.get("CODEX_PASSWORD", "")
COOKIE_NAME = os.environ.get("CODEX_COOKIE_NAME", "codex_session")
SESSION_SECRET = os.environ.get("CODEX_SESSION_SECRET", "")
SESSION_TTL = int(os.environ.get("CODEX_SESSION_TTL", str(30 * 24 * 3600)))


def run_command(args):
    try:
        return subprocess.check_output(args, stderr=subprocess.DEVNULL).decode("utf-8", "ignore").strip()
    except Exception:
        return ""


def sign_session(username, expires_at):
    payload = f"{username}|{expires_at}".encode("utf-8")
    return hmac.new(SESSION_SECRET.encode("utf-8"), payload, hashlib.sha256).hexdigest()


def parse_cookie_header(header_value):
    cookie = SimpleCookie()
    if header_value:
        cookie.load(header_value)
    return cookie


def extract_session(handler):
    cookie = parse_cookie_header(handler.headers.get("Cookie"))
    if COOKIE_NAME not in cookie:
        return None
    value = cookie[COOKIE_NAME].value
    try:
        username, expires_at, signature = value.split("|", 2)
        expires_at = int(expires_at)
    except Exception:
        return None
    if username != CODEX_USER or expires_at < int(time.time()):
        return None
    expected = sign_session(username, expires_at)
    if not hmac.compare_digest(signature, expected):
        return None
    return username


def make_session_value(username):
    expires_at = int(time.time()) + SESSION_TTL
    return f"{username}|{expires_at}|{sign_session(username, expires_at)}"


def safe_next(target):
    if not target or not target.startswith("/"):
        return "/codex/"
    return target


def session_title(session_name):
    if session_name == "codex-main":
        return "主终端"
    suffix = session_name.replace("codex-tab-", "", 1)
    label = suffix.split("-", 1)[0] if suffix else session_name
    return f"终端 {label}"


def list_codex_sessions():
    output = run_command(["/usr/bin/tmux", "list-sessions", "-F", "#{session_name}"])
    items = []
    seen = set()
    for line in output.splitlines():
        name = line.strip()
        if not name or name in seen:
            continue
        if name == "codex-main" or name.startswith("codex-tab-"):
            seen.add(name)
            items.append({"session": name, "title": session_title(name)})
    if not items:
        items.append({"session": "codex-main", "title": "主终端"})
    items.sort(key=lambda item: (0 if item["session"] == "codex-main" else 1, item["session"]))
    return items


def read_loadavg():
    try:
        with open("/proc/loadavg", "r", encoding="utf-8") as fh:
            return fh.read().strip().split()[:3]
    except Exception:
        return ["-", "-", "-"]


def read_meminfo():
    result = {}
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as fh:
            for line in fh:
                key, value = line.split(":", 1)
                result[key] = int(value.strip().split()[0])
    except Exception:
        return None
    total = result.get("MemTotal", 0) * 1024
    available = result.get("MemAvailable", 0) * 1024
    used = max(total - available, 0)
    return total, used, available


def human_bytes(size):
    units = ["B", "KB", "MB", "GB", "TB"]
    value = float(size)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.1f} {unit}"
        value /= 1024
    return f"{size} B"


def human_duration(seconds):
    seconds = int(seconds)
    parts = []
    for unit_seconds, label in ((86400, "天"), (3600, "小时"), (60, "分钟")):
        if seconds >= unit_seconds:
            parts.append(f"{seconds // unit_seconds}{label}")
            seconds %= unit_seconds
    if seconds or not parts:
        parts.append(f"{seconds}秒")
    return " ".join(parts[:3])


def read_uptime():
    try:
        with open("/proc/uptime", "r", encoding="utf-8") as fh:
            return human_duration(float(fh.read().split()[0]))
    except Exception:
        return "-"


def service_state(name):
    state = run_command(["/usr/bin/systemctl", "is-active", name])
    return state or "unknown"


def shell_quote(text):
    return html.escape(text, quote=True)


LOGIN_STYLE = """
      :root {
        --bg: #f4efe7;
        --panel: rgba(255, 251, 244, 0.94);
        --line: #e7d9c6;
        --text: #201a15;
        --muted: #6b5b4c;
        --accent: #b6421f;
        --error: #bb3e2d;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        min-height: 100vh;
        font-family: "Segoe UI", "PingFang SC", "Noto Sans SC", sans-serif;
        color: var(--text);
        background:
          radial-gradient(circle at top, rgba(246, 219, 197, 0.9), transparent 36%),
          linear-gradient(180deg, #f8f2ea 0%, #efe4d6 100%);
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 20px;
      }
      .card {
        width: min(100%, 420px);
        background: var(--panel);
        border: 1px solid var(--line);
        border-radius: 28px;
        box-shadow: 0 18px 48px rgba(65, 37, 15, 0.12);
        padding: 28px;
        backdrop-filter: blur(12px);
      }
      .eyebrow {
        margin: 0 0 10px;
        color: var(--accent);
        font-size: 12px;
        font-weight: 800;
        letter-spacing: 0.18em;
        text-transform: uppercase;
      }
      h1 { margin: 0; font-size: 32px; line-height: 1.06; }
      .copy { margin: 12px 0 0; color: var(--muted); font-size: 14px; line-height: 1.7; }
      form { margin-top: 22px; }
      label { display: block; margin-top: 14px; font-size: 13px; font-weight: 700; }
      input {
        width: 100%;
        margin-top: 8px;
        border: 1px solid var(--line);
        border-radius: 16px;
        padding: 14px 16px;
        font-size: 16px;
        background: #fffdf9;
        outline: none;
      }
      input:focus { border-color: var(--accent); }
      button {
        width: 100%;
        margin-top: 18px;
        border: 0;
        border-radius: 18px;
        padding: 15px 16px;
        font-size: 16px;
        font-weight: 800;
        background: var(--accent);
        color: #fff9f3;
        cursor: pointer;
      }
      .hint, .error {
        margin-top: 16px;
        border-radius: 16px;
        padding: 12px 14px;
        font-size: 13px;
        line-height: 1.6;
      }
      .hint { background: #fff6ec; border: 1px solid var(--line); color: var(--muted); }
      .error { background: #fff1ef; border: 1px solid #efc6c0; color: var(--error); }
      .next { margin-top: 16px; font-size: 12px; color: var(--muted); word-break: break-all; }
"""


APP_STYLE = """
      :root {
        --bg:
          radial-gradient(circle at top, rgba(34, 197, 94, 0.18), transparent 36%),
          radial-gradient(circle at 85% 18%, rgba(59, 130, 246, 0.2), transparent 32%),
          linear-gradient(180deg, #071018 0%, #09131d 45%, #060b12 100%);
        --panel: rgba(8, 15, 24, 0.84);
        --panel-border: rgba(148, 163, 184, 0.2);
        --text: #e5eef8;
        --muted: rgba(226, 232, 240, 0.72);
        --accent: #38bdf8;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        min-height: 100vh;
        background: var(--bg);
        color: var(--text);
        font-family: "SFMono-Regular", "JetBrains Mono", Consolas, monospace;
        padding: 24px;
      }
      .wrap {
        width: min(1100px, 100%);
        margin: 0 auto;
        background: var(--panel);
        border: 1px solid var(--panel-border);
        border-radius: 24px;
        box-shadow: 0 28px 80px rgba(0, 0, 0, 0.36);
        padding: 24px;
      }
      h1 { margin: 0; font-size: 30px; }
      .sub { margin-top: 10px; color: var(--muted); line-height: 1.7; font-size: 14px; }
      .nav { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 18px; }
      .nav a, .dir-link {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        padding: 10px 14px;
        border-radius: 999px;
        border: 1px solid rgba(56, 189, 248, 0.3);
        color: var(--text);
        text-decoration: none;
        background: rgba(14, 165, 233, 0.08);
      }
      .grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
        gap: 14px;
        margin-top: 24px;
      }
      .card {
        padding: 18px;
        border-radius: 18px;
        background: rgba(15, 23, 42, 0.56);
        border: 1px solid rgba(148, 163, 184, 0.14);
      }
      .card h2 { margin: 0 0 10px; font-size: 14px; }
      .value { font-size: 22px; font-weight: 700; }
      .small { color: var(--muted); font-size: 13px; line-height: 1.7; }
      table { width: 100%; border-collapse: collapse; margin-top: 22px; }
      th, td {
        padding: 12px 10px;
        border-bottom: 1px solid rgba(148, 163, 184, 0.12);
        text-align: left;
        font-size: 13px;
        vertical-align: top;
      }
      th { color: var(--muted); font-weight: 700; }
      pre {
        margin-top: 18px;
        padding: 16px;
        border-radius: 18px;
        overflow: auto;
        background: rgba(2, 6, 23, 0.78);
        border: 1px solid rgba(148, 163, 184, 0.12);
        white-space: pre-wrap;
        word-break: break-word;
      }
"""


def login_page(next_url, error=""):
    error_block = f'<div class="error">{shell_quote(error)}</div>' if error else ""
    return f"""<!DOCTYPE html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
    <title>Codex 登录</title>
    <style>{LOGIN_STYLE}</style>
  </head>
  <body>
    <main class="card">
      <p class="eyebrow">Codex Access</p>
      <h1>网页登录 Codex</h1>
      <p class="copy">为了兼容手机浏览器和微信内置浏览器，这里使用表单登录，不再依赖 Basic Auth。</p>
      <div class="hint">登录成功后会在当前浏览器保存会话，并自动跳回终端页面。</div>
      {error_block}
      <form method="post" action="/codex-login">
        <input type="hidden" name="next" value="{shell_quote(next_url)}" />
        <label for="username">账号</label>
        <input id="username" name="username" autocomplete="username" value="{shell_quote(CODEX_USER)}" />
        <label for="password">密码</label>
        <input id="password" name="password" type="password" autocomplete="current-password" autofocus />
        <button type="submit">登录进入 Codex</button>
      </form>
      <div class="next">登录后跳转到: {shell_quote(next_url)}</div>
    </main>
  </body>
</html>"""


def system_page():
    meminfo = read_meminfo()
    mem_total = mem_used = mem_free = "-"
    if meminfo:
        total, used, free = meminfo
        mem_total, mem_used, mem_free = human_bytes(total), human_bytes(used), human_bytes(free)
    disk = shutil.disk_usage("/")
    sessions = list_codex_sessions()
    services = [
        ("codex-main.service", service_state("codex-main.service")),
        ("codex-web-terminal.service", service_state("codex-web-terminal.service")),
        ("codex-web-helper.service", service_state("codex-web-helper.service")),
        ("nginx.service", service_state("nginx.service")),
    ]
    session_rows = "".join(
        f"<tr><td>{shell_quote(item['session'])}</td><td>{shell_quote(item['title'])}</td></tr>"
        for item in sessions
    )
    service_rows = "".join(
        f"<tr><td>{shell_quote(name)}</td><td>{shell_quote(state)}</td></tr>"
        for name, state in services
    )
    load1, load5, load15 = read_loadavg()
    return f"""<!DOCTYPE html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
    <title>Codex 系统概览</title>
    <style>{APP_STYLE}</style>
  </head>
  <body>
    <main class="wrap">
      <h1>Codex 系统概览</h1>
      <p class="sub">用于快速确认这台服务器上的 Codex 网页终端状态、资源情况和 tmux 会话。</p>
      <div class="nav">
        <a href="/codex/">返回 Codex</a>
        <a href="/codex-files">文件管理</a>
      </div>
      <section class="grid">
        <article class="card"><h2>主机名</h2><div class="value">{shell_quote(socket.gethostname())}</div></article>
        <article class="card"><h2>系统运行时长</h2><div class="value">{shell_quote(read_uptime())}</div></article>
        <article class="card"><h2>Load Average</h2><div class="value">{shell_quote(f"{load1} / {load5} / {load15}")}</div></article>
        <article class="card"><h2>内存使用</h2><div class="value">{shell_quote(mem_used)}</div><div class="small">总计 {shell_quote(mem_total)}，可用 {shell_quote(mem_free)}</div></article>
        <article class="card"><h2>根分区使用</h2><div class="value">{shell_quote(human_bytes(disk.used))}</div><div class="small">总计 {shell_quote(human_bytes(disk.total))}，可用 {shell_quote(human_bytes(disk.free))}</div></article>
        <article class="card"><h2>Codex 会话数</h2><div class="value">{len(sessions)}</div><div class="small">包含主终端和复制标签生成的 tmux 会话</div></article>
      </section>
      <table>
        <thead><tr><th>服务</th><th>状态</th></tr></thead>
        <tbody>{service_rows}</tbody>
      </table>
      <table>
        <thead><tr><th>tmux 会话</th><th>显示名称</th></tr></thead>
        <tbody>{session_rows}</tbody>
      </table>
    </main>
  </body>
</html>"""


def file_page(path_value, error=""):
    current = path_value or "/root"
    current = current if current.startswith("/") else "/root"
    current = os.path.abspath(current)
    links = "".join(
        f'<a class="dir-link" href="/codex-files?path={urllib.parse.quote(item)}">{shell_quote(item)}</a>'
        for item in ["/root", "/www", "/www/wwwroot", "/opt"]
    )
    error_block = f'<pre>{shell_quote(error)}</pre>' if error else ""
    rows = ""
    preview = ""
    if not error and os.path.exists(current):
        if os.path.isdir(current):
            parent = os.path.dirname(current.rstrip("/")) or "/"
            rows += f'<tr><td><a href="/codex-files?path={urllib.parse.quote(parent)}">..</a></td><td>目录</td><td></td></tr>'
            try:
                for name in sorted(os.listdir(current)):
                    full = os.path.join(current, name)
                    encoded = urllib.parse.quote(full)
                    kind = "目录" if os.path.isdir(full) else "文件"
                    size = "" if os.path.isdir(full) else human_bytes(os.path.getsize(full))
                    rows += f'<tr><td><a href="/codex-files?path={encoded}">{shell_quote(name)}</a></td><td>{kind}</td><td>{shell_quote(size)}</td></tr>'
            except Exception as exc:
                error_block = f"<pre>{shell_quote(str(exc))}</pre>"
        else:
            size = os.path.getsize(current)
            rows = f'<tr><td>{shell_quote(os.path.basename(current))}</td><td>文件</td><td>{shell_quote(human_bytes(size))}</td></tr>'
            try:
                if size <= 200 * 1024:
                    with open(current, "r", encoding="utf-8", errors="ignore") as fh:
                        preview = f"<pre>{shell_quote(fh.read())}</pre>"
                else:
                    preview = "<pre>文件过大，未直接预览。</pre>"
            except Exception as exc:
                preview = f"<pre>{shell_quote(str(exc))}</pre>"
    return f"""<!DOCTYPE html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
    <title>Codex 文件管理</title>
    <style>{APP_STYLE}</style>
  </head>
  <body>
    <main class="wrap">
      <h1>Codex 文件管理</h1>
      <p class="sub">轻量查看 `/root`、`/www`、`/opt` 下的部署文件和日志，方便远程排障。</p>
      <div class="nav">
        <a href="/codex/">返回 Codex</a>
        <a href="/codex-system">系统概览</a>
      </div>
      <div class="nav">{links}</div>
      <div class="small" style="margin-top:18px;">当前路径: {shell_quote(current)}</div>
      {error_block}
      <table>
        <thead><tr><th>名称</th><th>类型</th><th>大小</th></tr></thead>
        <tbody>{rows}</tbody>
      </table>
      {preview}
    </main>
  </body>
</html>"""


class Handler(BaseHTTPRequestHandler):
    server_version = "CodexWebHelper/2.0"

    def log_message(self, format_, *args):
        return

    def send_html(self, body, status=HTTPStatus.OK, extra_headers=None):
        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        if extra_headers:
            for key, value in extra_headers:
                self.send_header(key, value)
        self.end_headers()
        self.wfile.write(encoded)

    def send_json(self, payload, status=HTTPStatus.OK):
        encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def redirect(self, location, extra_headers=None):
        self.send_response(HTTPStatus.FOUND)
        self.send_header("Location", location)
        if extra_headers:
            for key, value in extra_headers:
                self.send_header(key, value)
        self.end_headers()

    def read_form(self):
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(length).decode("utf-8", "ignore")
        parsed = urllib.parse.parse_qs(raw, keep_blank_values=True)
        return {key: values[-1] if values else "" for key, values in parsed.items()}

    def is_authenticated(self):
        return bool(extract_session(self))

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)

        if path == "/health":
            self.send_json({"ok": True})
            return

        if path == "/auth/check":
            if self.is_authenticated():
                self.send_response(HTTPStatus.NO_CONTENT)
                self.end_headers()
            else:
                self.send_response(HTTPStatus.UNAUTHORIZED)
                self.end_headers()
            return

        if path == "/codex-login":
            next_url = safe_next((query.get("next") or ["/codex/"])[-1])
            if self.is_authenticated():
                self.redirect(next_url)
                return
            self.send_html(login_page(next_url))
            return

        if path == "/api/v1/codex/sessions":
            if not self.is_authenticated():
                self.send_response(HTTPStatus.UNAUTHORIZED)
                self.end_headers()
                return
            self.send_json(list_codex_sessions())
            return

        if path == "/codex-system":
            if not self.is_authenticated():
                self.send_response(HTTPStatus.UNAUTHORIZED)
                self.end_headers()
                return
            self.send_html(system_page())
            return

        if path == "/codex-files":
            if not self.is_authenticated():
                self.send_response(HTTPStatus.UNAUTHORIZED)
                self.end_headers()
                return
            current = (query.get("path") or ["/root"])[-1]
            error = ""
            if not os.path.exists(current):
                error = f"路径不存在: {current}"
            self.send_html(file_page(current, error))
            return

        self.send_response(HTTPStatus.NOT_FOUND)
        self.end_headers()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/codex-login":
            self.send_response(HTTPStatus.NOT_FOUND)
            self.end_headers()
            return

        form = self.read_form()
        username = form.get("username", "")
        password = form.get("password", "")
        next_url = safe_next(form.get("next", "/codex/"))

        if username != CODEX_USER or password != CODEX_PASSWORD or not CODEX_PASSWORD or not SESSION_SECRET:
            self.send_html(login_page(next_url, "账号或密码错误"), status=HTTPStatus.UNAUTHORIZED)
            return

        cookie_value = make_session_value(username)
        headers = [
            ("Set-Cookie", f"{COOKIE_NAME}={cookie_value}; Path=/; Max-Age={SESSION_TTL}; HttpOnly; SameSite=Lax"),
        ]
        self.redirect(next_url, extra_headers=headers)


def main():
    if not CODEX_PASSWORD or not SESSION_SECRET:
        raise SystemExit("CODEX_PASSWORD or CODEX_SESSION_SECRET is missing")

    class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
        daemon_threads = True

    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
EOF
  chmod 0755 "$HELPER_BIN_PATH"
}

write_main_service() {
  cat >"$MAIN_SERVICE_FILE" <<EOF
[Unit]
Description=Persistent Codex tmux session
After=network.target

[Service]
Type=oneshot
User=root
WorkingDirectory=$WORKDIR
Environment=HOME=$WORKDIR
Environment=TERM=xterm-256color
ExecStart=$MAIN_BOOTSTRAP_PATH codex-main
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
}

write_helper_service() {
  cat >"$HELPER_SERVICE_FILE" <<EOF
[Unit]
Description=Codex Web Helper
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WORKDIR
EnvironmentFile=$HELPER_ENV_FILE
ExecStart=$HELPER_BIN_PATH
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
}

write_terminal_service() {
  cat >"$TERMINAL_SERVICE_FILE" <<EOF
[Unit]
Description=Codex Web Terminal
After=network.target ${MAIN_SERVICE_NAME}.service
Requires=${MAIN_SERVICE_NAME}.service

[Service]
Type=simple
User=root
WorkingDirectory=$WORKDIR
Environment=HOME=$WORKDIR
Environment=TERM=xterm-256color
ExecStart=$TERMINAL_WRAPPER_PATH
Restart=always
RestartSec=3
KillMode=process
TimeoutStopSec=5

[Install]
WantedBy=multi-user.target
EOF
}

write_nginx_config() {
  mkdir -p "$(dirname "$NGINX_SITE_FILE")"
  cat >"$NGINX_SITE_FILE" <<EOF
server {
    listen 80;
    server_name $SERVER_NAME;

    location = /_codex_auth {
        internal;
        proxy_pass http://127.0.0.1:$HELPER_PORT/auth/check;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
    }

    location = /codex-login {
        proxy_pass http://127.0.0.1:$HELPER_PORT/codex-login;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ^~ /api/v1/codex/ {
        auth_request /_codex_auth;
        error_page 401 =302 /codex-login?next=\$request_uri;
        proxy_pass http://127.0.0.1:$HELPER_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location = /codex-system {
        auth_request /_codex_auth;
        error_page 401 =302 /codex-login?next=\$request_uri;
        proxy_pass http://127.0.0.1:$HELPER_PORT/codex-system;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location = /codex-files {
        auth_request /_codex_auth;
        error_page 401 =302 /codex-login?next=\$request_uri;
        proxy_pass http://127.0.0.1:$HELPER_PORT/codex-files;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location = /codex {
        return 302 /codex/;
    }

    location = /codex-terminal {
        return 302 /codex-terminal/;
    }

    location ^~ /codex-terminal/ {
        auth_request /_codex_auth;
        error_page 401 =302 /codex-login?next=\$request_uri;
        proxy_pass http://127.0.0.1:$TERMINAL_PORT;
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

    location = /codex/ {
        auth_request /_codex_auth;
        error_page 401 =302 /codex-login?next=\$request_uri;
        root $UI_DIR;
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0" always;
        try_files /index.html =404;
    }
}
EOF
}

cleanup_legacy_services() {
  for unit in codex-gotty.service codex-ws-bridge.service; do
    if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
      systemctl disable --now "$unit" >/dev/null 2>&1 || true
    fi
  done
}

reload_services() {
  systemctl daemon-reload
  systemctl enable --now "${MAIN_SERVICE_NAME}.service"
  systemctl enable --now "${HELPER_SERVICE_NAME}.service"
  systemctl enable --now "${SERVICE_NAME}.service"
  systemctl enable nginx >/dev/null 2>&1 || true
  nginx -t
  systemctl restart nginx
}

warm_primary_session() {
  if /usr/bin/tmux has-session -t codex-main 2>/dev/null; then
    return
  fi

  if [[ -n "$CODEX_MAIN_RESUME_ID" ]]; then
    /usr/bin/tmux new-session -d -s codex-main -c /root "bash -lc 'exec codex resume $CODEX_MAIN_RESUME_ID'"
    return
  fi

  /usr/bin/tmux new-session -d -s codex-main -c /root "bash -lc 'exec codex'"
}

print_summary() {
  local host_display
  host_display="$SERVER_NAME"
  if [[ "$host_display" == "_" ]]; then
    host_display="$(hostname -I | awk '{print $1}')"
  fi

  cat <<EOF

installed:
- ui: $UI_DIR
- config: $CONFIG_FILE
- helper env: $HELPER_ENV_FILE
- helper bin: $HELPER_BIN_PATH
- terminal bin: $TERMINAL_WRAPPER_PATH
- nginx: $NGINX_SITE_FILE

services:
- ${MAIN_SERVICE_NAME}.service
- ${HELPER_SERVICE_NAME}.service
- ${SERVICE_NAME}.service

access:
- http://$host_display/codex/
- login: http://$host_display/codex-login

auth:
- username: $WEB_USER
- password: $WEB_PASSWORD

checks:
- systemctl status ${MAIN_SERVICE_NAME}.service --no-pager
- systemctl status ${HELPER_SERVICE_NAME}.service --no-pager
- systemctl status ${SERVICE_NAME}.service --no-pager

notes:
- 主 tmux 会话固定为 codex-main
- 如果设置 CODEX_MAIN_RESUME_ID，主标签会固定恢复到指定对话
- 额外标签页继续创建独立的 codex-tab-* tmux 会话
EOF
}

main() {
  require_root
  ensure_dependencies
  ensure_codex
  generate_secrets
  copy_ui
  write_codex_config
  write_main_bootstrap
  write_shell_wrapper
  write_terminal_wrapper
  write_helper_env
  write_helper
  write_main_service
  write_helper_service
  write_terminal_service
  write_nginx_config
  cleanup_legacy_services
  reload_services
  warm_primary_session
  print_summary
}

main "$@"
