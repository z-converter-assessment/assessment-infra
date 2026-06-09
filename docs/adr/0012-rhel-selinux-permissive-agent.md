# ADR-0012: Agent 테스트 플릿 RHEL 계열을 SELinux permissive로 설정

- 상태: Accepted
- 날짜: 2026-06-07

## 컨텍스트

agent 테스트 플릿은 OS 7종(Debian 13/12, Ubuntu 24.04/22.04, Rocky 9, AlmaLinux 9,
CentOS Stream 9)으로 구성된다. 동일한 Ansible role·동일한 systemd 유닛으로 배포하는데,
**Ubuntu/Debian 계열은 정상 동작하나 RHEL 계열(Rocky·Alma·CentOS)에서만 agent 런타임의
ZDM `install.sh` 작업이 실패**했다.

원인 분석:

- ZDM `install.sh`는 Ansible이 아니라 **agent 바이너리가 런타임에 `task.install`을 받아**
  패키지를 내려받고 sudo로 실행하는 흐름이다.
- agent는 systemd 서비스(`assessment-agent`, NOPASSWD sudo)로 실행되며, 받은 스크립트를
  작업 디렉토리(`/var/lib/agent-worker`, `var_lib_t`)나 `/tmp`(`tmp_t`)에 두고 실행한다.
- **RHEL 계열은 SELinux enforcing 기본**이라, 서비스 도메인이 `var_lib_t`/`tmp_t` 파일에
  대한 `execute` 권한이 없어 AVC denial로 실행이 차단된다. `PrivateTmp=yes`·sudo 도메인
  전이도 추가 차단 지점이 될 수 있다.
- **Ubuntu/Debian은 AppArmor를 쓰지만 이 커스텀 바이너리용 프로파일이 없어 사실상
  unconfined**로 실행되므로 같은 동작이 통과한다. → OS 계열 간 동작 불일치의 근본 원인은
  MAC(Mandatory Access Control) 레이어 차이.
- 본 레포에는 SELinux 관련 처리(정책 모듈·fcontext·boolean)가 전무했다.

env 로딩은 원인이 아니다 — env 파일은 이미 `/etc/assessment-agent`(`etc_t`)에 있어
systemd(init_t)가 정상적으로 읽는다.

## 결정

**RHEL 계열(`ansible_os_family == 'RedHat'`)에 SELinux를 permissive로 설정**한다.

- `common` role에 `ansible.posix.selinux`로 `state: permissive` 적용 (정책 위반을 차단하지
  않고 AVC 로그만 남기는 모드). enforcing→permissive 전환은 재부팅 불필요.
- `python3-libselinux` 선설치, `requirements.yml`에 `ansible.posix` collection 추가.
- 적용 범위는 **agent 테스트 플릿 한정**. engine VM·운영 appliance에는 적용하지 않는다.

근거: 본 환경은 다양한 OS에서 agent 동작을 검증하는 **테스트 플릿**이며, AppArmor가 사실상
unconfined인 Ubuntu와 동작을 일치시키는 것이 목표다. permissive는 RHEL을 그와 동등한
"제약 없는 실행" 상태로 만든다.

## 트레이드오프

| | enforcing 유지 + 정책 모듈 | permissive (채택) |
|---|---|---|
| 보안 강제 | SELinux 보호 유지 | 사실상 비활성(로그만) |
| 구현 비용 | `audit2allow` 정책 모듈 작성·배포·유지 | 한 줄 설정 |
| OS 간 동작 일치 | 정책이 정확해야 일치 | Ubuntu(unconfined)와 즉시 동등 |
| 운영 적합성 | 운영 appliance에 적합 | 테스트 플릿 한정 |

permissive는 SELinux 강제를 사실상 끄는 것이므로 보안이 약화된다. 그러나 본 대상은
인터넷 비노출 테스트 플릿이고, 목적이 "여러 OS에서 동일 agent 동작 검증"이라 보안 강제보다
동작 일치가 우선한다.

## 후속 (운영 appliance가 RHEL일 경우)

운영 환경에 RHEL을 쓰게 되면 permissive 상주는 부적합하다. permissive에서 작업을 1회
완주시켜 쌓인 AVC를 `audit2allow -a`로 모아 **최소 권한 정책 모듈**을 생성·배포하고
enforcing을 유지하는 정공법으로 전환한다. 그 시점에 본 ADR을 Deprecated 처리하고 신규 ADR로
대체한다.
