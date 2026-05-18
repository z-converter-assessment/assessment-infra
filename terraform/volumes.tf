# ── Cinder 볼륨 ───────────────────────────────────────────────────

resource "openstack_blockstorage_volume_v3" "mq_data" {
  name = "mq-data"
  size = 20
}

resource "openstack_blockstorage_volume_v3" "db_data" {
  name = "db-data"
  size = 50
}

# ── 볼륨 attach ───────────────────────────────────────────────────
# /dev/vdb로 노출됨 — mount·mkfs는 이 단계에서 X (추후 Ansible)

resource "openstack_compute_volume_attach_v2" "mq_data_attach" {
  instance_id = openstack_compute_instance_v2.mq_vm.id
  volume_id   = openstack_blockstorage_volume_v3.mq_data.id
}

resource "openstack_compute_volume_attach_v2" "db_data_attach" {
  instance_id = openstack_compute_instance_v2.db_vm.id
  volume_id   = openstack_blockstorage_volume_v3.db_data.id
}
