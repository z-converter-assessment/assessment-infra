# Troubleshooting — CD 자동화 (engine v0.5.0 배포)

`deploy-engine.yml`(repository_dispatch `engine-release`) 파이프라인을 v0.5.0으로 처음 끝까지 통과시키며 발생한 오류·판단·조치·결과 기록. 같은 증상 재발 시 참고.

> 일반 배포 문제는 `troubleshooting.md`. 본 문서는 **CD 파이프라인(GitHub Actions self-hosted runner)** 한정.
> 배포 모델·흐름: `../architecture/runtime.md`, secret 경계: `../adr/0011-release-automation-self-hosted-runner.md`.

---

## 0. 환경 전제 — 거의 모든 오류의 공통 뿌리

deploy-engine은 **bastion = self-hosted runner**에서 돈다. 각 run은 `actions/checkout@v4`(기본 `clean: true` → `git clean -ffdx`)로 워크스페이스를 **매번 비운다**. 즉:

- **git에 없는 파일(gitignore·런타임 생성물)은 run마다 사라진다.**
- 워크스페이스 안에 둔 상태/산출물은 보존되지 않는다.

아래 5개 오류 중 3개(#1·#3·#4)가 이 한 가지 성질에서 파생됐다. 비-git 산출물은 **워크스페이스 밖**에 두고 확보하는 것이 원칙.

## 진행 요약 (run 연대기)

| run | 결과 | 멈춘 지점 | 원인 |
|---|---|---|---|
| 27207959748 | 부분 | `ansible ai` | ollama group 오타 (#2) |
| 27208665299 | 실패 | `terraform apply` | state 미보존 → 자원 중복 → 쿼터 초과 (#3) |
| 27210893629 | 부분 | `ansible ai` | ollama 모델 tarball 부재 (#4) |
| 27212447404 | 실패 | `ansible engine` | 볼륨 포맷 비멱등 (#5) |
| **27213791691** | **성공** | — | 전 단계 green |

> `ansible engine`(compose pull→migrate→up→API health 200)은 run 27207959748에서 이미 통과 — 엔진 배포 로직(contract 정합·v0.5.0·PGDATA_HOST 소유권)은 그 시점에 실 VM에서 검증됨. 이후 실패들은 모두 **CD 인프라(상태·산출물·멱등성)** 문제.

---

## #1. CI 워크스페이스에 `vault.yml`이 없어 ansible 실패 (트리거 전 선제 발견)

**증상**
첫 트리거 전 점검에서, runner 워크스페이스에 engine `vault.yml` 실파일이 없고 agent vault.yml(symlink) 대상이 dangling. 그대로 돌리면 ansible이 `vault_*` 미정의로 `.env` 렌더 단계에서 실패할 상태.

**판단**
- 문서(ADR-0011·CLAUDE.md)는 "vault.yml은 **암호화 commit**, `~/.vault-pass`만 로컬"을 전제하는데, 실제 `.gitignore`가 engine vault.yml을 추적 제외(설계 위반).
- checkout(clean)이 gitignored vault.yml을 워크스페이스에서 제거 → CI에 vault 부재. → **`.gitignore`가 결함**, 문서 설계가 정답.
- git history 영구성 고려: 커밋 전 약한 비밀(`vault_db_password` 등 len=4, `1234` 추정)을 강한 random으로 회전해야 안전.

**조치**
- `.gitignore`에서 engine vault.yml 제외 해제 → AES256 암호화본 commit.
- `vault_db_password`·`vault_mq_password`·`vault_app_secret_key`를 `openssl rand`로 회전(pgadmin은 이미 강함). 값은 노출 없이 decrypt→치환→encrypt.
- 커밋: `5ace384 chore(engine): vault.yml 암호화본 commit 전환 + 약한 비밀 회전`

**결과**
이후 모든 run에서 checkout이 vault.yml을 확보 → `ansible engine`의 `.env` 렌더·DB/MQ 자격 주입 정상. run 27207959748에서 엔진 API health 200 통과로 입증.

---

## #2. `ansible ai` 실패 — `Group ollama/ does not exist`

**증상**
```
TASK [ollama : create ollama user]
fatal: [ai-vm]: FAILED! => {"msg": "Group ollama/ does not exist"}
```

**판단**
그룹명이 `ollama/`(끝 슬래시)로 전달됨. `roles/ollama/tasks/main.yml`의 user 태스크 `group: ollama/`에 **오타 트레일링 슬래시**. 환경·상태 문제 아닌 단순 코드 결함.

**조치**
`group: ollama/` → `group: ollama`. 커밋 `5d61622 fix(ollama): ...`.

**결과**
다음 run에서 ollama user 생성·install·서비스 기동까지 통과(다음 막힌 지점은 #4).

---

## #3. `terraform apply` 실패 — SG rule 쿼터 초과 (state 미보존)

**증상**
```
Error creating openstack_networking_secgroup_v2: got 409
NeutronError: OverQuota — Quota exceeded for resources: ['security_group_rule']
```
1차 run에선 통과했던 apply가 2차에서 실패. 조사 결과 OpenStack에 `engine-vm`·`ai-vm` **각 5대**, SG 각 5벌, SG rule 99개 적체.

**판단**
- `versions.tf`에 backend 블록 없음 → **로컬 state**(`engine/terraform/terraform.tfstate`, gitignore).
- `git clean -ffdxn`이 워크스페이스의 tfstate를 삭제 대상으로 표시 확인 → **매 run state가 사라짐**.
- 따라서 매 run terraform이 빈 state에서 모든 자원을 **새로** 생성 → 기존 자원과 누적 → SG rule 쿼터 소진. (CLAUDE.md "보류된 결정: state remote backend"가 현실화된 것.)

**조치**
1. `versions.tf`에 워크스페이스 **밖** 고정경로 local backend 추가:
   `backend "local" { path = "/home/debian/.tfstate/engine/terraform.tfstate" }`
   → clean이 워크스페이스만 비우므로 state 보존. 커밋 `9d0e8cd fix(terraform): ...`.
2. orphan 자원 정리(openstack CLI, bastion·default·edu·Horizon 자원 보존): 서버 10·port 10·FIP 6·SG 15 삭제. SG rule 99→9로 쿼터 회복.

**결과**
이후 run에서 `terraform apply`가 **skipped**(plan no-op) → 자원 재생성 없이 1세트만 유지(멱등). state 파일이 `/home/debian/.tfstate/engine/`에 보존됨 확인.

> 단일 runner 전제의 임시 조치. 멀티 runner/사용자 단계 진입 시 Swift 원격 backend로 이전(별도 ADR).

---

## #4. `ansible ai` 실패 — `ollama-models.tar.gz` 부재

**증상**
```
TASK [ollama : stage ollama models tarball]
Could not find or access 'ollama/ollama-models.tar.gz'
```
ollama 설치·systemd 기동까지는 성공, 모델 tarball staging에서 실패.

**판단**
- `ollama-models.tar.gz`(gemma2:2b ~1.6GB)는 `.gitignore` 대상(대용량 바이너리, git 부적합) → checkout에 없음.
- 운영자 사전 준비(`ollama pull` 후 tar) 산출물인데 미스테이징. 게다가 #0 성질상 워크스페이스에 둬도 clean이 지움 → **워크스페이스 밖 + 복사 단계** 필요(vault·tfstate와 동형 문제).
- 코드 버그 아닌 **운영 산출물 누락 + 영속화 메커니즘 부재**.

**조치**
1. bastion에서 ollama 설치 → `ollama pull gemma2:2b` → `tar czf /home/debian/ollama-artifacts/ollama-models.tar.gz -C /usr/share/ollama .ollama`
   (추출 dest=`/usr/share/ollama`라 tar 루트가 `.ollama/`여야 함 — role unarchive와 정합).
2. `deploy-engine.yml`에 `ansible ai` 직전 staging step 추가: 영속 경로 → `engine/ansible/files/ollama/`로 cp. 커밋 `1142e78 fix(workflow): ...`.

**결과**
다음 run에서 staging step ✓ → 모델 추출 → ai-vm ollama에 gemma2:2b 적재 성공.

---

## #5. `ansible engine` 실패 — `mkfs.xfs: /dev/vdb contains a mounted filesystem`

**증상**
```
TASK [engine_compose : format db volume (xfs, skip if already formatted)]
mkfs.xfs: /dev/vdb contains a mounted filesystem
```
#3 수정으로 동일 VM을 **재사용**하게 되자 발생(이전엔 매 run VM을 새로 만들어 가려짐).

**판단**
format 태스크의 `creates: {{ db_mount_path }}/.xfs_formatted` 센티넬을 **role이 만든 적이 없음** → skip 가드가 무력 → 매 run `mkfs.xfs` 재실행. 새 볼륨(1회차)은 성공하나, 이미 포맷·마운트된 볼륨(재배포)엔 mkfs가 거부. **state 보존으로 재실행이 가능해지며 드러난 멱등성 결함.**

**조치**
`blkid`로 파일시스템 유무를 검사해 **미포맷 볼륨만** 포맷(db·mq 공통 loop). `-f` 강제포맷은 데이터 파괴라 금지. 커밋 `b262e4d fix(engine): Cinder 볼륨 포맷을 blkid 기반 멱등 처리`.

**결과**
재배포 run에서 `format cinder volumes` 태스크가 기존 xfs 감지 → 포맷 skip → compose 재기동 → API health 200. 최종 run 27213791691 전 단계 green.

---

## 교차 교훈

1. **checkout(clean)이 비-git 산출물을 지운다** → vault.yml(암호화 commit)·tfstate(외부 경로 backend)·ollama 모델(bastion 영속 경로 + cp step)을 워크스페이스 밖에 두고 확보. (#1·#3·#4)
2. **재실행 가능성(멱등성)이 잠재 버그를 드러낸다** → state 미보존 시절엔 매번 새 자원이라 비멱등 코드(#5 mkfs 등)가 가려졌다. 영속 backend 도입 후 동일 VM 재사용이 정상 경로가 되며 멱등성을 강제 검증하게 됨.
3. **문서와 `.gitignore`/코드 불일치는 결함 신호** → ADR-0011/CLAUDE.md vs `.gitignore`(#1)처럼, 설계 문서가 정답일 때가 많다.

## 최종 검증 (run 27213791691)

`terraform plan`(no-op·apply skip) → `ansible engine`(format skip→compose→health 200) → `stage ollama model`→ `ansible ai`(gemma2:2b 적재) **전 단계 success**. OpenStack에 engine-vm·ai-vm·bastion-new 각 1대만 ACTIVE.

## 운영 영속 자산 (git 밖 · bastion 로컬 — 재구성 시 함께 복구)

| 자산 | 경로 | 용도 |
|---|---|---|
| Terraform state | `/home/debian/.tfstate/engine/terraform.tfstate` | CD 멱등성 (소실 시 자원 중복 재생성) |
| Ollama 모델 tarball | `/home/debian/ollama-artifacts/ollama-models.tar.gz` | CD가 매 run ai-vm에 staging (모델 교체 시 재생성: `ollama pull` 후 `tar -C /usr/share/ollama .ollama`) |
| Vault password | `~/.vault-pass` | vault.yml 복호화 |
