# ADR-0009: Agent MQ 자격 — env key는 분리, vault 값은 publisher 자격 재사용

- 상태: Accepted
- 날짜: 2026-06-02

## 컨텍스트

`assessment-agent` v3.2부터 CM2 (Connection Model 2) 채택. 한 agent 프로세스 안에서 collector(publish-only)와 worker(consume + task.result publish)가 각자 다른 AMQP connection을 연다. 각 connection은 다른 자격을 요구한다:

- collector → `RABBITMQ_USER` / `RABBITMQ_PASS`
- worker → `RABBITMQ_WORKER_USER` / `RABBITMQ_WORKER_PASS`

assessment-agent 코드(`src/main.c:325`)는 두 변수쌍을 **항상** 읽으며, `RABBITMQ_WORKER_USER`가 빈값이면 worker init 자체를 skip(silent fallback). 따라서 infra는 두 변수쌍을 **반드시 inject**해야 한다 — 이 부분은 선택이 아니다.

선택지는 broker 측 RabbitMQ user를 1개로 둘 것인지 2개로 둘 것인지, 그리고 vault에 자격을 1쌍 둘 것인지 2쌍 둘 것인지의 조합:

| 옵션 | env 변수 | vault 값 | broker user |
|---|---|---|---|
| 1 (보수적) | 2쌍 분리 | 2쌍 신설 | 2개 — `agent-publisher` + `agent-worker` |
| 2 (단순화) | 2쌍 분리 (값 동일) | 1쌍 | 1개 (publisher 재사용) |
| 3 (혼합, 채택) | 2쌍 분리 (지금은 값 동일) | 1쌍 (지금) → 추후 2쌍 분리 가능 | 1개 (지금) → 추후 분리 가능 |

assessment-agent repo(`.claude/CLAUDE.md`)와 `docs/payload-schema.md` v3.2는 prod에서 **2 role 분리**를 권장한다 — 분리의 이점은 agent host 침해 시 worker 자격으로 다른 agent 메시지 publish 불가, publisher 자격으로 다른 agent 큐 consume 불가.

다만 본 infra의 현재 단계는 학습·테스트 환경(30대+ Linux + 1대 Windows agent)이며, broker ACL 운영 부담을 즉시 부담할 만큼 위협 모델이 정교하지 않다.

## 결정

**옵션 3 — env key는 분리, vault 값은 publisher 자격 재사용** 채택.

- `agent.env.local.j2`에 `RABBITMQ_WORKER_USER` / `RABBITMQ_WORKER_PASS` 변수를 추가
- 값은 `{{ vault_mq_user }}` / `{{ vault_mq_password }}` 재사용 — `vault.yml`에 worker 전용 항목 신설하지 않음
- broker 측 RabbitMQ는 단일 user (`assessment`) 유지 — engine MQ role의 user 생성 task에 변화 없음
- 분리 필요 시점에 ① vault에 `vault_mq_worker_user` / `vault_mq_worker_password` 추가, ② template만 갱신, ③ broker에 `agent-worker` role 추가 — 본 ADR 폐기·후속 ADR 작성

## 트레이드오프

| | 옵션 1 (분리) | 옵션 2 (완전 통합) | 옵션 3 (혼합, 채택) |
|---|---|---|---|
| broker ACL 분리 (침해 격리) | ✓ | ✗ | ✗ (지금) → ✓ (분리 시) |
| vault 항목 수 | 4개 (DB·MQ·worker·secret_key) | 3개 | 3개 |
| template 변경 비용 (분리로 가는 길) | — (이미 분리됨) | env key 추가 + vault 추가 + broker user 추가 | vault 추가 + broker user 추가 (env key는 그대로) |
| agent 코드 호환성 | ✓ | ✓ | ✓ |
| 코드 명확성 (`WORKER_USER`의 존재) | ✓ | ✗ — agent code 의도가 inject template에서 안 드러남 | ✓ — 키 존재로 의도 명시 |

옵션 3가 옵션 2 대비 가지는 이점은 "future-proofing without commitment": 키 분리를 코드에 박아두어 분리 작업의 진입 비용을 낮추고, agent CM2 모델의 존재를 inject 측에서도 명시적으로 표현. 옵션 1 대비 가지는 이점은 broker ACL 운영 부담을 분리가 실제로 필요한 시점까지 미룰 수 있다는 것.

## 결과

- `agent/ansible/roles/agent_env/templates/agent.env.local.j2`에 worker 자격 4줄 추가 (변수쌍 2개 + 주석)
- vault 변경 없음
- broker MQ role 변경 없음
- agent worker가 task.install consume 시작 — env-audit Critical #3 해소 (단, `WORKER_DOWNLOAD_ALLOWED_HOSTS` 미주입 시 download 단계에서 실패 보고)

## 후속 결정 (분리가 필요해질 때의 신호)

다음 조건 중 하나라도 충족되면 vault·broker user 분리를 재논의:

- agent 플릿이 실제 고객사 환경에 배포되어 host 침해 위협 모델이 현실화
- 한 자격으로 publisher·worker 양쪽 권한을 동시에 가진 게 monitoring에서 noise를 만들거나 audit log를 복잡하게 함
- RabbitMQ 사용량이 multi-tenant 패턴으로 진화

분리 결정 시 신규 ADR 작성, 본 ADR 상태 → Deprecated.
