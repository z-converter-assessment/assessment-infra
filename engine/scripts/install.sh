#!/usr/bin/env bash
# 현장 appliance 오프라인 설치 스크립트
# 사용법: ./install.sh [--vault-pass <path>]
# 전제: 번들 디렉토리 내에서 실행 (docker, ansible 사전 설치 필요)

set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VAULT_PASS_FILE="${VAULT_PASS_FILE:-~/.vault-pass}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault-pass) VAULT_PASS_FILE="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "==> SHA256SUMS 검증"
(cd "${BUNDLE_DIR}" && sha256sum -c SHA256SUMS --quiet)

echo "==> .env 파일 확인"
if [[ ! -f "${BUNDLE_DIR}/compose/.env" ]]; then
  echo "ERROR: compose/.env 없음 — .env.example 참고하여 작성 후 재실행"
  echo "       cp ${BUNDLE_DIR}/compose/.env.example ${BUNDLE_DIR}/compose/.env"
  echo "       vi ${BUNDLE_DIR}/compose/.env"
  exit 1
fi

echo "==> docker 이미지 로드"
for tar in "${BUNDLE_DIR}/images/"*.tar.gz; do
  echo "  load: $(basename "$tar")"
  docker load < "$tar"
done

echo "==> ansible-playbook 실행 (local connection)"
cd "${BUNDLE_DIR}/ansible"
ansible-playbook -i inventory.localhost.yml playbook-field.yml \
  --vault-password-file "${VAULT_PASS_FILE}" \
  -e "compose_mount_cinder=false"

echo "==> 헬스체크"
bash "${BUNDLE_DIR}/scripts/healthcheck.sh"

echo "==> 설치 완료"
