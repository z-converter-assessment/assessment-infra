# assessment-infra

assessment-engine + agent fleet의 OpenStack 배포 인프라.

- **Terraform**: OpenStack 자원 프로비저닝 (SG·keypair·VM·volume·FIP)
- **Ansible**: VM 내 설정·코드 배포·secret 주입
- network·subnet·router는 Horizon 수동 생성 후 `data` source로 참조

---

## 최종 구성 다이어그램 
┌──────────────────────────────────────────────────────────────────────┐
│       Host                                                           │
│         │                                                            │
│         │ FIP                                                        │
│         ▼                                                            │
│  ┌──────────────────────┐    engine-subnet (10.0.10.0/24)            │
│  │ API VM (4c/4G)       │                                            │
│  │   docker compose:    │                                            │
│  │   - migrate (1회)     │                                            │
│  │   - web (8000)       │                                            │
│  └──────┬───────────────┘                                            │
│         │                                                            │
│         │  AMQP·Redis·SQL                                            │
│         ▼                                                            │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐                 │
│  │ MQ VM       │  │ Cache VM     │  │ DB VM        │                 │
│  │ (2c/2G)     │  │ (1c/1G)      │  │ (2c/4G)      │                 │
│  │  rabbitmq   │  │  redis       │  │  postgres    │                 │
│  │  5672·15672 │  │  6379        │  │  5432        │                 │
│  └─────┬───────┘  └──────────────┘  └─────┬────────┘                 │
│        │ Cinder                            │ Cinder                  │
│        ▲                                   ▲                         │
│        │                                   │                         │
│  ┌─────┴───────────────────────────────────┴────┐                    │
│  │ Worker VM (2c/2G)                            │                    │
│  │   docker compose:                            │                    │
│  │   - consumer (server.* 컨슈머)               │                    │
│  │   - diagnostic-worker                        │                    │
│  │   - diagnostic-scheduler                     │                    │
│  └──────────────────────────────────────────────┘                    │
│                                                                      │
│                                                                      │
│  ┌──────────────────────────────────────────────┐                    │
│  │ agent-subnet (10.0.20.0/24)                  │                    │
│  │  Agent-01 (1c/1G)                            │                    │
│  │  Agent-02 (1c/1G)  ─→ AMQP publish ─→ MQ VM  │                    │
│  │  Agent-03 (1c/1G)                            │                    │
│  └──────────────────────────────────────────────┘                    │
│                                                                      │
│  ┌──────────────────────────────────────────────┐                    │
│  │ bastion (기존, 수동 생성)                       │                    │
│  │  - Terraform·Ansible 실행 host                │                    │
│  │  - ProxyJump 거점                             │                    │
│  └──────────────────────────────────────────────┘                    │
└──────────────────────────────────────────────────────────────────────┘

## 사전 조건 (Horizon 수동)

Terraform 실행 전 Horizon 콘솔에서 아래를 생성해야 한다.

1. Neutron network 1개
2. engine-subnet (`10.0.10.0/24`) + agent-subnet (`10.0.20.0/24`)
3. Router → External Gateway 부착 → 두 subnet에 interface 추가
4. Bootstrap VM 1대 (engine-subnet 배치, FIP 부여) — 이 VM이 bastion 역할

---

## Bastion VM 초기 세팅

> OS: Debian 12 (Bookworm)  
> 엔진·에이전트 VM도 동일 이미지 사용

### 1. 필수 도구 설치

```bash
sudo apt update && sudo apt install -y \
  git \
  curl \
  gnupg \
  lsb-release \
  software-properties-common \
  python3 \
  python3-pip \
  python3-venv
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

**Ansible**

```bash
# Debian 12 공식 패키지 (2.14+)
sudo apt install -y ansible
ansible --version
```

**gh CLI** (GitHub Releases wheel 다운로드용)

```bash
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
  https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list

sudo apt update && sudo apt install -y gh
gh --version
```

---

### 2. SSH 키 배치

로컬에서 bastion으로 IaC 키를 전송한다.

```bash
# 로컬에서 실행
scp IaC.pem <bastion-user>@<bastion-fip>:~/.ssh/IaC.pem
```

bastion에서 권한 설정:

```bash
chmod 0400 ~/.ssh/IaC.pem
```

내부 VM ProxyJump 설정 (`~/.ssh/config`):

```
Host bastion
  HostName <bastion-fip>
  User debian
  IdentityFile ~/.ssh/IaC.pem

Host 10.0.10.*
  User debian
  IdentityFile ~/.ssh/IaC.pem
  ProxyJump bastion

Host 10.0.20.*
  User debian
  IdentityFile ~/.ssh/IaC.pem
  ProxyJump bastion
```

---

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

Application Credential은 Horizon → Identity → Application Credentials에서 발급.  
secret은 생성 시 1회만 노출되므로 즉시 기록.

---

### 4. 레포 Clone

```bash
git clone https://github.com/<org>/assessment-infra.git
cd assessment-infra
```

---

### 5. Terraform 초기화 및 인증 검증

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars`를 열어 실제 값으로 수정한다.  
값은 Horizon 콘솔에서 확인 (Network → Networks, Compute → Images·Flavors).

```bash
terraform init
terraform plan   # 자원 0개 — OpenStack API 인증 통과 확인 목적
```

`plan`이 에러 없이 완료되면 인증·네트워크 연결 정상.

---

## 운영 루틴

### 인프라 변경 (Terraform)

```bash
cd ~/assessment-infra
git pull
cd terraform
terraform plan
terraform apply
```

### 코드 배포 (Ansible)

```bash
cd ~/assessment-infra
git pull
cd ansible
ansible-playbook -i inventory.yml playbook-api.yml
```

### wheel 수동 배포 (GitHub Release)

```bash
# 최신 릴리즈 다운로드
gh release download v<X.Y.Z> \
  --repo <org>/assessment-engine \
  --pattern '*.whl' --pattern 'SHA256SUMS' \
  --dir /tmp/release

# 무결성 검증
cd /tmp/release && sha256sum -c SHA256SUMS

# Ansible에 버전 전달
ansible-playbook -i inventory.yml playbook-api.yml \
  -e "assessment_engine_version=X.Y.Z"
```

---

## 디렉토리 구조

```
assessment-infra/
├── terraform/
│   ├── versions.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── data.tf
│   ├── security_groups.tf
│   ├── keypair.tf
│   ├── instances-engine.tf
│   ├── instances-agent.tf
│   ├── volumes.tf
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

## Secret 관리

| 파일 | 위치 | 권한 | git |
|------|------|------|-----|
| Application Credential | `~/.config/openstack/clouds.yaml` | 0600 | 제외 |
| SSH private key | `~/.ssh/IaC.pem` | 0400 | 제외 |
| Ansible Vault password | `~/.vault-pass` | 0400 | 제외 |
| Terraform state | `terraform/terraform.tfstate` | 0600 | 제외 |
| Vault 암호화 파일 | `ansible/group_vars/all/vault.yml` | — | 포함 (암호화) |
