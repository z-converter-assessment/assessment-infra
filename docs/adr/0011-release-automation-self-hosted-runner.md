# ADR-0011: Release 자동화 — bastion self-hosted GitHub Actions runner

- 상태: Accepted
- 날짜: 2026-06-07

## 컨텍스트

### 배포 대상 두 환경

ADR-0010 채택으로 본 시스템의 배포 단위는 "단일 노드 + docker compose"로 통일되었지만, 그 단일 노드가 위치하는 환경은 **두 가지**다:

| 환경 | 위치 | 네트워크 | 운영자 | release 적용 빈도 |
|---|---|---|---|---|
| **검증 환경** | 본사 OpenStack | GitHub outbound 가능 | infra 팀 | release마다 자동 |
| **현장 appliance** | 고객사 데이터센터 | 통상 폐쇄 (GitHub 도달 불가 가정) | 현장 엔지니어 1인 | 반입 1회 (2개월 운용) + hotfix |

같은 release artifact라도 **적용 경로가 다르다**:
- 검증 환경: release publish → runner가 자동 배포 → health check
- 현장 appliance: release publish → 본사에서 **배포 번들** 생성 → 엔지니어가 저장매체로 운반 → 현장에서 오프라인 적용

따라서 자동화는 "원격 push"가 아니라 "**번들 생산 + 검증 환경 push**"의 두 워크플로로 나누어야 한다.

### 현행 수동 절차의 문제

현재 engine·agent 배포는 bastion에서 수동 단계로 진행된다:

1. bastion에서 `gh release download`로 wheel·바이너리 수동 취득
2. `engine/ansible/group_vars/all/engine.yml`의 `engine_version` 수동 갱신
3. `cd engine/terraform && terraform apply` 수동 실행 (변경 있을 때)
4. `cd engine/ansible && ansible-playbook -i inventory.yml playbook-*.yml` 컴포넌트별 수동 실행

문제:
- **휴먼 에러**: `engine_version` 누락·playbook 실행 누락·alembic 순서 실수
- **추적성 결여**: 어느 release가 언제 어느 VM에 적용되었는지 git에만 의존
- **재현성 약함**: bastion 작업자마다 환경 변수·shell 차이
- **release ↔ 배포 시차**: assessment-engine repo에서 release를 cut해도 자동 반영되지 않음
- **현장 번들의 임시 조립**: 매 반입 건마다 엔지니어가 수작업으로 wheel·image tar·playbook을 묶음 → 누락·버전 mismatch 위험

ADR-0010 채택으로 배포 step이 단일 playbook 1개로 축소되면서, 자동화 ROI가 임계점을 넘었다.

### 검토한 방안

자동화 매커니즘:
- **방안 A (채택)**: bastion에 self-hosted GitHub Actions runner를 systemd로 등록 → assessment-engine repo의 release 태그 push가 본 repo workflow를 트리거하여 bastion에서 terraform/ansible 자동 실행
- **방안 B**: AWX/Ansible Tower 별도 호스트에 설치 → webhook 수신
- **방안 C**: cron + bastion에서 GitHub Releases polling
- **방안 D**: GitHub-hosted runner + bastion에 SSH로 진입

현장 배포 경로:
- **경로 F1 (채택)**: 본사 runner가 release 수신 시 **검증 환경 push**와 **번들 빌드**를 병행. 번들은 GitHub release asset(또는 본사 object storage)에 업로드 → 엔지니어가 본사 또는 사전 다운로드 지점에서 매체로 운반 → 현장에서 오프라인 적용
- **경로 F2**: 현장→본사 VPN 후 본사 runner가 ansible push
- **경로 F3**: 현장에 별도 runner를 두고 본사 GitHub와 직접 통신

F2는 고객 보안 정책 의존도가 높고, F3는 현장 노드를 GitHub와 연결해야 해서 사실상 폐쇄망 가정과 충돌. F1이 대다수 현장 정책과 호환되며 매체(저장매체) 운반은 이미 랙 운반 동선에 포함된다.

## 결정

방안 A + 경로 F1 — **bastion에 self-hosted runner 등록 + release 수신 시 ① 검증 환경 자동 push ② 현장용 배포 번들 빌드를 병행**한다.

### 공통 — runner

- **runner host**: bastion (별도 ops 호스트 신설하지 않음)
- **scope**: org-level 또는 본 repo level. 본 repo level로 시작
- **systemd unit**: `actions.runner.<org>-<repo>.<name>.service` (공식 `svc.sh install` 결과물)
- **권한**: runner는 bastion `debian` 사용자로 실행 — terraform·ansible·SSH key·vault password·clouds.yaml 접근 권한이 이미 있음
- **트리거**: assessment-engine repo에서 release 발행 시 `repository_dispatch`로 본 repo의 두 workflow(`deploy-engine`, `build-field-bundle`)를 모두 트리거. agent는 별도 `deploy-agent` / 번들에 동봉
- **secret 경계**: 배포 secret은 원칙적으로 bastion 로컬(`~/.vault-pass`, `~/.ssh/engine-key.pem`, `~/.config/openstack/clouds.yaml`)에 두고 workflow는 **파일 경로만 참조**한다.
  - **예외 — `terraform.tfvars`**: 이 파일은 gitignore 대상이라 checkout으로 확보되지 않고, `vault.yml`처럼 암호화 commit하기도 어렵다(terraform이 평문 변수 파일을 요구). 따라서 `ENGINE_TFVARS` **GitHub Environment secret**(`openstack-staging` scope)으로 보관하고 `write terraform.tfvars` step에서 런타임 생성한다. 이 한 값만 bastion 경계를 벗어나 GitHub secret store에 보관됨을 **의도적으로 허용**한다. 근거: tfvars는 OpenStack provisioning 파라미터 수준이고(앱 deep secret은 `vault.yml`에 잔류), Environment scope로 required-reviewer 게이트와 GitHub 감사 로그를 함께 얻는다. 트레이드오프는 아래 "핵심 우려와 대응" 참조.

### Workflow 1 — `deploy-engine.yml` (검증 환경 자동 적용)

1. checkout assessment-infra (현재 release 태그)
2. assessment-engine release artifact 다운로드 (`gh release download` 또는 docker image pull)
3. `engine_version` 변수를 workflow input/dispatch payload에서 주입 (파일 commit 없음)
4. `terraform plan` → 변경 있으면 사람 승인 필요 (workflow `environment: openstack-staging` + required reviewer)
5. `terraform apply`
6. `ansible-playbook playbook-engine.yml` 실행
7. health check (compose service `healthy`, `/health` 200) 후 종료

### Workflow 2 — `build-field-bundle.yml` (현장 appliance용 번들 생산)

본 workflow는 검증 환경에 푸시하지 않는다. **운반 가능한 self-contained 번들**을 산출한다.

번들 구성 (`bundle-<engine_version>-<infra_sha>.tar.gz`):

```
bundle/
├── manifest.json             # engine_version, infra commit, build_at, checksums, image digests
├── images/
│   ├── assessment-engine.tar # docker save 결과 (압축)
│   ├── postgres-16.tar
│   ├── rabbitmq-3.tar
│   ├── redis-7.tar
│   └── (옵션) ollama.tar
├── compose/
│   ├── docker-compose.yml
│   └── .env.template         # 현장 입력 항목 placeholder (고객망 DNS·IP·자격 등)
├── ansible/
│   ├── playbook-field.yml    # ansible_connection=local
│   ├── roles/engine_compose/
│   └── inventory.localhost.yml
├── scripts/
│   ├── install.sh            # 부트스트랩: docker load → .env 검증 → playbook 실행
│   └── healthcheck.sh
└── SHA256SUMS                # 매체 무결성
```

빌드 단계:

1. checkout assessment-infra (현재 release 태그)
2. release artifact·image pull → 각 이미지 `docker save` (gzip)
3. ansible artifact (`roles/engine_compose`, `playbook-field.yml`) 복사
4. `install.sh` 생성 — 현장에서 인터넷 없이 실행 가능하도록 모든 의존을 번들 내로 한정
5. `manifest.json` + `SHA256SUMS` 생성 (cosign 서명은 후속 결정)
6. 본 repo의 GitHub release에 asset 업로드 (또는 본사 object storage upload)

번들 적용 (현장):

1. 엔지니어가 매체에서 번들 추출, `SHA256SUMS` 검증
2. `.env.template` → `.env` 현장 입력 채움
3. `./install.sh` 실행 → `docker load` (전 이미지) → `ansible-playbook playbook-field.yml -i inventory.localhost.yml` (로컬 적용)
4. `./healthcheck.sh`로 자체 확인
5. 결과 로그를 분석해 본사에 회수 (회수 매체·채널은 별도 운영 결정)

### 환경 분리

| 항목 | 검증 환경 | 현장 appliance |
|---|---|---|
| terraform | 실행함 (OpenStack provider) | 실행 안 함 — 노드 자체가 사전 준비된 서버 |
| ansible connection | SSH via bastion | `local` (노드 자기 자신) |
| compose 마운트 source | Cinder volume mount | host disk mount |
| secret 출처 | bastion 로컬 vault | `.env`에 현장 엔지니어 직접 입력 |
| health check | runner가 원격 호출 | `install.sh`가 로컬 호출 |

## 트레이드오프

| | 방안 A (채택) | 방안 B (AWX) | 방안 C (cron polling) | 방안 D (GitHub-hosted + SSH) |
|---|---|---|---|---|
| 인프라 추가 | runner 프로세스 1개 | AWX VM 1대 + DB | 없음 | 없음 |
| 트리거 지연 | 즉시 (push event) | 즉시 (webhook) | polling interval | 즉시 |
| GitHub→내부 인입 | runner outbound 폴링 | webhook inbound 필요 (FW open) | outbound | SSH inbound 필요 (FW open) |
| secret 경계 | bastion 로컬 유지 | AWX vault | bastion 로컬 | GitHub secret 외부 보관 필요 |
| UI/감사 로그 | GitHub Actions UI | AWX UI | 없음 | GitHub Actions UI |
| 학습 비용 | 낮음 (현재 git 도구 재사용) | 높음 | 낮음 | 중간 |
| 운영 부담 | runner 1개 systemd | AWX 패치·DB 백업 | cron drift 위험 | SSH 키 외부 보관 |
| 사람 승인 게이트 | workflow `environment` | AWX survey | ✗ | workflow `environment` |

방안 B 대비 이점: 추가 호스트·DB 없음, 기존 GitHub 워크플로 연속성.
방안 C 대비 이점: 추적·승인·롤백이 GitHub Actions UI에 누적.
방안 D 대비 이점: bastion으로 SSH 인입 포트를 열 필요 없음 — runner는 outbound HTTPS 폴링만 사용. clouds.yaml·vault password를 GitHub 외부에 보관할 필요 없음.

### 현장 경로 비교 (F1 vs F2 vs F3)

| | F1 (채택, 본사 빌드+매체 운반) | F2 (VPN→본사 push) | F3 (현장 runner) |
|---|---|---|---|
| 고객망 신규 정책 요구 | 없음 | VPN/방화벽 허용 | GitHub outbound 허용 |
| 본사 통제 | 강 (번들·로그 모두 본사 경유) | 강 | 약 (현장 runner 신뢰 필요) |
| hotfix 적용 지연 | 매체 운반 + 인편 시간 | 분 단위 | 분 단위 |
| 운반 매체 분실 위험 | 있음 (서명·암호화로 완화 필요) | 없음 | 없음 |
| 적용 절차 학습 부담 | `install.sh` 1개 | 본사와 동일 | 본사와 동일 |

F1은 hotfix 지연이 단점이지만, 본 시스템은 2개월 수집·1회 보고서 산출 모델이라 hotfix 빈도가 낮을 것으로 추정. F2/F3 도입은 hotfix 빈도가 사업적 비용이 되는 시점에 후속 결정으로 미룬다.

핵심 우려와 대응:
- **secret 경계 이원화 (`terraform.tfvars`만 GitHub secret)** → 두 보관 방식의 트레이드오프를 의식적으로 수용:
  - *bastion 로컬 파일 (vault·ssh-key·clouds.yaml)*: secret이 GitHub에 절대 도달하지 않음(인입 표면 0), 폐쇄망 가정과 정합. 대신 runner 호스트마다 수동 배치 필요, GitHub UI에 감사 흔적 없음, 호스트 분실 시 단일 실패점.
  - *GitHub Environment secret (`ENGINE_TFVARS`)*: GitHub UI에서 편집·로테이션·Environment scope 게이트(required reviewer)·접근 감사 로그를 얻고 새 runner도 즉시 사용. 대신 평문 값이 GitHub 암호화 store에 보관되어 "모든 secret bastion 로컬" 원칙을 벗어나고, GitHub 측 침해 시 노출 면이 생김.
  - 적용 기준: **deep app secret(DB·MQ 자격 등)은 `vault.yml`(암호화 commit) + `~/.vault-pass`(로컬)** 경로 유지, **terraform provisioning 변수만 GitHub secret** 허용. tfvars에 deep secret을 넣지 않는 것을 전제로 함 — 위반 시 본 결정 재검토.
- **bastion이 빌드/배포/ops를 모두 짊어짐** → bastion 자체의 백업·복구 절차를 우선 정비 필요 (별도 작업). 본 ADR 범위 밖
- **runner 프로세스가 임의 코드 실행 경로** → repo write 권한자만 workflow 변경 가능. `workflow_dispatch` 승인자 분리. `pull_request` 트리거에서는 secret 차단
- **release 태그와 infra 태그 동기화** → workflow가 호출 시 `engine_version` input을 받아 in-memory로 ansible extra-vars 주입, 파일 commit 없음. 의도적으로 ansible variable 파일을 SoT로 두지 않음
- **번들 무결성/진위** → SHA256SUMS는 매체 무결성만 보장. 진위(악의적 교체 방지)는 후속 결정 — cosign 서명 + 현장 `install.sh`의 공개키 검증으로 보강 예정. 1차 채택 단계에서는 본사 인편·내부 매체 회전으로 통제
- **번들 크기** → docker image tar 합산 1~2 GB 예상. release asset 2 GB 제한 근접 시 본사 object storage(MinIO/S3)로 이전 — 후속 결정 신호
- **번들 ↔ 검증 환경 동등성** → 같은 commit·같은 image digest로 양쪽 빌드되도록 두 workflow가 동일 input·동일 checkout SHA를 공유. `manifest.json`에 digest 기록 → 검증 환경 health check 통과 후에만 번들을 "검증된 번들"로 승격 (별도 release label 또는 manifest field)

## 결과

- 본 repo에 다음 workflow 신설:
  - `.github/workflows/deploy-engine.yml` — 검증 환경 자동 적용
  - `.github/workflows/build-field-bundle.yml` — 현장 배포 번들 빌드
  - `.github/workflows/deploy-agent.yml` — agent 검증 환경 적용
- 본 repo에 다음 신규 자산:
  - `engine/compose/docker-compose.yml`, `.env.template`
  - `engine/ansible/playbook-field.yml` (ansible_connection=local)
  - `engine/ansible/inventory.localhost.yml`
  - `engine/scripts/build-bundle.sh`, `engine/scripts/install.sh`, `engine/scripts/healthcheck.sh`
- assessment-engine repo의 release workflow에 `repository_dispatch` step 추가 (별도 PR — assessment-engine repo)
- bastion에 runner systemd 등록 절차를 `docs/setup.md`에 추가
- `docs/operations/deploy-walkthrough.md`를 "수동 절차" → "GitHub Actions UI에서 트리거" 흐름으로 재작성 (검증 환경)
- 신규 `docs/operations/field-deploy.md` — 번들 수령·매체 운반·현장 `install.sh` 실행·회수까지의 절차
- `docs/operations/troubleshooting.md`에 runner 장애·트리거 미수신·terraform lock 충돌·번들 무결성 실패 케이스 추가
- terraform apply(검증)는 `environment: openstack-staging` + required reviewer 게이트로 보호
- ansible apply(검증)는 게이트 없이 자동 (idempotent 보장)
- 번들 빌드는 게이트 없이 release마다 자동 — "검증 통과 후 번들 승격"은 manifest field로 표시 (다운로드 차단 게이트는 후속 결정)

## 후속 결정 (재논의 신호)

- runner 1개로 동시 배포 충돌이 잦아지면 → runner 다중화 또는 별도 ops 호스트로 분리
- bastion 장애가 배포 차단이 되는 시점 → ops 호스트와 bastion 분리, runner는 ops 호스트로 이전
- 멀티 환경(staging/prod) 도입 → environment 분리, terraform workspace 도입과 함께 재논의
- **번들 진위 보호 강화 필요** (예: 외부 매체 분실·고객사 보안 감사 요구) → cosign 서명 + 현장 공개키 검증 도입. 신규 ADR 작성
- **번들 크기가 GitHub release asset 2 GB 제한 근접** → 본사 object storage(MinIO/S3) 이전. 번들 다운로드 매체·동선 재설계
- **현장 hotfix 빈도 증가** → "본사 빌드 → 매체 운반"의 지연이 사업적 비용이 되는 시점. 경로 F2(VPN) 재평가
- **현장에서 회수한 로그가 본사 관측 체계로 들어와야 하는 시점** → 번들에 텔레메트리 발신기 동봉 또는 회수 매체 전용 ingest 파이프라인. 별도 ADR
