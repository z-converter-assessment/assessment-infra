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
`app.env.j2`와 `playbook-api.yml` / `playbook-worker.yml`의 `app_env` dict를 pydantic-settings 필드명으로 전면 수정.

| 변경 전 (틀림) | 변경 후 (맞음) |
|---|---|
| `DATABASE_URL=postgresql://...` | `POSTGRES_HOST=`, `POSTGRES_PORT=`, `POSTGRES_DB=`, `POSTGRES_USER=`, `POSTGRES_PASSWORD=` |
| `BROKER_URL=amqp://...` | `RABBITMQ_HOST=`, `RABBITMQ_PORT=`, `RABBITMQ_VHOST=`, `RABBITMQ_USER=`, `RABBITMQ_PASSWORD=` |
| — | `REDIS_HOST=`, `REDIS_PORT=` |

> `database_url`은 config.py 내부 `@property`로 개별 필드를 조합해 생성한다. 외부에서 주입하는 변수가 아님.

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
