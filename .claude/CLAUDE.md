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
| `docs/architecture/components.md` | 각 VM의 책임·spec·인터페이스는? |
| `docs/setup.md` | 초기 구축 단계별 가이드 |
| `docs/operations/env-engine.md` | engine VM 환경변수 카탈로그 |
| `docs/operations/env-agent.md` | agent VM 환경변수 카탈로그 |
| `docs/operations/troubleshooting.md` | 작업 중 문제 해결 |
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
│       ├── group_vars/all/{common,engine,zdm}.yml
│       ├── files/wheels/                 # bastion에서 다운로드한 wheel
│       ├── playbook-{db,mq,cache,api,consumer}.yml
│       ├── playbook-ai.yml               # (TBD) Ollama 설치
│       └── roles/{app,postgres,rabbitmq,redis,ollama(TBD)}
└── agent/                                # assessment-agent 테스트 환경 (30대+)
    ├── terraform/
    │   ├── versions.tf · providers.tf · variables.tf · data.tf
    │   ├── instances.tf · outputs.tf · terraform.tfvars.example
    └── ansible/
        ├── ansible.cfg · inventory.yml (gitignore)
        ├── group_vars/all/common.yml
        ├── files/binaries/{assessment-agent-linux, assessment-agent.exe}
        ├── playbook-agent.yml
        ├── playbook-local-services.yml   # (TBD) PostgreSQL·Redis 로컬 설치
        └── roles/{agent, postgres-local(TBD), redis-local(TBD)}
```

## 아키텍처 요약

상세는 `docs/architecture/`. 여기는 작업 시 자주 참조하는 핵심만.

- **VM 8종**: engine 6종(API·MQ·Cache·DB·Consumer·AI) + agent 플릿(30대+·OS 8종+) + bastion 1
- **네트워크**: engine-subnet `10.0.10.0/24` / agent-subnet `10.0.20.0/24` — Horizon 수동
- **FIP**: API VM + Bastion만. 나머지 사설 IP only
- **파이프라인**: Horizon → Terraform → Ansible
- **Docker 없음** (ADR-0003) — 모든 컴포넌트 인스턴스 위에 직접 설치

VM 책임·spec 테이블·SG 매트릭스: `docs/architecture/components.md` / `topology.md`.

## 환경·OS·핵심 개념

작업 시 상시 필요한 도메인 지식.

### OS (Debian 13 Trixie) — ADR-0006

- 모든 엔진 VM OS: **Debian 13 (Trixie)**
- SSH 기본 접속 계정: `debian`
- Python: 3.13 (Trixie 기본) — `python3` / `python3-venv` 패키지
- site-packages 경로: `lib/python3.13/site-packages/`

### 환경 제약 (폐쇄망)

- `ppa1.rabbitmq.com` (Cloudsmith) 차단 → RabbitMQ는 Debian main repo (ADR-0004)
- TimescaleDB는 `postgresql-16 >= 16.14` 요구 → PGDG repo 필수 (`trixie-pgdg`)
- VM은 외부 인터넷 직접 접근 불가 → wheel·바이너리는 bastion에서 다운로드 후 Ansible files 디렉토리에 사전 복사

### assessment-engine 패키지 구조 (배포 시 참고)

- API 엔트리포인트: `assessment_engine.web.main:app` (uvicorn ExecStart)
- Worker 엔트리포인트: `python -m assessment_engine.consumer` (`__main__.py` 방식, console script 없음)
- Alembic: `_alembic.ini`·`_migrations/` (언더스코어) — `migrations/` symlink 필요
- wheel 파일명: `assessment_engine-{version}-py3-none-any.whl` (`v` 접두사 없음)
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

## wheel 배포 — Option A

1. bastion에서 GitHub Releases의 wheel 다운로드 → `engine/ansible/files/wheels/`
2. `engine/ansible/group_vars/all/engine.yml`의 `engine_version` 갱신
3. `playbook-api.yml` 또는 `playbook-consumer.yml` 실행

상세 흐름·alembic 단계·agent 바이너리 배포: `docs/architecture/runtime.md`.

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
| Agent 테스트 환경 OS | Debian 13/12, Ubuntu 24.04/22.04, Rocky 9, AlmaLinux 9, CentOS Stream 9, Windows Server 2022 (총 32대) | `agent/terraform/variables.tf` 반영 |
| Agent 로컬 서비스 role 구조 | 신규 `postgres-local` · `redis-local` role 작성 (단순 apt 설치) | agent-subnet 라우터 연결로 apt 접근 가능. engine role은 Cinder·TimescaleDB 포함으로 불일치. ADR-0008 |
| Cinder 볼륨 크기 | MQ 20 GB, DB 30 GB | `engine/terraform/volumes.tf` 반영 |
| Agent fleet 별도 repo 분리 | 별도 repo로 분리하지 않음 — 본 레포에서 `agent/` 디렉토리로 함께 관리 | — |
