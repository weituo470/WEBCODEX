#!/usr/bin/env bash
set -euo pipefail

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

archive_url="https://github.com/weituo470/WEBCODEX/archive/refs/heads/main.tar.gz"
curl -fsSL "$archive_url" -o "$tmpdir/webcodex.tgz"
tar -xzf "$tmpdir/webcodex.tgz" -C "$tmpdir"

src_dir="$(find "$tmpdir" -maxdepth 1 -type d -name 'WEBCODEX-*' | head -n 1)"
if [[ -z "$src_dir" ]]; then
  echo "failed to unpack WEBCODEX source"
  exit 1
fi

chmod +x "$src_dir/install.sh"
exec "$src_dir/install.sh"
