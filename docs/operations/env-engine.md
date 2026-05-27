# Engine VM 환경변수 카탈로그

engine VM에 주입되는 환경변수의 단일 진실. 출처·주입 경로·컴포넌트별 필요 여부를 기록한다.

---

## 주입 흐름

```
Ansible Vault                group_vars/all/              inventory.yml
vault.yml (암호화)           common.yml / zdm.yml          (gen-inventory.sh 생성)
  vault_db_password           zdm_default_ip               hostvars['db-vm'].ansible_host
  vault_mq_password           zdm_default_user             hostvars['mq-vm'].ansible_host
  vault_app_secret_key        ai.yml                       hostvars['cache-vm'].ansible_host
                               ollama_api_host
                               ollama_port
          │                        │                              │
          └────────────────────────┴──────────────────────────────┘
                                   │
                        roles/app/templates/app.env.j2
                        → /opt/assessment/<service>.env  (mode 0600)
                                   │
                        systemd EnvironmentFile=
                        → 프로세스 환경변수로 주입
```

변수 출처 3종:
- **Ansible Vault** (`vault.yml`): password 류 secret — `ansible-vault encrypt` 후 git commit
- **group_vars** (`common.yml` / `zdm.yml` / `ai.yml`): 비밀이 아닌 설정값 — 평문 commit
- **hostvars**: `gen-inventory.sh` 실행 후 inventory.yml에 기록된 VM 사설 IP

---

## 컴포넌트별 주입 변수

| 환경변수 | api-vm | consumer-vm | ai-vm | Ansible 출처 |
|---|:---:|:---:|:---:|---|
| `POSTGRES_HOST` | ✓ | ✓ | ✓ | `hostvars['db-vm'].ansible_host` |
| `POSTGRES_PORT` | ✓ | ✓ | ✓ | 고정값 `5432` |
| `POSTGRES_DB` | ✓ | ✓ | ✓ | `vault_db_name` |
| `POSTGRES_USER` | ✓ | ✓ | ✓ | `vault_db_user` |
| `POSTGRES_PASSWORD` | ✓ | ✓ | ✓ | `vault_db_password` (**Vault**) |
| `RABBITMQ_HOST` | ✓ | ✓ | ✓ | `hostvars['mq-vm'].ansible_host` |
| `RABBITMQ_PORT` | ✓ | ✓ | ✓ | 고정값 `5672` |
| `RABBITMQ_VHOST` | ✓ | ✓ | ✓ | `vault_mq_vhost` |
| `RABBITMQ_USER` | ✓ | ✓ | ✓ | `vault_mq_user` |
| `RABBITMQ_PASSWORD` | ✓ | ✓ | ✓ | `vault_mq_password` (**Vault**) |
| `REDIS_HOST` | ✓ | ✓ | ✓ | `hostvars['cache-vm'].ansible_host` |
| `REDIS_PORT` | ✓ | ✓ | ✓ | 고정값 `6379` |
| `SECRET_KEY` | ✓ | ✓ | ✓ | `vault_app_secret_key` (**Vault**) |
| `ZDM_DEFAULT_IP` | ✓ | ✓ | ✓ | `zdm_default_ip` (`zdm.yml`) |
| `ZDM_DEFAULT_USER` | ✓ | ✓ | ✓ | `zdm_default_user` (`zdm.yml`) |
| `OLLAMA_HOST` | — | — | ✓ | `ollama_api_host` (`ai.yml`, `127.0.0.1`) |
| `OLLAMA_PORT` | — | — | ✓ | `ollama_port` (`ai.yml`, `11434`) |

> **Vault 항목** — `engine/ansible/group_vars/all/vault.yml`에 암호화 저장.
> 평문 예시: `group_vars/all/vault.yml.example`.

---

## Ansible 변수 파일별 역할

| 파일 | 내용 | 변경 방법 |
|---|---|---|
| `group_vars/all/vault.yml` | DB·MQ password, SECRET_KEY | `ansible-vault edit group_vars/all/vault.yml` |
| `group_vars/all/vault.yml.example` | 위의 평문 템플릿 | 구조 변경 시 함께 수정 후 commit |
| `group_vars/all/zdm.yml` | ZDM IP·계정 | 평문 편집 후 commit |
| `group_vars/all/ai.yml` | Ollama 모델·포트·API 주소 | 평문 편집 후 commit |
| `group_vars/all/common.yml` | Python 버전, app 경로, venv 경로 | 평문 편집 후 commit |
| `inventory.yml` (gitignore) | VM 사설 IP (`ansible_host`) | `./scripts/gen-inventory.sh` 재실행 |

---

## 환경변수 상세

### POSTGRES_*

| 키 | 주입값 출처 | 비고 |
|---|---|---|
| `POSTGRES_HOST` | inventory `hostvars['db-vm'].ansible_host` | db-vm 사설 IP 자동 주입 |
| `POSTGRES_PORT` | `5432` (고정) | |
| `POSTGRES_DB` | `vault_db_name` | postgres role이 동일 값으로 DB 생성 |
| `POSTGRES_USER` | `vault_db_user` | postgres role이 동일 값으로 user 생성 |
| `POSTGRES_PASSWORD` | `vault_db_password` | **Vault** — CHANGEME 반드시 교체 |

### RABBITMQ_*

| 키 | 주입값 출처 | 비고 |
|---|---|---|
| `RABBITMQ_HOST` | inventory `hostvars['mq-vm'].ansible_host` | mq-vm 사설 IP 자동 주입 |
| `RABBITMQ_PORT` | `5672` (고정) | |
| `RABBITMQ_VHOST` | `vault_mq_vhost` | rabbitmq role이 동일 값으로 vhost 생성 |
| `RABBITMQ_USER` | `vault_mq_user` | rabbitmq role이 동일 값으로 user 생성 |
| `RABBITMQ_PASSWORD` | `vault_mq_password` | **Vault** — agent vault.yml과 **반드시 동일** |

> agent-vm도 동일 MQ broker에 접속하므로 `agent/ansible/group_vars/all/vault.yml`의 `vault_mq_*` 값과 일치해야 한다.

### REDIS_*

| 키 | 주입값 출처 | 비고 |
|---|---|---|
| `REDIS_HOST` | inventory `hostvars['cache-vm'].ansible_host` | cache-vm 사설 IP 자동 주입 |
| `REDIS_PORT` | `6379` (고정) | |

### 공통 (api · consumer · ai 전부)

| 키 | 주입값 출처 | 비고 |
|---|---|---|
| `SECRET_KEY` | `vault_app_secret_key` | **Vault** — `openssl rand -base64 32` 권장 |
| `ZDM_DEFAULT_IP` | `zdm_default_ip` (`zdm.yml`) | ZDM 기본 접속 IP |
| `ZDM_DEFAULT_USER` | `zdm_default_user` (`zdm.yml`) | ZDM 기본 계정 |

### ai-vm 전용 (OLLAMA_*)

| 키 | 주입값 출처 | 기본값 | 비고 |
|---|---|---|---|
| `OLLAMA_HOST` | `ollama_api_host` (`ai.yml`) | `127.0.0.1` | ai-vm 내부 Ollama 주소 (로컬 전용) |
| `OLLAMA_PORT` | `ollama_port` (`ai.yml`) | `11434` | |

> `app.env.j2`의 `{% if ollama_api_host is defined %}` 블록으로 조건 렌더링 — api·consumer vm에는 미주입.

---

## 환경변수 값 변경 절차

### secret 변경 (DB·MQ password, SECRET_KEY)

```bash
cd engine/ansible
ansible-vault edit group_vars/all/vault.yml
# CHANGEME → 실제 값으로 수정 후 저장

# 반영: 해당 컴포넌트 playbook 재실행
ansible-playbook playbook-api.yml       # SECRET_KEY 변경 시
ansible-playbook playbook-consumer.yml  # SECRET_KEY 변경 시
ansible-playbook playbook-ai.yml        # SECRET_KEY 변경 시
ansible-playbook playbook-db.yml        # DB password 변경 시 (DB 재설정 포함)
ansible-playbook playbook-mq.yml        # MQ password 변경 시 (MQ 재설정 포함)
```

### ZDM 접속 정보 변경

```bash
vi engine/ansible/group_vars/all/zdm.yml
ansible-playbook playbook-api.yml
ansible-playbook playbook-consumer.yml
ansible-playbook playbook-ai.yml
```

### VM IP 변경 (Terraform 재apply 후)

```bash
./scripts/gen-inventory.sh   # inventory.yml 갱신
ansible-playbook engine/ansible/playbook-api.yml
# ... 각 컴포넌트 재실행
```

---

## 주의사항

### env 파일 위치 및 권한

| 컴포넌트 | 파일 경로 | 권한 |
|---|---|---|
| api-vm | `/opt/assessment/assessment-api.env` | 0600 |
| consumer-vm | `/opt/assessment/assessment-consumer.env` | 0600 |
| ai-vm | `/opt/assessment/assessment-diagnostic.env` | 0600 |

파일 소유자: `assessment` (systemd service 실행 user). 직접 확인:

```bash
sudo cat /opt/assessment/assessment-api.env
```

### MQ 자격증명 agent 동기화

`vault_mq_user` / `vault_mq_password` / `vault_mq_vhost` 는 engine과 agent가 동일 broker를 사용하므로 반드시 일치해야 한다.

| 파일 | 변수 |
|---|---|
| `engine/ansible/group_vars/all/vault.yml` | `vault_mq_user`, `vault_mq_password`, `vault_mq_vhost` |
| `agent/ansible/group_vars/all/vault.yml` | 동일 키, 동일 값 |

### alembic 마이그레이션 환경변수

`app_run_alembic: true`인 api-vm에서만 alembic이 실행된다. 이때 `playbook-api.yml`의 `app_env` dict가 alembic 프로세스에 직접 주입된다 (systemd env 파일과 별도 경로).
