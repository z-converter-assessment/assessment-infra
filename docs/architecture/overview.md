# 시스템 개요

## 무엇을 만드는가

assessment-engine(평가·진단 시스템) + assessment-agent(C 바이너리 모니터링 에이전트)의 **OpenStack 배포 인프라**.

본 레포는 **인프라만** 담당 — 기능 코드는 assessment-engine repo에서 **컨테이너 이미지·compose 정의**(engine)와 **바이너리**(agent) 형태로 가져옴.

## 시스템 컨텍스트 (C4 Level 1)

```mermaid
flowchart LR
  user[사내망 사용자]
  engine_repo[assessment-engine repo<br/>GitHub Releases + GHCR]
  agent_repo[assessment-agent repo<br/>GitHub Releases]

  subgraph infra[본 레포 = OpenStack 환경]
    engine[Engine VM<br/>docker compose stack<br/>api·consumer·pg·mq·redis]
    ai[AI VM<br/>Ollama + diagnostic-worker]
    fleet[Agent Fleet<br/>30+ VM, 8+ OS]
  end

  user -- HTTP :8000 --> engine
  engine_repo -. image + docker-compose.yml .-> infra
  agent_repo -. binary .-> infra
  fleet -- AMQP --> engine
  ai -- Ollama :11434 / AMQP --> engine
```

## 본 레포가 만드는 것

- **Engine VM 1대** — `api·consumer·postgres·rabbitmq·redis`를 **docker compose 단일 stack**으로 호스팅 (ADR-0010). 컴포넌트 간 통신은 호스트 loopback
- **AI VM 1대** — Ollama 데몬 + diagnostic-worker (lifecycle·자원 요구 상이로 분리 유지)
- **Agent 테스트 플릿** (30대+·OS 8종+) — 멀티 OS 동작 검증
- **네트워크 격리** — engine-subnet / agent-subnet 분리, SG 3종(engine·agent·ai)으로 접근 제어
- **운영 자산** — Cinder 볼륨 (engine-vm에 PostgreSQL 30 GB·RabbitMQ 20 GB attach), FIP (engine-vm·bastion), Ansible Vault (secret)

## 본 레포가 만들지 않는 것

- Neutron network·subnet·router — Horizon 수동 (`data` source로 참조만)
- OpenStack keypair — Horizon 등록분 (`variable`로 참조만)
- Bastion VM — Horizon 수동 (첫 ops host)
- 기능 코드 — assessment-engine / assessment-agent repo의 release artifact

## 외부 의존 contract

assessment-engine repo의 자산을 본 레포가 참조한다. 카탈로그·schema는 외부 단일 진실.

| 자산 | 위치 | 용도 |
|---|---|---|
| engine 환경변수 카탈로그 | 본 레포 `docs/operations/env-engine.md` | engine `.env`에 inject할 키 목록 |
| agent 환경변수 카탈로그 | 본 레포 `docs/operations/env-agent.md` | agent VM inject할 키 목록 |
| prod contract | assessment-engine `docs/operations/prod-contract.md` | secret 채널·weak default 거부 정책 |
| 메시지 schema | assessment-engine `docs/architecture/agent.md` | agent ↔ broker 페이로드 |
| 디렉토리 구조 ref | assessment-engine `docs/ref/cd-repo-guide.md` + `agent-fleet-infra-guide.md` | 본 레포 디자인 ref (격리) |
| release artifact | assessment-engine release | `docker-compose.yml`·`env.example`·이미지(GHCR)·wheel·SHA256SUMS |

## 도구 파이프라인

0. **Horizon** (웹 UI) — network·subnet·router·bootstrap VM·keypair 수동 생성
1. **Terraform** (bastion) — SG·VM·port·volume·FIP 관리
2. **Ansible** (bastion) — docker 설치·Cinder 마운트·release의 compose 정의 배포·이미지 pull·`docker compose up`·secret inject
3. **자동화** — release 발행 시 self-hosted runner(bastion)가 `repository_dispatch`로 1·2를 자동 실행 (ADR-0011)

세부 단계: [`docs/setup.md`](../setup.md) · 자동 배포 흐름: [runtime.md](runtime.md).

## 환경 제약 (폐쇄망)

- VM은 외부 인터넷 직접 접근 불가 → engine VM은 인터넷 pull 대신 **bastion이 release의 `docker-compose.yml`·이미지를 대신 받아** 전달 (`delegate_to: localhost`). 현장 appliance는 이미지 tar 동봉 후 `docker load` (ADR-0010·0011)
- agent 바이너리는 bastion에서 다운로드 후 Ansible files 디렉토리에 사전 복사
- (구모델 잔재 — 직접 설치 시) `ppa1.rabbitmq.com` 차단·TimescaleDB PGDG repo 요구: 현재는 공식 컨테이너 이미지(`rabbitmq:3-management`, `postgres:16` + timescaledb) 사용으로 해소됨 (ADR-0004는 직접 설치 모델 한정)
