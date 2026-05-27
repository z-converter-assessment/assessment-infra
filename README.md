# assessment-infra

assessment-engine + agent fleet의 OpenStack 배포 인프라.

- **Terraform**: OpenStack 자원 프로비저닝 (SG·VM·Cinder·FIP) — network·subnet·router·keypair는 Horizon 수동 생성
- **Ansible**: VM 내 패키지 설치·Cinder 마운트·wheel/바이너리 배포·systemd 등록
- Docker 없음 — 모든 컴포넌트를 인스턴스 위에 직접 설치 (ADR-0003)

상세 아키텍처: `docs/architecture/` | 초기 구축 절차: `docs/setup.md`

---

## 컴포넌트 구조

```
                              Internet
                                  |
              FIP :22             |            FIP :8000
                |                 |                 |
                v                 |                 v
    ┌──────────────────────┐      |      ┌──────────────────────┐
    │      bastion-vm      │      |      │        api-vm        │
    │     [bastion-sg]     │      |      │       [api-sg]       │
    │      Debian 13       │      |      │    FastAPI  :8000    │
    │  Terraform / Ansible │      |      └──────────────────────┘
    └──────────┬───────────┘                        │
               │                                    │  :5672  [api-sg  → mq-sg]
               │  SSH :22 [bastion-sg]              │  :6379  [api-sg  → cache-sg]
               │  to all engine + agent VMs          │  :5432  [api-sg  → db-sg]
               │
  ─────────────────────────── engine-subnet 10.0.10.0/24 ──────────────────────
  │             │                                    │                         │
  │             ▼                     ┌──────────────┤                         │
  │                                   │    │         │                         │
  │   ┌──────────────────┐  ┌──────────────┐  ┌──────────┐                    │
  │   │      mq-vm       │  │  cache-vm    │  │  db-vm   │                    │
  │   │     [mq-sg]      │  │ [cache-sg]   │  │ [db-sg]  │                    │
  │   │  RabbitMQ        │  │ Redis :6379   │  │ PgSQL    │                    │
  │   │  :5672 / :15672  │  └──────────────┘  │ :5432    │                    │
  │   │  [Cinder 20G]    │                    │[Cinder   │                    │
  │   └──────────────────┘                    │ 30G]     │                    │
  │             ^                   ^          └──────────┘                    │
  │             │ :5672             │ :6379         ^                          │
  │   [worker-sg → mq-sg]  [worker-sg → cache-sg]  │ :5432                   │
  │   [ai-sg    → mq-sg]   [ai-sg    → cache-sg]   │ [worker-sg → db-sg]     │
  │             │                   │               │ [ai-sg    → db-sg]      │
  │   ┌─────────┴───────────────────┴───────────────┴────────┐                │
  │   │              worker-vm  [worker-sg]                   │                │
  │   │              assessment-worker                        │                │
  │   └───────────────────────────────────────────────────────┘                │
  │                          │ :11434  [worker-sg → ai-sg]                     │
  │                          v                                                  │
  │   ┌─────────────────────────────────────────────────────────────┐           │
  │   │                      ai-vm  [ai-sg]                         │           │
  │   │   Ollama :11434 (local)  /  assessment-diagnostic           │           │
  │   │   outbound :5672/:6379/:5432  [ai-sg → mq/cache/db-sg]     │           │
  │   └─────────────────────────────────────────────────────────────┘           │
  │                                                                             │
  ───────────────────────────────────────────────────────────────────────────────

  ─────────────────────── agent-subnet 10.0.20.0/24 ────────────────────────────
  │                                                                             │
  │   ┌──────────────────────────────────┐  ┌──────────────────────────────┐   │
  │   │      agent-vm  (Linux x30)       │  │    agent-vm  (Windows x2)    │   │
  │   │           [agent-sg]             │  │         [agent-sg]           │   │
  │   │   Debian / Ubuntu / RHEL         │  │    Windows Server 2022       │   │
  │   │   SSH :22    <- [bastion-sg]      │  │  WinRM :5985 <- [bastion-sg] │   │
  │   │   assessment-agent               │  │  assessment-agent.exe        │   │
  │   └─────────────────┬────────────────┘  └──────────────┬───────────────┘   │
  │                     │  AMQP :5672  [agent-sg → mq-sg]  │                   │
  │                     └──────────────────────────────────┘                   │
  │                                    │ to mq-vm                              │
  ───────────────────────────────────────────────────────────────────────────────
```

---

## 사전 조건 — Horizon 수동 생성

Terraform 실행 전 아래 자원이 Horizon에 존재해야 한다.

| 자원 | 이름 | 비고 |
|---|---|---|
| Network | `zconverter-private-net` | — |
| Subnet (engine) | `assessment-engine` | `10.0.10.0/24` |
| Subnet (agent) | `target-vms` | `10.0.20.0/24` |
| Router | `assessment-engine` | External Gateway + 두 subnet interface |
| External network | `external_net` | FIP 발급용 |
| Keypair | `engine-key` | Terraform이 이름만 참조 |
| Bastion VM | `engine-main` | engine-subnet, FIP 부여, Debian 13 |

---

## Part 1. Bastion 구축

> Bastion(`engine-main`)은 Terraform 관리 대상이 아님. Horizon에서 수동 생성 후 아래 초기 세팅 진행.

### 1-1. 필수 도구 설치

```bash
sudo apt update && sudo apt install -y \
  git curl gnupg lsb-release \
  python3 python3-pip python3-venv \
  ansible \
  python3-openstackclient
```

**Terraform**

```bash
wget -O /tmp/hashicorp.gpg https://apt.releases.hashicorp.com/gpg
sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg /tmp/hashicorp.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
terraform version
```

**Ansible 컬렉션**

```bash
ansible-galaxy collection install -r engine/ansible/requirements.yml
ansible-galaxy collection install -r agent/ansible/requirements.yml
```

### 1-2. SSH 키 배치

로컬에서 bastion으로 키 전송:

```bash
scp engine-key.pem debian@<bastion-fip>:~/.ssh/engine-key.pem
```

bastion에서 권한 설정:

```bash
chmod 0400 ~/.ssh/engine-key.pem
```

### 1-3. OpenStack 인증 (Application Credential)

```bash
mkdir -p ~/.config/openstack
cat > ~/.config/openstack/clouds.yaml << 'EOF'
clouds:
  openstack:
    auth:
      auth_url: https://<keystone-endpoint>:5000/v3
      application_credential_id: <credential-id>
      application_credential_secret: <credential-secret>
    region_name: RegionOne
    interface: public
    identity_api_version: 3
    auth_type: v3applicationcredential
EOF
chmod 0600 ~/.config/openstack/clouds.yaml
```

> Application Credential: Horizon → Identity → Application Credentials에서 발급.
> secret은 생성 시 **1회만 노출** — 즉시 기록.

인증 확인:

```bash
openstack server list
```

### 1-4. 레포 Clone

```bash
git clone https://github.com/<org>/assessment-infra.git
cd assessment-infra
```

---

## Part 2. Engine 환경 구축

### 2-1. Terraform

#### tfvars 작성

```bash
cp engine/terraform/terraform.tfvars.example engine/terraform/terraform.tfvars
```

필수 입력값:

```hcl
external_network_name = "external_net"   # openstack network list --external
bastion_sg_name       = "TODO"           # openstack server show engine-main -f json | jq '.security_groups'
```

flavor 이름은 `openstack flavor list`로 확인 후 매핑. image 이름은 `openstack image list --status active`로 확인.

#### 실행

```bash
cd engine/terraform

terraform init
terraform plan    # dry-run — 생성 예정 자원 확인
terraform apply
```

생성되는 자원:

| 자원 | 이름 | 비고 |
|---|---|---|
| SG | `api-sg` · `mq-sg` · `cache-sg` · `db-sg` · `worker-sg` · `ai-sg` | 7종 |
| VM | `api-vm` · `mq-vm` · `cache-vm` · `db-vm` · `worker-vm` · `ai-vm` | Debian 13 |
| Cinder | `mq-data` · `db-data` | `/dev/vdb` attach |
| FIP | api-vm 1개 | external_net에서 발급 |

IP 확인:

```bash
terraform output
```

### 2-2. Ansible

#### vault.yml 작성

```bash
cd engine/ansible
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
# CHANGEME 항목을 실제 값으로 교체
vi group_vars/all/vault.yml

ansible-vault encrypt group_vars/all/vault.yml
echo "<패스워드>" > ~/.vault-pass && chmod 0400 ~/.vault-pass
```

> `vault_mq_*` 값은 agent vault.yml과 **반드시 동일하게** 설정 — agent가 같은 MQ에 접속.

#### wheel 사전 배치

VM은 외부망 접근 불가 — bastion에서 미리 다운로드해야 한다.

```bash
cd engine/ansible/files/wheels

gh release download <TAG> \
  --repo <ORG>/assessment-engine \
  --pattern "*.whl" \
  --pattern "SHA256SUMS"

sha256sum -c SHA256SUMS --ignore-missing
```

다운로드 후 `engine/ansible/group_vars/all/engine.yml`의 버전 업데이트:

```yaml
engine_version: "0.1.0"   # v 접두사 없이 작성
```

> `files/wheels/*.whl` · `SHA256SUMS`는 `.gitignore` 처리 — git에 커밋하지 말 것.

#### inventory 생성

```bash
# 레포 루트에서 실행 — terraform output을 읽어 engine/ansible/inventory.yml 생성
./scripts/gen-inventory.sh
```

> VM 재생성 후 IP가 변경되면 스크립트를 다시 실행해 갱신.

#### 접속 확인

```bash
cd engine/ansible
ansible all -m ping
```

#### Playbook 실행 순서

`ansible.cfg`에 `inventory` · `vault_password_file` · `pipelining`이 설정되어 있으므로 `cd engine/ansible` 후 실행.
DB → MQ가 먼저 떠야 api · worker가 접속 가능하므로 **순서를 반드시 지킬 것**.

```bash
cd engine/ansible

ansible-playbook playbook-db.yml      # 1. PostgreSQL 16 + TimescaleDB (PGDG repo)
ansible-playbook playbook-mq.yml      # 2. RabbitMQ (Debian main repo — ADR-0004)
ansible-playbook playbook-cache.yml   # 3. Redis
ansible-playbook playbook-api.yml     # 4. API  (wheel → venv → alembic upgrade → systemd)
ansible-playbook playbook-worker.yml  # 5. Worker (wheel → venv → systemd)
```

> `playbook-ai.yml` (Ollama)은 모델 선택 확정 후 추가 예정 (TBD).

---

## Part 3. Agent 테스트 환경 구축

### 3-1. Terraform

#### tfvars 작성

```bash
cp agent/terraform/terraform.tfvars.example agent/terraform/terraform.tfvars
```

필수 입력값:

```hcl
bastion_sg_name = "TODO"   # openstack server show engine-main -f json | jq '.security_groups'
```

OS별 이미지 이름은 `openstack image list --status active`로 확인 후 `agent_os_map`을 override:

```hcl
agent_os_map = {
  debian13 = {
    image_name = "debian13_x64_uefi_3G"
    family     = "debian"
    ssh_user   = "debian"
    count      = 4
  }
  # ubuntu22, centos9, rocky9, windows2022 등 환경 가용 이미지에 맞게 설정
}
```

> 기본값(총 32대)은 `agent/terraform/variables.tf` 참조. 이미지 가용성 확인 후 count 조정.

#### 실행

```bash
cd agent/terraform

terraform init
terraform plan
terraform apply
```

생성되는 자원:

| 자원 | 비고 |
|---|---|
| `agent-sg` | agent fleet 공용 SG |
| `agent-vm-*` × N | OS별 그룹 (Linux + Windows) |

IP 확인:

```bash
terraform output
```

### 3-2. Ansible

#### vault.yml 작성

```bash
cd agent/ansible
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
# vault_mq_* 를 engine vault.yml과 동일한 값으로 설정
vi group_vars/all/vault.yml

ansible-vault encrypt group_vars/all/vault.yml
# ~/.vault-pass가 이미 있으면 생략
```

#### agent 바이너리 사전 배치

```bash
# bastion에서 GitHub Releases 또는 내부 저장소에서 다운로드
ls agent/ansible/files/binaries/
# assessment-agent-linux   (Linux 배포 바이너리)
# assessment-agent.exe     (Windows 배포 바이너리)
```

#### inventory 생성

```bash
# 레포 루트에서 실행 — agent/terraform output을 읽어 agent/ansible/inventory.yml 생성
./scripts/gen-inventory.sh --target agent
```

#### 접속 확인

```bash
cd agent/ansible
ansible all -m ping
```

#### Playbook 실행

```bash
cd agent/ansible

ansible-playbook playbook-agent.yml          # agent 바이너리 배포 + systemd (Linux)
# ansible-playbook playbook-agent-win.yml    # Windows 배포 (WinRM 설정 확정 후 추가 예정 — TBD)
# ansible-playbook playbook-local-services.yml  # 로컬 PostgreSQL·Redis 설치 (TBD)
```

---

## Secret · State 관리

| 파일 | 위치 | 권한 | git |
|---|---|---|---|
| Application Credential | `~/.config/openstack/clouds.yaml` | 0600 | 제외 |
| SSH private key | `~/.ssh/engine-key.pem` | 0400 | 제외 |
| Ansible Vault password | `~/.vault-pass` | 0400 | 제외 |
| Terraform state | `{engine,agent}/terraform/terraform.tfstate` | — | 제외 |
| Vault 암호화 파일 | `*/ansible/group_vars/all/vault.yml` | — | 포함 (암호화) |
| wheel · 바이너리 | `*/ansible/files/` | — | 제외 |

Terraform state는 현재 bastion 로컬 보관.
멀티 사용자 단계 진입 시 OpenStack Swift backend로 이전 예정.
