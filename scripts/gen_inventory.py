#!/usr/bin/env python3
"""terraform output -json을 stdin으로 받아 ansible/inventory.yml을 stdout으로 출력한다.

사용법:
    terraform -chdir=terraform output -json | python3 scripts/gen_inventory.py > ansible/inventory.yml
또는:
    ./scripts/gen-inventory.sh
"""
import json
import sys


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"ERROR: terraform output 파싱 실패 — {e}", file=sys.stderr)
        sys.exit(1)

    required = [
        "api_vm_private_ip",
        "mq_vm_private_ip",
        "cache_vm_private_ip",
        "db_vm_private_ip",
        "worker_vm_private_ip",
    ]
    missing = [k for k in required if k not in data]
    if missing:
        print(f"ERROR: terraform output에 누락된 키: {missing}", file=sys.stderr)
        sys.exit(1)

    def ip(key):
        return data[key]["value"]

    print(f"""\
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
""")


if __name__ == "__main__":
    main()
