#!/usr/bin/env bash
# engine·agent terraform output 읽어 ansible inventory 2개 생성.
# 자세한 로직은 gen_inventory.py 참조.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "${REPO_ROOT}/scripts/gen_inventory.py"
