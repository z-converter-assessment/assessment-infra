# assessment-infra

assessment-engine + agent fleet의 OpenStack 배포 인프라.

- **Terraform**: OpenStack 자원 프로비저닝 (SG·VM·Cinder·FIP) — network·subnet·router는 Horizon 수동 생성 후 `data` source로 참조
- **Ansible**: VM 내 apt 패키지 설치·Cinder 마운트·wheel 배포·systemd 등록
- Docker 없음 — 모든 컴포넌트를 인스턴스 위에 직접 설치

---

## 아키텍처

```
사내망 (FIP :8000)
       │
       ▼
┌─────────────────────────────────────────── engine-subnet 10.0.10.64/26 ──┐
│                                                                           │
│  api-vm (4c/4G)  ←── FIP 부여                                             │
│   uvicorn :8000                                                           │
│       │  AMQP·SQL·Redis                                                   │
│       ▼                                                                   │
│  mq-vm (2c/2G)      cache-vm (1c/1G)      db-vm (2c/4G)                  │
│   rabbitmq-server    redis-server           postgresql-16 + timescaledb   │
│   5672·15672         6379                   5432                          │
│   └─ Cinder 20G                             └─ Cinder 50G                │
│                                                                           │
│  worker-vm (2c/2G)                                                        │
│   assessment-worker (systemd)                                             │
│                                                                           │
│  engine-main (bastion) — Terraform·Ansible 실행 host, FIP 부여            │
└───────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────── agent-subnet 10.0.10.0/26 ────┐
│  Agent-vm (기존 1대, FIP 있음)                                             │
│  Agent-01/02/03 (추후 추가) → AMQP publish → mq-vm                        │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## 사전 조건 (Horizon 수동)

Terraform 실행 전 Horizon 콘솔에서 아래가 생성돼 있어야 한다.

| 자원 | 이름 | CIDR / 비고 |
|---|---|---|
| Network | `zconverter-private-net` | — |
| Subnet | `assessment-engine` | `10.0.10.64/26` — 엔진 VM용 |
| Subnet | `target-vms` | `10.0.10.0/26` — Agent VM용 |
| Router | `assessment-engine` | External Gateway 부착, 두 subnet interface 연결 |
| External network | `external_net` | FIP 발급용 |
| Keypair | `engine-key` | Horizon에 등록됨 |
| Bastion VM | `engine-main` | engine-subnet, FIP 부여 — Terraform·Ansible 실행 host |

---

## Bastion 초기 세팅

> OS: Debian 13 (Trixie)

### 1. 필수 도구 설치

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

### 2. SSH 키 배치

로컬에서 bastion으로 키 전송:

```bash
scp engine-key.pem debian@<bastion-fip>:~/.ssh/engine-key.pem
```

bastion에서 권한 설정:

```bash
chmod 0400 ~/.ssh/engine-key.pem
```

### 3. OpenStack 인증 (Application Credential)

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

Application Credential: Horizon → Identity → Application Credentials에서 발급.  
secret은 생성 시 1회만 노출 — 즉시 기록.

### 4. 레포 Clone

```bash
git clone https://github.com/<org>/assessment-infra.git
cd assessment-infra
```

---

## Terraform

### tfvars 작성

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

채워야 할 값:

```
external_network_name = "external_net"          # openstack network list --external
bastion_sg_name       = "<engine-main의 SG 이름>"  # openstack server show engine-main -f json | jq '.security_groups'
```

flavor 이름은 `openstack flavor list`로 확인 후 매핑.

### 실행

```bash
cd terraform

# 인증 확인 (자원 0개 plan)
terraform init
terraform plan

# 자원 생성
terraform apply
```

### 생성 자원 목록

| 자원 | 이름 | 비고 |
|---|---|---|
| SG | `api-sg` / `mq-sg` / `cache-sg` / `db-sg` / `worker-sg` | — |
| VM | `api-vm` `mq-vm` `cache-vm` `db-vm` `worker-vm` | Debian 13, engine-subnet |
| Cinder | `mq-data` (20G) / `db-data` (50G) | /dev/vdb로 attach |
| FIP | api-vm에 1개 | external_net에서 발급 |

### IP 확인

```bash
terraform output
```

---

## Ansible

### vault.yml 작성

```bash
cd ansible
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
# CHANGEME 채우기
ansible-vault encrypt group_vars/all/vault.yml
echo "<패스워드>" > ~/.vault-pass && chmod 0400 ~/.vault-pass
```

### wheel 사전 배치 (배포 전 필수)

VM은 외부망 접근 없음 — wheel 파일을 bastion에서 미리 다운로드해 `ansible/files/wheels/`에 넣어야 한다.

```bash
cd ansible/files/wheels

# GitHub Release에서 다운로드 (bastion은 외부 접근 가능)
gh release download <TAG> \
  --repo <ORG>/assessment-engine \
  --pattern "*.whl" \
  --pattern "SHA256SUMS"

# 체크섬 검증
sha256sum -c SHA256SUMS --ignore-missing
```

다운로드 후 `ansible/group_vars/all/engine.yml`의 버전 업데이트:

```yaml
engine_version: "0.1.0"   # v 접두사 없이 작성 — wheel 파일명이 v 없이 생성됨
```

> `ansible/files/wheels/*.whl`과 `SHA256SUMS`는 `.gitignore` 처리됨 — git에 커밋하지 말 것.

### inventory.yml 자동 생성

```bash
# 레포 루트에서 실행 — terraform output을 읽어 ansible/inventory.yml 생성
./scripts/gen-inventory.sh
```

> `StrictHostKeyChecking=no`가 inventory에 설정돼 있어 첫 접속 시 known_hosts 확인을 건너뜀.  
> VM 재생성 후 IP가 바뀌면 스크립트를 다시 실행해 inventory를 갱신할 것.

### 실행 순서

`ansible.cfg`에 `inventory`·`vault_password_file`·`pipelining`이 설정돼 있으므로 `cd ansible` 후 실행.  
DB → MQ가 먼저 떠야 api/worker가 접속 가능하므로 순서 지킬 것.

```bash
cd ansible

ansible-playbook playbook-db.yml      # 1. PostgreSQL 16 + TimescaleDB
ansible-playbook playbook-mq.yml      # 2. RabbitMQ (Debian main)
ansible-playbook playbook-cache.yml   # 3. Redis
ansible-playbook playbook-api.yml     # 4. API  (wheel copy → pip install → alembic → systemd)
ansible-playbook playbook-worker.yml  # 5. Worker (wheel copy → pip install → systemd)
```

### 단일 호스트 접속 확인

```bash
cd ansible
ansible db -m ping
```

---

## 디렉토리 구조

```
assessment-infra/
├── docs/
│   └── operations/
│       ├── troubleshooting.md  # 배포 트러블슈팅 기록
│       ├── env.md              # 환경변수 카탈로그
│       └── release.md          # wheel 배포 절차
├── scripts/
│   ├── gen-inventory.sh      # terraform output → ansible/inventory.yml 자동 생성
│   └── gen_inventory.py
├── terraform/
│   ├── versions.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── data.tf               # Horizon 생성 자원 data source
│   ├── security_groups.tf    # SG 6개 (api/mq/cache/db/worker/agent) + ingress rule
│   ├── instances.tf          # VM 5대 (Ubuntu 24.04)
│   ├── volumes.tf            # Cinder 2개 + attach
│   ├── floating_ips.tf       # api-vm FIP
│   ├── outputs.tf            # 사설 IP·FIP·agent_sg_id
│   └── terraform.tfvars.example
└── ansible/
    ├── ansible.cfg           # inventory·vault_password_file·pipelining 설정
    ├── inventory.yml         # gen-inventory.sh로 생성 (gitignore)
    ├── requirements.yml
    ├── files/
    │   └── wheels/           # 배포 전 운영자가 wheel·SHA256SUMS를 여기 배치 (gitignore)
    ├── group_vars/all/
    │   ├── common.yml        # engine_subnet_cidr·pg_version 등 공통 변수
    │   ├── engine.yml        # engine_version·engine_wheel_file
    │   ├── zdm.yml           # zdm_default_ip·zdm_default_user
    │   └── vault.yml.example
    ├── playbook-db.yml
    ├── playbook-mq.yml
    ├── playbook-cache.yml
    ├── playbook-api.yml
    ├── playbook-worker.yml
    └── roles/
        ├── postgres/         # Cinder 마운트 → postgresql-16 + timescaledb 설치 → DB·유저 생성
        ├── rabbitmq/         # Erlang + RabbitMQ 설치 (Debian main) → Cinder 마운트 → vhost·유저 설정
        ├── redis/            # apt install + bind 0.0.0.0
        └── app/              # python3.13 + acl → venv → wheel copy → pip install → systemd
```

---

## Secret·State 관리

| 파일 | 위치 | 권한 | git |
|---|---|---|---|
| Application Credential | `~/.config/openstack/clouds.yaml` | 0600 | 제외 |
| SSH private key | `~/.ssh/engine-key.pem` | 0400 | 제외 |
| Ansible Vault password | `~/.vault-pass` | 0400 | 제외 |
| Terraform state | `terraform/terraform.tfstate` | — | 제외 |
| Vault 암호화 파일 | `ansible/group_vars/all/vault.yml` | — | 포함 (암호화) |
| wheel 배포 파일 | `ansible/files/wheels/` | — | 제외 |

Terraform state는 현재 bastion 로컬 보관.  
멀티 사용자 단계 진입 시 OpenStack Swift backend로 이전 예정.
