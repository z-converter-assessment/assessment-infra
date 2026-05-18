# CLAUDE.md

> 본 레포는 assessment-engine + agent fleet의 OpenStack 배포 인프라.
> 기능 코드는 별도 — assessment-engine repo의 release artifact·contract 활용.

## 본 레포 범위

- Terraform: OpenStack 자원 (SG·keypair·VM·volume·FIP) — network·subnet·router는 Horizon에서 사전 수동 생성, `data` source로 참조
- Ansible: VM 안 설정·코드 배포·secret inject

## 의존 contract (assessment-engine repo)

| 자산 | 위치 | 용도 | CI 의존 |
|---|---|---|---|
| 환경변수 카탈로그 | `docs/operations/env.md` | inject할 키 목록 | X |
| prod contract | `docs/operations/prod-contract.md` | secret 채널·weak default 거부 정책 | X |
| 메시지 schema | `docs/architecture/agent.md` | agent ↔ broker 페이로드 | X |
| 디렉토리 구조 ref | `docs/ref/cd-repo-guide.md` + `agent-fleet-infra-guide.md` | 본 레포의 디자인 ref | X |
| release artifact | `docs/operations/release.md` | wheel·sdist·SHA256SUMS 다운로드 | **O — CI 완성 후 활성** |
| 배포 단계 | `docs/operations/deployment.md` | install·systemd 절차 | **O — wheel install step** |

## 도구

- Terraform: Windows jump server PowerShell에서 실행
- Ansible: Windows jump server PowerShell에서 실행 (또는 bootstrap VM)
- 인증: Application Credential (clouds.yaml)
- SSH key: IaC.pem (mode 0400)

## 디렉토리 구조

```
assessment-infra/
├── CLAUDE.md
├── README.md
├── .gitignore
├── docs/
│   ├── adr/                          # 본인이 작성하는 의사결정 기록
│   └── architecture.md               # 네트워크·VM 토폴로지 그림
├── terraform/
│   ├── versions.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── data.tf                       # Horizon 생성 자원 data source (network·subnet)
│   ├── security_groups.tf
│   ├── keypair.tf
│   ├── instances-engine.tf           # API·MQ·DB·Worker VM
│   ├── instances-agent.tf            # Agent VM N대
│   ├── volumes.tf                    # Cinder
│   ├── floating_ips.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
└── ansible/
    ├── inventory.tpl.yml
    ├── group_vars/all/vault.yml.example
    ├── playbook-db.yml
    ├── playbook-mq.yml
    ├── playbook-api.yml
    ├── playbook-worker.yml
    ├── playbook-agent.yml
    └── roles/
```

## 결정된 아키텍처

### 네트워크

- Neutron private network·subnet·router는 **Horizon에서 수동 생성** (Terraform 관리 대상 아님)
  - Terraform은 `data "openstack_networking_network_v2"` / `data "openstack_networking_subnet_v2"` 로 참조
- Subnet 2개:
  - engine-subnet `10.0.10.0/24` — 엔진 컴포넌트 VM
  - agent-subnet `10.0.20.0/24` — Agent VM
- Router 1개:
  - External Gateway 부착 (Floating IP NAT 담당)
  - 두 subnet에 internal interface 부착
- 보안 격리는 Security Group (SG) — subnet은 IP 관리·조직화 목적이지 보안 경계 아님
- Floating IP (FIP): API VM만 부여 (bootstrap VM은 Horizon에서 직접 부여). 나머지는 사설 IP only
- Bootstrap VM: Horizon에서 수동 생성한 첫 VM — 이후 Terraform이 나머지 VM 관리

### 엔진 컴포넌트 VM

| VM | spec | 상태 | 외부 노출 | 비고 |
|---|---|---|---|---|
| API | 4 vCPU / 4 GB | Stateless | 8000 (FIP) | RabbitMQ와 lifecycle 분리 위해 별도 |
| MQ | 2 vCPU / 2 GB | Stateful | X (사설 5672·15672) | Cinder 볼륨에 RabbitMQ 데이터 디렉토리 마운트 |
| DB | 2 vCPU / 4 GB | Stateful | X | Cinder 볼륨에 PostgreSQL 데이터 디렉토리 마운트 |
| Worker+Scheduler | 2 vCPU / 2 GB | — | X | diagnose worker + scheduler 합침. 트래픽 증가 시 분리 |

- Alembic 마이그레이션: API VM의 배포 단계 one-shot job (별도 VM X). ADR 0005 정독 후 최종 확정.
- Redis: 처우 보류. ADR 0001 정독 후 유지/제거 결정.

### Agent VM

- N대 (학습 단계 3대 시작)
- 1 vCPU / 1 GB / 20 GB
- agent-subnet 배치, Floating IP 없음
- bastion 경유 SSH (ProxyJump)
- machine-id 충돌 방지 — cloud-init에서 `rm /etc/machine-id && systemd-machine-id-setup` 자동화

### 도구 파이프라인

0. **Horizon** (웹 UI) — network·subnet·router·bootstrap VM 수동 생성
1. **Terraform** (Windows jump server PowerShell에서 실행) — SG·keypair·VM·volume·FIP (기존 network은 data source 참조)
2. **cloud-init** (각 VM user-data) — hostname·docker 설치·machine-id 재생성 등 첫 부팅 자동화
3. **Ansible** (Windows jump server 또는 bootstrap VM에서 실행) — VM에 SSH 푸시, compose 파일·env·secret 배포, 서비스 기동
4. **docker compose** (각 VM 내부) — 컴포넌트 컨테이너 기동

## 단계별 마일스톤

진행 순서 (각 단계 끝에 `terraform plan` → 결과 해석 → `apply` → state 확인):

### 사전 작업 (Horizon 수동)

0-a. Neutron network 1개 생성
0-b. engine-subnet (`10.0.10.0/24`) + agent-subnet (`10.0.20.0/24`) 생성
0-c. Router 생성 → External Gateway 부착 → 두 subnet에 interface 추가
0-d. Bootstrap VM 1대 생성 → engine-subnet 배치 → FIP 부여 (Windows에서 SSH 접근용)

### Terraform 단계 (Windows PowerShell에서 실행)

1. providers.tf + versions.tf 작성 → `terraform init` → 자원 0개 plan 검증 (인증 통과 확인)
2. data.tf — 기존 network·subnet data source 선언 (Horizon에서 만든 자원 참조)
3. security_groups.tf — SG 정의 (API·MQ·DB·Worker·Agent별)
4. keypair.tf — OpenStack keypair 등록
5. instances-engine.tf — 엔진 VM 4대 (API·MQ·DB·Worker)
6. volumes.tf — Cinder 볼륨 (MQ·DB 데이터용) + attach
7. floating_ips.tf — API VM에 FIP
8. instances-agent.tf — Agent VM 3대 + cloud-init user-data
9. outputs.tf — IP들 (Ansible inventory 입력)

### Ansible 단계 (Terraform 끝난 후, Windows 또는 bootstrap VM에서 실행)

10. inventory.tpl.yml — Terraform output 기반 inventory.yml 자동 생성
11. roles/docker — Docker 설치 (공통 role)
12. playbook-db.yml — DB VM 기동
13. playbook-mq.yml — MQ VM 기동
14. playbook-api.yml — API VM 기동 (wheel install + alembic + systemd) ← CI 완성 의존
15. playbook-worker.yml — Worker VM 기동
16. playbook-agent.yml — Agent VM에 agent 바이너리 배포

## 진행 원칙

- 자원 1개씩 빌드업: network → subnet → router → SG → keypair → VM → volume → FIP
- 각 단계마다 `terraform plan` 결과 확인 후 `apply`
- state는 bastion 로컬에 (`terraform/terraform.tfstate`) — 멀티 사용자 단계 시 remote backend (Swift) 이전
- secret은 Ansible Vault — `vault.yml.example`만 commit, `vault.yml`은 gitignore

## 이미 이해한 개념 (재설명 불필요)

### Terraform 핵심

- Provider = plugin 바이너리. `terraform init`이 다운로드
- Resource = 자원 1개. `<type>.<local_name>.<attr>` 형식으로 다른 resource 참조 → 자동 의존성 그래프
- State = `.tfstate` JSON. 자원 ID 매핑 보관. git commit 금지
- plan = dry-run / apply = 실제 적용 + state 갱신
- `.tf` 파일 분리는 가독성 목적. Terraform은 디렉토리 안 모든 .tf를 1 모듈로 처리

### OpenStack 네트워킹

- Floating IP = 외부망 IP의 사설 IP 1:1 NAT 매핑
- Router 역할 2가지: (1) 외부망 ↔ 사설망 게이트웨이 (본 환경 메인 용도), (2) 사설망 ↔ 사설망 라우팅
- Floating IP NAT은 Router에서 수행 — Router 없으면 FIP 동작 X
- Security Group = 하이퍼바이저 측 방화벽. OS firewall과 AND 게이트
- Subnet 분리는 보안 경계 아님 — IP 관리·조직화 목적
- Tenant = Project. Application Credential의 scope = 본인 project

### 인증·운영

- Application Credential: clouds.yaml에 ID/Secret. member role scope 충분. secret 1회 노출 후 재확인 불가
- bootstrap 패턴: 첫 ops host(bastion) 1대만 수동 생성, 이후 IaC
- Terraform·Ansible은 Windows jump server PowerShell에서 실행 (Linux bastion 아님)
- network·subnet·router는 Horizon 수동 생성 후 Terraform `data` source로 참조 — Terraform으로 재생성 금지

### SSH 운영

- ~/.ssh/config의 ProxyJump bastion으로 사설망 VM 우회 접속
- VM 재생성 시 known_hosts 충돌 → `ssh-keygen -R`로 해소
- machine-id 충돌은 application-level dedup 문제, snapshot 복제 시 빈번

## 보류된 결정

다음 항목들은 학습 진행 중 결정. 미결정 상태로 코드 작성 진행 가능하지만 해당 시점 도달 전 확정.

| 항목 | 결정 대기 사유 | 영향 |
|---|---|---|
| Redis VM 유무 | ADR 0001 (redis-decoupling) 정독 필요 — fail-open 정책 채택 후 Redis 역할 축소. 사설망 단일 인스턴스로 충분한지 검토 | volumes.tf에 Redis 볼륨 필요 여부, MQ VM과 합칠지 분리할지 |
| Alembic 실행 위치 | ADR 0005 (db-schema-management) 정독 필요 — migrate init-container 패턴. API VM의 one-shot job vs 별도 migrate VM | playbook-api.yml의 단계 |
| Worker·Scheduler 분리 | 현 트래픽에서 합쳐도 OK 결정. 추후 LLM 도입 시 worker만 분리 | instances-engine.tf 갱신 |
| Terraform state remote backend | bastion 로컬 시작. 멀티 사용자 단계 진입 시 OpenStack Swift backend로 이전 | versions.tf backend 블록 추가 |
| Agent fleet 별도 repo 분리 | 학습 마친 후 검토. 본 레포에 함께 유지 시작 | 디렉토리 구조 |

## CI 의존 — assessment-engine repo

assessment-engine repo의 CI workflow (release.yml)가 완성되면 `v*` tag push 시 GitHub Release에 wheel + sdist + SHA256SUMS가 자동 첨부된다 (ADR 0012). 본 레포의 playbook-api.yml이 이 artifact를 다운로드해 설치.

### 활성화 전 (현재) — placeholder 동작

- playbook-api.yml의 wheel install 단계는 **TODO 주석**으로 표시
- 인프라(Terraform) 작업은 CI 무관 — 전체 진행 가능
- Ansible 단계 중 1~15(Docker·DB·MQ 등)도 CI 무관 — 진행 가능
- playbook-api.yml의 wheel install step만 CI 완성 후 채움

### 활성화 후 — 채울 정보

다음 5개가 확정되면 채운다:

| placeholder | 채울 값 | 출처 |
|---|---|---|
| `assessment_engine_repo` | `<owner>/assessment-engine` | 엔진 담당자 확인 |
| `assessment_engine_version` | `v0.1.0` (첫 release tag) | CI 첫 발사 후 GitHub Releases 페이지 |
| `wheel_url_pattern` | `https://github.com/<owner>/assessment-engine/releases/download/{version}/assessment_engine-{version}-py3-none-any.whl` | assessment-engine `docs/operations/release.md` |
| `sha256sums_url` | 동일 패턴의 `SHA256SUMS` | 동일 |
| `gh_token` | GitHub PAT (private repo면) | 운영자 별도 발급 |

### 채울 위치

- `ansible/group_vars/all/common.yml`에 `assessment_engine_version` 변수 박음
- `ansible/playbook-api.yml`에 wheel install task 추가:
  - get_url로 wheel 다운로드
  - sha256 검증
  - pip install (venv 안)
  - alembic upgrade head
  - systemd unit 작성·start
- 참고: assessment-engine `docs/operations/deployment.md` "단계별 흐름" 절

## Secret·State 운영 정책

### Secret

- Ansible Vault — `~/.vault-pass` 파일로 복호화 (mode 0400, bastion 로컬 only)
- 평문 commit OK: `*.example` 파일 (키 카탈로그·구조 참고용)
- 암호화 commit OK: `group_vars/all/vault.yml` (Vault 암호화 후)
- gitignore: `*.pem`, `*.key`, `terraform.tfvars`, `inventory.yml`, `*.tfstate*`

### State

- 시작: bastion 로컬 (`terraform/terraform.tfstate`)
- 백업: bastion 외부에 주기 cp (별도 결정)
- 멀티 사용자 단계 진입 시: OpenStack Swift backend (`backend "swift" {}`)로 이전 — 별도 ADR로 결정 후 진행

### 인증 자산 분리

| 자산 | 위치 | 권한 |
|---|---|---|
| Application Credential | `~/.config/openstack/clouds.yaml` | 0600 |
| SSH private key | `~/.ssh/IaC.pem` | 0400 |
| Vault password | `~/.vault-pass` | 0400 |
| Terraform state | `terraform/terraform.tfstate` | 0600 |