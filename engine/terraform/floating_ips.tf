# ── engine-vm Floating IP ──────────────────────────────────────────

resource "openstack_networking_floatingip_v2" "engine_fip" {
  pool = var.external_network_name
}

resource "openstack_networking_floatingip_associate_v2" "engine_fip_assoc" {
  floating_ip = openstack_networking_floatingip_v2.engine_fip.address
  port_id     = openstack_networking_port_v2.engine_port.id
}
