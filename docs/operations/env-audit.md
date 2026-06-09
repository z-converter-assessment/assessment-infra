# 환경변수 inject 감사 (env-audit) — Deprecated

> **상태: Deprecated (2026-06-09).** engine·agent contract 격차의 Critical/High 및 대부분의 Medium 항목이 해소됨.
> 현재 inject 상태의 단일 진실은 아래 문서로 이관:
> - engine: `env-engine.md` (`.env.j2` v0.5.0과 1:1)
> - agent: `agent-test-environment.md` (§3 환경변수 + 주입 경로·실행 권한)
>
> 본 문서는 **아직 남은 잔여 항목만** 추적용으로 보존한다. 잔여 해소 시 본 문서를 삭제한다.

---

## 해소 요약 (2026-06-09 세션)

- **Critical 1–4**: `OLLAMA_BASE_URL` 단일 키, agent `WORKER_DOWNLOAD_ALLOWED_HOSTS`·`RABBITMQ_WORKER_*`·`WORKER_TASK_*` 전부 주입. (engine 측은 `RABBITMQ_TASK_*` prefix로 정식화)
- **High 5–6**: `APP_ENV=prod`(production→prod 정정)·`LOG_FORMAT=json` 주입.
- **High 7 (vhost)**: engine·agent 양쪽 `vault_mq_vhost=assessment`로 bit-exact 일치 확인(해소). engine repo docs default(`/assessment`)와만 표기 차이 — 운영상 무영향.
- **Medium 8**: ZDM 키군 전부 주입.
- **Medium 11**: routing/diagnostic 키 + `SQLALCHEMY_ECHO` 주입(완료).
- **Medium 9 일부 / 12 일부 / Low 15 일부**: `WEB_PORT`·`INSTALL_TIMEOUT_SEC`(engine), `AGENT_INTERVAL_SEC`·`AGENT_INVENTORY_REFRESH_SEC`·`AGENT_DRAIN_{GRACE,TERM,PUBLISH}_SEC`·`RABBITMQ_TLS_ENABLED=false`(agent, Linux+Windows) 주입. systemd `TimeoutStopSec=900` 정합.

근거 커밋: engine contract/v0.5.0(`21326cd`), agent 즉시수정 4건(`967a7d1` merge), agent 권장수정(`8a26683` merge).

---

## 잔여 항목

| # | 대상 | 키/내용 | 등급 | 처리안 |
|:--:|---|---|:--:|---|
| R-1 | engine diagnostic-worker | `LLM_TIMEOUT_SECONDS`, `RAG_ENABLED`, `EMBEDDING_PROVIDER/MODEL/DIMENSION/TIMEOUT_SECONDS`, `RAG_TOP_K`, `RAG_MAX_CONTEXT_CHARS`, `WORKER_JOB_TIMEOUT_SECONDS` | 🟠 | engine code default 의존(런타임 테스트상 `rag_enabled=False embedding_provider=mock`로 정상 부팅). 비-default 필요 시 `ai.yml`로 주입 |
| R-2 | engine web | `WEB_RELOAD`(base default false 충분), `AGENT_RESTART_ALERT_THRESHOLD`(엔진 read 여부 미확인) | ⚪ | read 확정 후 필요 시 `engine.yml`로 주입 |
| R-3 | engine | `SECRET_KEY` 실사용 검증 | 🔵 | v0.5.0 `env.example` 미수록. 부팅은 정상(extra ignore 추정) — 엔진 코드 read 여부 확인 후 미사용이면 `.env.j2`·vault에서 제거 |
| R-4 | agent | `RABBITMQ_HEARTBEAT_SEC`(기본 60), `RABBITMQ_CONFIRM_TIMEOUT_SEC`(기본 5) | ⚪ | 기본값 충분 — 문서화만, 튜닝 필요 시 `vars.yml`로 주입 |
| R-5 | agent (Windows) | `win_environment` 루프의 routing key가 리터럴 하드코딩(`assessment`·`server.inventory` 등) | 🔵 | Linux `agent.env.j2`는 `{{ mq_* }}` 변수화 완료. Windows 루프도 동일 변수 참조로 변경 권장(변경 시 한 곳만 수정) |
| R-6 | agent | 전체 TLS 키군(`RABBITMQ_TLS_CA_PATH`·`VERIFY_PEER/HOSTNAME`·`CERT_PATH/KEY_PATH`) | 🔵 | 폐쇄망 plain AMQP라 N/A. `RABBITMQ_TLS_ENABLED=false`는 명시 완료. prod 외부 노출(TLS) 전환 시 도입 |

---

## 관련 문서
- `env-engine.md` — engine VM 환경변수 카탈로그 (현재 inject 기준, 단일 진실)
- `agent-test-environment.md` — agent 환경변수·주입 경로·실행 권한
