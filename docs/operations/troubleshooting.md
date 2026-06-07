# Troubleshooting — 배포 트러블슈팅 기록

초기 배포 과정에서 발생한 문제들의 원인과 해결책을 기록.  
재배포·신규 환경 구축 시 참고.

---

## 1. `terraform destroy` 시 보안그룹 삭제 실패 (409 Conflict)

**증상**
```
Error: Error deleting openstack_networking_secgroup_v2: 409 Conflict
```

**원인**  
이전 `terraform apply`에서 VM 생성 도중 실패한 경우, VM은 삭제됐지만 Neutron Port(`DOWN` 상태)가 남아 있다.  
이 고아 포트(orphaned port)들이 보안그룹을 여전히 참조하고 있어 SG 삭제가 거부된다.

**해결**
```bash
# DOWN 상태 포트 목록 확인
openstack port list --format json | jq '.[] | select(.status == "DOWN") | {id, name}'

# 고아 포트 삭제 (각 포트 ID 대입)
openstack port delete <port-id>

# 삭제 후 terraform destroy 재시도
terraform destroy
```

> `default` 보안그룹은 OpenStack 시스템이 프로젝트마다 자동 생성하는 SG로 삭제 불가. Terraform 관리 대상이 아니므로 무시해도 된다.

---

## 2. `python3.12` 패키지 없음 (Debian 12 환경)

**증상**
```
No package matching 'python3.12' is available
```

**원인**  
초기 OS 이미지가 Debian 12(Bookworm)였는데, Debian 12 기본 repo에는 python3.11만 있다.  
assessment-engine wheel이 Python 3.12를 요구하므로 버전 불일치.

**해결**  
OS 이미지를 **Ubuntu 24.04 LTS(Noble)** 로 전환.  
Ubuntu 24.04 기본 repo에는 python3.12가 포함돼 있어 추가 repo 없이 설치 가능.

```hcl
# terraform/variables.tf
variable "image_name" {
  default = "ubuntu24.04_x64_uefi_3.5G"
}
```

Ansible `ansible_user`도 `debian` → `ubuntu`로 변경.

---

## 3. `become_user` 사용 시 ACL chmod 오류

**증상**
```
chmod: invalid mode: 'A+user:assessment:rx:allow'
setfacl: option needs an argument -- 'f'
```

**원인**  
Ansible이 `become_user`로 권한을 낮출 때 임시 파일 전송을 위해 ACL(setfacl)을 사용한다.  
`pipelining`이 꺼져 있으면 Ansible이 ACL 방식으로 폴백하는데, 환경에 따라 오작동한다.

**해결 1** — `pipelining = True` 설정 (`ansible/ansible.cfg`)
```ini
[defaults]
pipelining = True
```
pipelining을 켜면 ACL 대신 SSH 파이프로 전송하므로 ACL 문제 자체가 우회된다.

**해결 2** — `acl` 패키지 설치 보장 (이중 안전망)
```yaml
- name: install python3.12, venv, acl
  apt:
    name:
      - python3.12
      - python3.12-venv
      - acl
```

---

## 4. TimescaleDB 패키지 버전 충돌

**증상**
```
timescaledb-2-postgresql-16 : Depends: postgresql-16 (>= 16.14) but 16.13+... is installed
```

**원인**  
TimescaleDB 2.27.1이 `postgresql-16 >= 16.14`를 요구하는데, Ubuntu 24.04 기본 apt repo에는 `16.13`만 있다.

**해결**  
설치 전 PGDG(PostgreSQL Global Development Group) 공식 apt repo를 추가해 최신 postgresql-16을 받도록 변경.

```yaml
- name: add PGDG apt signing key
  apt_key:
    url: https://www.postgresql.org/media/keys/ACCC4CF8.asc

- name: add PGDG apt repository
  apt_repository:
    repo: "deb https://apt.postgresql.org/pub/repos/apt noble-pgdg main"
    filename: pgdg
    update_cache: true
```

TimescaleDB repo도 ubuntu/noble 기준으로 변경:
```yaml
- name: add TimescaleDB apt repository
  apt_repository:
    repo: "deb https://packagecloud.io/timescale/timescaledb/ubuntu/ noble main"
```

---

## 5. RabbitMQ Cloudsmith repo 차단

**증상**
```
TASK [rabbitmq : add Cloudsmith Erlang apt repository]
Failed to update apt cache: ... Could not connect to ppa1.rabbitmq.com
```

**원인**  
내부망 VM들이 외부 인터넷에 직접 접근할 수 없는 폐쇄망 환경.  
`ppa1.rabbitmq.com` (Cloudsmith) 도메인이 방화벽에 막혀 있다.  
`packagecloud.io`(TimescaleDB 등)는 허용돼 있어 혼동될 수 있음.

**해결**  
Cloudsmith repo 관련 task 전체 제거. Ubuntu 24.04 universe repo에 포함된 RabbitMQ를 그대로 사용.

```yaml
- name: install Erlang and rabbitmq-server
  apt:
    name:
      - erlang
      - rabbitmq-server
    state: present
    update_cache: true
```

> Ubuntu 24.04 universe의 RabbitMQ 버전이 구버전일 수 있으나, 현재 트래픽 규모에서는 문제없음.

---

## 6. wheel 파일명 `v` 접두사 불일치

**증상**
```
Could not find or access 'wheels/assessment_engine-v0.1.0-py3-none-any.whl'
```

**원인**  
`engine.yml`에 `engine_version: "v0.1.0"`으로 설정했는데, GitHub Release가 생성한 실제 wheel 파일명은 `v` 없이 `assessment_engine-0.1.0-py3-none-any.whl`.  
Python 패키징 컨벤션상 wheel 파일명에는 `v` 접두사를 붙이지 않는다.

**해결**  
`engine.yml`의 `engine_version` 값에서 `v` 제거.

```yaml
# 틀림
engine_version: "v0.1.0"

# 맞음
engine_version: "0.1.0"
```

---

## 7. Alembic `No 'script_location' key found` 오류

**증상**
```
alembic.config.CommandError: No 'script_location' key found in configuration.
```

**원인**  
wheel 내부 `_alembic.ini`의 `script_location`이 `%(here)s/migrations`를 가리키는데,  
실제 디렉토리명은 `_migrations`(언더스코어 접두사). 경로가 존재하지 않아 실패.

```
site-packages/assessment_engine/
├── _alembic.ini       # script_location = %(here)s/migrations  (언더스코어 없음)
├── _migrations/       # 실제 디렉토리 (언더스코어 있음)
```

**해결**  
심볼릭 링크로 `migrations` → `_migrations` 연결.

```yaml
- name: create migrations symlink (_migrations → migrations)
  file:
    src: "{{ app_venv }}/lib/python3.12/site-packages/assessment_engine/_migrations"
    dest: "{{ app_venv }}/lib/python3.12/site-packages/assessment_engine/migrations"
    state: link
```

---

## 8. Alembic 실행 시 `pyproject.toml` permission denied

**증상**
```
PermissionError: [Errno 13] Permission denied: '/root/pyproject.toml'
```

**원인**  
alembic이 현재 작업 디렉토리에서 `pyproject.toml`을 탐색하는데, `become_user: assessment`임에도 `command` 모듈이 root 홈(`/root`)을 cwd로 잡는 경우가 있다.  
`/root`는 `assessment` 유저가 읽을 수 없다.

**해결**  
`command` 모듈에 `chdir` 또는 alembic 실행 전 `cd {{ app_dir }}`로 작업 디렉토리 명시.

```yaml
- name: run alembic migrations
  command: >
    {{ app_venv }}/bin/alembic
    -c {{ app_venv }}/lib/python3.12/site-packages/assessment_engine/_alembic.ini
    upgrade head
  args:
    chdir: "{{ app_dir }}"
  become_user: "{{ app_user }}"
```

---

## 9. Alembic DNS 해석 실패 (환경변수 이름 불일치)

**증상**
```
sqlalchemy.exc.OperationalError: (asyncpg.exceptions.InvalidCatalogNameError)
  could not connect to server: Name or service not known
  host "postgres"
```

**원인**  
assessment-engine의 `config.py`는 **pydantic-settings** 기반으로 개별 환경변수를 읽는다:

```python
postgres_host: str = "postgres"   # POSTGRES_HOST
postgres_db:   str = "assessment" # POSTGRES_DB
...
```

기본값 `"postgres"`는 Docker 컨테이너 환경용 DNS 이름이다.  
`app.env.j2`가 `DATABASE_URL`/`BROKER_URL` 형식으로 작성돼 있어 pydantic-settings가 이를 읽지 못하고 기본값(`"postgres"`)으로 폴백 → DNS 해석 실패.

**확인 방법 (api-vm에서 직접 테스트)**
```bash
sudo -u assessment bash -c '
  export POSTGRES_HOST=<db-vm-ip>
  export POSTGRES_DB=assessment
  export POSTGRES_USER=assessment
  export POSTGRES_PASSWORD=<password>
  export POSTGRES_PORT=5432
  /opt/assessment/venv/bin/alembic \
    -c /opt/assessment/venv/lib/python3.12/site-packages/assessment_engine/_alembic.ini \
    upgrade head
'
# → 6개 마이그레이션 정상 완료
```

**해결**  
`app.env.j2`와 `playbook-api.yml` / `playbook-consumer.yml`의 `app_env` dict를 pydantic-settings 필드명으로 전면 수정.

| 변경 전 (틀림) | 변경 후 (맞음) |
|---|---|
| `DATABASE_URL=postgresql://...` | `POSTGRES_HOST=`, `POSTGRES_PORT=`, `POSTGRES_DB=`, `POSTGRES_USER=`, `POSTGRES_PASSWORD=` |
| `BROKER_URL=amqp://...` | `RABBITMQ_HOST=`, `RABBITMQ_PORT=`, `RABBITMQ_VHOST=`, `RABBITMQ_USER=`, `RABBITMQ_PASSWORD=` |
| — | `REDIS_HOST=`, `REDIS_PORT=` |

> `database_url`은 config.py 내부 `@property`로 개별 필드를 조합해 생성한다. 외부에서 주입하는 변수가 아님.

---

---

## 10. uvicorn `Could not import module "assessment_engine.main"`

**증상**
```
ERROR: Error loading ASGI app. Could not import module "assessment_engine.main".
```

**원인**  
`playbook-api.yml`의 `app_exec_start`가 `assessment_engine.main:app`으로 설정돼 있었는데, 실제 wheel 패키지 구조는 아래와 같다.

```
assessment_engine/
├── web/main.py        ← FastAPI app (실제 엔트리포인트)
├── consumer/main.py   ← Worker
└── diagnostic/main.py
```

최상위에 `main.py`가 없으므로 import 실패.

**확인 방법**
```bash
find /opt/assessment/venv/lib/python3.12/site-packages/assessment_engine/ -name "main.py"
```

**해결**  
`playbook-api.yml` `app_exec_start` 수정:
```yaml
# 변경 전
app_exec_start: "{{ app_venv }}/bin/uvicorn assessment_engine.main:app ..."

# 변경 후
app_exec_start: "{{ app_venv }}/bin/uvicorn assessment_engine.web.main:app ..."
```

운영 중인 VM에 즉시 반영:
```bash
sudo sed -i 's|assessment_engine.main:app|assessment_engine.web.main:app|' \
  /etc/systemd/system/assessment-api.service
sudo systemctl daemon-reload && sudo systemctl restart assessment-api
```

---

## 11. Consumer `assessment-consumer` 바이너리 없음

**증상**  
`playbook-consumer.yml`의 `app_exec_start: ".../bin/assessment-consumer"` 설정으로 서비스 기동 실패.

**원인**  
wheel에 `assessment-consumer` console script entry point가 정의돼 있지 않아 `venv/bin/`에 해당 바이너리가 생성되지 않는다.  
대신 consumer 패키지에 `__main__.py`가 있어 모듈 실행 방식을 지원한다.

**확인 방법**
```bash
ls /opt/assessment/venv/bin/ | grep assess   # 결과 없음
ls /opt/assessment/venv/lib/python3.12/site-packages/assessment_engine/consumer/
# __main__.py 존재 확인
```

**해결**  
`playbook-consumer.yml` 수정:
```yaml
# 변경 전
app_exec_start: "{{ app_venv }}/bin/assessment-consumer"

# 변경 후
app_exec_start: "{{ app_venv }}/bin/python -m assessment_engine.consumer"
```

---

## 12. RabbitMQ AMQP `Connection.Close` — 권한 없음

**증상**
```
pamqp.exceptions.AMQPInternalError: ("one of ['Connection.OpenOk']",
  <Connection.Close object ...>)
ERROR: Application startup failed. Exiting.
```

**원인**  
`assessment` 유저가 `assessment` vhost에 대한 권한이 전혀 없는 상태였다.

Ansible role의 권한 설정 task에 버그가 있었다:

```yaml
# 버그 있는 코드
- name: check current user permissions
  command: rabbitmqctl list_user_permissions {{ vault_mq_user }}
  register: current_perms

- name: set user permissions on vhost
  command: rabbitmqctl set_permissions -p {{ vault_mq_vhost }} {{ vault_mq_user }} ".*" ".*" ".*"
  when: vault_mq_vhost not in current_perms.stdout
```

`rabbitmqctl list_user_permissions assessment` 출력 헤더가 `Listing permissions for user "assessment" ...`이므로,  
`"assessment" not in current_perms.stdout`이 항상 **False**로 평가 → 권한 설정 task가 매번 스킵됐다.

**확인 방법** (mq-vm에서)
```bash
sudo rabbitmqctl list_user_permissions assessment
# 출력이 헤더만 있고 vhost 행이 없으면 권한 미설정 상태
```

**즉시 수동 복구**
```bash
sudo rabbitmqctl set_permissions -p assessment assessment ".*" ".*" ".*"
```

**Ansible role 수정** — 조건 체크 제거, 매 실행마다 덮어쓰기:
```yaml
- name: set user permissions on vhost
  command: rabbitmqctl set_permissions -p {{ vault_mq_vhost }} {{ vault_mq_user }} ".*" ".*" ".*"
  register: perms_result
  changed_when: true
  failed_when: perms_result.rc != 0
```

---

## 13. Terraform — flavor `c1_m2_r40` 없음

**증상**
```
Error: Unable to find flavor with name c1_m2_r40
  with openstack_compute_instance_v2.mq_vm
  with openstack_compute_instance_v2.db_vm
```

**원인**  
`terraform.tfvars`의 `flavor_mq`, `flavor_db`가 `c1_m2_r40`으로 설정돼 있으나 해당 환경에 존재하지 않는 flavor였다.

**확인 방법**
```bash
OS_CLOUD=openstack openstack flavor list
```

**해결**  
`terraform.tfvars`에서 존재하는 가장 가까운 flavor로 교체:

```hcl
flavor_mq = "c2_m2_r40"  # c1_m2_r40 미제공 → 2 vCPU / 2 GB 폴백
flavor_db = "c2_m4_r30"  # c1_m2_r40 미제공 → 2 vCPU / 4 GB 폴백
```

> `terraform.tfvars.example` 주석에 폴백 flavor가 이미 명시돼 있으므로, 신규 환경 세팅 시 먼저 `openstack flavor list`로 가용 목록 확인 후 매핑할 것.

---

## 14. Ansible SSH 키 권한 오류

**증상**
```
WARNING: UNPROTECTED PRIVATE KEY FILE!
Permissions 0664 for '/home/debian/.ssh/engine-key.pem' are too open.
Load key "/home/debian/.ssh/engine-key.pem": bad permissions
Permission denied (publickey).
```

**원인**  
`engine-key.pem` 파일 권한이 `0664`로 설정돼 있어 SSH 클라이언트가 키 사용을 거부한다.

**해결**
```bash
chmod 0400 ~/.ssh/engine-key.pem
```

---

## 15. postgres role — `apt_key` / `apt_repository` Debian 13에서 제거됨

**증상**
```
Failed to find required executable "apt-key" in paths: /usr/local/sbin:/usr/local/bin:...
```

**원인**  
Debian 13(Trixie)에서 `apt-key` 명령이 완전 제거됐다. Ansible의 `apt_key` 모듈과 `apt_repository` 모듈은 내부적으로 `apt-key`를 사용하므로 동작하지 않는다.

**해결**  
`/etc/apt/keyrings/` + `signed-by` 방식으로 전환:

```yaml
- name: create /etc/apt/keyrings directory
  file:
    path: /etc/apt/keyrings
    state: directory
    mode: "0755"

- name: download PGDG apt signing key
  get_url:
    url: https://www.postgresql.org/media/keys/ACCC4CF8.asc
    dest: /etc/apt/keyrings/pgdg.asc
    mode: "0644"

- name: add PGDG apt repository
  copy:
    content: "deb [signed-by=/etc/apt/keyrings/pgdg.asc] https://apt.postgresql.org/pub/repos/apt trixie-pgdg main\n"
    dest: /etc/apt/sources.list.d/pgdg.list
    mode: "0644"
  register: pgdg_repo

- name: update apt cache
  apt:
    update_cache: true
  when: pgdg_repo.changed or tsdb_repo.changed
```

> Debian 13 환경에서 외부 apt repo를 추가할 때는 `apt_key` / `apt_repository` 모듈 대신 이 패턴을 표준으로 사용할 것.

---

## 16. postgres role — pgvector extension 설치 및 권한

**증상 1 — 패키지 없음**
```
extension "vector" is not available
Could not open extension control file ".../extension/vector.control": No such file or directory.
```

**증상 2 — 권한 부족**
```
asyncpg.exceptions.InsufficientPrivilegeError: permission denied to create extension "vector"
HINT: Must be superuser to create this extension.
```

**원인**  
- `postgresql-16-pgvector` 패키지가 설치되지 않아 extension 파일 자체가 없었다.  
- Alembic이 `assessment` 유저 권한으로 `CREATE EXTENSION vector`를 실행하는데, extension 생성은 superuser만 가능하다.

**해결**  
postgres role에서 superuser(`postgres`)로 extension을 미리 생성:

```yaml
- name: install postgresql, timescaledb, pgvector
  apt:
    name:
      - "postgresql-{{ pg_version }}"
      - "timescaledb-2-postgresql-{{ pg_version }}"
      - "postgresql-{{ pg_version }}-pgvector"
    state: present

- name: enable pgvector extension (superuser required)
  become_user: postgres
  community.postgresql.postgresql_ext:
    name: vector
    db: "{{ vault_db_name }}"
    state: present
```

---

## 17. app role — `python3-packaging` 없음

**증상**
```
Failed to import the required Python library (packaging) on api-vm's Python /usr/bin/python3.13.
No module named 'packaging'
```

**원인**  
Ansible의 `pip` 모듈이 내부적으로 `packaging` 라이브러리를 사용하는데, Debian 13 기본 Python 환경에 설치돼 있지 않다.

**해결**  
app role의 패키지 설치 task에 추가:

```yaml
- name: install python3, venv, acl, packaging
  apt:
    name:
      - python3
      - python3-venv
      - python3-packaging
      - acl
    state: present
```

---

## 18. `engine_subnet_cidr` CIDR 범위 불일치

**증상**
```
asyncpg.exceptions.InvalidAuthorizationSpecificationError:
  no pg_hba.conf entry for host "10.0.10.23", user "assessment", database "assessment", no encryption
```

**원인**  
`common.yml`의 `engine_subnet_cidr`가 `10.0.10.64/26`으로 설정돼 있었다.  
이 범위는 `10.0.10.64 ~ 10.0.10.127`만 커버하는데, 실제 api-vm IP `10.0.10.23`은 이 범위 밖이었다.

**확인 방법**
```bash
# 각 VM의 실제 IP 확인
terraform -chdir=engine/terraform output
```

**해결**  
engine subnet 전체(`10.0.10.0/24`)로 수정:

```yaml
# group_vars/all/common.yml
engine_subnet_cidr: "10.0.10.0/24"
```

수정 후 `playbook-db.yml` 재실행 → pg_hba.conf 자동 갱신.

---

## 19. ollama role — systemd override 디렉토리 없음

**증상**
```
Destination directory /etc/systemd/system/ollama.service.d does not exist
```

**원인**  
ollama 공식 install script가 서비스를 설치하지만 `ollama.service.d/` drop-in 디렉토리는 생성하지 않는다. Ansible `copy` 모듈은 상위 디렉토리를 자동 생성하지 않는다.

**해결**  
override 파일 작성 task 앞에 디렉토리 생성 task 추가:

```yaml
- name: create ollama systemd override directory
  file:
    path: /etc/systemd/system/ollama.service.d
    state: directory
    mode: "0755"

- name: write ollama systemd override (host·port 변경)
  copy:
    dest: /etc/systemd/system/ollama.service.d/override.conf
    ...
```

---

## 20. ollama 모델 저장 경로 — `~/.ollama` 아님

**증상**  
bastion에서 `ollama pull` 후 `tar czf ... -C ~ .ollama` 실행 시:
```
tar: .ollama: Cannot stat: No such file or directory
```

**원인**  
ollama install script가 생성하는 `ollama` systemd 서비스 유저의 home이 `/usr/share/ollama`이다.  
모델은 `~/.ollama`가 아닌 `/usr/share/ollama/.ollama/`에 저장된다.

**확인 방법**
```bash
sudo find /usr/share/ollama -maxdepth 3
```

**해결**
```bash
sudo tar czf engine/ansible/files/ollama/ollama-models.tar.gz \
  -C /usr/share/ollama .ollama
```

---

## 21. agent terraform — 이미지 이름 불일치

**증상**
```
Error: Error retrieving image with name "ubuntu22.04_x64_uefi_3.5G": No image found
Error: Error retrieving image with name "almalinux9_x64_uefi_10G": No image found
...
```

**원인**  
`variables.tf` default의 이미지 이름이 실제 OpenStack 환경의 이미지 이름과 달랐다.

**확인 방법**
```bash
OS_CLOUD=openstack openstack image list --status active -f value -c Name
```

**해결**  
`terraform.tfvars`에서 `agent_os_map` 전체를 override해 실제 이미지명으로 교체:

| OS 키 | 기본값 (틀림) | 실제 이미지명 |
|---|---|---|
| ubuntu2204 | `ubuntu22.04_x64_uefi_3.5G` | `ubuntu22.04_x64_uefi_2.2G` |
| alma9 | `almalinux9_x64_uefi_10G` | `alma9_x64_uefi_10G` |
| centos9 | `centos-stream9_x64_uefi_10G` | `centos9stream_x64_uefi_10G` |
| windows2022 | `windows-server-2022_x64_uefi_40G` | `win2022_x64_uefi_40G_template` |

> 신규 환경 세팅 시 반드시 `openstack image list`로 실제 이름 확인 후 `terraform.tfvars`에 `agent_os_map` 전체를 명시할 것.

---

## 22. agent terraform — `No valid host was found` (하이퍼바이저 용량 부족)

**증상**
```
Error: Error waiting for instance to become ready: unexpected state 'ERROR', wanted target 'ACTIVE'
openstack server show <id> → fault.message: "No valid host was found."
```

**원인**  
프로젝트 쿼터(instances: 1000, cores: 2000)는 충분하지만, 실제 OpenStack 컴퓨트 노드의 물리 자원(RAM/CPU)이 부족했다.  
agent VM 30대를 동시에 생성 시도했을 때 하이퍼바이저 스케줄러가 배치 가능한 물리 호스트를 찾지 못했다.

**프로젝트 쿼터 vs 물리 용량 차이**  
- 쿼터: OpenStack DB에 저장된 소프트 제한 (관리자 설정)  
- 물리 용량: 실제 컴퓨트 노드의 RAM/CPU 합계 (하드 제한)  
둘은 독립적으로 관리되며, 쿼터가 여유 있어도 물리 노드가 꽉 차면 `No valid host was found` 발생.

**현 환경 제약**  
엔진 6대 + 에이전트 4대 = **총 10대**가 현재 클러스터의 수용 한계.

**해결**  
`terraform.tfvars`의 `agent_os_map` count를 4 → 1로 줄여 재적용:

```hcl
agent_os_map = {
  debian13 = { ..., count = 1 }
  debian12 = { ..., count = 1 }
  ...
}
```

근본 해결은 OpenStack 관리자에게 컴퓨트 노드 증설 요청.

---

## 요약 테이블

| # | 문제 | 원인 한 줄 요약 | 해결책 |
|---|---|---|---|
| 1 | SG 삭제 409 | 고아 Neutron 포트가 SG 참조 | `openstack port delete` 후 destroy |
| 2 | python3.12 없음 | Debian 12 기본 repo에 3.12 없음 | Ubuntu 24.04로 이미지 교체 |
| 3 | ACL chmod 오류 | pipelining 꺼짐 → ACL 폴백 오작동 | `pipelining = True` + `acl` 패키지 |
| 4 | TimescaleDB 의존성 충돌 | Ubuntu 기본 pg 16.13, TS가 16.14 요구 | PGDG apt repo 추가로 최신 pg 설치 |
| 5 | RabbitMQ Cloudsmith 차단 | 폐쇄망 방화벽이 ppa1.rabbitmq.com 차단 | Cloudsmith 제거, Ubuntu universe 사용 |
| 6 | wheel 파일 못 찾음 | `v` 접두사 있는 버전 문자열 vs 파일명 불일치 | `engine_version`에서 `v` 제거 |
| 7 | Alembic script_location 없음 | `_migrations` vs `migrations` 디렉토리명 불일치 | 심볼릭 링크 `migrations → _migrations` |
| 8 | pyproject.toml permission denied | alembic cwd가 `/root` → assessment 유저 읽기 불가 | `chdir: "{{ app_dir }}"` 명시 |
| 9 | DNS `postgres` 해석 실패 | env 파일 키가 `DATABASE_URL`로 틀림, pydantic이 기본값 사용 | `POSTGRES_*` / `RABBITMQ_*` 개별 키로 교체 |
| 10 | uvicorn ASGI import 실패 | 엔트리포인트가 `assessment_engine.main` (존재 안 함) | `assessment_engine.web.main:app`으로 수정 |
| 11 | consumer 바이너리 없음 | wheel에 console script 미등록 | `python -m assessment_engine.consumer`로 변경 |
| 12 | AMQP Connection.Close | Ansible when 조건 버그로 vhost 권한 설정 스킵 | 권한 task의 when 조건 제거, 무조건 실행 |
| 13 | flavor `c1_m2_r40` 없음 | 환경에 존재하지 않는 flavor 이름 | `openstack flavor list` 확인 후 `c2_m2_r40` / `c2_m4_r30` 폴백 |
| 14 | SSH 키 권한 0664 | pem 파일 권한이 너무 열려 있음 | `chmod 0400 ~/.ssh/engine-key.pem` |
| 15 | `apt_key` 없음 (Debian 13) | Debian 13에서 `apt-key` 명령 제거 | keyrings/ + signed-by 방식으로 전환 |
| 16 | pgvector 설치/권한 오류 | 패키지 미설치 + `assessment` 유저는 extension 생성 불가 | `postgresql-16-pgvector` 설치 + postgres 유저로 `postgresql_ext` 실행 |
| 17 | `python3-packaging` 없음 | Ansible pip 모듈 의존성 미충족 | `python3-packaging` apt 설치 추가 |
| 18 | pg_hba.conf CIDR 불일치 | `10.0.10.64/26`이 실제 VM IP 범위 밖 | `engine_subnet_cidr: "10.0.10.0/24"` 수정 |
| 19 | ollama override 디렉토리 없음 | install script가 drop-in 디렉토리 미생성 | `file` task로 디렉토리 사전 생성 |
| 20 | ollama 모델 경로 오류 | 모델이 `~/.ollama`가 아닌 `/usr/share/ollama/.ollama`에 저장 | tarball 경로를 `/usr/share/ollama`로 수정 |
| 21 | agent 이미지 이름 불일치 | variables.tf 기본값과 실제 환경 이미지명 차이 | `openstack image list` 확인 후 `agent_os_map` override |
| 22 | `No valid host was found` | 프로젝트 쿼터는 여유 있지만 하이퍼바이저 물리 용량 초과 | count 줄이거나 컴퓨트 노드 증설 요청 |
