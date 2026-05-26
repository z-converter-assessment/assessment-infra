# ADR-0005: Terraform state를 bastion 로컬에서 시작

- 상태: Accepted (멀티 사용자 단계 진입 시 재검토)
- 날짜: 2026-05-26

## 컨텍스트

Terraform state 백엔드를 초기부터 remote로 구성할지, 로컬로 시작할지 결정해야 한다.

검토한 방안:
- **방안 A**: OpenStack Swift backend — 멀티 사용자 안전, 초기 설정 비용 있음
- **방안 B**: bastion 로컬 (`terraform.tfstate`) — 즉시 시작 가능, 단일 사용자 환경

## 결정

방안 B — bastion 로컬 state로 시작한다.

이유:
1. 현재는 단일 운영자가 bastion에서 실행한다.
2. Swift backend 설정(컨테이너 생성·접근 권한)은 추가 Horizon 작업이 필요하다.
3. 학습 단계에서 인프라가 자주 재생성되므로 remote backend 설정 비용 대비 이점이 작다.

## 트레이드오프

| 장점 | 단점 |
|---|---|
| 즉시 시작 가능, 추가 설정 없음 | bastion 장애 시 state 유실 위험 |
| 설정 단순 | 멀티 사용자 동시 apply 불가 (state lock 없음) |
| — | state 파일을 별도 백업해야 함 |

## 전환 조건

다음 중 하나 발생 시 ADR을 갱신하고 Swift backend로 이전한다.

- 운영자가 2명 이상으로 늘어날 때
- bastion 재생성 가능성이 생길 때

## 결과

- `terraform/terraform.tfstate`는 `.gitignore`에 포함 (git commit 금지)
- bastion 외부에 주기적 cp로 백업 (별도 운영 절차)
- `versions.tf`에 backend 블록 없음 — 이전 시 `backend "swift" {}` 추가
