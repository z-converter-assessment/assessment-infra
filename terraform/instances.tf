# Port를 먼저 생성해 engine-subnet 고정 + SG 바인딩 후 인스턴스에 attach
# security_group_ids는 port에만 설정 — instance.security_groups 중복 설정 X

# ── Ports ─────────────────────────────────────────────────────────

resource "openstack_networking_port_v2" "api_port" {
  name               = "api-vm-port"
  network_id         = data.openstack_networking_network_v2.main.id
  security_group_ids = [openstack_networking_secgroup_v2.api_sg.id]

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.engine.id
  }
}

resource "openstack_networking_port_v2" "mq_port" {
  name               = "mq-vm-port"
  network_id         = data.openstack_networking_network_v2.main.id
  security_group_ids = [openstack_networking_secgroup_v2.mq_sg.id]

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.engine.id
  }
}

resource "openstack_networking_port_v2" "cache_port" {
  name               = "cache-vm-port"
  network_id         = data.openstack_networking_network_v2.main.id
  security_group_ids = [openstack_networking_secgroup_v2.cache_sg.id]

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.engine.id
  }
}

resource "openstack_networking_port_v2" "db_port" {
  name               = "db-vm-port"
  network_id         = data.openstack_networking_network_v2.main.id
  security_group_ids = [openstack_networking_secgroup_v2.db_sg.id]

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.engine.id
  }
}

resource "openstack_networking_port_v2" "worker_port" {
  name               = "worker-vm-port"
  network_id         = data.openstack_networking_network_v2.main.id
  security_group_ids = [openstack_networking_secgroup_v2.worker_sg.id]

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.engine.id
  }
}

# ── Instances ─────────────────────────────────────────────────────

resource "openstack_compute_instance_v2" "api_vm" {
  name        = "api-vm"
  image_id    = data.openstack_images_image_v2.debian12.id
  flavor_name = var.flavor_api
  key_pair    = var.keypair_name

  network {
    port = openstack_networking_port_v2.api_port.id
  }
}

resource "openstack_compute_instance_v2" "mq_vm" {
  name        = "mq-vm"
  image_id    = data.openstack_images_image_v2.debian12.id
  flavor_name = var.flavor_mq
  key_pair    = var.keypair_name

  network {
    port = openstack_networking_port_v2.mq_port.id
  }
}

resource "openstack_compute_instance_v2" "cache_vm" {
  name        = "cache-vm"
  image_id    = data.openstack_images_image_v2.debian12.id
  flavor_name = var.flavor_cache
  key_pair    = var.keypair_name

  network {
    port = openstack_networking_port_v2.cache_port.id
  }
}

resource "openstack_compute_instance_v2" "db_vm" {
  name        = "db-vm"
  image_id    = data.openstack_images_image_v2.debian12.id
  flavor_name = var.flavor_db
  key_pair    = var.keypair_name

  network {
    port = openstack_networking_port_v2.db_port.id
  }
}

resource "openstack_compute_instance_v2" "worker_vm" {
  name        = "worker-vm"
  image_id    = data.openstack_images_image_v2.debian12.id
  flavor_name = var.flavor_worker
  key_pair    = var.keypair_name

  network {
    port = openstack_networking_port_v2.worker_port.id
  }
}
