# Ansible inventory 생성에 필요한 모든 정보 — IP·family·ssh_user 매핑.
# gen-inventory.sh가 본 output을 읽어 inventory.yml 작성.

output "agent_vms" {
  description = "Agent VM 전체 정보 (key: VM key, value: {ip, family, ssh_user, name})"
  value = {
    for k, vm in local.agent_vms :
    k => {
      name     = "agent-${k}"
      ip       = openstack_networking_port_v2.agent_port[k].all_fixed_ips[0]
      family   = vm.family
      ssh_user = vm.ssh_user
      os_key   = vm.os_key
    }
  }
}

output "agent_vms_by_family" {
  description = "family별 VM key 목록 — inventory group 구성용"
  value = {
    for family in distinct([for vm in local.agent_vms : vm.family]) :
    family => [for k, vm in local.agent_vms : k if vm.family == family]
  }
}

output "agent_vms_by_os" {
  description = "OS별 VM key 목록 — inventory group 구성용"
  value = {
    for os_key in distinct([for vm in local.agent_vms : vm.os_key]) :
    os_key => [for k, vm in local.agent_vms : k if vm.os_key == os_key]
  }
}

output "agent_total_count" {
  description = "전체 Agent VM 개수"
  value       = length(local.agent_vms)
}
