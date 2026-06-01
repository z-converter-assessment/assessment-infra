# 배포 시나리오 (deploy walkthrough)

현재 코드 상태를 기준으로 한 단계별 배포 가이드. sudo grant·vault symlink·worker 자격 inject·MQ routing 계약·`APP_ENV=production`·ZDM_PACKAGE_* 등 본 repo 의 최근 변경을 모두 반영.

`docs/setup.md` 가 초기 인프라 부트스트랩(첫 bastion 생성·OpenStack credential 발급 등)을 다룬다면, 본 문서는 그 이후 **반복 가능한 배포 절차**를 다룬다.

---

## 0. 사전 준비 (bastion 측)

이미 완료됐다고 가정하는 항목:

- bastion VM 1대 (Debian 13) 수동 생성·SSH 접속 가능
- `~/.config/openstack/clouds.yaml` (Application Credential, mode `0600`)
- `~/.ssh/engine-key.pem` (OpenStack keypair private key, mode `0400`)
- `~/.vault-pass` (Ansible Vault password, mode `0400`)
- Horizon에서 사전 생성:
  - `engine-network` / `engine-subnet` (`10.0.10.0/24`)
  - `agent-network` / `agent-subnet` (`10.0.20.0/24`)
  - `router-1` (subnet 양쪽 연결)
  - keypair (private key는 bastion의 `~/.ssh/engine-key.pem`)
- Terraform · Ansible 설치된 bastion

부트스트랩이 안 됐다면 `docs/setup.md` 먼저.

---

## 1. 🔴 vault 설정 — 가장 먼저, 가장 중요

현재 코드는 `engine_app_env: production` 기본값으로 engine fail-fast 검증이 활성. vault 에 `CHANGEME` 한 항목이라도 남으면 api/consumer/ai 모두 startup 즉시 실패한다.

```bash
cd ~/assessment-infra/engine/ansible

# 1) 평문 vault 작성
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
$EDITOR group_vars/all/vault.yml
```

치환 대상:

| 키 | 값 생성 권장 |
|---|---|
| `vault_db_password` | `openssl rand -base64 24` |
| `vault_mq_password` | `openssl rand -base64 24` |
| `vault_app_secret_key` | `openssl rand -base64 32` |
| `vault_db_user` | 기본 `assessment` 가 weak default 거부 대상 — 다른 이름으로 |
| `vault_mq_user` | 동일 |

```bash
# 2) 암호화
ansible-vault encrypt group_vars/all/vault.yml

# 3) 확인
ansible-vault view group_vars/all/vault.yml | head
```

> `agent/ansible/group_vars/all/vault.yml` 은 위 파일의 **symlink**(ADR-0009 영역). agent 측 `ansible-playbook` 실행이 같은 vault를 자동 로드한다 — 별도 작업 없음. symlink 가 dangling 이면(즉 engine vault 가 아직 없으면) agent role 도 실패하므로 1단계가 항상 선행.

---

## 2. engine VM 6대 생성 — Terraform

```bash
cd ~/assessment-infra/engine/terraform

# 첫 실행만
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars   # network/keypair 이름 등 환경별 값 입력

terraform init
terraform plan -out=plan.out
terraform apply plan.out
```

생성 자원:

| VM | 책임 | FIP | Cinder |
|---|---|:---:|:---:|
| api-vm | uvicorn web 엔트리 + alembic | ✓ | — |
| consumer-vm | `server.*` + `task.result` consume | — | — |
| ai-vm | Ollama + diagnostic-worker | — | — |
| mq-vm | RabbitMQ | — | 20 GB |
| db-vm | PostgreSQL + TimescaleDB | — | 30 GB |
| cache-vm | Redis | — | — |

자원 ID는 `terraform.tfstate` (mode `0600`, git ignore).

---

## 3. engine inventory 생성

```bash
cd ~/assessment-infra
./scripts/gen-inventory.sh
# → engine/ansible/inventory.yml + agent/ansible/inventory.yml 동시 생성
#   (terraform output 에서 IP 추출 → ansible_host 매핑)
```

VM 재생성 시 known_hosts 충돌이 나면:

```bash
ssh-keygen -R <old-ip>
```

---

## 4. engine 배포 — Ansible (순서 의존)

```bash
cd ~/assessment-infra/engine/ansible

# 의존성: db → mq → cache → api → consumer → ai
ansible-playbook playbook-db.yml       # PostgreSQL + TimescaleDB + 계정·DB 생성
ansible-playbook playbook-mq.yml       # RabbitMQ + vhost·user 생성
ansible-playbook playbook-cache.yml    # Redis

ansible-playbook playbook-api.yml      # alembic 1회 + systemd: assessment-api
ansible-playbook playbook-consumer.yml # systemd: assessment-consumer
ansible-playbook playbook-ai.yml       # Ollama + systemd: assessment-diagnostic
```

각 playbook 이 inject 하는 env 카탈로그는 `docs/operations/env-engine.md`.

### 자주 걸리는 곳

| 증상 | 원인 | 해결 |
|---|---|---|
| api startup 직후 `_validate_prod_*` ValueError | vault 에 CHANGEME 잔존 | 1단계 재확인 |
| agent role 실패 (vault read 불가) | engine vault.yml 이 아직 없음 (symlink dangling) | 1단계 미완 |
| install 모달 발행 후 즉시 503 | `zdm_default_ip` 도달 불가 | 폐쇄망 라우팅 확인 |

상세: `docs/operations/troubleshooting.md`.

---

## 5. agent VM 30대+ 생성 — Terraform

```bash
cd ~/assessment-infra/agent/terraform

cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars   # OS 종류·대수, Windows 활성화 여부

terraform init
terraform plan -out=plan.out
terraform apply plan.out
```

생성 자원:

- Linux 7종 × 4대 = 28대 (Debian 13/12, Ubuntu 24.04/22.04, Rocky 9, AlmaLinux 9, CentOS Stream 9)
- Windows Server 2022 × 1대 (옵션 — `windows.tf`)

---

## 6. agent inventory 갱신

```bash
cd ~/assessment-infra
./scripts/gen-inventory.sh
```

`inventory.yml` 은 OS 계층 그룹(`linux/windows` → `debian/ubuntu/rhel` → `debian13/...`) 으로 자동 분류. `services.yml` 의 `agent_services` 가 group_vars 별로 분기.

---

## 7. agent 배포 — Ansible

```bash
cd ~/assessment-infra/agent/ansible

ansible-playbook site.yml
#   → deploy.yml        : common → agent_binary → agent_env → agent_service
#   → services.yml      : 더미 서비스 (service_db/web/cache/mq/...)
#   → noise.yml         : stress-ng + 재시작 timer 등 부하 시나리오
#   → health-check.yml  : 배포 검증
```

### 본 세션 변경이 적용되는 곳

- `common` role
  - `assessment-agent` user 생성
  - `/etc/sudoers.d/assessment-agent` 작성 → NOPASSWD sudo 부여 (`visudo -cf` validate)
- `agent_service` role
  - systemd unit 에서 hardening 다수 제거 (NoNewPrivileges/CapabilityBoundingSet/ProtectSystem 등) → sudo 작동
- `agent_env` role
  - `agent.env` : `WORKER_TASK_*`, `WORKER_DOWNLOAD_ALLOWED_HOSTS=192.168.3.94` 포함
  - `agent.env.local` : `RABBITMQ_USER`/`PASS` + `RABBITMQ_WORKER_USER`/`PASS` (현재 동일 자격 재사용 — ADR-0009)

agent 메시지 흐름 상세: `docs/architecture/agent-publish.md`.

---

## 8. 검증

bastion 에서 ProxyJump 로 각 VM 접속 후:

```bash
# api
ssh api-vm.engine
sudo systemctl status assessment-api
sudo head -20 /opt/assessment/assessment-api.env
# APP_ENV=production, LOG_FORMAT=json, RABBITMQ_EXCHANGE=assessment 등

# consumer
ssh consumer-vm.engine
sudo journalctl -u assessment-consumer -n 50

# ai-vm
ssh ai-vm.engine
sudo systemctl status ollama assessment-diagnostic
curl -sf http://127.0.0.1:11434/api/tags  # gemma2:2b 표시

# agent
ssh debian13-01.agent
sudo systemctl status assessment-agent
sudo journalctl -u assessment-agent -n 30
# "loop mode: interval=60s, ..., worker=on" 보이면 정상
# "RABBITMQ_WORKER_USER unset — worker disabled" 가 보이면 ❌

# broker
ssh mq-vm.engine
sudo rabbitmqctl list_queues name messages consumers
# server.inventory/metrics/error: consumers > 0
# agent.tasks.<composite_id>: 30개+ 떠 있어야 정상
```

---

## 9. 작동 흐름 한눈에

```
[운영자] → api-vm POST /tasks/install
   │ publish to (assessment.tasks, task.install.<composite_id>)
   ▼
[mq-vm]
   │ route to agent.tasks.<composite_id> 큐
   ▼
[agent worker on host #N]
   │ download http://192.168.3.94{ZDM_PACKAGE_PATH}
   │ tar 추출 → ZDM_PACKAGE_SCRIPT 실행 (sudo)
   │ publish to (assessment.tasks, task.result)
   ▼
[consumer-vm] → DB 기록

[agent collector on host #N]  (60s 주기)
   │ publish to (assessment, server.metrics)
   ▼
[consumer-vm] → TimescaleDB metrics 테이블

[운영자] → api-vm UI 에서 diagnostic 요청
   │ publish to (diagnostic.request)  (engine 내부)
   ▼
[ai-vm diagnostic-worker]
   │ Ollama 호출 (http://127.0.0.1:11434, gemma2:2b)
   │ publish to (diagnostic.result)
   ▼
[api-vm] → 사용자 응답
```

---

## 10. 주의사항 (본 세션 변경에서 기인)

| # | 내용 |
|:--:|---|
| 1 | **vault 강한 secret 의무**. `engine_app_env: production` 기본이므로 weak default 자동 거부. 검증을 일시 비활성하려면 `engine.yml` 의 `engine_app_env: staging` 으로 override (`staging` 은 dev 와 동일 동작) |
| 2 | **engine ↔ agent routing key 동기화**. `engine/ansible/group_vars/all/engine.yml::engine_mq_*` 와 `agent/ansible/group_vars/all/vars.yml::mq_*` 양쪽 수정 필요 — 별도 ansible run 이라 자동 공유 안 됨 |
| 3 | **ZDM IP 변경 시 두 곳**. `engine/.../zdm.yml::zdm_default_ip` + `agent/.../vars.yml::worker_download_allowed_hosts`. 후자가 안 맞으면 task.install 이 `url_not_allowed` 로 실패 |
| 4 | **vault symlink dangling 주의**. 새 bastion 에 clone 후 `git status` 에 symlink 만 보이고 실제 `engine/.../vault.yml` 이 없으면 1단계 미수행 상태 |
| 5 | **agent systemd unit 보안 약화 상태**. 진단 기능을 위해 NoNewPrivileges/Capabilities 제거 — host 침해 시 영향 반경이 일반 hardened service 보다 큼. prod 배포 전 자격 분리(ADR-0009 후속) + sudoers scope 좁히기 검토 |

---

## 11. 재배포 (코드만 변경됐을 때)

### engine wheel 교체

```bash
# 1) bastion에서 새 wheel 을 engine/ansible/files/wheels/ 에 복사
# 2) engine/ansible/group_vars/all/engine.yml 의 engine_version 갱신
ansible-playbook playbook-api.yml      # alembic 자동 재실행
ansible-playbook playbook-consumer.yml
ansible-playbook playbook-ai.yml
```

handler dedup 으로 인해 unit·env 파일이 실제로 변경된 host 만 재시작.

### agent 바이너리 교체

```bash
# 1) agent/ansible/files/binaries/ 에 새 바이너리 복사
cd agent/ansible
ansible-playbook deploy.yml
# → agent_binary role 의 sha256 비교 + atomic mv, 변경 시에만 restart
```

---

## 관련 문서

- `docs/setup.md` — 첫 bastion·OpenStack 부트스트랩
- `docs/architecture/runtime.md` — 메시지·env·배포 전체 흐름
- `docs/architecture/agent-publish.md` — agent CM2 모델·publish 메커니즘 상세
- `docs/operations/env-engine.md` — engine VM 환경변수 카탈로그
- `docs/operations/env-agent.md` — agent VM 환경변수 카탈로그
- `docs/operations/env-audit.md` — engine/agent contract 대비 inject 격차 추적
- `docs/operations/troubleshooting.md` — 배포 트러블슈팅 사례집
- `docs/adr/0009-agent-mq-credential-reuse.md` — agent worker 자격 분리·재사용 결정
