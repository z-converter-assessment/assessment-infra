# 환경변수 inject 감사 (env-audit)

assessment-engine·assessment-agent 두 repo의 contract 대비 본 infra의 환경변수 주입 누락·오류 카탈로그. 수정 완료 시 본 문서는 archive(또는 항목별 ✅ 마킹) 한다.

## 평가 기준

| 출처 | 위치 | 비고 |
|---|---|---|
| engine 측 expected env | `~/PycharmProjects/assessment-engine/docs/operations/env.md` | §12 전체 키 카탈로그, §9 컴포넌트별 read 매트릭스 |
| agent 측 expected env | `~/PycharmProjects/assessment-agent/.env.example`, `.claude/CLAUDE.md` §Configuration | broker·worker·TLS 키 군 |
| 본 infra 측 inject | `engine/ansible/playbook-{api,consumer,ai}.yml` `app_env` dict + `engine/ansible/roles/app/templates/app.env.j2` + `agent/ansible/roles/agent_env/templates/agent.env.{j2,local.j2}` | 환경변수 카탈로그는 `env-engine.md` / `env-agent.md` |

평가 시점: 2026-06-02.

---

## 🔴 Critical — 현재 배포 시 기능 자체가 실패

| # | 문제 | 영향 | 위치 |
|:--:|---|---|---|
| 1 | `OLLAMA_HOST` + `OLLAMA_PORT` 분리 주입 — engine은 `OLLAMA_BASE_URL` 단일 키 요구 | AI VM diagnostic 전부 동작 불가 — LLM·embedding 호출 실패 | `playbook-ai.yml` line 24-25, `engine/ansible/roles/app/templates/app.env.j2` line 21-25 |
| 2 | agent에 `WORKER_DOWNLOAD_ALLOWED_HOSTS` 미주입 | 미설정 = **모든 host blocked = worker 완전 비활성** → `task.install` 처리 안 됨 | `agent/ansible/roles/agent_env/templates/agent.env.j2` |
| 3 ✅ | ~~agent에 `RABBITMQ_WORKER_USER` / `RABBITMQ_WORKER_PASS` 미주입~~ | 해소 — `agent.env.local.j2`에 추가 (ADR-0009, publisher 자격 재사용) | — |
| 4 | `WORKER_TASK_EXCHANGE` / `WORKER_TASK_RESULT_KEY` / `WORKER_TASK_QUEUE_PREFIX` 양쪽 미주입 | engine consumer ↔ agent worker 간 routing 계약 불일치 시 결과 보고 유실 | engine playbook 3종 + `agent.env.j2` |

---

## 🟡 High — prod 검증·보안 정책 어긋남

| # | 문제 | 영향 |
|:--:|---|---|
| 5 | `APP_ENV` 전혀 미주입 | 모든 engine 컴포넌트가 `dev` 기본값으로 동작 → `_WEAK_VALUES` 검증 안 돎. `vault_db_password=assessment` 같은 dev default가 prod로 흘러도 startup 차단 없음 |
| 6 | `LOG_FORMAT` 미주입 | `text` 기본값. prod 권장 `json` 미적용 → log aggregator indexing 불리 |
| 7 | vhost 값 검증 필요 — engine docs default는 `/assessment`(leading slash 포함), 본 infra는 `assessment` | RabbitMQ에서 `/assessment`와 `assessment`는 다른 vhost. engine·agent·MQ role 모두 `assessment`로 통일돼 작동은 함 — 다만 engine docs의 prod recommendation과 미일치 |

---

## 🟠 Medium — engine code default 의존 (값은 동작하나 외부 contract로 명시 안 됨)

| # | 위치 | 미주입 키 |
|:--:|---|---|
| 8 | API VM | `ZDM_PACKAGE_PATH`, `ZDM_PACKAGE_SCRIPT`, `ZDM_META_CONNECT_TIMEOUT_SEC`, `ZDM_META_TOTAL_TIMEOUT_SEC`, `REDIS_TTL_ZDM_PACKAGE_SHA256` |
| 9 | API VM | `WEB_PORT`, `WEB_RELOAD`, `INSTALL_TIMEOUT_SEC`, `AGENT_RESTART_ALERT_THRESHOLD` |
| 10 | AI VM (diagnostic-worker) | `LLM_TIMEOUT_SECONDS`, `RAG_ENABLED`, `EMBEDDING_PROVIDER/MODEL/DIMENSION/TIMEOUT_SECONDS`, `RAG_TOP_K`, `RAG_MAX_CONTEXT_CHARS`, `WORKER_JOB_TIMEOUT_SECONDS` |
| 11 | engine 전 컴포넌트 | `RABBITMQ_EXCHANGE`, `RABBITMQ_ROUTING_KEY_INVENTORY/METRICS/ERROR`, `DIAGNOSTIC_ROUTING_KEY`, `DIAGNOSTIC_QUEUE_TTL_MS`, `DIAGNOSTIC_QUEUE_MAX_LEN`, `SQLALCHEMY_ECHO` |
| 12 | agent | `AGENT_INTERVAL_SEC`, `AGENT_INVENTORY_REFRESH_SEC`, `RABBITMQ_HEARTBEAT_SEC`, `RABBITMQ_CONFIRM_TIMEOUT_SEC`, `AGENT_DRAIN_GRACE_SEC` / `TERM_SEC` / `PUBLISH_SEC` |

---

## 🔵 Low — 정리 권장

| # | 문제 | 처리안 |
|:--:|---|---|
| 13 | `SECRET_KEY` inject는 dead — engine env.md 키 카탈로그에 없음 | engine 코드가 read하는지 검증 필요. 안 쓰면 vault.yml에서도 제거 |
| 14 | `agent.env`의 routing key가 리터럴 하드코딩 (`assessment`, `server.inventory` 등) | engine과 동일하게 vault/group_vars 변수로 빼야 변경 시 한 곳만 수정 |
| 15 | agent TLS 키 군 (`RABBITMQ_TLS_*`) 미주입 | 현재 폐쇄망이라 plain AMQP로 충분. prod 외부 노출 시 도입 필요 |

---

## 원인 분석 (3 패턴)

1. **신규 키 추적 누락** — engine repo가 task.install 도입 시 `WORKER_*`, `DIAGNOSTIC_*` 키 군을 추가했는데 본 infra는 따라가지 못함. → agent worker 자체가 작동 안 함 (Critical #2 #3 #4).
2. **single source vs split key** — `OLLAMA_BASE_URL` 한 키를 본 infra가 `HOST+PORT`로 잘못 쪼개 주입. engine config가 단일 URL 키만 받는 구조 (Critical #1).
3. **prod 마커 미주입** — `APP_ENV` 누락으로 engine의 fail-fast 검증 시스템 전체가 unreachable. dev default가 prod에 흘러도 startup이 막지 않음 (High #5).

가장 위험한 것: **Critical #2 + #3** — 현재 코드 그대로 30대 agent 띄워도 task.install 메시지를 아무도 consume 안 함. collector publish만 돌고 진단 명령은 발행 즉시 유실 (queue TTL 후 drop).

---

## 수정 시퀀스 (권장 순서)

1. `playbook-ai.yml`: `OLLAMA_HOST/PORT/MODEL` → `OLLAMA_BASE_URL` + `OLLAMA_MODEL` 으로 교체. `engine/ansible/group_vars/all/ai.yml`에 `ollama_base_url` 도입.
2. `agent_env/templates/agent.env.j2`: `WORKER_DOWNLOAD_ALLOWED_HOSTS` 추가. 화이트리스트 source는 `engine_mq_host` + ZDM host. vault/group_vars에 변수 정의.
3. `agent_env/templates/agent.env.local.j2`: `RABBITMQ_WORKER_USER` / `RABBITMQ_WORKER_PASS` 추가. vault에 `vault_mq_worker_user`/`vault_mq_worker_password` 신설(권장) — 또는 publisher 자격 재사용.
4. engine 3개 playbook `app_env` dict: `APP_ENV=production`, `LOG_FORMAT=json`, `WORKER_TASK_EXCHANGE`/`QUEUE_PREFIX`/`RESULT_KEY`, `RABBITMQ_EXCHANGE`/`ROUTING_KEY_*`, `DIAGNOSTIC_ROUTING_KEY`/`QUEUE_TTL_MS`/`QUEUE_MAX_LEN` 추가.
5. `playbook-api.yml`: `ZDM_PACKAGE_PATH`/`SCRIPT` + `ZDM_META_*` + `INSTALL_TIMEOUT_SEC` + `AGENT_RESTART_ALERT_THRESHOLD` 추가. `engine/ansible/group_vars/all/zdm.yml`에 변수 정의.
6. `playbook-ai.yml`: RAG/embedding/LLM tuning 키 추가 (`engine/ansible/group_vars/all/ai.yml`로 흡수).
7. `agent_env` role: agent runtime 튜닝 키군 (`AGENT_INTERVAL_SEC`, `AGENT_INVENTORY_REFRESH_SEC`, `WORKER_TASK_*`) 추가.
8. routing key 리터럴 → 변수화 (Low #14). 이 시점에서 `agent/ansible/group_vars/all/vars.yml`에 routing 관련 변수 그룹 도입.
9. `SECRET_KEY` 실사용 여부 검증 후 정리 (Low #13).

---

## 후속

수정 작업 진행 시 본 문서 항목별로 ✅ 마킹 또는 항목 제거. 모든 항목 해소 후 본 문서 폐기하고 `env-engine.md`/`env-agent.md`만 유지.

## 관련 문서

- `docs/operations/env-engine.md` — engine VM 환경변수 카탈로그 (현재 inject 기준)
- `docs/operations/env-agent.md` — agent VM 환경변수 카탈로그
- `~/PycharmProjects/assessment-engine/docs/operations/env.md` — engine repo의 contract
- `~/PycharmProjects/assessment-agent/.env.example` — agent repo의 contract
