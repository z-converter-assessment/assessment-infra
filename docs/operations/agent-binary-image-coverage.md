# Agent 바이너리 ↔ Glance 이미지 커버리지 매트릭스

> 작성일: 2026-06-16 · 대상 릴리즈: assessment-agent **v1.2.0**
> 소스: `openstack image list` (glance) + assessment-agent `.github/workflows/release.yml` 빌드 매트릭스 + `docs/centos6-bringup.md`

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

검증 칸 범례: `⬜ 미검증` · `✅ 성공` · `❌ 실패` · `— 해당없음(바이너리 미제공)`

---

## 1. 커버 가능 이미지

### 1-1. Linux — modern (`assessment-agent-linux-x86_64`)

| 이미지 이름(bios/uefi각각) | 매칭되는 바이너리 | mq 발행 성공여부 | zdm install 발행 성공 여부 |
|---|---|---|---|
| alma8_x64_bios_10G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| alma8_x64_uefi_10G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| alma9_x64_bios_10G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| alma9_x64_uefi_10G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| amazon2_x64_bios_25G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| amazon2023_x64_bios_25G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| centos7_x64_bios_8G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| centos7_x64_bios_8G_lvm_smb_nfs | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| centos7_x64_uefi_20G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| centos7_x64_uefi_20G_lvm_smb_nfs | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| centos7_x64_uefi_20G_v1 | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| centos8_x64_bios_10G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| centos8stream_x64_bios_10G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| centos8stream_x64_bios_10G_lvm_smb_nfs | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| centos8stream_x64_uefi_10G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| centos8stream_x64_uefi_10G_lvm_smb_nfs | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| centos8stream_x64_uefi_20G_v1 | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| centos9stream_x64_bios_10G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| centos9stream_x64_uefi_10G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| debian10_x64_bios_2G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| debian11_x64_bios_3G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| debian12_x64_bios_3G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| debian12_x64_uefi_3G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| debian13_x64_bios_3G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| debian13_x64_uefi_3G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| oracle7_x64_bios_37G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| oracle7_x64_uefi_20G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| oracle8_x64_bios_37G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| oracle8_x64_uefi_37G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| oracle9_x64_bios_37G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| oracle9_x64_uefi_37G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| redhat7_x64_bios_20G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| redhat7_x64_uefi_20G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| redhat8_x64_bios_10G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| redhat8_x64_uefi_10G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| redhat9_x64_bios_10G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| redhat9_x64_uefi_10G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| rocky8_x64_bios_10G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| rocky8_x64_bios_10G_lvm_smb_nfs | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| rocky8_x64_bios_10G_lvm_smb_nfs_2 | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| rocky8_x64_uefi_10G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| rocky8_x64_uefi_10G_v1 | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| rocky9_x64_bios_10G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| rocky9_x64_uefi_10G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| suse12_x64_bios_20G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| suse12_x64_uefi_20G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| suse15_x64_bios_40G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| suse15_x64_uefi_40G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| tencent4.0_x64_bios_20G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| tencent4.2_x64_bios_20G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| ubuntu18.04_x64_bios_2.2G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| ubuntu18.04_x64_uefi_2.2G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| ubuntu20.04_x64_bios_2.2G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| ubuntu20.04_x64_uefi_2.2G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| ubuntu22.04_x64_bios_2.2G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| ubuntu22.04_x64_uefi_2.2G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| ubuntu24.04_x64_bios_3.5G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |
| ubuntu24.04_x64_uefi_3.5G | assessment-agent-linux-x86_64 | ⬜ 미검증 | ⬜ 미검증 |

### 1-2. Linux — legacy (`assessment-agent-linux-x86_64-glibc2.12`)

| 이미지 이름(bios/uefi각각) | 매칭되는 바이너리 | mq 발행 성공여부 | zdm install 발행 성공 여부 |
|---|---|---|---|
| centos6_x64_bios_9G | assessment-agent-linux-x86_64-glibc2.12 | ⬜ 미검증 | ⬜ 미검증 |
| centos6_x64_uefi_10G | assessment-agent-linux-x86_64-glibc2.12 | ⬜ 미검증 | ⬜ 미검증 |

> CentOS 6은 pre-systemd(SysV init) + `/etc/os-release` 부재 — agent가 런타임에서 처리(`docs/centos6-bringup.md`). 설치 시 glibc2.12 바이너리를 `assessment-agent-linux-x86_64` 이름으로 배치하거나 `DIST_BIN`으로 지정해야 install.sh가 인식.

### 1-3. Windows — modern (`assessment-agent.exe`)

| 이미지 이름(bios/uefi각각) | 매칭되는 바이너리 | mq 발행 성공여부 | zdm install 발행 성공 여부 |
|---|---|---|---|
| win2016_x64_uefi_20G | assessment-agent.exe | ⬜ 미검증 | ⬜ 미검증 |
| win2019_x64_uefi_30G | assessment-agent.exe | ⬜ 미검증 | ⬜ 미검증 |
| win2019_x64_uefi_30G_custom | assessment-agent.exe | ⬜ 미검증 | ⬜ 미검증 |
| win2019_x64_uefi_30G_edu | assessment-agent.exe | ⬜ 미검증 | ⬜ 미검증 |
| win2022_x64_uefi_40G | assessment-agent.exe | ⬜ 미검증 | ⬜ 미검증 |
| win2025_x64_uefi_40G | assessment-agent.exe | ⬜ 미검증 | ⬜ 미검증 |

### 1-4. Windows — win7 (`assessment-agent-win7.exe`)

| 이미지 이름(bios/uefi각각) | 매칭되는 바이너리 | mq 발행 성공여부 | zdm install 발행 성공 여부 |
|---|---|---|---|
| win2012_x64_uefi_20G | assessment-agent-win7.exe | ⬜ 미검증 | ⬜ 미검증 |
| win2012R2_x64_bios_20G_v1 | assessment-agent-win7.exe | ⬜ 미검증 | ⬜ 미검증 |
| win2012R2_x64_bios_20G_v1.1 | assessment-agent-win7.exe | ⬜ 미검증 | ⬜ 미검증 |

---

## 2. 커버 불가 이미지

| 이미지 이름(bios/uefi각각) | 매칭되는 바이너리 | mq 발행 성공여부 | zdm install 발행 성공 여부 |
|---|---|---|---|
| suse11_x64_bios_20G | ❌ 없음 | — | — |
| win2003_x86_bios_40G | ❌ 없음 | — | — |
| win2008_x64_bios_40G | ❌ 없음(불확실) | — | — |

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
