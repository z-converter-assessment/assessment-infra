output "agent_vm_ips" {
  description = "Agent VM 사설 IP 목록 — Ansible inventory 입력용"
  value       = [for port in openstack_networking_port_v2.agent_port : port.all_fixed_ips[0]]
}
