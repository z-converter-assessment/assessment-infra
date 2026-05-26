# 컴포넌트별 책임

각 VM의 책임 경계·인터페이스만. 내부 구현(role tasks·systemd unit 내용)은 코드 참조.

플레이버 정의는 `engine/terraform/variables.tf`. SG 매트릭스는 [topology.md](topology.md).

## api-vm

| 항목 | 값 |
|---|---|
| 책임 | HTTP API 제공, 진단 작업 publish, alembic one-shot |
| 컴포넌트 | assessment-engine wheel — `assessment_engine.web.main:app` (uvicorn) |
| 외부 노출 | 8000/tcp (FIP 경유) |
| 의존 | db-vm · cache-vm · mq-vm |
| 상태 | Stateless |
| spec | 최저 플레이버 (1 vCPU / 1 GB) |
| 데이터 | 없음 (모든 상태는 db/cache/mq) |

## mq-vm

| 항목 | 값 |
|---|---|
| 책임 | AMQP 메시지 브로커 (engine 내부 + agent ↔ engine) |
| 컴포넌트 | rabbitmq-server (Debian main repo apt — ADR-0004) |
| 외부 노출 | 없음 (사설 5672·15672) |
| 의존 | 없음 |
| 상태 | Stateful — mnesia 디렉토리 |
| spec | 1 vCPU / **2 GB** (Erlang 런타임 요구로 1 GB 불가) |
| 데이터 | Cinder 볼륨 마운트 → `/var/lib/rabbitmq` |

## cache-vm

| 항목 | 값 |
|---|---|
| 책임 | TTL 캐시 (online·idempotent·token 등) |
| 컴포넌트 | redis-server (apt) |
| 외부 노출 | 없음 (사설 6379) |
| 의존 | 없음 |
| 상태 | Stateless — fail-open 정책, cold start 허용 (RDB·AOF off) |
| spec | 최저 (1 vCPU / 1 GB) |
| 데이터 | 영속화 없음 |

## db-vm

| 항목 | 값 |
|---|---|
| 책임 | 영속 메타데이터·진단 결과 저장 |
| 컴포넌트 | postgresql-16 + timescaledb (PGDG repo `trixie-pgdg`) |
| 외부 노출 | 없음 (사설 5432) |
| 의존 | 없음 |
| 상태 | Stateful — PostgreSQL data 디렉토리 |
| spec | 1 vCPU / **2 GB** (shared_buffers + OS 여유) |
| 데이터 | Cinder 볼륨 마운트 → `/var/lib/postgresql` |

> TimescaleDB는 `postgresql-16 >= 16.14` 요구 → PGDG repo 필수.

## worker-vm

| 항목 | 값 |
|---|---|
| 책임 | 진단 작업 consume·실행, 스케줄러 |
| 컴포넌트 | assessment-engine wheel — `python -m assessment_engine.consumer` |
| 외부 노출 | 없음 |
| 의존 | db-vm · cache-vm · mq-vm |
| 상태 | Stateless |
| spec | 최저 (1 vCPU / 1 GB) |
| 데이터 | 없음 |

> api-vm과 동일 wheel — systemd unit·EnvironmentFile만 다름 (`app_service_name: assessment-worker`).

## ai-vm

| 항목 | 값 |
|---|---|
| 책임 | LLM 진단 narrative 합성 |
| 컴포넌트 | Ollama 데몬 + 최경량 모델(~3B Q4) |
| 외부 노출 | 없음 (사설) |
| 의존 | api-vm:8000 · db-vm:5432 (역방향 — 본인이 호출) |
| 상태 | Stateless (모델 파일은 disk에 정적) |
| spec | ZDM 플레이버 (4 vCPU / 8 GB / 100 GB disk) |
| 데이터 | Ollama 모델 파일 (~2 GB) — disk 100 GB |

> Python wheel 없음. apt 또는 official install script로 Ollama 설치 (방식 TBD).

## agent-vm × N

| 항목 | 값 |
|---|---|
| 책임 | 로컬 서비스 메트릭·인벤토리 수집, AMQP publish |
| 컴포넌트 | assessment-agent (C 바이너리) + 로컬 PostgreSQL·Redis (모니터링 대상) |
| 외부 노출 | 없음 |
| 의존 | mq-vm:5672 (engine 측), 로컬 PostgreSQL·Redis |
| 상태 | machine-id 기반 dedup (application level — snapshot 복제 시 충돌 빈번) |
| spec | 1 vCPU / 1 GB / 20 GB |
| OS | 8종 이상 (Linux 계열 + Windows) — 목록 TBD |

> 테스트 플릿. 각 VM에 모니터링 대상 서비스를 직접 실행해 실제 환경 시뮬레이션.

## bastion-vm

| 항목 | 값 |
|---|---|
| 책임 | Ansible/Terraform 실행 호스트, ProxyJump SSH gateway |
| 컴포넌트 | Terraform + Ansible (Debian 13 위에서 실행) |
| 외부 노출 | 22/tcp (FIP — 사내망에서 접근) |
| 의존 | 없음 (모든 VM 관리) |
| 상태 | 작업 디렉토리, terraform.tfstate, Ansible Vault |
| spec | ZDM 플레이버 (4 vCPU / 8 GB / 100 GB disk) |
| OS | Debian 13 (Trixie) |

> 본 레포 Terraform 관리 대상 아님 (Horizon 수동 생성). `bastion-sg`는 data source로 참조.
