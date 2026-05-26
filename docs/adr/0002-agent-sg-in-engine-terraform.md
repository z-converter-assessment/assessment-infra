# ADR-0002: agent-sg를 engine/terraform에서 관리

- 상태: Accepted
- 날짜: 2026-05-26

## 컨텍스트

ADR-0001에서 engine/agent를 별도 Terraform 루트로 분리했다.
그런데 `mq-sg`는 Agent VM이 AMQP(5672) 연결을 하도록 `agent-sg`를 ingress source로 허용해야 한다.

두 가지 방안이 검토됐다.

- **방안 A**: `agent-sg`를 `agent/terraform`에서 생성하고, `engine/terraform`이 data source로 참조
- **방안 B**: `agent-sg`를 `engine/terraform`에서 생성하고, `agent/terraform`이 data source로 참조

## 결정

방안 B — `agent-sg`를 `engine/terraform/security_groups.tf`에서 생성한다.

이유: `mq-sg`의 ingress 규칙(`mq_5672_from_agent`)은 engine 인프라의 보안 정책이다.
engine이 "어떤 SG로부터 5672를 허용할지"를 결정하므로, 해당 SG도 engine이 소유해야 한다.
방안 A는 `engine/terraform`이 `agent/terraform`보다 나중에 apply돼야 하는 역방향 의존성을 만든다.

## 트레이드오프

| 장점 | 단점 |
|---|---|
| apply 순서가 engine → agent로 단방향 유지 | agent-sg가 engine state에 존재해 소유권이 다소 불명확 |
| engine이 자신의 보안 정책을 완전히 소유 | agent VM 없이도 agent-sg가 engine apply 시 생성됨 |

## 결과

- `engine/terraform/security_groups.tf`: `agent_sg` 리소스 정의
- `agent/terraform/data.tf`: `data "openstack_networking_secgroup_v2" "agent_sg"` 로 참조
- `engine/terraform/outputs.tf`: `agent_sg_id` output 노출 (향후 remote_state 참조용)
