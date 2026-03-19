# WEBCODEX

把 Codex 稳定地暴露成网页终端的一套可复用部署基线。

当前仓库采用稳定版架构：

- `tmux` 负责持久会话，主会话固定为 `codex-main`
- `ttyd + xterm` 负责真实终端渲染，解决中文输入问题
- 自定义 helper 负责网页登录、cookie 会话、会话列表、系统页、文件页
- 外层是多标签 Web UI，支持复制标签、重命名、移动端适配
- `nginx auth_request` 负责统一鉴权
- 可通过 `CODEX_MAIN_RESUME_ID` 把默认主标签固定到指定 `codex resume <conversation_id>`

## 公开入口

- 主入口: `/codex/`
- 登录页: `/codex-login`
- 内嵌终端: `/codex-terminal/`
- 会话接口: `/api/v1/codex/sessions`
- 辅助页面: `/codex-system`、`/codex-files`

## 一键安装

前提：

- 目标机器已安装并登录 `codex`
- 以 `root` 执行

```bash
curl -fsSL https://raw.githubusercontent.com/weituo470/WEBCODEX/main/bootstrap.sh | \
WEB_PASSWORD='ReplaceThisNow123!' \
SERVER_NAME='_' \
bash
```

如果要把默认主标签固定到某个指定对话：

```bash
curl -fsSL https://raw.githubusercontent.com/weituo470/WEBCODEX/main/bootstrap.sh | \
WEB_PASSWORD='ReplaceThisNow123!' \
SERVER_NAME='_' \
CODEX_MAIN_RESUME_ID='019cef2a-d869-7e40-b268-22c4bafcb3f9' \
bash
```

安装完成后访问：

```text
http://YOUR_HOST/codex/
```

默认账号：

```text
codex
```

## 本地源码安装

```bash
git clone https://github.com/weituo470/WEBCODEX.git
cd WEBCODEX
chmod +x install.sh
WEB_PASSWORD='ReplaceThisNow123!' SERVER_NAME='_' ./install.sh
```

如果要固定主对话：

```bash
WEB_PASSWORD='ReplaceThisNow123!' \
SERVER_NAME='_' \
CODEX_MAIN_RESUME_ID='019cef2a-d869-7e40-b268-22c4bafcb3f9' \
./install.sh
```

## 安装器做的事

- 安装依赖: `tmux`、`nginx`、`curl`、`openssl`、`tar`、`python3`、`ttyd`
- 写入 `codex-main-bootstrap`、`codex-web-shell`、`codex-web-terminal`
- 写入 `codex-web-helper`、helper 环境文件、主会话配置文件
- 写入 `codex-main.service`、`codex-web-helper.service`、`codex-web-terminal.service`
- 写入 nginx 站点配置
- 部署当前稳定版多标签 UI
- 自动停掉旧的 `codex-gotty.service`、`codex-ws-bridge.service`

## 环境变量

```bash
WEB_USER='codex'
WEB_PASSWORD='YourPassword'
SERVER_NAME='_'
WORKDIR='/root'
TERMINAL_PORT='8765'
HELPER_PORT='8780'
UI_DIR='/opt/codex-web-ui'
CODEX_MAIN_RESUME_ID='019cef2a-d869-7e40-b268-22c4bafcb3f9'
```

## 关键设计

- 不再使用 Basic Auth 作为主登录方案
- 不再依赖 `gotty/hterm` 作为主终端渲染
- 不再通过 nginx 解析 cookie 正则做登录判断
- 会话恢复和多标签切换都围绕 `tmux` 会话名实现
- 如果设置 `CODEX_MAIN_RESUME_ID`，主标签在首次启动和异常退出后重启时都会恢复到该对话

## 备注

- 本仓库假设 `codex` 已经可执行且完成登录
- 当前 UI 默认路径固定为 `/codex/`
- 主 tmux 会话固定为 `codex-main`
