terraform {
  required_version = ">= 1.5.0"

  # ADR-0013: 테스트 전용 내부 네트워크/서브넷 stack. agent 인스턴스 stack과 분리된 state로
  # 관리해 인스턴스 destroy/recreate가 네트워크를 삭제하지 않게 한다(워크스페이스 밖 고정경로).
  backend "local" {
    path = "/home/debian/.tfstate/agent-network/terraform.tfstate"
  }

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 2.1"
    }
  }
}
