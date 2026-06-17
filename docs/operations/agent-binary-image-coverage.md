# Agent 바이너리 ↔ Glance 이미지 커버리지 매트릭스

> 작성일: 2026-06-16 · 대상 릴리즈: assessment-agent **v1.2.0**
> 소스: `openstack image list` (glance) + assessment-agent `.github/workflows/release.yml` 빌드 매트릭스 + `docs/centos6-bringup.md` + agent/ansible roles(common·agent_env·agent_service)

## 목적

v1.2.0가 제공하는 5종 바이너리가 현재 glance에 등록된 이미지를 어디까지 커버하는지,
그리고 **동일 OS의 BIOS/UEFI 변종 각각**에 대해 MQ 발행·ZDM install 발행 검증 진행상황을 추적한다.

## 바이너리 선택 규칙 (요약)

| 바이너리 | 빌드 환경 | 적용 천장 | 타깃 |
|---|---|---|---|
| `assessment-agent-linux-x86_64` | manylinux2014 | glibc **2.17+** | RHEL/CentOS 7+, Ubuntu 18.04+, Debian 10+, Amazon Linux 2/2023, SLES 12/15, Tencent 4 등 |
| `assessment-agent-linux-x86_64-glibc2.12` | manylinux2010 | glibc **2.12** | CentOS/RHEL/Oracle **6** (pre-systemd, kernel 2.6.32) |
| `assessment-agent.exe` | MinGW modern | **NT10** | Windows Server 2016~2025 |
| `assessment-agent-win7.exe` | MinGW win7 | **NT6.1–6.3** | Server 2008R2 ~ 2012R2 |
| `assessment-agent-legacy.exe` | MinGW legacy (experimental) | **NT5.2** | Server 2003 / XP **x64** |

- **firmware(BIOS/UEFI)는 바이너리 선택과 무관** — 선택은 OS의 glibc/NT버전 + 아키텍처(x86_64)로만 결정된다. BIOS/UEFI를 행으로 나눈 건 부팅·ZDM 동작이 펌웨어별로 달라질 수 있어 **각각 독립 검증**이 필요하기 때문.
- 전 바이너리 **x86_64 전용** — 32-bit(x86) 이미지는 매칭 불가.

검증 칸 범례: `⬜ 미검증` · `✅ 성공` · `❌ 실패` · `— 해당없음(바이너리 미제공)` · `🚧 agent args 누락`(엔진·패키지는 정상, agent worker.c가 install.args 미전달 — §4 참조)

**`표준배포 가능 여부` 컬럼** — `mq/zdm 성공`은 **바이너리가 그 OS에서 동작함**(MQ+ZDM)만 의미하며, **표준 파이프라인으로 배포 가능한지는 별개**다. 이 컬럼이 그 구분을 표기한다:
- `✅ 표준` — cloud-init 정상 + python ≥3.7 → Terraform/cloud-init 키주입 후 표준 Ansible `deploy.yml`로 배포 완결
- `🔶 수동(pyX)` — cloud-init 정상이라 **접근은 표준**이나, target python<3.7로 ansible-core 모듈 실행 불가 → 정적 바이너리 **수동 배포** 필요(접근은 표준, 실행만 우회)
- `⛔ rescue` — **cloud-init 부재**로 keypair 자동 주입 실패 → rescue 모드로 **out-of-band 키 수동주입** 필요(표준 배포 불가). 이 행들의 `✅ 성공`은 **rescue 키주입을 전제로 한 바이너리 동작 입증**이며, 현 이미지로의 표준 배포 성공이 아니다.
- `⛔ permissive` — 부팅은 되나 SELinux 라벨손상으로 sshd 미기동 → rescue로 permissive 선적용 필요
- `⛔ SysV` — systemd 부재(centos6) / `— 부팅실패` — ACTIVE 미도달 / `별도(win)` — Windows는 cloudbase-init·`win_copy` 별도 경로
> 분류 근거: `⛔`(cloud-init 부재)는 redhat·suse·tencent·rocky8_lvm에서 **실측**. `✅`/`🔶`의 cloud-init 정상 여부는 2026-06-17 검증분(ubuntu·centos9stream) 외에는 **OS 특성(통상 cloud 이미지 탑재) + python 버전 기반 분류**이며, python<3.7 판정은 사실에 근거.

## 배포 권한 모델 (소스: agent/ansible roles)

매트릭스의 **`배포 유저 / 서비스 실행 권한`** 컬럼 값의 근거. OS 클래스별로 동일하다.

### Linux (systemd) — 표의 `agent유저(sudo無) / root`

| 항목 | 내용 |
|---|---|
| 생성 유저 | `assessment-agent` (**system** user/group) — shell `/usr/sbin/nologin`, home `/var/lib/agent-worker`, `create_home: false` (common role) |
| 유저 권한 | **비특권**. sudo **없음** — 구 `/etc/sudoers.d/assessment-agent` NOPASSWD 그랜트는 **제거**(바이너리가 sudo 호출 안 함). 소유: `/var/lib/agent-worker`·`results`·`done`(0750). env: `/etc/assessment-agent/agent.env`(root:assessment-agent **0640**, 그룹 읽기) |
| 서비스 실행 권한 | systemd 유닛 **`User=root` `Group=root`** → **root로 실행**. 이유: worker가 ZDM `install.sh`를 sudo/setuid 없이 직접 `execve` → root 필요. hardening 최소(`RestrictRealtime`만; `NoNewPrivileges`/`PrivateTmp` 미적용 — ZDM이 host 전반 변경 요구) |
| 비고 | 생성된 agent 유저는 **디렉토리 소유/그룹 권한용**이고, 실제 프로세스는 root로 돈다 |

### Linux (systemd 부재 = centos6, SysV) — 표의 `agent유저 / root · SysV필요`

| 항목 | 내용 |
|---|---|
| 생성 유저 | 동일 — `assessment-agent` 생성(common role은 systemd와 무관하게 동작) |
| 유저 권한 | 동일 (sudo 없음) |
| 서비스 실행 권한 | **root 필요**(ZDM install.sh)는 동일하나, `agent_service` role이 **systemd 유닛만 렌더** → centos6에서 **이 단계 실패**. 별도 **SysV init 스크립트(`/etc/init.d/`)** 또는 수동 기동 필요. (`docs/centos6-bringup.md`) |

### Windows — 표의 `유저無 / LocalSystem`

| 항목 | 내용 |
|---|---|
| 생성 유저 | **없음** — `common` role(유저/sudoers 생성)은 Linux 전용. Windows deploy는 binary·env·service만 |
| 유저 권한 | N/A (전용 계정 미생성) |
| 서비스 실행 권한 | `win_service` username 미지정 → 서비스 **LocalSystem**으로 실행. env는 머신 레벨 환경변수 주입 |

---

## 1. 커버 가능 이미지

### 1-1. Linux — modern (`assessment-agent-linux-x86_64`)

| 이미지 이름(bios/uefi각각) | 매칭되는 바이너리 | 배포 유저 / 서비스 실행 권한 | mq 발행 성공여부 | zdm install 발행 성공 여부 | 표준배포 가능 여부 |
|---|---|---|---|---|---|
| alma8_x64_bios_10G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py3.6) |
| alma8_x64_uefi_10G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py3.6) |
| alma9_x64_bios_10G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| alma9_x64_uefi_10G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| amazon2_x64_bios_25G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py2.7) |
| amazon2023_x64_bios_25G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| centos7_x64_bios_8G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py2.7) |
| centos7_x64_bios_8G_lvm_smb_nfs | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py2.7) |
| centos7_x64_uefi_20G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py2.7) |
| centos7_x64_uefi_20G_lvm_smb_nfs | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py2.7) |
| centos7_x64_uefi_20G_v1 | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py2.7) |
| centos8_x64_bios_10G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py3.6) |
| centos8stream_x64_bios_10G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py3.6) |
| centos8stream_x64_bios_10G_lvm_smb_nfs | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py3.6) |
| centos8stream_x64_uefi_10G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py3.6) |
| centos8stream_x64_uefi_10G_lvm_smb_nfs | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ❌ 실패(ssh-unreachable) | — | — 부팅실패 |
| centos8stream_x64_uefi_20G_v1 | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py3.6) |
| centos9stream_x64_bios_10G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| centos9stream_x64_uefi_10G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| debian10_x64_bios_2G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| debian11_x64_bios_3G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| debian12_x64_bios_3G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| debian12_x64_uefi_3G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| debian13_x64_bios_3G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| debian13_x64_uefi_3G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| oracle7_x64_bios_37G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py2.7) |
| oracle7_x64_uefi_20G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ❌ 실패(boot-ERROR) | — | — 부팅실패 |
| oracle8_x64_bios_37G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py3.6) |
| oracle8_x64_uefi_37G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py3.6) |
| oracle9_x64_bios_37G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| oracle9_x64_uefi_37G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| redhat7_x64_bios_20G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ⛔ rescue |
| redhat7_x64_uefi_20G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ⛔ rescue |
| redhat8_x64_bios_10G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ⛔ rescue |
| redhat8_x64_uefi_10G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ⛔ rescue |
| redhat9_x64_bios_10G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ⛔ rescue |
| redhat9_x64_uefi_10G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ⛔ rescue |
| rocky8_x64_bios_10G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py3.6) |
| rocky8_x64_bios_10G_lvm_smb_nfs | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공(SELinux permissive 선적용 필요) | ✅ 성공 | ⛔ permissive |
| rocky8_x64_bios_10G_lvm_smb_nfs_2 | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py3.6) |
| rocky8_x64_uefi_10G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py3.6) |
| rocky8_x64_uefi_10G_v1 | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py3.6) |
| rocky9_x64_bios_10G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| rocky9_x64_uefi_10G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| suse12_x64_bios_20G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ⛔ rescue |
| suse12_x64_uefi_20G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ❌ 실패(build-ERROR·3회) | — | — 부팅실패 |
| suse15_x64_bios_40G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ⛔ rescue |
| suse15_x64_uefi_40G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ⛔ rescue |
| tencent4.0_x64_bios_20G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ⛔ rescue |
| tencent4.2_x64_bios_20G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ⛔ rescue |
| ubuntu18.04_x64_bios_2.2G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py3.6) |
| ubuntu18.04_x64_uefi_2.2G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | 🔶 수동(py3.6) |
| ubuntu20.04_x64_bios_2.2G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| ubuntu20.04_x64_uefi_2.2G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| ubuntu22.04_x64_bios_2.2G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| ubuntu22.04_x64_uefi_2.2G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| ubuntu24.04_x64_bios_3.5G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |
| ubuntu24.04_x64_uefi_3.5G | assessment-agent-linux-x86_64 | agent유저(sudo無) / root | ✅ 성공 | ✅ 성공 | ✅ 표준 |

> **ubuntu 계열 검증 노트(2026-06-17)** — ubuntu18.04/20.04/22.04/24.04 bios·uefi 8종 모두 MQ·ZDM **✅ 성공**. cloud-init 정상이라 keypair 자동 주입·`ubuntu` 유저 SSH로 redhat 같은 우회 불필요. 단 **ubuntu18.04는 python 3.6.9**(ansible-core 모듈 요건 3.7+ 미달, `SyntaxError: future feature annotations`)라 표준 `deploy.yml` 대신 **정적 바이너리 수동 배포**(ubuntu 유저+sudo)로 검증 — 바이너리는 glibc 2.27 ≥ 2.17이라 정상 동작. 20.04(3.8)·22.04(3.10)·24.04(3.12)는 표준 Ansible deploy.

> **redhat 계열 검증 노트(2026-06-17)** — redhat7/8/9 bios·uefi 6종 모두 MQ·ZDM **✅ 성공**. 단, 과거 `ssh-unreachable`(redhat8/9, redhat7_uefi)·`미검증`(redhat7_bios)의 **근본 원인은 OS 이미지 결함**으로, 표준 배포 파이프라인으로는 접근 불가했다:
> - **cloud-init 미설치(전 redhat 이미지)**: glance redhat 이미지에 cloud-init이 없어 OpenStack keypair·user_data가 **주입되지 않음** → SSH 키 인증 전부 실패. (rocky/alma/centos는 cloud-init 정상이라 영향 없음 — redhat 이미지 고유.) rescue 모드(rocky9)로 부팅해 LVM 루트 마운트 후 **root authorized_keys 수동 주입 + `/etc/selinux/config` permissive(ADR-0012)** 로 접근 확보.
> - **redhat7 추가 — `ifcfg-eth0 ONBOOT=no`**: cloud-init 부재로 NIC가 부팅 시 안 올라와 L3 자체 unreachable. rescue에서 `ONBOOT=yes`로 수정해야 네트워크 기동.
> - **배포 경로**: redhat9는 `/usr/bin/python3`(3.9) 존재 → 표준 Ansible `deploy.yml` 사용. redhat8(platform-python 3.6, ansible-core 모듈 요건 3.7+ 미달)·redhat7(python2.7만)은 **미등록(subscription無)으로 dnf repo가 비어 python 설치 불가** → 정적 바이너리를 rh9 산출물에서 복제하는 **수동 배포**로 대체. agent 바이너리는 정적이라 런타임 의존성 없음(RHEL7.9 glibc 2.17 = 천장과 동일, 정상 동작).
> - 결론: **바이너리 커버리지 자체는 redhat 6종 전부 정상**(MQ+ZDM 발행·완료 확인). 실패로 보였던 항목은 전부 **이미지 프로비저닝 결함**(cloud-init 부재·ONBOOT·subscription)이며 agent/엔진 결함 아님. 운영 배포하려면 redhat 이미지에 cloud-init 탑재(또는 골든 이미지에 키/ONBOOT/SELinux 선반영)가 선행돼야 한다.

> **suse·tencent·centos9stream 검증 노트(2026-06-17)** — centos9stream bios·uefi(cloud-user, 표준 Ansible)·suse12_bios·suse15 bios·uefi·tencent4.0/4.2(rescue 후 root) 모두 MQ·ZDM **✅ 성공**.
> - **SUSE(SLES12/15)**: cloud-init 부재 + **btrfs 루트에서 `/root`가 별도 서브볼륨(`subvol=/@/root`)** — 기본 마운트의 `/root`에 키를 넣으면 런타임에 서브볼륨이 가려 무효. **`/@/root` 서브볼륨을 직접 마운트해 주입**해야 함. rocky9 rescue 커널은 btrfs 미지원이라 **debian13 rescue** 사용. SLES는 AppArmor라 SELinux 설정 불필요. python 구버전(SP3=3.4·SP1=3.6)이라 수동 배포. glibc(SP3 2.22·SP1 2.26) ≥ 2.17 정상.
> - **TencentOS 4.0/4.2**: RHEL9 기반 — cloud-init 부재(rocky9 rescue+키+permissive)지만 python 3.11 보유라 **표준 Ansible deploy**. MQ에 `os_id`는 tencent로 정상 보고.
> - **suse12_x64_uefi_20G**: 3회 연속 build-ERROR(ACTIVE 도달 실패) — UEFI 이미지/하이퍼바이저 부팅 결함. suse12_bios는 정상이라 SLES12 바이너리 커버리지는 입증됨.

### 1-2. Linux — legacy (`assessment-agent-linux-x86_64-glibc2.12`)

| 이미지 이름(bios/uefi각각) | 매칭되는 바이너리 | 배포 유저 / 서비스 실행 권한 | mq 발행 성공여부 | zdm install 발행 성공 여부 | 표준배포 가능 여부 |
|---|---|---|---|---|---|
| centos6_x64_bios_9G | assessment-agent-linux-x86_64-glibc2.12 | agent유저 / root · **SysV필요(systemd無)** | ❌ 실패(deploy-fail: root ForceCommand 차단) | — | ⛔ SysV(systemd부재) |
| centos6_x64_uefi_10G | assessment-agent-linux-x86_64-glibc2.12 | agent유저 / root · **SysV필요(systemd無)** | ❌ 실패(boot-ERROR) | — | — 부팅실패 |

> **rocky8_lvm_smb_nfs 노트(2026-06-17)** — 과거 `boot-BUILD` 분류는 부정확. 재확인 결과 부팅은 ACTIVE까지 도달하나 **루트 fs가 `unlabeled_t`로 라벨 손상 + SELinux enforcing** 조합으로 sshd가 ld.so.cache·/etc/group read 거부당해 기동 실패(restart 52회) → L3 도달은 되나 22 포트 미개방(connection refused). rescue로 `/etc/selinux/config` permissive 선적용 시 sshd 정상 기동·agent MQ+ZDM **✅ 성공**. 이미지 결함(라벨링)이며 `_2`/비-lvm 변종은 정상.

> CentOS 6은 pre-systemd(SysV init) + `/etc/os-release` 부재 — agent가 런타임에서 처리(`docs/centos6-bringup.md`). 설치 시 glibc2.12 바이너리를 `assessment-agent-linux-x86_64` 이름으로 배치하거나 `DIST_BIN`으로 지정해야 install.sh가 인식. `agent_service` role은 systemd 전용이라 centos6에선 SysV init 스크립트(또는 수동 기동) 필요.

### 1-3. Windows — modern (`assessment-agent.exe`)

| 이미지 이름(bios/uefi각각) | 매칭되는 바이너리 | 배포 유저 / 서비스 실행 권한 | mq 발행 성공여부 | zdm install 발행 성공 여부 | 표준배포 가능 여부 |
|---|---|---|---|---|---|
| win2016_x64_uefi_20G | assessment-agent.exe | 유저無 / LocalSystem | ⬜ 미검증 | ⬜ 미검증(🚧 agent args 누락) | 별도(win) |
| win2019_x64_uefi_30G | assessment-agent.exe | 유저無 / LocalSystem | ⬜ 미검증 | ⬜ 미검증(🚧 agent args 누락) | 별도(win) |
| win2019_x64_uefi_30G_custom | assessment-agent.exe | 유저無 / LocalSystem | ⬜ 미검증 | ⬜ 미검증(🚧 agent args 누락) | 별도(win) |
| win2019_x64_uefi_30G_edu | assessment-agent.exe | 유저無 / LocalSystem | ⬜ 미검증 | ⬜ 미검증(🚧 agent args 누락) | 별도(win) |
| win2022_x64_uefi_40G | assessment-agent.exe | 유저無 / LocalSystem | ⬜ 미검증 | ❌ 실패(🚧 agent args 누락) | 별도(win) |
| win2025_x64_uefi_40G | assessment-agent.exe | 유저無 / LocalSystem | ⬜ 미검증 | ⬜ 미검증(🚧 agent args 누락) | 별도(win) |

> **정정(2026-06-16)**: Windows ZDM install은 **구조적 불가가 아니다**. 엔진은 Windows를 `direct_exec` 타입으로 정식 지원하고(`config.py:105` `zdm_package_path_windows` + `task_service.py`의 `_resolve_install_dispatch`/`_publish_install`), ZDM 서버에 `ZConverter_CloudSource_Setup_Windows.exe`(528MB·32-bit PE32 NSIS 인스톨러)도 실재해 HTTP 200으로 다운로드된다(직접 확인).
> 실제 차단 원인은 **agent 결함 하나**: Windows worker(`assessment-agent/windows-agent/src/worker.c`)가 발행 payload의 `install.args=["-s",zdm_host,"-u",zdm_user]`를 **파싱하지 않고**(install 블록에서 `type`·`timeout_sec`만 읽음) `exec_install(..., NULL, ...)`로 argv_extra=NULL을 넘긴다. 그 결과 설치 프로그램이 ZDM 서버 IP·계정 인자 없이 실행돼 실패. `exec.c`의 `build_cmdline`은 argv_extra를 quote 처리해 받을 준비가 이미 됨 — worker만 미전달이라 Linux worker는 정상 동작한다. 상세: 메모리 `windows-agent-ignores-install-args`.
> `🚧 agent args 누락`은 agent worker.c 수정 후 재검증 대상(미검증 행은 인스턴스 미기동, win2022는 실제 발행→실패 확인). MQ(inventory 발행)는 별개로 동작.

### 1-4. Windows — win7 (`assessment-agent-win7.exe`)

| 이미지 이름(bios/uefi각각) | 매칭되는 바이너리 | 배포 유저 / 서비스 실행 권한 | mq 발행 성공여부 | zdm install 발행 성공 여부 | 표준배포 가능 여부 |
|---|---|---|---|---|---|
| win2012_x64_uefi_20G | assessment-agent-win7.exe | 유저無 / LocalSystem | ⬜ 미검증 | ⬜ 미검증(🚧 agent args 누락) | 별도(win) |
| win2012R2_x64_bios_20G_v1 | assessment-agent-win7.exe | 유저無 / LocalSystem | ⬜ 미검증 | ❌ 실패(🚧 agent args 누락) | 별도(win) |
| win2012R2_x64_bios_20G_v1.1 | assessment-agent-win7.exe | 유저無 / LocalSystem | ⬜ 미검증 | ⬜ 미검증(🚧 agent args 누락) | 별도(win) |

> 위 1-3절 정정이 win7 바이너리에도 동일 적용 — install 미동작은 NT 버전·바이너리와 무관하게 worker.c args 미전달 때문. win2012R2_v1은 이번에 인스턴스 기동 후 발행→실패 확인, 나머지는 미기동.

---

## 2. 커버 불가 이미지

| 이미지 이름(bios/uefi각각) | 매칭되는 바이너리 | 배포 유저 / 서비스 실행 권한 | mq 발행 성공여부 | zdm install 발행 성공 여부 | 표준배포 가능 여부 |
|---|---|---|---|---|---|
| suse11_x64_bios_20G | ❌ 없음 | — (미배포) | — | — | — |
| win2003_x86_bios_40G | ❌ 없음 | — (미배포) | — | — | — |
| win2008_x64_bios_40G | ❌ 없음(불확실) | — (미배포) | — | — | — |

### 불가 사유

- **suse11_x64_bios_20G** — SLES 11은 glibc ~2.11로 legacy 천장(2.12)보다도 낮음. modern(2.17)·legacy(2.12) 어느 쪽도 링크 불가. 별도 빌드 프로파일이 없으면 미지원.
- **win2003_x86_bios_40G** — **32-bit(x86)** 이미지. 모든 바이너리가 x86_64 전용이라 아키텍처 불일치. (legacy.exe도 "Server 2003 / XP **x64**" 대상)
- **win2008_x64_bios_40G** — Server 2008 RTM = **NT6.0**. win7 프로파일 하한이 NT6.1이라 갭에 걸림. 만약 해당 이미지가 실제로 **2008 R2(NT6.1)** 라면 `assessment-agent-win7.exe`로 커버 가능 → 부팅 후 `ver`로 NT 버전 확인 필요.

### 펌웨어 변종 부재 (glance에 단일 firmware만 존재 — 참고)

bios/uefi 둘 다 검증하려면 아래는 누락된 펌웨어 이미지를 glance에 추가해야 함:

- **BIOS만 존재**: amazon2, amazon2023, centos8, debian10, debian11, tencent4.0, tencent4.2, win2003, win2008, win2012R2
- **UEFI만 존재**: win2012, win2016, win2019(×3), win2022, win2025

---

## 3. 요약

| 구분 | 이미지 수 |
|---|---|
| Linux modern 커버 | 58 |
| Linux legacy(glibc2.12) 커버 | 2 |
| Windows modern 커버 | 6 |
| Windows win7 커버 | 3 |
| **커버 불가** | **3** (suse11, win2003 32bit, win2008 NT6.0?) |

> 검증 결과(mq·zdm 칸)는 테스트 진행하며 이 파일에서 갱신.

### 검증 진행 현황 (Linux modern 58종 기준)

| 상태 | 수 | 비고 |
|---|---|---|
| ✅ 성공 | 55 | MQ+ZDM 모두 성공 (rocky8_lvm_smb_nfs 1종은 SELinux permissive 선적용 조건) |
| ❌ 실패 | 3 | oracle7_x64_uefi_20G(boot-ERROR) · centos8stream_x64_uefi_10G_lvm_smb_nfs(ssh-unreachable) · suse12_x64_uefi_20G(build-ERROR·3회) |
| ⬜ 미검증 | 0 | — (Linux modern 전수 검증 완료) |

> **2026-06-17 실행분**: Linux modern 58종 **전수 검증 완료** (✅ 55 / ❌ 3). 이번 실행으로 redhat 6·rocky8_lvm·ubuntu 8·centos9stream 2·suse12_bios·suse15 2·tencent 2 = **21종을 ✅로 전환**. 실패 3종은 전부 **이미지/부팅 결함**(oracle7_uefi·suse12_uefi build/boot-ERROR, centos8stream_uefi_lvm ssh-unreachable)이며 agent/엔진 무결.
> - **cloud-init 부재 OS(redhat·suse·tencent)**: keypair 자동 주입 실패 → rescue 모드로 root 키 수동 주입(SLES는 btrfs `/@/root` 서브볼륨 직접 마운트, debian13 rescue 사용; RHEL계열은 rocky9 rescue+SELinux permissive). 운영 배포엔 골든 이미지에 cloud-init/키 선반영 필요.
> - **배포 경로**: python 3.7+ 보유 OS(redhat9·ubuntu20.04+·tencent4·centos9s)는 표준 Ansible `deploy.yml`. python 구버전(redhat7 py2.7·redhat8/ubuntu18 py3.6·suse12 py3.4·suse15 py3.6)은 정적 바이너리 수동 배포 — 바이너리는 전 OS glibc ≥2.17이라 정상 동작.

---

## 4. agent 개발자 공유 — Windows ZDM install args 미전달

> 작성: 2026-06-16 (infra 팀) · 대상: assessment-agent 개발자 · 상태: **확인 요청**

### 한 줄 요약

Windows worker가 엔진이 보낸 `task.install`의 `install.args`(`-s <zdm_host>` `-u <zdm_user>`)를 **파싱·전달하지 않아**, ZDM 설치 프로그램이 서버 IP·계정 인자 **없이** 실행되어 install이 실패합니다. (Linux worker는 정상.)

### 확인된 사실 (infra 측에서 직접 검증)

| # | 항목 | 결과 |
|---|---|---|
| 1 | 엔진의 Windows 분기 | `direct_exec` 타입으로 정식 지원 — `config.py:105` `zdm_package_path_windows`, `task_service.py`의 `_resolve_install_dispatch`(os_family=windows → `direct_exec`, script=null) |
| 2 | 엔진 발행 payload | `install.args = ["-s", <zdm_host>, "-u", <zdm_user>]` 정상 포함 (`task_service.py` `_publish_install`) |
| 3 | ZDM 패키지 실재 | `http://<zdm>/download/ZConverter_CloudSource_Setup_Windows.exe` → HTTP 200, 528MB, 32-bit PE32 NSIS 인스톨러. 다운로드 정상 |
| 4 | **agent 결함** | `windows-agent/src/worker.c`가 `install` 블록에서 `type`·`timeout_sec`만 읽고 `args` 미파싱 → `install_thread_arg_t`에 args 필드 없음 → `exec_install(..., target_file, NULL, ...)`로 argv_extra=NULL 전달 |
| 5 | exec 레이어는 준비됨 | `exec.c`의 `build_cmdline`은 argv_extra를 quote 처리해 `"package.exe" -s <host> -u <user>`로 조립할 능력 보유 — worker가 안 넘겨줄 뿐 |

### 코드 위치 (assessment-agent 레포)

- `windows-agent/src/worker.c` — install 블록 파싱부(`type`/`timeout_sec`만 읽는 곳) 및 `exec_install(..., NULL, ...)` 호출부
- `windows-agent/src/exec.c` — `build_cmdline` / `exec_install` (argv_extra 수용 가능, 수정 불필요)
- 참고(정상 동작 레퍼런스): Linux `src/worker.c`의 install.args 파싱 → `exec_install_script(..., iargs, ...)` 경로

### 제안 수정 (3곳, worker.c)

1. `jinstall`에서 `args` 배열 파싱 (cJSON array → `const char **`)
2. `install_thread_arg_t`에 args 필드 추가 + 저장 (Linux worker 방식 복제)
3. `exec_install(...)` 호출의 `NULL` → 파싱한 argv 배열로 교체

### agent 개발자 확인 요청 사항

- [ ] 위 진단(args 미전달)이 맞는지 — worker.c 현재 동작 확인
- [ ] 수정 적용 일정/대상 릴리즈
- [ ] NSIS 인스톨러가 받는 인자 규약 확인: 엔진은 `-s`/`-u`(unix-style)로 발행 중인데, ZConverter Windows setup이 실제로 기대하는 플래그 형식(`-s`/`/S` 등)이 무엇인지 — 엔진 args 포맷과 일치해야 함
- [ ] 수정 후 win2022(`assessment-agent.exe`)·win2012R2(`assessment-agent-win7.exe`) 재검증 시 infra가 인스턴스 제공 가능

> 관련 배경: ZDM install root cause는 두 갈래 — (a) 본 args 미전달, (b) OS-aware 패키지 부재 이슈(과거 추적). 본 문서는 (a)만 다룸.
