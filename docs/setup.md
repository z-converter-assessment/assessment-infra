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
| 3 | `security_groups.tf` | SG 정의 (API·MQ·Cache·DB·Worker·Agent·AI) |
| 4 | `instances.tf` | 엔진 VM + Port (API·MQ·Cache·DB·Worker·AI) |
| 5 | `volumes.tf` | Cinder 볼륨 (MQ·DB 데이터용) + attach |
| 6 | `floating_ips.tf` | API VM에 FIP |
| 7 | `outputs.tf` | IP들 (Ansible inventory 입력) |
| 8 | `agent/terraform/instances.tf` | Agent VM N대 + cloud-init user-data |

## 2. Ansible 단계 (bastion)

| 순서 | playbook | 작업 |
|---|---|---|
| 9 | `inventory.yml` | `scripts/gen-inventory.sh`로 생성 (Terraform output 기반) |
| 10 | `playbook-db.yml` | Cinder 마운트 + PGDG repo + postgresql apt + 데이터 디렉토리 이전 + systemd |
| 11 | `playbook-mq.yml` | Cinder 마운트 + rabbitmq-server apt + mnesia 디렉토리 이전 + systemd |
| 12 | `playbook-cache.yml` | redis-server apt + systemd |
| 13 | `playbook-api.yml` | wheel install + alembic upgrade head (`app_run_alembic: true`) + systemd |
| 14 | `playbook-worker.yml` | wheel install + systemd (alembic 안 함) |
| 15 | `playbook-ai.yml` | Ollama 설치 + 모델 pull + systemd (TBD) |
| 16 | `playbook-agent.yml` | agent 바이너리 배포 (Linux only — Windows playbook 미구현) |
| 17 | `playbook-local-services.yml` | Agent VM 로컬 PostgreSQL·Redis 설치 (TBD) |

## 사전 점검

- `clouds.yaml` (mode 0600): `~/.config/openstack/`
- `engine-key.pem` (mode 0400): `~/.ssh/`
- `.vault-pass` (mode 0400): `~/`
- `engine/ansible/files/wheels/`에 wheel 사전 복사
- `agent/ansible/files/binaries/`에 agent 바이너리 사전 복사
