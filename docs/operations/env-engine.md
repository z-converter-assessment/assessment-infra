# Engine VM 환경변수 카탈로그

engine VM에 주입되는 환경변수의 단일 진실. 출처·주입 경로·컴포넌트별 필요 여부를 기록한다.
v0.5.0 prod-safe base compose(ADR-0035) 기준 — `roles/engine_compose/templates/.env.j2`와 1:1 대응.

---

## 주입 흐름

```
Ansible Vault            group_vars/all/
vault.yml (암호화)        engine.yml · zdm.yml · ai.yml · common.yml
  vault_db_password        engine_mq_* (exchange·routing·task)
  vault_mq_password        engine_app_env / engine_log_format / engine_version
  vault_app_secret_key     engine_pgadmin_email / engine_pgadmin_port
  vault_pgadmin_password    engine_install_timeout_sec
          │                ollama_base_url / ollama_model (ai.yml)
          │                zdm_* (zdm.yml) · db/mq_mount_path (common.yml)
          └───────────┬────────────┘
                       │  engine_compose role (Jinja2)
                       ▼
       roles/engine_compose/templates/.env.j2
       → {{ compose_dir }}/.env   (/opt/engine-compose/.env, mode 0600)
                       │  docker compose (env_file)
                       ▼
   web · consumer · diagnostic-worker · migrate · pgadmin 컨테이너 환경변수
```

> 단일 노드 compose(ADR-0010)라 **diagnostic-worker도 engine-vm compose 스택에서 실행**된다. 따라서 `OLLAMA_*`가 engine `.env`에 포함되며(AI VM의 Ollama 데몬에 원격 접속), 과거처럼 AI VM 별도 inject가 아니다. AI VM(`playbook-ai.yml`)은 Ollama 데몬만 호스팅한다.
> engine 내부 서비스는 같은 compose 네트워크라 `POSTGRES_HOST=postgres`처럼 **VM IP가 아닌 compose 서비스명**으로 접속한다.

변수 출처:
- **Ansible Vault** (`vault.yml`): password·SECRET_KEY·pgadmin password — AES256 암호화 후 git commit (`~/.vault-pass`로 복호화)
- **group_vars** (`engine.yml`·`zdm.yml`·`ai.yml`·`common.yml`): 비밀 아닌 설정값 — 평문 commit
- **고정값**: compose 서비스명·포트 — `.env.j2`에 하드코딩 (`postgres`·`rabbitmq`·`redis`, 포트 5432/5672/6379/8000/15672)

---

## engine .env 카탈로그 (`.env.j2`와 1:1)

`roles/engine_compose/templates/.env.j2` → `/opt/engine-compose/.env` (**단일 파일** — 전 compose 서비스가 `env_file`로 공유).

| 환경변수 | 값 / Ansible 출처 | 비고 |
|---|---|---|
| `APP_ENV` | `engine_app_env` (`engine.yml`) | **`prod`** — 정확히 `prod`여야 weak-secret fail-fast 발동 |
| `LOG_FORMAT` | `engine_log_format` (`engine.yml`) | `json` |
| `ENGINE_IMAGE` | `ghcr.io/.../assessment-engine:{{ engine_version }}` | 버전 핀 명시 결선 (`engine_version`, `engine.yml`) |
| `POSTGRES_HOST` | **`postgres`** (고정 — 서비스명) | |
| `POSTGRES_PORT` | `5432` (고정) | |
| `POSTGRES_DB` | `vault_db_name` | |
| `POSTGRES_USER` | `vault_db_user` | |
| `POSTGRES_PASSWORD` | `vault_db_password` (**Vault**) | |
| `SQLALCHEMY_ECHO` | `false` (고정) | SQL 로깅 off |
| `PGADMIN_EMAIL` | `engine_pgadmin_email` (`engine.yml`) | 유효 TLD 필수 |
| `PGADMIN_PASSWORD` | `vault_pgadmin_password` (**Vault**) | pgadmin은 APP_ENV fail-fast 대상 아님 → 강 secret 필수 |
| `PGADMIN_PORT` | `engine_pgadmin_port` (`engine.yml`) | host 5050 노출 |
| `RABBITMQ_HOST` | **`rabbitmq`** (고정 — 서비스명) | |
| `RABBITMQ_PORT` | `5672` (고정) | |
| `RABBITMQ_MANAGEMENT_PORT` | `15672` (고정) | mgmt UI |
| `RABBITMQ_VHOST` | `vault_mq_vhost` | |
| `RABBITMQ_USER` | `vault_mq_user` | |
| `RABBITMQ_PASSWORD` | `vault_mq_password` (**Vault**) | |
| `RABBITMQ_EXCHANGE` | `engine_mq_exchange` (`engine.yml`) | agent와 일치 필수 |
| `RABBITMQ_ROUTING_KEY_INVENTORY` | `engine_mq_routing_key_inventory` | agent와 일치 |
| `RABBITMQ_ROUTING_KEY_METRICS` | `engine_mq_routing_key_metrics` | agent와 일치 |
| `RABBITMQ_ROUTING_KEY_ERROR` | `engine_mq_routing_key_error` | agent와 일치 |
| `RABBITMQ_TASK_EXCHANGE` | `engine_mq_task_exchange` (`engine.yml`) | task.install/result 전용 |
| `RABBITMQ_TASK_QUEUE_PREFIX` | `engine_mq_task_queue_prefix` | `agent.tasks` |
| `RABBITMQ_TASK_INSTALL_KEY_PREFIX` | `engine_mq_task_install_key_prefix` | `task.install` |
| `RABBITMQ_ROUTING_KEY_TASK_RESULT` | `engine_mq_task_result_key` | `task.result` |
| `RABBITMQ_QUEUE_WORKER_RESULT` | `engine_mq_worker_result_queue` | `worker.result` |
| `RABBITMQ_ROUTING_KEY_DIAGNOSTIC` | `engine_diagnostic_routing_key` | web publish / worker consume |
| `RABBITMQ_DIAGNOSTIC_QUEUE_TTL_MS` | `engine_diagnostic_queue_ttl_ms` | |
| `RABBITMQ_DIAGNOSTIC_QUEUE_MAX_LEN` | `engine_diagnostic_queue_max_len` | |
| `REDIS_HOST` | **`redis`** (고정 — 서비스명) | |
| `REDIS_PORT` | `6379` (고정) | |
| `SECRET_KEY` | `vault_app_secret_key` (**Vault**) | |
| `WEB_PORT` | `8000` (고정) | health check·SG 정합 |
| `INSTALL_TIMEOUT_SEC` | `engine_install_timeout_sec` (`engine.yml`) | install.sh wall-clock timeout |
| `ZDM_DEFAULT_IP` | `zdm_default_ip` (`zdm.yml`) | |
| `ZDM_DEFAULT_USER` | `zdm_default_user` (`zdm.yml`) | |
| `ZDM_PACKAGE_PATH` | `zdm_package_path` (`zdm.yml`) | |
| `ZDM_PACKAGE_SCRIPT` | `zdm_package_script` (`zdm.yml`) | |
| `ZDM_META_CONNECT_TIMEOUT_SEC` | `zdm_meta_connect_timeout_sec` (`zdm.yml`) | |
| `ZDM_META_TOTAL_TIMEOUT_SEC` | `zdm_meta_total_timeout_sec` (`zdm.yml`) | |
| `REDIS_TTL_ZDM_PACKAGE_SHA256` | `redis_ttl_zdm_package_sha256` (`zdm.yml`) | |
| `OLLAMA_BASE_URL` | `ollama_base_url` (`ai.yml`) | AI VM Ollama 데몬 URL (미도달 시 narrative pending) |
| `OLLAMA_MODEL` | `ollama_model` (`ai.yml`) | `gemma2:2b` — base default(qwen2.5:1.5b)와 다르므로 명시 필수 |
| `PGDATA_HOST` | `{{ db_mount_path }}/pgdata` (`common.yml`) | host bind 소스 — 키명 정확해야 Cinder bind |
| `MQ_DATA_HOST` | `{{ mq_mount_path }}` (`common.yml`) | host bind 소스 |

> **Vault 항목**: `vault.yml`(AES256, git commit). 평문 예시: `vault.yml.example`. CHANGEME는 강 random으로 교체(`openssl rand`).
> **컴포넌트별 read**: `WEB_PORT`·`INSTALL_TIMEOUT_SEC`는 web 전용, `OLLAMA_*`·`RABBITMQ_DIAGNOSTIC_*`는 diagnostic-worker 중심, MQ 접속·라우팅은 web/consumer/worker 공통. 단일 `.env`라 전 서비스가 같은 파일을 받고 각자 필요한 키만 read.

---

## Ansible 변수 파일별 역할

| 파일 | 내용 | 변경 방법 |
|---|---|---|
| `group_vars/all/vault.yml` | DB·MQ·app·pgadmin 비밀 (`vault_db_password`·`vault_mq_password`·`vault_app_secret_key`·`vault_pgadmin_password`) | `ansible-vault edit group_vars/all/vault.yml` |
| `group_vars/all/vault.yml.example` | 위의 평문 템플릿 | 구조 변경 시 함께 수정 후 commit |
| `group_vars/all/engine.yml` | `engine_version`·`engine_app_env`·`engine_log_format`·MQ exchange/routing/task 키·diagnostic 큐·`engine_install_timeout_sec`·pgadmin email/port | 평문 편집 후 commit |
| `group_vars/all/zdm.yml` | ZDM IP·계정·패키지 경로·메타 timeout·redis TTL | 평문 편집 후 commit |
| `group_vars/all/ai.yml` | `ollama_base_url`(AI VM IP 참조)·`ollama_model` | 평문 편집 후 commit |
| `group_vars/all/common.yml` | `compose_dir`·`db/mq_mount_path`·`postgres_container_uid` 등 | 평문 편집 후 commit |
| `inventory.yml` (gitignore) | VM 사설 IP (`ansible_host`) | `python3 scripts/gen_inventory.py --scope engine` 재실행 |

---

## agent와의 MQ 동기화

engine과 agent는 동일 broker를 사용한다.

**자격증명**: `vault_mq_user`/`vault_mq_password`/`vault_mq_vhost` — `agent/ansible/group_vars/all/vault.yml`은 engine vault를 가리키는 **symlink**라 동기화 작업 불필요.

**라우팅 contract** (값은 동일, 키 prefix만 다름):

| 값 | engine `.env` 키 (`engine.yml` 출처) | agent `agent.env` 키 |
|---|---|---|
| `assessment` | `RABBITMQ_EXCHANGE` | `RABBITMQ_EXCHANGE` |
| `server.inventory` | `RABBITMQ_ROUTING_KEY_INVENTORY` | `RABBITMQ_ROUTING_KEY_INVENTORY` |
| `server.metrics` | `RABBITMQ_ROUTING_KEY_METRICS` | `RABBITMQ_ROUTING_KEY_METRICS` |
| `server.error` | `RABBITMQ_ROUTING_KEY_ERROR` | `RABBITMQ_ROUTING_KEY_ERROR` |
| `assessment.tasks` | `RABBITMQ_TASK_EXCHANGE` | `WORKER_TASK_EXCHANGE` |
| `agent.tasks` | `RABBITMQ_TASK_QUEUE_PREFIX` | `WORKER_TASK_QUEUE_PREFIX` |
| `task.result` | `RABBITMQ_ROUTING_KEY_TASK_RESULT` | `WORKER_TASK_RESULT_KEY` |

> engine은 pydantic 필드명 그대로라 `RABBITMQ_*` prefix, agent(호스트 관점)는 `WORKER_TASK_*` prefix. **값은 bit-exact 일치** 필수.

---

## 환경변수 값 변경 절차

### secret·설정 변경

```bash
cd engine/ansible
ansible-vault edit group_vars/all/vault.yml     # password·SECRET_KEY·pgadmin
# 또는: vi group_vars/all/{engine,zdm,ai,common}.yml  (평문 설정)

# 반영: playbook-engine 1회 재실행 → .env 재렌더 → docker compose up -d (변경 서비스만 재생성)
ansible-playbook -i inventory.yml playbook-engine.yml \
  --vault-password-file ~/.vault-pass --extra-vars "engine_version=X.Y.Z ghcr_token=<...>"
```

> **DB·MQ·pgadmin password 회전 주의**: postgres·rabbitmq·pgadmin 컨테이너는 비밀번호를 **첫 init(빈 볼륨) 때만** 설정한다. 이미 데이터가 있는 VM이면 `.env`만 바뀌고 기존 계정 비번은 그대로라 접속 실패 — 볼륨 초기화 또는 컨테이너 내부에서 직접 변경 필요.

### VM IP 변경 (Terraform 재apply 후)

```bash
python3 scripts/gen_inventory.py --scope engine   # inventory.yml 갱신 (SSH 접속 대상)
ansible-playbook -i engine/ansible/inventory.yml engine/ansible/playbook-engine.yml \
  --vault-password-file ~/.vault-pass --extra-vars "engine_version=X.Y.Z ghcr_token=<...>"
```

> engine 내부 서비스 host는 compose 서비스명(고정)이라 VM IP 변경과 무관. `OLLAMA_BASE_URL`은 AI VM IP를 참조하므로 AI VM 재생성 시 inventory 갱신 후 재배포 필요.

---

## 주의사항

### env 파일 위치 및 권한

engine compose는 **단일 `.env`**를 전 서비스가 공유.

| 대상 | 경로 | 권한 |
|---|---|---|
| engine compose 전체 | `/opt/engine-compose/.env` | 0600 |

```bash
ssh engine-vm.engine
sudo cat /opt/engine-compose/.env
# 실행 중 컨테이너 값: sudo docker compose -f /opt/engine-compose/docker-compose.yml exec web env | grep RABBITMQ_
```

### alembic 마이그레이션

compose의 **`migrate` init-container**가 같은 `.env`를 받아 `alembic upgrade head`를 1회 실행. web·consumer·diagnostic-worker는 `depends_on: migrate (service_completed_successfully)`로 대기 → 별도 alembic 전용 env 경로 없음 (ADR-0010).

### Cinder bind 소유권

`PGDATA_HOST` host bind 소스는 timescaledb-ha의 postgres uid(`postgres_container_uid`, `common.yml`)로 선소유돼야 한다(`engine_compose` role이 처리). 미설정 시 initdb 권한 실패로 postgres unhealthy.
