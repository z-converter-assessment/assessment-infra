#!/usr/bin/env bash
# 현장 appliance 배포 번들 빌드
# 사용법: build-bundle.sh <engine_version>
# 출력: /tmp/bundle-<engine_version>.tar.gz

set -euo pipefail

ENGINE_VERSION="${1:?engine_version 인수 필요}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RELEASE_URL="https://github.com/z-converter-assessment/assessment-engine/releases/download/${ENGINE_VERSION}"
BUNDLE_DIR="/tmp/bundle-${ENGINE_VERSION}"
BUNDLE_OUT="/tmp/bundle-${ENGINE_VERSION}.tar.gz"

echo "==> 번들 빌드 시작: engine_version=${ENGINE_VERSION}"
rm -rf "${BUNDLE_DIR}"
mkdir -p "${BUNDLE_DIR}/images" "${BUNDLE_DIR}/compose" "${BUNDLE_DIR}/ansible" "${BUNDLE_DIR}/scripts"

# ── release artifact 다운로드 ──────────────────────────────────────
echo "==> docker-compose.yml 다운로드"
curl -fsSL "${RELEASE_URL}/docker-compose.yml" -o "${BUNDLE_DIR}/compose/docker-compose.yml"

echo "==> .env.example 다운로드"
curl -fsSL "${RELEASE_URL}/.env.example" -o "${BUNDLE_DIR}/compose/.env.example"

# ── docker 이미지 저장 ─────────────────────────────────────────────
echo "==> docker 이미지 pull 및 save"
echo "${GITHUB_TOKEN:-}" | docker login ghcr.io -u x-access-token --password-stdin 2>/dev/null || true

# docker-compose.yml에서 이미지 목록 추출 후 save
IMAGES=$(docker compose -f "${BUNDLE_DIR}/compose/docker-compose.yml" config --images 2>/dev/null || true)
for img in $IMAGES; do
  safe_name=$(echo "$img" | tr '/:' '__')
  echo "  save: ${img}"
  docker pull "$img"
  docker save "$img" | gzip > "${BUNDLE_DIR}/images/${safe_name}.tar.gz"
done

# ── ansible artifacts 복사 ─────────────────────────────────────────
echo "==> ansible artifact 복사"
cp "${REPO_ROOT}/engine/ansible/playbook-field.yml" "${BUNDLE_DIR}/ansible/"
cp "${REPO_ROOT}/engine/ansible/inventory.localhost.yml" "${BUNDLE_DIR}/ansible/"
cp -r "${REPO_ROOT}/engine/ansible/roles/engine_compose" "${BUNDLE_DIR}/ansible/roles/"
cp -r "${REPO_ROOT}/engine/ansible/group_vars" "${BUNDLE_DIR}/ansible/"

# ── 스크립트 복사 ──────────────────────────────────────────────────
cp "${REPO_ROOT}/engine/scripts/install.sh" "${BUNDLE_DIR}/scripts/"
cp "${REPO_ROOT}/engine/scripts/healthcheck.sh" "${BUNDLE_DIR}/scripts/"
chmod +x "${BUNDLE_DIR}/scripts/"*.sh

# ── manifest + SHA256SUMS ──────────────────────────────────────────
echo "==> manifest 생성"
INFRA_SHA=$(git -C "${REPO_ROOT}" rev-parse HEAD)
cat > "${BUNDLE_DIR}/manifest.json" <<EOF
{
  "engine_version": "${ENGINE_VERSION}",
  "infra_commit": "${INFRA_SHA}",
  "build_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "==> SHA256SUMS 생성"
(cd "${BUNDLE_DIR}" && find . -type f | sort | xargs sha256sum > SHA256SUMS)

# ── 번들 압축 ──────────────────────────────────────────────────────
echo "==> 번들 압축: ${BUNDLE_OUT}"
tar czf "${BUNDLE_OUT}" -C /tmp "bundle-${ENGINE_VERSION}"

echo "==> 완료: ${BUNDLE_OUT}"
ls -lh "${BUNDLE_OUT}"
