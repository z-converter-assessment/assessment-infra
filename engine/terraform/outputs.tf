# ── 사설 IP ───────────────────────────────────────────────────────

output "engine_vm_private_ip" {
  description = "engine-vm 사설 IP"
  value       = openstack_compute_instance_v2.engine_vm.access_ip_v4
}

output "ai_vm_private_ip" {
  description = "ai-vm 사설 IP"
  value       = openstack_compute_instance_v2.ai_vm.access_ip_v4
}

# ── Floating IP ───────────────────────────────────────────────────

output "engine_vm_fip" {
  description = "engine-vm Floating IP (사내망 접근용)"
  value       = openstack_networking_floatingip_v2.engine_fip.address
}

# ── Security Group ID (agent 레포에서 data source로 참조용) ──────────

output "agent_sg_id" {
  description = "agent-sg ID — agent 레포에서 data source openstack_networking_secgroup_v2로 참조"
  value       = openstack_networking_secgroup_v2.agent_sg.id
}

output "engine_vm_private_ip_for_agent" {
  description = "engine-vm 사설 IP — agent가 AMQP 연결할 브로커 주소 (MQ가 compose로 engine VM에 통합)"
  value       = openstack_compute_instance_v2.engine_vm.access_ip_v4
}
