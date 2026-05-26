# ADR-0004: RabbitMQ를 Ubuntu universe repo에서 설치

- 상태: Accepted
- 날짜: 2026-05-26

## 컨텍스트

RabbitMQ 공식 설치 가이드는 Cloudsmith(`ppa1.rabbitmq.com`)를 권장한다.
그러나 이 환경은 폐쇄망으로 외부 PPA에 접근할 수 없다.

검토한 방안:
- **방안 A**: Cloudsmith PPA — 공식 최신 버전, 폐쇄망에서 차단됨
- **방안 B**: Ubuntu 24.04 universe repo — apt 기본 제공, 폐쇄망 내 미러 사용 가능
- **방안 C**: .deb 패키지를 bastion에서 다운로드 후 VM에 복사

## 결정

방안 B — Ubuntu universe repo(`rabbitmq-server` 패키지)를 사용한다.

이유: 폐쇄망 내부 apt 미러가 universe repo를 포함하고 있어 별도 파일 전송 없이 설치 가능하다.
Ubuntu 24.04 universe의 RabbitMQ 버전은 학습 환경 요구사항을 충족한다.

## 트레이드오프

| 장점 | 단점 |
|---|---|
| 폐쇄망 내 apt 미러만으로 설치 가능 | 공식 최신 버전보다 낮을 수 있음 |
| 추가 파일 전송 불필요 | Ubuntu 버전 업그레이드 시 패키지 버전 변동 |
| Ansible role이 단순해짐 | Cloudsmith 제공 플러그인·관리도구 일부 미포함 가능 |

## 결과

- `engine/ansible/roles/rabbitmq/tasks/main.yml`: `apt: name=rabbitmq-server`
- Cloudsmith repo 추가 task 불필요
