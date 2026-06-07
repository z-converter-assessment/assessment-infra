# Agent publish 아키텍처

`assessment-agent` 프로세스(C 바이너리, `src/main.c` 진입점)가 RabbitMQ broker로 메시지를 발행·소비하는 메커니즘. infra가 inject 해야 할 env 변수의 출처가 본 문서.

소스 출처: `~/PycharmProjects/assessment-agent/src/{main,publish,worker,collect}.c` + `docs/payload-schema.md` (v3.2부터 CM2 모델 도입).

---

## 핵심 — 프로세스 1개, AMQP connection 2개 (CM2 모델)

agent v3.2부터 collector와 worker는 **각자 다른 AMQP connection + 다른 자격**으로 broker에 접속한다. 같은 프로세스 안의 두 컴포넌트지만 connection 자체가 분리.

```
                  ┌───────────────────────────────────────┐
                  │       agent process (단일 PID)         │
                  │                                       │
                  │  ┌────────────┐    ┌──────────────┐    │
                  │  │ collector  │    │   worker     │    │
                  │  │ (main 루프) │    │  (worker.c)  │    │
                  │  └─────┬──────┘    └──────┬───────┘    │
                  │        │ 단발성 conn      │ 영구 conn  │
                  │   AMQP conn 1        AMQP conn 2       │
                  │   (publish-only)     (consume+publish) │
                  └────────┼──────────────────┼───────────┘
                           │                  │
                           ▼                  ▼
                    RABBITMQ_USER       RABBITMQ_WORKER_USER
                    `assessment`        `assessment.tasks`
                     exchange            exchange
```

분리 이유 (payload-schema.md v3.2):
- broker ACL에서 `agent-publisher`·`agent-worker` 별도 role 부여 가능
- agent host 침해 시 한 자격의 피해 반경을 다른 자격까지 확장 못 함

---

## connection 1 — collector

`src/publish.c` 주석:
> Each call opens a fresh connection, publishes one message, and tears down.

→ collector는 매 publish마다 conn open → publish 1건 → conn close. publisher confirms 켜고 ACK까지 대기 (`RABBITMQ_CONFIRM_TIMEOUT_SEC`, default 5s).

### 발행하는 메시지 3종

| 메시지 | routing key | 트리거 | 내용 |
|---|---|---|---|
| inventory | `RABBITMQ_ROUTING_KEY_INVENTORY` (default `server.inventory`) | startup 1회 + `AGENT_INVENTORY_REFRESH_SEC` (default 1h) **±15% jitter** 재발행 | HW spec, OS, disks/mounts, services[], listen_ports[], MAC addresses 등 host 식별 정보 |
| metrics | `RABBITMQ_ROUTING_KEY_METRICS` (default `server.metrics`) | 매 `AGENT_INTERVAL_SEC` (default 60s) | `/proc` raw 값 (CPU tick, mem kB, disk_io[], net_io[], load) |
| error | `RABBITMQ_ROUTING_KEY_ERROR` (default `server.error`) | collect 실패 시 best-effort | error code + context. **재귀 방지** — 이 publish 실패해도 server.error 재시도 안 함 |

세 종류 공통:
- exchange: `RABBITMQ_EXCHANGE` (default `assessment`, direct type)
- delivery_mode: 2 (persistent)
- publisher confirms 켬 → broker ACK까지 deadline 대기
- 실패 시 exponential backoff retry (`publish_with_retry`, max backoff = `AGENT_INTERVAL_SEC`)

### inventory jitter — 동시 부팅 분산

```c
static time_t next_inventory_deadline(time_t now, int refresh_sec) {
    // refresh_sec × (1 + uniform(-0.15, +0.15))
}
srand((unsigned int)(time(NULL) ^ getpid()));  // seed에 pid mix
```

30대 agent가 같은 시각 부팅돼도 inventory가 같은 분에 몰리지 않게 분산. pid를 seed에 섞어 같은 시각 부팅 host도 발산.

---

## connection 2 — worker

worker는 **consume이 본업**, publish는 결과 보고 1종(task.result)뿐.

### 발행·소비 패턴

```
queue: agent.tasks.<composite_id>     ←──── engine api-vm이 publish
                                              (composite_id = machine_id + agent ver?)
   ↓ basic.get (polling, worker_tick 호출 시)
worker가 install.sh 실행 (sandbox extraction + setrlimit + clearenv)
   ↓
publish_conn_publish(conn,
                     WORKER_TASK_EXCHANGE (default "assessment.tasks"),
                     WORKER_TASK_RESULT_KEY (default "task.result"),
                     result_payload)
   ↓
basic.ack to broker
```

### 큐 이름 규약

```c
queue_prefix = getenv_default("WORKER_TASK_QUEUE_PREFIX", "agent.tasks");
cid = cached_composite_id(machine_id);
snprintf(queue_name, sizeof queue_name, "%s.%s", queue_prefix, cid);
```

engine 측에서 publish할 때 `task.install.<composite_id>` routing key를 쓰고, agent는 `agent.tasks.<composite_id>` 큐에 바인딩되어 receive. 양쪽이 같은 composite_id 규약을 알아야 함.

### worker 비활성 조건 — silent fallback

`src/main.c:325`:

```c
const char *worker_user = getenv_default("RABBITMQ_WORKER_USER", "");
if (*worker_user) {
    // worker_init() 진입 — persistent conn open, queue 준비
} else {
    fprintf(stderr, "[agent] RABBITMQ_WORKER_USER unset — worker disabled\n");
    // 메인 루프는 그대로 진행 (collector-only mode)
}
```

→ `RABBITMQ_WORKER_USER` 빈값이면 worker init 자체 skip. agent는 정상 기동하고 collector만 동작. task.install 메시지는 큐에 쌓이기만 함 → TTL 24h 후 DLX `assessment.tasks.dlx` → `assessment.tasks.dead`로 drop. 운영자가 "왜 install이 안 돼?"를 디버깅하려면 broker management 또는 agent stderr 첫줄 확인 필요.

env-audit Critical #3의 검출 지점이 정확히 이 분기다.

### download 화이트리스트 — Critical #2 검출 지점

```c
.allowed_hosts_csv = getenv_default("WORKER_DOWNLOAD_ALLOWED_HOSTS", "")
```

worker.c가 task.install payload의 `download.url`을 받으면 host 부분을 CSV와 case-insensitive **정확 매치** (subdomain wildcard 없음). 빈 CSV = 모든 host reject = `url_not_allowed` 코드로 task.result `failed` 보고.

worker는 동작은 함 (task 수신·ack·result publish 모두 정상) — download 단계만 실패. Critical #3와 달리 **task.result로 실패 보고가 가는** 점이 다름.

---

## startup → loop 전체 시퀀스

```
1. signal handler (SIGINT/SIGTERM → g_stop=1, SIGPIPE → IGN)
2. umask 077 (state files 0600)
3. load_env_file(".env") + getenv 우선
4. machine_id 결정:
   /etc/machine-id → dbus-uuidgen → cloud IMDS (AWS/Azure/GCP, 1s timeout)
5. publish_config 빌드 (collector용 — RABBITMQ_USER/PASS)
6. ── 초기 publish ──
   publish_with_retry(server.inventory, ...)  ← 실패해도 metrics로 계속
7. AGENT_INTERVAL_SEC <= 0 이면 one-shot 모드:
   metrics 1회 publish → exit
8. ── worker 초기화 (optional) ──
   if RABBITMQ_WORKER_USER 비어있지 않음:
       worker_publish_config 빌드 (worker용 — RABBITMQ_WORKER_USER/PASS)
       queue_name = "<WORKER_TASK_QUEUE_PREFIX>.<composite_id>"
       worker = worker_init(...)  ← persistent conn open + heartbeat 60s
   else:
       worker = NULL  (collector-only)
9. ── 메인 루프 ──
   while !g_stop:
       publish(server.metrics, payload)
       if 1h ±jitter 도달: publish(server.inventory, payload) + 다음 deadline 갱신
       worker_tick(worker)  ← basic.get 1회, 있으면 install + publish task.result + ack
       sleep_chunked(interval, 25s씩, worker_keepalive 사이사이 호출)
10. ── drain (SIGTERM 받으면) ──
    Phase 1 (grace, AGENT_DRAIN_GRACE_SEC=600s): in-flight install 자연 종료 대기
    Phase 2 (term, AGENT_DRAIN_TERM_SEC=30s): SIGTERM to install.sh process group
    Phase 3 (kill): SIGKILL
    Phase 4 (publish-stuck, AGENT_DRAIN_PUBLISH_SEC=180s): broker dead면
        result file을 /var/lib/agent-worker/results/에 남기고 종료
        → 다음 startup이 replay
```

### worker connection keepalive

```c
int remaining = interval;
const int chunk = 25;
while (remaining > 0 && !g_stop) {
    sleep((unsigned int)(remaining > chunk ? chunk : remaining));
    remaining -= chunk;
    if (worker) worker_keepalive(worker);
}
```

interval=60s sleep을 25s chunk로 쪼개는 이유 — librabbitmq가 `wait_frame_noblock`에서 heartbeat를 보내는데, heartbeat=60s 설정 하에 60s 한방 sleep이면 broker가 2×heartbeat tolerance window를 초과 판정해 connection drop. 25s chunk면 매 chunk 사이에 keepalive 호출로 heartbeat frame 교환 → drop 회피.

---

## infra가 inject해야 할 env 변수 (요약)

자세한 키 카탈로그는 `docs/operations/env-agent.md`, 누락 현황은 `docs/operations/env-audit.md` 참조.

| 그룹 | collector 사용 | worker 사용 | infra inject 위치 |
|---|---|---|---|
| broker 접속 | `RABBITMQ_HOST` `PORT` `VHOST` | 동일 (공유) | `agent.env.j2` |
| 자격 | `RABBITMQ_USER` `RABBITMQ_PASS` | `RABBITMQ_WORKER_USER` `RABBITMQ_WORKER_PASS` | `agent.env.local.j2` (secret) |
| collector 라우팅 | `RABBITMQ_EXCHANGE` `RABBITMQ_ROUTING_KEY_INVENTORY/METRICS/ERROR` | — | `agent.env.j2` |
| worker 라우팅 | — | `WORKER_TASK_EXCHANGE` `WORKER_TASK_QUEUE_PREFIX` `WORKER_TASK_RESULT_KEY` `WORKER_DOWNLOAD_ALLOWED_HOSTS` | `agent.env.j2` |
| 런타임 튜닝 | `AGENT_INTERVAL_SEC` `AGENT_INVENTORY_REFRESH_SEC` `RABBITMQ_HEARTBEAT_SEC` `RABBITMQ_CONFIRM_TIMEOUT_SEC` | `AGENT_DRAIN_*` `WORKER_INSTALL_*` `WORKER_STATE_DIR` 등 | `agent.env.j2` (선택 키들) |

자격 분리 결정의 트레이드오프는 `docs/adr/0009-agent-mq-credential-reuse.md`.

## 관련 문서

- `docs/operations/env-agent.md` — agent VM 환경변수 카탈로그
- `docs/operations/env-audit.md` — 현재 inject 격차
- `docs/adr/0009-agent-mq-credential-reuse.md` — worker 자격 분리·재사용 결정
- `~/PycharmProjects/assessment-agent/docs/payload-schema.md` — 메시지 contract v3.x
- `~/PycharmProjects/assessment-agent/docs/worker-task-design.md` — worker 보안 모델
