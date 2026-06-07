# Port를 먼저 생성해 engine-subnet 고정 + SG 바인딩 후 인스턴스에 attach
# security_group_ids는 port에만 설정 — instance.security_groups 중복 설정 X

# ── Ports ─────────────────────────────────────────────────────────

resource "openstack_networking_port_v2" "engine_port" {
  name               = "engine-vm-port"
  network_id         = data.openstack_networking_network_v2.main.id
  security_group_ids = [openstack_networking_secgroup_v2.engine_sg.id]

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.engine.id
  }
}

resource "openstack_networking_port_v2" "ai_port" {
  name               = "ai-vm-port"
  network_id         = data.openstack_networking_network_v2.main.id
  security_group_ids = [openstack_networking_secgroup_v2.ai_sg.id]

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.engine.id
  }
}

# ── Instances ─────────────────────────────────────────────────────

resource "openstack_compute_instance_v2" "engine_vm" {
  name        = "engine-vm"
  image_id    = data.openstack_images_image_v2.debian13.id
  flavor_name = var.flavor_engine
  key_pair    = var.keypair_name

  network {
    port = openstack_networking_port_v2.engine_port.id
  }
}

resource "openstack_compute_instance_v2" "ai_vm" {
  name        = "ai-vm"
  image_id    = data.openstack_images_image_v2.debian13.id
  flavor_name = var.flavor_ai
  key_pair    = var.keypair_name

  network {
    port = openstack_networking_port_v2.ai_port.id
  }
}
