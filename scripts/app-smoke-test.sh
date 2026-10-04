#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
scripts/package-app.sh >/dev/null
"$ROOT_DIR/dist/Vaulty.app/Contents/MacOS/Vaulty" --self-test
python3 scripts/check-app-contracts.py
printf 'PASS: packaged Vaulty interaction tests and modular source wiring contracts\n'
