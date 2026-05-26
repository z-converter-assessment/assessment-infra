# Agent 환경변수 카탈로그

> assessment-agent (C 바이너리)에 주입되는 환경변수 목록.
> engine 환경변수는 `docs/operations/env-engine.md` 참조.

## 주입 방식

Ansible이 각 Agent VM의 `/etc/assessment-agent.env`에 환경파일을 생성하고,
systemd unit의 `EnvironmentFile=` 지시어로 로드한다.

## 전체 키 목록

> TODO: assessment-agent repo 구현 확정 후 채울 것.
> 아래는 engine ↔ agent 계약(docs/architecture/agent.md)에서 예상되는 키 목록.

| 키 | 기본값 | 설명 |
|----|--------|------|
| `RABBITMQ_HOST` | (engine MQ VM 사설 IP) | engine MQ VM 주소 |
| `RABBITMQ_PORT` | `5672` | AMQP 포트 |
| `RABBITMQ_VHOST` | `/assessment` | 전용 vhost |
| `RABBITMQ_USER` | — | secret — Ansible Vault에서 주입 |
| `RABBITMQ_PASSWORD` | — | secret — Ansible Vault에서 주입 |
| `RABBITMQ_EXCHANGE` | `assessment` | engine과 동일 값 사용 |
| `RABBITMQ_ROUTING_KEY_INVENTORY` | `server.inventory` | engine과 동일 |
| `RABBITMQ_ROUTING_KEY_METRICS` | `server.metrics` | engine과 동일 |
| `RABBITMQ_ROUTING_KEY_ERROR` | `server.error` | engine과 동일 |
| `WORKER_TASK_EXCHANGE` | `assessment.tasks` | task.install/result 전용 exchange |
| `WORKER_TASK_QUEUE_PREFIX` | `agent.tasks` | 큐 prefix — full: `<prefix>.<machine_id>` |
| `WORKER_TASK_RESULT_KEY` | `task.result` | 결과 보고 routing key |

## 주의

- `RABBITMQ_HOST`는 agent VM이 engine MQ VM에 직접 접속. FIP 없이 사설 IP 사용 — agent-sg에서 mq-sg 5672 허용 필요 (security_groups.tf에 반영됨)
- Windows agent VM은 WinRM으로 배포 — 환경파일 경로·형식이 Linux와 다름 (결정 보류)
