# ── Ports ─────────────────────────────────────────────────────────

resource "openstack_networking_port_v2" "agent_port" {
  count              = var.agent_count
  name               = "agent-vm-${count.index + 1}-port"
  network_id         = data.openstack_networking_network_v2.main.id
  security_group_ids = [data.openstack_networking_secgroup_v2.agent_sg.id]

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.agent.id
  }
}

# ── Instances ─────────────────────────────────────────────────────

resource "openstack_compute_instance_v2" "agent_vm" {
  count       = var.agent_count
  name        = "agent-vm-${count.index + 1}"
  image_id    = data.openstack_images_image_v2.ubuntu24.id
  flavor_name = var.flavor_agent
  key_pair    = var.keypair_name

  network {
    port = openstack_networking_port_v2.agent_port[count.index].id
  }

  user_data = <<-EOF
    #cloud-config
    runcmd:
      - systemd-machine-id-setup --commit
  EOF
}
