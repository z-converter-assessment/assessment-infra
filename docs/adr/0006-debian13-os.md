# ADR-0006: 엔진 VM OS를 Debian 13(Trixie)으로 결정

- 상태: Accepted
- 날짜: 2026-05-26

## 컨텍스트

초기 검토 단계에서는 Ubuntu 24.04 LTS를 기준으로 Ansible 코드를 작성했다.
그러나 운영 환경의 OpenStack 이미지 공급 현황과 조직 표준을 재확인한 결과 Debian 13(Trixie)으로 변경하기로 결정했다.

## 결정

모든 엔진 컴포넌트 VM(API·MQ·Cache·DB·Worker·AI)의 OS를 Debian 13(Trixie)으로 통일한다.

주요 영향:
- SSH 기본 접속 계정: `ubuntu` → `debian`
- Python 런타임: `python3.12` → `python3`(Trixie 기본 Python 3.13)
- PGDG apt repo codename: `noble-pgdg` → `trixie-pgdg`
- TimescaleDB apt repo: `packagecloud .../ubuntu/ noble` → `packagecloud .../debian/ trixie`
- RabbitMQ: Ubuntu universe repo → Debian main repo (패키지명 동일: `rabbitmq-server`)

## 트레이드오프

| 장점 | 단점 |
|---|---|
| 조직 표준 이미지 사용 | Ubuntu 전용 PPA 일부 사용 불가 |
| Debian 장기 안정성 | Ubuntu LTS 대비 커뮤니티 자료 적음 |
| 경량 기본 설치 | 일부 패키지명·경로 차이로 Ansible 수정 필요 |

## 결과

- `engine/terraform/variables.tf`: `image_name` 기본값 변경
- `engine/terraform/terraform.tfvars.example`: `image_name` 변경
- `engine/ansible/group_vars/all/common.yml`: `ansible_user: debian`, `python_version: "3.13"` 추가
- `engine/ansible/roles/app/tasks/main.yml`: 버전 고정 패키지 → `python3`/`python3-venv`
- `engine/ansible/roles/postgres/tasks/main.yml`: repo codename 변경
- ADR-0004: RabbitMQ 설치 경로가 Ubuntu universe → Debian main으로 변경됨 (내용은 동일)
