# Horizon 수동 생성 자원 참조 — 이 파일에서 자원을 생성하지 않음

data "openstack_networking_network_v2" "main" {
  name = var.network_name
}

data "openstack_networking_subnet_v2" "agent" {
  name = var.agent_subnet_name
}

data "openstack_networking_secgroup_v2" "bastion_sg" {
  name = var.bastion_sg_name
}

data "openstack_images_image_v2" "ubuntu24" {
  name        = var.image_name
  most_recent = true
}

# engine/terraform에서 생성된 agent-sg를 참조 — engine terraform을 먼저 apply해야 함
data "openstack_networking_secgroup_v2" "agent_sg" {
  name = "agent-sg"
}
