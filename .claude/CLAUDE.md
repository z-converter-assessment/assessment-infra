# CLAUDE.md

> 본 레포는 assessment-engine + agent fleet의 OpenStack 배포 인프라.
> 기능 코드는 별도 — assessment-engine repo의 release artifact·contract 활용.

## 본 레포 범위

- Terraform: OpenStack 자원 (SG·VM·port·volume·FIP) — network·subnet·router·keypair는 Horizon 사전 등록, `data` source 또는 variable name으로 참조
- Ansible: VM 안 설정·코드/바이너리 배포·secret inject

## 문서 분기 원칙

- CLAUDE.md는 컨텍스트 상주 시 항상 유의미한 정보만 보유
- 세부는 `docs/` 분기 — 같은 사실은 한 곳에만
- 참조 방향: CLAUDE.md → docs (단방향)
- docs/ref/ 는 격리. 어떤 문서나 코드도 참조 금지

## commit 규칙

- type prefix: feat / fix / chore / refactor / test 중 정확한 분류
- 한글 설명 (subject + body)
- 세부: `docs/commit.md`

## ADR (Architecture Decision Record)

- 결정 시점에 `docs/adr/NNNN-<kebab-title>.md` 작성
- 번호는 4자리 순번 (0001, 0002, …)
- 필수 항목: 컨텍스트 / 결정 / 트레이드오프
- 상태값: Proposed → Accepted → Deprecated (이전 결정 대체 시 번호 유지 + 상태만 변경)
- ADR과 충돌 시 `docs/architecture/` 우선 (ADR=시점 로그, architecture=현재 스냅샷)

## 문서 색인

| 위치 | 답하는 질문 |
|---|---|
| `docs/architecture/overview.md` | 무엇을 만드는가? 외부 의존(assessment-engine repo)은? |
| `docs/architecture/topology.md` | 어디에 배치되어 있는가? (네트워크·VM·SG 매트릭스) |
| `docs/architecture/runtime.md` | 실행 시 어떻게 흐르는가? (메시지·env·배포 흐름) |
| `docs/architecture/components.md` | 각 VM·compose 서비스의 책임·spec·인터페이스는? |
| `docs/architecture/agent-publish.md` | agent CM2 모델·collector·worker connection 분리 메커니즘 |
| `docs/setup.md` | 초기 구축 단계별 가이드 (첫 bastion·OpenStack 부트스트랩) |
| `docs/operations/deploy-walkthrough.md` | 반복 배포 시나리오 (vault → engine → agent 순서) |
| `docs/operations/env-engine.md` | engine VM 환경변수 카탈로그 |
| `docs/operations/env-agent.md` | agent VM 환경변수 카탈로그 |
| `docs/operations/env-audit.md` | engine·agent repo contract 대비 inject 격차 (수정 완료 시 폐기) |
| `docs/operations/troubleshooting.md` | 작업 중 문제 해결 |
| `docs/operations/troubleshooting_CD.md` | CD 파이프라인(self-hosted runner) 오류·판단·조치·결과 기록 |
| `docs/operations/release.md` | release artifact 출처 |
| `docs/adr/` | 의사결정 시점 로그 (0001~) |

## 도구

- Terraform: bastion (Debian 13)에서 실행
- Ansible: bastion (Debian 13)에서 실행
- 인증: Application Credential (clouds.yaml)
- SSH key: engine-key.pem (mode 0400)

## 디렉토리 구조

```
assessment-infra/
├── .claude/CLAUDE.md
├── README.md
├── docs/
│   ├── adr/                              # 의사결정 기록 (0001~) — 시점 로그
│   ├── architecture/                     # 설계 단일 진실 — 현재 스냅샷
│   │   ├── README.md · overview.md · topology.md · runtime.md · components.md
│   │   └── diagrams/topology.svg
│   ├── setup.md                          # 초기 구축 단계별 가이드
│   └── operations/
│       ├── troubleshooting.md · release.md
│       ├── env-engine.md · env-agent.md
├── scripts/                              # gen-inventory.sh · gen_inventory.py
├── engine/                               # assessment-engine 인프라
│   ├── terraform/
│   │   ├── versions.tf · providers.tf · variables.tf · data.tf
│   │   ├── security_groups.tf · instances.tf · volumes.tf · floating_ips.tf
│   │   ├── test.tf · outputs.tf · terraform.tfvars.example
│   └── ansible/
│       ├── ansible.cfg · requirements.yml · inventory.yml (gitignore)
│       ├── inventory.localhost.yml        # 현장 appliance (connection=local)
│       ├── group_vars/all/{common,engine,ai,zdm,vault}.yml
│       ├── playbook-engine.yml            # compose stack 배포
│       ├── playbook-ai.yml                # Ollama + diagnostic-worker
│       ├── playbook-field.yml             # 현장 appliance 로컬 적용
│       └── roles/{engine_compose, ollama, app(레거시)}
└── agent/                                # assessment-agent 테스트 환경 (30대+)
    ├── terraform/
    │   ├── versions.tf · providers.tf · variables.tf · data.tf
    │   ├── instances.tf · windows.tf · outputs.tf · terraform.tfvars.example
    └── ansible/                          # (compose와 별개로 fleet refactor 진행 — 트리는 실파일 기준)
        ├── ansible.cfg · inventory.yml (gitignore)
        ├── group_vars/all/{vars,vault}.yml
        ├── site.yml · deploy.yml · services.yml · health-check.yml · noise.yml
        └── roles/{agent_binary, agent_env, agent_service, common,
                   service_{db,cache,mq,web,app,container,monitor}, noise·noise_*}
```

## 아키텍처 요약

상세는 `docs/architecture/`. 여기는 작업 시 자주 참조하는 핵심만.

- **VM**: engine-vm 1대(docker compose: api·consumer·postgres·rabbitmq·redis) + ai-vm 1대(Ollama + diagnostic-worker) + agent 플릿(30대+·OS 8종+) + bastion 1
- **네트워크**: engine-subnet `10.0.10.0/24` / agent-subnet `10.0.20.0/24` — Horizon 수동
- **FIP**: engine-vm(API:8000) + Bastion만. 나머지 사설 IP only
- **파이프라인**: Horizon → Terraform → Ansible. release 발행 시 bastion self-hosted runner가 `repository_dispatch`로 자동 실행 (ADR-0011)
- **배포 모델**: 단일 노드 + docker compose (ADR-0010 — ADR-0003 직접설치 모델 대체·Deprecated). 검증 환경(OpenStack)과 현장 appliance가 **같은 compose 정의 공유** — 현장은 마운트 소스만 host disk로 교체
- **deploy 주의**: 워크플로는 **main HEAD에서 실행** — 배포 로직 수정은 dispatch 전에 main에 머지돼야 반영됨

VM 책임·spec 테이블·SG 매트릭스: `docs/architecture/components.md` / `topology.md`.

## 환경·OS·핵심 개념

작업 시 상시 필요한 도메인 지식.

### OS (Debian 13 Trixie) — ADR-0006

- 모든 엔진 VM OS: **Debian 13 (Trixie)**
- SSH 기본 접속 계정: `debian`
- Python: 3.13 (Trixie 기본) — `python3` / `python3-venv` 패키지
- site-packages 경로: `lib/python3.13/site-packages/`

### 환경 제약 (폐쇄망)

- VM은 외부 인터넷 직접 접근 불가 → engine은 **bastion이 release의 `docker-compose.yml`·이미지를 대신 받아** 전달(`delegate_to: localhost`), agent 바이너리는 bastion에서 받아 files 디렉토리에 사전 복사
- engine 컴포넌트는 **공식 컨테이너 이미지**(`postgres:16`+timescaledb, `rabbitmq:3-management`, `redis:7`) 사용 — 구모델 직접설치 제약(RabbitMQ Cloudsmith 차단 ADR-0004, TimescaleDB PGDG repo)은 compose 전환으로 해소
- (참고) ADR-0004·PGDG 등 직접설치 관련 제약은 ADR-0003 모델 한정 — 현재 engine엔 미적용, agent 로컬 서비스(직접 apt 설치)엔 여전히 유효 가능

### assessment-engine 패키지 구조 (배포 시 참고)

- API 엔트리포인트: `assessment_engine.web.main:app` (uvicorn ExecStart)
- Worker 엔트리포인트: `python -m assessment_engine.consumer` (`__main__.py` 방식, console script 없음)
- Alembic: compose `migrate` init-container가 `upgrade head` 1회 실행 (api·consumer는 `depends_on`으로 대기). 구모델 playbook-api alembic task 폐기
- release 자산: `docker-compose.yml`·`env.example`·GHCR 이미지·wheel(`assessment_engine-{version}-py3-none-any.whl`)·SHA256SUMS. **release 태그는 `v` 접두사**(`v0.4.1`) — compose 다운로드 URL에 `v{{ engine_version }}` 필수
- 환경변수 키: `docs/operations/env-engine.md` 참조

### 인증·운영

- Application Credential: clouds.yaml에 ID/Secret. member role scope 충분. secret 1회 노출 후 재확인 불가
- bootstrap 패턴: 첫 ops host(bastion) 1대만 수동 생성, 이후 IaC
- network·subnet·router·keypair는 Horizon 수동 생성 후 Terraform `data`/`variable`로 참조 — Terraform으로 재생성 금지

### SSH 운영

- `~/.ssh/config`의 ProxyJump bastion으로 사설망 VM 우회 접속
- VM 재생성 시 known_hosts 충돌 → `ssh-keygen -R`로 해소
- machine-id 충돌은 application-level dedup 문제, snapshot 복제 시 빈번

### Terraform·OpenStack 핵심

- Provider = plugin 바이너리. `terraform init`이 다운로드
- Resource = 자원 1개. `<type>.<local_name>.<attr>` 형식으로 참조 → 자동 의존성 그래프
- State = `.tfstate` JSON. 자원 ID 매핑. git commit 금지
- plan = dry-run / apply = 실제 적용 + state 갱신
- Floating IP NAT은 Router에서 수행 — Router 없으면 FIP 동작 X
- Security Group = 하이퍼바이저 측 방화벽. OS firewall과 AND 게이트
- Tenant = Project. Application Credential의 scope = 본인 project

## engine 배포 — compose (ADR-0010·0011)

1. assessment-engine release(`v{version}`)에 `docker-compose.yml`·`env.example`·GHCR 이미지 게시
2. `engine/ansible/group_vars/all/engine.yml`의 `engine_version` 갱신 (또는 dispatch payload로 override)
3. `playbook-engine.yml` 실행 → bastion이 compose 정의 받아 engine-vm 전달 → `docker compose pull` → `up -d`

수동 재트리거:
```
gh api repos/:owner/:repo/dispatches -f event_type=engine-release -F client_payload[engine_version]=X.Y.Z
```

상세 흐름·alembic·agent 바이너리 배포: `docs/architecture/runtime.md`.

## 운영 정책

### Secret

- Ansible Vault — `~/.vault-pass` 파일로 복호화 (mode 0400, bastion 로컬 only)
- 평문 commit OK: `*.example` 파일
- 암호화 commit OK: `group_vars/all/vault.yml` (Vault 암호화 후)
- gitignore: `*.pem`, `*.key`, `terraform.tfvars`, `inventory.yml`, `*.tfstate*`

### State

- 시작: bastion 로컬 (`terraform/terraform.tfstate`)
- 백업: bastion 외부 주기 cp (별도 결정)
- 멀티 사용자 단계 진입 시 OpenStack Swift backend 이전 — 별도 ADR로 결정

### 인증 자산 분리

| 자산 | 위치 | 권한 |
|---|---|---|
| Application Credential | `~/.config/openstack/clouds.yaml` | 0600 |
| SSH private key | `~/.ssh/engine-key.pem` | 0400 |
| Vault password | `~/.vault-pass` | 0400 |
| Terraform state | `terraform/terraform.tfstate` | 0600 |

## 보류된 결정

| 항목 | 결정 대기 사유 | 영향 |
|---|---|---|
| Terraform state remote backend | 멀티 사용자 단계 진입 시 OpenStack Swift backend로 이전 | `versions.tf` backend 블록 |

## 확정된 결정 (코드 반영 완료)

| 항목 | 결정 내용 | 근거 |
|---|---|---|
| Agent Windows 배포 방식 | GitHub Releases에서 bastion에 수동 다운로드 후 Ansible `win_copy`로 주입 | 폐쇄망 — VM에서 외부 직접 접근 불가. ADR-0007 |
| AI VM Ollama 모델 | `gemma2:2b` (Q4, ~1.6 GB) | `engine/ansible/group_vars/all/ai.yml` 반영 |
| Agent 테스트 환경 OS | Linux 7종 × 4대 = 28대 (Debian 13/12, Ubuntu 24.04/22.04, Rocky 9, AlmaLinux 9, CentOS Stream 9) + Windows Server 2022 × 1대(옵션) | Linux: `agent/terraform/variables.tf`, Windows: `agent/terraform/windows.tf` |
| Agent 로컬 서비스 role 구조 | 신규 `postgres-local` · `redis-local` role 작성 (단순 apt 설치) | agent-subnet 라우터 연결로 apt 접근 가능. engine role은 Cinder·TimescaleDB 포함으로 불일치. ADR-0008 |
| Cinder 볼륨 크기 | MQ 20 GB, DB 30 GB | `engine/terraform/volumes.tf` 반영 |
| Agent fleet 별도 repo 분리 | 별도 repo로 분리하지 않음 — 본 레포에서 `agent/` 디렉토리로 함께 관리 | — |
