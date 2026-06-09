variable "cloud_name" {
  description = "clouds.yaml의 cloud 이름"
  type        = string
  default     = "openstack"
}

# ADR-0013: 테스트 전용 내부 네트워크/서브넷 정의.
# 키 = 네트워크 이름(인스턴스 stack이 data로 이름 참조). 서브넷 이름 = "<키>-subnet".
# 외부 라우팅 없음(internal-only) — outbound는 인스턴스의 primary agent-subnet(Horizon)이 담당.
variable "test_networks" {
  description = "terraform이 생성할 내부 테스트 네트워크. 키=네트워크명, 값=서브넷 속성"
  type = map(object({
    cidr        = string
    gateway_ip  = optional(string)       # null이면 OpenStack 자동 할당. 라우팅 없으니 표식 수준
    enable_dhcp = optional(bool, true)
    dns         = optional(list(string), [])
  }))
  default = {}
}
