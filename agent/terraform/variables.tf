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

# ── OS 8종 정의 ────────────────────────────────────────────────────
# 각 OS별 image_name·family·ssh_user·count를 한 곳에서 관리.
#
# family:
#   - debian/ubuntu : apt
#   - rhel          : dnf/yum (RHEL·Rocky·AlmaLinux·CentOS Stream)
#   - windows       : WinRM (Linux과 인증·통신 방식이 다름. playbook 미구현)
#
# image_name: openstack image list 로 확인 후 환경의 실제 이름으로 갱신.
# ssh_user: cloud image의 기본 계정 (cloud-init 표준).

variable "agent_os_map" {
  description = "OS별 image·family·count 정의. 키는 inventory group name으로도 사용됨."
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
    windows2022 = {
      image_name = "windows-server-2022_x64_uefi_40G"
      family     = "windows"
      ssh_user   = "Administrator"
      count      = 2
    }
  }
}
