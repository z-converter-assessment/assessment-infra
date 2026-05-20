# Architecture — 컴포넌트 구성 및 환경변수 주입 상세

---

## 1. 전체 컴포넌트 다이어그램

```
외부망 (인터넷)
      │
      │ Floating IP NAT  ← terraform/floating_ips.tf
      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  사내망                                                                      │
│                                                                             │
│  bastion-vm  (Horizon 수동 생성 · FIP 부여)                                  │
│  └── bastion-sg  (data source 참조만 — terraform/data.tf)                   │
│        SSH 22 ← 사내망                                                       │
│                                                                             │
└──────────────────────────┬──────────────────────────────────────────────────┘
                           │ ProxyJump SSH (bastion 경유)
        ┌──────────────────┼──────────────────────────────────────────────────┐
        │  engine-subnet   │  (CIDR: terraform/variables.tf → engine_subnet_name)
        │                  │
        │  ┌───────────────▼───────────────────┐
        │  │  api-vm  (flavor_api)             │  ← terraform/instances.tf
        │  │  Ubuntu 24.04                     │
        │  │  uvicorn :8000                    │  ← ansible/playbook-api.yml
        │  │  FIP 부여                         │  ← terraform/floating_ips.tf
        │  │                                   │
        │  │  SG: api-sg                       │  ← terraform/security_groups.tf
        │  │  ├── ingress TCP 22   ← bastion-sg  (remote SG)
        │  │  └── ingress TCP 8000 ← 0.0.0.0/0  (var.internal_cidr)
        │  └──────┬────────────────────────────┘
        │         │ POSTGRES_HOST / RABBITMQ_HOST / REDIS_HOST
        │         │
        │  ┌──────▼────────────────────────────┐
        │  │  db-vm  (flavor_db)               │  ← terraform/instances.tf
        │  │  Ubuntu 24.04                     │
        │  │  postgresql-16 + timescaledb :5432│  ← ansible/playbook-db.yml
        │  │                          │        │
        │  │  Cinder 50GB /dev/vdb   │        │  ← terraform/volumes.tf
        │  │  → mount: /var/lib/postgresql     │
        │  │                                   │
        │  │  SG: db-sg                        │  ← terraform/security_groups.tf
        │  │  ├── ingress TCP 22   ← bastion-sg  (remote SG)
        │  │  ├── ingress TCP 5432 ← api-sg      (remote SG)
        │  │  └── ingress TCP 5432 ← worker-sg   (remote SG)
        │  └───────────────────────────────────┘
        │
        │  ┌────────────────────────────────────┐
        │  │  mq-vm  (flavor_mq)               │  ← terraform/instances.tf
        │  │  Ubuntu 24.04                     │
        │  │  rabbitmq-server :5672 :15672     │  ← ansible/playbook-mq.yml
        │  │                                   │
        │  │  Cinder 20GB /dev/vdb             │  ← terraform/volumes.tf
        │  │  → mount: /var/lib/rabbitmq       │
        │  │                                   │
        │  │  SG: mq-sg                        │  ← terraform/security_groups.tf
        │  │  ├── ingress TCP 22    ← bastion-sg  (remote SG)
        │  │  ├── ingress TCP 5672  ← api-sg      (remote SG)
        │  │  ├── ingress TCP 5672  ← worker-sg   (remote SG)
        │  │  ├── ingress TCP 5672  ← agent-sg    (remote SG) ◄── agent-subnet
        │  │  ├── ingress TCP 15672 ← api-sg      (remote SG)
        │  │  └── ingress TCP 15672 ← worker-sg   (remote SG)
        │  └────────────────────────────────────┘
        │
        │  ┌────────────────────────────────────┐
        │  │  cache-vm  (flavor_cache)          │  ← terraform/instances.tf
        │  │  Ubuntu 24.04                     │
        │  │  redis-server :6379               │  ← ansible/playbook-cache.yml
        │  │                                   │
        │  │  SG: cache-sg                     │  ← terraform/security_groups.tf
        │  │  ├── ingress TCP 22   ← bastion-sg  (remote SG)
        │  │  ├── ingress TCP 6379 ← api-sg      (remote SG)
        │  │  └── ingress TCP 6379 ← worker-sg   (remote SG)
        │  └────────────────────────────────────┘
        │
        │  ┌────────────────────────────────────┐
        │  │  worker-vm  (flavor_worker)        │  ← terraform/instances.tf
        │  │  Ubuntu 24.04                     │
        │  │  python -m assessment_engine      │  ← ansible/playbook-worker.yml
        │  │              .consumer            │
        │  │                                   │
        │  │  SG: worker-sg                    │  ← terraform/security_groups.tf
        │  │  └── ingress TCP 22 ← bastion-sg    (remote SG)
        │  └────────────────────────────────────┘
        │
        └──────────────────────────────────────────────────────────────────────┘

        ┌──────────────────────────────────────────────────────────────────────┐
        │  agent-subnet  (CIDR: terraform/variables.tf → agent_subnet_name)   │
        │                                                                      │
        │  agent-vm × N  (flavor_agent, var.agent_count)                      │
        │  assessment-agent (C 실행파일)                                       │
        │  AMQP publish ──────────────────────────────────► mq-vm :5672       │
        │                                                                      │
        │  SG: agent-sg                         ← terraform/security_groups.tf│
        │  ├── ingress TCP 22  ← bastion-sg  (remote SG)                      │
        │  └── ingress ALL     ← agent-subnet CIDR (IP prefix)                │
        └──────────────────────────────────────────────────────────────────────┘
```

---

## 2. 보안그룹 remote SG 참조 관계

> `terraform/security_groups.tf` 기준

```
bastion-sg ──TCP 22──► api-sg
           ──TCP 22──► mq-sg
           ──TCP 22──► cache-sg
           ──TCP 22──► db-sg
           ──TCP 22──► worker-sg
           ──TCP 22──► agent-sg

api-sg ──TCP 5672──► mq-sg      (AMQP)
       ──TCP 15672─► mq-sg      (Management UI)
       ──TCP 6379──► cache-sg   (Redis)
       ──TCP 5432──► db-sg      (PostgreSQL)

worker-sg ──TCP 5672──► mq-sg   (AMQP)
          ──TCP 15672─► mq-sg   (Management UI)
          ──TCP 6379──► cache-sg (Redis)
          ──TCP 5432──► db-sg   (PostgreSQL)

agent-sg ──TCP 5672──► mq-sg    (AMQP publish only)
```

> **egress 규칙 없음** — OpenStack SG 기본값(egress 전체 허용)을 그대로 사용.  
> `api-sg` port 8000은 `remote_group_id` 아닌 IP prefix (`var.internal_cidr`, 기본 `0.0.0.0/0`) 방식.

---

## 3. 인스턴스별 환경변수 주입 상세

### 주입 파이프라인 (api-vm · worker-vm 공통)

```
[소스]                              [처리]                  [주입 방식]

Ansible Vault                   ┐
  vault.yml (암호화)             │  Ansible 실행 시         systemd
  → vault_db_password 등        │  Jinja2 렌더링           EnvironmentFile
                                 ├─────────────────────►  /opt/assessment/
group_vars/all/                  │  app.env.j2             <service>.env
  common.yml                     │  (template 모듈)        (mode 0600)
  engine.yml                     │                              │
  zdm.yml                        │                              ▼
                                 │                         프로세스 환경
inventory hostvars               │                         (systemd 기동 시)
  ansible_host (각 VM IP)       ┘
```

> 파일 위치:
> - 템플릿: `ansible/roles/app/templates/app.env.j2`
> - systemd unit: `ansible/roles/app/templates/app.service.j2`
> - 변수 선언: `ansible/group_vars/all/vault.yml.example` (실제값은 암호화된 `vault.yml`)

---

### api-vm

| 환경변수 | 실제 값 | 출처 파일 | 주입 방식 |
|---|---|---|---|
| `POSTGRES_HOST` | db-vm 사설 IP | inventory `hostvars['db-vm']` | EnvironmentFile |
| `POSTGRES_PORT` | `5432` | `playbook-api.yml` (하드코딩) | EnvironmentFile |
| `POSTGRES_DB` | `assessment` | `vault.yml` → `vault_db_name` | EnvironmentFile |
| `POSTGRES_USER` | `assessment` | `vault.yml` → `vault_db_user` | EnvironmentFile |
| `POSTGRES_PASSWORD` | `****` | `vault.yml` → `vault_db_password` (Vault 암호화) | EnvironmentFile |
| `RABBITMQ_HOST` | mq-vm 사설 IP | inventory `hostvars['mq-vm']` | EnvironmentFile |
| `RABBITMQ_PORT` | `5672` | `playbook-api.yml` (하드코딩) | EnvironmentFile |
| `RABBITMQ_VHOST` | `assessment` | `vault.yml` → `vault_mq_vhost` | EnvironmentFile |
| `RABBITMQ_USER` | `assessment` | `vault.yml` → `vault_mq_user` | EnvironmentFile |
| `RABBITMQ_PASSWORD` | `****` | `vault.yml` → `vault_mq_password` (Vault 암호화) | EnvironmentFile |
| `REDIS_HOST` | cache-vm 사설 IP | inventory `hostvars['cache-vm']` | EnvironmentFile |
| `REDIS_PORT` | `6379` | `playbook-api.yml` (하드코딩) | EnvironmentFile |
| `SECRET_KEY` | `****` | `vault.yml` → `vault_app_secret_key` (Vault 암호화) | EnvironmentFile |
| `ZDM_DEFAULT_IP` | `192.168.3.94` | `group_vars/all/zdm.yml` | EnvironmentFile |
| `ZDM_DEFAULT_USER` | `admin@zconverter.com` | `group_vars/all/zdm.yml` | EnvironmentFile |

> **추가 — alembic 실행 시 (`app_run_alembic: true`):**  
> 위 동일 변수 15개를 Ansible `environment:` 키워드로 command 모듈에 직접 주입.  
> 파일 경유 없이 인메모리로 전달됨 (`ansible/roles/app/tasks/main.yml`).

**systemd unit:** `/etc/systemd/system/assessment-api.service`  
**EnvironmentFile:** `/opt/assessment/assessment-api.env` (mode `0600`, owner: `assessment`)  
**ExecStart:** `/opt/assessment/venv/bin/uvicorn assessment_engine.web.main:app --host 0.0.0.0 --port 8000`  
**실행 유저:** `assessment` (system user, nologin shell, home: `/opt/assessment`)

---

### worker-vm

api-vm과 환경변수 구성 **동일**. 차이점만 기록.

| 항목 | api-vm | worker-vm |
|---|---|---|
| 서비스명 | `assessment-api` | `assessment-worker` |
| ExecStart | `uvicorn assessment_engine.web.main:app ...` | `python -m assessment_engine.consumer` |
| EnvironmentFile | `/opt/assessment/assessment-api.env` | `/opt/assessment/assessment-worker.env` |
| alembic 실행 | O (`app_run_alembic: true`) | X (`app_run_alembic: false`) |

> `ansible/playbook-worker.yml`에서 `app_service_name: assessment-worker`로 선언.  
> app role이 동일하게 적용되므로 env 파일·systemd unit 모두 자동 생성.

---

### db-vm

**환경변수 없음.** Ansible이 설정 파일 및 SQL 명령으로 직접 구성.

| 설정 항목 | 값 | 방법 | 출처 파일 |
|---|---|---|---|
| `listen_addresses` | `'*'` | `lineinfile` → `postgresql.conf` | `roles/postgres/tasks/main.yml` |
| `shared_preload_libraries` | `'timescaledb'` | `lineinfile` → `postgresql.conf` | `roles/postgres/tasks/main.yml` |
| pg_hba 허용 CIDR | `10.0.10.64/26` | `lineinfile` → `pg_hba.conf` | `roles/postgres/tasks/main.yml` (`common.yml` → `engine_subnet_cidr`) |
| DB 유저 | `assessment` | `community.postgresql.postgresql_user` | `vault.yml` → `vault_db_user` |
| DB 유저 패스워드 | `****` | `community.postgresql.postgresql_user` | `vault.yml` → `vault_db_password` (Vault) |
| DB명 | `assessment` | `community.postgresql.postgresql_db` | `vault.yml` → `vault_db_name` |

**Cinder 볼륨:** `/dev/vdb` → `mkfs.ext4` → mount `/var/lib/postgresql` (`common.yml` → `db_volume_device`)

---

### mq-vm

**환경변수 없음.** Ansible이 `rabbitmqctl` CLI로 직접 구성.

| 설정 항목 | 값 | 방법 | 출처 파일 |
|---|---|---|---|
| vhost 생성 | `assessment` | `rabbitmqctl add_vhost` | `vault.yml` → `vault_mq_vhost` |
| 유저 생성 | `assessment` | `rabbitmqctl add_user` | `vault.yml` → `vault_mq_user` / `vault_mq_password` (Vault) |
| 유저 권한 | `".*" ".*" ".*"` | `rabbitmqctl set_permissions` | `roles/rabbitmq/tasks/main.yml` |
| Management Plugin | 활성화 | `rabbitmq-plugins enable rabbitmq_management` | `roles/rabbitmq/tasks/main.yml` |
| guest 유저 | 삭제 | `rabbitmqctl delete_user guest` | `roles/rabbitmq/tasks/main.yml` |

**Cinder 볼륨:** `/dev/vdb` → `mkfs.ext4` → mount `/var/lib/rabbitmq` (`common.yml` → `mq_volume_device`)  
> 설치 후 서비스 정지 → 볼륨 마운트 → 재기동 순서로 mnesia가 Cinder 위에 초기화됨.

---

### cache-vm

**환경변수 없음.** Ansible이 `redis.conf` 1개 항목만 변경.

| 설정 항목 | 값 | 방법 | 출처 파일 |
|---|---|---|---|
| `bind` | `0.0.0.0` | `lineinfile` → `redis.conf` | `roles/redis/tasks/main.yml` |

> fail-open 정책 — 재시작 시 cold start 허용. 볼륨 없음.

---

## 4. 코드 오류 수정 이력

문서 작성 중 발견한 오류:

| 파일 | 오류 내용 | 수정 내용 |
|---|---|---|
| `terraform/data.tf` | image data source 이름이 `debian12`이나 실제로는 Ubuntu 24.04 이미지를 참조 | `debian12` → `ubuntu24` 로 rename |
| `terraform/instances.tf` | `data.openstack_images_image_v2.debian12.id` 참조 5곳 | 동일하게 `ubuntu24`로 수정 |
