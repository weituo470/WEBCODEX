# WEBCODEX

把 Codex 稳定地暴露成网页终端的一套可复用部署基线。

这次仓库已经从早期 `gotty` 方案切到最终稳定版架构：

- `tmux` 负责持久会话，主会话固定为 `codex-main`
- `ttyd + xterm` 负责真实终端渲染，解决中文输入问题
- 自定义登录 helper 负责表单登录、会话 cookie、会话列表、系统页、文件页
- 外层是多标签 Web UI，支持复制标签、重命名、移动端适配
- `nginx auth_request` 负责统一鉴权，不再在配置里硬编码 cookie 正则

## 最终稳定架构

- 公开入口: `/codex/`
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

## 安装器做的事

- 安装依赖: `tmux`、`nginx`、`curl`、`openssl`、`tar`、`python3`、`ttyd`
- 写入 `codex-main-bootstrap`、`codex-web-shell`、`codex-web-terminal`
- 写入 `codex-web-helper` 和会话环境文件
- 写入 `codex-main.service`、`codex-web-helper.service`、`codex-web-terminal.service`
- 写入 nginx 站点配置
- 部署当前稳定版多标签 UI
- 自动停掉旧的 `codex-gotty.service`、`codex-ws-bridge.service`

## 关键设计

- 不再使用 Basic Auth 作为主登录方案
- 不再依赖 `gotty/hterm` 作为主终端渲染
- 不再通过 nginx 解析 cookie 正则做登录判断
- 会话恢复和多标签切换都围绕 `tmux` 会话名实现

## 环境变量

```bash
WEB_USER='codex'
WEB_PASSWORD='YourPassword'
SERVER_NAME='_'
WORKDIR='/root'
TERMINAL_PORT='8765'
HELPER_PORT='8780'
UI_DIR='/opt/codex-web-ui'
CODEX_MAIN_RESUME_ID='019cdbeb-e315-7ad0-8af6-a871ac6eeb26'
```

## 排障和复盘

这次真实修复过程、踩坑点和为什么这样改，见：

- [DEPLOYMENT_NOTES.md](DEPLOYMENT_NOTES.md)

## 备注

- 本仓库假设 `codex` 已经可执行且完成登录
- 当前 UI 默认路径固定为 `/codex/`
- 主 tmux 会话固定为 `codex-main`
