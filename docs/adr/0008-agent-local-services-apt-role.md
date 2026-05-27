# ADR-0008: Agent 로컬 서비스를 신규 *-local role로 apt 직접 설치

- 상태: Accepted
- 날짜: 2026-05-27

## 컨텍스트

Agent VM에는 모니터링 대상 서비스로 PostgreSQL과 Redis를 로컬에 설치해야 한다.
engine에는 이미 `postgres` role과 `redis` role이 존재하며, 이를 재사용할지 별도 role을 작성할지 결정이 필요했다.

engine role의 특성:
- `postgres` role: Cinder 마운트 + PGDG repo + TimescaleDB 확장 + DB/user 생성 포함
- `redis` role: bind 0.0.0.0 설정 포함 (engine 내부 접근용)

agent VM에서 필요한 것:
- 모니터링 대상으로서 단순히 서비스가 실행 중이면 됨
- Cinder 없음, TimescaleDB 불필요, 외부 노출 불필요

## 결정

**신규 `postgres-local` · `redis-local` role 작성** 채택.

- agent-subnet이 라우터에 연결되어 apt 패키지 저장소에 직접 접근 가능
- 단순 `apt install` + 기본 설정만 수행하는 경량 role로 작성
- engine role과 코드 공유 없이 독립적으로 유지

## 트레이드오프

| | engine role 재사용 | 신규 *-local role (채택) |
|---|---|---|
| 코드 중복 | 없음 | role 파일 별도 존재 |
| 복잡도 | engine 전용 변수·task가 agent에 노출 | 역할 명확히 분리 |
| 유지보수 | engine 변경이 agent에 의도치 않게 영향 | 독립적 변경 가능 |

agent의 요구사항(단순 설치·실행)이 engine(Cinder·TimescaleDB·PGDG)과 근본적으로 달라
재사용보다 분리가 장기적으로 유지보수 부담이 낮다.
