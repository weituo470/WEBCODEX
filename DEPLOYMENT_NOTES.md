# WEBCODEX 修复复盘

这份文档记录这次把网页 Codex 从“不稳定可见”修到“可以长期使用”的过程，目的是下一台服务器不要再走同样的弯路。

## 1. 最早的问题

第一版仓库走的是 `gotty + hterm + Basic Auth` 思路，能很快看到页面，但真实使用中连续暴露了几个关键问题：

1. 页面经常黑屏，或者只有异常小块区域。
2. `gotty.js` WebSocket 握手不稳定，浏览器报 `ws://.../codex/ws failed`。
3. 移动端和微信浏览器对 Basic Auth 支持不稳定。
4. 即使页面能打开，中文输入体验很差。
5. 聊天记录区域一度只能显示一行。
6. 前端控制台计数持续暴涨，说明页面内部存在循环事件。

## 2. 中间阶段做过什么

中间阶段为了让旧版 `gotty` 能继续跑，做过两类补丁：

1. 增加 WebSocket bridge，兼容 `Sec-WebSocket-Protocol: gotty`。
2. 增加 `/codex/token`、`/codex/auth_token.js` 等兼容层。

这一步可以把“完全不能用”拉回到“勉强能打开”，但它没有从根上解决中文输入和浏览器兼容问题，只是给旧架构打补丁。

## 3. 最终确认的稳定方案

最后稳定下来的架构是：

1. `tmux` 负责持久会话和多标签会话。
2. `ttyd + xterm` 负责真实终端渲染。
3. 自定义 Python helper 负责网页登录、session cookie、会话列表、系统页、文件页。
4. 外层保留自定义多标签 UI。
5. `nginx auth_request` 统一做登录校验。

关键原因：

1. `ttyd/xterm` 对中文输入法明显比 `gotty/hterm` 更稳定。
2. 表单登录比 Basic Auth 更适合手机浏览器。
3. `auth_request` 比 nginx 里手写 cookie 正则更稳、更容易迁移。

## 4. 这次真正修掉的关键 Bug

### 4.1 黑屏和 WebSocket 异常

根因不是单一问题，而是旧的 `gotty` 链路太脆：

1. 自定义 UI、代理、WebSocket 子协议、token 端点都要互相对齐。
2. 任意一层路径或 header 不一致，就会出现黑屏或无法连接。

最终处理：

1. 主终端切换到 `/codex-terminal/` 下的 `ttyd`。
2. 外层 UI 只做 iframe 容器，不再自己模拟终端协议。

### 4.2 中文输入不稳定

根因：

1. `gotty/hterm` 在中文 IME 场景下表现不可靠。

最终处理：

1. 放弃让 `gotty` 继续承担主终端。
2. 终端实际渲染改为 `ttyd/xterm`。

### 4.3 聊天记录只显示一行

根因：

1. 前端终端容器使用了子元素 `height: 100%`。
2. 但父容器不是显式高度，导致 iframe 实际可用高度几乎为 0。

最终处理：

1. 终端外壳改成标准 flex 高度传递。
2. `.terminal-wrap` 改为 `display: flex`。
3. `.terminal-stack` 改为 `flex: 1 1 auto; min-height: 0;`。

### 4.4 控制台计数狂涨

根因：

前端里存在这条循环：

`updateViewportHeight -> dispatchResize -> window.resize -> loadLayout -> applyLayout -> dispatchResize`

这会导致页面一直自己给自己触发 resize，浏览器控制台数字持续增加，同时白白消耗浏览器和服务端资源。

最终处理：

1. 删除对当前页面的 `window.dispatchEvent(new Event("resize"))`。
2. 改成只通知内嵌终端 iframe 自己重算尺寸。
3. 调试日志默认关闭，只在 `?debug=1` 或本地显式开启时输出。

## 5. 为什么仓库也必须一起改

如果只改线上机器，不改仓库，下次部署时 Codex 还是会执行旧的 `gotty` 安装器，再次踩回：

1. Basic Auth 不稳定。
2. gotty WebSocket 兼容层复杂。
3. 中文输入问题重现。
4. UI 高度和 resize 循环问题可能再次出现。

所以仓库本身必须直接表达最终稳定架构，而不是继续保留旧方案。

## 6. 仓库现在应该具备的能力

下一台服务器的理想部署结果应该是：

1. 安装依赖后直接起 `tmux + ttyd + helper + nginx`。
2. 公开地址固定为 `/codex/`。
3. 登录页固定为 `/codex-login`。
4. 主会话自动存在，名称为 `codex-main`。
5. 手机浏览器和桌面浏览器都能正常登录。
6. 中文输入正常。
7. 聊天历史区域可正常撑满，不再是一行。
8. 前端不会再出现 resize 自激循环。

## 7. 给下一次部署的建议

1. 不要再把 `gotty` 作为主终端方案。
2. 不要再把 Basic Auth 当成移动端主登录方式。
3. 不要在 nginx 里硬编码复杂 cookie 正则做权限判断。
4. 如果遇到黑屏，先检查真正的终端路径是否是 `/codex-terminal/`。
5. 如果页面异常刷日志，第一时间检查有没有事件循环，而不是先怀疑服务器性能。
