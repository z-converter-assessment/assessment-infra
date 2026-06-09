# ADR-0013: 테스트 전용 내부 네트워크/서브넷 생성.
# router/external gateway 미부착 = internal-only(격리). 토폴로지 시각화·레거시 그룹핑용.
# network/subnet은 이름으로 인스턴스 stack(agent/terraform)이 data 참조한다.

resource "openstack_networking_network_v2" "test" {
  for_each       = var.test_networks
  name           = each.key
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "test" {
  for_each    = var.test_networks
  name        = "${each.key}-subnet"
  network_id  = openstack_networking_network_v2.test[each.key].id
  cidr        = each.value.cidr
  ip_version  = 4
  enable_dhcp = each.value.enable_dhcp
  gateway_ip  = each.value.gateway_ip
  # internal-only — router_interface 없음(외부/서브넷 간 라우팅 미제공). 의도적.
  dns_nameservers = each.value.dns
}
