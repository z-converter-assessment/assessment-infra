#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

terraform -chdir="${REPO_ROOT}/terraform" output -json \
  | python3 "${REPO_ROOT}/scripts/gen_inventory.py" \
  > "${REPO_ROOT}/ansible/inventory.yml"

echo "ansible/inventory.yml 생성 완료."
