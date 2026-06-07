# ADR-0001: engine과 agent를 별도 Terraform 루트로 분리

- 상태: Accepted
- 날짜: 2026-05-26

## 컨텍스트

assessment-engine(API·MQ·Cache·DB·Worker)과 assessment-agent(학습용 Agent VM)는 생명주기와 담당자가 다르다.
초기에는 단일 `terraform/` 루트 아래에 모두 두려 했으나, 다음 문제가 예상됐다.

- Agent VM은 엔진 인프라와 무관하게 독립적으로 apply/destroy해야 한다.
- 엔진 state에 Agent VM이 섞이면 `terraform destroy`가 의도치 않게 엔진 자원을 건드릴 위험이 있다.
- 추후 Agent fleet을 별도 팀이 운영할 경우 state 분리가 필요하다.

## 결정

`engine/terraform/`과 `agent/terraform/`을 별도 Terraform 루트로 분리한다.

- `engine/terraform/`: API·MQ·Cache·DB·Worker VM + 관련 SG·volume·FIP
- `agent/terraform/`: Agent VM N대 + 관련 포트

apply 순서 의존성은 코드로 명시 (`agent/terraform/data.tf`에서 engine이 생성한 `agent_sg`를 data source로 참조).

## 트레이드오프

| 장점 | 단점 |
|---|---|
| engine/agent 독립 apply·destroy | apply 순서를 수동으로 지켜야 함 (engine 먼저) |
| state 분리로 폭발 반경 제한 | cross-stack 참조를 data source로 해결해야 함 |
| 추후 remote backend 분리 용이 | 두 디렉토리 관리 부담 |

## 향후 고려

루트가 3개 이상으로 늘어나거나 팀이 커지면 Terragrunt `dependency` 블록으로 apply 순서를 선언적으로 관리하는 것을 검토한다.
