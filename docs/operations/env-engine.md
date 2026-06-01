# Engine VM 환경변수 카탈로그

engine VM에 주입되는 환경변수의 단일 진실. 출처·주입 경로·컴포넌트별 필요 여부를 기록한다.

---

## 수정 우선순위

engine·agent repo 양쪽 contract 대비 본 infra의 누락·오류 전체 카탈로그는 `env-audit.md` 참조. 현재 inject 상태를 본 문서가 기록하고, 격차는 audit이 추적한다.

---

## 주입 흐름

```
Ansible Vault                group_vars/all/              inventory.yml
vault.yml (암호화)           common.yml / zdm.yml          (gen-inventory.sh 생성)
  vault_db_password           zdm_default_ip               hostvars['db-vm'].ansible_host
  vault_mq_password           zdm_default_user             hostvars['mq-vm'].ansible_host
  vault_app_secret_key        ai.yml                       hostvars['cache-vm'].ansible_host
                               ollama_base_url
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

> **범례**: ✓ 주입 / — 불필요 / ⚠ 미주입(수정 필요) / ❌ 키 오류(수정 필요)

| 환경변수 | api-vm | consumer-vm | ai-vm | Ansible 출처 |
|---|:---:|:---:|:---:|---|
| `APP_ENV` | ✓ | ✓ | ✓ | `engine_app_env` (`engine.yml`, default `production`) |
| `LOG_FORMAT` | ✓ | ✓ | ✓ | `engine_log_format` (`engine.yml`, default `json`) |
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
| `RABBITMQ_EXCHANGE` | ✓ | ✓ | ✓ | `engine_mq_exchange` (`engine.yml`) |
| `RABBITMQ_ROUTING_KEY_INVENTORY` | ✓ | ✓ | ✓ | `engine_mq_routing_key_inventory` (`engine.yml`) |
| `RABBITMQ_ROUTING_KEY_METRICS` | ✓ | ✓ | ✓ | `engine_mq_routing_key_metrics` (`engine.yml`) |
| `RABBITMQ_ROUTING_KEY_ERROR` | ✓ | ✓ | ✓ | `engine_mq_routing_key_error` (`engine.yml`) |
| `WORKER_TASK_EXCHANGE` | ✓ | ✓ | ✓ | `engine_mq_task_exchange` (`engine.yml`) |
| `WORKER_TASK_RESULT_KEY` | ✓ | ✓ | ✓ | `engine_mq_task_result_key` (`engine.yml`) |
| `DIAGNOSTIC_ROUTING_KEY` | ✓ | — | ✓ | `engine_diagnostic_routing_key` (`engine.yml`) |
| `DIAGNOSTIC_QUEUE_TTL_MS` | ✓ | — | ✓ | `engine_diagnostic_queue_ttl_ms` (`engine.yml`) |
| `DIAGNOSTIC_QUEUE_MAX_LEN` | ✓ | — | ✓ | `engine_diagnostic_queue_max_len` (`engine.yml`) |
| `REDIS_HOST` | ✓ | ✓ | ✓ | `hostvars['cache-vm'].ansible_host` |
| `REDIS_PORT` | ✓ | ✓ | ✓ | 고정값 `6379` |
| `SECRET_KEY` | ✓ | ✓ | ✓ | `vault_app_secret_key` (**Vault**) |
| `ZDM_DEFAULT_IP` | ✓ | ✓ | ✓ | `zdm_default_ip` (`zdm.yml`) |
| `ZDM_DEFAULT_USER` | ✓ | ✓ | ✓ | `zdm_default_user` (`zdm.yml`) |
| `ZDM_PACKAGE_PATH` | ⚠ | — | — | `zdm.yml` 추가 필요 |
| `ZDM_PACKAGE_SCRIPT` | ⚠ | — | — | `zdm.yml` 추가 필요 |
| `OLLAMA_BASE_URL` | — | — | ✓ | `ollama_base_url` (`ai.yml`, `http://127.0.0.1:11434`) |
| `OLLAMA_MODEL` | — | — | ✓ | `ollama_model` (`ai.yml`, `gemma2:2b`) |

> **Vault 항목** — `engine/ansible/group_vars/all/vault.yml`에 암호화 저장.
> 평문 예시: `group_vars/all/vault.yml.example`.

---

## Ansible 변수 파일별 역할

| 파일 | 내용 | 변경 방법 |
|---|---|---|
| `group_vars/all/vault.yml` | DB·MQ password, SECRET_KEY | `ansible-vault edit group_vars/all/vault.yml` |
| `group_vars/all/vault.yml.example` | 위의 평문 템플릿 | 구조 변경 시 함께 수정 후 commit |
| `group_vars/all/zdm.yml` | ZDM IP·계정·패키지 경로·routing key 군 | 평문 편집 후 commit |
| `group_vars/all/ai.yml` | Ollama base URL | 평문 편집 후 commit |
| `group_vars/all/common.yml` | Python 버전, app 경로, venv 경로, LOG_FORMAT | 평문 편집 후 commit |
| `inventory.yml` (gitignore) | VM 사설 IP (`ansible_host`) | `./scripts/gen-inventory.sh` 재실행 |

---

## 환경변수 상세

### APP_ENV

| 키 | 주입값 | 비고 |
|---|---|---|
| `APP_ENV` | `production` (고정) | pydantic-settings의 prod 보안 검증 활성화 조건. **미주입 시 `dev` 기본값으로 동작** |

> api·consumer·ai 모두 필요. 각 playbook `app_env` dict에 `APP_ENV: "production"` 추가.

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
| `RABBITMQ_PASSWORD` | `vault_mq_password` | **Vault** — agent vault는 본 파일 symlink |
| `RABBITMQ_EXCHANGE` | `zdm.yml` → `rabbitmq_exchange` | 기본값 `assessment`. agent의 publish exchange와 일치 필수 |
| `RABBITMQ_ROUTING_KEY_INVENTORY` | `zdm.yml` → `rabbitmq_routing_key_inventory` | 기본값 `server.inventory`. agent와 일치 필수 |
| `RABBITMQ_ROUTING_KEY_METRICS` | `zdm.yml` → `rabbitmq_routing_key_metrics` | 기본값 `server.metrics`. agent와 일치 필수 |
| `RABBITMQ_ROUTING_KEY_ERROR` | `zdm.yml` → `rabbitmq_routing_key_error` | 기본값 `server.error`. agent와 일치 필수 |
| `RABBITMQ_TASK_EXCHANGE` | `zdm.yml` → `rabbitmq_task_exchange` | diagnostic task dispatch용 |
| `RABBITMQ_TASK_RESULT_KEY` | `zdm.yml` → `rabbitmq_task_result_key` | diagnostic 결과 수신 routing key |
| `DIAGNOSTIC_ROUTING_KEY` | `zdm.yml` → `diagnostic_routing_key` | api·ai 모두 사용 |

> agent-vm도 동일 MQ broker에 접속하므로 routing key 군은 `agent/ansible/roles/agent_env/templates/agent.env.j2`와 반드시 일치해야 한다.

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
| `LOG_FORMAT` | `common.yml` → `log_format` | `json` (prod 권장) / `text` (기본값) |

### api-vm 전용 (ZDM_PACKAGE_*)

| 키 | 주입값 출처 | 비고 |
|---|---|---|
| `ZDM_PACKAGE_PATH` | `zdm_package_path` (`zdm.yml`) | bastion에 준비된 ZDM 설치 패키지 경로 |
| `ZDM_PACKAGE_SCRIPT` | `zdm_package_script` (`zdm.yml`) | ZDM 설치 스크립트 파일명 |

### ai-vm 전용 (OLLAMA_*)

| 키 | 주입값 출처 | 기본값 | 비고 |
|---|---|---|---|
| `OLLAMA_BASE_URL` | `ollama_base_url` (`ai.yml`) | `http://127.0.0.1:11434` | ai-vm 내부 Ollama 전체 URL — engine 코드가 단일 URL 키 요구 |
| `OLLAMA_MODEL` | `ollama_model` (`ai.yml`) | `gemma2:2b` | 진단 로직이 사용할 모델명 |

> `app.env.j2`의 `{% if ollama_base_url is defined %}` 블록으로 조건 렌더링 — api·consumer vm에는 미주입.

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

`vault_mq_user` / `vault_mq_password` / `vault_mq_vhost` 는 engine과 agent가 동일 broker를 사용한다.

`agent/ansible/group_vars/all/vault.yml` 은 `engine/ansible/group_vars/all/vault.yml` 을 가리키는 **symlink** — 단일 파일이므로 동기화 작업 불필요. agent playbook 실행 시에도 engine vault를 그대로 로드한다.

### MQ routing key agent 동기화

agent가 publish하는 routing key와 engine consumer/ai가 subscribe하는 routing key가 반드시 일치해야 한다.

| 변수 | engine (`zdm.yml`) | agent (`agent.env.j2`) |
|---|---|---|
| `RABBITMQ_EXCHANGE` | `rabbitmq_exchange` | `RABBITMQ_EXCHANGE=assessment` (하드코딩) |
| `RABBITMQ_ROUTING_KEY_INVENTORY` | `rabbitmq_routing_key_inventory` | `RABBITMQ_ROUTING_KEY_INVENTORY=server.inventory` |
| `RABBITMQ_ROUTING_KEY_METRICS` | `rabbitmq_routing_key_metrics` | `RABBITMQ_ROUTING_KEY_METRICS=server.metrics` |
| `RABBITMQ_ROUTING_KEY_ERROR` | `rabbitmq_routing_key_error` | `RABBITMQ_ROUTING_KEY_ERROR=server.error` |

### alembic 마이그레이션 환경변수

`app_run_alembic: true`인 api-vm에서만 alembic이 실행된다. 이때 `playbook-api.yml`의 `app_env` dict가 alembic 프로세스에 직접 주입된다 (systemd env 파일과 별도 경로).
