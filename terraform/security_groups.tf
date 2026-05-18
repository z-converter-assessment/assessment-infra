# ── Security Groups ───────────────────────────────────────────────

resource "openstack_networking_secgroup_v2" "api_sg" {
  name        = "api-sg"
  description = "API VM — SSH from bastion, 8000 from internal"
}

resource "openstack_networking_secgroup_v2" "mq_sg" {
  name        = "mq-sg"
  description = "MQ VM — SSH from bastion, AMQP/mgmt from api+worker"
}

resource "openstack_networking_secgroup_v2" "cache_sg" {
  name        = "cache-sg"
  description = "Cache VM — SSH from bastion, 6379 from api+worker"
}

resource "openstack_networking_secgroup_v2" "db_sg" {
  name        = "db-sg"
  description = "DB VM — SSH from bastion, 5432 from api+worker"
}

resource "openstack_networking_secgroup_v2" "worker_sg" {
  name        = "worker-sg"
  description = "Worker VM — SSH from bastion only"
}

# ── api-sg ingress ────────────────────────────────────────────────

resource "openstack_networking_secgroup_rule_v2" "api_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = data.openstack_networking_secgroup_v2.bastion_sg.id
  security_group_id = openstack_networking_secgroup_v2.api_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "api_8000" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8000
  port_range_max    = 8000
  remote_ip_prefix  = var.internal_cidr
  security_group_id = openstack_networking_secgroup_v2.api_sg.id
}

# ── mq-sg ingress ─────────────────────────────────────────────────

resource "openstack_networking_secgroup_rule_v2" "mq_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = data.openstack_networking_secgroup_v2.bastion_sg.id
  security_group_id = openstack_networking_secgroup_v2.mq_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "mq_5672_from_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5672
  port_range_max    = 5672
  remote_group_id   = openstack_networking_secgroup_v2.api_sg.id
  security_group_id = openstack_networking_secgroup_v2.mq_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "mq_5672_from_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5672
  port_range_max    = 5672
  remote_group_id   = openstack_networking_secgroup_v2.worker_sg.id
  security_group_id = openstack_networking_secgroup_v2.mq_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "mq_15672_from_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 15672
  port_range_max    = 15672
  remote_group_id   = openstack_networking_secgroup_v2.api_sg.id
  security_group_id = openstack_networking_secgroup_v2.mq_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "mq_15672_from_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 15672
  port_range_max    = 15672
  remote_group_id   = openstack_networking_secgroup_v2.worker_sg.id
  security_group_id = openstack_networking_secgroup_v2.mq_sg.id
}

# ── cache-sg ingress ──────────────────────────────────────────────

resource "openstack_networking_secgroup_rule_v2" "cache_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = data.openstack_networking_secgroup_v2.bastion_sg.id
  security_group_id = openstack_networking_secgroup_v2.cache_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "cache_6379_from_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6379
  port_range_max    = 6379
  remote_group_id   = openstack_networking_secgroup_v2.api_sg.id
  security_group_id = openstack_networking_secgroup_v2.cache_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "cache_6379_from_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6379
  port_range_max    = 6379
  remote_group_id   = openstack_networking_secgroup_v2.worker_sg.id
  security_group_id = openstack_networking_secgroup_v2.cache_sg.id
}

# ── db-sg ingress ─────────────────────────────────────────────────

resource "openstack_networking_secgroup_rule_v2" "db_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = data.openstack_networking_secgroup_v2.bastion_sg.id
  security_group_id = openstack_networking_secgroup_v2.db_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "db_5432_from_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5432
  port_range_max    = 5432
  remote_group_id   = openstack_networking_secgroup_v2.api_sg.id
  security_group_id = openstack_networking_secgroup_v2.db_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "db_5432_from_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5432
  port_range_max    = 5432
  remote_group_id   = openstack_networking_secgroup_v2.worker_sg.id
  security_group_id = openstack_networking_secgroup_v2.db_sg.id
}

# ── worker-sg ingress ─────────────────────────────────────────────

resource "openstack_networking_secgroup_rule_v2" "worker_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = data.openstack_networking_secgroup_v2.bastion_sg.id
  security_group_id = openstack_networking_secgroup_v2.worker_sg.id
}
