variable "cloud_name" {
  description = "clouds.yaml의 cloud 이름"
  type        = string
  default     = "openstack"
}

# ── Horizon 수동 생성 자원 이름 (data source 참조용) ──────────────

variable "network_name" {
  description = "Horizon에서 생성한 Neutron network 이름"
  type        = string
}

variable "agent_subnet_name" {
  description = "agent VM용 subnet 이름 (10.0.20.0/24)"
  type        = string
}

variable "bastion_sg_name" {
  description = "bastion VM에 적용된 SG 이름 — SSH source 허용용"
  type        = string
}

# ── 이미지 · keypair ───────────────────────────────────────────────

variable "image_name" {
  description = "VM 공용 OS 이미지 이름"
  type        = string
  default     = "ubuntu24.04_x64_uefi_3.5G"
}

variable "keypair_name" {
  description = "Horizon에 이미 등록된 keypair 이름"
  type        = string
  default     = "engine-key"
}

# ── Flavor ────────────────────────────────────────────────────────

variable "flavor_agent" {
  description = "Agent VM flavor (1 vCPU / 1 GB)"
  type        = string
}

variable "agent_count" {
  description = "Agent VM 대수"
  type        = number
  default     = 3
}
