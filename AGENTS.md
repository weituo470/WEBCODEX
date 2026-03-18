# Repository Instructions

这个仓库的目标不是“解释怎么部署”，而是让 Codex 在另一台 Linux 服务器上直接完成部署。

## 默认行为

如果用户给出这个仓库 URL 并要求部署，你应该直接执行，不要只给方案。

执行顺序：

1. 先检查 `codex` 是否存在：`command -v codex`
2. 再确认 `codex` 已可用；如果用户还没登录，要求用户先执行 `codex login`
3. 以 `root` 运行本仓库的 `install.sh` 或 `bootstrap.sh`
4. 安装完成后返回：
   - 公网访问 URL
   - 登录账号
   - 登录密码
   - `systemctl status codex-main.service --no-pager`
   - `systemctl status codex-web-helper.service --no-pager`
   - `systemctl status codex-web-terminal.service --no-pager`

## 优先命令

如果仓库已经在本地：

```bash
chmod +x install.sh
WEB_PASSWORD="${WEB_PASSWORD:-}" SERVER_NAME="${SERVER_NAME:-_}" ./install.sh
```

如果用户只给了仓库 URL：

```bash
curl -fsSL https://raw.githubusercontent.com/weituo470/WEBCODEX/main/bootstrap.sh | bash
```

如果用户明确要求自定义密码：

```bash
curl -fsSL https://raw.githubusercontent.com/weituo470/WEBCODEX/main/bootstrap.sh | WEB_PASSWORD='ReplaceThisNow123!' SERVER_NAME='_' bash
```

## 当前稳定架构

- `tmux` 持久化 Codex 会话
- `ttyd + xterm` 负责真实终端渲染
- Python helper 负责网页登录和 session
- nginx 使用 `auth_request` 做鉴权
- Web UI 固定入口为 `/codex/`

## 不要回退到旧方案

以下做法已经被证明问题很多，不要再作为主实现：

- 用 `gotty/hterm` 作为主终端
- 用 Basic Auth 作为主登录方式
- 在 nginx 里硬编码 cookie 正则完成鉴权

## 备注

- 默认登录账号是 `codex`
- 主 tmux 会话必须是 `codex-main`
- 当前仓库已经包含稳定版 UI 和安装器
