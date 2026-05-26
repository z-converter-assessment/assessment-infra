# ADR-0003: Docker 미사용 — 컴포넌트 직접 설치 방식 채택

- 상태: Accepted
- 날짜: 2026-05-26

## 컨텍스트

assessment-engine의 각 컴포넌트(API·MQ·Cache·DB·Worker)를 VM에 배포할 때 컨테이너화 여부를 결정해야 한다.

검토한 방안:
- **방안 A**: Docker + docker-compose로 각 VM에 컨테이너 배포
- **방안 B**: apt/pip으로 직접 설치 + systemd 관리

## 결정

방안 B — Docker 없이 직접 설치한다.

이유:
1. **폐쇄망 제약**: Docker Hub 및 외부 registry 접근이 불가하다. Private registry 구성은 추가 인프라가 필요하다.
2. **단순성**: 컴포넌트당 VM 1개 구조에서 컨테이너 격리의 이점이 크지 않다.
3. **Stateful 서비스**: RabbitMQ·PostgreSQL은 Cinder 볼륨을 직접 마운트해야 하므로 컨테이너 볼륨 관리가 오히려 복잡해진다.
4. **디버깅 접근성**: systemd journalctl로 로그를 직접 조회할 수 있어 운영이 단순하다.

## 트레이드오프

| 장점 | 단점 |
|---|---|
| 폐쇄망에서 추가 registry 불필요 | 이미지 기반 불변 배포 불가 |
| Cinder 볼륨 직접 마운트 단순 | 패키지 버전 드리프트 위험 |
| systemd로 통일된 프로세스 관리 | VM OS 의존성 (ubuntu 24.04 가정) |

## 결과

- 모든 VM은 `apt` + `pip install wheel` + `systemd` 조합으로 구성
- Ansible role이 패키지 설치·설정·서비스 기동을 담당
- assessment-engine 배포는 wheel 파일을 venv에 pip install 하는 방식
