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

variable "engine_subnet_name" {
  description = "engine VM용 subnet 이름 (10.0.10.64/26)"
  type        = string
}

variable "agent_subnet_name" {
  description = "agent VM용 subnet 이름 (10.0.10.0/26)"
  type        = string
}

variable "external_network_name" {
  description = "Floating IP 발급용 외부 네트워크 이름 — openstack network list --external 로 확인"
  type        = string
}

variable "bastion_sg_name" {
  description = "기존 bastion VM에 적용된 SG 이름 — SSH source 허용용"
  type        = string
}

variable "internal_cidr" {
  description = "사내망 CIDR — engine-vm 8000 포트 ingress 허용 범위 (폐쇄망이면 0.0.0.0/0 유지)"
  type        = string
  default     = "0.0.0.0/0"
}

# ── 이미지 · keypair ───────────────────────────────────────────────

variable "image_name" {
  description = "VM 공용 OS 이미지 이름"
  type        = string
  default     = "debian13_x64_uefi_3G"
}

variable "keypair_name" {
  description = "Horizon에 이미 등록된 keypair 이름"
  type        = string
  default     = "engine-key"
}

# ── Flavor ────────────────────────────────────────────────────────

variable "flavor_engine" {
  description = "Engine VM flavor — api·consumer·postgres·rabbitmq·redis 전체 호스트 (최소 4 vCPU / 8 GB 권장)"
  type        = string
}

variable "flavor_ai" {
  description = "AI VM flavor — Ollama 최경량 모델 (~3B Q4 ≈ 2 GB) + OS 여유. ZDM 플레이버 (4 vCPU / 8 GB / 100 GB disk)"
  type        = string
}
