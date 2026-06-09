# OS별 N대씩 생성. agent_os_map을 flatten해서 단일 VM 리스트로 변환.
#
# VM key 형식: "<os_key>-<index>"  (예: "debian13-1", "ubuntu2404-3")
# VM name 형식: "agent-<os_key>-<index>"

locals {
  agent_vms = merge([
    for os_key, os in var.agent_os_map : {
      for i in range(os.count) :
      "${os_key}-${i + 1}" => {
        os_key     = os_key
        family     = os.family
        ssh_user   = os.ssh_user
        image_name = os.image_name
      }
    }
  ]...)

  # VM × 추가 네트워크 조합 — 멀티 NIC secondary 포트 생성용.
  # agent_extra_networks가 {}이면 빈 맵 → secondary 포트 0개(기존 단일 NIC 동작).
  agent_extra_ports = merge([
    for vmk, vm in local.agent_vms : {
      for nick, net in var.agent_extra_networks :
      "${vmk}__${nick}" => {
        vm_key = vmk
        nic    = nick
      }
    }
  ]...)
}

# ── Ports ─────────────────────────────────────────────────────────

# primary NIC(eth0) — bastion SSH·MQ 경로. inventory IP는 이 포트에서 가져온다.
resource "openstack_networking_port_v2" "agent_port" {
  for_each           = local.agent_vms
  name               = "agent-${each.key}-port"
  network_id         = data.openstack_networking_network_v2.main.id
  security_group_ids = [data.openstack_networking_secgroup_v2.agent_sg.id]

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.agent.id
  }
}

# secondary NIC들 — 멀티 NIC(패턴 A). SG는 port 단위라 agent_sg 재사용.
resource "openstack_networking_port_v2" "agent_extra_port" {
  for_each           = local.agent_extra_ports
  name               = "agent-${each.value.vm_key}-${each.value.nic}-port"
  network_id         = data.openstack_networking_network_v2.extra[each.value.nic].id
  security_group_ids = [data.openstack_networking_secgroup_v2.agent_sg.id]

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.extra[each.value.nic].id
  }
}

# ── Instances ─────────────────────────────────────────────────────

resource "openstack_compute_instance_v2" "agent_vm" {
  for_each    = local.agent_vms
  name        = "agent-${each.key}"
  image_id    = data.openstack_images_image_v2.agent_image[each.value.os_key].id
  flavor_name = var.flavor_agent
  key_pair    = var.keypair_name

  # primary NIC 먼저 → eth0(default route·bastion 접속). 이후 secondary NIC들 부착.
  network {
    port = openstack_networking_port_v2.agent_port[each.key].id
  }

  dynamic "network" {
    for_each = { for k, p in local.agent_extra_ports : k => p if p.vm_key == each.key }
    content {
      port = openstack_networking_port_v2.agent_extra_port[network.key].id
    }
  }

  # machine-id 재생성 (snapshot 복제 대비)
  user_data = <<-EOF
    #cloud-config
    runcmd:
      - systemd-machine-id-setup --commit
  EOF
}

# ── 레거시 Linux (ADR-0013) ───────────────────────────────────────
# centos6·ubuntu18 — primary NIC=agent-subnet(연결성), secondary NIC=agent-legacy(그룹핑).
# 지원 검증 + agent 개발자 컴파일/실행 환경 제공 목적. centos6는 systemd 부재로 agent_service(systemd)
# 단계에서 실패가 예상됨(지원 확인 대상).
locals {
  agent_legacy_vms = var.agent_legacy_enabled ? merge([
    for os_key, os in var.agent_legacy_os_map : {
      for i in range(os.count) :
      "${os_key}-${i + 1}" => {
        os_key   = os_key
        family   = os.family
        ssh_user = os.ssh_user
      }
    }
  ]...) : {}
}

# primary NIC — agent-subnet (engine MQ·outbound·bastion)
resource "openstack_networking_port_v2" "legacy_port" {
  for_each           = local.agent_legacy_vms
  name               = "agent-${each.key}-port"
  network_id         = data.openstack_networking_network_v2.main.id
  security_group_ids = [data.openstack_networking_secgroup_v2.agent_sg.id]

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.agent.id
  }
}

# secondary NIC — agent-legacy (그룹핑)
resource "openstack_networking_port_v2" "legacy_extra_port" {
  for_each           = local.agent_legacy_vms
  name               = "agent-${each.key}-legacy-port"
  network_id         = data.openstack_networking_network_v2.legacy[0].id
  security_group_ids = [data.openstack_networking_secgroup_v2.agent_sg.id]

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.legacy[0].id
  }
}

resource "openstack_compute_instance_v2" "legacy_vm" {
  for_each    = local.agent_legacy_vms
  name        = "agent-${each.key}"
  image_id    = data.openstack_images_image_v2.agent_legacy_image[each.value.os_key].id
  flavor_name = var.flavor_agent
  key_pair    = var.keypair_name

  network {
    port = openstack_networking_port_v2.legacy_port[each.key].id
  }

  network {
    port = openstack_networking_port_v2.legacy_extra_port[each.key].id
  }

  # machine-id 재생성. (centos6는 systemd-machine-id-setup 부재 → 비치명적 실패, 무시)
  user_data = <<-EOF
    #cloud-config
    runcmd:
      - systemd-machine-id-setup --commit
  EOF
}
