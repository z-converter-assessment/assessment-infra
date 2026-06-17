# Agent 바이너리 커버리지 테스트 — 요구사항

> 작성일: 2026-06-16 · 출처: 운영자 지시
> 대상: assessment-agent **v1.2.0** 바이너리 × OpenStack glance 이미지
> 결과 기록처: [`agent-binary-image-coverage.md`](agent-binary-image-coverage.md)

## 0. 현재 목표 (Goal)

**이번 실행 범위 = Ubuntu 계열 전체.** (나머지 OS는 이번 목표에서 제외)

대상 이미지 (3-2의 OS버전 그룹 + 대표→병렬 전략 적용):

| OS 그룹 | 바이너리 | 이미지 |
|---|---|---|
| ubuntu18.04 | modern | ubuntu18.04_x64_bios_2.2G · ubuntu18.04_x64_uefi_2.2G |
| ubuntu20.04 | modern | ubuntu20.04_x64_bios_2.2G · ubuntu20.04_x64_uefi_2.2G |
| ubuntu22.04 | modern | ubuntu22.04_x64_bios_2.2G · ubuntu22.04_x64_uefi_2.2G |
| ubuntu24.04 | modern | ubuntu24.04_x64_bios_3.5G · ubuntu24.04_x64_uefi_3.5G |

> 범위 조정 필요하면 본 표만 수정.

## 1. 목적

v1.2.0가 제공하는 바이너리들이 glance에 등록된 OS 이미지들을 실제로 어디까지
커버하는지 **실측**한다. 단순 빌드 매트릭스 추론이 아니라, 각 이미지에 인스턴스를
띄우고 agent를 배포해 **MQ 발행**과 **ZDM install 발행**이 실제로 동작하는지 확인한다.

## 2. 범위

- **대상 이미지**: 커버리지 매트릭스 기준 **커버 가능 전체**(~69). 바이너리 미매칭(커버 불가)
  이미지(suse11, win2003 32bit, win2008 NT6.0)는 테스트 대상에서 제외.
- **기준 바이너리**: 현재(v1.2.0) 제공 바이너리 — 별도 빌드/수정 없이 있는 그대로 테스트.
- **BIOS/UEFI 분리**: 동일 OS라도 **BIOS·UEFI 이미지를 각각 별도 테스트**한다.
  (바이너리 선택은 펌웨어와 무관하지만 부팅·ZDM 동작이 펌웨어별로 다를 수 있어 독립 검증)

## 3. 실행 순서·방식

### 3-1. Windows — 사전 일괄 부팅

- Windows는 부팅 시간이 길어, **Windows glance 이미지별 인스턴스를 먼저 전부 띄워 둔다**(워밍업).
- 이후 Linux 테스트가 도는 동안 병렬로 부팅이 진행되도록 한다.

### 3-2. Linux — OS버전별 "대표 1대 검증 후 병렬"

이미지당 다음 순서를 1회 수행:
  1. 인스턴스 1대 부팅
  2. (매칭되는) 바이너리 배포
  3. **MQ 발행 확인** — 엔진이 agent가 심어진 인스턴스를 인식하는지
  4. **ZDM install 발행 확인** — install 작업이 정상 수행되는지
  5. 결과를 커버리지 매트릭스에 기입
  6. 테스트 끝난 인스턴스는 **즉시 삭제**

실행 전략(**동일 OS 버전에 다수 이미지**가 있을 때 — 예: BIOS/UEFI, lvm_smb_nfs, _v1 변종):

- 이미지를 **OS 버전 단위로 그룹화**한다(`_x64`/`_x86` 앞 prefix 기준. 예: `centos7`, `rocky8`, `alma9`).
- 각 그룹에서 **대표 이미지 1대를 먼저 단독 검증**한다.
- 대표가 **배포 + MQ + ZDM install 모두 성공**하면 → 같은 그룹의 **나머지 이미지를 병렬로** 테스트한다.
- 대표가 실패하면 → 나머지는 **순차**로 돌려 각 이미지를 개별 진단한다.
- 그룹 간에는 순차로 진행한다.

> 병렬 실행 때문에 MQ 발행 확인은 **인스턴스 IP로 server_inventory를 매칭**(여러 agent가 동시 보고해도 호스트 구분 가능)한다.

## 4. 인스턴스 자원 요건

- **큰 이미지 부팅**: 기본 flavor(10G root)보다 디스크가 큰 이미지(oracle/suse15/amazon/redhat7 등)는
  **디스크가 충분한 큰 flavor로 부팅**한다(이미지 크기에 맞춰 선택).

## 5. 검증 항목(합격 기준)

| 항목 | 합격 기준 |
|---|---|
| MQ 발행 | agent 기동 후 엔진 server_inventory에 해당 인스턴스가 신규 인식(최근 보고)됨 |
| ZDM install 발행 | 엔진에서 install 작업 발행 시 agent가 수행해 작업이 정상 완료(success)됨 |

### 5-1. 배포 권한 확인 (매트릭스 필드)

각 이미지에 대해 아래를 확인해 커버리지 매트릭스에 **`배포 유저 / 서비스 실행 권한`** 필드로 기입한다.

- **생성 유저**: 바이너리 배포 시 어떤 계정을 생성하는가
- **유저 권한**: 그 계정이 어떤 권한(sudo 유무 등)을 갖는가
- **서비스 실행 권한**: systemd 서비스가 어떤 권한(User=)으로 실행되는가
- **systemd 없는 OS**: 별도로 어떤 권한/기동 방식(SysV init 등)이 필요한지 별도 기입

> 권한 모델 상세·근거는 [`agent-binary-image-coverage.md`](agent-binary-image-coverage.md)의 "배포 권한 모델" 섹션 참조.

## 6. 결과 기록

- 결과는 [`agent-binary-image-coverage.md`](agent-binary-image-coverage.md)의 매트릭스
  (`mq 발행 성공여부` / `zdm install 발행 성공 여부` 칸)에 이미지별(BIOS/UEFI 각각) 기입.

## 7. 알려진 제약 (요구사항 해석 시 참고)

- **Windows ZDM install**: 엔진 ZDM 패키지가 Linux 전용(tarball + bash `install.sh`)이고
  Windows env에 `WORKER_*` 미주입 → 현재 구성상 **구조적으로 불가**. Windows의 ZDM 칸은
  by-design 실패로 처리(별도 지원 작업 필요).
- **RHEL 계열 ZDM**: SELinux enforcing이 install.sh를 차단 → permissive 적용 필요(ADR-0012).
