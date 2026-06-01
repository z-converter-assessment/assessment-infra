# Windows Server 2022 — boot-from-volume
# 이미지 크기(40GB)가 하이퍼바이저 로컬 디스크를 초과하므로 Cinder 볼륨 부팅.
# 활성화: terraform.tfvars에 windows_vm_enabled = true 설정.

variable "windows_vm_enabled" {
  description = "Windows Server 2022 agent VM 활성화 여부"
  type        = bool
  default     = false
}

variable "flavor_windows" {
  description = "Windows VM flavor (RAM 4GB 이상 권장)"
  type        = string
  default     = "c2_m4_r30"
}

variable "windows_image_name" {
  description = "Windows Server 2022 이미지명 (openstack image list 로 확인)"
  type        = string
  default     = "windows-server-2022_x64_uefi_40G"
}

variable "windows_admin_password" {
  description = "Administrator 초기 비밀번호 — cloudbase-init user_data로 주입"
  type        = string
  sensitive   = true
  default     = ""
}

# ── Data ──────────────────────────────────────────────────────────

data "openstack_images_image_v2" "win2022" {
  count       = var.windows_vm_enabled ? 1 : 0
  name        = var.windows_image_name
  most_recent = true
}

# ── Cinder 부팅 볼륨 ──────────────────────────────────────────────

resource "openstack_blockstorage_volume_v3" "win_boot" {
  count    = var.windows_vm_enabled ? 1 : 0
  name     = "agent-win2022-1-boot"
  size     = 50
  image_id = data.openstack_images_image_v2.win2022[0].id
}

# ── Port ──────────────────────────────────────────────────────────

resource "openstack_networking_port_v2" "win_port" {
  count              = var.windows_vm_enabled ? 1 : 0
  name               = "agent-win2022-1-port"
  network_id         = data.openstack_networking_network_v2.main.id
  security_group_ids = [data.openstack_networking_secgroup_v2.agent_sg.id]

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.agent.id
  }
}

# ── user_data (cloudbase-init) ────────────────────────────────────

locals {
  win_user_data = join("\n", [
    "#ps1_sysnative",
    "net user Administrator \"${var.windows_admin_password}\"",
    "Enable-PSRemoting -Force -SkipNetworkProfileCheck",
    "winrm set winrm/config/service '@{AllowUnencrypted=\"true\"}'",
    "winrm set winrm/config/service/auth '@{Basic=\"true\"}'",
    "netsh advfirewall firewall add rule name=\"WinRM-HTTP-In-TCP\" protocol=TCP dir=in localport=5985 action=allow",
  ])
}

# ── Instance ──────────────────────────────────────────────────────

resource "openstack_compute_instance_v2" "win_vm" {
  count       = var.windows_vm_enabled ? 1 : 0
  name        = "agent-win2022-1"
  flavor_name = var.flavor_windows
  key_pair    = var.keypair_name

  network {
    port = openstack_networking_port_v2.win_port[0].id
  }

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.win_boot[0].id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = true
  }

  user_data = local.win_user_data
}

# ── Output ────────────────────────────────────────────────────────

output "windows_vm" {
  description = "Windows Server 2022 VM 정보 (비활성화 시 null)"
  value = var.windows_vm_enabled ? {
    name     = "agent-win2022-1"
    ip       = try(openstack_networking_port_v2.win_port[0].all_fixed_ips[0], "")
    family   = "windows"
    ssh_user = "Administrator"
    os_key   = "windows2022"
  } : null
}
