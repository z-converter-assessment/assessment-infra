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
}

# ── Ports ─────────────────────────────────────────────────────────

resource "openstack_networking_port_v2" "agent_port" {
  for_each           = local.agent_vms
  name               = "agent-${each.key}-port"
  network_id         = data.openstack_networking_network_v2.main.id
  security_group_ids = [data.openstack_networking_secgroup_v2.agent_sg.id]

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.agent.id
  }
}

# ── Instances ─────────────────────────────────────────────────────

resource "openstack_compute_instance_v2" "agent_vm" {
  for_each    = local.agent_vms
  name        = "agent-${each.key}"
  image_id    = data.openstack_images_image_v2.agent_image[each.value.os_key].id
  flavor_name = var.flavor_agent
  key_pair    = var.keypair_name

  network {
    port = openstack_networking_port_v2.agent_port[each.key].id
  }

  # machine-id 재생성 (snapshot 복제 대비)
  user_data = <<-EOF
    #cloud-config
    runcmd:
      - systemd-machine-id-setup --commit
  EOF
}
