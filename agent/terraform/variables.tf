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
  description = "agent VM용 subnet 이름 (10.0.20.0/24) — primary NIC(eth0, bastion SSH·MQ 경로)"
  type        = string
}

# ── 멀티 NIC 추가 네트워크 (패턴 A) ────────────────────────────────
# 네트워크 시각화 기능 검증을 위해 각 agent를 여러 서브넷에 동시 소속시킨다.
# 네트워크·서브넷은 Horizon에서 사전 생성하고 이름으로 참조 — 레포 정책상 Terraform이
# network/subnet을 생성하지 않는다(data source 참조만).
# 모든 agent(Linux 전체 + 활성 시 Windows)에 일괄 부착된다.
# 키 = NIC 라벨(port 이름·output에 사용). 기본 {} → 비우면 기존 단일 NIC 동작 유지(무중단).
variable "agent_extra_networks" {
  description = "agent에 추가로 붙일 네트워크(멀티 NIC). 키=NIC 라벨, 값={network_name, subnet_name}"
  type = map(object({
    network_name = string
    subnet_name  = string
  }))
  default = {}
}

variable "bastion_sg_name" {
  description = "bastion VM에 적용된 SG 이름 — SSH source 허용용"
  type        = string
}

# ── keypair ────────────────────────────────────────────────────────

variable "keypair_name" {
  description = "Horizon에 이미 등록된 keypair 이름"
  type        = string
  default     = "engine-key"
}

# ── Agent flavor ───────────────────────────────────────────────────

variable "flavor_agent" {
  description = "Agent VM 공용 flavor (1 vCPU / 1 GB / 20 GB)"
  type        = string
}

# ── Linux OS 정의 ──────────────────────────────────────────────────
# 각 OS별 image_name·family·ssh_user·count를 한 곳에서 관리.
# Windows는 boot-from-volume·cloudbase-init이 필요해 별도 windows.tf에서 정의.
#
# family:
#   - debian/ubuntu : apt
#   - rhel          : dnf/yum (RHEL·Rocky·AlmaLinux·CentOS Stream)
#
# image_name: openstack image list 로 확인 후 환경의 실제 이름으로 갱신.
# ssh_user: cloud image의 기본 계정 (cloud-init 표준).

variable "agent_os_map" {
  description = "Linux OS별 image·family·count 정의. 키는 inventory group name으로도 사용됨."
  type = map(object({
    image_name = string
    family     = string
    ssh_user   = string
    count      = number
  }))

  default = {
    debian13 = {
      image_name = "debian13_x64_uefi_3G"
      family     = "debian"
      ssh_user   = "debian"
      count      = 4
    }
    debian12 = {
      image_name = "debian12_x64_uefi_3G"
      family     = "debian"
      ssh_user   = "debian"
      count      = 4
    }
    ubuntu2404 = {
      image_name = "ubuntu24.04_x64_uefi_3.5G"
      family     = "ubuntu"
      ssh_user   = "ubuntu"
      count      = 4
    }
    ubuntu2204 = {
      image_name = "ubuntu22.04_x64_uefi_3.5G"
      family     = "ubuntu"
      ssh_user   = "ubuntu"
      count      = 4
    }
    rocky9 = {
      image_name = "rocky9_x64_uefi_10G"
      family     = "rhel"
      ssh_user   = "rocky"
      count      = 4
    }
    alma9 = {
      image_name = "almalinux9_x64_uefi_10G"
      family     = "rhel"
      ssh_user   = "almalinux"
      count      = 4
    }
    centos9 = {
      image_name = "centos-stream9_x64_uefi_10G"
      family     = "rhel"
      ssh_user   = "cloud-user"
      count      = 4
    }
  }
}

# ── 레거시 OS (지원 검증 + agent 개발자 컴파일/실행 환경 제공) ──────
# primary NIC=agent-subnet(연결성), secondary NIC=agent-legacy(ADR-0013 그룹핑).
# agent-legacy 서브넷은 network stack(agent/terraform/network)이 선행 생성해야 함.
variable "agent_legacy_enabled" {
  description = "레거시 OS(centos6·ubuntu18 + win2008) 인스턴스 활성화. agent-legacy 서브넷 선행 필요"
  type        = bool
  default     = true
}

variable "agent_legacy_os_map" {
  description = "레거시 Linux OS 정의. 키=inventory OS group 이름. 각 1대."
  type = map(object({
    image_name = string
    family     = string
    ssh_user   = string
    count      = number
  }))
  default = {
    centos6 = {
      image_name = "centos6_x64_uefi_10G"
      family     = "rhel"
      ssh_user   = "centos"
      count      = 1
    }
    ubuntu18 = {
      image_name = "ubuntu18.04_x64_uefi_2.2G"
      family     = "ubuntu"
      ssh_user   = "ubuntu"
      count      = 1
    }
  }
}
