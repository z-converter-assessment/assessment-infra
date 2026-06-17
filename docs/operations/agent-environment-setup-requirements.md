# Agent 환경 구성 — 요구사항

> 작성일: 2026-06-17 · 전제: engine v0.7.0 배포 완료(API·MQ·pgAdmin 가동)
> 목적: assessment-agent 플릿을 띄우고 engine과 연결(MQ 발행 + ZDM install)하기 위한 구성 요구사항 정의.
> 관련: [`agent-test-environment.md`](agent-test-environment.md)(플릿 구성·주입 경로) · [`agent-binary-image-coverage.md`](agent-binary-image-coverage.md)(OS별 접근·배포 로직) · [`deploy-walkthrough.md`](deploy-walkthrough.md)

## 0. 목표 (Goal)

**이번 구성 범위 (2026-06-17 확정):**
- **Linux ~30대 — OS 버전·firmware(bios/uefi) 다양하게.** cloud-init 정상 OS만(**redhat·suse·tencent 제외**). py<3.7(el7/el8·rocky8·ubuntu18)은 포함하되 정적 바이너리 수동 배포.
- **Windows 8버전 1대씩** — 2003·2008·2012·2012R2·2016·2019·2022·2025 각 1대. terraform `windows_os_map`에 추가해 **일단 부팅**(2003 32bit·2008 NT6.0은 agent 미지원, 부팅 확인만).
- **로컬 서비스 전체 설치** — 각 agent에 service_db·cache·mq·web·app·container·monitor 전부(점검 대상 워크로드 시뮬레이션).
- **noise 적용** — noise_* role로 재시작·offline·부하 시뮬레이션 켬.
- keypair: `new-bastion-key`(engine-key.pem 매칭).

## 1. 사전 조건 (engine 측 — 구성 시작 전 확인)

- [ ] engine-vm 가동 + API(`:8000`) health OK
- [ ] RabbitMQ(`:5672` AMQP) 도달 가능 — agent는 이 broker로 inventory·task.result 발행
- [ ] engine `server_inventory` 테이블 조회 가능(검증용)
- [ ] **MQ 자격증명**: `vault.yml`의 `vault_mq_user`/`vault_mq_password`(현재 `assessment`) — engine·agent 공용(agent vault는 engine vault symlink)
- [ ] engine MQ 호스트 IP — `scripts/gen-inventory.sh`가 engine-vm 사설 IP를 자동 주입(`engine_mq_host`). 엔진 재배포로 IP 바뀌었으면 inventory 재생성 필요

## 2. 대상 플릿 정의

- **OS 매트릭스·대수**: `agent/terraform/variables.tf`의 `agent_os_map`(Linux)·`agent_legacy_os_map`(centos6·ubuntu18)·`windows.tf`(Windows)에서 관리.
  - 각 OS: `image_name` · `family` · `ssh_user` · `count`
- **이번 구성 대상 — Linux ~30대 (버전·firmware 다양, cloud-init 정상 OS만)**:

  | OS군 | 포함 버전·firmware | 대수 | 배포경로 |
  |---|---|---|---|
  | debian | 10(bios)·11(bios)·12(bios/uefi)·13(bios/uefi) | 6 | 표준 |
  | ubuntu | 18(bios)·20(bios/uefi)·22(bios/uefi)·24(bios/uefi) | 7 | 18=수동(py3.6)/그외 표준 |
  | rocky | 8(bios/uefi)·9(bios/uefi) | 4 | 8=수동(py3.6)/9=표준 |
  | alma | 8(bios)·9(bios/uefi) | 3 | 8=수동/9=표준 |
  | centos | 7(bios)·8(bios)·8stream(bios)·9stream(bios/uefi) | 5 | 7/8=수동·9s=표준 |
  | oracle | 7(bios)·8(bios)·9(bios/uefi) | 4 | 7/8=수동·9=표준 |
  | amazon | 2(bios)·2023(bios) | 2 | 2=수동·2023=표준 |

  > 합계 **~31대**(±조정). 전부 cloud-init 정상 → 표준 SSH 접근(rescue 불필요). py<3.7(el7/el8·rocky8·ubuntu18)은 정적 바이너리 수동 배포.
  > 정확한 glance 이미지명은 terraform `agent_os_map`에서 확정(부팅결함 oracle7_uefi·centos8stream_uefi_lvm 등은 제외).
  > **제외 OS**: redhat·suse·tencent(cloud-init 부재 — 추후 rescue 포함 시 별도).

- **Windows 8대 (OS 버전별 1대, `windows_os_map`)**: win2003·win2008·win2012·win2012R2·win2016·win2019·win2022·win2025 각 1대.
  - 2003(x86 32bit)·2008(NT6.0)은 **바이너리 미지원** → 부팅 확인만. 2012R2~2025는 modern/win7 바이너리 커버.
  - boot-from-volume + cloudbase-init(WinRM). flavor `windows`.
- 참고(접근 난이도 — 본 세션 실측, `agent-binary-image-coverage.md`):
  - **표준 배포 가능**(cloud-init 정상 + python≥3.7): debian10~13 · ubuntu20.04+ · rocky9 · alma9 · centos9stream · oracle9 · amazon2023 · tencent4(py3.11)
  - **cloud-init 부재 → rescue 키주입 필요**: redhat 전 버전 · suse12/15 · tencent(접근만)
  - **python<3.7 → 정적 바이너리 수동 배포**: el7/el8 · rocky8 · ubuntu18 · suse12/15
  - **부팅/이미지 결함**: oracle7_uefi · suse12_uefi · centos8stream_uefi_lvm

### 2-1. OS별 종합 매핑 (서브넷 · 주입 바이너리 · 배포경로)

> Linux 31대 — 전부 glibc ≥2.17 → **`assessment-agent-linux-x86_64`(modern)** 단일 바이너리. (centos6 등 glibc2.12 legacy는 본 구성에 없음.)

| # | OS 키 | 이미지 | test 서브넷(그룹) | dual → | 주입 바이너리 | 배포경로(py) |
|---|---|---|---|---|---|---|
| 1 | debian10 | debian10_x64_bios_2G | test-net (G1) | -02 | linux-x86_64 | 표준(3.7) |
| 2 | debian11 | debian11_x64_bios_3G | test-net | — | linux-x86_64 | 표준(3.9) |
| 3 | debian12bios | debian12_x64_bios_3G | test-net | — | linux-x86_64 | 표준 |
| 4 | debian12uefi | debian12_x64_uefi_3G | test-net | — | linux-x86_64 | 표준 |
| 5 | debian13bios | debian13_x64_bios_3G | test-net-02 (G2) | -03 | linux-x86_64 | 표준 |
| 6 | debian13uefi | debian13_x64_uefi_3G | test-net-02 | — | linux-x86_64 | 표준 |
| 7 | ubuntu18 | ubuntu18.04_x64_bios_2.2G | test-net-02 | — | linux-x86_64 | 수동(3.6) |
| 8 | ubuntu20bios | ubuntu20.04_x64_bios_2.2G | test-net-02 | — | linux-x86_64 | 표준(3.8) |
| 9 | ubuntu20uefi | ubuntu20.04_x64_uefi_2.2G | test-net-03 (G3) | -04 | linux-x86_64 | 표준 |
| 10 | ubuntu22bios | ubuntu22.04_x64_bios_2.2G | test-net-03 | — | linux-x86_64 | 표준 |
| 11 | ubuntu22uefi | ubuntu22.04_x64_uefi_2.2G | test-net-03 | — | linux-x86_64 | 표준 |
| 12 | ubuntu24bios | ubuntu24.04_x64_bios_3.5G | test-net-03 | — | linux-x86_64 | 표준 |
| 13 | ubuntu24uefi | ubuntu24.04_x64_uefi_3.5G | test-net-04 (G4) | -05 | linux-x86_64 | 표준 |
| 14 | rocky8bios | rocky8_x64_bios_10G | test-net-04 | — | linux-x86_64 | 수동(3.6) |
| 15 | rocky8uefi | rocky8_x64_uefi_10G | test-net-04 | — | linux-x86_64 | 수동(3.6) |
| 16 | rocky9bios | rocky9_x64_bios_10G | test-net-04 | — | linux-x86_64 | 표준(3.9) |
| 17 | rocky9uefi | rocky9_x64_uefi_10G | test-net-05 (G5) | -06 | linux-x86_64 | 표준 |
| 18 | alma8 | alma8_x64_bios_10G | test-net-05 | — | linux-x86_64 | 수동(3.6) |
| 19 | alma9bios | alma9_x64_bios_10G | test-net-05 | — | linux-x86_64 | 표준(3.9) |
| 20 | alma9uefi | alma9_x64_uefi_10G | test-net-05 | — | linux-x86_64 | 표준 |
| 21 | centos7 | centos7_x64_bios_8G | test-net-06 (G6) | -07 | linux-x86_64 | 수동(2.7) |
| 22 | centos8 | centos8_x64_bios_10G | test-net-06 | — | linux-x86_64 | 수동(3.6) |
| 23 | centos8stream | centos8stream_x64_bios_10G | test-net-06 | — | linux-x86_64 | 수동(3.6) |
| 24 | centos9bios | centos9stream_x64_bios_10G | test-net-06 | — | linux-x86_64 | 표준(3.9) |
| 25 | centos9uefi | centos9stream_x64_uefi_10G | test-net-07 (G7) | -08 | linux-x86_64 | 표준 |
| 26 | oracle7 | oracle7_x64_bios_37G | test-net-07 | — | linux-x86_64 | 수동(2.7) |
| 27 | oracle8bios | oracle8_x64_bios_37G | test-net-07 | — | linux-x86_64 | 수동(3.6) |
| 28 | oracle9bios | oracle9_x64_bios_37G | test-net-07 | — | linux-x86_64 | 표준(3.9) |
| 29 | oracle9uefi | oracle9_x64_uefi_37G | test-net-08 (G8) | test-net(wrap) | linux-x86_64 | 표준 |
| 30 | amazon2 | amazon2_x64_bios_25G | test-net-08 | — | linux-x86_64 | 수동(2.7) |
| 31 | amazon2023 | amazon2023_x64_bios_25G | test-net-08 | — | linux-x86_64 | 표준(3.9) |

> **Windows 8대** — NT 버전별 바이너리 분기(서브넷은 primary=agent-subnet, secondary=agent_extra 기본):

| OS 키 | 이미지 | 주입 바이너리 | 비고 |
|---|---|---|---|
| windows2003 | win2003_x86_bios_40G | — (미지원) | x86 32bit — 전 바이너리 x86_64 전용. 부팅만 |
| windows2008 | win2008_x64_bios_40G | — (불확실) | NT6.0 — win7(NT6.1↑) 하한 미달. 부팅만 |
| windows2012 | win2012_x64_uefi_20G | assessment-agent-win7.exe | NT6.2 |
| windows2012r2 | win2012R2_x64_bios_20G_v1 | assessment-agent-win7.exe | NT6.3 |
| windows2016 | win2016_x64_uefi_20G | assessment-agent.exe | NT10 |
| windows2019 | win2019_x64_uefi_30G | assessment-agent.exe | NT10 |
| windows2022 | win2022_x64_uefi_40G | assessment-agent.exe | NT10 |
| windows2025 | win2025_x64_uefi_40G | assessment-agent.exe | NT10 |

> 바이너리 천장·근거: `agent-binary-image-coverage.md` "바이너리 선택 규칙". Windows ZDM install은 worker.c args 미전달 이슈 있음(§4 동 문서).

## 3. 프로비저닝 (Terraform — `agent/terraform/`)

- [ ] 내부 네트워크/서브넷: ADR-0013 — agent 테스트 전용 internal-only는 `agent/terraform/network/`에서 생성 허용. primary `agent-subnet`·라우터·keypair는 Horizon 수동
- [ ] keypair: **`new-bastion-key`** (engine-key.pem 매칭) — 확정
- [ ] SG: `agent-sg`(engine MQ·bastion SSH·subnet 내부 허용)
- [ ] flavor: OS 디스크 크기에 맞춰 선택(큰 이미지=oracle/suse15/amazon은 ≥디스크 flavor)
- [ ] `terraform apply` 후 인스턴스 IP·status 확인

### 3-1. 서브넷 토폴로지 (2026-06-17 요구)

> **모든 agent에 동일 서브넷을 적용하지 않는다.** ~4대씩 묶어 서브넷에 배정하고, **각 서브넷마다 1대는 서로 다른 2개 서브넷에 연결(dual-homed)**.

- **primary NIC**: 전 agent `agent-subnet`(1.1.1.64/26) 고정 — engine MQ·bastion 연결용(필수).
- **test 서브넷 그룹(secondary NIC)**: Linux 31대를 **4대씩 그룹화** → 8개 서브넷 그룹(4×7 + 3).
- **dual-homed**: 각 그룹 첫 대는 **다음 서브넷에도** secondary NIC 추가(wrap-around) → 각 서브넷이 인접 그룹의 dual 1대를 수용.

#### 결정: A — test 서브넷 6개 신규 생성 (확정 2026-06-17)
- 기존 2개 + **신규 6개 = 8개**. 신규는 `agent/terraform/network/`에서 internal-only 생성(ADR-0013).

| # | 서브넷(network) | CIDR | 비고 |
|---|---|---|---|
| 1 | subnet-test-net | 2.2.2.0/25 | 기존 |
| 2 | subnet-test-net-02 | 3.3.3.0/25 | 기존 |
| 3 | subnet-test-net-03 | 172.20.3.0/24 | 신규 |
| 4 | subnet-test-net-04 | 172.20.4.0/24 | 신규 |
| 5 | subnet-test-net-05 | 172.20.5.0/24 | 신규 |
| 6 | subnet-test-net-06 | 172.20.6.0/24 | 신규 |
| 7 | subnet-test-net-07 | 172.20.7.0/24 | 신규 |
| 8 | subnet-test-net-08 | 172.20.8.0/24 | 신규 |

#### 그룹 매핑 (31대 → 8 서브넷, 각 그룹 첫 대 dual)

| 그룹 | 서브넷 | agent(4대) | dual(→다음 서브넷) |
|---|---|---|---|
| G1 | test-net | debian10·debian11·debian12bios·debian12uefi | debian10 → -02 |
| G2 | test-net-02 | debian13bios·debian13uefi·ubuntu18·ubuntu20bios | debian13bios → -03 |
| G3 | test-net-03 | ubuntu20uefi·ubuntu22bios·ubuntu22uefi·ubuntu24bios | ubuntu20uefi → -04 |
| G4 | test-net-04 | ubuntu24uefi·rocky8bios·rocky8uefi·rocky9bios | ubuntu24uefi → -05 |
| G5 | test-net-05 | rocky9uefi·alma8·alma9bios·alma9uefi | rocky9uefi → -06 |
| G6 | test-net-06 | centos7·centos8·centos8stream·centos9bios | centos7 → -07 |
| G7 | test-net-07 | centos9uefi·oracle7·oracle8bios·oracle9bios | centos9uefi → -08 |
| G8 | test-net-08 | oracle9uefi·amazon2·amazon2023 (3대) | oracle9uefi → test-net (wrap) |

- 결과: 각 서브넷에 secondary NIC 4~5개(그룹 4 + 인접 dual 1), 각 서브넷에 dual-homed 1대씩.
- **terraform 모델 변경**: `agent_os_map` 각 엔트리에 `test_subnet`(+ optional `test_subnet_dual`) 필드 추가 → `instances.tf`가 VM별 secondary 포트를 그 서브넷에 생성. 기존 `agent_extra_networks`(전 agent 동일 부착) 대체.

## 4. 접근 전제 (cloud-init 유무에 따른 분기)

> 표준 파이프라인은 cloud-init이 keypair를 주입한다는 전제. 부재 OS는 우회 필요.
> **이번 구성은 cloud-init 정상 OS만 대상 → rescue 우회 불필요(표준 SSH 접근만).** 아래 부재 OS 분기는 추후 redhat/suse/tencent 포함 시 참고.

- **cloud-init 정상 OS**: Terraform `key_pair` 주입 → 기본 유저(ubuntu/debian/rocky/almalinux/cloud-user)로 SSH 표준 접근
- **cloud-init 부재 OS(redhat·suse·tencent)**: rescue 모드로 root 키 수동주입 필요
  - RHEL계열(redhat·tencent): rocky9 rescue + LVM 마운트 + SELinux permissive
  - SLES(suse): **debian13 rescue**(btrfs 지원) + `/@/root` 서브볼륨 직접 마운트
  - redhat7: 추가로 `ifcfg-eth0 ONBOOT=yes` 수정(NIC 미기동)
  - > 운영 배포 시엔 **골든 이미지에 cloud-init/키/ONBOOT 선반영**이 정공법. 위 rescue는 테스트 우회책.
- [ ] `~/.ssh/config` ProxyJump(bastion) 또는 동일 대역 직접 접근 경로 확인
- [ ] VM 재생성 시 known_hosts 충돌 → `ssh-keygen -R`

## 5. 배포 (Ansible — `agent/ansible/`)

- [ ] inventory 생성: `./scripts/gen-inventory.sh` (또는 테스트용 별도 inventory)
- [ ] vault 복호화: `~/.vault-pass`(0400)
- [ ] 배포: `ansible-playbook site.yml -i inventory.yml --vault-password-file ~/.vault-pass`
  - `deploy.yml`(common·agent_binary·agent_env·agent_service) → `services.yml` → `noise.yml` → `health-check.yml`
- [ ] **python<3.7 OS**(el7/el8·suse·ubuntu18): ansible-core 모듈 불가 → 정적 바이너리 수동 배포(rh9 산출물 복제 패턴)
- [ ] 바이너리: `agent_version`(현재 `1.2.0`), `agent_binary_filename`(`assessment-agent-linux-x86_64`) — 폐쇄망이라 bastion이 받아 `files/`에 사전 복사
- [ ] Windows: GitHub Releases→bastion 수동 다운로드→`win_copy` 주입(ADR-0007)

## 6. 주입 환경변수 / MQ 계약 (`group_vars/all/vars.yml` 기준)

- MQ: `engine_mq_host`(inventory 자동) · `engine_mq_port=5672` · `rabbitmq_tls_enabled=false`(engine plain 포트)
- 자격: `vault_mq_user`/`vault_mq_password`(=assessment)
- exchange/routing: `mq_exchange=assessment` · inventory/metrics/error 키 · task 군(`assessment.tasks`·`agent.tasks`·`task.result`)
- **worker download allowlist**: `worker_download_allowed_hosts`(ZDM host CSV — Linux `192.168.3.92`, Windows `192.168.3.94`). 비면 모든 download reject(ADR-0016, deploy 시점 고정)
- 루프/drain: `agent_interval_sec=60` · `agent_inventory_refresh_sec=300` · drain 예산(grace/term/publish)
- 서비스 설치: `agent_services` — **이번 구성: 전체 설치**(`[service_db, service_cache, service_mq, service_web, service_app, service_container, service_monitor]`). 전 OS군 동일 적용.

## 7. 검증 기준 (합격)

| 항목 | 합격 기준 | 확인 방법 |
|---|---|---|
| 바이너리 기동 | `assessment-agent` systemd active, `published inventory` 로그 | `journalctl -u assessment-agent` |
| MQ 발행 | engine `server_inventory`에 해당 인스턴스 신규 인식(machine_id·ip·last_seen) | engine postgres 조회 |
| ZDM install | `POST /api/tasks/install`(zdm_ip=192.168.3.92, zdm_user=메일형식) → task status `success` | `GET /api/tasks/{id}` |
| (RHEL계열) SELinux | install.sh 차단 없도록 permissive(ADR-0012) | `getenforce` |

## 8. 노이즈/부하 구성 (선택)

- `noise.yml`·`noise_*` role — 부하/장애 시뮬레이션. **이번 구성: 적용(켬)**. 강도/항목(재시작·offline·부하)은 role 기본값 사용 — 조정 필요 시 별도 지정.

## 9. 결정 사항 (2026-06-17 확정)

- [x] 구성 범위: **Linux ~30대(버전·firmware 다양, cloud-init 정상 OS) + Windows 8버전 1대씩** — §0·§2
- [x] keypair: **new-bastion-key** — §3
- [x] `agent_services`: **전체 설치**(7개 service_*) — §6
- [x] noise: **적용(켬)** — §8
- [x] cloud-init 부재 OS(redhat·suse·tencent): **이번 구성 제외**(추후 별도) — §4
- [x] **서브넷 토폴로지**: **A 선택** — test 서브넷 6개 신규 생성(총 8개), 4대/서브넷, 각 서브넷 dual-homed 1대 — §3-1
- [x] **per-VM 서브넷 매핑 모델**: `agent_os_map`에 `test_subnet`/`test_subnet_dual` 필드 추가 방식 — §3-1

> 남은 조정 여지: noise 강도 등 세부는 실행 시 미세조정.

## 10. 구현 진행 상태 (2026-06-17 시점)

### 완료 (코드 반영, apply 전)
- [x] 본 요구사항 문서(§0~9) 작성·갱신
- [x] `agent/terraform/network/terraform.tfvars`: test 서브넷 6개(`subnet-test-net-03`~`08`, 172.20.3~8.0/24) 추가 — `terraform plan` = **12 to add**(6 net + 6 subnet), apply 대기
- [x] `agent/terraform/terraform.tfvars`:
  - `windows_os_map` → 8버전(2003·2008·2012·2012R2·2016·2019·2022·2025) 각 1대
  - `agent_os_map` → 31엔트리(debian6·ubuntu7·rocky4·alma3·centos5·oracle4·amazon2, bios/uefi 다양)
  - `flavor_agent` → `1c-2m-40r`(oracle37·amazon25 수용)
  - `terraform validate` ✅

### 미착수 (다음 단계)
- [ ] **network 스택 apply** → 서브넷 6개 실제 생성
- [ ] **agent terraform 모델 리팩터**: `variables.tf` `agent_os_map`에 `test_subnet`/`test_subnet_dual` 필드 추가 + `instances.tf` per-VM secondary 포트 생성(기존 `agent_extra_networks` all-to-all 대체) + `data.tf` 8개 test 서브넷 data source
- [ ] **agent_os_map에 그룹 매핑 값 채우기**(§3-1 표대로 31대 → 8 서브넷)
- [ ] **agent 스택 apply** → Linux 31 + Windows 8 = 39대 부팅
- [ ] gen-inventory → `site.yml` 배포(agent_services 전체 + noise) → §7 검증(MQ·ZDM)

### 참고
- apply는 아직 하나도 안 함(서브넷·VM 미생성). engine v0.7.0은 별도 가동 중.
- terraform.tfvars는 gitignore — 본 문서가 구성 의도의 단일 기록.
