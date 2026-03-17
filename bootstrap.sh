#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/weituo470/WEBCODEX.git}"
TARGET_DIR="${TARGET_DIR:-/opt/WEBCODEX}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "please run as root"
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y git
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y git
  elif command -v yum >/dev/null 2>&1; then
    yum install -y git
  else
    echo "git is required"
    exit 1
  fi
fi

rm -rf "$TARGET_DIR"
git clone "$REPO_URL" "$TARGET_DIR"
cd "$TARGET_DIR"
chmod +x install.sh
./install.sh
