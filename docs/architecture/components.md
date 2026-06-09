# 컴포넌트별 책임

각 VM·compose 서비스의 책임 경계·인터페이스만. 내부 구현(role tasks·compose 정의)은 코드 참조.

플레이버 정의는 `engine/terraform/variables.tf`. SG 매트릭스는 [topology.md](topology.md).

> ADR-0010 이후 engine 컴포넌트는 **engine-vm 1대의 docker compose 서비스**다. 아래 "engine-vm" 표의 각 행은 별도 VM이 아니라 같은 호스트의 컨테이너.

## engine-vm

| 항목 | 값 |
|---|---|
| 책임 | engine stack 전체 호스팅 (docker compose) |
| 외부 노출 | 8000/tcp (FIP 경유, api 서비스) · 15672 (bastion SSH 포워딩, mq mgmt) |
| spec | `var.flavor_engine` (compose 전체를 수용 — pg+mq+redis+api+consumer) |
| 데이터 | Cinder 2볼륨: `/mnt/pgdata`(30 GB) · `/mnt/mqdata`(20 GB) |
| 배포 | `engine_compose` role — docker-ce 설치 → 볼륨 mount → release compose pull → up |

### compose 서비스

| 서비스 | 책임 | 이미지 | 포트(호스트 내) | 상태 |
|---|---|---|---|---|
| `api` | HTTP API, 진단 작업 publish | GHCR assessment-engine (`assessment_engine.web.main:app`) | 8000 | Stateless |
| `consumer` | 진단 작업 consume·실행, 스케줄러 | GHCR assessment-engine (`python -m assessment_engine.consumer`) | — | Stateless |
| `migrate` | alembic `upgrade head` 1회 (init-container) | GHCR assessment-engine | — | one-shot |
| `postgres` | 영속 메타데이터·진단 결과 | `postgres:16` + timescaledb | 5432 | Stateful → `/mnt/pgdata` |
| `rabbitmq` | AMQP 브로커 (engine 내부 + agent·AI) | `rabbitmq:3-management` | 5672 · 15672 | Stateful → `/mnt/mqdata` |
| `redis` | TTL 캐시 (online·idempotent·token) | `redis:7` | 6379 | Stateless (RDB·AOF off, fail-open) |

> 같은 호스트라 서비스 간 통신은 loopback/compose 네트워크 — SG rule 없음. `restart: unless-stopped` + `healthcheck` + `depends_on: service_healthy`로 기동 순서·자가 복구.

## ai-vm

| 항목 | 값 |
|---|---|
| 책임 | LLM 진단 narrative 합성 + AI diagnostic-worker |
| 컴포넌트 | Ollama 데몬(`ollama` role) + diagnostic-worker (compose) |
| 외부 노출 | 11434 (engine-sg에서만) |
| 의존 | engine-vm의 mq:5672·pg:5432·redis:6379 (diagnostic-worker가 역접속) |
| 상태 | Stateless (모델 파일은 disk에 정적) |
| spec | `var.flavor_ai` (ZDM급 — 4 vCPU / 8 GB / 100 GB disk) |
| 데이터 | Ollama 모델 파일 (`gemma2:2b` ~1.6 GB) — disk 100 GB |

> engine stack과 분리 유지: GPU/메모리 요구·모델 disk·lifecycle 상이 (ADR-0010).

## agent-vm × N

| 항목 | 값 |
|---|---|
| 책임 | 로컬 서비스 메트릭·인벤토리 수집, AMQP publish |
| 컴포넌트 | assessment-agent (C 바이너리) + 로컬 PostgreSQL·Redis (모니터링 대상) |
| 외부 노출 | 없음 (Windows는 WinRM 5985 ← bastion) |
| 의존 | engine-vm:5672 (MQ), 로컬 PostgreSQL·Redis |
| 상태 | machine-id 기반 dedup (application level — snapshot 복제 시 충돌 빈번) |
| spec | 1 vCPU / 1 GB / 20 GB |
| OS | Linux 7종 × 4 (Debian 13/12·Ubuntu 24.04/22.04·Rocky 9·AlmaLinux 9·CentOS Stream 9) + Windows Server 2022 ×1(옵션) |

> 테스트 플릿. 각 VM에 모니터링 대상 서비스를 직접 실행해 실제 환경 시뮬레이션.

## bastion-vm

| 항목 | 값 |
|---|---|
| 책임 | Terraform/Ansible 실행 호스트, **self-hosted runner**, ProxyJump SSH gateway |
| 컴포넌트 | Terraform + Ansible + GitHub Actions runner (Debian 13) |
| 외부 노출 | 22/tcp (FIP — 사내망에서 접근) |
| 의존 | 없음 (모든 VM 관리) |
| 상태 | 작업 디렉토리, terraform.tfstate, Ansible Vault, `~/.ssh/engine-key.pem`, runner |
| spec | ZDM 플레이버 (4 vCPU / 8 GB / 100 GB disk) |
| OS | Debian 13 (Trixie) |

> 본 레포 Terraform 관리 대상 아님 (Horizon 수동 생성). `bastion-sg`는 data source로 참조.
