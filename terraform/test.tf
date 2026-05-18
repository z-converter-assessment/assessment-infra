data "openstack_compute_availablity_zones_v2" "zones" {}

output "connection_test_result"{
    description = "success to access with openstack, this is openstack_compute_availablity_zones"
    value = data.openstack_compute_availablity_zones_v2.zones.names
}