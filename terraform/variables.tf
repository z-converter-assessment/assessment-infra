variable "cloud_name" {
  description = "clouds.yaml의 cloud 이름"
  type        = string
  default     = "openstack"
}

# Horizon에서 수동 생성한 네트워크 자원 이름 (data source 참조용)
variable "network_name" {
  description = "Horizon에서 생성한 Neutron network 이름"
  type        = string
}

variable "engine_subnet_name" {
  description = "Horizon에서 생성한 engine-subnet 이름 (10.0.10.0/24)"
  type        = string
}

variable "agent_subnet_name" {
  description = "Horizon에서 생성한 agent-subnet 이름 (10.0.20.0/24)"
  type        = string
}

variable "external_network_name" {
  description = "Floating IP NAT용 외부 네트워크 이름"
  type        = string
}

variable "image_name" {
  description = "엔진·에이전트 VM 공용 OS 이미지 이름"
  type        = string
}

variable "flavor_api" {
  description = "API VM flavor (4 vCPU / 4 GB)"
  type        = string
}

variable "flavor_mq" {
  description = "MQ VM flavor (2 vCPU / 2 GB)"
  type        = string
}

variable "flavor_db" {
  description = "DB VM flavor (2 vCPU / 4 GB)"
  type        = string
}

variable "flavor_worker" {
  description = "Worker+Scheduler VM flavor (2 vCPU / 2 GB)"
  type        = string
}

variable "flavor_agent" {
  description = "Agent VM flavor (1 vCPU / 1 GB)"
  type        = string
}

variable "agent_count" {
  description = "Agent VM 대수"
  type        = number
  default     = 3
}

variable "keypair_name" {
  description = "OpenStack에 등록할 keypair 이름"
  type        = string
  default     = "IaC"
}

variable "public_key_path" {
  description = "등록할 SSH 공개키 경로"
  type        = string
  default     = "~/.ssh/IaC.pub"
}
