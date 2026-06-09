# Ansible inventory 생성에 필요한 모든 정보 — IP·family·ssh_user 매핑.
# gen_inventory.py가 본 output을 읽어 inventory.yml 작성.
# 표준 agent VM + 레거시 Linux + Windows를 한 묶음으로 노출(키=inventory OS group 이름).

locals {
  # IP를 뺀 메타(family·os_key) 통합 맵 — group 구성용.
  all_vms_meta = merge(
    { for k, vm in local.agent_vms : k => { family = vm.family, os_key = vm.os_key } },
    { for k, vm in local.agent_legacy_vms : k => { family = vm.family, os_key = vm.os_key } },
    { for k, vm in local.windows_vms : k => { family = "windows", os_key = vm.os_key } },
  )
}

output "agent_vms" {
  description = "전체 agent VM (표준+레거시+windows). key: VM key, value: {name, ip, family, ssh_user, os_key}"
  value = merge(
    {
      for k, vm in local.agent_vms : k => {
        name     = "agent-${k}"
        ip       = openstack_networking_port_v2.agent_port[k].all_fixed_ips[0]
        family   = vm.family
        ssh_user = vm.ssh_user
        os_key   = vm.os_key
      }
    },
    {
      for k, vm in local.agent_legacy_vms : k => {
        name     = "agent-${k}"
        ip       = openstack_networking_port_v2.legacy_port[k].all_fixed_ips[0]
        family   = vm.family
        ssh_user = vm.ssh_user
        os_key   = vm.os_key
      }
    },
    {
      for k, vm in local.windows_vms : k => {
        name     = "agent-${k}"
        ip       = openstack_networking_port_v2.win_port[k].all_fixed_ips[0]
        family   = "windows"
        ssh_user = "Administrator"
        os_key   = vm.os_key
      }
    },
  )
}

output "agent_vms_by_family" {
  description = "family별 VM key 목록 — inventory group 구성용"
  value = {
    for family in distinct([for vm in local.all_vms_meta : vm.family]) :
    family => [for k, vm in local.all_vms_meta : k if vm.family == family]
  }
}

output "agent_vms_by_os" {
  description = "OS별 VM key 목록 — inventory group 구성용 (키=group_vars 파일명과 정렬)"
  value = {
    for os_key in distinct([for vm in local.all_vms_meta : vm.os_key]) :
    os_key => [for k, vm in local.all_vms_meta : k if vm.os_key == os_key]
  }
}

output "agent_total_count" {
  description = "전체 agent VM 개수 (표준+레거시+windows)"
  value       = length(local.all_vms_meta)
}

output "agent_extra_nics" {
  description = "표준 agent별 secondary NIC IP (agent_extra_networks). 비면 {}"
  value = {
    for vmk, vm in local.agent_vms :
    vmk => {
      for nick, net in var.agent_extra_networks :
      nick => openstack_networking_port_v2.agent_extra_port["${vmk}__${nick}"].all_fixed_ips[0]
    }
  }
}

output "agent_legacy_nics" {
  description = "레거시 VM의 agent-legacy NIC IP (정보용). 비활성/없으면 {}"
  value = merge(
    { for k, p in openstack_networking_port_v2.legacy_extra_port : k => p.all_fixed_ips[0] },
    { for k, p in openstack_networking_port_v2.win_legacy_port : k => p.all_fixed_ips[0] },
  )
}
