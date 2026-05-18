# ── api-vm Floating IP ────────────────────────────────────────────

resource "openstack_networking_floatingip_v2" "api_fip" {
  pool = var.external_network_name
}

resource "openstack_networking_floatingip_associate_v2" "api_fip_assoc" {
  floating_ip = openstack_networking_floatingip_v2.api_fip.address
  port_id     = openstack_networking_port_v2.api_port.id
}
