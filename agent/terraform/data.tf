# Horizon 수동 생성 자원 참조 — 이 파일에서 자원을 생성하지 않음

data "openstack_networking_network_v2" "main" {
  name = var.network_name
}

data "openstack_networking_subnet_v2" "agent" {
  name = var.agent_subnet_name
}

# 멀티 NIC용 추가 네트워크/서브넷 — 이름으로 참조 (var.agent_extra_networks).
# 생성 주체: Horizon 또는 network stack(ADR-0013). 어느 쪽이든 이름으로 data 참조.
data "openstack_networking_network_v2" "extra" {
  for_each = var.agent_extra_networks
  name     = each.value.network_name
}

data "openstack_networking_subnet_v2" "extra" {
  for_each = var.agent_extra_networks
  name     = each.value.subnet_name
}

data "openstack_networking_secgroup_v2" "bastion_sg" {
  name = var.bastion_sg_name
}

# engine/terraform에서 생성된 agent-sg를 참조 — engine terraform을 먼저 apply해야 함
data "openstack_networking_secgroup_v2" "agent_sg" {
  name = "agent-sg"
}

# OS별 이미지 data source — agent_os_map의 키별로 하나씩 lookup
data "openstack_images_image_v2" "agent_image" {
  for_each = var.agent_os_map

  name        = each.value.image_name
  most_recent = true
}

# ── 레거시 (ADR-0013) ──────────────────────────────────────────────
# agent-legacy 내부 서브넷 — network stack(agent/terraform/network)이 생성. 레거시 VM secondary NIC용.
data "openstack_networking_network_v2" "legacy" {
  count = var.agent_legacy_enabled ? 1 : 0
  name  = "agent-legacy"
}

data "openstack_networking_subnet_v2" "legacy" {
  count = var.agent_legacy_enabled ? 1 : 0
  name  = "agent-legacy-subnet"
}

# 레거시 Linux OS 이미지
data "openstack_images_image_v2" "agent_legacy_image" {
  for_each    = var.agent_legacy_enabled ? var.agent_legacy_os_map : {}
  name        = each.value.image_name
  most_recent = true
}
