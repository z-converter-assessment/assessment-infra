# 인프라 셋업 절차

> 일회성 초기 구축 가이드. CLAUDE.md는 상시 컨텍스트, 본 문서는 셋업 시점에만 참조.

진행 순서: 각 Terraform 단계 끝에 `plan` → 결과 해석 → `apply` → state 확인.

## 0. 사전 작업 (Horizon 수동)

| 단계 | 작업 |
|---|---|
| 0-a | Neutron network 1개 생성 |
| 0-b | engine-subnet (`10.0.10.0/24`) + agent-subnet (`10.0.20.0/24`) 생성 |
| 0-c | Router 생성 → External Gateway 부착 → 두 subnet에 interface 추가 |
| 0-d | Bootstrap VM (Bastion) 생성 → engine-subnet 배치 → FIP 부여 (Debian 13, ZDM flavor) |
| 0-e | OpenStack keypair 등록 (이름: `engine-key`) — Terraform이 reference만 함 |

## 1. Terraform 단계 (bastion · Debian 13)

| 순서 | 파일 | 내용 |
|---|---|---|
| 1 | `versions.tf` + `providers.tf` | `terraform init` → 자원 0개 plan 검증 |
| 2 | `data.tf` | network·subnet data source 선언 (Horizon 자원 참조) |
| 3 | `security_groups.tf` | SG 정의 (engine·agent·ai 3종) |
| 4 | `instances.tf` | engine-vm + ai-vm + Port |
| 5 | `volumes.tf` | Cinder 볼륨 db 30 GB·mq 20 GB → **engine-vm에 attach** |
| 6 | `floating_ips.tf` | engine-vm에 FIP (API :8000) |
| 7 | `outputs.tf` | IP들 (Ansible inventory 입력) |
| 8 | `agent/terraform/instances.tf` | Agent VM N대 + cloud-init user-data |

## 2. Ansible 단계 (bastion)

> engine은 단일 VM의 docker compose (ADR-0010). 컴포넌트별 playbook은 `playbook-engine.yml` 1개로 통합.

| 순서 | playbook | 작업 |
|---|---|---|
| 9 | `inventory.yml` | `python3 scripts/gen_inventory.py --scope engine` (Terraform output 기반) |
| 10 | `playbook-engine.yml` | docker-ce 설치 + Cinder mkfs/mount(`/mnt/pgdata`·`/mnt/mqdata`) + release `docker-compose.yml` 다운로드 + `.env` 렌더 + `docker compose pull` → `up -d` (migrate→api·consumer·pg·mq·redis) |
| 11 | `playbook-ai.yml` | Ollama 설치 + 모델 pull(`gemma2:2b`) + diagnostic-worker |
| 12 | `agent/ansible/site.yml` | agent 바이너리·env·service + 더미 서비스 + 부하 + health-check (Linux·Windows) |

> 위 9~11은 release 발행 시 self-hosted runner가 `repository_dispatch`로 자동 실행 (ADR-0011). 수동 시에만 직접 호출.

## 사전 점검

- `clouds.yaml` (mode 0600): `~/.config/openstack/`
- `engine-key.pem` (mode 0400): `~/.ssh/`
- `.vault-pass` (mode 0400): `~/`
- engine 이미지: GHCR pull (runner outbound) 또는 현장은 `docker save` tar 동봉 — wheel 사전 복사 불필요
- `agent/ansible/files/binaries/`에 agent 바이너리 사전 복사
