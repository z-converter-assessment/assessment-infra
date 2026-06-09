# Agent 테스트 환경 — 구성·환경변수·실행 권한

> assessment-agent(1.0.0, C 바이너리 + Windows .exe) 테스트 플릿이 **어떻게 구성되고, 환경변수가 어떤 경로로 주입되며, 어떤 권한으로 실행되는지** 정리.
> 소스: `agent/terraform/*`, `agent/ansible/roles/{common,agent_binary,agent_env,agent_service}`, `agent/ansible/group_vars/`.
> 배포 모델: 수동(`site.yml`) — engine과 달리 CD 자동화 미반영.

---

## 1. 테스트 환경 구성

### Fleet (Terraform — `agent/terraform/`)
- **Linux 7종 × 4대 = 28대** + **Windows Server 2022 1대(옵션, `windows_vm_enabled`)**
  - apt 계열: `debian13`, `debian12`, `ubuntu2404`, `ubuntu2204`
  - rhel 계열: `rocky9`, `alma9`, `centos9` (dnf)
  - OS 매트릭스는 `terraform/variables.tf`의 `agent_os_map`에서 image_name·family·ssh_user·count로 관리. Windows는 boot-from-volume·cloudbase-init 때문에 `windows.tf` 별도.
- flavor: Linux 공용 1 vCPU / 1 GB / 20 GB.
- 네트워크: `agent-subnet 10.0.20.0/24`가 primary NIC. 옵션 멀티 NIC(`agent_extra_networks`, 네트워크 시각화 검증용). network·subnet·keypair는 **Horizon 수동 생성 → data source 참조**(Terraform이 생성 안 함). FIP 없음(사설 only, bastion ProxyJump 접속).

### 오케스트레이션 (`agent/ansible/site.yml` = 4개 플레이북 순차)
| 플레이북 | 역할 |
|---|---|
| `deploy.yml` | agent 본체 배포 — Linux: `common → agent_binary → agent_env → agent_service`, Windows: `agent_binary → agent_env → agent_service` (common 제외) |
| `services.yml` | **타깃 서버 시뮬레이션** — 호스트의 `agent_services`에 따라 nginx(web)·postgres(db)·redis(cache)·mosquitto(mq)·docker·podman(container)·node-exporter(monitor)·apache(app) 설치. 기본 `[]`, OS·host별 지정. Windows 제외 |
| `noise.yml` | 부하/이상 상황 주입 — CPU·IO·메모리 부하, agent 재시작, 1회 오프라인 (assessment 현실성 검증) |
| `health-check.yml` | `agent_workers` ping + `assessment-agent` 서비스 active 확인 |

- 인벤토리는 `scripts/gen_inventory.py`가 생성 — OS 그룹 + `agent_workers` + `service_*` + `noise_*` 그룹.

---

## 2. 환경변수 주입 경로 (OS별 상이)

### Linux — 파일 2개 렌더 → systemd `EnvironmentFile`
`agent_env` role이 `/etc/assessment-agent/`(dir `0750 root:assessment-agent`)에 렌더:

| 파일 | 권한 | 내용 | 비고 |
|---|---|---|---|
| `agent.env` | `0640 root:assessment-agent` | MQ 접속·라우팅·worker 설정 | 비밀 아님 |
| `agent.env.local` | `0640 root:assessment-agent` | MQ 자격증명 | `no_log: true` |

systemd unit이 **두 `EnvironmentFile=` 라인**으로 둘 다 로드 → agent 프로세스의 OS env로 주입.

### Windows — 머신 레벨 환경변수(레지스트리)
`agent_env` role이 `ansible.windows.win_environment`(`level: machine`)로 설정. MQ 호스트/라우팅 1세트 + 자격증명(별도 task, `no_log`). .exe 서비스가 머신 env에서 읽음.

### 값의 출처
| 출처 | 내용 |
|---|---|
| `group_vars/all/vars.yml` | 비밀 아닌 값 (라우팅 키·포트·다운로드 화이트리스트·agent identity) |
| `group_vars/all/vault.yml` | 비밀 (**engine vault.yml의 symlink** → 엔진과 동일 MQ 자격 사용, ADR-0009) |
| `gen_inventory.py` | `engine_mq_host` 런타임 주입 |

---

## 3. 주입되는 환경변수

### Linux `agent.env` (비밀 아님)
| 키 | 값(출처) |
|---|---|
| `RABBITMQ_HOST` | engine MQ 호스트 (gen_inventory 주입) |
| `RABBITMQ_PORT` | `5672` |
| `RABBITMQ_VHOST` | `assessment` |
| `RABBITMQ_EXCHANGE` | `assessment` |
| `RABBITMQ_ROUTING_KEY_INVENTORY` | `server.inventory` |
| `RABBITMQ_ROUTING_KEY_METRICS` | `server.metrics` |
| `RABBITMQ_ROUTING_KEY_ERROR` | `server.error` |
| `WORKER_TASK_EXCHANGE` | `assessment.tasks` |
| `WORKER_TASK_QUEUE_PREFIX` | `agent.tasks` |
| `WORKER_TASK_RESULT_KEY` | `task.result` |
| `WORKER_DOWNLOAD_ALLOWED_HOSTS` | `192.168.3.94` (ZDM 호스트 화이트리스트 — 비면 worker가 모든 download reject) |

### Linux `agent.env.local` (비밀)
| 키 | 값 |
|---|---|
| `RABBITMQ_USER` / `RABBITMQ_PASS` | vault MQ 자격 |
| `RABBITMQ_WORKER_USER` / `RABBITMQ_WORKER_PASS` | 동일 자격 재사용 (ADR-0009 — vault에 worker 항목 분리 시 갱신) |

> **라우팅 키·exchange 값은 엔진(`engine/ansible/group_vars/all/engine.yml`)과 반드시 일치**해야 하는 contract. agent는 `WORKER_TASK_*` prefix, 엔진은 `RABBITMQ_TASK_*` prefix지만 **값은 동일**해야 한다(호스트 관점 차이일 뿐).

### Windows (머신 env)
`RABBITMQ_HOST` · `RABBITMQ_PORT` · `RABBITMQ_VHOST` · `RABBITMQ_EXCHANGE` · `RABBITMQ_ROUTING_KEY_{INVENTORY,METRICS,ERROR}` · `RABBITMQ_USER` · `RABBITMQ_PASS`.

> ⚠️ **Windows 누락(결함 후보)**: Windows env 주입에는 `WORKER_TASK_*` · `WORKER_DOWNLOAD_ALLOWED_HOSTS` · `RABBITMQ_WORKER_*`가 **빠져 있다**(Linux엔 있음). 따라서 Windows agent는 worker(task.install consume) 설정·다운로드 화이트리스트가 없어, 설령 ZDM가 Windows를 지원해도 worker가 download를 reject한다. (Windows ZDM install 불가 사유 중 하나 — 더불어 엔진이 내려주는 ZDM 패키지가 Linux tarball+bash `install.sh` 전용이라 구조적으로도 불가.)

---

## 4. 실행 권한

### Linux — 비root 시스템 유저 + 무제한 sudo
- systemd `assessment-agent.service`: `User=assessment-agent` / `Group=assessment-agent`
  - `common` role이 만든 **system user** (`/usr/sbin/nologin`, home `/var/lib/agent-worker`, home 미생성).
- `common` role이 **NOPASSWD sudo 전권** 부여: `/etc/sudoers.d/assessment-agent` → `assessment-agent ALL=(ALL) NOPASSWD: ALL`.
  - → 평상시 비root지만 **암호 없이 임의 명령을 root로 상승** 가능. ZDM install·진단이 root를 요구하기 때문.
- systemd 하드닝 **의도적으로 최소화**: `NoNewPrivileges`·CapabilityBounding **비활성**(sudo 상승 허용 위해), `PrivateTmp=yes`·`RestrictRealtime=yes`만. WorkingDirectory `/var/lib/agent-worker`(0750).
- RHEL 계열: **SELinux permissive**(ADR-0012) — 받은 스크립트를 `var_lib_t`/`tmp_t`에서 실행해도 AVC 차단 없음. Ubuntu(AppArmor 프로파일 없음 → 사실상 unconfined)와 동작 일치 목적.

### Windows — LocalSystem
- `ansible.windows.win_service`로 .exe를 서비스 등록(`start_mode: auto`). **서비스 계정 미지정 → 기본 LocalSystem**(최고 권한 = 사실상 관리자).

**요약**: 양쪽 모두 **사실상 root/관리자 등가 권한**으로 동작 — Linux는 전용 유저 + NOPASSWD sudo ALL, Windows는 LocalSystem. ZDM 설치가 관리자 권한을 요구하기 때문이며 의도된 설계다.

---

## 알려진 이슈

- **RHEL 계열 ZDM install**: SELinux enforcing이 차단 → permissive로 해소(ADR-0012). 배포 시 적용.
- **Windows ZDM install**: 엔진 ZDM 패키지가 Linux 전용(`...Linux.tar.gz` + bash `install.sh`)이고, Windows env에 `WORKER_*` 미주입 → 현재 구성으론 불가. Windows 지원 시 (1) Windows ZDM 패키지, (2) 엔진의 OS별 패키지 경로 분기, (3) Windows env에 WORKER_* 주입 필요.
