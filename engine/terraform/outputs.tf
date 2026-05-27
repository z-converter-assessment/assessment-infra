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

output "consumer_vm_private_ip" {
  description = "consumer-vm 사설 IP"
  value       = openstack_compute_instance_v2.consumer_vm.access_ip_v4
}

output "ai_vm_private_ip" {
  description = "ai-vm 사설 IP"
  value       = openstack_compute_instance_v2.ai_vm.access_ip_v4
}

# ── Floating IP ───────────────────────────────────────────────────

output "api_vm_fip" {
  description = "api-vm Floating IP (사내망 접근용)"
  value       = openstack_networking_floatingip_v2.api_fip.address
}

# ── Security Group ID (agent 레포에서 data source로 참조용) ──────────

output "agent_sg_id" {
  description = "agent-sg ID — agent 레포에서 data source openstack_networking_secgroup_v2로 참조"
  value       = openstack_networking_secgroup_v2.agent_sg.id
}

output "mq_vm_private_ip_for_agent" {
  description = "mq-vm 사설 IP — agent가 AMQP 연결할 브로커 주소"
  value       = openstack_compute_instance_v2.mq_vm.access_ip_v4
}
