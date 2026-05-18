# Horizon에서 수동 생성한 네트워크 자원 참조 — 이 파일에서 자원을 생성하지 않음

data "openstack_networking_network_v2" "main" {
  name = var.network_name
}

data "openstack_networking_subnet_v2" "engine" {
  name = var.engine_subnet_name
}

data "openstack_networking_subnet_v2" "agent" {
  name = var.agent_subnet_name
}
