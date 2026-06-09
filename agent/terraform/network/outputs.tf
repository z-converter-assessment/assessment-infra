# 인스턴스 stack(agent/terraform)이 참조할 네트워크/서브넷 이름.
# agent_extra_networks 항목의 network_name/subnet_name과 매칭해 사용.
output "test_networks" {
  description = "생성된 테스트 네트워크 — 키별 network_name·subnet_name·cidr"
  value = {
    for k, n in openstack_networking_network_v2.test : k => {
      network_name = n.name
      subnet_name  = openstack_networking_subnet_v2.test[k].name
      cidr         = openstack_networking_subnet_v2.test[k].cidr
    }
  }
}
