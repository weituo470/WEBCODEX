# Repository Instructions

This repository is intended to be handed to Codex on a target Linux server so Codex can deploy a web-accessible Codex terminal with minimal user interaction.

## Default behavior

If the user provides this repository URL and asks you to deploy it, do not stop at explanation. Execute the deployment.

Use this flow:

1. Confirm `codex` is installed by running `command -v codex`.
2. Confirm Codex authentication is available. If login is missing or invalid, stop and tell the user to run `codex login` first.
3. Run the installer from this repository as root.
4. If the user did not provide a password, choose a strong random password and report it back.
5. After installation, report:
   - the public URL
   - the username
   - the password
   - `systemctl status codex-web-terminal --no-pager`
   - whether nginx is active

## Preferred command

If the repository has already been cloned locally, run:

```bash
chmod +x install.sh
WEB_PASSWORD="${WEB_PASSWORD:-}" SERVER_NAME="${SERVER_NAME:-_}" ./install.sh
```

If the user only provided the repository URL, the simplest install path is:

```bash
curl -fsSL https://raw.githubusercontent.com/weituo470/WEBCODEX/main/bootstrap.sh | bash
```

If a password is required explicitly:

```bash
curl -fsSL https://raw.githubusercontent.com/weituo470/WEBCODEX/main/bootstrap.sh | WEB_PASSWORD='ReplaceMeNow123!' SERVER_NAME='_' bash
```

## Notes

- This project assumes `codex` itself is already installed.
- The installer handles `tmux`, `nginx`, `curl`, `openssl`, `tar`, and `gotty`.
- The default web path is `/codex/`.
- The default username is `codex`.
- The main persistent tmux session is `codex-main`.
