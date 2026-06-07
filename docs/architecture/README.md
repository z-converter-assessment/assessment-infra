# 아키텍처 문서

본 디렉토리는 인프라 설계의 **단일 진실**. 운영 절차는 `docs/operations/`, 의사결정 로그는 `docs/adr/`.

## 문서별 역할

| 파일 | 답하는 질문 |
|---|---|
| [overview.md](overview.md) | 무엇을 만드는가? 외부 의존은? |
| [topology.md](topology.md) | 어디에 어떻게 배치되어 있는가? (네트워크·VM·SG) |
| [runtime.md](runtime.md) | 실행 시 어떻게 흐르는가? (메시지·데이터·배포) |
| [components.md](components.md) | 각 VM의 책임 경계와 인터페이스는? |

## 다이어그램

- `diagrams/topology.svg` — 전체 토폴로지 (시각화 export)
- Mermaid 소스는 각 .md 안에 inline (GitHub 자동 렌더)

## 관련 문서

| 위치 | 답하는 질문 |
|---|---|
| `docs/adr/` | 왜 이렇게 결정했는가 (시점 로그) |
| `docs/operations/` | 어떻게 운영·작업하는가 (env·troubleshooting·release) |
| `docs/setup.md` | 초기 구축 단계별 가이드 |
| `.claude/CLAUDE.md` | 상시 컨텍스트 — 본 디렉토리 요약·링크만 |

## 변경 원칙

- **같은 사실은 한 곳에만**. 다른 문서는 링크로 참조
- **ADR과 충돌 시 본 디렉토리 우선** (ADR은 시점 로그, architecture는 현재 스냅샷)
- **코드로 알 수 있는 내용은 쓰지 않음** — role tasks·SG rule 상세는 코드 참조. 책임·경계만 기술
- **갱신 시점**: Terraform/Ansible 코드와 함께 같은 PR에서 갱신
