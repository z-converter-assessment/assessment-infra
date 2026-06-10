# ── Security Groups ───────────────────────────────────────────────

resource "openstack_networking_secgroup_v2" "engine_sg" {
  name        = "engine-sg"
  description = "Engine VM — SSH/API/MQ(agent+ai)/RabbitMQ-mgmt from bastion, Postgres/Redis from ai"
}

resource "openstack_networking_secgroup_v2" "agent_sg" {
  name        = "agent-sg"
  description = "Agent VM — SSH from bastion, inbound from agent-subnet"
}

resource "openstack_networking_secgroup_v2" "ai_sg" {
  name        = "ai-sg"
  description = "AI VM — SSH from bastion, Ollama(11434) from engine"
}

# ── engine-sg ingress ─────────────────────────────────────────────

resource "openstack_networking_secgroup_rule_v2" "engine_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = data.openstack_networking_secgroup_v2.bastion_sg.id
  security_group_id = openstack_networking_secgroup_v2.engine_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "engine_8000" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8000
  port_range_max    = 8000
  remote_ip_prefix  = var.internal_cidr
  security_group_id = openstack_networking_secgroup_v2.engine_sg.id
}

# agent fleet → MQ (AMQP)
resource "openstack_networking_secgroup_rule_v2" "engine_5672_from_agent" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5672
  port_range_max    = 5672
  remote_group_id   = openstack_networking_secgroup_v2.agent_sg.id
  security_group_id = openstack_networking_secgroup_v2.engine_sg.id
}

# AI VM diagnostic worker → MQ / Postgres / Redis (compose 서비스들이 engine VM 호스트에 바인딩)
resource "openstack_networking_secgroup_rule_v2" "engine_5672_from_ai" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5672
  port_range_max    = 5672
  remote_group_id   = openstack_networking_secgroup_v2.ai_sg.id
  security_group_id = openstack_networking_secgroup_v2.engine_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "engine_5432_from_ai" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5432
  port_range_max    = 5432
  remote_group_id   = openstack_networking_secgroup_v2.ai_sg.id
  security_group_id = openstack_networking_secgroup_v2.engine_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "engine_6379_from_ai" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6379
  port_range_max    = 6379
  remote_group_id   = openstack_networking_secgroup_v2.ai_sg.id
  security_group_id = openstack_networking_secgroup_v2.engine_sg.id
}

# RabbitMQ Management UI — bastion에서 SSH 포트포워딩으로 접근
resource "openstack_networking_secgroup_rule_v2" "engine_15672_from_bastion" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 15672
  port_range_max    = 15672
  remote_group_id   = data.openstack_networking_secgroup_v2.bastion_sg.id
  security_group_id = openstack_networking_secgroup_v2.engine_sg.id
}

# pgAdmin UI (v0.5.0 base compose) — bastion에서 SSH 포트포워딩으로 접근
resource "openstack_networking_secgroup_rule_v2" "engine_5050_from_bastion" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5050
  port_range_max    = 5050
  remote_group_id   = data.openstack_networking_secgroup_v2.bastion_sg.id
  security_group_id = openstack_networking_secgroup_v2.engine_sg.id
}

# ── agent-sg ingress ──────────────────────────────────────────────

resource "openstack_networking_secgroup_rule_v2" "agent_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = data.openstack_networking_secgroup_v2.bastion_sg.id
  security_group_id = openstack_networking_secgroup_v2.agent_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "agent_all_from_agent_subnet" {
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = data.openstack_networking_subnet_v2.agent.cidr
  security_group_id = openstack_networking_secgroup_v2.agent_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "agent_winrm_from_bastion" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5985
  port_range_max    = 5985
  remote_group_id   = data.openstack_networking_secgroup_v2.bastion_sg.id
  security_group_id = openstack_networking_secgroup_v2.agent_sg.id
}

# ── ai-sg ingress ─────────────────────────────────────────────────

resource "openstack_networking_secgroup_rule_v2" "ai_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = data.openstack_networking_secgroup_v2.bastion_sg.id
  security_group_id = openstack_networking_secgroup_v2.ai_sg.id
}

# engine compose 서비스가 AI VM Ollama를 호출하는 경로용 (api 등)
resource "openstack_networking_secgroup_rule_v2" "ai_11434_from_engine" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 11434
  port_range_max    = 11434
  remote_group_id   = openstack_networking_secgroup_v2.engine_sg.id
  security_group_id = openstack_networking_secgroup_v2.ai_sg.id
}
