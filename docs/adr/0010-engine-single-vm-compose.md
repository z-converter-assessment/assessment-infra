# ADR-0010: Engine 배포 — 단일 VM + Docker Compose 채택 (ADR-0003 대체)

- 상태: Accepted
- 날짜: 2026-06-07

## 컨텍스트

### 사용 시나리오 (1차 동기)

기업 미팅에서 확정된 제품 운용 모델은 **appliance 형태의 현장 배포**다:

1. 엔지니어가 **서버랙 1대를 직접 운반**하여 고객사 데이터센터에 반입
2. 랙 안의 서버에 assessment-engine을 설치하고 고객망에 연결
3. 고객 자산(서버군)에 **agent를 등록**하여 메트릭 수집을 개시
4. **약 2개월간 메트릭을 수집**하여 분석 보고서를 산출
5. 보고 종료 후 랙 회수

이 모델의 본 repo에 대한 제약:

- **고객망 의존성 최소화**: 현장마다 다른 네트워크 정책(SG·라우팅·DNS·방화벽)에 매번 적응해야 한다. VM 간 통신 토폴로지가 단순할수록 현장 적응 비용이 낮다
- **1인 운영**: 현장 엔지니어가 곧 운영자다. SSH·playbook·상태 점검 대상이 적을수록 사고 표면이 작다
- **하드웨어 1 unit**: 1U/2U 서버 1대가 곧 배포 단위. 그 위에 6 VM을 띄우는 것은 6 VM 분리의 격리 이점이 거의 없고, hypervisor 오버헤드와 자원 단편화만 더한다
- **2개월 short-lived**: SLA·HA 요구는 약함 (고객사가 본 시스템에 의존해서 운영하는 것이 아니라, 본 시스템이 고객을 관측). 단일 노드의 SPOF가 사업적으로 수용 가능

### ADR-0003 재평가

ADR-0003(2026-05-26)은 학습/테스트 단계의 OpenStack 환경에서 컴포넌트별 VM 분리를 전제로 "Docker 미사용 + 직접 설치"를 채택했다. 그 결정의 근거는 위 appliance 시나리오와 다음과 같이 충돌한다:

| ADR-0003 근거 | appliance 시나리오에서의 변화 |
|---|---|
| 폐쇄망 — Docker Hub 접근 불가 | 이미지를 **공장에서 사전 빌드 → tar 동봉** 또는 bastion outbound 활용. 현장에서 pull 안 함 |
| 컴포넌트당 VM 1개라 컨테이너 격리 이점 적음 | 단일 VM에 다중 컴포넌트 → 오히려 cgroup 격리·재시작 단위 분리가 필요 |
| Cinder 직접 마운트 단순 | 현장 appliance에서는 디스크 자체가 로컬 disk. Cinder 추상화는 OpenStack 테스트 환경 한정 |
| systemd 통일 운영 | `docker compose` 자체를 systemd unit 1개로 감싸면 동질성 유지 |

즉 ADR-0003의 전제(VM 분리 + OpenStack 멀티 VM)가 사용 시나리오와 정합하지 않게 되었다.

### 부수 동기

- **현행 운영 부담**: VM 6종(API·MQ·Cache·DB·Consumer·AI)의 SG·FIP·DNS·SSH·known_hosts·release 동기화가 컴포넌트 수에 비례
- **자원 비효율**: 학습/테스트 단계에서 각 VM 평균 CPU·메모리 사용률 10% 미만
- **자동화 진입 비용**: 6개 playbook의 release timing 동기화(alembic vs API 등)가 release 자동화(ADR-0011)의 상태 머신을 복잡하게 만듦

이들은 1차 동기가 아니라 결정의 부수적 보강 근거.

### 검토한 방안

- **방안 A (현행 유지)**: VM 6종 + 직접 설치 (ADR-0003)
- **방안 B (채택)**: VM 1대 + docker compose, stateful 볼륨은 host disk 또는 Cinder 마운트
- **방안 C**: VM 1대 + 직접 설치 (compose 없이 systemd 다중 unit)
- **방안 D**: k3s 단일 노드 + helm

## 결정

방안 B — **단일 노드에 docker compose로 전체 engine stack 배포**한다. 본 repo의 OpenStack 환경은 이 모델의 사전 검증 환경으로 둔다.

구성:
- **노드 1개**: `engine` (전 컴포넌트 호스트). 별도 유지: bastion / AI(Ollama) / agent fleet
- **compose 서비스**: `api` · `consumer` · `postgres` · `rabbitmq` · `redis`
- **stateful 볼륨**:
  - **OpenStack 검증 환경**: PostgreSQL 30 GB·RabbitMQ 20 GB Cinder 볼륨 attach → `/mnt/pgdata`, `/mnt/mqdata`로 마운트 → compose `volumes:` bind mount
  - **현장 appliance**: host 로컬 disk의 같은 경로(`/mnt/pgdata`, `/mnt/mqdata`)로 통일. compose 파일은 동일, 마운트 소스만 환경별로 다름
- **이미지 출처**:
  - 공식 이미지(`postgres:16`, `rabbitmq:3-management`, `redis:7`) — docker.io에서 pull
  - assessment-engine 이미지 — bastion 또는 빌드 호스트에서 빌드 또는 GHCR pull. 현장 반입 전에 `docker save` tar로 동봉, 현장에서 `docker load`
- **장애 격리·자가 복구**: 각 서비스에 `healthcheck` + `restart: unless-stopped` 지정. 컨테이너 단위 재시작이 가능하여 한 컴포넌트 장애가 전체 stack 재시작으로 확장되지 않음. 외부 오케스트레이터(k8s) 없이도 단일 노드 가용성 요구는 충족
- **AI VM(Ollama)**: 별도 유지(GPU/메모리 요구·lifecycle 상이) — 본 ADR 범위 밖. 현장 appliance에서는 동일 노드에 같이 올릴지 시나리오별 별도 결정

`engine` 노드의 OS는 Debian 13 유지(ADR-0006). docker-ce는 docker.com apt repo에서 설치.

## 트레이드오프

| | 방안 A (현행) | 방안 B (채택) | 방안 C (단일 VM + systemd) | 방안 D (k3s) |
|---|---|---|---|---|
| VM 수 | 6 | 1 | 1 | 1 |
| 자원 격리 | VM 단위 (강) | cgroup (중) | systemd slice (약) | cgroup + namespace (중) |
| SPOF | 컴포넌트별 | VM 1개 | VM 1개 | VM 1개 |
| 배포 단순성 | 6 playbook 동기화 | compose 1 파일 | systemd unit 5개 | helm chart |
| 이미지 기반 불변 배포 | ✗ | ✓ | ✗ | ✓ |
| Cinder 볼륨 관리 | OS mount 직결 | OS mount + compose bind | OS mount 직결 | PV/PVC 추상화 |
| 디버깅 (로그 조회) | `journalctl` | `docker logs` / `journalctl -u docker` | `journalctl` | `kubectl logs` |
| 학습 비용 | 낮음 | 낮음 | 낮음 | 높음 |
| Polling/private registry 필요성 | ✗ | △ (bastion outbound 활용) | ✗ | △ |
| 자동화 statemachine 복잡도 | 높음 (6 step) | 낮음 (1 step) | 중간 | 중간 |

ADR-0003 대비 주요 반증:
1. "폐쇄망 제약" → 현장 반입 전 `docker save` tar 동봉 경로로 해소. OpenStack 검증 환경은 bastion outbound 활용. private registry 신설 불필요
2. "Cinder 직접 마운트 단순성" → 검증 환경(OpenStack)은 Cinder 마운트 유지, 현장은 host disk 마운트. compose 파일은 양쪽 환경에서 동일하게 같은 경로를 참조
3. "systemd 통일 운영" → `docker compose`도 systemd unit 1개로 감쌀 수 있어 ops 인터페이스(`systemctl status engine-compose`) 동질성 유지

방안 D(k3s) 대비 이점:
- 현장 1인 엔지니어에게 k8s 운영 지식 요구 없음
- 단일 노드에서 k8s가 추가로 제공하는 가치(노드 fail-over, 자동 rescheduling)는 본 시나리오에서 발생하지 않음
- 컨테이너 단위 재시작·healthcheck·의존성 순서는 compose만으로 충족 (`docker compose restart <svc>`, `healthcheck`, `depends_on: condition: service_healthy`)

## 결과

- **ADR-0003 상태 → Deprecated** (본 ADR 수락 시점에 변경)
- terraform: `engine/terraform/instances.tf`에서 VM 정의 6개 → 1개로 축소 (`engine`). AI VM은 별도 유지
- terraform: `engine/terraform/volumes.tf`에서 PostgreSQL/RabbitMQ 볼륨만 유지, attach 대상은 `engine` VM
- terraform: `security_groups.tf`에서 컴포넌트 간 통신용 SG rule 제거(같은 host loopback) — 외부 인입 SG만 유지(`api:8000`, `mq:15672`, `ssh:22`)
- ansible: `roles/postgres` · `roles/rabbitmq` · `roles/redis` · `roles/app` 사용 중단, 신규 `roles/engine_compose` 도입
- `engine/compose/docker-compose.yml`, `.env` template 신설. 환경별 차이는 `.env`의 마운트 경로 변수로만 흡수
- `playbook-{db,mq,cache,api,consumer}.yml` 통합 → `playbook-engine.yml` 1개
- 환경변수 inject 경로: `roles/engine_compose/templates/.env.j2` (현행 `app.env.j2`·`zdm.yml` 통합)
- 현장 appliance 반입 절차(이미지 tar 동봉·load·`docker compose up`)는 별도 문서(`docs/operations/field-deploy.md`)로 후속 정리
- `docs/architecture/{topology,components,runtime}.md` 갱신, `docs/operations/deploy-walkthrough.md` 재작성

## 후속 결정 (재논의 신호)

다음 조건 중 하나라도 충족되면 분리 또는 오케스트레이션 도입을 재논의:

- 단일 VM의 가용성 요구가 SLA화 (HA 필요)
- 한 컴포넌트(주로 postgres)의 자원 요구가 다른 컴포넌트의 noisy neighbor 문제를 발생시킴
- 멀티 테넌시·동적 스케일링 요구
- 컴포넌트별 독립 릴리즈 cadence 분화

분리 결정 시 신규 ADR 작성, 본 ADR 상태 → Deprecated.
