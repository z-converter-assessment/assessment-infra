# ── 사설 IP ───────────────────────────────────────────────────────

output "api_vm_private_ip" {
  description = "api-vm 사설 IP"
  value       = openstack_compute_instance_v2.api_vm.access_ip_v4
}

output "mq_vm_private_ip" {
  description = "mq-vm 사설 IP"
  value       = openstack_compute_instance_v2.mq_vm.access_ip_v4
}

output "cache_vm_private_ip" {
  description = "cache-vm 사설 IP"
  value       = openstack_compute_instance_v2.cache_vm.access_ip_v4
}

output "db_vm_private_ip" {
  description = "db-vm 사설 IP"
  value       = openstack_compute_instance_v2.db_vm.access_ip_v4
}

output "worker_vm_private_ip" {
  description = "worker-vm 사설 IP"
  value       = openstack_compute_instance_v2.worker_vm.access_ip_v4
}

# ── Floating IP ───────────────────────────────────────────────────

output "api_vm_fip" {
  description = "api-vm Floating IP (사내망 접근용)"
  value       = openstack_networking_floatingip_v2.api_fip.address
}
