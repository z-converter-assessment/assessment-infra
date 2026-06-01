# ADR-0007: Agent Windows 배포를 바이너리 파일 주입 방식으로 결정

- 상태: Accepted
- 날짜: 2026-05-27

## 컨텍스트

Agent VM에는 Linux 계열 외에 Windows Server 2022 VM이 포함된다.
Windows에서 Ansible 제어는 WinRM 프로토콜을 사용하며, 배포 대상은 Go로 빌드된 `assessment-agent.exe` 바이너리다.

배포 방식으로 두 가지를 검토했다.

1. **자동 다운로드**: 배포 시 VM 내부에서 GitHub Releases를 직접 pull
2. **바이너리 파일 주입**: bastion에서 수동으로 다운로드한 바이너리를 Ansible로 복사

## 결정

**Option 2 — 바이너리 파일 주입** 채택.

- GitHub Releases에서 `assessment-agent.exe`를 bastion에서 수동 다운로드
- `agent/ansible/files/binaries/assessment-agent.exe`에 배치
- Ansible `win_copy` 모듈로 VM 내부에 주입 후 서비스 등록

## 트레이드오프

| | 자동 다운로드 | 바이너리 주입 (채택) |
|---|---|---|
| 폐쇄망 대응 | 불가 (VM에서 GitHub 접근 불가) | 가능 (bastion 경유) |
| 버전 관리 | 자동 | 수동 (운영자가 명시적 배치) |
| 일관성 | Linux 방식과 다름 | Linux 바이너리 배포와 동일 패턴 |

Linux agent(`assessment-agent-linux`)도 같은 파일 주입 방식을 사용하므로 일관성이 유지된다.
폐쇄망 환경에서 VM이 외부 인터넷에 직접 접근할 수 없으므로 자동 다운로드는 불가능하다.
