data "openstack_compute_availability_zones_v2" "zones" {}

output "connection_test_result" {
  description = "openstack availability zones — 인증 통과 확인용"
  value       = data.openstack_compute_availability_zones_v2.zones.names
}