# Windows agent VMs — boot-from-volume + cloudbase-init/WinRM.
# windows2022 ×7 (검증 플릿) + windows2008 ×1 (legacy 지원 확인, BIOS only).
# 활성화: terraform.tfvars에 windows_vm_enabled = true.
# 키(map) = inventory OS group 이름 = group_vars/<키>.yml 과 정렬.

variable "windows_vm_enabled" {
  description = "Windows agent VM 활성화 여부"
  type        = bool
  default     = false
}

variable "flavor_windows" {
  description = "Windows VM flavor (RAM 4GB 이상 권장)"
  type        = string
  default     = "c2_m4_r30"
}

variable "windows_admin_password" {
  description = "Administrator 초기 비밀번호 — cloudbase-init user_data로 주입"
  type        = string
  sensitive   = true
  default     = ""
}

variable "windows_os_map" {
  description = "Windows OS별 정의. legacy=true면 secondary NIC를 agent-legacy에 부착(agent_legacy_enabled 필요)."
  type = map(object({
    image_name  = string
    count       = number
    volume_size = optional(number, 50)
    legacy      = optional(bool, false)
  }))
  default = {
    windows2022 = {
      image_name = "win2022_x64_uefi_40G"
      count      = 7
    }
    windows2008 = {
      image_name  = "win2008_x64_bios_40G"
      count       = 1
      volume_size = 60
      legacy      = true
    }
  }
}

# ── VM 플랫 맵 (비활성 시 빈 맵 → 자원 0개) ───────────────────────
locals {
  windows_vms = var.windows_vm_enabled ? merge([
    for os_key, os in var.windows_os_map : {
      for i in range(os.count) :
      "${os_key}-${i + 1}" => {
        os_key      = os_key
        image_name  = os.image_name
        volume_size = os.volume_size
        legacy      = os.legacy
      }
    }
  ]...) : {}

  # 멀티 NIC(패턴 A) — agent_extra_networks를 모든 windows VM에 부착
  windows_extra_ports = merge([
    for vmk, vm in local.windows_vms : {
      for nick, net in var.agent_extra_networks :
      "${vmk}__${nick}" => { vm_key = vmk, nic = nick }
    }
  ]...)
}

# ── Data ──────────────────────────────────────────────────────────

data "openstack_images_image_v2" "windows_image" {
  for_each    = var.windows_vm_enabled ? var.windows_os_map : {}
  name        = each.value.image_name
  most_recent = true
}

# ── Cinder 부팅 볼륨 (VM당 1개) ────────────────────────────────────

resource "openstack_blockstorage_volume_v3" "win_boot" {
  for_each = local.windows_vms
  name     = "agent-${each.key}-boot"
  size     = each.value.volume_size
  image_id = data.openstack_images_image_v2.windows_image[each.value.os_key].id

  # 40~60GB Windows 이미지→볼륨 복사가 기본 timeout을 초과해 "context deadline exceeded" 발생.
  timeouts {
    create = "30m"
  }
}

# ── Ports ─────────────────────────────────────────────────────────

# primary NIC — agent-subnet (WinRM·bastion·MQ 경로)
resource "openstack_networking_port_v2" "win_port" {
  for_each           = local.windows_vms
  name               = "agent-${each.key}-port"
  network_id         = data.openstack_networking_network_v2.main.id
  security_group_ids = [data.openstack_networking_secgroup_v2.agent_sg.id]

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.agent.id
  }
}

# secondary NIC — agent_extra_networks (토폴로지 시각화). cloudbase-init이 자동 구성 안 할 수 있어
# 게스트 내 IP 설정은 별도(Ansible win 단계).
resource "openstack_networking_port_v2" "win_extra_port" {
  for_each           = local.windows_extra_ports
  name               = "agent-${each.value.vm_key}-${each.value.nic}-port"
  network_id         = data.openstack_networking_network_v2.extra[each.value.nic].id
  security_group_ids = [data.openstack_networking_secgroup_v2.agent_sg.id]

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.extra[each.value.nic].id
  }
}

# secondary NIC — agent-legacy (legacy=true VM만, ADR-0013 그룹핑). agent_legacy_enabled 선행 필요.
resource "openstack_networking_port_v2" "win_legacy_port" {
  for_each           = var.agent_legacy_enabled ? { for k, v in local.windows_vms : k => v if v.legacy } : {}
  name               = "agent-${each.key}-legacy-port"
  network_id         = data.openstack_networking_network_v2.legacy[0].id
  security_group_ids = [data.openstack_networking_secgroup_v2.agent_sg.id]

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.legacy[0].id
  }
}

# ── user_data (cloudbase-init) ────────────────────────────────────
# 주의: windows2008은 cloudbase-init/WinRM(PS 2.0) 미지원 가능 — 그 경우 WinRM 연결부터 실패(지원 확인 대상).
locals {
  win_user_data = join("\n", [
    "#ps1_sysnative",
    "net user Administrator \"${var.windows_admin_password}\"",
    "Enable-PSRemoting -Force -SkipNetworkProfileCheck",
    "winrm set winrm/config/service '@{AllowUnencrypted=\"true\"}'",
    "winrm set winrm/config/service/auth '@{Basic=\"true\"}'",
    "netsh advfirewall firewall add rule name=\"WinRM-HTTP-In-TCP\" protocol=TCP dir=in localport=5985 action=allow",
    # 이미지가 평가판(ServerStandardEval·TIMEBASED_EVAL)이라 만료 시 wlms.exe 가 ~1시간 주기로
    # 강제 셧다운한다(License Status=Notification). 폐쇄망이라 KMS/활성화 서버 도달 불가 →
    # 첫 부팅에 평가 타이머를 리셋한다(rearm 한도 6회). 재생성 VM의 즉시 셧다운 재발 방지.
    "cscript //nologo C:\\Windows\\System32\\slmgr.vbs /rearm",
  ])
}

# ── Instance ──────────────────────────────────────────────────────

resource "openstack_compute_instance_v2" "win_vm" {
  for_each    = local.windows_vms
  name        = "agent-${each.key}"
  flavor_name = var.flavor_windows
  key_pair    = var.keypair_name

  # primary NIC 먼저 → 관리 NIC. 이후 secondary NIC들.
  network {
    port = openstack_networking_port_v2.win_port[each.key].id
  }

  dynamic "network" {
    for_each = { for k, p in local.windows_extra_ports : k => p if p.vm_key == each.key }
    content {
      port = openstack_networking_port_v2.win_extra_port[network.key].id
    }
  }

  dynamic "network" {
    for_each = (each.value.legacy && var.agent_legacy_enabled) ? [1] : []
    content {
      port = openstack_networking_port_v2.win_legacy_port[each.key].id
    }
  }

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.win_boot[each.key].id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = true
  }

  user_data = local.win_user_data
}
