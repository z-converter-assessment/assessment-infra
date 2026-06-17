# Agent 환경 구성 — 요구사항

> 작성일: 2026-06-17 · 전제: engine v0.7.0 배포 완료(API·MQ·pgAdmin 가동)
> 목적: assessment-agent 플릿을 띄우고 engine과 연결(MQ 발행 + ZDM install)하기 위한 구성 요구사항 정의.
> 관련: [`agent-test-environment.md`](agent-test-environment.md)(플릿 구성·주입 경로) · [`agent-binary-image-coverage.md`](agent-binary-image-coverage.md)(OS별 접근·배포 로직) · [`deploy-walkthrough.md`](deploy-walkthrough.md)

## 0. 목표 (Goal)

> **이번 구성 범위 = `결정필요`** (예: 전체 플릿 재구성 / 특정 OS군만 / 커버리지 테스트용 N대)

## 1. 사전 조건 (engine 측 — 구성 시작 전 확인)

- [ ] engine-vm 가동 + API(`:8000`) health OK
- [ ] RabbitMQ(`:5672` AMQP) 도달 가능 — agent는 이 broker로 inventory·task.result 발행
- [ ] engine `server_inventory` 테이블 조회 가능(검증용)
- [ ] **MQ 자격증명**: `vault.yml`의 `vault_mq_user`/`vault_mq_password`(현재 `assessment`) — engine·agent 공용(agent vault는 engine vault symlink)
- [ ] engine MQ 호스트 IP — `scripts/gen-inventory.sh`가 engine-vm 사설 IP를 자동 주입(`engine_mq_host`). 엔진 재배포로 IP 바뀌었으면 inventory 재생성 필요

## 2. 대상 플릿 정의

- **OS 매트릭스·대수**: `agent/terraform/variables.tf`의 `agent_os_map`(Linux)·`agent_legacy_os_map`(centos6·ubuntu18)·`windows.tf`(Windows)에서 관리.
  - 각 OS: `image_name` · `family` · `ssh_user` · `count`
- 이번 구성 대상 OS·대수: `결정필요`
- 참고(접근 난이도 — 본 세션 실측, `agent-binary-image-coverage.md`):
  - **표준 배포 가능**(cloud-init 정상 + python≥3.7): debian10~13 · ubuntu20.04+ · rocky9 · alma9 · centos9stream · oracle9 · amazon2023 · tencent4(py3.11)
  - **cloud-init 부재 → rescue 키주입 필요**: redhat 전 버전 · suse12/15 · tencent(접근만)
  - **python<3.7 → 정적 바이너리 수동 배포**: el7/el8 · rocky8 · ubuntu18 · suse12/15
  - **부팅/이미지 결함**: oracle7_uefi · suse12_uefi · centos8stream_uefi_lvm

## 3. 프로비저닝 (Terraform — `agent/terraform/`)

- [ ] 내부 네트워크/서브넷: ADR-0013 — agent 테스트 전용 internal-only는 `agent/terraform/network/`에서 생성 허용. primary `agent-subnet`·라우터·keypair는 Horizon 수동
- [ ] keypair: `결정필요`(현재 fleet은 `new-bastion-key` 사용 — engine-key.pem 매칭)
- [ ] SG: `agent-sg`(engine MQ·bastion SSH·subnet 내부 허용)
- [ ] flavor: OS 디스크 크기에 맞춰 선택(큰 이미지=oracle/suse15/amazon은 ≥디스크 flavor)
- [ ] `terraform apply` 후 인스턴스 IP·status 확인

## 4. 접근 전제 (cloud-init 유무에 따른 분기)

> 표준 파이프라인은 cloud-init이 keypair를 주입한다는 전제. 부재 OS는 우회 필요.

- **cloud-init 정상 OS**: Terraform `key_pair` 주입 → 기본 유저(ubuntu/debian/rocky/almalinux/cloud-user)로 SSH 표준 접근
- **cloud-init 부재 OS(redhat·suse·tencent)**: rescue 모드로 root 키 수동주입 필요
  - RHEL계열(redhat·tencent): rocky9 rescue + LVM 마운트 + SELinux permissive
  - SLES(suse): **debian13 rescue**(btrfs 지원) + `/@/root` 서브볼륨 직접 마운트
  - redhat7: 추가로 `ifcfg-eth0 ONBOOT=yes` 수정(NIC 미기동)
  - > 운영 배포 시엔 **골든 이미지에 cloud-init/키/ONBOOT 선반영**이 정공법. 위 rescue는 테스트 우회책.
- [ ] `~/.ssh/config` ProxyJump(bastion) 또는 동일 대역 직접 접근 경로 확인
- [ ] VM 재생성 시 known_hosts 충돌 → `ssh-keygen -R`

## 5. 배포 (Ansible — `agent/ansible/`)

- [ ] inventory 생성: `./scripts/gen-inventory.sh` (또는 테스트용 별도 inventory)
- [ ] vault 복호화: `~/.vault-pass`(0400)
- [ ] 배포: `ansible-playbook site.yml -i inventory.yml --vault-password-file ~/.vault-pass`
  - `deploy.yml`(common·agent_binary·agent_env·agent_service) → `services.yml` → `noise.yml` → `health-check.yml`
- [ ] **python<3.7 OS**(el7/el8·suse·ubuntu18): ansible-core 모듈 불가 → 정적 바이너리 수동 배포(rh9 산출물 복제 패턴)
- [ ] 바이너리: `agent_version`(현재 `1.2.0`), `agent_binary_filename`(`assessment-agent-linux-x86_64`) — 폐쇄망이라 bastion이 받아 `files/`에 사전 복사
- [ ] Windows: GitHub Releases→bastion 수동 다운로드→`win_copy` 주입(ADR-0007)

## 6. 주입 환경변수 / MQ 계약 (`group_vars/all/vars.yml` 기준)

- MQ: `engine_mq_host`(inventory 자동) · `engine_mq_port=5672` · `rabbitmq_tls_enabled=false`(engine plain 포트)
- 자격: `vault_mq_user`/`vault_mq_password`(=assessment)
- exchange/routing: `mq_exchange=assessment` · inventory/metrics/error 키 · task 군(`assessment.tasks`·`agent.tasks`·`task.result`)
- **worker download allowlist**: `worker_download_allowed_hosts`(ZDM host CSV — Linux `192.168.3.92`, Windows `192.168.3.94`). 비면 모든 download reject(ADR-0016, deploy 시점 고정)
- 루프/drain: `agent_interval_sec=60` · `agent_inventory_refresh_sec=300` · drain 예산(grace/term/publish)
- 서비스 설치: `agent_services`(service_db/cache/mq/web/app/container/monitor) — OS군별 override. 이번 구성값: `결정필요`

## 7. 검증 기준 (합격)

| 항목 | 합격 기준 | 확인 방법 |
|---|---|---|
| 바이너리 기동 | `assessment-agent` systemd active, `published inventory` 로그 | `journalctl -u assessment-agent` |
| MQ 발행 | engine `server_inventory`에 해당 인스턴스 신규 인식(machine_id·ip·last_seen) | engine postgres 조회 |
| ZDM install | `POST /api/tasks/install`(zdm_ip=192.168.3.92, zdm_user=메일형식) → task status `success` | `GET /api/tasks/{id}` |
| (RHEL계열) SELinux | install.sh 차단 없도록 permissive(ADR-0012) | `getenforce` |

## 8. 노이즈/부하 구성 (선택)

- `noise.yml`·`noise_*` role — 부하/장애 시뮬레이션. 적용 여부·강도: `결정필요`

## 9. 결정 필요 항목 (정리)

- [ ] 구성 범위(OS·대수) — §0·§2
- [ ] keypair — §3
- [ ] `agent_services` OS군별 구성 — §6
- [ ] noise 적용 여부 — §8
- [ ] cloud-init 부재 OS 포함 여부 / 골든 이미지 선반영 vs rescue 우회 — §4
