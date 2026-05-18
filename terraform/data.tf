# Horizon에서 수동 생성한 자원 참조 — 이 파일에서 자원을 생성하지 않음

data "openstack_networking_network_v2" "main" {
  name = var.network_name
}

data "openstack_networking_subnet_v2" "engine" {
  name = var.engine_subnet_name
}

data "openstack_networking_subnet_v2" "agent" {
  name = var.agent_subnet_name
}

data "openstack_networking_network_v2" "external" {
  name     = var.external_network_name
  external = true
}

data "openstack_images_image_v2" "debian12" {
  name        = var.image_name
  most_recent = true
}

data "openstack_networking_secgroup_v2" "bastion_sg" {
  name = var.bastion_sg_name
}
