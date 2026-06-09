# ADR-0013: Agent 테스트 전용 내부 네트워크/서브넷을 Terraform으로 생성

- 상태: Accepted
- 날짜: 2026-06-09

## 컨텍스트

agent 테스트 플릿의 한 목표는 **네트워크 토폴로지 시각화 검증** — 각 agent를 여러 네트워크/서브넷에 동시 소속시켜 다양한 토폴로지를 재현하고, 엔진의 시각화 기능을 검증한다(멀티 NIC, 패턴 A).

현재 상태:
- 레포 정책(CLAUDE.md): **network·subnet·router·keypair는 Horizon 수동 생성, Terraform은 `data`/`variable` 참조만 — 재생성 금지**.
- `agent/terraform`은 이 정책대로 네트워크/서브넷/라우터를 **하나도 생성하지 않고** 전부 `data`로 참조한다(검증 완료). `agent_extra_networks`(멀티 NIC)도 `data` 참조라 **Horizon 사전 생성을 전제**한다.
- primary `agent-subnet`은 Horizon에서 라우터에 연결돼 outbound(apt·ZDM 다운로드 등)를 제공하며(ADR-0008), **모든 agent가 primary에 붙는다**. agent 바이너리는 이미 bastion 프리스테이지(`local_file`)다.

문제:
- 다양한/다수의 테스트 서브넷을 Horizon에서 수동 생성하는 것은 번거롭고 재현성이 낮으며 드리프트(코드 밖 토폴로지) 위험이 있다. 테스트 토폴로지를 **코드로 선언**하고 싶다.

제약:
- app-cred(member scope)는 **router external gateway 부착**에 권한이 부족할 수 있다(외부망 연결은 elevated 권한·공유 external net 필요).
- Terraform local state(ADR-0005)는 본 세션에서 CD 재실행 시 state 유실로 자원 중복 생성 사고를 낸 바 있다 → 네트워크를 인스턴스와 같은 state에 두면 같은 churn 위험.

권한 검증(2026-06-09): app-cred(member scope)로 **내부 network·subnet 생성/삭제 가능 확인**(throwaway `tf-permcheck-*`, CIDR 10.250.250.0/24로 생성→삭제, 잔존 0). 즉 internal-only 생성은 권한상 실현 가능. (router external gateway는 미검증 — 본 결정 범위 밖.)

## 결정

**테스트 전용 *내부* 네트워크/서브넷에 한해 Terraform 생성을 허용한다** (현 "재생성 금지" 정책의 명시적 예외).

1. **범위 (하이브리드)**: `agent_extra_networks`의 `data` 참조를 `resource` 생성(`openstack_networking_network_v2`·`openstack_networking_subnet_v2`)으로 전환한다. **primary `agent-subnet` + outbound 라우터는 Horizon 유지** — outbound가 필요한 작업(apt·ZDM·릴리즈)은 primary가 담당하므로 영향 없음. 바이너리 프리스테이지 모델도 불변.
2. **외부 연결성 (내부 전용)**: 생성하는 테스트 네트워크는 **router/external gateway 미부착**한 격리 네트워크다. 토폴로지 시각화 목적엔 인터페이스/서브넷 소속만으로 충분하고, external gateway 권한 이슈를 회피한다.
3. **State 격리**: 테스트 네트워크는 agent 인스턴스와 **분리된 state**(별도 terraform 디렉터리 또는 별도 backend 경로)로 관리해 인스턴스 destroy/recreate가 네트워크를 삭제하지 않게 한다. (대안인 동일 state는 destroy 시 네트워크까지 삭제·재생성 churn이라 기각.)
4. **SG**: 테스트망 port에도 기존 `agent_sg`(engine terraform 소유, ADR-0002)를 재사용한다(현행 유지). 서브넷별 SG 분리가 필요하면 후속 ADR.

## 트레이드오프

### Horizon 수동 vs Terraform 생성 (테스트 환경 관점)
| 관점 | Horizon 수동 (현행) | Terraform 생성 (본 결정, 내부망 한정) |
|---|---|---|
| 재현성/IaC | 낮음(수동 클릭) | 높음 — 다수 서브넷을 map으로 선언·apply |
| 다양한 토폴로지 | 수동 다수 생성 번거로움 | 이상적 — 선언적 매트릭스 |
| 권한 | external gw 등 콘솔서 1회 처리 | 내부망 생성은 member로 가능, external gw는 회피(내부 전용이라 불요) |
| 라이프사이클 | network가 state 밖이라 인스턴스와 독립 | state 분리 시 보존 / 동일 state면 destroy가 삭제 |
| 멀티 스택 공유 | engine·agent 각자 data 참조 | 테스트망은 agent 전용이라 공유 충돌 적음 |

### 내부 전용 vs outbound
internal-only는 external gateway 권한 문제를 없애고 시각화 목적에 충분. outbound가 필요해지면 primary agent-subnet(Horizon)을 쓰거나 별도 router 작업(권한 확인 필요) — 본 결정 범위 밖.

## 영향 / 변경 대상

- **CLAUDE.md 정책 갱신**: "terraform network 재생성 금지"에 **"테스트 전용 내부망은 예외"** 명시.
- `agent/terraform/data.tf`: `data ... extra` → `resource`. 변수 스키마(`agent_extra_networks`)에 **서브넷 속성(cidr, 필요 시 gateway_ip·dns·dhcp)** 추가 필요(현재는 network_name/subnet_name만).
- State 분리 채택 시: 별도 terraform 디렉터리/backend 구성 + `gen_inventory`·apply 순서 문서화.

## 구현 후속 (결정은 확정, 아래는 구현 작업)

- **별도 state 구성**: 테스트 네트워크용 terraform 디렉터리(예: `agent/terraform/network/`) + 별도 backend 경로(ADR-0005 로컬 백엔드 패턴 — 워크스페이스 밖 고정경로). agent 인스턴스 stack은 생성된 network/subnet을 `data`로 참조(생성 순서: network → 인스턴스).
- **변수 스키마 확장**: `agent_extra_networks`에 서브넷 속성(`cidr`, 필요 시 `gateway_ip`·`enable_dhcp`·`dns`) 추가. `data.tf`의 `extra` data → 신규 stack의 `resource`로 이전.
- **CLAUDE.md 정책 갱신**: "terraform network 재생성 금지"에 "테스트 전용 내부망은 예외(본 ADR)" 명시.
- **게스트 OS extra NIC**: 시각화가 Neutron port 레벨이면 불요. agent가 게스트 OS 인터페이스를 읽어 보고해야 하면 cloud-init/ansible로 extra NIC up 처리 필요(별도 판단).

## 검증 완료 (본 ADR 확정 근거)

- state 격리 방식: **별도 state** 확정.
- 권한: app-cred member로 internal network/subnet 생성/삭제 가능 검증(컨텍스트 참조).
