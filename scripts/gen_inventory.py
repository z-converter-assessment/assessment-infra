#!/usr/bin/env python3
"""engine·agent terraform output에서 Ansible inventory 2개를 생성한다.

생성 파일:
  - engine/ansible/inventory.yml — db·mq·cache·api·worker·ai 그룹
  - agent/ansible/inventory.yml  — linux(debian/ubuntu/rhel) / windows + OS별 group

사용법:
    ./scripts/gen-inventory.sh
또는:
    python3 scripts/gen_inventory.py

선결 조건:
    engine/terraform과 agent/terraform 모두 `terraform apply` 완료 후 호출.
"""
import json
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
ENGINE_TF = REPO_ROOT / "engine" / "terraform"
AGENT_TF = REPO_ROOT / "agent" / "terraform"
ENGINE_INV = REPO_ROOT / "engine" / "ansible" / "inventory.yml"
AGENT_INV = REPO_ROOT / "agent" / "ansible" / "inventory.yml"


def tf_output(workdir: Path) -> dict:
    """terraform -chdir=<workdir> output -json 결과 반환."""
    try:
        result = subprocess.run(
            ["terraform", f"-chdir={workdir}", "output", "-json"],
            capture_output=True, text=True, check=True,
        )
    except FileNotFoundError:
        sys.exit("ERROR: terraform CLI를 찾을 수 없습니다. PATH 확인.")
    except subprocess.CalledProcessError as e:
        sys.exit(f"ERROR: {workdir} terraform output 실패 — {e.stderr.strip()}")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as e:
        sys.exit(f"ERROR: {workdir} terraform output JSON 파싱 실패 — {e}")


def gen_engine_inventory(engine_out: dict) -> str:
    required = [
        "api_vm_private_ip",
        "mq_vm_private_ip",
        "cache_vm_private_ip",
        "db_vm_private_ip",
        "worker_vm_private_ip",
        "ai_vm_private_ip",
    ]
    missing = [k for k in required if k not in engine_out]
    if missing:
        sys.exit(f"ERROR: engine terraform output 누락 — {missing}")

    def ip(key):
        return engine_out[key]["value"]

    return f"""\
# 자동 생성 파일 — `./scripts/gen-inventory.sh`이 매번 덮어쓰기
# 수동 편집 금지. group_vars/는 별도 commit 가능.

all:
  vars:
    ansible_user: debian
    ansible_ssh_private_key_file: ~/.ssh/engine-key.pem
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no"

  children:
    db:
      hosts:
        db-vm:
          ansible_host: {ip('db_vm_private_ip')}
    mq:
      hosts:
        mq-vm:
          ansible_host: {ip('mq_vm_private_ip')}
    cache:
      hosts:
        cache-vm:
          ansible_host: {ip('cache_vm_private_ip')}
    api:
      hosts:
        api-vm:
          ansible_host: {ip('api_vm_private_ip')}
    worker:
      hosts:
        worker-vm:
          ansible_host: {ip('worker_vm_private_ip')}
    ai:
      hosts:
        ai-vm:
          ansible_host: {ip('ai_vm_private_ip')}
"""


def gen_agent_inventory(agent_out: dict, engine_out: dict) -> str:
    for k in ("agent_vms", "agent_vms_by_family", "agent_vms_by_os"):
        if k not in agent_out:
            sys.exit(f"ERROR: agent terraform output 누락 — {k}")
    if "mq_vm_private_ip" not in engine_out:
        sys.exit("ERROR: engine terraform의 mq_vm_private_ip 필요 (agent → MQ 접속용)")

    agent_vms = agent_out["agent_vms"]["value"]
    by_family = agent_out["agent_vms_by_family"]["value"]
    by_os = agent_out["agent_vms_by_os"]["value"]
    engine_mq_host = engine_out["mq_vm_private_ip"]["value"]

    lines = [
        "# 자동 생성 파일 — `./scripts/gen-inventory.sh`이 매번 덮어쓰기",
        "# 수동 편집 금지. group_vars/는 별도 commit 가능.",
        "",
        "all:",
        "  vars:",
        "    ansible_ssh_private_key_file: ~/.ssh/engine-key.pem",
        '    ansible_ssh_common_args: "-o StrictHostKeyChecking=no"',
        f"    engine_mq_host: {engine_mq_host}",
        "    engine_mq_port: 5672",
        "",
        "  children:",
    ]

    # agent_workers — 모든 agent VM의 최상위 그룹 (deploy·health-check 타겟)
    has_linux = any(f in by_family for f in ("debian", "ubuntu", "rhel"))
    has_windows = "windows" in by_family
    lines.append("    agent_workers:")
    lines.append("      children:")
    if has_linux:
        lines.append("        linux:")
    if has_windows:
        lines.append("        windows:")
    lines.append("")

    # linux 부모 그룹 (children: 가용한 linux family만 포함)
    linux_families = [f for f in ("debian", "ubuntu", "rhel") if f in by_family]
    if linux_families:
        lines.append("    linux:")
        lines.append("      children:")
        for f in linux_families:
            lines.append(f"        {f}:")
        lines.append("")

    # family group — 호스트 전체 정의 (ansible_host, ansible_user 포함)
    for family, keys in by_family.items():
        lines.append(f"    {family}:")
        lines.append("      hosts:")
        for key in keys:
            vm = agent_vms[key]
            lines.append(f"        {vm['name']}:")
            lines.append(f"          ansible_host: {vm['ip']}")
            lines.append(f"          ansible_user: {vm['ssh_user']}")
        lines.append("")

    # OS-specific group — fine-grained targeting용. 호스트 이름만 (vars는 family에서 상속)
    for os_key, keys in by_os.items():
        lines.append(f"    {os_key}:")
        lines.append("      hosts:")
        for key in keys:
            vm = agent_vms[key]
            lines.append(f"        {vm['name']}:")
        lines.append("")

    return "\n".join(lines)


def main():
    engine_out = tf_output(ENGINE_TF)
    agent_out = tf_output(AGENT_TF)

    engine_inv = gen_engine_inventory(engine_out)
    agent_inv = gen_agent_inventory(agent_out, engine_out)

    ENGINE_INV.write_text(engine_inv)
    AGENT_INV.write_text(agent_inv)

    n_engine = 6  # API·MQ·Cache·DB·Worker·AI
    n_agent = agent_out.get("agent_total_count", {}).get("value", "?")
    print(f"OK  {ENGINE_INV.relative_to(REPO_ROOT)}  ({n_engine} hosts)")
    print(f"OK  {AGENT_INV.relative_to(REPO_ROOT)}   ({n_agent} hosts)")


if __name__ == "__main__":
    main()
