# ── Cinder 볼륨 ───────────────────────────────────────────────────

resource "openstack_blockstorage_volume_v3" "db_data" {
  name = "db-data"
  size = 30
}

resource "openstack_blockstorage_volume_v3" "mq_data" {
  name = "mq-data"
  size = 20
}

# ── 볼륨 attach ───────────────────────────────────────────────────
# 두 볼륨 모두 engine-vm에 attach — 순서: db(/dev/vdb) → mq(/dev/vdc)
# mount·mkfs는 이 단계에서 X (Ansible engine_compose role이 담당)

resource "openstack_compute_volume_attach_v2" "db_data_attach" {
  instance_id = openstack_compute_instance_v2.engine_vm.id
  volume_id   = openstack_blockstorage_volume_v3.db_data.id
}

resource "openstack_compute_volume_attach_v2" "mq_data_attach" {
  instance_id = openstack_compute_instance_v2.engine_vm.id
  volume_id   = openstack_blockstorage_volume_v3.mq_data.id
  depends_on  = [openstack_compute_volume_attach_v2.db_data_attach]
}
