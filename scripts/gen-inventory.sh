#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

terraform -chdir="${REPO_ROOT}/engine/terraform" output -json \
  | python3 "${REPO_ROOT}/scripts/gen_inventory.py" \
  > "${REPO_ROOT}/engine/ansible/inventory.yml"

echo "engine/ansible/inventory.yml 생성 완료."
