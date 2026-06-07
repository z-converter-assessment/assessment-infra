#!/usr/bin/env bash
# compose 서비스 헬스체크
# 사용법: ./healthcheck.sh [--host <ip>] [--port <port>]

set -euo pipefail

HOST="${HEALTH_HOST:-localhost}"
PORT="${HEALTH_PORT:-8000}"
RETRIES=12
INTERVAL=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "==> compose 서비스 상태 확인"
docker compose -f "$(dirname "$0")/../compose/docker-compose.yml" ps

echo "==> API 헬스체크 (http://${HOST}:${PORT}/health)"
for i in $(seq 1 $RETRIES); do
  if curl -sf "http://${HOST}:${PORT}/health" > /dev/null; then
    echo "OK  /health 응답 확인 (시도 ${i}/${RETRIES})"
    exit 0
  fi
  echo "  대기 중... (${i}/${RETRIES})"
  sleep $INTERVAL
done

echo "ERROR: ${RETRIES}회 시도 후 /health 응답 없음"
docker compose -f "$(dirname "$0")/../compose/docker-compose.yml" logs --tail=50
exit 1
