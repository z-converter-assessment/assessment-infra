# Engine VM 환경변수 카탈로그

engine VM에 주입되는 환경변수의 단일 진실. 출처·주입 경로·컴포넌트별 필요 여부를 기록한다.

---

## 수정 우선순위

engine·agent repo 양쪽 contract 대비 본 infra의 누락·오류 전체 카탈로그는 `env-audit.md` 참조. 현재 inject 상태를 본 문서가 기록하고, 격차는 audit이 추적한다.

---

## 주입 흐름

```
Ansible Vault            group_vars/all/
vault.yml (암호화)        engine.yml / zdm.yml / common.yml
  vault_db_password        engine_mq_* (exchange·routing key)
  vault_mq_password        zdm_default_ip / zdm_package_*
  vault_app_secret_key     engine_app_env / engine_log_format
          │                        │
          └───────────┬────────────┘
                       │  engine_compose role (Jinja2)
                       ▼
       roles/engine_compose/templates/.env.j2
       → {{ compose_dir }}/.env   (mode 0600)
                       │  docker compose (env_file)
                       ▼
       api · consumer · migrate 컨테이너 환경변수
```

> engine 내부 서비스는 같은 호스트의 compose 네트워크라 `POSTGRES_HOST=postgres`처럼 **VM IP가 아닌 compose 서비스명**으로 접속한다 (inventory hostvars 불필요). AI VM의 diagnostic-worker는 별도 host라 engine-vm 사설 IP로 접속 — 별도 inject(ollama role), 본 카탈로그 범위 밖.

변수 출처:
- **Ansible Vault** (`vault.yml`): password·SECRET_KEY — `ansible-vault encrypt` 후 git commit
- **group_vars** (`engine.yml` / `zdm.yml` / `common.yml`): 비밀 아닌 설정값 — 평문 commit
- **고정값**: compose 서비스명·포트 — `.env.j2`에 하드코딩 (`postgres`·`rabbitmq`·`redis`)

---

## engine .env 카탈로그

`roles/engine_compose/templates/.env.j2` → `{{ compose_dir }}/.env` (**단일 파일** — api·consumer·migrate 컨테이너가 compose `env_file`로 공유). 아래는 `.env.j2`와 1:1 대응.

| 환경변수 | 값 / Ansible 출처 |
|---|---|
| `APP_ENV` | `engine_app_env` (`engine.yml`, default `production`) |
| `LOG_FORMAT` | `engine_log_format` (`engine.yml`, default `json`) |
| `POSTGRES_HOST` | **`postgres`** (고정 — compose 서비스명) |
| `POSTGRES_PORT` | `5432` (고정) |
| `POSTGRES_DB` | `vault_db_name` |
| `POSTGRES_USER` | `vault_db_user` |
| `POSTGRES_PASSWORD` | `vault_db_password` (**Vault**) |
| `RABBITMQ_HOST` | **`rabbitmq`** (고정 — compose 서비스명) |
| `RABBITMQ_PORT` | `5672` (고정) |
| `RABBITMQ_VHOST` | `vault_mq_vhost` |
| `RABBITMQ_USER` | `vault_mq_user` |
| `RABBITMQ_PASSWORD` | `vault_mq_password` (**Vault**) |
| `RABBITMQ_EXCHANGE` | `engine_mq_exchange` (`engine.yml`) |
| `RABBITMQ_ROUTING_KEY_INVENTORY` | `engine_mq_routing_key_inventory` (`engine.yml`) |
| `RABBITMQ_ROUTING_KEY_METRICS` | `engine_mq_routing_key_metrics` (`engine.yml`) |
| `RABBITMQ_ROUTING_KEY_ERROR` | `engine_mq_routing_key_error` (`engine.yml`) |
| `WORKER_TASK_EXCHANGE` | `engine_mq_task_exchange` (`engine.yml`) |
| `WORKER_TASK_RESULT_KEY` | `engine_mq_task_result_key` (`engine.yml`) |
| `DIAGNOSTIC_ROUTING_KEY` | `engine_diagnostic_routing_key` (`engine.yml`) |
| `DIAGNOSTIC_QUEUE_TTL_MS` | `engine_diagnostic_queue_ttl_ms` (`engine.yml`) |
| `DIAGNOSTIC_QUEUE_MAX_LEN` | `engine_diagnostic_queue_max_len` (`engine.yml`) |
| `REDIS_HOST` | **`redis`** (고정 — compose 서비스명) |
| `REDIS_PORT` | `6379` (고정) |
| `SECRET_KEY` | `vault_app_secret_key` (**Vault**) |
| `ZDM_DEFAULT_IP` | `zdm_default_ip` (`zdm.yml`) |
| `ZDM_DEFAULT_USER` | `zdm_default_user` (`zdm.yml`) |
| `ZDM_PACKAGE_PATH` | `zdm_package_path` (`zdm.yml`) |
| `ZDM_PACKAGE_SCRIPT` | `zdm_package_script` (`zdm.yml`) |
| `ZDM_META_CONNECT_TIMEOUT_SEC` | `zdm_meta_connect_timeout_sec` (`zdm.yml`) |
| `ZDM_META_TOTAL_TIMEOUT_SEC` | `zdm_meta_total_timeout_sec` (`zdm.yml`) |
| `REDIS_TTL_ZDM_PACKAGE_SHA256` | `redis_ttl_zdm_package_sha256` (`zdm.yml`) |
| `PGDATA` | `{{ db_mount_path }}/pgdata` (compose bind mount source) |
| `MQ_DATA` | `{{ mq_mount_path }}` (compose bind mount source) |

> **Vault 항목** — `engine/ansible/group_vars/all/vault.yml`에 암호화 저장. 평문 예시: `group_vars/all/vault.yml.example`.
>
> **AI VM (`OLLAMA_*` 등)**: engine `.env`에 **미포함**. AI VM의 diagnostic-worker는 `ollama role`/`playbook-ai.yml`이 별도 주입 — `OLLAMA_BASE_URL`(`ai.yml`, `http://127.0.0.1:11434`)·`OLLAMA_MODEL`(`gemma2:2b`) + engine-vm IP로의 MQ/PG/Redis 접속. 상세는 코드 참조.

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
| `POSTGRES_HOST` | `postgres` (compose 서비스명, 고정) | 같은 호스트 compose 네트워크 |
| `POSTGRES_PORT` | `5432` (고정) | |
| `POSTGRES_DB` | `vault_db_name` | postgres role이 동일 값으로 DB 생성 |
| `POSTGRES_USER` | `vault_db_user` | postgres role이 동일 값으로 user 생성 |
| `POSTGRES_PASSWORD` | `vault_db_password` | **Vault** — CHANGEME 반드시 교체 |

### RABBITMQ_*

| 키 | 주입값 출처 | 비고 |
|---|---|---|
| `RABBITMQ_HOST` | `rabbitmq` (compose 서비스명, 고정) | 같은 호스트 compose 네트워크 |
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
| `REDIS_HOST` | `redis` (compose 서비스명, 고정) | 같은 호스트 compose 네트워크 |
| `REDIS_PORT` | `6379` (고정) | |

### engine .env 공통 (api · consumer · migrate)

| 키 | 주입값 출처 | 비고 |
|---|---|---|
| `SECRET_KEY` | `vault_app_secret_key` | **Vault** — `openssl rand -base64 32` 권장 |
| `ZDM_DEFAULT_IP` | `zdm_default_ip` (`zdm.yml`) | ZDM 기본 접속 IP |
| `ZDM_DEFAULT_USER` | `zdm_default_user` (`zdm.yml`) | ZDM 기본 계정 |
| `LOG_FORMAT` | `engine_log_format` (`engine.yml`) | `json` (prod 권장) / `text` |
| `ZDM_PACKAGE_PATH` | `zdm_package_path` (`zdm.yml`) | bastion에 준비된 ZDM 설치 패키지 경로 |
| `ZDM_PACKAGE_SCRIPT` | `zdm_package_script` (`zdm.yml`) | ZDM 설치 스크립트 파일명 |

> 구모델에서 `ZDM_PACKAGE_*`는 api-vm 전용이었으나, 현재 단일 `.env`라 engine 전 서비스가 공유.

### AI VM (OLLAMA_*) — engine .env 범위 밖

AI VM의 diagnostic-worker는 `ollama role`/`playbook-ai.yml`이 별도 주입 (engine `.env.j2`에 없음).

| 키 | 주입값 출처 | 기본값 | 비고 |
|---|---|---|---|
| `OLLAMA_BASE_URL` | `ollama_base_url` (`ai.yml`) | `http://127.0.0.1:11434` | AI VM 로컬 Ollama URL |
| `OLLAMA_MODEL` | `ollama_model` (`ai.yml`) | `gemma2:2b` | 진단 로직이 사용할 모델명 |

> diagnostic-worker는 engine-vm의 MQ/PG/Redis에 **engine-vm 사설 IP**로 접속 — engine 내부 서비스명(`postgres` 등)과 다름. 정확한 키는 ai role 코드 참조.

---

## 환경변수 값 변경 절차

### secret·설정 변경 (vault / zdm.yml / engine.yml)

```bash
cd engine/ansible
ansible-vault edit group_vars/all/vault.yml   # password·SECRET_KEY
# 또는: vi group_vars/all/zdm.yml / engine.yml  (평문 설정)

# 반영: playbook-engine 1회 재실행 → .env 재렌더 → docker compose up -d (변경 서비스만 재생성)
ansible-playbook -i inventory.yml playbook-engine.yml \
  --vault-password-file ~/.vault-pass --extra-vars "engine_version=X.Y.Z ghcr_token=<...>"
```

> DB·MQ password를 바꾸면 `.env`의 자격과 postgres/rabbitmq 컨테이너 초기화 자격이 어긋날 수 있다 — 빈 stack 최초 기동이 아니라면 볼륨(`/mnt/pgdata`·`/mnt/mqdata`)의 기존 자격과의 정합을 별도 확인.

### VM IP 변경 (Terraform 재apply 후)

```bash
python3 scripts/gen_inventory.py --scope engine   # inventory.yml 갱신
ansible-playbook -i engine/ansible/inventory.yml engine/ansible/playbook-engine.yml \
  --vault-password-file ~/.vault-pass --extra-vars "engine_version=X.Y.Z ghcr_token=<...>"
```

> engine 내부 서비스 host는 compose 서비스명(고정)이라 VM IP 변경과 무관. inventory 갱신은 ansible의 SSH 접속 대상(`ansible_host`) 때문.

---

## 주의사항

### env 파일 위치 및 권한

engine compose는 **단일 `.env`** 를 전 서비스가 공유 (`env_file`).

| 대상 | 파일 경로 | 권한 |
|---|---|---|
| engine compose 전체 | `{{ compose_dir }}/.env` (예: `/opt/assessment/.env`) | 0600 |

직접 확인:

```bash
ssh engine-vm.engine
sudo cat /opt/assessment/.env
# 실행 중 컨테이너에 들어간 값: sudo docker compose exec api env | grep RABBITMQ_
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

compose의 **`migrate` init-container**가 같은 `.env`(`env_file`)를 받아 `alembic upgrade head`를 1회 실행한다. api·consumer는 `depends_on: migrate (service_completed_successfully)`로 대기 → 별도 alembic 전용 env 경로 없음. (구모델의 `playbook-api.yml app_run_alembic` 폐기, ADR-0010)
